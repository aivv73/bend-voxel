import argparse
import gzip
from hashlib import sha256
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "scripts"), str(ROOT / "tests")]
import megascene_bend
from megascene_report import classify
from megascene_static import schedule
from test_megascene_report import fixture


def workload(case, frozen):
    source = fixture(case)
    source["manifest"]["effective"].update(side_m="64", warmup="120", frames="21600",
                                            schedule=case + "-perf-v2")
    source["schedule"] = frozen
    source["calibration"] = None
    cpu, reference, current = [], [], 0
    actions = {int(action["frame"]): action for action in frozen["actions"]}
    for index, planned in enumerate(frozen["frames"]):
        population = planned["phase"]
        duration = 1 if index <= 120 else 80_000_000 if population == "edit" else 500_000
        if index in actions:
            action = actions[index]["action"]
            cpu.append({"record_type": "action", "frame": str(index), "action": action, "accepted": True})
            reference.append({"record_type": "action", "action": action})
            cpu.append({"record_type": "edit", "frame": str(index), "action": action, "accepted": True,
                        "begin_ns": str(current), "end_ns": str(current + duration), "duration_ns": str(duration)})
        row = {"record_type": "frame", "frame": str(index), "population": population, "begin_ns": str(current),
               "end_ns": str(current + duration), "duration_ns": str(duration), "unit": "ns", "status": "measured"}
        cpu.append(row)
        reference.append({key: row[key] for key in ("record_type", "frame", "begin_ns", "end_ns")})
        for stage in ("draw", "update", "present"):
            cpu.append({"record_type": "stage", "frame": str(index), "stage": stage, "duration_ns": "10000"})
        current += duration
    checkpoints = sorted({row["frame"] for row in frozen["required_checkpoints"]}, key=int)
    cpu[:0] = [{"record_type": "checkpoint", "frame": frame} for frame in checkpoints]
    cpu.append({"record_type": "complete", "frame": str(len(frozen["frames"]))})
    source.update(cpu=cpu, reference=reference,
                  validation={"status": "pass", "checked_frames": str(len(frozen["frames"]))},
                  comparison={"status": "pass", "checked_frames": str(len(checkpoints)),
                              "checkpoints": [{"frame": frame} for frame in checkpoints]})
    source["summary"]["supervision"]["reference_records"] = str(len(reference))
    return source


def retain(path, value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    path.write_bytes(gzip.compress(encoded, mtime=0))
    return sha256(encoded).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("case", choices=("static", "history"))
    parser.add_argument("--artifacts", type=Path, default=ROOT / "build/evidence-migration")
    parser.add_argument("--worker", type=Path)
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    frozen_path = args.artifacts / (args.case + "-frozen.json.gz")
    if frozen_path.is_file():
        frozen = json.loads(gzip.decompress(frozen_path.read_bytes()))
    else:
        config = fixture(args.case)["manifest"]["effective"]
        config.update(side_m="64", warmup="120", frames="21600", schedule=args.case + "-perf-v2")
        frozen = schedule(config)
        retain(frozen_path, frozen)
    source = workload(args.case, frozen)
    executable = args.worker or megascene_bend.worker("evidence_report")
    prior_worker = megascene_bend.worker
    megascene_bend.worker = lambda module: executable if module == "evidence_report" else prior_worker(module)
    started = time.perf_counter()
    result = classify(**source)
    elapsed = time.perf_counter() - started
    previous_report = args.artifacts / (args.case + "-report.json.gz")
    if previous_report.is_file():
        assert result == json.loads(gzip.decompress(previous_report.read_bytes()))
    assert result["evidence_errors"] == []
    assert result["populations"]["ordinary"]["mean"] == 500_000.0
    assert result["accepted_edits"]["count"] == ("120" if args.case == "history" else "0")
    assert all(result[key]["status"] == "pass" for key in
               ("schedule_completion", "population_qualification", "qualified_capacity"))
    assert set(result["stage_populations"]) == {"draw", "update", "present"}
    evidence = {"case": args.case, "synthetic": True, "worker_threads": 1,
                "elapsed_seconds": round(elapsed, 3), "timing_scope": "classify including transport; prepared worker",
                "frames": len(frozen["frames"]), "stage_records": 3 * len(frozen["frames"]),
                "ordinary_samples": result["populations"]["ordinary"]["count"],
                "accepted_edits": result["accepted_edits"]["count"],
                "worker_sha256": sha256(executable.read_bytes()).hexdigest(),
                "input_sha256": retain(args.artifacts / (args.case + "-input.json.gz"), source),
                "report_sha256": retain(args.artifacts / (args.case + "-report.json.gz"), result)}
    (args.artifacts / (args.case + "-timing.json")).write_text(json.dumps(evidence, sort_keys=True, indent=2) + "\n")
    print(json.dumps(evidence, sort_keys=True))


if __name__ == "__main__":
    main()
