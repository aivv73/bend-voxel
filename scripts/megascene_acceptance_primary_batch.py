#!/usr/bin/env python3
"""Fill only missing primary and 360p runtime rows in the #68 matrix.

Runs are sequential to keep Vulkan measurements isolated. This checks runtime
coverage only; named visual reviews and acceptance remain separate gates.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

from megascene_acceptance_index import campaigns, coverage
from megascene_evidence import run as evidence


def inventory(base):
    _, attempts = campaigns(base)
    return attempts, coverage(attempts)


def retain_failure(output, archive):
    if not output.is_dir():
        return None
    target = archive / "failed" / output.name
    if target.exists():
        raise ValueError(f"failed work already retained: {target}")
    shutil.copytree(output, target, copy_function=shutil.copy2)
    files = [{"path": str(path.relative_to(target)),
              "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
             for path in sorted(target.rglob("*")) if path.is_file()]
    (target / "retention.json").write_text(json.dumps({
        "schema": "megascene-acceptance-retained-failure/1",
        "source": str(output), "archive": str(target), "files": files},
        indent=2, sort_keys=True) + "\n")
    return target


def source_for(row, rows, by_id, preferred_root):
    return evidence("source_for", {"row": row, "rows": rows, "by_id": by_id,
                                   "preferred_ids": [identifier for identifier, item in by_id.items()
                                                     if item.get("archive") is not None and
                                                     Path(item["archive"]).is_relative_to(preferred_root)]},
                    "evidence_acceptance")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-base", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--checks", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    script = Path(__file__).resolve().parent
    attempts, rows = inventory(args.archive_base)
    pending = evidence("primary_pending", rows, "evidence_acceptance")
    for row in pending:
        print(f"PENDING {row['group']} {row['case']} {row['preset']} "
              f"threads={row['threads']} resolution={row['resolution']} "
              f"best_repeat={max(map(len, row['repeat_groups'].values()), default=0)}/"
              f"{row['required_complete_attempts']}", flush=True)
    if not args.execute:
        return
    for required in pending:
        fresh_source = None
        for n in range(required["required_complete_attempts"] + 1):
            attempts, rows = inventory(args.archive_base)
            row = next(r for r in rows if all(r[k] == required[k] for k in
                       ("group", "case", "preset", "threads", "resolution")))
            if row["runtime_coverage"] == "observed":
                break
            by_id = {a["attempt_id"]: a for a in attempts}
            source = fresh_source or source_for(row, rows, by_id, args.archive)
            tag = f"{row['case']}-{row['preset']}-{row['threads']}-{row['resolution']}-{uuid.uuid4().hex[:8]}"
            name = "primary-" + tag
            output = args.work / tag
            command = [sys.executable, str(script / "megascene.py"), "--case", row["case"],
                       "--preset", row["preset"], "--seed", "45", "--threads", row["threads"],
                       "--resolution", row["resolution"], "--archive", str(args.archive),
                       "--output", str(output)]
            mode = None
            if source:
                command += ["--runtime-from", source["archive"]]
                original = json.loads(Path(source["manifest"]).read_text())
                mode = original.get("worker_environment", {}).get("MEGASCENE_CALIBRATION")
                if mode in ("on", "off"):
                    command += ["--calibration", mode]
                    peer = original["effective"].get("calibration_peer_validation")
                    if not peer:
                        raise ValueError("calibration source lacks opposite-mode validation")
                    command += ["--calibration-peer-validation", peer]
            if row["case"] == "static" and mode not in ("on", "off"):
                command.append("--capture-opening")
            wrapped = [sys.executable, str(script / "megascene_acceptance_run.py"),
                       "--ledger", str(args.ledger), "--archive", str(args.checks),
                       "--name", name, "--timeout", "1800", "--", *command]
            print("START", name, "runtime_from", source["archive"] if source else None,
                  flush=True)
            result = subprocess.run(wrapped, check=False)
            if result.returncode:
                print("FAILED", name, "retained", retain_failure(output, args.archive),
                      flush=True)
                raise SystemExit(result.returncode)
            attempts, updated = inventory(args.archive_base)
            candidate = next(r for r in updated if all(r[k] == required[k] for k in
                             ("group", "case", "preset", "threads", "resolution")))
            old_ids = set(row["complete_runtime_attempts"])
            new_ids = set(candidate["complete_runtime_attempts"]) - old_ids
            if len(new_ids) != 1:
                print("INCOMPLETE", name, "runtime audit did not gain one complete attempt",
                      flush=True)
                raise SystemExit(2)
            fresh_source = next(a for a in attempts if a["attempt_id"] in new_ids)
            print("END", name, candidate["runtime_coverage"], flush=True)
        else:
            print("INCOMPLETE", required, "repeat target unavailable", flush=True)
            raise SystemExit(2)


if __name__ == "__main__":
    main()
