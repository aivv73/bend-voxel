import copy
import json
from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from megascene_bend import run_input
from megascene_scale import admit_schedule


def bits(value):
    return "0x" + struct.pack(">f", value).hex()


class FrozenAdmission(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.baseline = json.loads((ROOT / "tests/fixtures/megascene_frozen_admission_baseline.json").read_text())
        cls.config = cls.baseline[0]["config"]
        cls.frozen = cls.baseline[0]["frozen"]

    def test_retained_python_admission_outcomes(self):
        for case in self.baseline:
            with self.subTest(case=case["name"]):
                if "error" in case:
                    with self.assertRaises(ValueError) as rejected:
                        admit_schedule(case["config"], case["frozen"])
                    self.assertEqual(str(rejected.exception), case["error"])
                else:
                    self.assertEqual(admit_schedule(case["config"], case["frozen"]), case["result"])

    def test_malformed_words_and_native_worker_requests_reject(self):
        for value in (None, 0, "0X00000000", "0x0000000", "0x000000000", "0x0000000g",
                      "0x7fc00000", "0xff800000", "0x0000000\n"):
            frozen = copy.deepcopy(self.frozen)
            frozen["frames"][0]["camera"]["yaw"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                admit_schedule(self.config, frozen)
        for request in ("", "v1 s31 s31", "v1 i4294967295 i0\n\n\n\n", "v1 i0 i4294967296\n\n\n\n",
                        "v1 s31 s31\nF injected\n\n\n", "v1 s31 s31\n\n\n\n\nextra"):
            with self.subTest(request=request), self.assertRaises(ValueError):
                run_input("megascene_frozen_admit", request)

    def test_optional_actions_and_missing_pick_distances_reject(self):
        for required in (None, False, 0, 0.0, -0.0, "", []):
            frozen = copy.deepcopy(self.frozen)
            frozen["actions"][0]["required"] = required
            with self.subTest(required=required), self.assertRaisesRegex(ValueError, "frozen action silently optional"):
                admit_schedule(self.config, frozen)
        frozen = copy.deepcopy(self.frozen)
        frozen["frames"][2]["expected_pick"] = {"kind": "1"}
        with self.assertRaisesRegex(ValueError, "malformed frozen binary32"):
            admit_schedule(self.config, frozen)
        frozen["frames"][2]["expected_pick"] = {"kind": "0"}
        self.assertEqual(admit_schedule(self.config, frozen)["frozen_actions"], "1")

    def test_ray_tolerance_uses_binary64_products_and_sums(self):
        for word, accepted in (("0x3f800008", True), ("0x3f800009", False),
                               ("0x3f7ffff0", True), ("0x3f7fffef", False)):
            frozen = copy.deepcopy(self.frozen)
            frozen["frames"][2]["ray"] = dict(origin_m=[bits(0)]*3, direction=[word,bits(0),bits(0)])
            with self.subTest(word=word):
                if accepted:
                    self.assertEqual(admit_schedule(self.config, frozen)["frozen_frames"], "3")
                else:
                    with self.assertRaisesRegex(ValueError, "frozen ray direction invalid"):
                        admit_schedule(self.config, frozen)
        frozen = copy.deepcopy(self.frozen)
        frozen["frames"][2]["ray"] = dict(origin_m=[bits(0)]*3, direction=[])
        with self.assertRaisesRegex(ValueError, "frozen ray direction invalid"):
            admit_schedule(self.config, frozen)

    def test_ray_rounding_counterexamples_keep_original_verdicts(self):
        for direction, accepted in ((["0x3e8348ef", "0xbf5fa042", "0xbed3d55a"], True),
                                    (["0x3f0cf54f", "0x3f5532f4", "0x3d69692f"], False),
                                    (["0x3f800000", "0x3ab95d21", "0x351a03af"], True)):
            frozen = copy.deepcopy(self.frozen)
            frozen["frames"][2]["ray"] = dict(origin_m=[bits(0)]*3, direction=direction)
            with self.subTest(direction=direction):
                if accepted:
                    self.assertEqual(admit_schedule(self.config, frozen)["frozen_frames"], "3")
                else:
                    with self.assertRaisesRegex(ValueError, "frozen ray direction invalid"):
                        admit_schedule(self.config, frozen)

    def test_incomplete_vectors_reject_before_replay(self):
        for length in (0, 1, 2, 4):
            for path in (("frames", 0, "camera", "eye_m"), ("actions", 0, "target_m"),
                         ("supplementary_views", 0, "camera", "eye_m")):
                frozen = copy.deepcopy(self.frozen)
                node = frozen
                for key in path[:-1]:
                    node = node[key]
                node[path[-1]] = [bits(0)]*length
                with self.subTest(path=path, length=length), self.assertRaisesRegex(ValueError, "malformed frozen"):
                    admit_schedule(self.config, frozen)

    def test_legacy_hit_distance_keeps_strict_binary64_reach(self):
        for value, accepted in (("255.99999999999997", True), ("256.0", False),
                                ("-5e-324", False), ("0.0", True), ("-0.0", True),
                                (True, True), (False, True), (0, True), (1, True),
                                (0.0, True), (1.0, True), (-0.0, True), (256, False),
                                (256.0, False), (-1, False), (-1.0, False),
                                ("nan", False), ("inf", False), ("1e300", False),
                                ("0 255 add", False), ("not a number", False), ("1_0", True),
                                ("2_5_5.9_9", True), ("1__0", False), ("_10", False), ("10_", False)):
            frozen = copy.deepcopy(self.frozen)
            frozen["actions"][0]["pre_edit_hit"] = {"distance": value}
            with self.subTest(value=value):
                if accepted:
                    self.assertEqual(admit_schedule(self.config, frozen)["frozen_actions"], "1")
                else:
                    with self.assertRaisesRegex(ValueError, "required edit target outside strict reach"):
                        admit_schedule(self.config, frozen)

    def test_unicode_legacy_distances_keep_python_lexical_acceptance(self):
        for value, accepted in (("1\u00a0", True), ("\u00a01\u00a0", True), ("١٠", True),
                                ("１２", True), ("١_٠", True), ("𝟙𝟘", True), ("١e١", True),
                                ("\u20071\u202f", True), ("١.٥", True), ("٢٥٦", False),
                                ("−١", False), ("１ｅ１", False), ("١\u00a0٠", False),
                                ("١__٠", False), ("_١", False), ("١_", False), ("Ⅻ", False),
                                ("①", False), ("1\u200b", False), ("١a", False)):
            frozen = copy.deepcopy(self.frozen)
            frozen["actions"][0]["pre_edit_hit"] = {"distance": value}
            with self.subTest(value=value):
                if accepted:
                    self.assertEqual(admit_schedule(self.config, frozen)["frozen_actions"], "1")
                else:
                    with self.assertRaisesRegex(ValueError, "required edit target outside strict reach"):
                        admit_schedule(self.config, frozen)

    def test_unicode_decimal_table_and_whitespace_have_complete_runtime_coverage(self):
        table = json.loads((ROOT / "tests/fixtures/megascene_unicode_decimal_table.json").read_text())
        self.assertEqual(table["unicode_version"], "16.0.0")
        self.assertEqual(len(table["decimal_zero_code_points"]), 76)
        self.assertEqual(len(table["non_ascii_float_whitespace_code_points"]), 19)
        values = [chr(zero + digit) for zero in table["decimal_zero_code_points"] for digit in range(10)]
        values += [chr(space) + "1" + chr(space) for space in table["non_ascii_float_whitespace_code_points"]]
        for value in values:
            frozen = copy.deepcopy(self.frozen)
            frozen["actions"][0]["pre_edit_hit"] = {"distance": value}
            with self.subTest(value=value):
                self.assertEqual(admit_schedule(self.config, frozen)["frozen_actions"], "1")

    def test_binary32_coordinate_and_reach_limits_keep_exact_endpoints(self):
        for path, limit in ((("frames", 0, "camera", "eye_m", 0), 0x45000000),
                            (("supplementary_views", 0, "camera", "eye_m", 0), 0x45000000),
                            (("actions", 0, "target_m", 0), 0x44800000)):
            for word, accepted in ((limit, True), (limit + 1, False),
                                   (limit | 0x80000000, True), ((limit + 1) | 0x80000000, False)):
                frozen = copy.deepcopy(self.frozen)
                node = frozen
                for key in path[:-1]:
                    node = node[key]
                node[path[-1]] = f"0x{word:08x}"
                with self.subTest(path=path, word=word):
                    if accepted:
                        self.assertEqual(admit_schedule(self.config, frozen)["frozen_frames"], "3")
                    else:
                        with self.assertRaises(ValueError):
                            admit_schedule(self.config, frozen)
        for word, accepted in (("0x437fffff", True), ("0x43800000", False),
                               ("0x80000000", True), ("0x80000001", False)):
            frozen = copy.deepcopy(self.frozen)
            frozen["actions"][0]["pre_edit_hit"]["distance_m"] = word
            with self.subTest(word=word):
                if accepted:
                    self.assertEqual(admit_schedule(self.config, frozen)["frozen_actions"], "1")
                else:
                    with self.assertRaisesRegex(ValueError, "required edit target outside strict reach"):
                        admit_schedule(self.config, frozen)

    def test_binding_preserves_string_identity_and_feature_sets(self):
        frozen = copy.deepcopy(self.frozen)
        frozen["review_views"][0]["name"] = "оригинал |\n"
        frozen["supplementary_views"][0]["supplementary_to"] = "оригинал |\n"
        frozen["review_views"][0]["features"] = ["свет |\n", "wall"]
        frozen["supplementary_views"][0]["features"] = ["свет |\n", "свет |\n"]
        self.assertEqual(admit_schedule(self.config, frozen)["frozen_actions"], "1")
        frozen["supplementary_views"][0]["features"] = ["Свет |\n"]
        with self.assertRaisesRegex(ValueError, "supplementary view does not bind"):
            admit_schedule(self.config, frozen)


class GeneratedFrozenAdmission(unittest.TestCase):
    def test_real_schedule_families_keep_retained_admission_reports(self):
        from megascene_static import schedule
        baseline = json.loads((ROOT / "tests/fixtures/megascene_frozen_schedule_baseline.json").read_text())
        self.assertEqual(len(baseline), 23)
        for case in baseline:
            config = case["config"]
            with self.subTest(case=config["case"], schedule=config.get("schedule"), diagnostic=config.get("diagnostic")):
                self.assertEqual(admit_schedule(config, schedule(config)), case["result"])


if __name__ == "__main__":
    unittest.main()
