"""Literal observations captured before the Bend evidence migration."""

import gzip
import json
import copy
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import megascene_acceptance_index as acceptance
import megascene_search as search
from megascene_evidence import run as evidence


class RetainedEvidenceParity(unittest.TestCase):
    def inspect_observation(self, observation):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for filename, key in (("manifest.json", "manifest"), ("summary.json", "summary")):
                (root / filename).write_text(json.dumps(observation[key]))
            if observation["complete"]:
                (root / "validation").mkdir()
                for filename, key in (("validation.json", "validation"),
                                      ("validation/inventory.json", "inventory"),
                                      ("schedule.json", "schedule"), ("inputs.json", "inputs")):
                    (root / filename).write_text(json.dumps(observation[key]))
                if observation["timed"] is not None:
                    (root / "inventory.json").write_text(json.dumps(observation["timed"]))
            def report_bundle(*arguments):
                if observation.get("partial_error"):
                    raise ValueError("raw report unavailable")
                return observation["report"]
            with patch.object(search, "applicable"), patch.object(search, "identity"), \
                 patch.object(search, "verify_evidence"), \
                 patch.object(search, "_calibration", return_value=(None, None)), \
                 patch.object(search, "_fingerprint", return_value="frozen-fingerprint"), \
                 patch.object(search, "report_bundle", side_effect=report_bundle):
                actual = search.inspect(root, observation["expected"], observation["fixture"])
            actual["archive"] = "$archive"
            return actual

    def search_method_observation(self, observation):
        recorded = {"appended": [], "assessed": [], "snapshots": []}
        instance = search.Search.__new__(search.Search)
        instance.events = copy.deepcopy(observation["events"])
        instance.fixture = observation.get("fixture", True)
        instance.append = lambda kind, fields: recorded["appended"].append({"kind": kind, **fields})
        def assess(spec, observed, token):
            if observation["method"] == "reassess_diagnostics":
                token = token.rsplit("-", 5)[0] + "-$uuid"
            recorded["assessed"].append([spec, observed, token])
        if observation["method"] != "assess_diagnostic":
            instance.assess_diagnostic = assess
        def inspect(output, *arguments):
            if observation.get("inspection_error"):
                raise ValueError(observation["inspection_error"])
            return copy.deepcopy(observation["updated"].get(str(output), {}))
        def normalize(value, folder):
            if isinstance(value, str):
                return value.replace(folder, "$archive")
            if isinstance(value, list):
                return [normalize(child, folder) for child in value]
            if isinstance(value, dict):
                return {key: normalize(child, folder) for key, child in value.items()}
            return value
        with tempfile.TemporaryDirectory() as folder:
            instance.path = Path(folder)
            with patch.object(search, "inspect", side_effect=inspect), \
                 patch.object(search, "snapshot", side_effect=lambda path, result: recorded["snapshots"].append(result)), \
                 patch("megascene_compare_controls.compare", return_value=observation.get("comparison")), \
                 patch("megascene_compare_schedules.compare", return_value=observation.get("comparison")):
                getattr(instance, observation["method"])(*observation.get("args", []))
            return normalize(recorded, folder)

    def test_original_search_and_acceptance_observations(self):
        path = ROOT / "tests/fixtures/megascene_search_acceptance_baseline.json.gz"
        with gzip.open(path, "rt") as stream:
            observations = json.load(stream)
        for index, row in enumerate(observations):
            operation, arguments = row["operation"], row["arguments"]
            with self.subTest(index=index, operation=operation):
                if "exception" in row:
                    expected_type = {"KeyError": KeyError, "ValueError": ValueError,
                                     "TypeError": TypeError}[row["exception"]]
                    with self.assertRaises(expected_type) as observed:
                        if operation == "search_method":
                            self.search_method_observation(arguments[0])
                        elif operation == "inspect":
                            self.inspect_observation(arguments[0])
                        elif operation in ("all_attempts", "next_task"):
                            instance = search.Search.__new__(search.Search)
                            instance.events = arguments[0]
                            instance.fixture = arguments[1] if len(arguments) > 1 else False
                            getattr(instance, operation)()
                        else:
                            module = acceptance if operation in ("complete", "coverage") else search
                            getattr(module, operation)(*arguments)
                    self.assertEqual(str(observed.exception), row["message"])
                    continue
                if operation == "search_method":
                    actual = self.search_method_observation(arguments[0])
                elif operation == "inspect":
                    actual = self.inspect_observation(arguments[0])
                elif operation in ("next_task", "all_attempts"):
                    instance = search.Search.__new__(search.Search)
                    instance.events = arguments[0]
                    instance.fixture = arguments[1] if len(arguments) > 1 else False
                    actual = getattr(instance, operation)()
                elif operation in ("requirements", "complete", "coverage"):
                    actual = getattr(acceptance, operation)(*arguments)
                elif operation in ("source_for", "runner_remaining"):
                    actual = evidence(operation, arguments[0], "evidence_acceptance")
                else:
                    actual = getattr(search, operation)(*arguments)
                self.assertEqual(json.loads(json.dumps(actual)), row["expected"])

    def test_named_capture_reuse_preserves_hashes_and_feature_order(self):
        path = ROOT / "tests/fixtures/megascene_search_acceptance_baseline.json.gz"
        with gzip.open(path, "rt") as stream:
            observations = json.load(stream)
        source = copy.deepcopy(next(row["arguments"][0][0] for row in observations
                                    if row["operation"] == "coverage" and row["arguments"][0]))
        source.update(attempt_id="source", archive="/source")
        target = copy.deepcopy(source)
        target.update(attempt_id="target", archive="/target")
        target["configuration"]["threads"] = "12"
        review = {"status": "pass", "schedule_sha256": "frozen-schedule",
                  "views": [{"name": "opening", "frame": "0",
                             "capture": {"sha256": "identical-bytes"},
                             "features": [{"name": "building silhouettes"},
                                          {"name": "major shadows"}]}]}
        pending = copy.deepcopy(review)
        pending["status"] = "awaiting_named_feature_review"
        inputs = [{"attempt": source, "review": review, "assessments_present": True},
                  {"attempt": target, "review": pending, "assessments_present": False}]
        self.assertEqual(evidence("review_reuse", inputs, "evidence_acceptance"),
                         [{"source_attempt": "source", "source_archive": "/source",
                           "target_attempt": "target", "target_archive": "/target", "capture_count": 1}])
        pending["views"][0]["features"].reverse()
        self.assertEqual(evidence("review_reuse", inputs, "evidence_acceptance"), [])
        pending["views"][0]["features"].reverse()
        pending["views"][0]["capture"]["sha256"] = "different-bytes"
        self.assertEqual(evidence("review_reuse", inputs, "evidence_acceptance"), [])
        del review["views"][0]["capture"]["sha256"]
        with self.assertRaises(KeyError) as observed:
            evidence("review_reuse", inputs, "evidence_acceptance")
        self.assertEqual(str(observed.exception), "'sha256'")

    def test_allowance_charges_exact_counters_and_keeps_supervisor_cap(self):
        ledger = {"allowance_ns": "1000", "prior_gross_charge_ns": "100",
                  "new_work_charge_ns": "200", "new_work": [], "remaining_ns": "700"}
        actual = evidence("charge", {"ledger": ledger, "entry": {"elapsed_ns": "25"},
                                     "supervised": 500}, "evidence_acceptance")
        self.assertEqual(actual, {"allowance_ns": "1000", "prior_gross_charge_ns": "100",
                                  "new_work_charge_ns": "225", "new_work": [{"elapsed_ns": "25"}],
                                  "remaining_ns": "500", "runner_campaign_remaining_ns": "500"})
        self.assertEqual(evidence("allowance_gate", {"ledger": ledger, "supervised": None,
                                                     "timeout": 60}, "evidence_acceptance"), 0.0000007)
        ledger["remaining_ns"] = "0"
        with self.assertRaisesRegex(ValueError, "consolidated acceptance allowance exhausted"):
            evidence("allowance_gate", {"ledger": ledger, "supervised": None,
                                         "timeout": 60}, "evidence_acceptance")

    def test_acceptance_runner_charges_real_process_and_retains_log(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / "ledger.json"
            path.write_text(json.dumps({"allowance_ns": "10000000000",
                                        "prior_gross_charge_ns": "0", "new_work_charge_ns": "0",
                                        "remaining_ns": "10000000000", "new_work": []}))
            result = subprocess.run([sys.executable, str(ROOT / "scripts/megascene_acceptance_run.py"),
                                     "--ledger", str(path), "--archive", str(root / "checks"),
                                     "--name", "real-child", "--timeout", "2", "--", "/bin/true"],
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stderr)
            ledger = json.loads(path.read_text())
            self.assertEqual(len(ledger["new_work"]), 1)
            entry = ledger["new_work"][0]
            self.assertEqual((entry["status"], entry["exit_code"]), ("pass", 0))
            self.assertEqual(ledger["new_work_charge_ns"], entry["elapsed_ns"])
            self.assertEqual(int(ledger["remaining_ns"]), 10_000_000_000 - int(entry["elapsed_ns"]))
            self.assertTrue(Path(entry["log"]).is_file())

    def test_primary_batch_keeps_missing_primary_and_resolution_order(self):
        rows = [{"group": "primary", "runtime_coverage": "missing", "id": "a"},
                {"group": "proxy", "runtime_coverage": "missing", "id": "b"},
                {"group": "resolution", "runtime_coverage": "observed", "id": "c"},
                {"group": "resolution", "runtime_coverage": "missing", "id": "d"}]
        self.assertEqual(evidence("primary_pending", rows, "evidence_acceptance"),
                         [{"group": "primary", "runtime_coverage": "missing", "id": "a"},
                          {"group": "resolution", "runtime_coverage": "missing", "id": "d"}])


if __name__ == "__main__":
    unittest.main()
