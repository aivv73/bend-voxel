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
from megascene_evidence import run as evidence

def point(case, q, seed=45, threads=6, diagnostic=None, schedule=None):
    return evidence("point", {"case": case, "q": q, "seed": seed, "threads": threads,
                              "diagnostic": diagnostic, "schedule": schedule}, "evidence_search")


def key(spec):
    return hashlib.sha256(canonical(spec)).hexdigest()[:20]


def labels(report):
    return evidence("labels", report, "evidence_search")


def outcome_for(rows, dimension, simulation=False):
    return evidence("outcome_for", {"rows": rows, "dimension": dimension,
                                    "simulation": simulation}, "evidence_search")


def _main_keys():
    return [{"point": spec, "key": key(spec)}
            for spec in evidence("main_points", None, "evidence_search")]


def _event_input(events, simulation=False):
    return {"events": events, "simulation": simulation, "main_keys": _main_keys(),
            "keys": [{"event_index": index, "key": key(event["point"])}
                     for index, event in enumerate(events) if event.get("kind") == "attempt"]}


def summarize(events, simulation=False):
    result = evidence("summarize", _event_input(events, simulation), "evidence_search")
    for categories in result["bounds"].values():
        for bound in categories.values():
            bound["nonmonotonic_fail_then_pass"] = [tuple(pair) for pair in
                                                    bound["nonmonotonic_fail_then_pass"]]
    return result


def refinement_candidate(state, case, dimension):
    return evidence("refinement_candidate", {"state": state, "case": case,
                                             "dimension": dimension, "main_keys": _main_keys()}, "evidence_search")


def _fingerprint(root, manifest, inventory):
    from megascene_bend import DEPENDENCIES, dependency_files, source_directory

    config = manifest["effective"]
    actual = {k: v for k,v in inventory.items() if k not in ("validation", "attempt_id", "campaign_id", "series_id")}
    classifier = {name:hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                  for name in ("megascene_search.py","megascene_report.py","megascene_checkpoints.py",
                               "megascene_review.py","megascene_evidence.py","megascene_bend.py")}
    policy_sources = {name for module, dependencies in DEPENDENCIES.items()
                      if module.startswith("evidence_") for name in dependency_files(dependencies)}
    classifier.update({"generator/" + name: hashlib.sha256(
        (source_directory() / name).read_bytes()).hexdigest() for name in sorted(policy_sources)})
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
        if evidence("calibration_reassess", value, "evidence_search"):
            from megascene_calibration_series import assess
            assessment = assess(series.with_name("series.json"))
            evidence("calibration_binding", {"assessment": assessment, "calibration": value,
                                              "reference": str(series.with_name("assessment.json"))},
                     "evidence_search")
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
    scope = evidence("inspect_scope", {"manifest": manifest, "summary": summary,
                                        "expected": expected, "fixture": fixture}, "evidence_search")
    config, synthetic = scope["config"], scope["synthetic"]
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
        evidence("validation_gate", {"validation": validation, "fixture": fixture}, "evidence_search")
        if fixture:
            report = summary
            fingerprint = hashlib.sha256(canonical({"point":expected,"inventory":inventory,
                "schedule":read_json((root/"schedule.json").read_text())})).hexdigest()
        else:
            applicable(validation,identity(manifest,root,config))
            verify_evidence(manifest,root,("validation.json", "validation/inventory.json", "summary.json"))
            if (root/"inventory.json").is_file():
                verify_evidence(manifest,root,("inventory.json",))
                timed_inventory = read_json((root/"inventory.json").read_text())
                evidence("timed_inventory_gate", {"timed": timed_inventory, "validated": validated_inventory},
                         "evidence_search")
                inventory = timed_inventory
                inventory_source = "inventory.json"
            calibration, calibration_source = _calibration(config,root)
            report = report_bundle(root,calibration)
            evidence("capacity_inventory_gate", {"report": report, "inventory_source": inventory_source},
                     "evidence_search")
            fingerprint = _fingerprint(root,manifest,inventory)
    else:
        report = summary
    partial = False
    if not complete and not fixture:
        try:
            report = report_bundle(root)
            partial = True
        except (ValueError, KeyError, OSError):
            pass
    return evidence("inspect_result", {"manifest": manifest, "config": config, "expected": expected,
                                        "archive": str(root), "inventory": inventory,
                                        "inventory_source": inventory_source, "fingerprint": fingerprint,
                                        "calibration_source": calibration_source, "report": report,
                                        "complete": complete, "fixture": fixture, "partial": partial,
                                        "validation": validation if complete else None,
                                        "synthetic": synthetic}, "evidence_search")


def _campaign_remaining(archive):
    path = archive/"campaign.json"
    if not path.exists():
        return 7200 * 1_000_000_000, "new"
    c = read_json(path.read_text())
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    remaining = evidence("runner_remaining", {"campaign": c, "boot_id": boot,
                                               "monotonic_ns": time.monotonic_ns(),
                                               "utc_ns": time.time_ns(), "lease_always": True},
                         "evidence_acceptance")
    return remaining, c["state"]


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
        evidence("search_initial_gate", {"additional": additional, "existing": existing,
                                         "campaign": had_campaign}, "evidence_search")
        if not fixture and not had_campaign:
            from megascene_supervisor import Campaign
            campaign = Campaign(self.archive)
            campaign.close(True)
        if existing:
            for raw in self.log.read_bytes().splitlines(keepends=True):
                require(raw.endswith(b"\n"), "truncated search evidence")
                e = read_json(raw.decode())
                evidence("event_record_gate", {"event": e, "sequence": len(self.events)}, "evidence_search")
                self.events.append(e)
        else:
            evidence("search_new_gate", {"additional": additional, "fixture": fixture}, "evidence_search")
            campaign_record = read_json((self.archive/"campaign.json").read_text()) if not fixture else None
            self.append("start", {"archive":str(self.archive), "work":str(self.work), "simulation":fixture,
                                  "additional_allowance_s":str(additional),
                                  "initial_allowance_s":"7200",
                                  "campaign_id":campaign_record["campaign_id"] if campaign_record else None})
        evidence("search_resume_gate", {"first": self.events[0], "archive": str(self.archive),
                                         "work": str(self.work), "fixture": fixture,
                                         "existing": existing, "additional": additional}, "evidence_search")
        if existing:
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
        for identifier, record in evidence("series_records", state, "evidence_search").items():
            snapshot(series/(identifier+".json"), record)

    def recover_pending(self):
        for proposal in evidence("recover_pending", self.events, "evidence_search"):
            try:
                observed = inspect(Path(proposal["output"]),proposal["point"],self.fixture)
            except (ValueError,KeyError,OSError,TypeError) as exc:
                observed = evidence("inspection_failure", {"attempt_id": proposal["attempt_token"],
                    "archive": proposal["output"], "cause": "external_interruption",
                    "fixture": self.fixture, "error": str(exc)}, "evidence_search")
            self.append("attempt",{"point":proposal["point"],"reason":proposal["reason"],
                                   "output":proposal["output"],"returncode":None,
                                   "attempt_token":proposal["attempt_token"],**observed})
            if proposal["reason"] == "targeted_diagnostic":
                self.assess_diagnostic(proposal["point"],observed,proposal["attempt_token"])

    def recover_diagnostics(self):
        for attempt in evidence("recover_diagnostics", self.events, "evidence_search"):
            token = attempt["attempt_token"]
            path = self.path/"comparisons"/(token+".json")
            if path.is_file():
                result = read_json(path.read_text())
                evidence("orphaned_diagnostic", {"result": result, "attempt": attempt}, "evidence_search")
                self.append("diagnostic_assessment",{"point":attempt["point"],
                    "attempt_id":attempt["attempt_id"],"assessment":str(path),"status":result["status"]})
            else:
                self.assess_diagnostic(attempt["point"],attempt,token)

    def reassess_archives(self):
        for original in evidence("events_of", {"events": self.events, "kind": "attempt"}, "evidence_search"):
            try:
                updated = inspect(Path(original["output"]),original["point"],self.fixture)
            except (ValueError,KeyError,OSError,TypeError):
                if evidence("reassessment_failure", original, "evidence_search"):
                    continue
                raise
            reassessed = evidence("reassessment", {"original": original, "updated": updated,
                                                    "events": self.events}, "evidence_search")
            if reassessed is not None:
                self.append("reassessment", reassessed)

    def reassess_diagnostics(self):
        for attempt in evidence("reassess_diagnostics", self.events, "evidence_search"):
            self.assess_diagnostic(attempt["point"],attempt,attempt["attempt_token"]+"-"+str(uuid.uuid4()))

    def all_attempts(self):
        return evidence("all_attempts", self.events, "evidence_search")

    def attempts(self, spec):
        return evidence("attempts", {"events": self.events, "point": spec}, "evidence_search")

    def assess_diagnostic(self, spec, observed, token):
        prepared = evidence("diagnostic_prepare", {"events": self.events, "point": spec,
                                                    "observed": observed}, "evidence_search")
        baseline, result = prepared["baseline"], prepared["result"]
        try:
            stage = evidence("diagnostic_gate", {"baseline": baseline, "observed": observed,
                                                  "fixture": self.fixture, "point": spec,
                                                  "result": result}, "evidence_search")
            result = stage["result"]
            comparison = None
            if stage["mode"] == "control":
                from megascene_compare_controls import compare
                comparison = compare(baseline["archive"], observed["archive"])
            elif stage["mode"] == "schedule":
                from megascene_compare_schedules import compare
                comparison = compare(baseline["archive"], observed["archive"])
            result = evidence("diagnostic_finish", {"result": result, "comparison": comparison,
                                                    "error": None}, "evidence_search")
        except (ValueError,KeyError,OSError,TypeError) as exc:
            result = evidence("diagnostic_finish", {"result": result, "comparison": None,
                                                    "error": str(exc)}, "evidence_search")
        path = self.path/"comparisons"/(token+".json")
        path.parent.mkdir(exist_ok=True)
        snapshot(path,result)
        self.append("diagnostic_assessment",{"point":spec,"attempt_id":observed["attempt_id"],
                                              "assessment":str(path),"status":result["status"]})

    def next_task(self):
        return tuple(evidence("next_task", _event_input(self.events, self.fixture), "evidence_search"))

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
                         evidence("validation_pass", read_json((Path(a["archive"])/"validation.json").read_text()),
                                  "evidence_search")),None)
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
            observed = evidence("inspection_failure", {"attempt_id": attempt_token, "archive": str(output),
                "cause": "evidence_failure", "fixture": self.fixture, "error": str(exc)}, "evidence_search")
        observed = evidence("returncode_suppression", {"observed": observed, "returncode": result,
                                                        "reassessment": False}, "evidence_search")
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
                self.append("stop", evidence("plan_complete", summarize(self.events,self.fixture), "evidence_search"))
                self.save()
                return
            stopped = evidence("dispatch_limit", {"limit": limit, "count": count,
                                                   "point": spec}, "evidence_search")
            if stopped is not None:
                self.append("stop", stopped)
                self.save()
                return
            remaining, state = _campaign_remaining(self.archive)
            stopped = evidence("campaign_gate", {"simulation": self.fixture,
                                                  "additional": self.additional,
                                                  "remaining_ns": remaining,
                                                  "state": state, "point": spec}, "evidence_search")
            if stopped is not None:
                self.append("stop", stopped)
                self.save()
                return
            observed = self.dispatch(spec,reason,runner)
            count += 1
            if evidence("policy_stop", observed, "evidence_search"):
                self.append("stop", evidence("policy_stop_record", {"observed": observed, "point": spec},
                                             "evidence_search"))
                self.save()
                return


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    p.add_argument("--archive",type=Path,required=True,help="durable campaign archive root")
    p.add_argument("--work",type=Path,required=True,help="separate local attempt output root")
    p.add_argument("--additional-allowance",type=int,default=0)
    p.add_argument("--dispatch-limit",type=int,help="explicit maximum runner invocations this command")
    args=p.parse_args(argv)
    evidence("cli_gate", {"additional": args.additional_allowance, "limit": args.dispatch_limit}, "evidence_search")
    search=Search(args.archive,args.work,args.additional_allowance)
    search.run(args.dispatch_limit)
    print(search.path/"state.json")


if __name__=="__main__":
    main()
