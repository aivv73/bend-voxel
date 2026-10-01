import copy
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from megascene_compare_controls import compare as compare_controls
from megascene_compare_schedules import compare as compare_schedules, geometry, removed
from megascene_evidence import run


class ComparisonEvidenceTests(unittest.TestCase):
    def test_frozen_python_control_and_schedule_results(self):
        cases = json.loads((ROOT / "tests/fixtures/evidence_comparison_parity.json").read_text())
        for index, case in enumerate(cases):
            payload = copy.deepcopy(case["payload"])
            if case["operation"] == "schedules":
                for label in ("baseline", "variant"):
                    frames = payload[label][4]["frames"]
                    payload[label][4]["frames"] = [copy.deepcopy(frames["value"]) for _ in range(frames["repeat"])]
                compare, loader = compare_schedules, "megascene_compare_schedules.load"
            else:
                compare, loader = compare_controls, "megascene_compare_controls.load"
            with self.subTest(index=index, operation=case["operation"]):
                with patch(loader, side_effect=(payload["baseline"], payload["variant"])):
                    if "error" in case:
                        expected_error = {"ValueError": ValueError, "KeyError": KeyError,
                                          "TypeError": TypeError}[case.get("exception", "ValueError")]
                        with self.assertRaises(expected_error) as error:
                            compare("baseline", "variant")
                        self.assertEqual(str(error.exception), case["error"])
                    else:
                        self.assertEqual(compare("baseline", "variant"), case["expected"])

    def test_geometry_retains_position_and_material_without_lifetime_ids(self):
        payload = {"bodies": [
            {"id": "20", "anchored": True, "occupancy": [["4", "5", "6"]],
             "surface": {"material": "🧩"}, "offset_m": "0x3f800000"},
            {"id": "7", "anchored": False, "occupancy": [["1", "2", "3"]],
             "surface": {"material": "stone"}, "offset_m": "0x00000000"}]}
        self.assertEqual(geometry(payload), [
            {"anchored": False, "occupancy": [["1", "2", "3"]],
             "surface": {"material": "stone"}, "offset_m": "0x00000000"},
            {"anchored": True, "occupancy": [["4", "5", "6"]],
             "surface": {"material": "🧩"}, "offset_m": "0x3f800000"}])

    def test_removed_cell_set_keeps_observed_owner_and_string_order(self):
        frozen = {"actions": [
            {"pre_edit_hit": {"owner": "2"}, "reference_removed_cells": [["-1", "0", "2", "3"]] * 2},
            {"pre_edit_hit": {"owner": "10"}, "reference_removed_cells": [["-1", "0", "2", "3"]]}]}
        self.assertEqual(removed(frozen), [("10", "-1", "0", "2", "3"), ("2", "-1", "0", "2", "3")])
        self.assertEqual(removed({"actions": [{"reference_removed_cells": []}]}), [])
        with self.assertRaises(KeyError) as error:
            removed({"actions": [{"reference_removed_cells": [["0"]]}]})
        self.assertEqual(str(error.exception), "'pre_edit_hit'")

    def test_control_load_needs_matching_independent_evidence(self):
        payload = {"manifest": {"attempt_id": "timed", "effective": {}},
                   "summary": {"attempt_id": "timed", "attempt_kind": "development_observation", "synthetic": False,
                       "state_correctness": {"status": "pass"}, "schedule_completion": {"status": "pass"},
                       "rendering_correctness": {"status": "pass"}},
                   "validation": {"status": "pass", "synthetic": False, "identity": {"capture": "bound"}},
                   "inventory": {"validation": "validation.json"}, "expected_identity": {"capture": "bound"}}
        self.assertIs(run("controls_load", payload, "evidence_comparison"), True)
        changed = copy.deepcopy(payload)
        changed["validation"]["identity"]["capture"] = "stale"
        with self.assertRaisesRegex(ValueError, "validation/runtime identity mismatch"):
            run("controls_load", changed, "evidence_comparison")
        changed = copy.deepcopy(payload)
        changed["summary"]["synthetic"] = True
        with self.assertRaisesRegex(ValueError, "complete nonsynthetic timed Vulkan attempt required"):
            run("controls_load", changed, "evidence_comparison")


if __name__ == "__main__":
    unittest.main()
