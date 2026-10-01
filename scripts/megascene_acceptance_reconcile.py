#!/usr/bin/env python3
"""Charge every retained earlier Megascene campaign to the #68 allowance.

The gross charge intentionally includes failed and development attempts. Run
only between acceptance commands so a command cannot overwrite this ledger.
"""

import argparse
import json
from pathlib import Path

from megascene_acceptance_run import runner_remaining, save
from megascene_evidence import run as evidence


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
    result = evidence("reconcile", {"ledger": ledger, "campaigns": campaigns,
                                    "supervised": None}, "evidence_acceptance")
    if result["missing"]:
        parser.error(f"previously charged campaign missing: {result['missing']}")
    ledger = result["ledger"]
    ledger = evidence("remaining", {"ledger": ledger, "supervised": runner_remaining(ledger)},
                      "evidence_acceptance")
    print(json.dumps({"campaigns": len(campaigns),
                      "newly_charged": result["newly_charged"],
                      "prior_gross_charge_s": round(int(ledger["prior_gross_charge_ns"]) / 1e9, 3),
                      "remaining_s": round(int(ledger["remaining_ns"]) / 1e9, 3)},
                     indent=2))
    if args.write:
        save(args.ledger, ledger)


if __name__ == "__main__":
    main()
