import json
from decimal import Decimal
from fractions import Fraction
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from megascene_recipe import Box, Owner, admit_sources, envelope_cells, generate
from megascene_bend import run_input


class AdmissionParity(unittest.TestCase):
    def test_every_supported_recipe_matches_frozen_python_admission(self):
        fixtures = json.loads((ROOT / "tests/fixtures/megascene_admission_baseline.json").read_text())
        for key, expected in fixtures.items():
            preset, seed, control = key.split("/")
            control = None if control == "base" else control
            with self.subTest(recipe=key):
                self.assertEqual(admit_sources(generate(preset, int(seed), control),
                                               envelope_cells(preset, control) // 2, 2048), expected)

    def test_partial_contacts_and_transitive_connectivity(self):
        owners = [Owner("partial", None, [Box((0, 0, 0), (2, 1, 2), 1),
                                          Box((1, 1, 0), (3, 2, 1), 2)])]
        self.assertEqual(admit_sources(owners, 320, 0),
                         {"cells": "6", "surface_rectangle_bounds": ["16"],
                          "vertex_bound": "96", "geometry_byte_bound": "6144"})
        owners = [Owner("bridge", None, [Box((0, 0, 0), (1, 1, 1), 1),
                                         Box((2, 0, 0), (3, 1, 1), 2),
                                         Box((1, 0, 0), (2, 1, 1), 2)])]
        self.assertEqual(admit_sources(owners, 320, 0),
                         {"cells": "3", "surface_rectangle_bounds": ["18"],
                          "vertex_bound": "108", "geometry_byte_bound": "6912"})

    def test_owner_order_and_allowed_boundary_contact(self):
        owners = [Owner("a", None, [Box((0, 0, 0), (1, 1, 1), 1)]),
                  Owner("b", None, [Box((1, 0, 0), (2, 1, 1), 1),
                                    Box((2, 0, 0), (3, 1, 1), 1)])]
        self.assertEqual(admit_sources(owners, 320, 2**32 - 1),
                         {"cells": "3", "surface_rectangle_bounds": ["6", "12"],
                          "vertex_bound": "108", "geometry_byte_bound": "6912"})
        self.assertEqual(admit_sources(owners[::-1], 320, 2**32 - 1)["surface_rectangle_bounds"],
                         ["12", "6"])
        self.assertEqual(admit_sources([], 320, 0),
                         {"cells": "0", "surface_rectangle_bounds": [],
                          "vertex_bound": "0", "geometry_byte_bound": "0"})

    def test_worker_rejects_incomplete_or_extra_source_records(self):
        request = "megascene-admission/1 320 1 0 1 1 1 0 0 0 1 1 1 complete"
        expected = {"cells": "1", "surface_rectangle_bounds": ["6"],
                    "vertex_bound": "36", "geometry_byte_bound": "2304"}
        self.assertEqual(json.loads(run_input("megascene_admit", request)), expected)
        for broken in (request.removesuffix(" complete"), request + " extra",
                       request.replace("0 1 1 1 0", "0 2 1 1 0", 1),
                       request.replace("320", "10/", 1),
                       request.replace("0 1 1 1 0", "0 4294967295 1 1 0", 1),
                       request.replace("megascene-admission/1", "megascene-admission/2", 1)):
            with self.subTest(request=broken), self.assertRaises(ValueError):
                run_input("megascene_admit", broken)

    def test_repeated_clipped_endpoints_are_counted_once(self):
        owners = [Owner("grid", None, [Box((0, 0, 0), (4, 1, 4), 1),
                                       Box((1, 1, 0), (3, 2, 1), 2),
                                       Box((1, 1, 2), (3, 2, 4), 2)])]
        self.assertEqual(admit_sources(owners, 320, 0),
                         {"cells": "22", "surface_rectangle_bounds": ["26"],
                          "vertex_bound": "156", "geometry_byte_bound": "9984"})

    def test_rejected_supplied_geometry(self):
        unit = Box((0, 0, 0), (1, 1, 1), 1)
        cases = [([], "connected"),
                 ([unit, Box((1, 1, 0), (2, 2, 1), 2)], "connected"),
                 ([unit, Box((1, 1, 1), (2, 2, 2), 2)], "connected"),
                 ([unit, unit], "connected"),
                 ([Box((0, 0, 0), (1, 1, 1), 2)], "anchor"),
                 ([Box((0, 0, 0), (1, 1, 1), 6)], "material"),
                 ([Box((0, 0, 0), (0, 1, 1), 1)], "envelope"),
                 ([Box((-321, 0, 0), (1, 1, 1), 1)], "envelope"),
                 ([Box((0, 0, 0), (1, 129, 1), 1)], "envelope"),
                 ([Box((0.0, 0, 0), (1, 1, 1), 1)], "envelope"),
                 ([Box((False, 0, 0), (1, 1, 1), 1)], "envelope"),
                 ([unit, Box((0, 0, 0), (1, 2, 1), 1),
                   Box((1, 0, 0), (2, 2, 1), 2)], "overlapping")]
        for boxes, reason in cases:
            with self.subTest(boxes=boxes), self.assertRaisesRegex(ValueError, reason):
                admit_sources([Owner("bad", None, boxes)], 320, 2048)
        with self.assertRaisesRegex(ValueError, "overlapping"):
            admit_sources([Owner("a", None, [unit]), Owner("b", None, [unit])], 320, 2048)

    def test_numeric_guards_precede_narrowing_and_products(self):
        unit = [Owner("unit", None, [Box((0, 0, 0), (1, 1, 1), 1)])]
        for budget in (-1, 2**32, True, 1.0):
            with self.subTest(budget=budget), self.assertRaisesRegex(ValueError, "fragment budget"):
                admit_sources(unit, 320, budget)
        cases = [(Box((2**24 + 1, 0, 0), (2**24 + 2, 1, 1), 1), "coordinate"),
                 (Box((2**23, 0, 0), (2**23 + 1, 1, 1), 1), "spatial split"),
                 (Box((0, 0, 0), (65536, 1, 65536), 1), "box volume")]
        for box, reason in cases:
            with self.subTest(box=box), self.assertRaisesRegex(ValueError, reason):
                admit_sources([Owner("numeric", None, [box])], 2**25, 2048)
        owners = [Owner("a", None, [Box((-65536, 0, -65536), (0, 1, -32768), 1)]),
                  Owner("b", None, [Box((0, 0, 0), (65536, 1, 32768), 1)])]
        with self.assertRaisesRegex(ValueError, "world cell sum"):
            admit_sources(owners, 65536, 2048)

    def test_exact_coordinates_above_u32_and_numeric_transport(self):
        for lo, hi in ((2**40, 2**40 + 2**18), (-2**40 - 2**18, -2**40)):
            with self.subTest(lo=lo):
                owners = [Owner("distant", None, [Box((lo, 0, 0), (hi, 1, 1), 1)])]
                self.assertEqual(admit_sources(owners, 2**40 + 2**18, 0),
                                 {"cells": "262144", "surface_rectangle_bounds": ["6"],
                                  "vertex_bound": "36", "geometry_byte_bound": "2304"})
        expected = {"cells": "1", "surface_rectangle_bounds": ["6"],
                    "vertex_bound": "36", "geometry_byte_bound": "2304"}
        for material in (True, 1.0, Decimal(1), Fraction(1, 1), complex(1, 0)):
            owners = [Owner("unit", None, [Box((0, 0, 0), (1, 1, 1), material)])]
            for half in (1.5, float("inf"), Decimal("1.5"), Fraction(3, 2)):
                with self.subTest(material=material, half=half):
                    self.assertEqual(admit_sources(owners, half, 0), expected)
            for half in (.5, float("-inf"), float("nan")):
                with self.subTest(half=half), self.assertRaisesRegex(ValueError, "envelope"):
                    admit_sources(owners, half, 0)

    @unittest.skipUnless(hasattr(sys, "set_int_max_str_digits"), "Python has no decimal digit limit")
    def test_decimal_transport_bypasses_python_digit_limit(self):
        previous = sys.get_int_max_str_digits()
        try:
            sys.set_int_max_str_digits(640)
            huge = 10**700
            owners = [Owner("unit", None, [Box((0, 0, 0), (1, 1, 1), 1)])]
            self.assertEqual(admit_sources(owners, huge, 0)["cells"], "1")
            with self.assertRaisesRegex(ValueError, "fragment budget"):
                admit_sources(owners, huge, huge)
            with self.assertRaisesRegex(ValueError, "envelope"):
                admit_sources(owners, -huge, 0)
        finally:
            sys.set_int_max_str_digits(previous)


if __name__ == "__main__":
    unittest.main()
