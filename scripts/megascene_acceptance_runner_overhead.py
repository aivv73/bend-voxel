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
from megascene_evidence import run as evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    ledger = json.loads(args.ledger.read_text())
    roots = ledger.get("runner_campaign_history", []) + [ledger["runner_campaign"]]
    snapshots = [(item["path"], json.loads(Path(item["path"]).read_text())) for item in roots]
    campaigns = []
    for index, (path, campaign) in enumerate(snapshots):
        next_start = snapshots[index + 1][1].get("utc_start") if index + 1 < len(snapshots) else None
        campaigns.append({"path": path, "root": path.removesuffix("/campaign.json"),
                          "campaign": campaign,
                          "next_start_ns": int(datetime.fromisoformat(next_start).timestamp() *
                                               1_000_000_000) if next_start else None})
    result = evidence("overhead", {"ledger": ledger, "campaigns": campaigns,
                                   "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                                   "monotonic_ns": time.monotonic_ns(), "utc_ns": time.time_ns(),
                                   "supervised": runner_remaining(ledger)}, "evidence_acceptance")
    ledger, changes = result["ledger"], result["charged"]
    print(json.dumps({"charged": changes,
                      "remaining_s": round(int(ledger["remaining_ns"]) / 1e9, 3)},
                     indent=2))
    if args.write:
        save(args.ledger, ledger)


if __name__ == "__main__":
    main()
