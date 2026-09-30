#!/usr/bin/env python3
"""Charge supervisor lease time not already charged by command wrappers.

Run between acceptance commands. This captures idle and review time within
each #68 runner lease, including the bridge between runner roots, without
counting a wrapped attempt twice.
"""

import argparse
from datetime import datetime
import json
from pathlib import Path
import time

from megascene_acceptance_run import runner_remaining, save


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    ledger = json.loads(args.ledger.read_text())
    credited = ledger.setdefault("runner_overhead_credited_ns", {})
    changes = []
    roots = ledger.get("runner_campaign_history", []) + [ledger["runner_campaign"]]
    for index, item in enumerate(roots):
        path = item["path"]
        campaign = json.loads(Path(path).read_text())
        gross = int(campaign["elapsed_ns"])
        bridge = 0
        if path == ledger["runner_campaign"]["path"] and campaign["state"] == "active":
            boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
            since = (time.monotonic_ns() - int(campaign["lease_ns"])
                     if boot == campaign["boot_id"] else
                     time.time_ns() - int(campaign["lease_utc_ns"]))
            gross = min(int(campaign["allowance_ns"]), gross + max(0, since))
        elif index + 1 < len(roots) and campaign["state"] == "active":
            next_campaign = json.loads(Path(roots[index + 1]["path"]).read_text())
            next_start_ns = int(datetime.fromisoformat(
                next_campaign["utc_start"]).timestamp() * 1_000_000_000)
            bridge = max(0, next_start_ns - int(campaign["lease_utc_ns"]))
            gross += bridge
        wrapped = sum(int(run["elapsed_ns"]) for run in ledger["new_work"]
                      if run.get("runner_campaign") == path or
                      path.removesuffix("/campaign.json") in run.get("command", []))
        overhead = max(0, gross - wrapped)
        previous = int(credited.get(path, "0"))
        if overhead > previous:
            delta = overhead - previous
            changes.append({"name": "supervisor-gross-overhead",
                            "campaign": path, "elapsed_ns": str(delta),
                            "gross_ns": str(gross), "wrapped_ns": str(wrapped),
                            "bridge_to_next_runner_ns": str(bridge),
                            "status": "charged"})
            credited[path] = str(overhead)
    for change in changes:
        ledger["new_work"].append(change)
        ledger["new_work_charge_ns"] = str(int(ledger["new_work_charge_ns"]) +
                                           int(change["elapsed_ns"]))
    remaining = max(0, int(ledger["allowance_ns"]) -
                    int(ledger["prior_gross_charge_ns"]) -
                    int(ledger["new_work_charge_ns"]))
    supervised = runner_remaining(ledger)
    ledger["runner_campaign_remaining_ns"] = str(supervised)
    ledger["remaining_ns"] = str(min(remaining, supervised))
    print(json.dumps({"charged": changes,
                      "remaining_s": round(int(ledger["remaining_ns"]) / 1e9, 3)},
                     indent=2))
    if args.write:
        save(args.ledger, ledger)


if __name__ == "__main__":
    main()
