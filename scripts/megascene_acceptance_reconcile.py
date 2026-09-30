#!/usr/bin/env python3
"""Charge every retained earlier Megascene campaign to the #68 allowance.

The gross charge intentionally includes failed and development attempts. Run
only between acceptance commands so a command cannot overwrite this ledger.
"""

import argparse
import json
from pathlib import Path

from megascene_acceptance_run import runner_remaining, save


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-base", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    ledger = json.loads(args.ledger.read_text())
    runners = {Path(item["path"]).resolve() for item in
               ledger.get("runner_campaign_history", []) + [ledger["runner_campaign"]]}
    campaigns = []
    for path in sorted(args.archive_base.glob("megascene*/campaign.json")):
        if path.resolve() in runners:
            continue
        value = json.loads(path.read_text())
        campaigns.append({"archive": str(path.parent), "campaign": str(path),
                          "campaign_id": value["campaign_id"],
                          "elapsed_ns": str(value["elapsed_ns"]),
                          "scope": "all retained earlier Megascene work; conservative gross charge"})
    previous = {row["campaign"] for row in ledger["prior_campaigns"]}
    found = {row["campaign"] for row in campaigns}
    if not previous <= found:
        parser.error(f"previously charged campaign missing: {sorted(previous - found)}")
    ledger["prior_campaigns"] = campaigns
    ledger["prior_gross_charge_ns"] = str(sum(int(row["elapsed_ns"]) for row in campaigns))
    ledger["charging_policy"] = ("Conservative gross charge of every retained earlier "
                                 "Megascene campaign root, including development and failed "
                                 "attempts; new work charged once through new_work")
    remaining = max(0, int(ledger["allowance_ns"]) -
                    int(ledger["prior_gross_charge_ns"]) -
                    int(ledger["new_work_charge_ns"]))
    supervised = runner_remaining(ledger)
    ledger["runner_campaign_remaining_ns"] = str(supervised)
    ledger["remaining_ns"] = str(min(remaining, supervised))
    print(json.dumps({"campaigns": len(campaigns),
                      "newly_charged": sorted(found - previous),
                      "prior_gross_charge_s": round(int(ledger["prior_gross_charge_ns"]) / 1e9, 3),
                      "remaining_s": round(int(ledger["remaining_ns"]) / 1e9, 3)},
                     indent=2))
    if args.write:
        save(args.ledger, ledger)


if __name__ == "__main__":
    main()
