#!/usr/bin/env python3
"""Separate Megascene admission and bounded Vulkan replay entry point."""

import argparse
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

from megascene_recipe import admit_sources, bend_program, generate
from megascene_inventory import (SCHEMA, canonical, integer, inventory, measurement,
                                 outcome, require)

ROOT = Path(__file__).resolve().parents[1]


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError(message)


def parser():
    p = Parser(description=__doc__, allow_abbrev=False)
    p.add_argument("--output", required=True, help="new directory for the local evidence bundle")
    p.add_argument("--case", default="admission")
    p.add_argument("--campaign", help="persistent campaign archive root; static defaults to --archive")
    p.add_argument("--additional-allowance", help="explicit additional seconds for an existing interrupted/exhausted campaign")
    p.add_argument("--preset", choices=("small", "large"))
    p.add_argument("--side-m", help="fixed district side: 64 or 128")
    p.add_argument("--seed", default="45")
    p.add_argument("--threads", default="6")
    p.add_argument("--fragment-budget", default="2048")
    p.add_argument("--capture-opening", action="store_true", help="separate opening capture after static observation")
    p.add_argument("--validation-only", action="store_true", help="build and validate a complete replay without a timed attempt")
    p.add_argument("--validated", help="reuse an identical successful archived validation")
    p.add_argument("--runtime-from", help="reuse archived runtime bytes, then validate this thread configuration separately")
    p.add_argument("--deadline", help="bounded replay deadline in seconds (default 300)")
    # Settings are admitted per capability; no silent fallback workload.
    for name in ("diagnostic", "resolution", "profile", "schedule", "frames", "warmup",
                 "archive", "calibration", "search"):
        p.add_argument("--" + name)
    return p


def configuration(args):
    require(args.case in ("admission", "static", "traversal", "picking", "localized", "support", "history"), "unsupported Megascene case")
    require(args.additional_allowance is None or args.campaign or args.archive, "additional allowance requires a campaign archive")
    if args.additional_allowance is not None:
        require(1 <= integer(args.additional_allowance) <= 86400, "additional allowance must be 1..86400 seconds")
    if args.case in ("static", "traversal", "picking", "localized", "support", "history") and args.campaign:
        require(Path(args.campaign).expanduser().resolve() == Path(args.archive or "").expanduser().resolve(), "static campaign must use its archive root")
    if args.case == "admission":
        require(not args.validation_only and args.validated is None and args.runtime_from is None, "validation options require --case static")
        require(not args.capture_opening and args.deadline is None, "capture/deadline require --case static")
        for name in ("diagnostic", "resolution", "profile", "schedule", "frames", "warmup", "archive", "calibration", "search"):
            require(getattr(args, name) is None, f"--{name} requires --case static or a later capability; request rejected")
    seed, threads, budget = map(integer, (args.seed, args.threads, args.fragment_budget))
    require(seed in (45, 46), "supported seeds are 45 and 46")
    require(threads in (1, 6, 12), "supported thread counts are 1, 6 and 12")
    require(budget <= 2**32-1, "fragment budget exceeds U32")
    side = integer(args.side_m) if args.side_m is not None else None
    require(side in (None, 64, 128), "supported district sides are 64 and 128 metres")
    preset = args.preset or ("large" if side == 128 else "small")
    require(side is None or side == (64 if preset == "small" else 128), "contradictory preset and side")
    config = {"case": args.case, "preset": preset, "side_m": str(64 if preset == "small" else 128),
            "seed": str(seed), "threads": str(threads), "fragment_budget": str(budget)}
    if args.case in ("static", "traversal", "picking", "localized", "support", "history"):
        from megascene_static import settings
        return settings(args, config)
    return config


def snapshot(path, value):
    # Snapshots are atomic; a failed worker cannot leave a success-shaped prefix.
    data = canonical(value) + b"\n"
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as f:
        temporary = Path(f.name)
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    try:
        os.replace(temporary, path)
        descriptor = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    finally:
        temporary.unlink(missing_ok=True)


def artifact(path, root):
    return {"path": path.relative_to(root).as_posix(),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "size_bytes": str(path.stat().st_size)}


def run(command, cwd, stdout, stderr, timeout):
    environment = dict(os.environ)
    for name in ("LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT"):
        environment.pop(name, None)
    from megascene_supervisor import active_campaign
    if active_campaign is not None:
        require(active_campaign.remaining_ns() > 0, "campaign allowance exhausted")
        timeout = min(timeout, active_campaign.remaining_ns()/1e9)
    with stdout.open("w") as out, stderr.open("w") as err:
        result = subprocess.run(command, cwd=cwd, stdout=out, stderr=err, env=environment,
                                timeout=timeout, check=False)
    require(result.returncode == 0, f"{Path(command[0]).name} exited {result.returncode}; see {stderr.name}")


def provenance():
    def git(*args):
        return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    return {"revision": git("rev-parse", "HEAD"), "dirty": bool(git("status", "--porcelain")),
            "scope": "repository state at admission; retained source bytes identify this build"}


def runtime_environment():
    model = platform.processor()
    try:
        model = next((line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
                      if line.startswith("model name")), model)
    except OSError:
        pass
    count = os.cpu_count()
    return {"os": platform.platform(), "machine": platform.machine(), "python": platform.python_version(),
            "cpu_model": model or None, "cpu_model_status": "measured" if model else "unsupported",
            "cpu_model_reason": "host CPU identification" if model else "CPU model unavailable",
            "logical_cpus": measurement("measured", "host logical CPUs", "host", "threads", str(count)) if count is not None
                            else measurement("unsupported", "CPU count unavailable", "host", "threads")}


def summary(status, reason):
    missing = outcome("inconclusive", "not executed by admission-only entry point", "Vulkan attempt")
    return {"schema": SCHEMA, "record_type": "summary", "attempt_kind": "admission",
            "admission": outcome(status, reason, "fixed-preset initialization", ["manifest.json"]),
            "state_correctness": outcome("pass" if status == "pass" else "inconclusive", reason,
                                         "initialization only", ["validation.json"] if status == "pass" else []),
            "numeric_validity": outcome("pass" if status == "pass" else "inconclusive", reason, "initial construction only"),
            **{name: dict(missing) for name in ("rendering_correctness", "visual_quality", "schedule_completion",
                                               "population_qualification", "calibration", "responsiveness")},
            "measurement_availability": measurement("not_executed", "no timed/rendered attempt", "Vulkan attempt", "ns"),
            "qualified_capacity": outcome("inconclusive", "admission cannot qualify capacity", "Vulkan attempt"),
            "interactive_pass": outcome("inconclusive", "admission cannot qualify responsiveness", "Vulkan attempt"),
            "termination": {"cause": "admission_complete" if status == "pass" else "rejected_request",
                            "reason": reason},
            "limitations": ["Runtime/reference initialization evidence; no unsafe-dependent formal proof.",
                            "No replay, targets, rendering, GPU, resource monitoring or benchmark evidence.",
                            "Fixed presets only; no universal numeric envelope or capacity claim."]}


def execute(config, output, manifest):
    manifest["extensions"]["phase"] = "source_admission"
    owners = generate(config["preset"], int(config["seed"]))
    numeric = admit_sources(owners, int(config["side_m"])*5, int(config["fragment_budget"]))
    expected = "10503360" if config["preset"] == "small" else "42096576"
    require(numeric["cells"] == expected, "fixed recipe cell total mismatch")
    require(len(owners) == (21 if config["preset"] == "small" else 81), "fixed recipe owner count mismatch")
    manifest["numeric_admission"] = outcome("pass", "checked fixed-preset source arithmetic and geometry bounds",
                                            "initial construction only", ["inputs.json"])
    manifest["numeric_bounds"] = numeric
    manifest["extensions"]["phase"] = "build"
    snapshot(output / "manifest.json", manifest)
    source = {"schema": SCHEMA, "record_type": "generation_inputs", "configuration": config,
              "owners": [{"id": str(i), "role": owner.role,
                          "neighborhood": None if owner.neighborhood is None else str(owner.neighborhood),
                          "boxes": [b.record() for b in owner.boxes]} for i, owner in enumerate(owners, 1)]}
    snapshot(output / "inputs.json", source)
    runtime = output / "runtime"
    runtime.mkdir()
    (runtime / "src").mkdir()
    # Preserve the actual dependency closure. No native renderer is linked or
    # loaded by this worker. The generated C includes Bend's runtime and effects.
    for name in ("math", "spatial", "mesh", "world", "showcase", "atelier_assets", "material", "megascene"):
        shutil.copyfile(ROOT / f"src/{name}.bend", runtime / f"src/{name}.bend")
    for name in ("megascene.py", "megascene_recipe.py", "megascene_inventory.py"):
        shutil.copyfile(ROOT / "scripts" / name, runtime / name)
    (runtime / "input.bend").write_text(bend_program(owners, int(config["fragment_budget"])))
    version = subprocess.run(["bend", "version"], capture_output=True, text=True, check=True).stdout.strip()
    require(version == "bend 2.0.32", "Megascene is pinned to Bend 2.0.32")
    manifest["runtime"]["bend"] = version
    manifest["source"] = provenance()
    manifest["build"] = {"command": ["bend", "input.bend", "-o", "worker"],
                         "c_export_command": ["bend", "input.bend", "-o", "worker.c"],
                         "working_directory": "runtime"}
    run(["bend", "input.bend", "-o", "worker.c"], runtime,
        output / "c-build.stdout.log", output / "c-build.stderr.log", 120)
    run(["bend", "input.bend", "-o", "worker"], runtime,
        output / "build.stdout.log", output / "build.stderr.log", 120)
    # Keep loader/environment provenance separate from recoverable worker bytes.
    run(["ldd", "worker"], runtime, output / "dependencies.log", output / "dependencies.stderr.log", 10)
    libraries = runtime / "lib"
    libraries.mkdir()
    loader = None
    for name in re.findall(r"(/[^\s]+)", (output / "dependencies.log").read_text()):
        source_library = Path(name)
        saved_library = libraries / source_library.name
        if saved_library.exists():
            require(saved_library.read_bytes() == source_library.read_bytes(), "conflicting runtime library names")
        else:
            shutil.copy2(source_library, saved_library)
        if source_library.name.startswith("ld-linux"):
            loader = saved_library
    require(loader is not None, "unsupported native loader; admission currently requires Linux/glibc")
    manifest["artifacts"] = [artifact(p, output) for p in sorted(runtime.rglob("*")) if p.is_file()]
    manifest["artifacts"].append(artifact(output / "inputs.json", output))
    manifest["worker_command"] = [str(loader.relative_to(output)), "--library-path", "runtime/lib",
                                  "runtime/worker", "--threads", config["threads"]]
    manifest["extensions"]["phase"] = "construction"
    snapshot(output / "manifest.json", manifest)
    run([str(loader), "--library-path", str(libraries), str(runtime / "worker"), "--threads", config["threads"]], runtime,
        output / "stdout.log", output / "stderr.log", 120)
    manifest["extensions"]["phase"] = "inventory_validation"
    achieved = inventory((output / "stdout.log").read_text(), owners, config, numeric)
    # These raw records preserve per-body identity and cached geometry. They are
    # not yet schedule/state checkpoints under megascene-checkpoint/1.
    achieved["requested_controls"] = manifest["requested"]
    achieved["effective_controls"] = config
    achieved["production_evidence"] = artifact(output / "stdout.log", output)
    snapshot(output / "inventory.json", achieved)
    reference = artifact(runtime / "megascene_inventory.py", output)
    validation = {"schema": SCHEMA, "record_type": "validation", "scope": "initialization only",
                  "independent_reference": reference,
                  "initialization": outcome("pass", "actual trees, IDs, anchors, face coverage and vertices match",
                                            "fixed-preset initialization", ["inputs.json", "stdout.log", "inventory.json"]),
                  "source_checks": ["disjointness across owners", "positive-face connectivity", "protected anchors"],
                  "numeric_bounds": numeric,
                  "complete_replay": measurement("not_executed", "admission-only entry point", "replay", "frames"),
                  "reuse_eligibility": outcome("not_applicable", "initial admission cannot qualify a timed attempt",
                                               "Vulkan attempt"),
                  "production_evidence": artifact(output / "stdout.log", output)}
    snapshot(output / "validation.json", validation)
    manifest["admission"] = outcome("pass", "fixed district constructed and checked", "initialization only",
                                    ["inventory.json", "validation.json"])
    manifest["extensions"]["phase"] = "complete"
    manifest["evidence"] = [artifact(output / name, output) for name in
                            ("inventory.json", "validation.json", "stdout.log", "stderr.log")]
    snapshot(output / "manifest.json", manifest)
    report = summary("pass", "fixed district constructed and checked")
    report["attempt_id"] = manifest["attempt_id"]
    snapshot(output / "summary.json", report)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    output = None
    created_output = False
    campaign = None
    completed = False
    manifest = {"schema": SCHEMA, "record_type": "manifest", "attempt_kind": "admission", "synthetic": False,
                "attempt_id": str(uuid.uuid4()), "campaign_id": None, "series_id": None,
                "utc_start": datetime.now(timezone.utc).isoformat(),
                "requested": {"argv": argv}, "effective": None,
                "admission": outcome("inconclusive", "admission has not completed", "initialization"),
                "numeric_admission": outcome("inconclusive", "not checked yet", "initial construction"),
                "runtime": runtime_environment(),
                "clocks": {"supervisor": "python.monotonic_ns",
                           "resolution_ns": str(round(time.get_clock_info("monotonic").resolution * 1_000_000_000)),
                           "scope": "build/worker deadline only; not benchmark timing"},
                "capabilities": {name: measurement("not_executed", "admission-only worker", name, unit) for name, unit in
                                 (("vulkan", "frames"), ("gpu", "ns"), ("resources", "bytes"), ("replay", "frames"))},
                "reproduction": {"scope": "local admission bundle with worker, inputs and loaded libraries; requires compatible Linux kernel/CPU",
                                 "durable_campaign_archive": measurement("not_executed", "no retained campaign started", "campaign", "bytes")},
                "artifacts": [], "extensions": {"phase": "configuration"}}
    try:
        # Discover a unique destination even for malformed requests, so their
        # requested values and explicit rejection can be retained when possible.
        destinations = [argv[i+1] for i, a in enumerate(argv[:-1]) if a == "--output"]
        destinations += [a.split("=", 1)[1] for a in argv if a.startswith("--output=")]
        if len(destinations) == 1 and destinations[0] and not destinations[0].startswith("--"):
            output = Path(destinations[0]).expanduser().resolve()
            output.mkdir(parents=True, exist_ok=False)
            created_output = True
            snapshot(output / "manifest.json", manifest)
        options = [a.split("=", 1)[0] for a in argv if a.startswith("--")]
        require(len(options) == len(set(options)), "duplicate options are rejected")
        args = parser().parse_args(argv)
        manifest["requested"]["options"] = vars(args)
        config = configuration(args)
        manifest["effective"] = config
        require(output is not None, "a new --output directory is required")
        campaign_root = args.campaign or (args.archive if config["case"] in ("static", "traversal", "picking", "localized", "support", "history") else None)
        if campaign_root:
            import megascene_supervisor
            campaign = megascene_supervisor.Campaign(Path(campaign_root).expanduser().resolve(), integer(args.additional_allowance) if args.additional_allowance else 0)
            megascene_supervisor.active_campaign = campaign
            manifest["campaign_id"] = campaign.value["campaign_id"]
        if config["case"] in ("static", "traversal", "picking", "localized", "support", "history"):
            from megascene_static import execute as execute_static
            execute_static(config, output, manifest, campaign)
            print(f"Unqualified {config['case']} development observation: {output / 'summary.json'}")
        else:
            execute(config, output, manifest)
            print(f"Admitted {config['preset']} seed {config['seed']}: {output / 'inventory.json'}")
        completed = True
        return 0
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, TypeError, ImportError) as error:
        reason = str(error)
        if isinstance(manifest.get("effective"), dict) and manifest["effective"]["case"] in ("static", "traversal", "picking", "localized", "support", "history"):
            from megascene_static import report as static_report
            archive = manifest.get("reproduction", {}).get("archive")
            archived = Path(archive) if archive else None
            if archived and (archived/"summary.json").exists():
                for file in archived.rglob("*"):
                    if file.is_file() and "runtime" not in file.relative_to(archived).parts:
                        target = output/file.relative_to(archived)
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(file,target)
            elif created_output:
                report = static_report([], [reason], manifest["effective"], 2, "prelaunch_failure", 0, manifest["attempt_id"])
                report["numeric_validity"] = manifest["numeric_admission"]
                report["termination"] = {"cause": "campaign_deadline" if campaign is not None and not campaign.remaining_ns() else "prelaunch_failure", "exit_code": None, "signal": None, "reason": reason}
                if archived and archived.is_dir():
                    snapshot(archived/"manifest.json",manifest)
                    snapshot(archived/"summary.json",report)
                snapshot(output/"manifest.json",manifest)
                snapshot(output/"summary.json",report)
            print(reason, file=sys.stderr)
            return 2
        report = summary("fail", reason)
        # A build, process, or validation failure is not a rejected setting and
        # must not masquerade as an observed capacity limit.
        if manifest["effective"] is not None:
            report["termination"]["cause"] = "admission_failure"
        report["attempt_id"] = manifest["attempt_id"]
        if manifest["extensions"]["phase"] == "inventory_validation":
            report["state_correctness"] = outcome("fail", reason, "initialization only", ["stdout.log"])
        # A compiler/loader failure cannot undo numeric checks already completed.
        report["numeric_validity"] = manifest["numeric_admission"]
        manifest["admission"] = outcome("fail", reason, "initialization only")
        if created_output:
            snapshot(output / "manifest.json", manifest)
            snapshot(output / "summary.json", report)
        print(canonical(report).decode(), file=sys.stderr)
        return 2

    finally:
        if campaign is not None:
            # Build, validation, controls and failed attempts all share the lease.
            if manifest.get("effective", {}).get("case") == "admission":
                campaign.attempt(manifest["attempt_id"], output/"summary.json", "admission_complete" if completed else "admission_failure")
            elif not any(a['attempt_id'] == manifest['attempt_id'] for a in campaign.value['attempts']):
                cause = "prelaunch_failure"
                if (output/"summary.json").exists():
                    import json
                    cause = json.loads((output/"summary.json").read_text())["termination"]["cause"]
                campaign.attempt(manifest["attempt_id"], output/"summary.json", cause)
            campaign.close(completed)
            import megascene_supervisor
            megascene_supervisor.active_campaign = None


if __name__ == "__main__":
    sys.exit(main())
