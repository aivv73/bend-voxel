"""Static validation orchestration; separate processes and retained failure data."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import time
import uuid

from megascene_checkpoints import applicable, audit, identity, initial_payload, mismatch, verify_evidence
from megascene_inventory import SCHEMA, inventory, outcome, read_json, require


def render_identity(records):
    ignored = {"schema", "record_type", "campaign_id", "series_id", "attempt_id", "sequence", "clock_id", "time_ns", "frame"}
    return [{k:v for k,v in r.items() if k not in ignored} for r in records if r["record_type"] in ("render_settings", "palette")]


def host_artifacts(invocation, archive):
    """Bind reuse to the actually sampled host loader/graphics libraries too."""
    result = {}
    for name in invocation["loaded_objects"]:
        path = Path(name)
        if archive in path.parents or ".so" not in path.name:
            continue
        require(path.is_file(), "loaded host artifact unavailable: "+name)
        result[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    require(result, "loaded host artifact evidence unavailable")
    return result


def verify_host_artifacts(validation):
    for name, expected in validation["loaded_host_artifacts"].items():
        require(Path(name).is_file() and hashlib.sha256(Path(name).read_bytes()).hexdigest() == expected,
                "stale loaded host artifact: "+name)


def validate_or_reuse(config, archive, manifest, loader, campaign, source, owners, bounds):
    from megascene import run, snapshot
    from megascene_static import launch
    from megascene_references import check
    started = time.monotonic_ns()
    value = {"schema": SCHEMA, "record_type": "validation", "synthetic": False,
             "status": "fail", "attempt_id": None, "reused": False,
             "scope": "complete declared "+config["case"]+" schedule; independent dense fixtures and sparse/runtime/native checks",
             "failures": [], "checked_frames": "0"}
    try:
        actual_identity = identity(manifest, archive, config)
        value["identity"] = actual_identity
        if config.get("validated"):
            original = read_json((source/"manifest.json").read_text())
            # Validate retained evidence bytes as well as runtime identities. A
            # successful flag in an edited/incomplete file is insufficient.
            required = {"validation.json"} | {"validation/"+name for name in (
                "manifest.json", "summary.json", "cpu.jsonl", "gpu.jsonl", "stdout.log", "stderr.log", "reference.stdout.log",
                "reference.stderr.log", "comparison.json", "inventory.json", "invocation.json", "supervision.json",
                "resources.jsonl", "heaps.jsonl", "allocations.jsonl", "reference.jsonl", "reference.shared")}
            required |= {a["path"] for a in original["evidence"] if a["path"].startswith("validation/")}
            verify_evidence(original, source, required)
            previous = read_json((source/"validation.json").read_text())
            applicable(previous, actual_identity)
            verify_host_artifacts(previous)
            value = {**previous, "reused": True, "source": str(source), "reuse_verification_ns": str(time.monotonic_ns()-started)}
            shutil.copytree(source/"validation", archive/"validation")
            return value
        destination = archive/"validation"
        destination.mkdir()
        validation_manifest = {**manifest, "attempt_id": str(uuid.uuid4()), "attempt_kind": "validation_replay"}
        validation_manifest["artifacts"] = [{**entry, "path": "../"+entry["path"]} for entry in manifest["artifacts"]]
        value["attempt_id"] = validation_manifest["attempt_id"]
        snapshot(destination/"manifest.json", validation_manifest)
        reference_start = time.monotonic_ns()
        run([str(archive/f"runtime/lib/{loader}"), "--library-path", str(archive/"runtime/lib"),
             str(archive/"runtime/reference-worker"), "--gpu", "off", "--threads", config["threads"]],
            archive/"runtime", destination/"reference.stdout.log", destination/"reference.stderr.log", 30)
        value["independent_references"] = check((destination/"reference.stdout.log").read_text())
        value["independent_references"]["duration_ns"] = str(time.monotonic_ns()-reference_start)
        summary, records = launch(config, archive, validation_manifest, loader, campaign=campaign, validation=True)
        summary["attempt_kind"] = "validation_replay"
        frozen = read_json((archive/"schedule.json").read_text())
        text = (destination/"stdout.log").read_text()
        achieved = inventory(text, owners, config, bounds)
        snapshot(destination/"inventory.json", achieved)
        expected, work = initial_payload(text, frozen, manifest["worker_environment"]["MEGASCENE_SCHEDULE_SHA256"], config)
        result = audit(records, frozen, expected, work, summary["schedule_completion"]["status"] == "pass", thorough=True)
        require(not result["synthetic"], "synthetic replay cannot validate a real configuration")
        snapshot(destination/"comparison.json", result)
        value["loaded_host_artifacts"] = host_artifacts(read_json((destination/"invocation.json").read_text()), archive)
        value.update(status=result["status"], checked_frames=result["checked_frames"], native_frames=result["native_frames"],
                     failures=result["failures"], checkpoints=result["checkpoints"], expected=expected, actual_work=work,
                     effective_render_identity=render_identity(records), numeric_evidence=bounds,
                     invariant_coverage=["tree_bounds_and_counts", "six_neighbor_connectivity", "protected_anchors",
                        "source_ownership", "material_conservation", "finite_motion_bits", "drawable_coverage_and_winding",
                        "fresh_bend_native_transport", "native_mesh_slots_and_draw_ranges", "unculled_triangle_visibility",
                        "full_proxy_shadow_cache_transitions"])
        summary["state_correctness"] = outcome(value["status"], "independent initial references and every-frame sparse checks", "complete declared "+config["case"]+" schedule", ["comparison.json"])
        snapshot(destination/"summary.json", summary)
        # No artifact is permitted to change during validation.
        require(identity(manifest, archive, config) == actual_identity, "artifacts changed during validation")
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as exc:
        value["status"] = "fail"
        value["failures"].append({"reason": str(exc)})
    value["duration_ns"] = str(time.monotonic_ns()-started)
    snapshot(archive/"validation.json", value)
    return value


def compare_attempt(config, archive, manifest, validation, summary, records):
    from megascene import snapshot
    failures = []
    try:
        applicable(validation, identity(manifest, archive, config))
        verify_host_artifacts(validation)
        actual_host = host_artifacts(read_json((archive/"invocation.json").read_text()), archive)
        require(actual_host == validation["loaded_host_artifacts"], "loaded host artifacts differ from validation")
        frozen = read_json((archive/"schedule.json").read_text())
        result = audit(records, frozen, validation["expected"], validation["actual_work"],
                       summary["schedule_completion"]["status"] == "pass")
        require(not result["synthetic"], "synthetic checkpoints cannot qualify a real attempt")
        diff = mismatch(validation["effective_render_identity"], render_identity(records), "effective_render_settings")
        if diff:
            result["failures"].append(diff)
            result["status"] = "fail"
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as exc:
        failures.append({"reason": str(exc)})
        result = {"schema": SCHEMA, "record_type": "checkpoint_comparison", "status": "fail", "failures": failures}
    snapshot(archive/"comparison.json", result)
    summary["validation"] = {"path": "validation.json", "attempt_id": validation["attempt_id"],
                             "reused": validation["reused"], "duration_ns": validation.get("duration_ns")}
    summary["state_correctness"] = outcome(result["status"], "exact required checkpoints agree with separately validated configuration" if result["status"] == "pass" else "checkpoint/validation mismatch",
        "complete declared "+config["case"]+" schedule", ["validation.json", "comparison.json", "cpu.jsonl"])
    summary["rendering_correctness"] = outcome(result["status"], "drawable geometry, native cache and unculled visibility checks" if result["status"] == "pass" else "geometry/native evidence incomplete or mismatched",
        config["case"]+" geometry/cache/visibility; visual quality remains separate", ["validation.json", "comparison.json"])
    # Correctness never promotes calibration, visual quality, performance,
    # capacity qualification, or the parent feature's implementation acceptance.
    snapshot(archive/"summary.json", summary)
