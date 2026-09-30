#!/usr/bin/env python3
"""Correct a visual assessment while retaining its complete prior revision."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import uuid

from megascene import artifact, snapshot
from megascene_inventory import require
from megascene_review import assess


def correct(bundle, input_path, reviewer, reason):
    root = Path(bundle).resolve()
    require(reason.strip(), "correction reason required")
    original = json.loads((root / "review.json").read_text())
    require((root / "assessments.json").is_file(), "prior assessment required")
    revision = root / "review-revisions" / uuid.uuid4().hex
    revision.mkdir(parents=True)
    retained = []
    for name in ("review.json", "assessments.json", "summary.json", "manifest.json"):
        destination = revision / name
        shutil.copy2(root / name, destination)
        retained.append(artifact(destination, root))
    audit = {
        "schema": "megascene-acceptance-review-correction/1",
        "bundle": str(root), "reason": reason, "reviewer": reviewer,
        "recorded_utc": datetime.now(timezone.utc).isoformat(),
        "prior_status": original["status"], "retained": retained,
    }
    snapshot(revision / "audit.json", audit)
    # The assessor refuses replacement. The old input is now durably retained
    # and hashed; removing only its canonical name permits the audited revision.
    (root / "assessments.json").unlink()
    try:
        status = assess(root, input_path, reviewer)
    except Exception as exc:
        for name in ("review.json", "assessments.json", "summary.json", "manifest.json"):
            shutil.copy2(revision / name, root / name)
        audit["correction_error"] = str(exc)
        snapshot(revision / "audit.json", audit)
        raise
    manifest = json.loads((root / "manifest.json").read_text())
    manifest["evidence"] += retained + [artifact(revision / "audit.json", root)]
    manifest["evidence"].sort(key=lambda item: item["path"])
    snapshot(root / "manifest.json", manifest)
    return {"bundle": str(root), "prior_status": original["status"],
            "status": status, "audit": str(revision / "audit.json")}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--assessments", required=True, type=Path)
    parser.add_argument("--reviewer", required=True)
    parser.add_argument("--reason", required=True)
    args = parser.parse_args()
    print(json.dumps(correct(args.bundle, args.assessments, args.reviewer,
                             args.reason), sort_keys=True))
