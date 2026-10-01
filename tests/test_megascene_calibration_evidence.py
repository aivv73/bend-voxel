import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from megascene_calibration_series import _record, classify_statistic, plan
from megascene_evidence import run


class CalibrationParity(unittest.TestCase):
    def test_literal_python_baseline(self):
        fixtures = json.loads((ROOT / "tests/fixtures/evidence_calibration_parity.json").read_text())
        for index, fixture in enumerate(fixtures):
            with self.subTest(index=index, operation=fixture["operation"]):
                def invoke():
                    if fixture["operation"] == "plan":
                        return plan(fixture["input"])
                    if fixture["operation"] == "classify_statistic":
                        return classify_statistic(**fixture["input"])
                    return run(fixture["operation"], fixture["input"], module="evidence_calibration")
                if "expected_error" in fixture:
                    exception = {"KeyError": KeyError, "TypeError": TypeError,
                                 "IndexError": IndexError, "ValueError": ValueError}[fixture["exception_type"]]
                    with self.assertRaises(exception) as caught:
                        invoke()
                    self.assertEqual(str(caught.exception), fixture["expected_error"])
                else:
                    self.assertEqual(invoke(), fixture["expected"])

    def test_common_recorder_rejects_malformed_source_intervals(self):
        request = {"records": [{"record_type": "frame", "frame": "0", "population": "startup",
                               "begin_ns": "garbage", "end_ns": "garbage", "duration_ns": "garbage"}],
                   "frozen": {"frames": [{"phase": "startup"}], "actions": []}}
        with self.assertRaisesRegex(ValueError, "noncanonical integer"):
            run("reference_sequence", request, module="evidence_calibration")
        request["records"][0].pop("begin_ns")
        with self.assertRaises(KeyError):
            run("reference_sequence", request, module="evidence_calibration")

    def test_failed_schedule_binding_retains_attempted_runtime_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "output"
            output.mkdir()
            (output / "manifest.json").write_text(json.dumps({
                "reproduction": {"archive": str(root / "archive")},
                "artifacts": [{"path": "runtime/worker", "sha256": "attempted-bytes"}]}))
            series = {"scope": {"schedule": "static-perf-v2"}, "runs": [],
                      "controls": [], "validations": {}}
            with self.assertRaises(KeyError):
                _record(root / "series.json", series, "validation", "on", output, 0)
            retained = json.loads((root / "series.json").read_text())
            self.assertEqual(retained["runtime_artifacts"], {"runtime/worker": "attempted-bytes"})
            self.assertEqual(retained["runs"][0]["binding_error"], "'schedule.json'")
            self.assertEqual(retained["validations"]["on"], retained["runs"][0])


if __name__ == "__main__":
    unittest.main()
