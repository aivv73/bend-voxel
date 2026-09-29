#!/usr/bin/env python3
"""Repair the #68 history 360p report after the preflight-extremum fix.

The pre-review output is a retained copy of the first completed report. The
archive keeps its prior summary and an audit record before reclassification.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil

from megascene import artifact, snapshot
from megascene_report import report_bundle


ERROR = "resource device_free_bytes observed extremum mismatch"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--pre-review-summary", required=True, type=Path)
    args = parser.parse_args()
    root = args.bundle.resolve()
    before = (root / "summary.json").read_bytes()
    original = args.pre_review_summary.read_bytes()
    current = json.loads(before)
    first = json.loads(original)
    manifest = json.loads((root / "manifest.json").read_text())
    supervision = json.loads((root / "supervision.json").read_text())
    assert not (root / "summary.before-preflight-fix.json").exists()
    assert not (root / "report-reclassification.json").exists()
    assert current["attempt_id"] == first["attempt_id"] == manifest["attempt_id"]
    assert current["schedule_completion"]["status"] == "inconclusive"
    assert first["schedule_completion"]["status"] == "pass"
    assert current["visual_quality"]["status"] == "pass"
    assert current["evidence_errors"] == first["evidence_errors"] == [ERROR]
    assert supervision["errors"] == []
    assert supervision["termination"]["cause"] == "normal_exit"
    shutil.copy2(root / "summary.json", root / "summary.before-preflight-fix.json")
    base = dict(first)
    base["visual_quality"] = current["visual_quality"]
    base["review"] = current["review"]
    base["source_evidence_errors"] = []
    snapshot(root / "summary.json", base)
    result = report_bundle(root)
    assert result["schedule_completion"]["status"] == "pass"
    assert result["visual_quality"]["status"] == "pass"
    assert result["evidence_errors"] == []
    snapshot(root / "summary.json", result)
    snapshot(root / "report-reclassification.json", {
        "schema": "megascene-acceptance-reclassification/1",
        "attempt_id": manifest["attempt_id"],
        "reason": "preflight device-free sample excluded from supervisor live extrema",
        "old_summary_sha256": digest(before),
        "pre_review_summary_sha256": digest(original),
        "new_summary_sha256": digest((root / "summary.json").read_bytes()),
        "preserved_prior_summary": "summary.before-preflight-fix.json",
        "result": "schedule, state, rendering and visual checks pass; calibration remains separately qualified",
    })
    manifest["evidence"] = [artifact(path, root) for path in sorted(root.rglob("*"))
                            if path.is_file() and "runtime" not in path.relative_to(root).parts
                            and path.relative_to(root).as_posix() != "manifest.json"]
    snapshot(root / "manifest.json", manifest)
    print(root / "report-reclassification.json")


if __name__ == "__main__":
    main()
