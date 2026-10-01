#!/usr/bin/env python3
"""Run and assess the bounded, ordered Megascene calibration controls."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from megascene_evidence import run as _run
from megascene import snapshot
from megascene_calibration import compare_modes, reference_sequence
from megascene_inventory import SCHEMA, read_json, require
from megascene_report import read_stream

ORDER = ("off", "on", "on", "off", "off", "on")
STATISTICS = ("ordinary_mean", "ordinary_p95", "ordinary_p99", "accepted_edits_p95")
MIN_ORDINARY = 1000
MIN_MEASURED_NS = 10_000_000_000
MIN_EDITS = 100


def _policy(operation, payload):
    return _run(operation, payload, module="evidence_calibration")


def matrix(protocol="legacy"):
    return _policy("plan", protocol)["configurations"]


def plan(protocol="legacy"):
    return _policy("plan", protocol)


def scope(config):
    return _policy("scope", config)


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
    from megascene_performance import enabled
    if enabled(series['scope']) and archive is not None:
        try:
            bound = _policy("series_runtime_prepare", {"series": series, "manifest": manifest})
            if bound["new_binding"]:
                series["runtime_artifacts"] = bound["series"]["runtime_artifacts"]
                bound = _policy("series_runtime_schedule", series)
                series["schedule_sha256"] = bound["schedule_sha256"]
        except (ValueError,KeyError,TypeError) as exc:
            item['binding_error']=str(exc)
            snapshot(path,series)
            raise
        snapshot(path,series)
    _policy("record_status", {"returncode": returncode, "archive": archive, "output": str(output)})
    return Path(archive)


def run_series(archive, work, case, preset, threads, additional=0, protocol="legacy", series_path=None):
    config = _policy("series_configuration", {"protocol": protocol, "case": case,
                                              "preset": preset, "threads": str(threads)})
    require(archive.is_absolute() and work.is_absolute(), "archive and work paths must be absolute")
    require(archive != work and archive not in work.parents and work not in archive.parents,
            "archive and work must be separate")
    series_root = (archive/("calibration-series-v2" if protocol=="performance-v2" else "calibration-series")/(case+"-"+preset+"-"+str(threads))).resolve()
    if series_path is None:
        series_path = series_root/"series.json"
    else:
        require(series_path.is_absolute(), "explicit series must stay inside this performance configuration namespace")
        series_path = series_path.resolve()
        require(protocol == "performance-v2" and
                series_path.name == "series.json" and series_root in series_path.parents,
                "explicit series must stay inside this performance configuration namespace")
    series_path.parent.mkdir(parents=True, exist_ok=True)
    resuming = series_path.exists()
    if resuming:
        series = read_json(series_path.read_text())
        _policy("series_resume", {"series": series, "config": config})
    else:
        series = {"schema": SCHEMA, "record_type": "calibration_series", "scope": scope(config),
                  "order": list(ORDER), "validations": {}, "controls": [], "runs": [],
                  "archive_root": str(archive), "work_root": str(work), "status": "incomplete"}
        if protocol=="performance-v2": series['protocol']=protocol
        snapshot(series_path, series)
    _policy("series_roots", {"series": series, "archive": str(archive), "work": str(work)})
    if len(series["controls"]) == 6:
        return write_assessment(series_path)
    _policy("series_continuation", {"resuming": resuming, "additional": additional})
    campaign_file = archive/"campaign.json"
    if campaign_file.exists():
        campaign = read_json(campaign_file.read_text())
        _policy("campaign_continuation", {"exists": True, "campaign": campaign, "additional": additional})
    else:
        _policy("campaign_continuation", {"exists": False, "additional": additional})
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
        if protocol=="performance-v2": command += ['--schedule',config['schedule']]
        if mode == "off":
            command += ["--runtime-from", series["validations"]["on"]["archive"]]
        if allowance_pending:
            command += ["--additional-allowance", str(allowance_pending)]
        result = subprocess.run(command, check=False)
        retained = _record(series_path, series, "validation", mode, output, result.returncode)
        _policy("run_evidence", {"evidence": read_json((retained/"validation.json").read_text()),
                                 "reason": "validation did not pass"})
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
        if protocol=="performance-v2": command += ['--schedule',config['schedule']]
        if allowance_pending:
            command += ["--additional-allowance", str(allowance_pending)]
        result = subprocess.run(command, check=False)
        retained = _record(series_path, series, "control", mode, output, result.returncode)
        _policy("run_evidence", {"evidence": read_json((retained/"summary.json").read_text())["schedule_completion"],
                                 "reason": "control did not complete"})
        allowance_pending = 0
    result = write_assessment(series_path)
    series["status"] = result["status"]
    snapshot(series_path, series)
    return result


def _values(root, expected_scope, mode):
    request = {"manifest": read_json((root / "manifest.json").read_text()),
               "summary": read_json((root / "summary.json").read_text()),
               "validation": read_json((root / "validation.json").read_text()),
               "scope": expected_scope, "mode": mode, "archive": str(root)}
    _policy("values_header", request)
    request["frozen"] = read_json((root / "schedule.json").read_text())
    request["records"], request["errors"] = read_stream(root / "reference.jsonl", request["manifest"])
    return _policy("values", request)


def classify_statistic(name, controls):
    return _policy("classify_statistic", {"name": name, "controls": controls})


def assess(series_path):
    from megascene_checkpoints import applicable, identity, verify_evidence
    series = read_json(series_path.read_text())
    report = _policy("assessment_start", {"series": series, "path": str(series_path)})
    controls = series["controls"]
    try:
        for mode in ("on", "off"):
            run = series["validations"].get(mode)
            _policy("validation_run", {"run": run, "mode": mode})
            root = Path(run["archive"])
            manifest = read_json((root / "manifest.json").read_text())
            validation_summary = read_json((root / "summary.json").read_text())
            _policy("mode_scope", {"series": series, "manifest": manifest,
                                   "summary": validation_summary, "mode": mode})
            verify_evidence(manifest, root, {"validation.json", "validation/summary.json",
                                            "validation/comparison.json"})
            validation = read_json((root / "validation.json").read_text())
            applicable(validation, identity(manifest, root, manifest["effective"]))
            _policy("mode_validation", {"series": series, "manifest": manifest,
                 "summary": validation_summary, "validation": validation, "mode": mode})
        for index, item in enumerate(controls):
            _policy("control_entry", item)
            value = _values(Path(item["archive"]), series["scope"], ORDER[index])
            report = _policy("append_control", {"report": report, "value": value})
            binding = None
            if series.get("protocol", "legacy") == "performance-v2":
                manifest = read_json((Path(item["archive"]) / "manifest.json").read_text())
                binding = {"artifacts": {a["path"]: a["sha256"] for a in manifest["artifacts"]}}
            report = _policy("report_control", {"report": report, "value": value, "binding": binding})
        for pair_indices in _policy("pair_indices", controls):
            pair = compare_modes(controls[pair_indices["off"]]["archive"],
                                 controls[pair_indices["on"]]["archive"])
            report = _policy("pair_record", {"report": report, "pair": pair,
                                             "positions": pair_indices["positions"]})
    except (OSError, KeyError, ValueError, TypeError, IndexError) as exc:
        report["reason"] = str(exc)
        return report
    return _policy("assessment_finish", report)


def write_assessment(series_path):
    result = assess(series_path)
    assessment_path = series_path.with_name("assessment.json")
    snapshot(assessment_path,result)
    calibration={"schema":SCHEMA,
        "record_type":"calibration", "status":result["status"], "scope":result["scope"],
        "reference":str(assessment_path)}
    if 'binding' in result:
        calibration['binding']=result['binding']
        calibration['reference_sha256']=hashlib.sha256(assessment_path.read_bytes()).hexdigest()
    snapshot(series_path.with_name("calibration.json"),calibration)
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
    p.add_argument("--protocol",choices=("legacy","performance-v2"),default="legacy")
    args = p.parse_args(argv)
    if args.command == "plan":
        result = plan(args.protocol)
    elif args.command == "assess":
        require(args.series, "--series required")
        result = write_assessment(Path(args.series).expanduser().resolve())
    else:
        require(all((args.archive,args.work,args.case,args.preset,args.threads)),
                "run requires --archive, --work, --case, --preset and --threads")
        require(0 <= args.additional_allowance <= 86400, "additional allowance out of range")
        result = run_series(Path(args.archive).expanduser().resolve(), Path(args.work).expanduser().resolve(),
                            args.case,args.preset,args.threads,args.additional_allowance,args.protocol,
                            Path(args.series).expanduser().resolve() if args.series else None)
    print(json.dumps(result,sort_keys=True,indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(2)
