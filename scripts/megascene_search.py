#!/usr/bin/env python3
"""Persisted, bounded Megascene scale search over archived Vulkan attempts.

The runner owns validation, calibration, resource supervision and attempt
classification. This module only orders work and confirms repeated outcomes.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

from megascene import snapshot
from megascene_checkpoints import applicable, identity, verify_evidence
from megascene_inventory import SCHEMA, canonical, read_json, require
from megascene_report import report_bundle
from megascene_scale import midpoint_refinement, next_growth, preset_for

CASES = ("static", "traversal", "picking", "localized", "support", "history")
DEADLINES = {"startup_deadline", "completion_watchdog", "case_deadline", "campaign_deadline"}
POLICY_STOPS = {"required_edit_rejection", "monitoring_failure", "external_interruption",
                "process_rss_reserve", "available_ram_reserve", "device_free_reserve",
                "heap_budget_reserve", "rejected_request", "prelaunch_failure", "device_loss"}
DIAGNOSTICS = {
    "static": (("spread", None), ("material-detail", None), ("surface-detail", None)),
    "localized": (("material-detail", None),),
    "support": (("fill", None), (None, "support-1-span-v1"), (None, "support-2-span-v1")),
    "history": (("fill", None), ("body-rich", None), (None, "history-12-v1"),
                (None, "history-48-v1")),
}


def point(case, q, seed=45, threads=6, diagnostic=None, schedule=None):
    preset = preset_for(q)
    default_schedule = (f"{diagnostic}-{case}-v1" if diagnostic else
                        f"{case}-v2" if case in ("traversal", "picking") or
                        case == "history" and preset not in ("small", "large") else case+"-v1")
    return {"case": case, "q": q, "preset": preset, "seed": seed, "threads": threads,
            "resolution": "1920x1080", "profile": "full", "fragment_budget": "2048",
            "warmup":"120", "frames":"3600",
            "diagnostic": diagnostic, "schedule": schedule or default_schedule}


def key(spec):
    return hashlib.sha256(canonical(spec)).hexdigest()[:20]


def labels(report):
    """A failure cause never becomes a pass or a physical exhaustion claim."""
    cause = report.get("termination", {}).get("cause", "unknown")
    capacity = report.get("qualified_capacity", {}).get("status")
    responsive = report.get("responsiveness", {}).get("status")
    interactive = report.get("interactive_pass", {}).get("status")
    allocation = report.get("observed_capacity_failure", {}).get("status")
    if cause == "normal_exit" and capacity == "pass":
        return {"capacity": "pass", "interactive": "pass" if interactive == "pass" else
                "fail:responsiveness" if responsive == "fail" else "inconclusive", "time_budget": "pass",
                "observed_capacity_failure": "pass"}
    return {"capacity": "inconclusive", "interactive": "inconclusive",
            "time_budget": "fail:"+cause if cause in DEADLINES else "inconclusive",
            "observed_capacity_failure": "fail:allocation_error" if cause == "allocation_error" and
            allocation == "inconclusive" else "inconclusive"}


def outcome_for(rows, dimension, simulation=False):
    """Three agreeing independent runs, or two explicit allocation failures."""
    if not rows:
        return {"status": "untested", "attempts": []}
    if any(row.get("synthetic") for row in rows) and not simulation:
        return {"status": "excluded", "attempts": [row["attempt_id"] for row in rows],
                "reason": "synthetic attempt cannot establish a measured endpoint"}
    values = [row["labels"][dimension] for row in rows]
    ids = [row["attempt_id"] for row in rows]
    fingerprints = {row.get("workload_fingerprint") for row in rows if row["labels"][dimension] != "inconclusive"}
    if len(ids) != len(set(ids)) or len(fingerprints) > 1:
        return {"status": "unstable", "attempts": ids, "reason": "attempt or workload identity differs"}
    if None in fingerprints:
        return {"status": "observed", "attempts": ids,
                "reason": "frozen workload or actual inventory identity unavailable"}
    observed = [v for v in values if v != "inconclusive"]
    if len(set(observed)) > 1 or len(set(v for v in observed if v.startswith("fail:"))) > 1:
        return {"status": "unstable", "attempts": ids, "reason": "mixed pass/fail or failure causes"}
    if any(v == "inconclusive" for v in values):
        return {"status": "unstable", "attempts": ids, "reason": "incomplete or unqualified evidence"}
    needed = 2 if dimension == "observed_capacity_failure" else 3
    if len(rows) >= needed and observed:
        return {"status": "confirmed", "result": observed[0], "attempts": ids[:needed],
                "evidence_count": needed}
    return {"status": "observed", "result": observed[0] if observed else "inconclusive", "attempts": ids}


def summarize(events, simulation=False):
    points = {}
    stops = []
    reassessed = {e["attempt_id"]:e["observed"] for e in events if e["kind"] == "reassessment"}
    for event in events:
        if event["kind"] == "attempt":
            spec = event["point"]
            entry = points.setdefault(key(spec), {"point": spec, "attempts": []})
            entry["attempts"].append({**event,**reassessed.get(event["attempt_id"],{})})
        elif event["kind"] == "stop":
            stops.append(event)
    for entry in points.values():
        entry["outcomes"] = {dimension: outcome_for(entry["attempts"], dimension, simulation)
                             for dimension in ("interactive", "time_budget", "capacity", "observed_capacity_failure")}
        entry["diagnostic_assessments"] = [e for e in events if e["kind"] == "diagnostic_assessment" and
                                           e["attempt_id"] in {a["attempt_id"] for a in entry["attempts"]}]
    bounds = {}
    for case in CASES:
        rows = [v for v in points.values() if v["point"]["case"] == case and
                v["point"]["seed"] == 45 and v["point"]["threads"] == 6 and
                v["point"]["diagnostic"] is None and v["point"]["schedule"] == point(case,v["point"]["q"])["schedule"]]
        rows.sort(key=lambda v: v["point"]["q"])
        categories = {}
        for dimension in ("interactive", "time_budget", "capacity", "observed_capacity_failure"):
            passed = [v for v in rows if v["outcomes"][dimension]["status"] == "confirmed" and
                      v["outcomes"][dimension]["result"] == "pass"]
            failed = [v for v in rows if v["outcomes"][dimension]["status"] == "confirmed" and
                      v["outcomes"][dimension]["result"].startswith("fail:")]
            last = passed[-1] if passed else None
            larger = [v for v in failed if last is None or v["point"]["q"] > last["point"]["q"]]
            first = larger[0] if larger else None
            nonmonotonic = [(a["point"]["q"], b["point"]["q"])
                            for a in failed for b in passed if a["point"]["q"] < b["point"]["q"]]
            adjacent = bool(last and first and first["point"]["q"] == last["point"]["q"]+1)
            within_ten_percent = bool(last and first and
                (first["point"]["q"]**2-last["point"]["q"]**2)*10 <= last["point"]["q"]**2)
            categories[dimension] = {"largest_confirmed_pass": _bound(last, dimension),
                "nearest_confirmed_larger_failure": _bound(first, dimension),
                "untested_q_between": list(range(last["point"]["q"]+1, first["point"]["q"])) if last and first else [],
                "nonmonotonic_fail_then_pass": nonmonotonic,
                "refinement_status":"nonmonotonic" if nonmonotonic else
                    "adjacent" if adjacent else "within_ten_percent" if within_ten_percent else
                    "unfinished" if last and first else "unbounded_observation",
                "note": "no passing bound established" if not last else
                        "no failing bound observed" if not first else
                        "separate tested regions; no single maximum" if nonmonotonic else "discrete observed bracket"}
        bounds[case] = categories
    return {"schema": SCHEMA, "record_type": "search_state", "simulation": simulation,
            "campaign_id":events[0].get("campaign_id") if events else None,
            "points": points, "bounds": bounds,
            "stops": stops, "operational_cap":{"largest_supported_q":5,"next_coarse_growth_q":next_growth(4),
                "meaning":"runner admission cap, not observed physical exhaustion"},
            "untested_main": [point(case,q) for q in (2,3,4,5) for case in CASES
                                   if key(point(case,q)) not in points],
            "scope": "tested configurations only; no architectural maximum inferred"}


def _bound(entry, dimension):
    if entry is None:
        return None
    return {"point": entry["point"], "outcome": entry["outcomes"][dimension],
            "inventories": [a["inventory"] for a in entry["attempts"]
                            if a["attempt_id"] in entry["outcomes"][dimension]["attempts"]]}


def refinement_candidate(state, case, dimension):
    bound = state["bounds"][case][dimension]
    low, high = bound["largest_confirmed_pass"], bound["nearest_confirmed_larger_failure"]
    if not low or not high or bound["nonmonotonic_fail_then_pass"]:
        return None
    lower, upper = low["point"]["q"], high["point"]["q"]
    if (upper*upper-lower*lower)*10 <= lower*lower:
        return None
    q = midpoint_refinement(lower,upper)
    return q if q is not None and key(point(case,q)) not in state["points"] else None


def _fingerprint(root, manifest, inventory):
    config = manifest["effective"]
    actual = {k: v for k,v in inventory.items() if k not in ("validation", "attempt_id", "campaign_id", "series_id")}
    classifier = {name:hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                  for name in ("megascene_search.py","megascene_report.py","megascene_checkpoints.py",
                               "megascene_review.py")}
    return hashlib.sha256(canonical({"scope": {k: config[k] for k in
        ("case", "preset", "seed", "threads", "resolution", "profile", "schedule",
         "diagnostic", "control", "fragment_budget", "warmup", "frames")},
        "schedule": hashlib.sha256((root/"schedule.json").read_bytes()).hexdigest(),
        "inputs": hashlib.sha256((root/"inputs.json").read_bytes()).hexdigest(),
        "runtime_artifacts":{a["path"]:a["sha256"] for a in manifest["artifacts"]
                             if a["path"].startswith("runtime/")},
        "runtime":manifest["runtime"], "constants":manifest["constants"],
        "classifier_artifacts":classifier,
        "inventory": actual})).hexdigest()


def _calibration(config, root):
    local = root/"calibration.json"
    if local.is_file():
        return read_json(local.read_text()), str(local)
    series = (Path(config["archive"])/"calibration-series"/
              (config["case"]+"-"+config["preset"]+"-"+config["threads"])/"calibration.json")
    if series.is_file():
        value = read_json(series.read_text())
        # Reassess a claimed pass against the original controls. The report
        # subsequently checks the exact attempt scope.
        if value.get("status") == "pass":
            from megascene_calibration_series import assess
            assessment = assess(series.with_name("series.json"))
            require(assessment["status"] == "pass" and assessment["scope"] == value["scope"] and
                    value["reference"] == str(series.with_name("assessment.json")),
                    "calibration result no longer agrees with retained controls")
        return value, str(series)
    return None, None


def inspect(output, expected, fixture=False):
    """Consume a complete scope when present; preserve partial failures as such."""
    manifest_path = output/"manifest.json"
    require(manifest_path.is_file(), "runner left no manifest")
    manifest = read_json(manifest_path.read_text())
    root = Path(manifest.get("reproduction", {}).get("archive") or output)
    if not (root/"manifest.json").is_file():
        root = output
    manifest = read_json((root/"manifest.json").read_text())
    summary = read_json((root/"summary.json").read_text())
    config = manifest.get("effective") or {}
    require(manifest.get("schema") == SCHEMA and summary.get("schema") == SCHEMA and
            manifest.get("attempt_id") == summary.get("attempt_id"), "attempt identity/schema mismatch")
    for name, value in (("case",expected["case"]), ("preset",expected["preset"]),
                        ("side_m",str(32*expected["q"])),
                        ("seed",str(expected["seed"])), ("threads",str(expected["threads"])),
                        ("resolution",expected["resolution"]), ("profile",expected["profile"]),
                        ("fragment_budget",expected["fragment_budget"]),
                        ("warmup",expected["warmup"]), ("frames",expected["frames"]),
                        ("diagnostic",None if expected["diagnostic"] in
                         ("spread", "fill", "body-rich", "material-detail", "surface-detail") else expected["diagnostic"]),
                        ("schedule",expected["schedule"])):
        require(config.get(name) == value, "attempt scope mismatch: "+name)
    require(config.get("control") == (expected["diagnostic"] if expected["diagnostic"] in
            ("spread", "fill", "body-rich", "material-detail", "surface-detail") else None),
            "attempt control mismatch")
    synthetic = bool(manifest.get("synthetic") or summary.get("synthetic"))
    require(fixture or not synthetic, "synthetic attempt excluded from measured search")
    complete = all((root/name).is_file() for name in
                   ("validation.json", "validation/inventory.json", "schedule.json", "inputs.json"))
    inventory = None
    fingerprint = None
    calibration_source = None
    inventory_source = None
    if complete:
        validated_inventory = read_json((root/"validation/inventory.json").read_text())
        inventory = validated_inventory
        inventory_source = "validation/inventory.json"
        validation = read_json((root/"validation.json").read_text())
        require(validation.get("status") == "pass", "complete validation required")
        if fixture:
            report = summary
            fingerprint = hashlib.sha256(canonical({"point":expected,"inventory":inventory,
                "schedule":read_json((root/"schedule.json").read_text())})).hexdigest()
        else:
            require(validation.get("synthetic") is False,
                    "complete real validation required")
            applicable(validation,identity(manifest,root,config))
            verify_evidence(manifest,root,("validation.json", "validation/inventory.json", "summary.json"))
            if (root/"inventory.json").is_file():
                verify_evidence(manifest,root,("inventory.json",))
                timed_inventory = read_json((root/"inventory.json").read_text())
                require(timed_inventory == validated_inventory, "timed and validated initial inventories differ")
                inventory = timed_inventory
                inventory_source = "inventory.json"
            calibration, calibration_source = _calibration(config,root)
            report = report_bundle(root,calibration)
            if report.get("qualified_capacity",{}).get("status") == "pass":
                require(inventory_source == "inventory.json" and
                        report.get("initialization",{}).get("status") == "pass",
                        "capacity pass lacks actual timed initial inventory")
            fingerprint = _fingerprint(root,manifest,inventory)
    else:
        report = summary
    classified = labels(report) if complete else {name:"inconclusive" for name in
        ("interactive","time_budget","capacity","observed_capacity_failure")}
    # A failed run can establish a time or allocation observation if its raw
    # report was classified, even though no complete validation was possible.
    if not complete and not fixture:
        try:
            report = report_bundle(root)
            partial = labels(report)
            classified["time_budget"] = partial["time_budget"]
            classified["observed_capacity_failure"] = partial["observed_capacity_failure"]
        except (ValueError, KeyError, OSError):
            pass
    if ((expected["warmup"],expected["frames"]) != ("120","3600") or
            (not fixture and manifest.get("attempt_kind") != "development_observation")):
        classified = {name:"inconclusive" for name in classified}
    return {"attempt_id": manifest["attempt_id"], "campaign_id":manifest.get("campaign_id"),
            "series_id":manifest.get("series_id"), "attempt_kind":manifest.get("attempt_kind"),
            "effective_scope":config, "archive": str(root), "inventory": inventory,
            "inventory_source":inventory_source,
            "workload_fingerprint": fingerprint, "labels": classified,
            "cause": report.get("termination",{}).get("cause","unknown"), "synthetic": synthetic,
            "evidence_gates":{name:report.get(name,{}).get("status") for name in
                ("state_correctness","rendering_correctness","visual_quality","numeric_validity",
                 "schedule_completion","workload_completion")},
            "calibration": report.get("calibration"), "calibration_source":calibration_source,
            "report_status": report.get("qualification"),
            "validation_attempt_id": validation.get("attempt_id") if complete else None,
            "source_control_effects":manifest.get("numeric_bounds",{}).get("control_effects")}


def _campaign_remaining(archive):
    path = archive/"campaign.json"
    if not path.exists():
        return 7200 * 1_000_000_000, "new"
    c = read_json(path.read_text())
    elapsed = int(c["elapsed_ns"])
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    if c["boot_id"] == boot:
        elapsed += max(0,time.monotonic_ns()-int(c["lease_ns"]))
    else:
        elapsed += max(0,time.time_ns()-int(c["lease_utc_ns"]))
    return max(0,int(c["allowance_ns"])-elapsed), c["state"]


class Search:
    def __init__(self, archive, work, additional=0, fixture=False):
        self.archive, self.work, self.fixture = Path(archive).resolve(), Path(work).resolve(), fixture
        require(self.archive != self.work and self.archive not in self.work.parents and
                self.work not in self.archive.parents, "search archive and work must be separate")
        self.path = self.archive/"search"
        self.log = self.path/"search.jsonl"
        self.path.mkdir(parents=True,exist_ok=True)
        self.events = []
        existing = self.log.exists()
        had_campaign = (self.archive/"campaign.json").exists()
        require(not additional or existing or had_campaign,
                "additional allowance requires an existing search or campaign")
        if not fixture and not had_campaign:
            from megascene_supervisor import Campaign
            campaign = Campaign(self.archive)
            campaign.close(True)
        if existing:
            for raw in self.log.read_bytes().splitlines(keepends=True):
                require(raw.endswith(b"\n"), "truncated search evidence")
                e = read_json(raw.decode())
                require(e["schema"] == SCHEMA and e["sequence"] == str(len(self.events)),
                        "search evidence schema/sequence mismatch")
                self.events.append(e)
        else:
            require(not additional or not fixture, "additional allowance requires an existing search")
            campaign_record = read_json((self.archive/"campaign.json").read_text()) if not fixture else None
            self.append("start", {"archive":str(self.archive), "work":str(self.work), "simulation":fixture,
                                  "additional_allowance_s":str(additional),
                                  "initial_allowance_s":"7200",
                                  "campaign_id":campaign_record["campaign_id"] if campaign_record else None})
        require(self.events[0]["archive"] == str(self.archive) and
                self.events[0]["work"] == str(self.work) and
                self.events[0]["simulation"] == fixture, "search resume scope differs")
        if existing:
            require(additional > 0, "resuming search requires --additional-allowance SECONDS")
            self.recover_pending()
            self.recover_diagnostics()
            self.reassess_archives()
            if not fixture:
                self.reassess_diagnostics()
            self.append("resume", {"additional_allowance_s":str(additional)})
        self.additional = additional
        self.work.mkdir(parents=True,exist_ok=True)
        self.save()

    def append(self, kind, fields):
        e = {"schema":SCHEMA,"record_type":"search_event", "sequence":str(len(self.events)),
             "utc":datetime.now(timezone.utc).isoformat(), "utc_ns":str(time.time_ns()),
             "kind":kind, **fields}
        data = canonical(e)+b"\n"
        with self.log.open("ab", buffering=0) as f:
            require(f.write(data) == len(data), "short search evidence write")
            os.fsync(f.fileno())
        if len(self.events) == 0:
            descriptor = os.open(self.path,os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        self.events.append(e)
        return e

    def save(self):
        state = summarize(self.events,self.fixture)
        snapshot(self.path/"state.json",state)
        series = self.path/"series"
        series.mkdir(exist_ok=True)
        for identifier, entry in state["points"].items():
            snapshot(series/(identifier+".json"),{"schema":SCHEMA,"record_type":"search_series",
                "scope":entry["point"], "attempts":[{"attempt_id":a["attempt_id"],
                    "archive":a["archive"],"inventory":a["inventory"],
                    "workload_fingerprint":a.get("workload_fingerprint"),
                    "validation_attempt_id":a.get("validation_attempt_id"),
                    "calibration":a.get("calibration"),"labels":a["labels"]} for a in entry["attempts"]],
                "outcomes":entry["outcomes"],
                "diagnostic_assessments":entry["diagnostic_assessments"],
                "synthetic_simulation":self.fixture})

    def recover_pending(self):
        completed = {e["attempt_token"] for e in self.events if e["kind"] == "attempt" and
                     "attempt_token" in e}
        for proposal in [e for e in self.events if e["kind"] == "proposal" and
                         e["attempt_token"] not in completed]:
            try:
                observed = inspect(Path(proposal["output"]),proposal["point"],self.fixture)
            except (ValueError,KeyError,OSError,TypeError) as exc:
                observed = {"attempt_id":proposal["attempt_token"],"archive":proposal["output"],
                    "inventory":None,"workload_fingerprint":None,
                    "labels":{name:"inconclusive" for name in
                              ("interactive","time_budget","capacity","observed_capacity_failure")},
                    "cause":"external_interruption","synthetic":self.fixture,"inspection_error":str(exc)}
            self.append("attempt",{"point":proposal["point"],"reason":proposal["reason"],
                                   "output":proposal["output"],"returncode":None,
                                   "attempt_token":proposal["attempt_token"],**observed})
            if proposal["reason"] == "targeted_diagnostic":
                self.assess_diagnostic(proposal["point"],observed,proposal["attempt_token"])

    def recover_diagnostics(self):
        assessed = {e["attempt_id"] for e in self.events if e["kind"] == "diagnostic_assessment"}
        for attempt in [e for e in self.events if e["kind"] == "attempt" and
                        e["reason"] == "targeted_diagnostic" and e["attempt_id"] not in assessed]:
            token = attempt["attempt_token"]
            path = self.path/"comparisons"/(token+".json")
            if path.is_file():
                result = read_json(path.read_text())
                require(result["schema"] == SCHEMA and result["attempt_id"] == attempt["attempt_id"],
                        "orphaned diagnostic assessment identity mismatch")
                self.append("diagnostic_assessment",{"point":attempt["point"],
                    "attempt_id":attempt["attempt_id"],"assessment":str(path),"status":result["status"]})
            else:
                self.assess_diagnostic(attempt["point"],attempt,token)

    def reassess_archives(self):
        for original in [e for e in self.events if e["kind"] == "attempt"]:
            try:
                updated = inspect(Path(original["output"]),original["point"],self.fixture)
            except (ValueError,KeyError,OSError,TypeError):
                if all(value == "inconclusive" for value in original["labels"].values()):
                    continue
                raise
            if original.get("returncode") not in (None,0):
                updated["labels"] = {name:"inconclusive" for name in
                                     ("interactive","time_budget","capacity","observed_capacity_failure")}
            previous = next((e["observed"] for e in reversed(self.events) if e["kind"] == "reassessment" and
                             e["attempt_id"] == original["attempt_id"]), original)
            if previous.get("workload_fingerprint"):
                updated["workload_fingerprint"] = previous["workload_fingerprint"]
            if any(updated.get(name) != previous.get(name) for name in updated):
                self.append("reassessment",{"attempt_id":original["attempt_id"],
                                            "point":original["point"],"observed":updated,
                                            "reason":"archived review/calibration or evidence changed"})

    def reassess_diagnostics(self):
        latest = {e["attempt_id"]:e for e in self.events if e["kind"] == "diagnostic_assessment"}
        for attempt in [e for e in self.all_attempts() if e["reason"] == "targeted_diagnostic" and
                        e["labels"]["capacity"] == "pass"]:
            prior = latest.get(attempt["attempt_id"])
            if prior and prior["status"] == "pass":
                continue
            baseline = self.attempts(point(attempt["point"]["case"],2))
            if not any(row["labels"]["capacity"] == "pass" for row in baseline):
                continue
            self.assess_diagnostic(attempt["point"],attempt,attempt["attempt_token"]+"-"+str(uuid.uuid4()))

    def all_attempts(self):
        reassessed = {e["attempt_id"]:e["observed"] for e in self.events if e["kind"] == "reassessment"}
        return [{**e,**reassessed.get(e["attempt_id"],{})} for e in self.events if e["kind"] == "attempt"]

    def attempts(self, spec):
        return [e for e in self.all_attempts() if e["point"] == spec]

    def assess_diagnostic(self, spec, observed, token):
        baseline = next((e for e in self.attempts(point(spec["case"],2)) if
                         e.get("validation_attempt_id") and e.get("inventory") and
                         e["labels"]["capacity"] == "pass"),None)
        result = {"schema":SCHEMA,"record_type":"search_diagnostic_assessment",
                  "point":spec,"baseline_attempt_id":baseline["attempt_id"] if baseline else None,
                  "attempt_id":observed["attempt_id"],
                  "baseline_validation_id":baseline["validation_attempt_id"] if baseline else None,
                  "validation_id":observed.get("validation_attempt_id"),
                  "baseline_inventory":baseline["inventory"] if baseline else None,
                  "control_inventory":observed.get("inventory"),
                  "source_control_effects":observed.get("source_control_effects"),
                  "status":"inconclusive"}
        try:
            require(baseline is not None and observed.get("validation_attempt_id") and
                    observed["validation_attempt_id"] != baseline["validation_attempt_id"],
                    "separate complete baseline and control validations required")
            if self.fixture:
                result["status"] = "simulated"
                result["reason"] = "controlled synthetic inventories; no measured comparison"
            elif spec["diagnostic"]:
                from megascene_compare_controls import compare
                comparison = compare(baseline["archive"],observed["archive"])
                result.update(status=comparison["status"],comparison=comparison)
            else:
                from megascene_compare_schedules import compare
                comparison = compare(baseline["archive"],observed["archive"])
                result.update(status=comparison["status"],comparison=comparison)
        except (ValueError,KeyError,OSError,TypeError) as exc:
            result["reason"] = str(exc)
        path = self.path/"comparisons"/(token+".json")
        path.parent.mkdir(exist_ok=True)
        snapshot(path,result)
        self.append("diagnostic_assessment",{"point":spec,"attempt_id":observed["attempt_id"],
                                              "assessment":str(path),"status":result["status"]})

    def next_task(self):
        state = summarize(self.events,self.fixture)
        # Breadth first: every family at one coarse scale before increasing q.
        for q in (2,3,4,5):
            for case in CASES:
                spec = point(case,q)
                if self.attempts(spec):
                    continue
                previous = [e for e in self.all_attempts() if
                            e["point"]["case"] == case and e["point"]["seed"] == 45 and
                            e["point"]["threads"] == 6 and e["point"]["diagnostic"] is None and
                            e["point"]["q"] < q]
                if any(e["labels"]["capacity"] != "pass" for e in previous):
                    continue
                return spec, "coarse_growth"
        # Confirm only the consequential observed pass and nearest failure in
        # each independent family, preserving other points as observations.
        for case in CASES:
            rows = [v for v in state["points"].values() if v["point"]["case"] == case and
                    v["point"]["seed"] == 45 and v["point"]["threads"] == 6 and
                    v["point"]["diagnostic"] is None]
            rows.sort(key=lambda v:v["point"]["q"])
            passes = [v for v in rows if v["attempts"][0]["labels"]["capacity"] == "pass"]
            failures = [v for v in rows if v["attempts"][0]["labels"]["time_budget"].startswith("fail:") or
                        v["attempts"][0]["labels"]["observed_capacity_failure"].startswith("fail:") or
                        v["attempts"][0]["labels"]["interactive"].startswith("fail:")]
            candidates = passes[-1:] + failures[:1]
            if passes:
                candidates += [v for v in failures if v["point"]["q"] > passes[-1]["point"]["q"]][:1]
            candidates = list({key(v["point"]):v for v in candidates}.values())
            for v in candidates:
                attempts = v["attempts"]
                first = attempts[0]
                cause = first["cause"]
                needed = 2 if cause == "allocation_error" else 3
                if len(attempts) < needed and all(a["labels"] == first["labels"] for a in attempts):
                    return v["point"], "allocation_diagnostic_retry" if cause == "allocation_error" else "endpoint_repetition"
        # A discrete interior setting is proposed only for a confirmed bracket.
        for case in CASES:
            for dimension in ("interactive","time_budget","capacity","observed_capacity_failure"):
                q = refinement_candidate(state,case,dimension)
                if q is not None:
                    return point(case,q), "area_midpoint_refinement"
        # These implemented diagnostics have separate schedules/validations and
        # are available at the declared small/seed-45/six-thread control scope.
        for case, variants in DIAGNOSTICS.items():
            main = [e for e in self.all_attempts() if
                    e["point"]["case"] == case and e["point"]["seed"] == 45 and
                    e["point"]["threads"] == 6 and e["point"]["diagnostic"] is None]
            if not main or not any(a["labels"]["interactive"].startswith("fail:") or
                                   a["labels"]["time_budget"].startswith("fail:") or
                                   a["labels"]["observed_capacity_failure"].startswith("fail:") for a in main):
                continue
            for diagnostic,schedule in variants:
                spec = point(case,2,diagnostic=diagnostic,schedule=schedule)
                if not self.attempts(spec):
                    return spec, "targeted_diagnostic"
        # Consequential primary boundaries get independent-seed and thread
        # observations. They remain separate series and need their own repeats.
        for case in CASES:
            b = state["bounds"][case]["capacity"]
            boundary = b["nearest_confirmed_larger_failure"] or state["bounds"][case]["interactive"]["nearest_confirmed_larger_failure"]
            if boundary:
                q = boundary["point"]["q"]
                for seed,threads in ((46,6),(45,1),(45,12)):
                    spec = point(case,q,seed=seed,threads=threads)
                    if not self.attempts(spec):
                        return spec, "boundary_crosscheck"
        return None, None

    def dispatch(self, spec, reason, runner=None):
        attempt_token = str(uuid.uuid4())
        output = self.work/(key(spec)+"-"+attempt_token)
        command = [sys.executable, str(Path(__file__).with_name("megascene.py")),
                   "--case",spec["case"],"--side-m",str(32*spec["q"]),
                   "--seed",str(spec["seed"]),"--threads",str(spec["threads"]),
                   "--resolution",spec["resolution"],"--profile",spec["profile"],
                   "--fragment-budget",spec["fragment_budget"],"--schedule",spec["schedule"],
                   "--warmup",spec["warmup"],"--frames",spec["frames"],
                   "--archive",str(self.archive),"--output",str(output)]
        if spec["case"] == "static":
            command += ["--capture-opening"]
        if spec["diagnostic"]:
            command += ["--diagnostic",spec["diagnostic"]]
        previous = next((a for a in self.attempts(spec) if
                         Path(a["archive"]).joinpath("validation.json").is_file() and
                         read_json((Path(a["archive"])/"validation.json").read_text()).get("status") == "pass"),None)
        if previous and not self.fixture:
            command += ["--validated",previous["archive"]]
        if self.additional:
            command += ["--additional-allowance",str(self.additional)]
            self.additional = 0
        self.append("proposal", {"point":spec,"reason":reason,"output":str(output),
                                 "attempt_token":attempt_token,"command":command})
        result = runner(command,output,spec) if runner else subprocess.run(command,check=False).returncode
        try:
            observed = inspect(output,spec,self.fixture)
        except (ValueError,KeyError,OSError,TypeError) as exc:
            observed = {"attempt_id":attempt_token,"archive":str(output),"inventory":None,
                        "workload_fingerprint":None,"labels":{name:"inconclusive" for name in
                            ("interactive","time_budget","capacity","observed_capacity_failure")},
                        "cause":"evidence_failure","synthetic":self.fixture,"inspection_error":str(exc)}
        if result != 0:
            observed["labels"] = {name:"inconclusive" for name in
                                  ("interactive","time_budget","capacity","observed_capacity_failure")}
            observed["runner_failure"] = "nonzero runner return code"
        self.append("attempt", {"point":spec,"reason":reason,"output":str(output),
                                "returncode":result,"attempt_token":attempt_token,**observed})
        if reason == "targeted_diagnostic":
            self.assess_diagnostic(spec,observed,attempt_token)
        self.save()
        return observed

    def run(self, limit=None, runner=None):
        count = 0
        while True:
            spec, reason = self.next_task()
            if spec is None:
                self.append("stop",{"reason":"search_plan_complete",
                                    "operational_cap_q":"5", "next_unsupported_growth_q":str(next_growth(4)),
                                    "physical_exhaustion_established":False,
                                    "untested_gaps":summarize(self.events,self.fixture)["untested_main"]})
                self.save()
                return
            if limit is not None and count >= limit:
                self.append("stop",{"reason":"declared_dispatch_limit", "next_point":spec})
                self.save()
                return
            remaining, state = _campaign_remaining(self.archive)
            if not self.fixture and not self.additional and (remaining <= 0 or state == "interrupted"):
                self.append("stop",{"reason":"campaign_allowance_or_interruption", "remaining_ns":str(remaining),
                                    "next_point":spec})
                self.save()
                return
            observed = self.dispatch(spec,reason,runner)
            count += 1
            if (observed["cause"] in POLICY_STOPS or observed["cause"] == "evidence_failure" or
                    all(value == "inconclusive" for value in observed["labels"].values())):
                self.append("stop",{"reason":"policy_or_evidence_stop", "cause":observed["cause"],
                                    "point":spec,"attempt_id":observed["attempt_id"]})
                self.save()
                return


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    p.add_argument("--archive",type=Path,required=True,help="durable campaign archive root")
    p.add_argument("--work",type=Path,required=True,help="separate local attempt output root")
    p.add_argument("--additional-allowance",type=int,default=0)
    p.add_argument("--dispatch-limit",type=int,help="explicit maximum runner invocations this command")
    args=p.parse_args(argv)
    require(0 <= args.additional_allowance <= 86400 and
            (args.dispatch_limit is None or args.dispatch_limit >= 1), "invalid allowance/dispatch limit")
    search=Search(args.archive,args.work,args.additional_allowance)
    search.run(args.dispatch_limit)
    print(search.path/"state.json")


if __name__=="__main__":
    main()
