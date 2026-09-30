#!/usr/bin/env python3
"""Classify a retained Megascene attempt from its raw evidence.

This reader never combines attempts or promotes an observation to an endpoint.
It can be called by the runner after validation/review, or directly on an
archived attempt with ``--bundle``. Synthetic bundles remain synthetic.
"""
import argparse
import math
from pathlib import Path

from megascene_inventory import SCHEMA, integer, outcome, read_json, require

SCOPE_KEYS = ("case", "preset", "seed", "threads", "resolution", "profile",
              "schedule", "diagnostic", "control", "fragment_budget")
CALIBRATION_STATES = {"pass", "not_executed", "insufficient", "noisy", "failed", "inapplicable"}
RESERVE_CAUSES = {"process_rss_reserve", "available_ram_reserve", "device_free_reserve", "heap_budget_reserve"}


def distribution(values):
    """Nearest-rank percentiles over exact integer nanoseconds."""
    values = list(values)
    if not values:
        return {"count": "0", "unit": "ns", "samples_ns": [], "observation_interval_ns":"0",
                **{name: None for name in ("mean", "p50", "p95", "p99", "max")}}
    ordered = sorted(values)
    return {"count": str(len(values)), "unit": "ns", "samples_ns": list(map(str, values)),
            "observation_interval_ns":str(sum(values)),
            "mean": sum(values)/len(values),
            **{f"p{p}": ordered[math.ceil(len(values)*p/100)-1] for p in (50, 95, 99)},
            "max": ordered[-1]}


def checked_object(value, kind):
    require(isinstance(value, dict) and value.get("schema") == SCHEMA, "unsupported "+kind+" schema")
    extensions = value.get("extensions", {})
    require(isinstance(extensions, dict) and not (extensions.keys() & (value.keys()-{"extensions"})),
            kind+" extension overrides a required field")
    return value


def read_stream(path, manifest):
    """Return the valid committed prefix and every detected stream problem."""
    if not path.is_file():
        return [], [path.name+" missing"]
    records, errors, last_time = [], [], None
    for raw in path.read_bytes().splitlines(keepends=True):
        try:
            require(raw.endswith(b"\n"), "truncated "+path.name+" tail")
            r = checked_object(read_json(raw.decode("utf-8")), path.name)
            require(all(r.get(k) == manifest[k] for k in ("attempt_id", "series_id", "campaign_id")),
                    path.name+" identity mismatch")
            require(integer(r["sequence"]) == len(records), path.name+" sequence gap or duplicate")
            require(r["clock_id"] == "linux.CLOCK_MONOTONIC", path.name+" clock mismatch")
            now = integer(r["time_ns"])
            require(last_time is None or now >= last_time, path.name+" time regressed")
            if path.name == "cpu.jsonl" and r["record_type"] in ("frame", "stage", "edit"):
                begin, end = integer(r["begin_ns"]), integer(r["end_ns"])
                require(begin <= end <= now and integer(r["duration_ns"]) == end-begin and
                        r["status"] == "measured" and r["unit"] == "ns", "invalid CPU interval")
            if path.name == "resources.jsonl" and r.get("status") == "measured":
                begin, end = integer(r["sample_begin_ns"]), integer(r["sample_end_ns"])
                require(begin <= end <= now and r["unit"] == "bytes", "invalid resource sample boundary/unit")
                for field in ("rss_bytes","available_ram_bytes","device_free_bytes"):
                    if field in r: integer(r[field])
                for heap in r.get("heaps",[]):
                    integer(heap["heap"]); integer(heap["usage_bytes"]); integer(heap["budget_bytes"])
            last_time = now
            records.append(r)
        except (ValueError, KeyError, TypeError, UnicodeError) as exc:
            errors.append(str(exc))
            break
    return records, errors


def calibration_result(value, config, attempt_kind):
    if attempt_kind == "calibration_off":
        result = outcome("inconclusive", "calibration-off control cannot qualify a benchmark endpoint", "performance calibration")
        result.update(calibration_status="inapplicable",reference=None,configuration_scope=None)
        return result
    if value is None:
        result = outcome("inconclusive", "calibration not executed", "performance calibration")
        result.update(calibration_status="not_executed",reference=None,configuration_scope=None)
        return result
    checked_object(value,"calibration")
    require(isinstance(value, dict) and value.get("status") in CALIBRATION_STATES,
            "invalid calibration status")
    state = value["status"]
    scope, reference = value.get("scope"), value.get("reference")
    from megascene_performance import scope_keys
    keys=scope_keys(config)
    require(isinstance(scope, dict) and all(k in scope for k in keys), "calibration scope incomplete")
    require(reference is None or isinstance(reference, str) and reference, "invalid calibration reference")
    applicable = all(scope[k] == config.get(k) for k in keys)
    if state == "pass":
        require(reference and applicable, "passing calibration lacks matching scope/reference")
    reason = {"pass":"applicable calibration passed", "not_executed":"calibration not executed",
              "insufficient":"calibration populations insufficient", "noisy":"calibration controls too noisy",
              "failed":"calibration overhead failed", "inapplicable":"calibration does not cover this configuration"}[state]
    if not applicable:
        reason = "calibration scope does not match this configuration"
    result = outcome("pass" if state == "pass" and applicable else
                     "fail" if state == "failed" and applicable else
                     "not_applicable" if state == "inapplicable" or not applicable else "inconclusive", reason,
                     "performance calibration", [reference] if reference else [])
    result.update(calibration_status=state, reference=reference, configuration_scope=scope)
    return result


def _gate(status, reason, scope, evidence=()):
    return outcome(status, reason, scope, evidence)


def classify(summary, manifest, cpu, cpu_errors=(), gpu_errors=(), resources=(), resource_errors=(),
             allocations=(), allocation_errors=(), reference=(), reference_errors=(),
             validation=None, review=None, calibration=None, comparison=None, schedule=None):
    """Calculate independent attempt outcomes from one attempt's raw records."""
    checked_object(manifest, "manifest")
    checked_object(summary, "summary")
    require(manifest["record_type"] == "manifest" and summary["record_type"] == "summary" and
            manifest["attempt_id"] == summary["attempt_id"], "manifest/summary identity mismatch")
    config = manifest["effective"]
    from megascene_performance import enabled, validate
    performance=enabled(config)
    require(isinstance(config, dict), "missing effective configuration")
    result = dict(summary)
    result["synthetic"] = bool(manifest.get("synthetic") or summary.get("synthetic"))
    result["attempt_kind"] = manifest["attempt_kind"]
    errors = list(cpu_errors)+list(resource_errors)+list(allocation_errors)+list(reference_errors)
    initial_error_count = len(errors)
    if performance:
        try:
            require(schedule is not None, "performance frozen schedule unavailable")
            validate(schedule)
        except (ValueError, KeyError, TypeError) as exc:
            errors.append(str(exc))
    frames = [r for r in cpu if r["record_type"] == "frame"]
    edits = [r for r in cpu if r["record_type"] == "edit"]
    actions = [r for r in cpu if r["record_type"] == "action"]
    warmup, measured = integer(config["warmup"]), integer(config["frames"])
    valid_frames = []
    for i, frame in enumerate(frames):
        try:
            require(i <= warmup+measured, "extra CPU frames")
            require(integer(frame["frame"]) == i, "CPU frame gap or duplicate")
            expected = "startup" if i == 0 else "warmup" if i <= warmup else None
            if performance and schedule and i<len(schedule['frames']):
                expected=schedule['frames'][i]['phase']
            if expected is not None:
                require(frame["population"] == expected, "CPU frame population mismatch")
            require(frame["population"] in {"startup", "warmup", "ordinary", "edit", "motion"},
                    "unknown CPU population")
            begin, end = integer(frame["begin_ns"]), integer(frame["end_ns"])
            require(end >= begin and integer(frame["duration_ns"]) == end-begin and frame["unit"] == "ns" and
                    frame["status"] == "measured", "invalid CPU interval")
            if i:
                require(begin == integer(frames[i-1]["end_ns"]), "CPU frame boundary gap")
            valid_frames.append(frame)
        except (ValueError, KeyError, TypeError) as exc:
            errors.append(str(exc)); break
    frames = valid_frames
    valid_edits = []
    try:
        # An edit response is tied to a unique action. A rejected action may
        # retain its interval but never counts toward the accepted population.
        seen = set()
        for edit in edits:
            key = edit["action"]
            require(key not in seen, "duplicate edit response")
            seen.add(key)
            require(type(edit["accepted"]) is bool and integer(edit["frame"]) <= warmup+measured,
                    "invalid edit association")
            require(integer(edit["duration_ns"]) == integer(edit["end_ns"])-integer(edit["begin_ns"]),
                    "invalid edit interval")
            frame = frames[integer(edit["frame"])]
            require(frame["population"] == "edit" and
                    integer(frame["begin_ns"]) <= integer(edit["begin_ns"]) <= integer(edit["end_ns"]) and
                    edit["end_ns"] == frame["end_ns"], "edit response boundary mismatch")
            valid_edits.append(edit)
        require(len(actions) == len(edits), "action/edit count mismatch")
        require(len({r["action"] for r in actions}) == len(actions), "duplicate action evidence")
        require({r["action"] for r in actions} == seen, "action/edit identity mismatch")
        require(all(type(r["accepted"]) is bool for r in actions), "action acceptance missing")
        require(all(next(e for e in edits if e["action"] == r["action"])["accepted"] == r["accepted"]
                    for r in actions), "action/edit acceptance mismatch")
    except (ValueError, KeyError, TypeError, IndexError) as exc:
        errors.append(str(exc))
    cpu_integrity_ok = len(errors) == initial_error_count
    accepted = [integer(r["duration_ns"]) for r in valid_edits if r.get("accepted") is True]
    measured_frames = frames[warmup+1:]
    ordinary_values = [integer(r["duration_ns"]) for r in measured_frames if
                       r["population"] in (("ordinary",) if performance else ("ordinary", "motion"))]
    values = {name:[integer(r["duration_ns"]) for r in frames if r["population"] == name]
              for name in ("startup", "warmup", "edit", "motion")}
    values["ordinary"] = ordinary_values
    values["combined"] = [integer(r["duration_ns"]) for r in measured_frames]
    result["populations"] = {name:distribution(samples) for name,samples in values.items()}
    result["accepted_edits"] = distribution(accepted)
    frame_population = {r["frame"]:r["population"] for r in frames}
    stages = {}
    for r in cpu:
        if r["record_type"] != "stage": continue
        if r.get("frame") not in frame_population and r.get("stage") != "teardown": continue
        population = frame_population.get(r.get("frame"),"teardown")
        stage = r["stage"]
        stages.setdefault(stage,{}).setdefault(population,[]).append(integer(r["duration_ns"]))
        if population == "motion" and not performance:
            stages[stage].setdefault("ordinary",[]).append(integer(r["duration_ns"]))
    result["stage_populations"] = {stage:{name:distribution(samples) for name,samples in groups.items()}
                                   for stage,groups in stages.items()}
    if config["case"] == "history" and isinstance(schedule,dict):
        named = {}
        for name,pair in schedule.get("history_populations",{}).items():
            lo,hi = map(integer,pair)
            selected = [r for r in measured_frames if lo <= integer(r["frame"])-warmup-1 <= hi]
            named[name] = {kind:distribution(integer(r["duration_ns"]) for r in selected if
                kind == "combined" or r["population"] == kind) for kind in
                (("combined","ordinary","edit","motion") if performance else ("combined","ordinary","edit"))}
        result["history_populations"] = named
    duration = integer(measured_frames[-1]["end_ns"])-integer(measured_frames[0]["begin_ns"]) if measured_frames else 0
    result["measured_interval_ns"] = str(duration)
    result["completed_prefix"] = {"startup":bool(frames), "warmup":str(min(max(0,len(frames)-1),warmup)),
                                  "measured":str(max(0,len(frames)-warmup-1))}
    result["cold_startup"] = ({"status":"measured", "reason":"process launch to first usable frame-effect return",
                                "scope":"startup", "unit":"ns", "value":str(integer(frames[0]["end_ns"])-integer(summary["supervision"]["launch_ns"]))}
                              if frames and summary.get("supervision",{}).get("launch_ns") and
                                 integer(frames[0]["end_ns"]) >= integer(summary["supervision"]["launch_ns"])
                              else {"status":"incomplete", "reason":"startup boundary unavailable", "scope":"startup", "unit":"ns", "value":None})
    references = [r for r in reference if r["record_type"] == "frame"]
    if reference:
        if ([(r.get("frame"),r.get("begin_ns"),r.get("end_ns")) for r in references] !=
                [(r.get("frame"),r.get("begin_ns"),r.get("end_ns")) for r in frames]):
            errors.append("CPU/reference frame mismatch")
        if sum(r["record_type"] == "action" for r in reference) != sum(r["record_type"] == "action" for r in cpu):
            errors.append("CPU/reference action mismatch")
    else:
        errors.append("reference evidence unavailable")
    supervision = summary.get("supervision", {})
    if supervision and supervision.get("termination",{}).get("cause") != summary.get("termination",{}).get("cause"):
        errors.append("summary/supervisor termination mismatch")
    for field, observed in (("resource_samples",resources),("allocation_records",allocations),
                            ("reference_records",reference)):
        if field in supervision and integer(supervision[field]) != len(observed):
            errors.append(field+" count mismatch")
    for field, aggregator, summary_key in (("rss_bytes",max,"observed_maxima"),
                                           ("available_ram_bytes",min,"observed_minima"),
                                           ("device_free_bytes",min,"observed_minima")):
        # Supervisor extrema cover observed worker samples. The earlier
        # preflight sample belongs to resource admission, not that population.
        samples = [integer(r[field]) for r in resources
                   if field in r and r.get("phase") != "preflight"]
        if samples and supervision.get(summary_key,{}).get(field) != str(aggregator(samples)):
            errors.append("resource "+field+" observed extremum mismatch")
    heap_maxima = {}
    for r in resources:
        for heap in r.get("heaps",[]):
            ident, usage = heap["heap"], integer(heap["usage_bytes"])
            heap_maxima[ident] = max(usage,heap_maxima.get(ident,0))
    if heap_maxima and supervision.get("heap_observed_maxima") != {k:str(v) for k,v in heap_maxima.items()}:
        errors.append("resource heap observed maxima mismatch")
    if allocations:
        try:
            from megascene_supervisor import audit_allocations
            ledger = audit_allocations(allocations,normal=summary.get("termination",{}).get("cause")=="normal_exit")
            require(ledger == supervision.get("allocation_ledger"), "allocation ledger summary mismatch")
        except (ValueError, KeyError, TypeError) as exc:
            errors.append("allocation ledger: "+str(exc))
    if supervision.get("errors"):
        errors += ["supervision: "+str(item) for item in supervision["errors"]]
    if not resources:
        errors.append("resource evidence unavailable")
    if not allocations:
        errors.append("allocation evidence unavailable")
    gpu = summary.get("gpu_execution", {})
    if gpu.get("errors") or gpu_errors:
        errors += ["GPU: "+str(item) for item in (gpu.get("errors") or gpu_errors)]
    gpu_ok = gpu.get("required_evidence_complete") is True
    if frames and not gpu_ok:
        errors.append("required GPU evidence incomplete")
    # Preserve errors from the raw launch report, not errors computed by an
    # earlier classification. Review updates may classify the same raw bundle
    # again, and derived errors must be recomputed from its current evidence.
    source_errors = summary.get("source_evidence_errors", summary.get("evidence_errors", []))
    result["source_evidence_errors"] = source_errors
    prior_errors = [e for e in source_errors if not e.startswith("GPU: ")]
    errors = list(dict.fromkeys(prior_errors+errors))
    cause = summary.get("termination", {}).get("cause", "unknown")
    failed_allocations = [r for r in allocations if r["record_type"] == "allocation_failed"]
    if cause == "allocation_error" and not failed_allocations:
        errors.append("allocation termination lacks explicit failed operation")
    if cause in RESERVE_CAUSES and not summary.get("termination",{}).get("reason"):
        errors.append("reserve stop lacks supervisor source/time/value reason")
    result["evidence_errors"] = errors
    result["termination_evidence"] = _gate("inconclusive" if cause == "unknown" or
        any("termination" in e for e in errors) else "pass",
        "supervisor cause and supporting raw evidence" if cause != "unknown" else "termination cause unavailable",
        "attempt termination",["supervision.json","resources.jsonl","allocations.jsonl"])
    full_frames = len(frames) == 1+warmup+measured
    action_required = config["case"] in ("localized", "support", "history")
    expected_actions = {"localized":1, "support":6, "history":120}.get(config["case"],0)
    if config.get("schedule") in ("history-12-v1", "history-48-v1", "support-1-span-v1", "support-2-span-v1"):
        expected_actions = {"history-12-v1":12,"history-48-v1":48,"support-1-span-v1":2,"support-2-span-v1":4}[config["schedule"]]
    action_ok = len(accepted) == expected_actions and len(actions) == expected_actions
    completions = [r for r in cpu if r["record_type"] == "complete"]
    cpu_complete = (len(completions) == 1 and cpu and cpu[-1] is completions[0] and
                    completions[0].get("frame") == str(1+warmup+measured))
    prior_completion = summary.get("schedule_completion",{})
    prior_allows_completion = (prior_completion.get("status") == "pass" or
        prior_completion.get("reason","").startswith("required GPU evidence incomplete"))
    schedule_pass = (full_frames and action_ok and cause == "normal_exit" and cpu_complete and
                     prior_allows_completion and cpu_integrity_ok and not cpu_errors and
                     not any(e for e in errors if e != "required GPU evidence incomplete"
                             and not e.startswith("GPU: ")))
    if cause == "required_edit_rejection" or (full_frames and not action_ok):
        schedule_status, schedule_reason = "fail", "required action rejected, missing or extra"
    elif schedule_pass:
        schedule_status, schedule_reason = "pass", "complete declared schedule and required evidence"
    else:
        schedule_status, schedule_reason = "inconclusive", "incomplete schedule or inconsistent required evidence"
    result["schedule_completion"] = _gate(schedule_status,schedule_reason,config["schedule"],["cpu.jsonl","reference.jsonl"])
    validation_status = validation.get("status") if isinstance(validation,dict) else None
    if validation_status == "pass":
        try:
            require(integer(validation["checked_frames"]) == 1+warmup+measured,
                    "independent validation replay incomplete")
            require(isinstance(comparison,dict) and comparison.get("status") == "pass",
                    "timed checkpoint comparison unavailable")
            expected_checkpoint_frames = {r["frame"] for r in comparison["checkpoints"]}
            actual_checkpoint_frames = [r["frame"] for r in cpu if r["record_type"] in ("checkpoint","static_audit")]
            require(integer(comparison["checked_frames"]) == len(expected_checkpoint_frames),
                    "timed checkpoint count inconsistent")
            if isinstance(schedule,dict):
                require(schedule.get("schedule_id") == config["schedule"], "frozen schedule identity mismatch")
                require(expected_checkpoint_frames == {r["frame"] for r in schedule["required_checkpoints"]},
                        "required checkpoint schedule mismatch")
            require(set(actual_checkpoint_frames) == expected_checkpoint_frames and
                    len(actual_checkpoint_frames) == len(expected_checkpoint_frames),
                    "timed checkpoint evidence missing or duplicated")
        except (ValueError, KeyError, TypeError) as exc:
            errors.append(str(exc))
            validation_status = None
    if validation_status != "pass":
        result["state_correctness"] = _gate("inconclusive" if validation_status is None else "fail",
            "complete independent validation unavailable" if validation_status is None else "independent validation failed",
            config["schedule"],["validation.json"])
    elif result.get("state_correctness",{}).get("status") != "pass":
        # A passing separate replay never repairs a failed timed checkpoint.
        result["state_correctness"] = _gate(result.get("state_correctness",{}).get("status","inconclusive"),
            "timed checkpoint comparison did not pass",config["schedule"],["comparison.json"])
    review_status = review.get("status") if isinstance(review,dict) else None
    if review_status == "incorrect_rendering":
        result["rendering_correctness"] = _gate("fail","named feature geometry incorrect",config["profile"],["review.json"])
        result["visual_quality"] = _gate("inconclusive","rendering incorrect; readability cannot qualify",config["profile"],["review.json"])
    if review_status == "insufficient_readability":
        result["visual_quality"] = _gate("fail","named feature readability insufficient",config["profile"],["review.json"])
    if review_status == "pass" and result.get("visual_quality",{}).get("status") != "fail":
        result["visual_quality"] = _gate("pass","named feature assessment passed",config["profile"],["review.json"])
    if result.get("numeric_validity",{}).get("status") == "pass" and manifest.get("numeric_admission",{}).get("status") != "pass":
        result["numeric_validity"] = _gate("inconclusive","numeric admission evidence does not pass",
                                            config["schedule"],["manifest.json"])
    cal = calibration_result(calibration,config,result["attempt_kind"])
    result["calibration"] = cal
    ordinary_duration=sum(ordinary_values)
    enough_ordinary = len(ordinary_values) >= 1000 and (ordinary_duration if performance else duration) >= 10_000_000_000
    result["population_qualification"] = _gate("pass" if enough_ordinary else "inconclusive",
        "1000 ordinary frames and 10 ordinary seconds" if enough_ordinary and performance else
        "1000 ordinary frames and 10 measured seconds" if enough_ordinary else
        "requires 1000 ordinary frames and 10 ordinary seconds in this attempt" if performance else
        "requires 1000 ordinary frames and 10 measured seconds in this attempt", "ordinary frames",["cpu.jsonl"])
    result["edit_response"] = (_gate("not_applicable","no edits in declared schedule","accepted edits") if not action_required else
        _gate("pass" if len(accepted)>=100 else "inconclusive",
              "at least 100 accepted edits" if len(accepted)>=100 else "fewer than 100 accepted edits in this attempt",
              "accepted edits",["cpu.jsonl"]))
    failed_gates = []
    if result["cold_startup"]["status"] == "measured" and integer(result["cold_startup"]["value"]) > 30_000_000_000:
        failed_gates.append("startup")
    if ordinary_values:
        stats = result["populations"]["ordinary"]
        for key,limit in (("mean",16_700_000),("p95",16_700_000),("p99",33_300_000),("max",100_000_000)):
            if stats[key] > limit: failed_gates.append("ordinary_"+key)
    if action_required and accepted:
        stats = result["accepted_edits"]
        for key,limit in (("p95",100_000_000),("max",250_000_000)):
            if stats[key] > limit: failed_gates.append("edit_"+key)
    ready = (enough_ordinary and result["cold_startup"]["status"] == "measured" and
             (not action_required or len(accepted)>=100))
    status = "fail" if failed_gates else "pass" if ready else "inconclusive"
    result["responsiveness"] = _gate(status, ", ".join(failed_gates) if failed_gates else
        "all applicable latency gates pass" if ready else "latency population or startup evidence insufficient",
        "declared interactive gates",["cpu.jsonl"])
    result["responsiveness"]["failed_gates"] = failed_gates
    resource_ok = not any("resource" in e or "allocation" in e or "supervision" in e for e in errors) and bool(resources and allocations)
    cpu_available = bool(frames) and cpu_integrity_ok and not cpu_errors
    result["measurement_availability"] = {"cpu":_gate("pass" if cpu_available else "inconclusive",
            "completed CPU intervals" if cpu_available else "CPU intervals incomplete","frame intervals",["cpu.jsonl"]),
        "gpu":_gate("pass" if gpu_ok else "inconclusive","GPU capability and interval evidence" if gpu_ok else
                    "GPU intervals incomplete","submitted work",["gpu.jsonl"]),
        "resources":_gate("pass" if resource_ok else "inconclusive","supervised resource/allocation evidence" if resource_ok else
                          "resource or allocation evidence incomplete","attempt",["resources.jsonl","allocations.jsonl"])}
    requirements = ("state_correctness","rendering_correctness","visual_quality","numeric_validity","schedule_completion")
    failures = [name for name in requirements if result.get(name,{}).get("status") == "fail"]
    missing = [name for name in requirements if result.get(name,{}).get("status") != "pass"]
    result["workload_completion"] = _gate("fail" if failures else "inconclusive" if missing else "pass",
        "required state, fidelity, numeric and schedule evidence" if not missing else
        "failed: "+", ".join(failures) if failures else "unqualified: "+", ".join(missing),
        "complete declared workload",["validation.json","comparison.json","review.json","cpu.jsonl"])
    if not resource_ok: missing.append("resource_evidence")
    gpu_messages = set(map(str,gpu.get("errors") or gpu_errors))
    if any(e not in gpu_messages and not e.startswith("GPU: ") and e != "required GPU evidence incomplete"
           for e in errors):
        missing.append("evidence_integrity")
    if not reference or any("reference" in e.lower() for e in errors):
        missing.append("reference_evidence")
    if result["attempt_kind"] in ("calibration_off","validation_only","validation_replay","opening_capture","admission","reproduction"):
        missing.append("nonqualifying_attempt_kind")
    if cause in RESERVE_CAUSES or cause in ("required_edit_rejection","allocation_error","device_loss"):
        failures.append(cause)
    capacity_status = "fail" if failures else "pass" if not missing else "inconclusive"
    result["qualified_capacity"] = _gate(capacity_status,
        "correct complete workload within policy" if capacity_status=="pass" else
        "failed: "+", ".join(failures) if failures else "unqualified: "+", ".join(missing),
        "complete declared workload",["summary.json","validation.json","supervision.json"])
    if capacity_status == "fail" or result["responsiveness"]["status"] == "fail":
        interactive = "fail"
    elif (capacity_status == "pass" and result["responsiveness"]["status"] == "pass" and
          cal["status"] == "pass" and gpu_ok):
        interactive = "pass"
    else:
        interactive = "inconclusive"
    result["interactive_pass"] = _gate(interactive,
        "qualified single-attempt interactive observation" if interactive=="pass" else
        "latency or required correctness/fidelity failed" if interactive=="fail" else
        "capacity, populations or calibration not qualified", "single attempt",["summary.json"])
    result["confirmed_endpoint"] = _gate("inconclusive","one attempt cannot confirm a search endpoint",
                                          "series repetition",["campaign.json","series.json"])
    result["endpoint_eligible"] = _gate("inconclusive" if result["synthetic"] else
        "pass" if interactive == "pass" else "inconclusive",
        "synthetic fixture is excluded from measured searches" if result["synthetic"] else
        "qualified attempt requires separate repetitions" if interactive == "pass" else
        "attempt is not a qualified interactive observation", "search input")
    result["observed_capacity_failure"] = _gate("inconclusive" if cause == "allocation_error" and failed_allocations else
        "not_applicable", "explicit allocation failure is one observation; diagnostic retry required" if
        cause == "allocation_error" and failed_allocations else "no confirmed allocation failure endpoint",
        "single attempt",["allocations.jsonl"] if failed_allocations else [])
    result["implementation_acceptance"] = _gate("inconclusive",
        "one attempt, including a truthfully reported failure, cannot complete the required acceptance matrix",
        "issue #47 acceptance matrix",["campaign.json"])
    result["raw_evidence"] = {"cpu":"cpu.jsonl","gpu":"gpu.jsonl","resources":"resources.jsonl",
                              "allocations":"allocations.jsonl","reference":"reference.jsonl",
                              "checkpoints":"cpu.jsonl","actions":"cpu.jsonl"}
    result["qualification"] = "synthetic_report" if result["synthetic"] else "classified_attempt"
    return result


def report_bundle(bundle, calibration=None):
    """Public read-only report boundary for a retained attempt directory."""
    bundle = Path(bundle)
    manifest = checked_object(read_json((bundle/"manifest.json").read_text()),"manifest")
    summary = checked_object(read_json((bundle/"summary.json").read_text()),"summary")
    if manifest["attempt_kind"] == "calibration_off":
        from megascene_calibration import off_result
        from megascene_static import read_stream as read_cpu
        cpu, errors = read_cpu(bundle/"cpu.jsonl",manifest["attempt_id"])
        validation = read_json((bundle/"validation.json").read_text()) if (bundle/"validation.json").is_file() else None
        return {**summary, **off_result(manifest["effective"],bundle,manifest,validation,
                          read_json((bundle/"supervision.json").read_text()),cpu,errors)}
    cpu, cpu_errors = read_stream(bundle/"cpu.jsonl",manifest)
    from megascene_gpu import read_stream as read_gpu
    gpu, gpu_errors = read_gpu(bundle/"gpu.jsonl",manifest)
    resources, resource_errors = read_stream(bundle/"resources.jsonl",manifest)
    allocations, allocation_errors = read_stream(bundle/"allocations.jsonl",manifest)
    reference, reference_errors = read_stream(bundle/"reference.jsonl",manifest)
    from megascene_gpu import summarize
    frozen=read_json((bundle/'schedule.json').read_text()) if (bundle/'schedule.json').exists() else None
    gpu_result = summarize(gpu,gpu_errors,[r for r in cpu if r["record_type"] == "frame"],manifest["effective"],frozen)
    summary = dict(summary)
    summary["gpu_execution"] = gpu_result
    def optional(name):
        path = bundle/name
        return checked_object(read_json(path.read_text()),name) if path.is_file() else None
    if calibration is None:
        calibration = optional("calibration.json")
    from megascene_performance import enabled
    if enabled(manifest['effective']) and calibration is not None:
        from megascene_checkpoints import identity
        from hashlib import sha256
        actual=identity(manifest,bundle,manifest['effective'])['artifacts']
        if calibration['status']=='pass':
            require(calibration.get('binding',{}).get('artifacts')==actual,
                    'performance calibration runtime/schedule binding mismatch')
            reference_path=Path(calibration['reference'])
            require(sha256(reference_path.read_bytes()).hexdigest()==calibration.get('reference_sha256'),
                    'performance calibration assessment bytes mismatch')
            assessment=read_json(reference_path.read_text())
            require(assessment['status']==calibration['status'] and assessment['scope']==calibration['scope'] and
                    assessment.get('binding')==calibration['binding'], 'performance calibration assessment mismatch')
    return classify(summary,manifest,cpu,cpu_errors,gpu_result["errors"],resources,resource_errors,
                    allocations,allocation_errors,reference,reference_errors,
                    optional("validation.json"),optional("review.json"),calibration,optional("comparison.json"),
                    optional("schedule.json"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle",required=True)
    parser.add_argument("--calibration",help="explicit calibration status/reference/scope JSON")
    args = parser.parse_args()
    cal = read_json(Path(args.calibration).read_text()) if args.calibration else None
    import json
    print(json.dumps(report_bundle(args.bundle,cal),sort_keys=True,indent=2))


if __name__ == "__main__":
    main()
