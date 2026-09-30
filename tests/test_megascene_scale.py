"""Independent discrete scale, mapping and admission boundary checks."""

import sys
import json
import math
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from megascene_scale import (U32_MAX, U64_MAX, admit_schedule, history_stride, history_visit,
                             midpoint_refinement, next_growth, operational_bounds, preset_for)
from megascene_bend import run
from megascene_recipe import generate
from megascene_picking import value
from megascene_static import schedule


class ScalePolicy(unittest.TestCase):
    def test_unsupported_scale_retains_request_and_no_effective_work(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "rejected"
            result = subprocess.run([sys.executable,
                str(Path(__file__).resolve().parents[1] / "scripts" / "megascene.py"),
                "--side-m", "192", "--output", str(output)],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            manifest = json.loads((output / "manifest.json").read_text())
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(manifest["requested"]["options"]["side_m"], "192")
            self.assertIsNone(manifest["effective"])
            self.assertEqual(summary["termination"]["cause"], "rejected_request")
            self.assertNotIn("runtime", [part.name for part in output.iterdir()])
            numeric_output = Path(directory) / "numeric-rejected"
            numeric = subprocess.run([sys.executable,
                str(Path(__file__).resolve().parents[1] / "scripts" / "megascene.py"),
                "--side-m", "96", "--fragment-budget", str(U32_MAX),
                "--output", str(numeric_output)], capture_output=True, text=True)
            self.assertEqual(numeric.returncode, 2)
            numeric_manifest = json.loads((numeric_output / "manifest.json").read_text())
            numeric_summary = json.loads((numeric_output / "summary.json").read_text())
            self.assertEqual(numeric_manifest["effective"]["side_m"], "96")
            self.assertEqual(numeric_manifest["numeric_admission"]["status"], "fail")
            self.assertEqual(numeric_summary["termination"]["cause"], "rejected_request")

    def test_growth_and_refinement_use_integer_area_and_lower_ties(self):
        for q in range(2, 100):
            candidates = range(q+1, 2*q+2)
            expected = min(candidates, key=lambda x: (abs(x*x-2*q*q), x))
            self.assertEqual(next_growth(q), expected)
        for low in range(2, 20):
            for high in range(low+1, 25):
                expected = min(range(low+1, high),
                               key=lambda x: (abs(2*x*x-low*low-high*high), x),
                               default=None)
                self.assertEqual(midpoint_refinement(low, high), expected)
        self.assertEqual([next_growth(q) for q in (2, 3, 4)], [3, 4, 6])
        self.assertIsNone(midpoint_refinement(4, 5))

    def test_stride_visits_actual_prior_counts(self):
        self.assertEqual(history_stride(25), 6)
        self.assertEqual(history_stride(4), 5)
        self.assertEqual(history_stride(16), 5)
        for count in (4, 9, 16, 25):
            for seed in (45, 46):
                visited = []
                for group in range(12):
                    neighborhood, prior = history_visit(group, count, seed)
                    self.assertEqual(prior, visited.count(neighborhood))
                    self.assertLess(prior, 3)
                    visited.append(neighborhood)
                self.assertEqual(len(set(visited[:min(12,count)])), min(12,count))
        self.assertEqual([history_visit(i,25,45)[0] for i in range(6)],
                         [0,6,12,18,24,5])

    def test_scale_policy_preserves_arbitrary_integer_width(self):
        self.assertEqual(next_growth(1 << 32), 6074001000)
        self.assertEqual(next_growth(1 << 48), 398065729532861)
        self.assertEqual(next_growth(10**100),
            14142135623730950488016887242096980785696718753769480731766797379907324784621070388503875343276415727)
        self.assertEqual(midpoint_refinement(10**100, 10**100 + 10), 10**100 + 5)
        self.assertIsNone(midpoint_refinement(10**100, 10**100 + 1))
        self.assertEqual(midpoint_refinement(2, 9), 6)
        self.assertEqual(history_stride(math.factorial(30) // 24), 31)
        self.assertEqual(history_visit(11, 10**100, 46), (78, 0))
        neighborhood, prior = history_visit(1, 4, 45.0)
        self.assertEqual((neighborhood, prior), (1.0, 0))
        self.assertIs(type(neighborhood), float)

    def test_scale_policy_keeps_invalid_input_rejections(self):
        for q in (True, 1, -2, 2.0, "2"):
            with self.subTest(q=q), self.assertRaisesRegex(ValueError, "growth requires"):
                next_growth(q)
        for low, high in ((1, 3), (2, 2), (3, 2), (2.0, 3), (2, True)):
            with self.subTest(low=low, high=high), self.assertRaisesRegex(ValueError, "refinement requires"):
                midpoint_refinement(low, high)
        for count in (3, True, -4, 4.0, "4"):
            with self.subTest(count=count), self.assertRaisesRegex(ValueError, "history needs"):
                history_stride(count)
        for group, seed in ((-1, 45), (12, 45), (True, 45), (0, 44), (0, "45")):
            with self.subTest(group=group, seed=seed), self.assertRaisesRegex(ValueError, "unsupported history"):
                history_visit(group, 4, seed)

    def test_bend_policy_rejects_invalid_arguments_before_work(self):
        for arguments in (("growth", 1), ("growth", "2x"), ("growth", ""),
                          ("refinement", 3, 2), ("stride", 3),
                          ("visit", 12, 4, 45), ("visit", 1 << 32, 4, 45),
                          ("visit", 0, 4, 44)):
            with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                run("megascene_policy", *arguments)

    def test_numeric_boundaries_reject_before_unsafe_work(self):
        kwargs = dict(q=3, owners=46, cells=23663488, surface_rectangles=5364,
                      vertices=32184, frame_count=3721, budget=2048)
        self.assertEqual(operational_bounds(**kwargs)["initial_owners"], "46")
        for field in ("cells", "surface_rectangles", "vertices", "frame_count"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                operational_bounds(**(kwargs | {field: U32_MAX+1}))
        with self.assertRaisesRegex(ValueError, "edit_vertex"):
            operational_bounds(**(kwargs | {"cells": U32_MAX//36+1}))
        with self.assertRaisesRegex(ValueError, "initial_next_id"):
            operational_bounds(**(kwargs | {"owners": U32_MAX}))
        with self.assertRaisesRegex(ValueError, "native_geometry"):
            operational_bounds(**(kwargs | {"vertices": U32_MAX//128}))
        with self.assertRaises(ValueError):
            operational_bounds(**(kwargs | {"budget": U32_MAX}))
        with patch("megascene_scale.time.monotonic_ns", return_value=U64_MAX-1):
            with self.assertRaisesRegex(ValueError, "clock"):
                operational_bounds(**kwargs)
        with self.assertRaisesRegex(ValueError, "unsupported"):
            preset_for(6)

    def test_intermediate_source_and_frozen_interactions(self):
        config = dict(preset="scale-3", side_m="96", seed="45", warmup="120",
                      frames="3600", fragment_budget="2048", resolution="1920x1080",
                      control=None, diagnostic=None)
        owners = generate("scale-3", 45)
        self.assertEqual(len(owners), 46)
        self.assertEqual([owner.role for owner in owners[1:6]],
                         ["building", "span0", "span1", "span2", "irregular"])
        for case, schedule_id, actions in (("picking", "picking-v2", 0),
                                            ("localized", "localized-v1", 1),
                                            ("support", "support-v1", 6),
                                            ("history", "history-v2", 120)):
            with self.subTest(case=case):
                frozen = schedule(config | {"case": case, "schedule": schedule_id}, owners)
                admission = admit_schedule(config | {"case": case, "schedule": schedule_id}, frozen)
                self.assertEqual(len(frozen["frames"]), 3721)
                self.assertEqual(len(frozen["actions"]), actions)
                self.assertEqual(admission["frozen_actions"], str(actions))
                self.assertTrue(all((value(a["pre_edit_hit"]["distance_m"])
                                     if "distance_m" in a["pre_edit_hit"] else
                                     float(a["pre_edit_hit"]["distance"])) < 256
                                    for a in frozen["actions"]))
                if case == "history":
                    self.assertEqual(frozen["history_neighborhood_mapping"]["stride"], "5")

    def test_non_coprime_fixed_stride_is_replaced_in_real_schedule(self):
        config = dict(case="history", preset="scale-5", side_m="160", seed="45",
                      warmup="120", frames="3600", fragment_budget="2048",
                      resolution="1920x1080", control=None, diagnostic=None,
                      schedule="history-v2")
        frozen = schedule(config)
        mapping = frozen["history_neighborhood_mapping"]
        self.assertEqual(mapping["stride"], "6")
        self.assertEqual([int(group["neighborhood"]) for group in mapping["group_visits"][:6]],
                         [0, 6, 12, 18, 24, 5])
        self.assertEqual(admit_schedule(config, frozen)["frozen_actions"], "120")


if __name__ == "__main__":
    unittest.main()
