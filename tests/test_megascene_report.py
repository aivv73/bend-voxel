"""Independent synthetic outcome examples for the public attempt report boundary."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))
from megascene_inventory import SCHEMA, canonical, outcome
from megascene_report import SCOPE_KEYS, classify, report_bundle
from megascene_supervisor import audit_allocations


def fixture(case="static", slow=False, count=None):
    edits = {"static":0,"localized":1,"history":120}[case]
    if count is not None:
        edits = count
    config = {"case":case,"preset":"small","seed":"45","threads":"6","resolution":"1920x1080",
              "profile":"full","schedule":case+"-v1","diagnostic":None,"control":None,
              "fragment_budget":"2048","warmup":"0","frames":"3600"}
    manifest = {"schema":SCHEMA,"record_type":"manifest","attempt_id":"fixture","series_id":"fixture",
                "campaign_id":"fixture","attempt_kind":"development_observation","synthetic":True,
                "effective":config,"numeric_admission":outcome("pass","checked","attempt")}
    summary = {"schema":SCHEMA,"record_type":"summary","attempt_id":"fixture","synthetic":True,
               "schedule_completion":outcome("pass","complete","attempt"),
               **{key:outcome("pass","fixture","attempt") for key in
                  ("state_correctness","rendering_correctness","visual_quality","numeric_validity")},
               "termination":{"cause":"normal_exit","exit_code":"0","signal":None},
               "gpu_execution":{"required_evidence_complete":True,"errors":[]},"evidence_errors":[]}
    cpu, reference, current = [], [], 0
    startup = 34_000_000_000 if slow else 2_000_000_000
    def frame(i, duration, population):
        nonlocal current
        record={"record_type":"frame","frame":str(i),"population":population,"begin_ns":str(current),
                "end_ns":str(current+duration),"duration_ns":str(duration),"unit":"ns","status":"measured"}
        current += duration
        cpu.append(record)
        reference.append({k:record[k] for k in ("record_type","frame","begin_ns","end_ns")})
    frame(0,startup,"startup")
    # Exact static example: 54 s, mean/p95/p99/max = 15/16/20/32 ms.
    ordinary = ([14_000_000]*341+[15_000_000]*3078+[16_000_000]*144+
                [20_000_000]*36+[32_000_000])
    assert len(ordinary)==3600 and sum(ordinary)==54_000_000_000
    ordinary_index=0
    for i in range(1,3601):
        is_edit = i <= edits
        if is_edit:
            duration=200_000_000 if slow else 80_000_000
            cpu.append({"record_type":"action","frame":str(i),"action":str(i-1),"accepted":True})
            reference.append({"record_type":"action","action":str(i-1)})
            cpu.append({"record_type":"edit","frame":str(i),"action":str(i-1),"accepted":True,
                        "begin_ns":str(current),"end_ns":str(current+duration),"duration_ns":str(duration)})
            population="edit"
        else:
            duration=25_000_000 if slow else ordinary[ordinary_index]
            ordinary_index+=1
            population="ordinary"
        frame(i,duration,population)
    for i in (0,3600):
        cpu.insert(0,{"record_type":"checkpoint","frame":str(i)})
    cpu.append({"record_type":"complete","frame":"3601"})
    resources=[{"record_type":"host_sample"}]
    allocations=[{"record_type":"ledger_start","live_bytes":"0","peak_bytes":"0"}]
    summary["supervision"]={"launch_ns":"0","errors":[],"termination":summary["termination"],
                            "resource_samples":"1","allocation_records":"1","reference_records":str(len(reference)),
                            "allocation_ledger":audit_allocations(allocations,normal=True)}
    validation={"status":"pass","checked_frames":"3601"}
    comparison={"status":"pass","checked_frames":"2","checkpoints":[{"frame":"0"},{"frame":"3600"}]}
    calibration={"schema":SCHEMA,"status":"pass","reference":"calibration/control-set.json",
                 "scope":{key:config.get(key) for key in SCOPE_KEYS}}
    return dict(summary=summary,manifest=manifest,cpu=cpu,resources=resources,allocations=allocations,
                reference=reference,validation=validation,comparison=comparison,calibration=calibration,
                review={"status":"pass"})


def classify_fixture(data):
    return classify(**data)


class SyntheticOutcomes(unittest.TestCase):
    def test_static_success_and_one_cut_inconclusive(self):
        result=classify_fixture(fixture())
        ordinary=result["populations"]["ordinary"]
        self.assertEqual([ordinary[k] for k in ("mean","p95","p99","max")],
                         [15_000_000,16_000_000,20_000_000,32_000_000])
        self.assertEqual(result["measured_interval_ns"],"54000000000")
        self.assertEqual(result["qualified_capacity"]["status"],"pass")
        self.assertEqual(result["workload_completion"]["status"],"pass")
        self.assertEqual(result["interactive_pass"]["status"],"pass")
        self.assertEqual(result["edit_response"]["status"],"not_applicable")
        self.assertEqual(result["confirmed_endpoint"]["status"],"inconclusive")
        self.assertEqual(result["endpoint_eligible"]["status"],"inconclusive")
        cut=classify_fixture(fixture("localized"))
        self.assertEqual(cut["accepted_edits"]["samples_ns"],["80000000"])
        self.assertEqual(cut["qualified_capacity"]["status"],"pass")
        self.assertEqual(cut["edit_response"]["status"],"inconclusive")
        self.assertEqual(cut["interactive_pass"]["status"],"inconclusive")

    def test_slow_history_and_failure_dimensions(self):
        history=classify_fixture(fixture("history",slow=True))
        self.assertEqual(history["accepted_edits"]["count"],"120")
        self.assertEqual(history["qualified_capacity"]["status"],"pass")
        self.assertEqual(history["responsiveness"]["status"],"fail")
        self.assertEqual(history["interactive_pass"]["status"],"fail")
        for status in ("not_executed","insufficient","noisy","failed","inapplicable"):
            data=fixture();data["calibration"]["status"]=status
            self.assertEqual(classify_fixture(data)["interactive_pass"]["status"],"inconclusive")
        data=fixture();data["manifest"]["attempt_kind"]="calibration_off"
        self.assertEqual(classify_fixture(data)["interactive_pass"]["status"],"inconclusive")
        data=fixture();data["calibration"]["scope"]["threads"]="12"
        with self.assertRaisesRegex(ValueError,"scope/reference"):classify_fixture(data)

    def test_policy_monitor_reserve_allocation_gpu_quality_and_interruption(self):
        cases=(
            ("required_edit_rejection","fail","fail"),
            ("monitoring_failure","inconclusive","inconclusive"),
            ("process_rss_reserve","fail","fail"),
            ("allocation_error","fail","fail"),
            ("external_interruption","inconclusive","inconclusive"),
        )
        for cause,capacity,interactive in cases:
            with self.subTest(cause=cause):
                data=fixture("localized");data["summary"]["termination"]["cause"]=cause
                data["summary"]["supervision"]["termination"]["cause"]=cause
                if cause=="process_rss_reserve":
                    data["summary"]["termination"]["reason"]="host_sample time_ns=1 rss_bytes=21474836480"
                if cause=="allocation_error":
                    failed={"record_type":"allocation_failed","allocation_id":"1","size_bytes":"4096",
                            "heap":"0","memory_type":"0","device":"fixture","vk_result":"-2",
                            "live_bytes":"0","peak_bytes":"0","heap_live_bytes":"0","heap_peak_bytes":"0"}
                    data["allocations"].append(failed)
                    data["summary"]["supervision"].update(allocation_records="2",
                        allocation_ledger=audit_allocations(data["allocations"]))
                if cause=="required_edit_rejection":
                    for r in data["cpu"]:
                        if r["record_type"] in ("action","edit"):r["accepted"]=False
                result=classify_fixture(data)
                self.assertEqual(result["qualified_capacity"]["status"],capacity)
                self.assertEqual(result["interactive_pass"]["status"],interactive)
                self.assertEqual(result["termination"]["cause"],cause)
        data=fixture();data["summary"]["gpu_execution"]["required_evidence_complete"]=False
        result=classify_fixture(data)
        self.assertEqual(result["qualified_capacity"]["status"],"pass")
        self.assertEqual(result["measurement_availability"]["gpu"]["status"],"inconclusive")
        self.assertEqual(result["interactive_pass"]["status"],"inconclusive")
        for key in ("rendering_correctness","visual_quality","numeric_validity"):
            data=fixture();data["summary"][key]["status"]="fail"
            result=classify_fixture(data)
            self.assertEqual(result["qualified_capacity"]["status"],"fail",key)
            self.assertEqual(result["workload_completion"]["status"],"fail",key)
        data=fixture();data["summary"]["numeric_validity"]["status"]="inconclusive"
        self.assertEqual(classify_fixture(data)["workload_completion"]["status"],"inconclusive")
        data=fixture();data["review"]={"status":"incorrect_rendering"}
        self.assertEqual(classify_fixture(data)["rendering_correctness"]["status"],"fail")

    def test_missing_duplicate_and_inconsistent_evidence(self):
        mutations=(lambda d:d["cpu"].pop(),
                   lambda d:d["cpu"].append(copy.deepcopy(d["cpu"][-1])),
                   lambda d:d["reference"].pop(),
                   lambda d:d["comparison"]["checkpoints"].pop(),
                   lambda d:d["summary"]["supervision"].update(resource_samples="2"),
                   lambda d:d["summary"]["supervision"]["termination"].update(cause="worker_error"))
        for change in mutations:
            data=fixture();change(data)
            self.assertNotEqual(classify_fixture(data)["interactive_pass"]["status"],"pass")
        data=fixture();data["summary"]["schedule_completion"] = outcome("inconclusive","required replay evidence failed","attempt")
        self.assertNotEqual(classify_fixture(data)["schedule_completion"]["status"],"pass")
        extra=fixture();extra["cpu"].insert(-1,{"record_type":"action","frame":"1","action":"0","accepted":True})
        self.assertNotEqual(classify_fixture(extra)["schedule_completion"]["status"],"pass")
        data=fixture();next(r for r in data["cpu"] if r["record_type"]=="frame" and r["frame"]=="1000")["frame"]="999"
        prefix=classify_fixture(data)
        self.assertEqual(prefix["completed_prefix"]["measured"],"999")
        self.assertEqual(prefix["schedule_completion"]["status"],"inconclusive")
        self.assertEqual(prefix["measurement_availability"]["cpu"]["status"],"inconclusive")


class PublicBoundary(unittest.TestCase):
    def test_schema_extensions_truncated_tail_and_measured_zero(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);data=fixture();manifest=data["manifest"];summary=data["summary"]
            manifest["effective"]["frames"]="1"
            summary["supervision"]["launch_ns"]="2000000000"
            (root/"manifest.json").write_bytes(canonical(manifest)+b"\n")
            (root/"summary.json").write_bytes(canonical(summary)+b"\n")
            identity={"schema":SCHEMA,"campaign_id":"fixture","series_id":"fixture","attempt_id":"fixture",
                      "clock_id":"linux.CLOCK_MONOTONIC"}
            first={**identity,"record_type":"frame","sequence":"0","time_ns":"2000000000","frame":"0",
                   "begin_ns":"2000000000","end_ns":"2000000000","duration_ns":"0","status":"measured",
                   "unit":"ns","population":"startup"}
            second={**first,"sequence":"1","frame":"1","population":"ordinary","time_ns":"2000000001",
                    "end_ns":"2000000001","duration_ns":"1"}
            complete={**identity,"record_type":"complete","sequence":"2","time_ns":"2000000001","frame":"2"}
            (root/"cpu.jsonl").write_bytes(b"".join(canonical(r)+b"\n" for r in (first,second,complete)))
            result=report_bundle(root)
            self.assertEqual(result["cold_startup"]["value"],"0")
            self.assertEqual(result["populations"]["ordinary"]["samples_ns"],["1"])
            self.assertEqual(result["interactive_pass"]["status"],"inconclusive")
            with (root/"cpu.jsonl").open("ab") as stream:stream.write(b'{"damaged":')
            self.assertTrue(any("truncated" in error for error in report_bundle(root)["evidence_errors"]))
            manifest["schema"]="megascene-evidence/2"
            (root/"manifest.json").write_bytes(canonical(manifest)+b"\n")
            with self.assertRaisesRegex(ValueError,"unsupported manifest schema"):report_bundle(root)
            manifest["schema"]=SCHEMA;manifest["extensions"]={"effective":{}}
            (root/"manifest.json").write_bytes(canonical(manifest)+b"\n")
            with self.assertRaisesRegex(ValueError,"extension overrides"):report_bundle(root)


if __name__=="__main__":unittest.main()
