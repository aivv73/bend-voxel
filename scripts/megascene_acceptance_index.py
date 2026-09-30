#!/usr/bin/env python3
"""Inventory retained Megascene evidence against the minimum acceptance matrix.

This is a locator and coverage audit, not a benchmark or acceptance assessor.
It never promotes an attempt on the strength of a summary status alone.
"""

import argparse
import hashlib
import json
from pathlib import Path


CASES = ("static", "traversal", "picking", "localized", "support", "history")
SCHEDULES = {"static": "static-v1", "traversal": "traversal-v2",
             "picking": "picking-v2", "localized": "localized-v1",
             "support": "support-v1", "history": "history-v1"}
OUTCOMES = ("schedule_completion", "state_correctness", "rendering_correctness",
            "visual_quality", "numeric_validity", "population_qualification",
            "calibration", "responsiveness", "qualified_capacity")
CONTROLS = (
    ("static", "spread-static-v1", "spread"),
    ("support", "fill-support-v1", "fill"),
    ("history", "fill-history-v1", "fill"),
    ("history", "body-rich-history-v1", "body-rich"),
    ("static", "material-detail-static-v1", "material-detail"),
    ("localized", "material-detail-localized-v1", "material-detail"),
    ("static", "surface-detail-static-v1", "surface-detail"),
    ("history", "history-12-v1", None),
    ("history", "history-48-v1", None),
    ("support", "support-1-span-v1", None),
    ("support", "support-2-span-v1", None),
)
CORROBORATION = (
    ("independent_reference_and_mismatch", "docs/validation/megascene-checkpoints/failures.json"),
    ("static_thread_equality", "docs/validation/megascene-checkpoints/thread-comparison.json"),
    ("localized_thread_equality", "docs/validation/megascene-localized/thread-comparison.json"),
    ("support_thread_equality", "docs/validation/megascene-support/thread-comparison.json"),
    ("history_small_thread_equality", "docs/validation/megascene-acceptance/history-small-threads.json"),
    ("history_large_thread_equality", "docs/validation/megascene-acceptance/history-large-threads.json"),
    ("complete_calibration_matrix", "docs/validation/megascene-acceptance/calibration-summary.json"),
    ("audited_visual_corrections", "docs/validation/megascene-acceptance/visual-review-corrections.md"),
    ("identical_capture_visual_reuse", "docs/validation/megascene-acceptance/visual-reuse.json"),
    ("additional_identical_capture_visual_reuse", "docs/validation/megascene-acceptance/visual-reuse-extension.json"),
    ("approved_history_view_decision", "docs/validation/megascene-acceptance/history-review-proposal.md"),
    ("approved_proxy_view_decision", "docs/validation/megascene-acceptance/proxy-review-proposal.md"),
    ("supplementary_view_preservation", "docs/validation/megascene-acceptance/supplementary-preservation.json"),
    ("supplementary_history_thread_equality", "docs/validation/megascene-acceptance/history-small-supplementary-threads.json"),
    ("supplementary_view_review", "docs/validation/megascene-acceptance/supplementary-views.md"),
    ("supplementary_repeat_reviews", "docs/validation/megascene-acceptance/supplementary-repeat-reviews.json"),
    ("large_history_guard_regression", "docs/validation/megascene-acceptance/large-history-guard.md"),
    ("resource_recovery", "docs/validation/megascene-gpu/recovery.json"),
    ("report_fixtures", "docs/validation/megascene-report/results.json"),
    ("archive_reproduction", "docs/validation/megascene-reproduction/README.md"),
    ("search_contract", "docs/megascene-search.md"),
    ("reference_fixtures", "tests/megascene_reference.py"),
    ("failure_and_search_tests", "tests/test_megascene_search.py"),
    ("reproduction_tests", "tests/test_megascene_reproduce.py"),
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def attempt(manifest_path):
    bundle = manifest_path.parent
    manifest = read(manifest_path)
    summary_path = bundle / "summary.json"
    summary = read(summary_path) if summary_path.exists() else {}
    validation_record = summary.get("validation")
    validation_path = (bundle / validation_record["path"]
                       if isinstance(validation_record, dict) and
                       validation_record.get("path") else None)
    evidence = manifest.get("evidence") or []
    artifacts = manifest.get("artifacts") or []
    paths = [item.get("path") for item in evidence if isinstance(item, dict)]
    key_artifacts = ("runtime/worker", "runtime/build/libvoxel_vulkan.so",
                     "schedule.json", "inputs.json")
    # Repeat observations must share actual frozen runtime/input bytes and mode.
    identity = {"attempt_kind": manifest.get("attempt_kind"),
                "calibration_mode": (manifest.get("worker_environment") or {}).get(
                    "MEGASCENE_CALIBRATION"),
                "artifacts": [(item["path"], item["sha256"]) for item in artifacts]}
    repeat_identity = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    return {
        "attempt_id": manifest.get("attempt_id"),
        "archive": str(bundle),
        "manifest": str(manifest_path),
        "manifest_sha256": digest(manifest_path),
        "summary": str(summary_path) if summary_path.exists() else None,
        "summary_sha256": digest(summary_path) if summary_path.exists() else None,
        "configuration": manifest.get("effective"),
        "attempt_kind": manifest.get("attempt_kind"),
        "repeat_identity_sha256": repeat_identity,
        "completed_prefix": summary.get("completed_prefix"),
        "termination": summary.get("termination"),
        "outcomes": {key: (summary.get(key) or {}).get("status") for key in OUTCOMES},
        "validation": validation_record,
        "validation_file": str(validation_path) if validation_path and
                           validation_path.is_file() else None,
        "validation_sha256": digest(validation_path) if validation_path and
                             validation_path.is_file() else None,
        "validation_status": read(validation_path).get("status") if
                             validation_path and validation_path.is_file() else None,
        "runtime_artifacts": {"manifest_entries": len(artifacts),
                              "present_entries": sum((bundle / item["path"]).is_file()
                                                     for item in artifacts),
                              "key_files": [{"path": str(bundle / item["path"]),
                                             "sha256": item["sha256"]}
                                            for item in artifacts if item["path"] in key_artifacts or
                                            item["path"].endswith(".spv")]},
        "raw_evidence": {"manifest_entries": len(evidence),
                         "present_entries": sum((bundle / item["path"]).is_file()
                                                for item in evidence),
                         "review_and_recovery_files": [
                             {"path": str(bundle / item["path"]), "sha256": item["sha256"]}
                             for item in evidence if any(word in item["path"] for word in
                             ("review", "comparison", "calibration", "reproduction"))]},
        "captures": [str(bundle / path) for path in paths if path and "captures/" in path],
        "reviews": [str(p) for p in sorted(bundle.glob("*review*.json"))] +
                   [str(p) for p in sorted((bundle / "validation").glob("*review*.json"))],
    }


def campaigns(base):
    result = []
    attempts = []
    campaign_files = set(base.glob("megascene*/campaign.json"))
    campaign_files.update(base.glob("megascene-acceptance-68/runner/campaign.json"))
    for campaign_file in sorted(campaign_files):
        root = campaign_file.parent
        ledger = read(campaign_file)
        bundles = [attempt(p) for p in sorted(root.glob("*/*/*/manifest.json"))]
        attempts.extend(bundles)
        result.append({
            "archive": str(root), "campaign": str(campaign_file),
            "campaign_sha256": digest(campaign_file),
            "campaign_id": ledger.get("campaign_id"),
            "elapsed_ns": ledger.get("elapsed_ns"),
            "allowance_ns": ledger.get("allowance_ns"),
            "additional_allowances": ledger.get("additional_allowances"),
            "state": ledger.get("state"),
            "attempts": [{"attempt_id": row.get("attempt_id"),
                          "cause": row.get("cause"),
                          "summary": row.get("summary"),
                          "summary_present": Path(row.get("summary", "")).is_file()}
                         for row in ledger.get("attempts", [])],
            "bundle_ids": [row["attempt_id"] for row in bundles],
        })
    return result, attempts


def requirements():
    rows = []
    for preset, threads in (("small", (1, 6, 12)), ("large", (6,))):
        for case in CASES:
            for thread in threads:
                rows.append({"group": "primary", "case": case, "preset": preset,
                             "threads": str(thread), "resolution": "1920x1080",
                             "profile": "full", "schedule": SCHEDULES[case],
                             "diagnostic": None, "control": None,
                             "required_complete_attempts": 3 if preset == "small" and
                                 case in ("static", "history") else 1})
    for case in ("static", "history"):
        rows.append({"group": "resolution", "case": case, "preset": "small",
                     "threads": "6", "resolution": "640x360", "profile": "full",
                     "schedule": SCHEDULES[case], "diagnostic": None,
                     "control": None, "required_complete_attempts": 1})
    for diagnostic in ("mixed-world", "compact-reference"):
        for case in ("traversal", "picking"):
            for profile in ("full", "proxy"):
                rows.append({"group": "proxy", "case": case, "preset": "small",
                             "threads": "6", "resolution": "1920x1080", "profile": profile,
                             "schedule": f"proxy-{diagnostic}-{case}-v1",
                             "diagnostic": diagnostic, "control": None,
                             "required_complete_attempts": 1})
    for case, schedule, control in CONTROLS:
        rows.append({"group": "control", "case": case, "preset": "small",
                     "threads": "6", "resolution": "1920x1080", "profile": "full",
                     "schedule": schedule, "diagnostic": None, "control": control,
                     "required_complete_attempts": 1})
    return rows


def complete(row):
    config = row["configuration"] or {}
    outcomes = row["outcomes"]
    return (config.get("warmup") == "120" and config.get("frames") == "3600" and
            not config.get("validation_only") and row["completed_prefix"] ==
            {"startup": True, "warmup": "120", "measured": "3600"} and
            all(outcomes[key] == "pass" for key in
                ("schedule_completion", "state_correctness", "rendering_correctness")) and
            row["validation_status"] == "pass" and
            row["runtime_artifacts"]["present_entries"] ==
            row["runtime_artifacts"]["manifest_entries"] and
            row["raw_evidence"]["present_entries"] ==
            row["raw_evidence"]["manifest_entries"])


def coverage(attempts):
    result = []
    keys = ("case", "preset", "threads", "resolution", "profile", "schedule",
            "diagnostic", "control")
    for needed in requirements():
        matching = []
        for row in attempts:
            config = row["configuration"] or {}
            if (config.get("seed") == "45" and
                    all(config.get(key) == needed[key] for key in keys) and
                    row["attempt_kind"] != "calibration_off"):
                matching.append(row)
        completed = [row for row in matching if complete(row)]
        repeat_groups = {}
        for row in completed:
            repeat_groups.setdefault(row["repeat_identity_sha256"], []).append(row["attempt_id"])
        result.append({**needed,
                       "candidate_attempts": [row["attempt_id"] for row in matching],
                       "complete_runtime_attempts": [row["attempt_id"] for row in completed],
                       "visual_quality_pass_attempts": [row["attempt_id"] for row in
                                                        completed if row["outcomes"]["visual_quality"] == "pass"],
                       "numeric_validity_pass_attempts": [row["attempt_id"] for row in
                                                          completed if row["outcomes"]["numeric_validity"] == "pass"],
                       "repeat_groups": repeat_groups,
                       "runtime_coverage": "observed" if max(map(len, repeat_groups.values()), default=0) >=
                           needed["required_complete_attempts"] else "missing",
                       "acceptance": "unassessed"})
    return result


def calibration_series(base):
    rows = []
    for case in ("static", "history"):
        for preset in ("small", "large"):
            for threads in (1, 6, 12):
                name = f"{case}-{preset}-{threads}"
                found = set(base.glob(f"megascene*/calibration-series/{name}/series.json"))
                found.update(base.glob(
                    f"megascene-acceptance-68/runner/calibration-series/{name}/series.json"))
                entries = []
                for path in sorted(found):
                    series = read(path)
                    assessment_path = path.with_name("assessment.json")
                    entries.append({"series": str(path), "series_sha256": digest(path),
                                    "status": series.get("status"),
                                    "validations": series.get("validations"),
                                    "controls": series.get("controls"),
                                    "assessment": str(assessment_path) if assessment_path.exists() else None,
                                    "assessment_sha256": digest(assessment_path)
                                    if assessment_path.exists() else None,
                                    "assessment_status": read(assessment_path).get("status")
                                    if assessment_path.exists() else None})
                rows.append({"case": case, "preset": preset, "threads": str(threads),
                             "required_controls": 6, "series": entries})
    return rows


def supporting_artifacts(base):
    """Index the #68 proof, diagnostic, admission and Atelier archive."""
    files = []
    roots = [(base / "megascene-acceptance-68", None)]
    roots += [(root, {"failed", "checks", "review-sheets", "diagnostics"}) for root in sorted(
        base.glob("megascene-acceptance-68-*"))]
    for root, allowed in roots:
        if not root.is_dir():
            continue
        for category in sorted(root.iterdir()):
            if not category.is_dir() or category.name == "runner" or (
                    allowed is not None and category.name not in allowed):
                continue
            for path in sorted(p for p in category.rglob("*") if p.is_file()):
                files.append({"category": f"{root.name}/{category.name}",
                              "path": str(path), "sha256": digest(path),
                              "bytes": path.stat().st_size})
    return files


def corroboration():
    root = Path(__file__).resolve().parents[1]
    rows = [{"role": role, "repository_path": relative,
             "sha256": digest(root / relative)} for role, relative in CORROBORATION]
    for path in sorted((root / "docs/validation/megascene-acceptance/reviews").glob("*.json")):
        rows.append({"role": "named_visual_assessment_input",
                     "repository_path": str(path.relative_to(root)),
                     "sha256": digest(path)})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-base", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    campaign_rows, attempts = campaigns(args.archive_base)
    value = {"schema": "megascene-acceptance-index/1", "issue": 68,
             "scope": "retained evidence locator and runtime coverage audit; no acceptance or performance pass",
             "policy": "docs/megascene-spec.md#minimum-implementation-acceptance-coverage",
             "campaigns": campaign_rows, "attempts": attempts,
             "coverage": coverage(attempts),
             "calibration_matrix": calibration_series(args.archive_base),
             "supporting_artifacts": supporting_artifacts(args.archive_base),
             "corroboration": corroboration(),
             "known_campaign_elapsed_ns": str(sum(int(row["elapsed_ns"] or 0)
                                                 for row in campaign_rows)),
             "implementation_acceptance": "unassessed",
             "acceptance_assessment": "acceptance.json (separate reviewed decision, when present)",
             "qualified_performance": "unqualified",
             "future_limit_discovery": "outside_issue_68"}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    print(f"{len(campaign_rows)} campaigns, {len(attempts)} bundles, "
          f"{len(value['coverage'])} runtime rows, "
          f"{sum(row['runtime_coverage'] == 'observed' for row in value['coverage'])} observed")


if __name__ == "__main__":
    main()
