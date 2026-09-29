#!/usr/bin/env python3
"""Reuse a visual assessment only for byte-identical named captures.

The source and target must have the same case, route, schedule hash, profile,
preset, seed, resolution, feature names and capture SHA-256 values. Threads may
differ.
"""

import argparse
import json
from pathlib import Path

from megascene_acceptance_index import campaigns, complete
from megascene_review import assess


def signature(attempt):
    config = attempt["configuration"] or {}
    root = Path(attempt["archive"])
    path = root / "review.json"
    if not path.is_file():
        return None
    review = json.loads(path.read_text())
    views = review.get("views")
    if not views:
        return None
    scope = tuple(config.get(key) for key in
                  ("case", "preset", "seed", "resolution", "profile", "schedule",
                   "diagnostic", "control"))
    captures = tuple((view["name"], view["frame"], view["capture"]["sha256"],
                      tuple(feature["name"] for feature in view["features"]))
                     for view in views)
    return scope, review["schedule_sha256"], captures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-base", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    _, attempts = campaigns(args.archive_base)
    sources = {}
    for item in attempts:
        if not complete(item):
            continue
        key = signature(item)
        if key is None:
            continue
        root = Path(item["archive"])
        review = json.loads((root / "review.json").read_text())
        if review.get("status") == "pass" and (root / "assessments.json").is_file():
            sources.setdefault(key, item)
    results = []
    for item in attempts:
        if not complete(item):
            continue
        key = signature(item)
        if key is None or key not in sources:
            continue
        root = Path(item["archive"])
        review = json.loads((root / "review.json").read_text())
        if review.get("status") != "awaiting_named_feature_review":
            continue
        source = sources[key]
        if source["attempt_id"] == item["attempt_id"]:
            continue
        row = {"source_attempt": source["attempt_id"],
               "source_archive": source["archive"],
               "target_attempt": item["attempt_id"],
               "target_archive": item["archive"],
               "capture_count": len(key[2])}
        if args.execute:
            row["assessment"] = assess(root, Path(source["archive"]) / "assessments.json",
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
