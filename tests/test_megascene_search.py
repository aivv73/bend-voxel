"""Controlled search workers and synthetic evidence; no benchmark claims."""

import os
from pathlib import Path
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))

from megascene import snapshot
from megascene_inventory import SCHEMA, read_json
from megascene_search import Search, inspect, labels, outcome_for, point, refinement_candidate, summarize


def worker(kind="pass", inventory_delta=0):
    def run(command, output, spec):
        output.mkdir(parents=True)
        attempt_id = str(uuid.uuid4())
        cause = {"pass":"normal_exit", "slow":"normal_exit", "timeout":"case_deadline",
                 "allocation":"allocation_error", "monitor":"monitoring_failure",
                 "budget":"required_edit_rejection", "numeric":"rejected_request"}[kind]
        config = {"case":spec["case"],"preset":spec["preset"],"side_m":str(32*spec["q"]),"seed":str(spec["seed"]),
                  "threads":str(spec["threads"]),"resolution":spec["resolution"],
                  "profile":spec["profile"],"schedule":spec["schedule"],
                  "fragment_budget":spec["fragment_budget"],"warmup":spec["warmup"],
                  "frames":spec["frames"],"diagnostic":None if spec["diagnostic"] in
                  ("spread","fill","body-rich","material-detail","surface-detail") else spec["diagnostic"],
                  "control":spec["diagnostic"] if spec["diagnostic"] in
                  ("spread","fill","body-rich","material-detail","surface-detail") else None}
        snapshot(output/"manifest.json",{"schema":SCHEMA,"record_type":"manifest",
                 "synthetic":True,"attempt_id":attempt_id,"effective":config,
                 "reproduction":{"archive":str(output)}})
        snapshot(output/"summary.json",{"schema":SCHEMA,"record_type":"summary",
                 "synthetic":True,"attempt_id":attempt_id,"termination":{"cause":cause},
                 "qualified_capacity":{"status":"pass" if kind in ("pass","slow") else "fail"},
                 "responsiveness":{"status":"fail" if kind == "slow" else "pass" if kind == "pass" else "inconclusive"},
                 "interactive_pass":{"status":"pass" if kind == "pass" else "fail" if kind == "slow" else "inconclusive"},
                 "observed_capacity_failure":{"status":"inconclusive"}})
        snapshot(output/"validation.json",{"schema":SCHEMA,"status":"pass",
                 "synthetic":True,"attempt_id":str(uuid.uuid4())})
        (output/"validation").mkdir()
        snapshot(output/"validation/inventory.json",{"schema":SCHEMA,"q":spec["q"],
                 "cells":str(1000*spec["q"]+inventory_delta),"diagnostic":spec["diagnostic"]})
        snapshot(output/"schedule.json",{"schema":SCHEMA,"schedule_id":spec["schedule"]})
        snapshot(output/"inputs.json",{"schema":SCHEMA,"seed":str(spec["seed"])})
        return 0
    return run


class SearchPolicy(unittest.TestCase):
    def search(self):
        temp = tempfile.TemporaryDirectory()
        root = Path(temp.name)
        return temp,Search(root/"archive",root/"work",fixture=True)

    def test_only_pass_only_fail_and_synthetic_exclusion(self):
        temp,search = self.search()
        with temp:
            for _ in range(3):
                search.dispatch(point("static",2),"test",worker("pass"))
                search.dispatch(point("history",2),"test",worker("timeout"))
            state = summarize(search.events,simulation=True)
            self.assertEqual(state["bounds"]["static"]["capacity"]["largest_confirmed_pass"]["point"]["q"],2)
            self.assertIsNone(state["bounds"]["static"]["capacity"]["nearest_confirmed_larger_failure"])
            self.assertIsNone(state["bounds"]["history"]["time_budget"]["largest_confirmed_pass"])
            self.assertEqual(state["bounds"]["history"]["time_budget"]["nearest_confirmed_larger_failure"]["point"]["q"],2)
            self.assertEqual(summarize(search.events)["points"][next(iter(state["points"]))]["outcomes"]["capacity"]["status"],"excluded")

    def test_planner_runs_breadth_first_and_confirms_only_pass_endpoints(self):
        temp,search=self.search()
        with temp:
            search.run(limit=100,runner=worker("pass"))
            attempts=[e for e in search.events if e["kind"]=="attempt"]
            self.assertEqual([a["point"]["q"] for a in attempts[:24]],
                             [q for q in (2,3,4,5) for _ in range(6)])
            self.assertEqual(len(attempts),36)
            state=summarize(search.events,True)
            self.assertEqual(len(list((search.path/"series").glob("*.json"))),24)
            for case in ("static","traversal","picking","localized","support","history"):
                bound=state["bounds"][case]["capacity"]
                self.assertEqual(bound["largest_confirmed_pass"]["point"]["q"],5)
                self.assertIsNone(bound["nearest_confirmed_larger_failure"])
            self.assertEqual(search.events[-1]["reason"],"search_plan_complete")

    def test_planner_only_fail_keeps_policy_and_diagnostics_separate(self):
        temp,search=self.search()
        with temp:
            search.run(limit=100,runner=worker("timeout"))
            state=summarize(search.events,True)
            for case in ("static","traversal","picking","localized","support","history"):
                bound=state["bounds"][case]["time_budget"]
                self.assertIsNone(bound["largest_confirmed_pass"])
                self.assertEqual(bound["nearest_confirmed_larger_failure"]["point"]["q"],2)
                self.assertIsNone(state["bounds"][case]["observed_capacity_failure"]["nearest_confirmed_larger_failure"])
            self.assertTrue(any(e["kind"]=="diagnostic_assessment" for e in search.events))
            self.assertTrue(all(a["point"]["q"]==2 for a in search.events if a["kind"]=="attempt"))

    def test_planner_preserves_mixed_causes(self):
        temp,search=self.search()
        with temp:
            def controlled(command,output,spec):
                kind=("timeout" if not search.attempts(spec) else "allocation") if spec==point("static",2) else "pass"
                return worker(kind)(command,output,spec)
            search.run(limit=100,runner=controlled)
            self.assertEqual(len(search.attempts(point("static",2))),2)
            entry=summarize(search.events,True)["points"]
            static=next(v for v in entry.values() if v["point"]==point("static",2))
            self.assertEqual(static["outcomes"]["time_budget"]["status"],"unstable")
            self.assertEqual(static["outcomes"]["observed_capacity_failure"]["status"],"unstable")

    def test_planner_preserves_nonmonotonicity(self):
        temp,search=self.search()
        with temp:
            def controlled(command,output,spec):
                return worker("slow" if spec==point("static",2) else "pass")(command,output,spec)
            search.run(limit=100,runner=controlled)
            bounds=summarize(search.events,True)["bounds"]["static"]["interactive"]
            self.assertEqual(bounds["nonmonotonic_fail_then_pass"],[(2,5)])
            self.assertEqual(bounds["refinement_status"],"nonmonotonic")

    def test_mixed_causes_and_nonmonotonic_interactive_points(self):
        temp,search = self.search()
        with temp:
            search.dispatch(point("static",2),"test",worker("timeout"))
            search.dispatch(point("static",2),"test",worker("allocation"))
            entry = summarize(search.events,True)["points"]
            self.assertEqual(entry[next(iter(entry))]["outcomes"]["time_budget"]["status"],"unstable")
            for _ in range(3):
                search.dispatch(point("history",2),"test",worker("slow"))
                search.dispatch(point("history",3),"test",worker("pass"))
            bounds = summarize(search.events,True)["bounds"]["history"]["interactive"]
            self.assertEqual(bounds["nonmonotonic_fail_then_pass"],[(2,3)])
            self.assertIsNone(bounds["nearest_confirmed_larger_failure"])

    def test_allocation_retry_requires_two_and_scope_matches(self):
        temp,search = self.search()
        with temp:
            spec = point("static",2)
            search.dispatch(spec,"test",worker("allocation"))
            rows = search.attempts(spec)
            self.assertEqual(outcome_for(rows,"observed_capacity_failure",True)["status"],"observed")
            search.dispatch(spec,"allocation_diagnostic_retry",worker("allocation"))
            confirmed = outcome_for(search.attempts(spec),"observed_capacity_failure",True)
            self.assertEqual((confirmed["status"],confirmed["evidence_count"]),("confirmed",2))
            search.dispatch(spec,"test",worker("allocation",1))
            self.assertEqual(outcome_for(search.attempts(spec),"observed_capacity_failure",True)["status"],"unstable")
            self.assertIsNone(summarize(search.events,True)["bounds"]["static"]["capacity"]["nearest_confirmed_larger_failure"])

    def test_discrete_area_midpoint_refinement_candidate(self):
        temp,search=self.search()
        with temp:
            for _ in range(3):
                search.dispatch(point("static",2),"test",worker("pass"))
            for _ in range(2):
                search.dispatch(point("static",5),"test",worker("allocation"))
            state=summarize(search.events,True)
            self.assertEqual(refinement_candidate(state,"static","observed_capacity_failure"),4)
            self.assertEqual(state["bounds"]["static"]["observed_capacity_failure"]["untested_q_between"],[3,4])

    def test_missing_workload_identity_cannot_confirm_endpoint(self):
        temp,search=self.search()
        with temp:
            spec=point("static",2)
            for _ in range(3):
                search.dispatch(spec,"test",worker("pass"))
            rows=[dict(a,workload_fingerprint=None) for a in search.attempts(spec)]
            self.assertEqual(outcome_for(rows,"capacity",True)["status"],"observed")
            with self.assertRaisesRegex(ValueError,"synthetic attempt"):
                inspect(Path(rows[0]["archive"]),spec)

    def test_policy_stops_never_become_physical_failures(self):
        for kind in ("monitor","budget","numeric"):
            temp,search = self.search()
            with temp:
                search.dispatch(point("static",2),"test",worker(kind))
                entry = next(iter(summarize(search.events,True)["points"].values()))
                self.assertEqual(entry["attempts"][0]["labels"]["observed_capacity_failure"],"inconclusive")
                self.assertIsNone(summarize(search.events,True)["bounds"]["static"]["capacity"]["nearest_confirmed_larger_failure"])

    def test_interrupt_resume_and_pending_proposal(self):
        temp,search = self.search()
        with temp:
            search.run(limit=1,runner=worker("pass"))
            self.assertEqual(len(search.attempts(point("static",2))),1)
            with self.assertRaisesRegex(ValueError,"additional-allowance"):
                Search(search.archive,search.work,fixture=True)
            resumed = Search(search.archive,search.work,additional=7,fixture=True)
            resumed.run(limit=1,runner=worker("pass"))
            self.assertEqual(len(resumed.attempts(point("static",2))),1)
            self.assertEqual(len(resumed.attempts(point("traversal",2))),1)
            self.assertEqual([e["sequence"] for e in resumed.events],list(map(str,range(len(resumed.events)))))
            resumed.append("proposal",{"point":point("picking",2),"reason":"coarse_growth",
                        "output":str(resumed.work/"lost"),"attempt_token":"lost","command":[]})
            recovered = Search(search.archive,search.work,additional=3,fixture=True)
            self.assertEqual(recovered.attempts(point("picking",2))[0]["cause"],"external_interruption")
            self.assertEqual(recovered.next_task()[0],point("localized",2))

    def test_resume_reassesses_retained_attempt_without_overwriting_it(self):
        temp,search=self.search()
        with temp:
            spec=point("static",2)
            search.dispatch(spec,"coarse_growth",worker("pass"))
            original=search.attempts(spec)[0]
            bundle=Path(original["archive"])
            summary=read_json((bundle/"summary.json").read_text())
            summary["responsiveness"]["status"]="fail"
            summary["interactive_pass"]["status"]="fail"
            snapshot(bundle/"summary.json",summary)
            resumed=Search(search.archive,search.work,additional=10,fixture=True)
            self.assertEqual(original["labels"]["interactive"],"pass")
            self.assertEqual(resumed.attempts(spec)[0]["labels"]["interactive"],"fail:responsiveness")
            self.assertEqual(len(resumed.attempts(spec)),1)
            self.assertEqual(len([e for e in resumed.events if e["kind"]=="reassessment"]),1)

    def test_diagnostic_dispatch_has_own_scope_and_inventory(self):
        temp,search = self.search()
        with temp:
            baseline=point("history",2)
            variant=point("history",2,diagnostic="body-rich")
            prefix=point("history",2,schedule="history-12-v1")
            for spec in (baseline,variant,prefix):
                search.dispatch(spec,"targeted_diagnostic",worker("pass"))
            records = [search.attempts(spec)[0] for spec in (baseline,variant,prefix)]
            self.assertEqual(len({r["validation_attempt_id"] for r in records}),3)
            self.assertEqual(len({r["workload_fingerprint"] for r in records}),3)
            self.assertEqual(variant["schedule"],"body-rich-history-v1")
            self.assertEqual(prefix["schedule"],"history-12-v1")
            state=summarize(search.events,True)
            for spec in (variant,prefix):
                assessment=state["points"][next(k for k,v in state["points"].items() if v["point"]==spec)]["diagnostic_assessments"]
                self.assertEqual(len(assessment),1)
                self.assertEqual(assessment[0]["status"],"simulated")
                self.assertEqual(read_json(Path(assessment[0]["assessment"]).read_text())["status"],"simulated")

    def test_resume_recovers_orphaned_diagnostic_assessment(self):
        temp,search=self.search()
        with temp:
            search.dispatch(point("static",2),"coarse_growth",worker("pass"))
            spec=point("static",2,diagnostic="spread")
            output=search.work/"interrupted-control"
            worker("pass")([],output,spec)
            observed=inspect(output,spec,fixture=True)
            search.append("attempt",{"point":spec,"reason":"targeted_diagnostic",
                      "output":str(output),"returncode":0,"attempt_token":"orphan",**observed})
            recovered=Search(search.archive,search.work,additional=5,fixture=True)
            assessments=[e for e in recovered.events if e["kind"]=="diagnostic_assessment"]
            self.assertEqual(len(assessments),1)
            self.assertEqual(assessments[0]["status"],"simulated")


@unittest.skipUnless(os.environ.get("MEGASCENE_VULKAN_TEST") == "1", "opt-in bounded real Vulkan dispatch")
class SearchVulkan(unittest.TestCase):
    def test_short_real_dispatch_is_retained_without_endpoint(self):
        with tempfile.TemporaryDirectory(prefix="megascene-search-",dir=Path.home()) as d:
            root=Path(d)
            search=Search(root/"archive",root/"work")
            spec={**point("static",2),"resolution":"640x360","warmup":"1","frames":"2"}
            observed=search.dispatch(spec,"bounded_integration")
            self.assertEqual(observed["cause"],"normal_exit")
            self.assertEqual(observed["inventory_source"],"inventory.json")
            self.assertEqual(observed["labels"]["capacity"],"inconclusive")
            self.assertTrue((Path(observed["archive"])/"manifest.json").is_file())
            self.assertEqual(read_json((Path(observed["archive"])/"summary.json").read_text())["opening_capture"]["status"],"pass")


if __name__=="__main__":
    unittest.main()
