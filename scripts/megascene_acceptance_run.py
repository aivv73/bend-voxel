#!/usr/bin/env python3
"""Run a non-Megascene acceptance check within the consolidated allowance."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def save(path, value):
    temporary = path.with_name(path.name + ".new")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, path)


def runner_remaining(ledger):
    runner = ledger.get("runner_campaign")
    if not runner:
        return None
    value = json.loads(Path(runner["path"]).read_text())
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    if value["state"] != "active":
        elapsed_since_lease = 0
    else:
        elapsed_since_lease = (time.monotonic_ns() - int(value["lease_ns"])
                               if boot == value["boot_id"] else
                               time.time_ns() - int(value["lease_utc_ns"]))
    used = int(value["elapsed_ns"]) + max(0, elapsed_since_lease)
    return max(0, int(value["allowance_ns"]) - used)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ledger", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--name", required=True)
    parser.add_argument("--timeout", required=True, type=int)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or args.timeout <= 0 or not args.name.replace("-", "").isalnum():
        parser.error("name, positive timeout and command required")
    ledger = json.loads(args.ledger.read_text())
    remaining = int(ledger["remaining_ns"])
    supervised = runner_remaining(ledger)
    if supervised is not None:
        remaining = min(remaining, supervised)
    if remaining <= 0:
        parser.error("consolidated acceptance allowance exhausted")
    timeout = min(args.timeout, remaining / 1_000_000_000)
    args.archive.mkdir(parents=True, exist_ok=True)
    log = args.archive / (args.name + ".log")
    if log.exists():
        parser.error(f"retained check already exists: {log}")
    start = time.monotonic_ns()
    started_utc = datetime.now(timezone.utc).isoformat()
    status = "failed"
    code = None
    with log.open("x") as stream:
        try:
            proc = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                    start_new_session=True)
            try:
                code = proc.wait(timeout=timeout)
                status = "pass" if code == 0 else "failed"
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
                code = 124
                status = "timeout"
        except OSError as exc:
            stream.write(f"Launch failure: {exc}\n")
            code = 127
            status = "launch_failed"
    elapsed = time.monotonic_ns() - start
    entry = {"name": args.name, "command": command, "started_utc": started_utc,
             "elapsed_ns": str(elapsed), "status": status, "exit_code": code,
             "log": str(log), "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()}
    if ledger.get("runner_campaign"):
        entry["runner_campaign"] = ledger["runner_campaign"]["path"]
    ledger["new_work"].append(entry)
    ledger["new_work_charge_ns"] = str(int(ledger["new_work_charge_ns"]) + elapsed)
    ledger["remaining_ns"] = str(max(0, int(ledger["allowance_ns"]) -
                                   int(ledger["prior_gross_charge_ns"]) -
                                   int(ledger["new_work_charge_ns"])))
    supervised = runner_remaining(ledger)
    if supervised is not None:
        ledger["runner_campaign_remaining_ns"] = str(supervised)
        ledger["remaining_ns"] = str(min(int(ledger["remaining_ns"]), supervised))
    save(args.ledger, ledger)
    print(json.dumps(entry, sort_keys=True))
    raise SystemExit(0 if status == "pass" else 1)


if __name__ == "__main__":
    main()
