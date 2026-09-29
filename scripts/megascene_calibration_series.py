#!/usr/bin/env python3
"""Run and assess the bounded, ordered Megascene calibration controls."""

import argparse
from decimal import Decimal
from fractions import Fraction
import json
from pathlib import Path
import subprocess
import sys

from megascene import snapshot
from megascene_calibration import compare_modes, reference_sequence
from megascene_inventory import SCHEMA, integer, read_json, require
from megascene_report import SCOPE_KEYS, read_stream

ORDER = ("off", "on", "on", "off", "off", "on")
STATISTICS = ("ordinary_mean", "ordinary_p95", "ordinary_p99", "accepted_edits_p95")
MIN_ORDINARY = 1000
MIN_MEASURED_NS = 10_000_000_000
MIN_EDITS = 100


def matrix():
    return [{"case": case, "preset": preset, "seed": "45", "threads": str(threads),
             "resolution": "1920x1080", "profile": "full", "schedule": case+"-v1",
             "diagnostic": None, "control": None, "fragment_budget": "2048",
             "warmup": "120", "frames": "3600", "order": list(ORDER)}
            for case in ("static", "history") for preset in ("small", "large")
            for threads in (1, 6, 12)]


def plan():
    configurations = matrix()
    return {"schema": SCHEMA, "record_type": "calibration_plan", "configurations": configurations,
            "configuration_count": len(configurations),
            "control_count": sum(len(c["order"]) for c in configurations),
            "control_order": list(ORDER), "pairs": [[0, 1], [2, 3], [4, 5]],
            "qualification_scope": "only the exact tested configuration and workload regime"}


def scope(config):
    return {key: config[key] for key in SCOPE_KEYS}


def paths(series):
    return [Path(item["archive"]) for item in series["controls"]]


def _record(path, series, category, mode, output, returncode):
    manifest_path = output/"manifest.json"
    archive = None
    if manifest_path.exists():
        manifest = read_json(manifest_path.read_text())
        archive = manifest.get("reproduction", {}).get("archive")
    item = {"kind": category, "mode": mode, "output": str(output), "archive": archive,
            "returncode": returncode}
    series["runs"].append(item)
    if category == "validation":
        series["validations"][mode] = item
    else:
        series["controls"].append(item)
    snapshot(path, series)
    require(returncode == 0 and archive is not None, "runner failed; retained partial series: "+str(output))
    return Path(archive)


def run_series(archive, work, case, preset, threads, additional=0):
    config = next(c for c in matrix() if (c["case"], c["preset"], c["threads"]) ==
                  (case, preset, str(threads)))
    require(archive.is_absolute() and work.is_absolute(), "archive and work paths must be absolute")
    require(archive != work and archive not in work.parents and work not in archive.parents,
            "archive and work must be separate")
    series_path = archive/"calibration-series"/(case+"-"+preset+"-"+str(threads))/"series.json"
    series_path.parent.mkdir(parents=True, exist_ok=True)
    resuming = series_path.exists()
    if resuming:
        series = read_json(series_path.read_text())
        require(series["scope"] == scope(config) and series["order"] == list(ORDER),
                "existing series scope/order mismatch")
        require(all(run["returncode"] == 0 for run in series["runs"]),
                "series contains a failed run; retain it without automatic rerun")
    else:
        series = {"schema": SCHEMA, "record_type": "calibration_series", "scope": scope(config),
                  "order": list(ORDER), "validations": {}, "controls": [], "runs": [],
                  "archive_root": str(archive), "work_root": str(work), "status": "incomplete"}
        snapshot(series_path, series)
    require(series["archive_root"] == str(archive) and series["work_root"] == str(work),
            "resume paths differ from original series")
    if len(series["controls"]) == 6:
        return write_assessment(series_path)
    require(not resuming or additional > 0,
            "resuming an incomplete series requires --additional-allowance SECONDS")
    campaign_file = archive/"campaign.json"
    if campaign_file.exists():
        campaign = read_json(campaign_file.read_text())
        require(campaign["state"] == "ready" or additional,
                "campaign interrupted; declare --additional-allowance to resume")
    elif additional:
        raise ValueError("additional allowance requires an existing campaign")
    work.mkdir(parents=True, exist_ok=True)
    allowance_pending = additional
    for mode in ("on", "off"):
        if mode in series["validations"]:
            continue
        output = work/("validation-"+mode)
        require(not output.exists(), "output already exists: "+str(output))
        command = [sys.executable, str(Path(__file__).with_name("megascene.py")), "--case", case,
                   "--preset", preset, "--seed", "45", "--threads", str(threads),
                   "--profile", "full", "--resolution", "1920x1080", "--calibration", mode,
                   "--validation-only", "--archive", str(archive), "--output", str(output)]
        if mode == "off":
            command += ["--runtime-from", series["validations"]["on"]["archive"]]
        if allowance_pending:
            command += ["--additional-allowance", str(allowance_pending)]
        result = subprocess.run(command, check=False)
        retained = _record(series_path, series, "validation", mode, output, result.returncode)
        require(read_json((retained/"validation.json").read_text())["status"] == "pass",
                "validation did not pass")
        allowance_pending = 0
    for index in range(len(series["controls"]), len(ORDER)):
        mode = ORDER[index]
        output = work/("control-"+str(index+1)+"-"+mode)
        require(not output.exists(), "output already exists: "+str(output))
        command = [sys.executable, str(Path(__file__).with_name("megascene.py")), "--case", case,
                   "--preset", preset, "--seed", "45", "--threads", str(threads),
                   "--profile", "full", "--resolution", "1920x1080", "--calibration", mode,
                   "--validated", series["validations"][mode]["archive"],
                   "--calibration-peer-validation", series["validations"]["off" if mode == "on" else "on"]["archive"],
                   "--archive", str(archive), "--output", str(output)]
        if allowance_pending:
            command += ["--additional-allowance", str(allowance_pending)]
        result = subprocess.run(command, check=False)
        retained = _record(series_path, series, "control", mode, output, result.returncode)
        require(read_json((retained/"summary.json").read_text())["schedule_completion"]["status"] == "pass",
                "control did not complete")
        allowance_pending = 0
    result = write_assessment(series_path)
    series["status"] = result["status"]
    snapshot(series_path, series)
    return result


def _values(root, expected_scope, mode):
    manifest = read_json((root/"manifest.json").read_text())
    summary = read_json((root/"summary.json").read_text())
    validation = read_json((root/"validation.json").read_text())
    require(not manifest.get("synthetic") and not summary.get("synthetic"), "synthetic control")
    require(manifest["attempt_kind"] == "calibration_"+mode and
            scope(manifest["effective"]) == expected_scope, "control scope/mode mismatch")
    require(summary["attempt_id"] == manifest["attempt_id"] and
            summary["schedule_completion"]["status"] == "pass", "control incomplete")
    require(validation["status"] == "pass" and integer(validation["checked_frames"]) == 3721,
            "control lacks complete mode validation")
    require(summary["termination"]["cause"] == "normal_exit" and
            not summary.get("evidence_errors"), "control evidence/termination invalid")
    if mode == "off":
        require(summary["endpoint_agreement"]["status"] == "pass", "off endpoint evidence missing")
    else:
        require(summary["state_correctness"]["status"] == "pass", "on state evidence missing")
    frozen = read_json((root/"schedule.json").read_text())
    records, errors = read_stream(root/"reference.jsonl", manifest)
    require(not errors, "damaged common recorder: "+", ".join(errors))
    frames, _, edits = reference_sequence(records, frozen)
    ordinary = [integer(r["duration_ns"]) for r in frames if r["population"] == "ordinary"]
    accepted = [integer(r["duration_ns"]) for r in edits if r["accepted"]]
    measured = [r for r in frames if r["population"] not in ("startup", "warmup")]
    duration = integer(measured[-1]["end_ns"])-integer(measured[0]["begin_ns"]) if measured else 0
    sufficient = len(ordinary) >= MIN_ORDINARY and duration >= MIN_MEASURED_NS and (
        expected_scope["case"] != "history" or len(accepted) >= MIN_EDITS)
    require(summary["populations"]["ordinary"]["count"] == str(len(ordinary)) and
            summary["populations"]["ordinary"]["samples_ns"] == list(map(str,ordinary)),
            "ordinary samples differ from common recorder")
    reported_edits = summary.get("accepted_edits", summary["populations"].get("accepted_edits"))
    if expected_scope["case"] == "history":
        require(reported_edits["count"] == str(len(accepted)) and
                reported_edits["samples_ns"] == list(map(str,accepted)),
                "accepted-edit samples differ from common recorder")
    def percentile(values, rank):
        return sorted(values)[(len(values)*rank+99)//100-1] if values else None
    stats = {"ordinary_mean": Decimal(sum(ordinary))/len(ordinary) if ordinary else None,
             "ordinary_p95": percentile(ordinary,95), "ordinary_p99": percentile(ordinary,99)}
    exact = {"ordinary_mean": [sum(ordinary), len(ordinary)],
             "ordinary_p95": [stats["ordinary_p95"], 1],
             "ordinary_p99": [stats["ordinary_p99"], 1]}
    if expected_scope["case"] == "history":
        stats["accepted_edits_p95"] = percentile(accepted,95)
        exact["accepted_edits_p95"] = [stats["accepted_edits_p95"], 1]
    reported = {"ordinary_mean": summary["populations"]["ordinary"]["mean"],
                "ordinary_p95": summary["populations"]["ordinary"]["p95"],
                "ordinary_p99": summary["populations"]["ordinary"]["p99"]}
    if expected_scope["case"] == "history":
        reported["accepted_edits_p95"] = reported_edits["p95"]
    for name, value in stats.items():
        require(value is not None and reported[name] is not None and
                abs(Decimal(str(reported[name]))-Decimal(value)) <= Decimal("0.001"),
                "reported statistic differs from common recorder: "+name)
    return {"attempt_id": manifest["attempt_id"], "archive": str(root), "mode": mode,
            "ordinary_count": len(ordinary), "accepted_edit_count": len(accepted),
            "measured_duration_ns": duration, "sufficient": sufficient,
            "statistics": {k: float(v) for k,v in stats.items()}, "exact_statistics": exact}


def classify_statistic(name, controls):
    observations = [{"position": i+1, "mode": c["mode"], "attempt_id": c["attempt_id"],
                     "value_ns": c["statistics"][name], "ordinary_count": c["ordinary_count"],
                     "accepted_edit_count": c["accepted_edit_count"],
                     "measured_duration_ns": c["measured_duration_ns"]}
                    for i,c in enumerate(controls)]
    values = [Fraction(*c["exact_statistics"][name]) for c in controls]
    off = [values[i] for i in (0,3,4)]
    population_sufficient = all(c["sufficient"] for c in controls)
    valid_denominators = all(v > 0 for v in off)
    paired = [(values[0],values[1]), (values[3],values[2]), (values[4],values[5])]
    ratios = [float(on/off_value) for off_value,on in paired] if valid_denominators else []
    noise = float(max(off)/min(off)-1) if valid_denominators else None
    status = ("insufficient" if not population_sufficient or not valid_denominators else
              "noisy" if max(off)*20 > min(off)*21 else
              "failed" if any(on*20 > off_value*21 for off_value,on in paired) else "pass")
    reason = ("population below the required minimum" if not population_sufficient else
              "zero or invalid off denominator" if not valid_denominators else
              "off variation exceeds 5%" if status == "noisy" else
              "one or more paired increases exceed 5%" if status == "failed" else
              "all paired increases are at most 5%")
    return {"status": status, "observations": observations, "off_variation": noise,
            "paired_on_over_off": ratios, "max_paired_on_over_off": max(ratios) if ratios else None,
            "population_sufficient": population_sufficient,
            "valid_denominators": valid_denominators, "threshold": 0.05, "reason": reason}


def assess(series_path):
    series = read_json(series_path.read_text())
    require(series["schema"] == SCHEMA and series["order"] == list(ORDER), "unsupported series")
    require(series["scope"] in [scope(c) for c in matrix()], "series outside accepted calibration matrix")
    controls = series["controls"]
    require(len(controls) <= 6 and all(item["mode"] == ORDER[i] for i,item in enumerate(controls)),
            "control order mismatch")
    report = {"schema": SCHEMA, "record_type": "calibration_assessment",
              "scope": series["scope"], "order": list(ORDER), "status": "insufficient",
              "control_count": len(controls), "controls": [], "pairs": [], "statistics": {},
              "on_acceptance_candidates": [],
              "reference": str(series_path), "qualification_scope": "exact tested configuration only",
              "transient_off_state_equality": "unproven", "cost_subtraction": False}
    try:
        for mode in ("on", "off"):
            run = series["validations"].get(mode)
            require(run is not None, "missing "+mode+" mode validation")
            require(run["returncode"] == 0 and run["archive"], "missing mode validation")
            root = Path(run["archive"])
            manifest = read_json((root/"manifest.json").read_text())
            validation_summary = read_json((root/"summary.json").read_text())
            require(not manifest.get("synthetic") and manifest["attempt_kind"] == "calibration_"+mode and
                    validation_summary["attempt_kind"] == "validation_only" and
                    manifest["effective"]["calibration_mode"] == mode and
                    scope(manifest["effective"]) == series["scope"], "mode validation scope mismatch")
            from megascene_checkpoints import applicable, identity, verify_evidence
            verify_evidence(manifest,root,{"validation.json","validation/summary.json",
                                           "validation/comparison.json"})
            validation = read_json((root/"validation.json").read_text())
            applicable(validation,identity(manifest,root,manifest["effective"]))
            require(validation["status"] == "pass" and integer(validation["checked_frames"]) == 3721,
                    "incomplete mode validation")
        for index, item in enumerate(controls):
            require(item["returncode"] == 0 and item["archive"], "failed control")
            value = _values(Path(item["archive"]), series["scope"], ORDER[index])
            report["controls"].append(value)
            if ORDER[index] == "on":
                report["on_acceptance_candidates"].append({"attempt_id": value["attempt_id"],
                    "archive": value["archive"],
                    "scope": "complete instrumented observation; separate acceptance gates still apply"})
        for first in (0, 2, 4):
            if len(controls) <= first+1:
                break
            off_index = first if ORDER[first] == "off" else first+1
            on_index = first+1 if ORDER[first] == "off" else first
            pair = compare_modes(controls[off_index]["archive"], controls[on_index]["archive"])
            require(pair["status"] == "pass", "paired equivalence evidence unavailable")
            report["pairs"].append({"positions": [first+1, first+2],
                                    "off_attempt_id": pair["off"], "on_attempt_id": pair["on"],
                                    "endpoint_and_action_agreement": "pass"})
    except (OSError, KeyError, ValueError, TypeError, IndexError) as exc:
        report["reason"] = str(exc)
        return report
    if len(report["pairs"]) != 3:
        report["reason"] = "six complete controls and three equivalent pairs required"
        return report
    states = []
    for name in STATISTICS[:3] if series["scope"]["case"] == "static" else STATISTICS:
        result = classify_statistic(name, report["controls"])
        report["statistics"][name] = result
        states.append(result["status"])
    report["status"] = ("insufficient" if "insufficient" in states else "noisy" if "noisy" in states else
                        "failed" if "failed" in states else "pass")
    report["reason"] = {"pass":"all applicable pairs within the accepted bound",
                        "noisy":"off controls vary by more than 5%",
                        "failed":"at least one paired increase exceeds 5%",
                        "insufficient":"required population or denominator missing"}[report["status"]]
    return report


def write_assessment(series_path):
    result = assess(series_path)
    assessment_path = series_path.with_name("assessment.json")
    snapshot(assessment_path,result)
    snapshot(series_path.with_name("calibration.json"),{"schema":SCHEMA,
        "record_type":"calibration", "status":result["status"], "scope":result["scope"],
        "reference":str(assessment_path)})
    return result


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("command", choices=("plan", "run", "assess"))
    p.add_argument("--archive")
    p.add_argument("--work")
    p.add_argument("--case", choices=("static", "history"))
    p.add_argument("--preset", choices=("small", "large"))
    p.add_argument("--threads", type=int, choices=(1,6,12))
    p.add_argument("--series")
    p.add_argument("--additional-allowance", type=int, default=0)
    args = p.parse_args(argv)
    if args.command == "plan":
        result = plan()
    elif args.command == "assess":
        require(args.series, "--series required")
        result = write_assessment(Path(args.series).expanduser().resolve())
    else:
        require(all((args.archive,args.work,args.case,args.preset,args.threads)),
                "run requires --archive, --work, --case, --preset and --threads")
        require(0 <= args.additional_allowance <= 86400, "additional allowance out of range")
        result = run_series(Path(args.archive).expanduser().resolve(), Path(args.work).expanduser().resolve(),
                            args.case,args.preset,args.threads,args.additional_allowance)
    print(json.dumps(result,sort_keys=True,indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(2)
