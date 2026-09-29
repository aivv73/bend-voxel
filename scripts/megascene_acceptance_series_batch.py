#!/usr/bin/env python3
"""Run the remaining accepted calibration configurations sequentially."""

import argparse
from pathlib import Path
import subprocess
import sys


REMAINING = (("static", "large", 1), ("static", "large", 12),
             ("history", "small", 1), ("history", "small", 6),
             ("history", "small", 12), ("history", "large", 1),
             ("history", "large", 6), ("history", "large", 12))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--checks", type=Path, required=True)
    parser.add_argument("--start", choices=[f"{c}-{p}-{t}" for c, p, t in REMAINING],
                        default="static-large-1")
    parser.add_argument("--name-suffix", default="")
    args = parser.parse_args()
    script = Path(__file__).resolve().parent
    start = next(i for i, (c, p, t) in enumerate(REMAINING)
                 if f"{c}-{p}-{t}" == args.start)
    for case, preset, threads in REMAINING[start:]:
        name = f"calibration-{case}-{preset}-{threads}{args.name_suffix}"
        series = args.archive / "calibration-series" / f"{case}-{preset}-{threads}" / "series.json"
        if series.exists():
            raise RuntimeError(f"Existing series requires inspection, not automatic retry: {series}")
        command = [sys.executable, str(script / "megascene_acceptance_run.py"),
                   "--ledger", str(args.ledger), "--archive", str(args.checks),
                   "--name", name, "--timeout", "2400", "--",
                   sys.executable, str(script / "megascene_calibration_series.py"), "run",
                   "--archive", str(args.archive),
                   "--work", str(args.work / name), "--case", case,
                   "--preset", preset, "--threads", str(threads)]
        print(f"START {name}", flush=True)
        result = subprocess.run(command, check=False)
        print(f"END {name} exit={result.returncode}", flush=True)
        if result.returncode:
            raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
