import json
import math
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from megascene_report import calibration_result, classify, distribution, read_stream
from megascene_evidence import decode, run


class ReportParity(unittest.TestCase):
    def test_retained_literal_reports(self):
        cases = json.loads((ROOT / "tests/fixtures/evidence_report_parity.json").read_text())
        functions = {"classify": classify, "calibration_result": calibration_result}
        for case in cases:
            with self.subTest(case=case["name"]):
                if case["operation"] in ("calibration_binding", "calibration_assessment"):
                    if "error" in case:
                        with self.assertRaises((ValueError, KeyError)) as failure:
                            run(case["operation"], case["input"])
                        self.assertEqual(str(failure.exception), case["error"])
                    else:
                        self.assertEqual(run(case["operation"], case["input"]), case["expected"])
                    continue
                if case["operation"] == "read_stream":
                    with tempfile.TemporaryDirectory() as directory:
                        source = case["input"]
                        path = Path(directory) / source["name"]
                        path.write_text(source["raw"])
                        actual = read_stream(path, source["manifest"])
                        self.assertEqual(list(actual), case["expected"])
                    continue
                if "error" in case:
                    with self.assertRaises((ValueError, KeyError)) as failure:
                        functions[case["operation"]](**case["input"])
                    self.assertEqual(str(failure.exception), case["error"])
                    continue
                actual = (distribution(case["input"]) if case["operation"] == "distribution" else
                          functions[case["operation"]](**case["input"]))
                self.assertEqual(actual, case["expected"])

    def test_latency_uses_the_rounded_mean(self):
        fixture = json.loads((ROOT / "tests/fixtures/evidence_report_parity.json").read_text())[0]["input"]
        prepared = run("prepare", fixture)
        prepared["result"]["measured_interval_ns"] = "10000000000"
        prepared["context"]["ordinary_count"] = 1000
        rounded = decode("r35862976921600001/2147483648\n")
        self.assertEqual(rounded, 16_700_000.0)
        ordinary = prepared["result"]["populations"]["ordinary"]
        ordinary["mean"] = rounded
        self.assertEqual(run("finalize", prepared)["responsiveness"]["status"], "pass")
        ordinary["mean"] = math.nextafter(rounded, math.inf)
        result = run("finalize", prepared)
        self.assertEqual(result["responsiveness"]["status"], "fail")
        self.assertEqual(result["responsiveness"]["failed_gates"], ["ordinary_mean"])


if __name__ == "__main__":
    unittest.main()
