from contextlib import redirect_stderr
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from megascene import configuration, main, parser
from megascene_bend import worker
from megascene_configuration import policy


def assert_retained_numeric_workers(test, bundle):
    runtime = bundle / "runtime"
    required = {"megascene_configuration.py", "generator/megascene_configuration.bend",
                "generator/megascene_operational.bend", "generator/megascene_worker_source.bend",
                "generator/megascene_frozen_admit.bend", "generator/frozen_admission.bend",
                "generator/schedule_float.bend", "generator/schedule_float.c", "generator/schedule_float.js",
                "generator/schedule_binary.bend", "generator/schedule_file.bend"}
    retained = {path.relative_to(runtime).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in runtime.rglob("*") if path.is_file()}
    test.assertLessEqual(required, retained.keys())
    code = """
import json
from pathlib import Path
import sys
runtime = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(runtime))
import megascene
import megascene_bend
import megascene_configuration
import megascene_recipe
import megascene_scale
for module in (megascene, megascene_bend, megascene_configuration, megascene_recipe, megascene_scale):
    assert Path(module.__file__).resolve().parent == runtime
config = megascene.configuration(megascene.parser().parse_args(['--output', 'isolated-output']))
bounds = megascene_scale.operational_bounds(2, 21, 1, 6, 36, 3, 0, (640, 360))
owners = [megascene_recipe.Owner('unit', None,
    [megascene_recipe.Box((0, 0, 0), (1, 1, 1), 1)])]
source = megascene_recipe.bend_program(owners, 0)
print(json.dumps({'config': config, 'native_bytes': bounds['initial_native_geometry_bytes_bound'],
    'frame_counter': bounds['frame_counter_upper_bound'], 'source_main': source.splitlines()[-1],
    'source_main_count': source.count('def main()')}))
"""
    with tempfile.TemporaryDirectory() as directory:
        isolated = Path(directory)
        environment = {**os.environ, "MEGASCENE_CACHE_ROOT": str(isolated / "cache")}
        result = subprocess.run([sys.executable, "-I", "-B", "-c", code, str(runtime)], cwd=isolated,
                                env=environment, capture_output=True, text=True, timeout=180)
    test.assertEqual(result.returncode, 0, result.stdout + result.stderr)
    test.assertEqual(json.loads(result.stdout), {
        "config": {"case": "admission", "preset": "small", "side_m": "64",
                   "neighborhoods_per_side": "2", "seed": "45", "threads": "6", "fragment_budget": "2048"},
        "native_bytes": "6501376", "frame_counter": "4", "source_main_count": 1,
        "source_main": "  M.emit(W.from.bodies(W.assemblies([owner0()],1),0))"})
    test.assertEqual({path.relative_to(runtime).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in runtime.rglob("*") if path.is_file()}, retained)


class ConfigurationAdmission(unittest.TestCase):
    def request(self, *extra):
        return parser().parse_args(["--output", "/home/aivv/configuration-output", *extra])

    def test_public_configuration_matches_captured_python_baseline(self):
        fixtures = json.loads((ROOT / "tests/fixtures/megascene_configuration_baseline.json").read_text())
        for fixture in fixtures:
            with self.subTest(argv=fixture["argv"]):
                args = parser().parse_args(fixture["argv"])
                if "error" in fixture:
                    with self.assertRaises(ValueError) as rejected:
                        configuration(args)
                    self.assertEqual(str(rejected.exception), fixture["error"])
                else:
                    self.assertEqual(configuration(args), fixture["configuration"])

    def test_huge_canonical_integers_reject_without_wrapping(self):
        huge = "9" * 5000
        for field, message in (("seed", "supported seeds are 45 and 46"),
                               ("threads", "supported thread counts are 1, 6 and 12"),
                               ("fragment-budget", "fragment budget exceeds U32")):
            with self.subTest(field=field):
                with self.assertRaisesRegex(ValueError, message):
                    configuration(self.request("--" + field, huge))
        with self.assertRaisesRegex(ValueError, "district side must be 32\\*q metres"):
            configuration(self.request("--side-m", huge))
        with self.assertRaisesRegex(ValueError, "square neighborhood scale unsupported"):
            configuration(self.request("--side-m", "1" + "0" * 5000))
        for field in ("warmup", "frames", "deadline"):
            with self.subTest(field=field):
                message = "development deadline" if field == "deadline" else "unsupported replay frame count"
                with self.assertRaisesRegex(ValueError, message):
                    configuration(self.request("--case", "static", "--archive", "/home/aivv/configuration-archive", "--" + field, huge))

    def test_non_string_and_noncanonical_numeric_requests(self):
        for field in ("seed", "threads", "fragment_budget", "side_m", "additional_allowance"):
            for value in (True, False, 45, 1.0, "-1", "00", "01", " 45", "45 ", "４５", "9" * 5000 + "x"):
                with self.subTest(field=field, value_type=type(value).__name__):
                    args = self.request("--campaign", "/home/aivv/configuration-campaign")
                    setattr(args, field, value)
                    with self.assertRaisesRegex(ValueError, "noncanonical integer"):
                        configuration(args)
        for field in ("warmup", "frames", "deadline"):
            args = self.request("--case", "static", "--archive", "/home/aivv/configuration-archive")
            for value in (True, 120, "-1", "0120"):
                with self.subTest(field=field, value_type=type(value).__name__):
                    setattr(args, field, value)
                    with self.assertRaisesRegex(ValueError, "noncanonical integer"):
                        configuration(args)

    def test_native_worker_rejects_wrapping_and_overflow(self):
        executable = worker("megascene_configuration")
        values = ["admission", "0", "0", "45", "6", "2048", "0", "0", "0",
                  "false", "false", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"]
        for index, value, message in ((3, "4294967341", "supported seeds are 45 and 46"),
                                      (4, "4294967302", "supported thread counts are 1, 6 and 12"),
                                      (5, "4294967296", "fragment budget exceeds U32"),
                                      (2, "14294967360", "square neighborhood scale unsupported: supported q=2..5; no physical capacity claim")):
            with self.subTest(index=index):
                request = values.copy()
                request[index] = value
                result = subprocess.run([str(executable), "--threads", "1", "--", "common", *request],
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr.strip(), message)
        self.assertEqual(policy("common", self.request("--fragment-budget", "4294967295"))["fragment_budget"], "4294967295")

    def test_configuration_infrastructure_failure_retains_unadmitted_replay(self):
        errors = (FileNotFoundError("Bend compiler unavailable"), RuntimeError("Bend worker build failed"),
                  RuntimeError("Megascene is pinned to Bend 2.0.34"),
                  subprocess.TimeoutExpired(["bend", "version"], 10))
        for error in errors:
            with self.subTest(error=type(error).__name__), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                with patch("megascene_configuration.policy", side_effect=error), redirect_stderr(io.StringIO()):
                    result = main(["--case", "static", "--output", str(root / "output"),
                                   "--archive", str(root / "archive")])
                manifest = json.loads((root / "output/manifest.json").read_text())
                summary = json.loads((root / "output/summary.json").read_text())
                self.assertEqual(result, 2)
                self.assertIsNone(manifest["effective"])
                self.assertIsNone(manifest["campaign_id"])
                self.assertEqual(manifest["numeric_admission"]["status"], "inconclusive")
                self.assertEqual(manifest["admission"]["status"], "inconclusive")
                self.assertEqual(summary["attempt_kind"], "development_observation")
                self.assertEqual(summary["termination"], {"cause": "prelaunch_failure", "exit_code": None,
                                                          "signal": None, "reason": str(error)})
                self.assertEqual(summary["completed_prefix"], {"startup": False, "warmup": "0", "measured": "0"})
                self.assertEqual(summary["numeric_validity"]["status"], "inconclusive")
                self.assertFalse((root / "archive").exists())

    def test_numeric_configuration_rejection_keeps_priority(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with redirect_stderr(io.StringIO()):
                result = main(["--case", "static", "--seed", "47", "--frames", "0",
                               "--output", str(root / "output"), "--archive", str(root / "archive")])
            manifest = json.loads((root / "output/manifest.json").read_text())
            summary = json.loads((root / "output/summary.json").read_text())
            self.assertEqual(result, 2)
            self.assertIsNone(manifest["effective"])
            self.assertEqual(summary["termination"]["cause"], "rejected_request")
            self.assertEqual(summary["termination"]["reason"], "supported seeds are 45 and 46")
            self.assertEqual(manifest["admission"]["status"], "fail")


if __name__ == "__main__":
    unittest.main()
