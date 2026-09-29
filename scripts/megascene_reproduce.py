"""Restore an archived Megascene static/localized attempt and replay its saved inputs."""
import argparse
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import uuid

from megascene_inventory import SCHEMA, integer, outcome, read_json, require


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError(message)


def options(argv):
    parser = Parser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--reproduce-from", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--additional-allowance")
    args, other = parser.parse_known_args(argv)
    names = [word.split("=", 1)[0] for word in argv if word.startswith("--")]
    return args, other, names


def safe_path(root, name):
    path = PurePosixPath(name)
    require(isinstance(name, str) and name == path.as_posix() and not path.is_absolute() and
            path.parts and all(part not in (".", "..") for part in path.parts), "unsafe archived artifact path")
    target = root.joinpath(*path.parts)
    require(not any(parent.is_symlink() for parent in (target, *target.parents) if parent != root.parent),
            "symlink in archived artifact path")
    return target


def verified_file(source, item):
    path = safe_path(source, item["path"])
    require(path.is_file() and not path.is_symlink(), "missing archived artifact: "+item["path"])
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b""):
            digest.update(chunk)
            size += len(chunk)
    require(digest.hexdigest() == item["sha256"] and str(size) == item["size_bytes"],
            "tampered archived artifact: "+item["path"])
    return path


def retain_file(source, destination, item):
    original = verified_file(source, item)
    target = safe_path(destination, item["path"])
    target.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation preserves any partial interrupted write as evidence.
    with original.open("rb") as src, target.open("xb") as dst:
        shutil.copyfileobj(src, dst, 1024*1024)
        dst.flush()
        os.fsync(dst.fileno())
    shutil.copymode(original, target)
    verified_file(destination, item)
    descriptor = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def source_bundle(source, original):
    from megascene_checkpoints import verify_evidence
    require(original["schema"] == SCHEMA and original["record_type"] == "manifest" and
            original.get("synthetic") is False, "real archived manifest required")
    require(original.get("attempt_kind") == "development_observation", "timed source attempt required")
    require(original["effective"]["case"] in ("static", "localized"),
            "reproduction currently supports static and localized attempts")
    require(original["reproduction"]["archive"] == str(source) and
            original["reproduction"]["status"] == "runtime_archived_before_execution",
            "manifest does not identify this durable archive")
    require(not any(part in ("build", "dist", "tmp") for part in source.parts),
            "source remains in disposable output")
    items = original["artifacts"]
    paths = [item["path"] for item in items]
    require(len(paths) == len(set(paths)), "duplicate archived artifact identity")
    for name in paths:
        safe_path(source, name)
    required = {"runtime/worker", "runtime/reference-worker", "runtime/build/libvoxel_vulkan.so",
                "runtime/build/vulkan-scene.vert.spv", "runtime/build/vulkan-scene.frag.spv",
                "runtime/build/vulkan-shadow.vert.spv", "runtime/src/megascene_entry.bend",
                "runtime/megascene_recipe.py", "runtime/megascene_static.py", "inputs.json", "schedule.json"}
    if original["effective"]["case"] == "localized":
        required |= {"camera.bin", "runtime/edit-reference-worker"}
    require(required <= set(paths), "incomplete archived runtime/generator/schedule artifacts")
    loader = PurePosixPath(original["worker_command"][0])
    require(loader.as_posix() in paths and loader.parent.as_posix() == "runtime/lib" and
            original["worker_command"] == [loader.as_posix(), "--library-path", "runtime/lib", "runtime/worker",
                                           "--gpu", "off", "--threads", original["effective"]["threads"]],
            "archived worker command changed")
    from megascene_checkpoints import applicable, identity
    source_identity = identity(original, source, original["effective"])
    config, env = original["effective"], original["worker_environment"]
    require(env["MEGASCENE_WARMUP"] == config["warmup"] and
            env["MEGASCENE_MEASURED"] == config["frames"] and
            env["MEGASCENE_GROUND"] == str(integer(config["envelope_side_m"])//2+8) and
            env["VOXEL_VULKAN_LIBRARY"] == "runtime/build/libvoxel_vulkan.so" and
            env["VOXEL_STRESS_PRESENT"] == "unpaced", "archived runtime environment/configuration mismatch")
    if config["case"] == "localized":
        require(env["MEGASCENE_CAMERA_FILE"] == "../camera.bin" and env["MEGASCENE_LOCALIZED"] == "1",
                "archived localized runtime environment mismatch")
    frozen = read_json((source/"schedule.json").read_text())
    require(frozen["schedule_id"] == original["effective"]["schedule"] and
            frozen["warmup_frames"] == original["effective"]["warmup"] and
            frozen["measured_frames"] == original["effective"]["frames"] and
            len(frozen["frames"]) == 1+integer(frozen["warmup_frames"])+integer(frozen["measured_frames"]),
            "frozen schedule/configuration mismatch")
    schedule_hash = hashlib.sha256((source/"schedule.json").read_bytes()).hexdigest()
    require(env["MEGASCENE_SCHEDULE_SHA256"] == schedule_hash,
            "worker schedule hash mismatch")
    inputs = read_json((source/"inputs.json").read_text())
    require(inputs["schema"] == SCHEMA and inputs["record_type"] == "generation_inputs", "invalid archived generation inputs")
    for key in ("preset", "seed", "side_m", "envelope_side_m", "control", "fragment_budget"):
        require(inputs["configuration"][key] == original["effective"][key], "archived input configuration mismatch: "+key)
    evidence = ("validation.json", "comparison.json", "inventory.json", "summary.json", "cpu.jsonl")
    if all((source/name).is_file() for name in evidence):
        verify_evidence(original, source, evidence)
        applicable(read_json((source/"validation.json").read_text()), source_identity)
    return items, evidence


def owners_from_inputs(path, source_inventory):
    from megascene_recipe import Box, Owner
    data = read_json(path.read_text())
    source_owners = source_inventory["owners"]
    require(len(data["owners"]) == len(source_owners), "archived source owner count mismatch")
    for i, (owner, source) in enumerate(zip(data["owners"], source_owners), 1):
        require(owner["id"] == source["id"] == str(i) and owner["role"] == source["role"],
                "archived source owner identity mismatch")
        require("neighborhood" not in owner or owner["neighborhood"] == source["neighborhood"],
                "archived source neighborhood mismatch")
    return [Owner(owner["role"], None if source["neighborhood"] is None else integer(source["neighborhood"]),
            [Box(tuple(integer(value, signed=True) for value in box["lo"]),
            tuple(integer(value, signed=True) for value in box["hi"]), integer(box["material"])) for box in owner["boxes"]])
            for owner, source in zip(data["owners"], source_owners)]


def inventory_state(value):
    return {key: item for key, item in value.items() if key not in
            ("requested_controls", "effective_controls", "production_evidence", "validation")}


def compare_source(archive):
    from megascene_checkpoints import mismatch, verify_evidence
    from megascene_static import read_stream
    source = archive/"source_evidence"
    prior = {name: read_json((source/name).read_text()) for name in
             ("manifest.json", "validation.json", "comparison.json", "inventory.json", "summary.json")}
    verify_evidence(prior["manifest.json"], source,
                    ("validation.json", "comparison.json", "inventory.json", "summary.json", "cpu.jsonl"))
    current = {name: read_json((archive/name).read_text()) for name in
               ("validation.json", "comparison.json", "inventory.json", "summary.json")}
    failures = []
    require(prior["validation.json"].get("status") == prior["comparison.json"].get("status") == "pass" and
            prior["summary.json"]["state_correctness"]["status"] == "pass" and
            prior["summary.json"]["schedule_completion"]["status"] == "pass", "source has no complete passing checkpoint baseline")
    for name, left, right in (
        ("initial_state", prior["validation.json"]["expected"], current["validation.json"]["expected"]),
        ("initial_work", prior["validation.json"]["actual_work"], current["validation.json"]["actual_work"]),
        ("initial_inventory", inventory_state(prior["inventory.json"]), inventory_state(current["inventory.json"])),
        ("validation_checkpoints", prior["validation.json"]["checkpoints"], current["validation.json"]["checkpoints"]),
        ("timed_checkpoints", prior["comparison.json"]["checkpoints"], current["comparison.json"]["checkpoints"]),
        ("timed_work", prior["comparison.json"]["actual_work"], current["comparison.json"]["actual_work"])):
        diff = mismatch(left, right, name)
        if diff:
            failures.append(diff)
    source_records, source_errors = read_stream(source/"cpu.jsonl", prior["manifest.json"]["attempt_id"])
    actual_records, actual_errors = read_stream(archive/"cpu.jsonl", read_json((archive/"manifest.json").read_text())["attempt_id"])
    require(not source_errors and not actual_errors, "damaged source or reproduction checkpoint stream: "+str(source_errors+actual_errors))
    original = {r["frame"]: r for r in source_records if r["record_type"] == "checkpoint"}
    reproduced = {r["frame"]: r for r in actual_records if r["record_type"] == "checkpoint"}
    for frame in sorted(original.keys() | reproduced.keys(), key=int):
        if frame not in original or frame not in reproduced:
            failures.append({"field": "checkpoint/"+frame, "missing": True})
        else:
            diff = mismatch(original[frame]["payload"], reproduced[frame]["payload"], "checkpoint/"+frame)
            if diff:
                failures.append(diff)
    return {"schema": SCHEMA, "record_type": "reproduction_comparison",
            "status": "fail" if failures else "pass", "failures": failures,
            "source_attempt_id": prior["manifest.json"]["attempt_id"],
            "validation_attempt_id": current["validation.json"]["attempt_id"],
            "checked_checkpoints": str(len(original)),
            "scope": "exact initial inventory, independent validation and timed canonical state/geometry; elapsed times excluded"}


def main(argv):
    from megascene import runtime_environment, snapshot
    from megascene_supervisor import Campaign
    from megascene_static import finish_archive
    output = archive = campaign = None
    attempt_id = str(uuid.uuid4())
    manifest = {"schema": SCHEMA, "record_type": "manifest", "attempt_kind": "reproduction",
                "synthetic": False, "attempt_id": attempt_id, "campaign_id": None, "series_id": str(uuid.uuid4()),
                "utc_start": datetime.now(timezone.utc).isoformat(), "requested": {"argv": argv},
                "effective": None, "runtime": runtime_environment(), "artifacts": [], "evidence": [], "capabilities": {},
                "extensions": {"phase": "recovery"}}
    try:
        args, other, names = options(argv)
        output = Path(args.output).expanduser().resolve()
        source = Path(args.reproduce_from).expanduser().resolve()
        archive_root = Path(args.archive).expanduser().resolve()
        require(not any(part in ("build", "dist", "tmp") for part in archive_root.parts),
                "archive must be outside disposable build/dist/tmp directories")
        require(all(a != b and a not in b.parents and b not in a.parents for a,b in
                    ((source, archive_root), (source, output), (output, archive_root))),
                "source, output and archive must be separate directory trees")
        output.mkdir(parents=True, exist_ok=False)
        snapshot(output/"manifest.json", manifest)
        campaign = Campaign(archive_root, integer(args.additional_allowance) if args.additional_allowance else 0)
        manifest["campaign_id"] = campaign.value["campaign_id"]
        archive = archive_root/manifest["campaign_id"]/manifest["series_id"]/attempt_id
        archive.mkdir(parents=True, exist_ok=False)
        manifest["reproduction"] = {"source_archive": str(source), "archive": str(archive),
                                    "status": "retrieval_pending"}
        snapshot(archive/"manifest.json", manifest)
        require(not other, "reproduction uses the archived configuration; changed options: "+" ".join(other))
        require(len(names) == len(set(names)), "duplicate options are rejected")
        original = read_json((source/"manifest.json").read_text())
        items, source_evidence = source_bundle(source, original)
        manifest["effective"] = {**original["effective"], "archive": str(archive_root),
                                 "validated": None, "runtime_from": None, "capture_opening": False}
        manifest["source"] = original["source"]
        manifest["build"] = original["build"]
        manifest["constants"] = original["constants"]
        manifest["numeric_admission"] = original["numeric_admission"]
        manifest["numeric_bounds"] = original["numeric_bounds"]
        manifest["worker_command"] = original["worker_command"]
        manifest["worker_environment"] = original["worker_environment"]
        manifest["runtime"].update(graphics_requirements=original["runtime"].get("graphics_requirements"),
                                   display=os.environ.get("DISPLAY"))
        manifest["reproduction"].update(source_attempt_id=original["attempt_id"],
                                        source_validation_attempt_id=None,
                                        source_environment=original["runtime"])
        snapshot(archive/"manifest.json", manifest)
        for item in items:
            retain_file(source, archive, item)
        manifest["artifacts"] = items
        from megascene_checkpoints import identity
        identity(manifest, archive, manifest["effective"])
        source_store = archive/"source_evidence"
        source_store.mkdir()
        shutil.copy2(source/"manifest.json", source_store/"manifest.json")
        for name in source_evidence:
            if (source/name).is_file():
                entry = next((item for item in original["evidence"] if item["path"] == name), None)
                require(entry is not None, "missing source evidence identity: "+name)
                retain_file(source, source_store, entry)
        if (source_store/"validation.json").is_file():
            manifest["reproduction"]["source_validation_attempt_id"] = read_json(
                (source_store/"validation.json").read_text()).get("attempt_id")
        manifest["reproduction"]["status"] = "restored_and_verified"
        snapshot(archive/"manifest.json", manifest)
        config = manifest["effective"]
        from megascene_validation import validate_or_reuse, compare_attempt
        from megascene_static import launch
        from megascene_inventory import inventory
        from megascene_report import report_bundle
        loader = Path(manifest["worker_command"][0]).name
        require((source_store/"inventory.json").is_file(), "archived inventory baseline unavailable")
        owners = owners_from_inputs(archive/"inputs.json", read_json((source_store/"inventory.json").read_text()))
        validation = validate_or_reuse(config, archive, manifest, loader, campaign, None, owners, manifest["numeric_bounds"])
        manifest["reproduction"]["validation_attempt_id"] = validation.get("attempt_id")
        require(validation["status"] == "pass", "restored validation failed; see validation.json")
        report, records = launch(config, archive, manifest, loader, campaign=campaign)
        manifest["execution_environment"] = {"loaded_host_artifacts": validation.get("loaded_host_artifacts"),
                                            "effective_render_settings": report.get("effective_render_settings"),
                                            "invocation": "invocation.json"}
        compare_attempt(config, archive, manifest, validation, report, records)
        achieved = inventory((archive/"stdout.log").read_text(), owners, config, manifest["numeric_bounds"])
        snapshot(archive/"inventory.json", achieved)
        report["initialization"] = outcome("pass", "saved source inputs match actual initial world", "initialization", ["inventory.json"])
        report["numeric_validity"] = manifest["numeric_admission"]
        try:
            comparison = compare_source(archive)
        except (ValueError, OSError, KeyError, TypeError) as exc:
            comparison = {"schema": SCHEMA, "record_type": "reproduction_comparison",
                          "status": "fail", "failures": [{"reason": str(exc)}],
                          "scope": "archived and reproduced canonical evidence"}
        snapshot(archive/"reproduction_comparison.json", comparison)
        report["reproduction"] = outcome(comparison["status"],
            "archived and reproduced inventories, actions and state/geometry checkpoints agree" if comparison["status"] == "pass" else
            "archived and reproduced canonical evidence differs", config["schedule"], ["reproduction_comparison.json"])
        snapshot(archive/"summary.json", report)
        report = report_bundle(archive)
        report["reproduction"] = outcome(comparison["status"] if
            report["state_correctness"]["status"] == report["schedule_completion"]["status"] == "pass" else "inconclusive",
            "exact archived checkpoint comparison" if comparison["status"] == "pass" else "checkpoint mismatch or incomplete replay",
            config["schedule"], ["reproduction_comparison.json"])
        snapshot(archive/"summary.json", report)
        manifest["reproduction"]["status"] = "complete" if report["reproduction"]["status"] == "pass" else "incomplete"
        manifest["extensions"]["phase"] = manifest["reproduction"]["status"]
        finish_archive(archive, output, manifest)
        if report["reproduction"]["status"] != "pass":
            print("reproduction did not match archived checkpoints; see reproduction_comparison.json", file=sys.stderr)
            return 2
        print("Reproduced archived "+config["case"]+" attempt: "+str(archive/"summary.json"))
        return 0
    except (ValueError, OSError, KeyError, TypeError, ImportError) as exc:
        reason = str(exc)
        if archive is not None:
            manifest["reproduction"]["status"] = "failed"
            manifest["extensions"]["phase"] = "failed"
            prior = read_json((archive/"summary.json").read_text()) if (archive/"summary.json").is_file() else None
            report = prior or {"schema": SCHEMA, "record_type": "summary", "attempt_id": attempt_id,
                               "attempt_kind": "reproduction", "synthetic": False}
            report["reproduction"] = report.get("reproduction") or outcome("fail", reason, "archived runtime retrieval/replay",
                                                                           ["manifest.json", "reproduction_comparison.json"])
            report.setdefault("schedule_completion", outcome("inconclusive", reason, "replay"))
            report.setdefault("state_correctness", outcome("inconclusive", reason, "replay"))
            report.setdefault("completed_prefix", {"startup": False, "warmup": "0", "measured": "0"})
            report.setdefault("termination", {"cause": "recovery_failure", "reason": reason,
                                              "exit_code": None, "signal": None})
            snapshot(archive/"summary.json", report)
            finish_archive(archive, output, manifest)
        elif output is not None and output.is_dir():
            snapshot(output/"manifest.json", manifest)
            snapshot(output/"summary.json", {"schema": SCHEMA, "record_type": "summary",
                     "attempt_id": attempt_id, "attempt_kind": "reproduction", "synthetic": False,
                     "reproduction": outcome("fail", reason, "archive admission")})
        print(reason, file=sys.stderr)
        return 2
    finally:
        if campaign is not None:
            if not any(item["attempt_id"] == attempt_id for item in campaign.value["attempts"]):
                summary = archive/"summary.json" if archive is not None else output/"summary.json"
                campaign.attempt(attempt_id, summary, manifest.get("reproduction", {}).get("status", "failed"))
            campaign.close(manifest.get("reproduction", {}).get("status") == "complete")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
