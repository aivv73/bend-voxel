#!/usr/bin/env python3
"""Reuse a visual assessment only for byte-identical named captures.

The source and target must have the same case, route, schedule hash, profile,
preset, seed, resolution, feature names and capture SHA-256 values. Threads may
differ.
"""

import argparse
import json
from pathlib import Path

from megascene_acceptance_index import campaigns
from megascene_evidence import run as evidence
from megascene_review import assess


def _review(attempt):
    path = Path(attempt["archive"]) / "review.json"
    return json.loads(path.read_text()) if path.is_file() else None


def signature(attempt):
    value = evidence("review_signature", {"attempt": attempt, "review": _review(attempt)},
                     "evidence_acceptance")
    if value is None:
        return None
    scope, schedule_hash, captures = value
    return tuple(scope), schedule_hash, tuple((name, frame, digest, tuple(features))
                                              for name, frame, digest, features in captures)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-base", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    _, attempts = campaigns(args.archive_base)
    observed = [{"attempt": item, "review": _review(item),
                 "assessments_present": (Path(item["archive"]) / "assessments.json").is_file()}
                for item in attempts]
    candidates = evidence("review_reuse", observed, "evidence_acceptance")
    results = []
    for row in candidates:
        root = Path(row["target_archive"])
        if args.execute:
            row["assessment"] = assess(root, Path(row["source_archive"]) / "assessments.json",
                                       "Codex review of byte-identical archived captures")
        results.append(row)
        print(json.dumps(row, sort_keys=True), flush=True)
    if args.execute:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({
            "schema": "megascene-acceptance-visual-reuse/1",
            "policy": "same scope, named features and capture SHA-256; target reviewed separately",
            "rows": results}, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
