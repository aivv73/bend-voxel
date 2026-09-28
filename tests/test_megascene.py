"""Runner/evidence integration, independent recipe and small dense references.

No synthetic report is evidence of a Vulkan run. These tests exercise the real
admission executable for all four fixed preset/seed combinations.
"""

from collections import Counter
import copy
import hashlib
from itertools import product
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from megascene_inventory import (SCHEMA, canonical, coordinate, inventory, measurement,
                                 read_evidence, read_json, surface_actual, surface_reference,
                                 verify_vertices)
from megascene_recipe import (Box, Owner, admit_sources, bend_program, bits, checked,
                              connected, generate, volume)
from megascene_reference import boxes as reference_boxes


class Admission(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="megascene-tests-")
        cls.root = Path(cls.temp.name)
        cls.bundles = {}
        for preset, seed in product(("small", "large"), (45, 46)):
            path = cls.root / f"{preset}-{seed}"
            result = subprocess.run([sys.executable, str(ROOT / "scripts/megascene.py"),
                                     "--preset", preset, "--seed", str(seed), "--output", str(path)],
                                    capture_output=True, text=True, timeout=180)
            if result.returncode:
                raise AssertionError(result.stderr + "\n" + "\n".join(
                    p.read_text() for p in path.glob("*stderr.log")))
            cls.bundles[preset, seed] = path

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_both_presets_seeds_against_independent_recipe(self):
        for (preset, seed), path in self.bundles.items():
            with self.subTest(preset=preset, seed=seed):
                manifest = read_evidence(path / "manifest.json")
                inv = read_evidence(path / "inventory.json")
                q = 2 if preset == "small" else 4
                expected = [[]]
                materials, roles = Counter(), Counter()
                for iz, ix in product(range(q), repeat=2):
                    local = reference_boxes((3*ix + 5*iz + seed-45) % 4)
                    for role in ("terrain", "building", "span0", "span1", "span2", "irregular"):
                        cells = []
                        for x, y, z, material in local[role]:
                            lo = (x[0]+320*ix-160*q, y[0], z[0]+320*iz-160*q)
                            hi = (x[1]+320*ix-160*q, y[1], z[1]+320*iz-160*q)
                            cells.append((lo, hi, material))
                            count = (x[1]-x[0])*(y[1]-y[0])*(z[1]-z[0])
                            materials[str(material)] += count
                            roles[role] += count
                        if role == "terrain":
                            expected[0].extend(cells)
                        else:
                            expected.append(cells)
                records = [read_json(line) for line in (path / "stdout.log").read_text().splitlines()][1:-1]
                self.assertEqual(len(records), 21 if q == 2 else 81)
                for i, (record, boxes) in enumerate(zip(records, expected), 1):
                    actual = [(tuple(map(coordinate, b[:3])), tuple(map(coordinate, b[3:6])), int(b[6]))
                              for b in record["boxes"]]
                    self.assertCountEqual(actual, boxes, f"owner {i}")
                    self.assertEqual(record["id"], str(i))
                    self.assertTrue(record["anchored"])
                    self.assertTrue(record["connected"])
                self.assertEqual(inv["cells"], "10503360" if q == 2 else "42096576")
                self.assertEqual(inv["cells_by_material"], {k: str(v) for k, v in materials.items()})
                self.assertEqual(inv["cells_by_role"], {k: str(v) for k, v in roles.items()})
                self.assertEqual(inv["bodies"]["initial_owners"], str(1+5*q*q))
                self.assertEqual(inv["authored_boxes"], str(51*q*q))
                self.assertEqual(inv["fragment_budget"], "2048")
                self.assertEqual(inv["cell_size_m"], "0x3dcccccd")
                self.assertEqual(manifest["effective"]["seed"], str(seed))
                self.assertEqual(manifest["admission"]["status"], "pass")
        for preset in ("small", "large"):
            a, b = [read_evidence(self.bundles[preset, s]/"inventory.json") for s in (45,46)]
            self.assertNotEqual(a["production_evidence"]["sha256"], b["production_evidence"]["sha256"])

    def test_recoverable_artifacts_and_thread_determinism(self):
        path = self.bundles["small", 45]
        manifest = read_evidence(path / "manifest.json")
        for entry in manifest["artifacts"] + manifest["evidence"]:
            content = (path / entry["path"]).read_bytes()
            self.assertEqual(hashlib.sha256(content).hexdigest(), entry["sha256"])
            self.assertEqual(len(content), int(entry["size_bytes"]))
        expected = (path / "stdout.log").read_text().splitlines()[1:]
        for threads in (1, 12):
            command = manifest["worker_command"][:-1] + [str(threads)]
            result = subprocess.run([str(path / command[0]), *command[1:]], cwd=path,
                                    capture_output=True, text=True, timeout=60, check=True)
            self.assertEqual(read_json(result.stdout.splitlines()[0])["threads"], str(threads))
            self.assertEqual(result.stdout.splitlines()[1:], expected)

    def test_no_benchmark_pass_from_admission(self):
        path = self.bundles["small", 45]
        report = read_evidence(path / "summary.json")
        self.assertEqual(report["admission"]["status"], "pass")
        for name in ("qualified_capacity", "interactive_pass", "rendering_correctness", "schedule_completion",
                     "visual_quality", "population_qualification", "calibration", "responsiveness"):
            self.assertEqual(report[name]["status"], "inconclusive")
        self.assertEqual(report["measurement_availability"]["status"], "not_executed")
        self.assertIsNone(report["measurement_availability"]["value"])
        self.assertEqual(read_evidence(path/"validation.json")["complete_replay"]["status"], "not_executed")

    def test_rejections_retain_requested_settings(self):
        cases = [("--preset", "large", "--side-m", "64"), ("--side-m", "256"),
                 ("--seed", "47"), ("--seed", "045"), ("--seed", "4.5e1"),
                 ("--fragment-budget", "4294967296"), ("--fragment-budget", "-1"),
                 ("--threads", "0"), ("--threads", "7"), ("--case", "history"),
                 ("--resolution", "1920x1080"), ("--profile", "full"), ("--schedule", "none"),
                 ("--diagnostic", "none"), ("--frames", "0"), ("--unknown", "1"),
                 ("--seed", "45", "--seed", "46"), ("--seed",)]
        for n, extra in enumerate(cases):
            path = self.root / f"rejected-{n}"
            cmd = [sys.executable, str(ROOT/"scripts/megascene.py"), "--output", str(path), *extra]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 2, extra)
            manifest = read_evidence(path / "manifest.json")
            self.assertEqual(manifest["requested"]["argv"], cmd[2:])
            self.assertIsNone(manifest["effective"])
            self.assertEqual(manifest["admission"]["status"], "fail")
            self.assertFalse((path / "runtime").exists())
            self.assertEqual(read_evidence(path / "summary.json")["termination"]["cause"], "rejected_request")

    def test_existing_bundle_is_never_overwritten(self):
        path = self.bundles["small", 45]
        before = (path / "manifest.json").read_bytes()
        result = subprocess.run([sys.executable, str(ROOT/"scripts/megascene.py"), "--output", str(path)],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertEqual((path / "manifest.json").read_bytes(), before)

    def test_corrupt_geometry_and_truncated_transport_fail(self):
        path = self.bundles["small", 45]
        manifest = read_evidence(path / "manifest.json")
        original = (path / "stdout.log").read_text()
        owners = generate("small", 45)
        def verify(text):
            return inventory(text, owners, manifest["effective"], manifest["numeric_bounds"])
        with self.assertRaises(ValueError):
            verify(original.rstrip())
        records = [read_json(line) for line in original.splitlines()]
        mutations = [lambda r: r[1].update(id="2"), lambda r: r[1].update(connected=False),
                     lambda r: r[1]["faces"].append(r[1]["faces"][0]),
                     lambda r: r[1]["faces"].pop(), lambda r: r[1]["boxes"][0].__setitem__(6, "5"),
                     lambda r: r[1]["vertices"][0].__setitem__(0, "0x7f800000")]
        for mutation in mutations:
            changed = copy.deepcopy(records)
            mutation(changed)
            with self.assertRaises(ValueError):
                verify("\n".join(canonical(r).decode() for r in changed)+"\n")

    def test_small_engine_fixtures_against_dense_cells(self):
        # Independent fixtures: negative coordinates, partial face contacts,
        # multiple materials, and an internal cavity. All use production trees.
        owners = [Owner("partial", None, [Box((-3,0,-2),(-1,2,2),1), Box((-1,0,-1),(1,1,1),2)]),
                  Owner("cavity", None, [Box((3,0,0),(7,1,4),1), Box((3,1,0),(4,4,4),3),
                                         Box((6,1,0),(7,4,4),2), Box((4,3,0),(6,4,4),5)])]
        path = self.bundles["small", 45] / "runtime"
        admit_sources(owners, 320, 2048)
        (path / "fixture.bend").write_text(bend_program(owners, 2048))
        compiled = subprocess.run(["bend", "fixture.bend", "-o", "fixture"], cwd=path,
                                  capture_output=True, text=True, timeout=120)
        self.assertEqual(compiled.returncode, 0, compiled.stdout+compiled.stderr)
        result = subprocess.run([str(path/"fixture"), "--threads", "1"],
                                capture_output=True, text=True, timeout=30, check=True)
        records = [read_json(line) for line in result.stdout.splitlines()][1:-1]
        for owner, record in zip(owners, records):
            dense = {p: b.material for b in owner.boxes for p in product(*[range(l,h) for l,h in zip(b.lo,b.hi)])}
            seen, pending = set(), [next(iter(dense))]
            exposed = {}
            while pending:
                p = pending.pop()
                if p in seen:
                    continue
                seen.add(p)
                for side in range(6):
                    axis, step = side//2, 1 if side%2 else -1
                    neighbor = tuple(p[k]+(step if k==axis else 0) for k in range(3))
                    if neighbor in dense:
                        if neighbor not in seen:
                            pending.append(neighbor)
                    else:
                        exposed[p, side] = dense[p]
            self.assertEqual(len(seen), len(dense))
            self.assertEqual(record["cells"], str(len(dense)))
            self.assertTrue(record["connected"])
            actual = {}
            faces = []
            for f in record["faces"]:
                lo, hi = tuple(map(coordinate, f[:3])), tuple(map(coordinate, f[3:6]))
                side, material = int(f[6]), int(f[7])
                faces.append((lo,hi,side,material))
                axis = side//2
                ranges = [range(lo[k],hi[k]) if k!=axis else [lo[k]-(1 if side%2 else 0)] for k in range(3)]
                for p in product(*ranges):
                    self.assertNotIn((p,side), actual)
                    actual[p,side] = material
            self.assertEqual(actual, exposed)
            self.assertEqual(surface_actual(faces), surface_reference(owner.boxes))
            verify_vertices(faces, record["vertices"])


class ReferencesAndReports(unittest.TestCase):
    def test_vertex_reference_rejects_overlapping_triangles(self):
        face = ((0,0,0), (1,1,0), 5, 2)
        points = [(0,0,0), (.1,0,0), (.1,.1,0), (0,.1,0)]
        vertices = [[*(bits(c) for c in points[i]), "5", "2"] for i in (0,1,2,0,1,3)]
        with self.assertRaisesRegex(ValueError, "diagonal"):
            verify_vertices([face], vertices)

    def test_source_and_arithmetic_guards(self):
        base = Box((0,0,0),(1,1,1),1)
        for other in (Box((1,1,0),(2,2,1),2), Box((1,1,1),(2,2,2),2)):
            self.assertFalse(connected([base, other]))
            with self.assertRaises(ValueError):
                admit_sources([Owner("bad", None, [base, other])], 320, 2048)
        bad = [[base,base], [Box((0,0,0),(1,1,1),2)], [Box((0,0,0),(0,1,1),1)],
               [Box((-321,0,0),(1,1,1),1)], [Box((0,0,0),(1,129,1),1)]]
        for boxes in bad:
            with self.assertRaises(ValueError):
                admit_sources([Owner("bad",None,boxes)], 320, 2048)
        self.assertEqual(checked(2**32-1, "counter"), 2**32-1)
        with self.assertRaises(ValueError):
            checked(2**32, "counter")
        with self.assertRaises(ValueError):
            volume(Box((0,0,0),(65536,65536,1),1))

    def test_explicit_status_and_schema_fixtures(self):
        synthetic = {"schema": SCHEMA, "synthetic": True,
                     "zero": measurement("measured", "observed zero", "fixture", "cells", "0"),
                     "missing": measurement("not_executed", "admission only", "fixture", "ns")}
        self.assertEqual(synthetic["zero"]["value"], "0")
        self.assertIsNone(synthetic["missing"]["value"])
        with self.assertRaises(ValueError):
            measurement("not_executed", "", "fixture", "ns", "0")
        with self.assertRaises(ValueError):
            read_json('{"schema":"megascene-evidence/1","schema":"megascene-evidence/2"}')
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/"manifest.json"
            path.write_text(json.dumps({**synthetic, "schema": "megascene-evidence/2"}))
            with self.assertRaisesRegex(ValueError, "unsupported evidence schema"):
                read_evidence(path)


if __name__ == "__main__":
    unittest.main()
