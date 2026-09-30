"""Diagnostic on/off evidence; an off control never qualifies an endpoint."""
import argparse
import math
from pathlib import Path

from megascene_inventory import SCHEMA, integer, measurement, outcome, read_json, require
from megascene_report import distribution, read_stream

DISABLED = ("intermediate_checkpoints", "detailed_inventory_transitions", "stage_timing",
            "gpu_queries", "ordinary_logging")


def verify_peer_validation(config, manifest, archive):
    """Require a separate opposite-mode replay before a complete control."""
    from megascene_checkpoints import applicable, identity, verify_evidence
    from megascene_validation import verify_host_artifacts
    peer = Path(config["calibration_peer_validation"]).expanduser().resolve()
    peer_manifest = read_json((peer/"manifest.json").read_text())
    peer_config = peer_manifest["effective"]
    require(peer_config["calibration_mode"] == ("on" if config["calibration_mode"] == "off" else "off"),
            "peer validation mode mismatch")
    keys = ("case", "preset", "seed", "threads", "resolution", "profile", "schedule", "warmup", "frames", "fragment_budget")
    require(all(peer_config[k] == config[k] for k in keys), "peer validation workload mismatch")
    peer_identity = identity(peer_manifest,peer,peer_config)
    own_identity = identity(manifest,archive,config)
    require(peer_identity["artifacts"] == own_identity["artifacts"], "peer validation runtime artifacts differ")
    required = {"validation.json"} | {a["path"] for a in peer_manifest.get("evidence",[])
                                      if a["path"].startswith("validation/")}
    require(any(p.startswith("validation/") for p in required), "peer validation archive incomplete")
    verify_evidence(peer_manifest,peer,required)
    validation = read_json((peer/"validation.json").read_text())
    applicable(validation,peer_identity)
    verify_host_artifacts(validation)
    require(integer(validation["checked_frames"]) == 1+integer(config["warmup"])+integer(config["frames"]),
            "peer validation replay incomplete")
    return {"status":"pass", "mode":peer_config["calibration_mode"], "source":str(peer),
            "validation_attempt_id":validation["attempt_id"]}


def reference_sequence(records, frozen):
    """Check the common recorder without borrowing any detailed CPU records."""
    frames = [r for r in records if r["record_type"] == "frame"]
    actions = [r for r in records if r["record_type"] == "action"]
    begins = [r for r in records if r["record_type"] == "edit_begin"]
    edits = [r for r in records if r["record_type"] == "edit"]
    require(len(frames) == len(frozen["frames"]), "incomplete common frame recorder")
    for index, row in enumerate(frames):
        require(row["frame"] == str(index) and row["population"] == frozen["frames"][index]["phase"],
                "common recorder frame/population mismatch")
        begin, end = integer(row["begin_ns"]), integer(row["end_ns"])
        require(begin <= end and integer(row["duration_ns"]) == end-begin,
                "common recorder frame interval mismatch")
        if index:
            require(row["begin_ns"] == frames[index-1]["end_ns"], "common frame boundary gap")
    planned = frozen["actions"]
    require(len(actions) == len(begins) == len(edits) == len(planned), "common action outcome missing")
    for planned_action, begin, action, edit in zip(planned, begins, actions, edits):
        expected = (planned_action["action"], planned_action["frame"])
        require((action["action"], action["frame"]) == expected and
                (begin["action"], begin["frame"]) == expected and
                (edit["action"], edit["frame"]) == expected, "common action identity mismatch")
        require(action["accepted"] is True and action["removed_cells"] == planned_action["expected_removed_cells"] and
                action["outcome"]["target_m"] == planned_action["target_m"] and
                edit["accepted"] is True and edit["removed_cells"] == action["removed_cells"],
                "common scalar action outcome mismatch")
        require(integer(begin["begin_ns"]) <= integer(edit["end_ns"]) and
                integer(edit["duration_ns"]) == integer(edit["end_ns"])-integer(edit["begin_ns"]),
                "common edit interval mismatch")
    return frames, actions, edits


def off_result(config, archive, manifest, validation, supervised, cpu, problems):
    """Read an actual off execution. Equality is deliberately limited to endpoints."""
    frozen = read_json((archive/"schedule.json").read_text())
    reference, ref_errors = read_stream(archive/"reference.jsonl", manifest)
    resource, resource_errors = read_stream(archive/"resources.jsonl", manifest)
    allocations, allocation_errors = read_stream(archive/"allocations.jsonl", manifest)
    errors = list(problems)+ref_errors+resource_errors+allocation_errors
    if manifest.get("evidence"):
        try:
            from megascene_checkpoints import verify_evidence
            verify_evidence(manifest, archive, {"summary.json", "validation.json", "cpu.jsonl",
                "reference.jsonl", "resources.jsonl", "allocations.jsonl", "supervision.json"})
        except (ValueError, KeyError, OSError) as exc:
            errors.append(str(exc))
    checkpoints = [r for r in cpu if r["record_type"] == "checkpoint"]
    forbidden = {"frame", "stage", "edit", "action", "static_audit", "native_audit", "render_work", "body_motion"}
    if any(r["record_type"] in forbidden for r in cpu):
        errors.append("disabled detailed field present in off stream")
    if any(r["record_type"] not in {"worker_start", "checkpoint", "complete", "window_closed"} for r in cpu):
        errors.append("unexpected off stream record")
    frames = [r for r in reference if r.get("record_type") == "frame"]
    actions = [r for r in reference if r.get("record_type") == "action"]
    edits = [r for r in reference if r.get("record_type") == "edit"]
    try:
        reference_sequence(reference, frozen)
        require(len(checkpoints) == 2 and [r["frame"] for r in checkpoints] ==
                ["0", str(len(frozen["frames"])-1)], "off endpoint checkpoints missing or duplicated")
        require(integer(checkpoints[0]["time_ns"]) <= integer(frames[0]["end_ns"]) and
                integer(checkpoints[1]["time_ns"]) >= integer(frames[-1]["end_ns"]),
                "off endpoint checkpoint timing invalid")
        require([r["names"] for r in checkpoints] ==
                [["initialization", "review_opening"], ["completion"]], "off endpoint names mismatch")
        require(len([r for r in cpu if r["record_type"] == "complete"]) == 1 and
                cpu[-1]["record_type"] == "complete", "off completion marker missing")
        require(integer(supervised["reference_records"]) == len(reference) and
                integer(supervised["shared_committed_slots"]) == len(reference) and
                integer(supervised["shared_header_records"]) == len(reference),
                "lost common recorder records")
        require(supervised["termination"]["cause"] == "normal_exit" and not supervised["errors"] and
                resource and allocations and supervised["allocation_ledger"] is not None,
                "mandatory supervision/accounting incomplete")
        require(not (archive/"gpu.jsonl").exists() or not (archive/"gpu.jsonl").stat().st_size,
                "GPU query evidence unexpectedly enabled in off control")
        require(validation is not None and validation["status"] == "pass" and
                integer(validation["checked_frames"]) == len(frozen["frames"]),
                "separate complete off validation unavailable")
        catalog = {row["name"]: row for row in validation["checkpoints"]}
        for row, name in zip(checkpoints, ("initialization", "completion")):
            require(row["sha256"] == catalog[name]["sha256"] and
                    row["body_sha256"] == catalog[name]["body_sha256"],
                    "off endpoint differs from complete validation: "+name)
    except (ValueError, KeyError, TypeError, IndexError) as exc:
        errors.append(str(exc))
    try:
        ordinary = [integer(r["duration_ns"]) for r in frames if r["population"] == "ordinary"]
        accepted = [integer(r["duration_ns"]) for r in edits if r["accepted"]]
    except (ValueError, KeyError, TypeError) as exc:
        errors.append("damaged common duration: "+str(exc))
        ordinary, accepted = [], []
    complete = not errors
    result = {"schema": SCHEMA, "record_type": "summary", "attempt_id": manifest["attempt_id"],
              "attempt_kind": "calibration_off", "synthetic": manifest.get("synthetic", False),
              "qualification": "diagnostic_control_only", "termination": supervised["termination"],
              "supervision": supervised, "evidence_errors": errors,
              "disabled_evidence": {name: measurement("disabled", "accepted calibration-off protocol", name,
                  "ns" if name in ("stage_timing", "gpu_queries") else "records") for name in DISABLED},
              "equality_limit": "Initial/final and scalar action evidence cannot establish transient state equality.",
              "endpoint_agreement": outcome("pass" if complete else "inconclusive",
                  "initial/final canonical digests and scalar outcomes agree with separate complete off validation" if complete else
                  "endpoint or common evidence incomplete", config["schedule"], ["validation.json", "cpu.jsonl", "reference.jsonl"]),
              "schedule_completion": outcome("pass" if complete else "inconclusive",
                  "common frame/action sequence complete" if complete else "off control invalid", config["schedule"], ["reference.jsonl"]),
              "state_correctness": outcome("inconclusive", "actual off control omits intermediate checkpoints", config["schedule"]),
              "rendering_correctness": outcome("inconclusive", "actual off control omits detailed native audits", config["profile"]),
              "visual_quality": outcome("inconclusive", "off control cannot qualify visual quality", config["profile"]),
              "calibration": outcome("inconclusive", "off control cannot qualify performance alone", config["schedule"]),
              "gpu_execution": {"capability": measurement("disabled", "GPU queries disabled by calibration-off protocol",
                  "submitted work", "ns"), "required_evidence_complete": False},
              "measurement_availability": {"reference": outcome("pass" if complete else "inconclusive",
                  "common preallocated recorder retained" if complete else "common recorder incomplete", "frame/edit boundaries", ["reference.jsonl"]),
                  "gpu": outcome("not_applicable", "GPU queries disabled by calibration-off protocol", "GPU intervals"),
                  "resources": outcome("pass" if resource and allocations and not resource_errors and not allocation_errors else "inconclusive",
                  "mandatory resource/allocation evidence", "attempt", ["resources.jsonl", "allocations.jsonl"])},
              "qualified_capacity": outcome("inconclusive", "calibration-off controls cannot enter capacity endpoints", config["schedule"]),
              "interactive_pass": outcome("inconclusive", "calibration-off controls cannot enter interactive endpoints", config["schedule"]),
              "endpoint_eligible": outcome("inconclusive", "calibration-off control is diagnostic only", config["schedule"]),
              "populations": {"ordinary": distribution(ordinary), "accepted_edits": distribution(accepted)},
              "completed_prefix": {"startup": bool(frames), "warmup": str(sum(r["population"] == "warmup" for r in frames)),
                                   "measured": str(sum(r["population"] in ("ordinary", "edit", "motion") for r in frames))},
              "raw_evidence": {"reference": "reference.jsonl", "endpoints": "cpu.jsonl", "resources": "resources.jsonl",
                               "allocations": "allocations.jsonl"}}
    from megascene_performance import enabled
    if enabled(config):
        result['populations'].update({name:distribution(integer(r['duration_ns']) for r in frames if r['population']==name)
                                     for name in ('edit','motion','warmup')})
        measured=[r for r in frames if r['population'] not in ('startup','warmup')]
        result['populations']['combined']=distribution(integer(r['duration_ns']) for r in measured)
        result['measured_interval_ns']=str(integer(measured[-1]['end_ns'])-integer(measured[0]['begin_ns'])) if measured else '0'
    return result


def compare_modes(off_path, on_path):
    """Read-only paired control comparison; no benchmark qualification is inferred."""
    off_path, on_path = Path(off_path), Path(on_path)
    off_manifest, on_manifest = (read_json((p/"manifest.json").read_text()) for p in (off_path,on_path))
    require(off_manifest["attempt_kind"] == "calibration_off" and on_manifest["attempt_kind"] == "calibration_on",
            "paired attempt kinds must be calibration_off and calibration_on")
    from megascene_checkpoints import identity, verify_evidence
    for root, manifest in ((off_path,off_manifest),(on_path,on_manifest)):
        identity(manifest,root,manifest["effective"])
        verify_evidence(manifest,root,{"summary.json","validation.json","cpu.jsonl","reference.jsonl",
                                      "resources.jsonl","allocations.jsonl","supervision.json"})
    keys = ("case", "preset", "seed", "threads", "resolution", "profile", "schedule", "warmup", "frames", "fragment_budget")
    require(all(off_manifest["effective"][k] == on_manifest["effective"][k] for k in keys), "paired workloads differ")
    require({a["path"]:a["sha256"] for a in off_manifest["artifacts"]} ==
            {a["path"]:a["sha256"] for a in on_manifest["artifacts"]}, "paired runtime artifacts differ")
    off_summary, on_summary = (read_json((p/"summary.json").read_text()) for p in (off_path,on_path))
    require(off_summary["endpoint_agreement"]["status"] == "pass" and
            on_summary["state_correctness"]["status"] == "pass", "paired evidence incomplete")
    off_ref, off_errors = read_stream(off_path/"reference.jsonl",off_manifest)
    on_ref, on_errors = read_stream(on_path/"reference.jsonl",on_manifest)
    require(not off_errors and not on_errors, "paired reference stream damaged")
    def scalar(rows):
        return [(r["frame"],r["action"],r["accepted"],r["removed_cells"],r["outcome"])
                for r in rows if r["record_type"] == "action"]
    require(scalar(off_ref) == scalar(on_ref), "paired scalar action outcomes differ")
    off_cpu, off_cpu_errors = read_stream(off_path/"cpu.jsonl",off_manifest)
    on_cpu, on_cpu_errors = read_stream(on_path/"cpu.jsonl",on_manifest)
    require(not off_cpu_errors and not on_cpu_errors, "paired endpoint stream damaged")
    endpoint = lambda rows: [(r["frame"],r["sha256"],r["body_sha256"]) for r in rows
                             if r["record_type"] == "checkpoint" and r["frame"] in
                             ("0",str(1+integer(off_manifest["effective"]["warmup"])+integer(off_manifest["effective"]["frames"])-1))]
    require(endpoint(off_cpu) == endpoint(on_cpu), "paired initial/final canonical states differ")
    statistics = {}
    for population, field in (("ordinary", "mean"), ("ordinary", "p95"),
                              ("ordinary", "p99"), ("accepted_edits", "p95")):
        if population == "accepted_edits" and off_manifest["effective"]["case"] != "history":
            continue
        def distribution_for(summary):
            return (summary["populations"]["ordinary"] if population == "ordinary" else
                    summary.get("accepted_edits", summary["populations"].get("accepted_edits")))
        off_values, on_values = distribution_for(off_summary), distribution_for(on_summary)
        off_value, on_value = off_values[field], on_values[field]
        require(off_value is None or type(off_value) in (int,float) and math.isfinite(off_value) and off_value >= 0,
                "invalid off statistic")
        require(on_value is None or type(on_value) in (int,float) and math.isfinite(on_value) and on_value >= 0,
                "invalid on statistic")
        statistics[population+"_"+field] = {"off_ns":off_value, "on_ns":on_value,
            "off_count":off_values["count"], "on_count":on_values["count"],
            "on_over_off":on_value/off_value if off_value and on_value is not None else None}
    return {"schema": SCHEMA, "record_type": "calibration_pair", "status": "pass", "off": off_manifest["attempt_id"],
            "on": on_manifest["attempt_id"], "scope": "initial/final canonical state and scalar action outcomes only",
            "transient_state_equality": "unproven", "benchmark_qualification": "not_applicable",
            "observed_statistics": statistics, "statistics_scope": "descriptive paired values; no cost subtraction or calibration pass"}


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--off", required=True)
    p.add_argument("--on", required=True)
    args = p.parse_args()
    import json
    print(json.dumps(compare_modes(args.off,args.on),sort_keys=True))
