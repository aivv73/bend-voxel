import copy
from decimal import Decimal
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from megascene_bend import run
import megascene_bend
from megascene_recipe import Box, Owner, admit_sources, envelope_cells, generate, source_owners, generation_inputs
from megascene_inventory import volume
from megascene_scale import history_stride, side_count


class BendSources(unittest.TestCase):
    def test_exact_ordered_sources_for_every_supported_recipe(self):
        fixtures = json.loads((ROOT / "tests/fixtures/megascene_recipe_baseline.json").read_text())
        admission = json.loads((ROOT / "tests/fixtures/megascene_admission_baseline.json").read_text())
        self.assertEqual(fixtures.keys(), admission.keys())
        for key, expected in fixtures.items():
            with self.subTest(recipe=key):
                preset, seed, control = key.split("/")
                owners = generate(preset,int(seed),None if control == "base" else control)
                self.assertEqual(admit_sources(owners, envelope_cells(preset, None if control == "base" else control) // 2, 2048), admission[key])
                inputs, admitted = generation_inputs(dict(preset=preset, seed=seed,
                    side_m=str(32*side_count(preset)),
                    envelope_side_m="1024", fragment_budget="2048", control=None if control == "base" else control))
                self.assertEqual(admitted, owners)
                self.assertEqual(len(json.loads(inputs)["owners"]), len(owners))
                records = [{"role": o.role, "neighborhood": o.neighborhood,
                            "boxes": [b.record() for b in o.boxes]} for o in owners]
                content = json.dumps(records,sort_keys=True,separators=(",", ":")).encode()
                self.assertEqual(hashlib.sha256(content).hexdigest(),expected["sha256"])
                self.assertEqual(len(owners),expected["owners"])
                self.assertEqual(sum(len(o.boxes) for o in owners),expected["boxes"])
                self.assertEqual(sum(volume(b) for o in owners for b in o.boxes),expected["cells"])

    def test_admission_adapter_rejects_noninteger_coordinates_and_budgets(self):
        unit = [Owner("unit", None, [Box((0, 0, 0), (1, 1, 1), 1)])]
        for budget in (True, 1.0):
            with self.subTest(budget=budget), self.assertRaisesRegex(ValueError, "fragment budget"):
                admit_sources(unit, 320, budget)
        for coordinate in (0.0, False):
            owners = [Owner("unit", None, [Box((coordinate, 0, 0), (1, 1, 1), 1)])]
            with self.subTest(coordinate=coordinate), self.assertRaisesRegex(ValueError, "envelope"):
                admit_sources(owners, 320, 2048)

    def test_admission_adapter_preserves_numeric_coercions(self):
        expected = {"cells": "1", "surface_rectangle_bounds": ["6"],
                    "vertex_bound": "36", "geometry_byte_bound": "2304"}
        for material in (True, 1.0, Decimal(1), Fraction(1, 1), complex(1, 0)):
            owners = [Owner("unit", None, [Box((0, 0, 0), (1, 1, 1), material)])]
            for half in (1.5, float("inf"), Decimal("1.5"), Fraction(3, 2)):
                with self.subTest(material=material, half=half):
                    self.assertEqual(admit_sources(owners, half, 0), expected)
            for half in (.5, float("-inf"), float("nan")):
                with self.subTest(material=material, half=half), self.assertRaisesRegex(ValueError, "envelope"):
                    admit_sources(owners, half, 0)

    @unittest.skipUnless(hasattr(sys, "set_int_max_str_digits"), "Python has no decimal digit limit")
    def test_admission_adapter_bypasses_python_digit_limit(self):
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

    def test_cached_sources_do_not_share_mutable_owners(self):
        owners = generate("small",45)
        owners[0].boxes.clear()
        owners[1].role = "changed"
        fresh = generate("small",45)
        self.assertEqual(len(fresh[0].boxes),40)
        self.assertEqual(fresh[1].role,"building")

    def test_source_transport_rejects_incomplete_and_damaged_records(self):
        text = run("megascene_source",2,45,"base")
        records = [json.loads(line) for line in text.splitlines()]
        for broken in (text.rstrip(), "\n".join(text.splitlines()[:-1])+"\n",
                       "\n".join(text.splitlines()[:1]+text.splitlines()[2:])+"\n"):
            with self.subTest(truncation=broken[-60:]), self.assertRaises(ValueError):
                source_owners(broken,2,45)
        mutations = [lambda r: r[0].update(seed=46),
                     lambda r: r[0].update(control="material-detail"),
                     lambda r: r[0].update(envelope_cells=960),
                     lambda r: r[1].update(neighborhood=True),
                     lambda r: r[1].update(boxes=[]),
                     lambda r: r[1]["boxes"][0]["lo"].__setitem__(0,.5),
                     lambda r: r[1]["boxes"][0]["lo"].__setitem__(0,10**500),
                     lambda r: r[1]["boxes"][0]["hi"].__setitem__(0,float("inf")),
                     lambda r: r[1]["boxes"][0].update(material=True),
                     lambda r: r[1].update(role="unknown"),
                     lambda r: r[1].update(role=[]),
                     lambda r: r.__setitem__(slice(2,4),[r[3],r[2]]),
                     lambda r: r[2].update(neighborhood=1)]
        for mutate in mutations:
            changed = copy.deepcopy(records)
            mutate(changed)
            with self.assertRaises(ValueError):
                source_owners("\n".join(map(json.dumps,changed))+"\n",2,45)
        with self.assertRaises(ValueError):
            source_owners(text.replace('"side":2','"side":2,"side":2',1),2,45)
        with self.assertRaises(ValueError):
            source_owners(text,2,45,"material-detail")

    def test_source_edits_invalidate_results_for_the_same_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/"src").mkdir()
            for name in {n for names in megascene_bend.DEPENDENCIES.values() for n in names}:
                shutil.copyfile(ROOT/"src"/(name+".bend"),root/"src"/(name+".bend"))
            with patch.object(megascene_bend,"ROOT",root):
                self.assertEqual(generate("small",45)[0].boxes[1].material,2)
                config = dict(preset="small",seed="45",side_m="64",envelope_side_m="64",control=None,fragment_budget="2048")
                frozen, admitted = generation_inputs(config)
                recipe = root/"src/megascene_recipe.bend"
                recipe.write_text(recipe.read_text().replace(
                    "box(0.0,320.0,1.0,8.0,0.0,320.0,2)",
                    "box(0.0,320.0,1.0,8.0,0.0,320.0,5)"))
                self.assertEqual(generate("small",45)[0].boxes[1].material,5)
                changed, fresh = generation_inputs(config)
                self.assertEqual(admitted[0].boxes[1].material,2)
                self.assertEqual(json.loads(frozen)["owners"][0]["boxes"][1]["material"],"2")
                self.assertEqual(fresh[0].boxes[1].material,5)
                self.assertEqual(json.loads(changed)["owners"][0]["boxes"][1]["material"],"5")
                self.assertEqual(history_stride(4),5)
                policy = root/"src/megascene_scale.bend"
                policy.write_text(policy.read_text().replace(
                    "count,Pending{Integer.five()}","count,Pending{Integer.bit(True{},Integer.four())}"))
                self.assertEqual(history_stride(4),9)

    def test_old_archives_receive_a_separate_complete_generator(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as cache:
            runtime = Path(directory)
            (runtime/"src").mkdir()
            frozen = runtime/"src/math.bend"
            frozen.write_text("retained old renderer source")
            megascene_bend.retain_sources(runtime)
            retained_files = sorted(p.relative_to(runtime).as_posix() for p in runtime.rglob("*"))
            with patch.object(megascene_bend,"ROOT",runtime), patch.object(megascene_bend,"SCRIPT_DIR",runtime), \
                    patch.dict(os.environ,{"MEGASCENE_CACHE_ROOT":cache}):
                owners = generate("small",45)
                self.assertEqual(len(owners),21)
                self.assertEqual(history_stride(25),6)
                self.assertEqual(admit_sources(owners,320,2048)["cells"],"10503360")
                inputs, admitted = generation_inputs(dict(preset="small",seed="45",side_m="64",envelope_side_m="64",control=None,fragment_budget="2048"))
                self.assertEqual(admitted,owners)
                self.assertEqual(inputs,(ROOT/"tests/fixtures/megascene_inputs_small_seed45.json").read_bytes())
            self.assertEqual(frozen.read_text(),"retained old renderer source")
            self.assertEqual(sorted(p.relative_to(runtime).as_posix() for p in runtime.rglob("*")),retained_files)

    def test_admission_source_changes_invalidate_the_worker(self):
        owners = [Owner("a",None,[Box((0,0,0),(1,1,1),1)]),
                  Owner("b",None,[Box((0,0,0),(1,1,1),1)])]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/"src").mkdir()
            for name in megascene_bend.DEPENDENCIES["megascene_admit"]:
                shutil.copyfile(ROOT/"src"/(name+".bend"),root/"src"/(name+".bend"))
            with patch.object(megascene_bend,"ROOT",root):
                with self.assertRaisesRegex(ValueError,"overlapping source ownership"):
                    admit_sources(owners,320,0)
                admission = root/"src/megascene_admission.bend"
                admission.write_text(admission.read_text().replace(
                    "overlapping source ownership","changed admission rejection"))
                with self.assertRaisesRegex(ValueError,"changed admission rejection"):
                    admit_sources(owners,320,0)

    def test_actual_worker_rejects_unsupported_inputs(self):
        for args in ((0,45,"base"),(6,45,"base"),(2,47,"base"),
                     (2,45,"unknown"),("4294967296",45,"base")):
            with self.subTest(args=args), self.assertRaises(ValueError):
                run("megascene_source",*args)

    def test_source_order_is_identical_at_one_six_and_twelve_threads(self):
        with tempfile.TemporaryDirectory() as directory:
            worker = Path(directory)/"worker"
            subprocess.run(["bend",str(ROOT/"src/megascene_source.bend"),"-o",str(worker)],
                           capture_output=True,text=True,check=True,timeout=120)
            outputs = [subprocess.run([str(worker),"--threads",str(threads),"--","4","46","surface-detail"],
                       capture_output=True,text=True,check=True,timeout=60).stdout for threads in (1,6,12)]
            self.assertEqual(outputs[0],outputs[1])
            self.assertEqual(outputs[0],outputs[2])


class CacheConfiguration(unittest.TestCase):
    def test_defaults_and_override_precedence_do_not_require_home(self):
        with patch.dict(os.environ,{"MEGASCENE_CACHE_ROOT":"","XDG_CACHE_HOME":""}):
            self.assertEqual(megascene_bend.cache_root(),ROOT / "build")
            with patch.object(megascene_bend,"SCRIPT_DIR",ROOT / "retained"), \
                    patch.object(Path,"home",return_value=Path("/home/example")):
                self.assertEqual(megascene_bend.cache_root(),Path("/home/example/.cache/bend-voxel"))
        with patch.object(Path,"home",side_effect=AssertionError("home must not be needed")), \
                patch.dict(os.environ,{"MEGASCENE_CACHE_ROOT":"","XDG_CACHE_HOME":"/work/cache"}):
            self.assertEqual(megascene_bend.cache_root(),Path("/work/cache/bend-voxel"))
            with patch.dict(os.environ,{"MEGASCENE_CACHE_ROOT":"/work/explicit"}):
                self.assertEqual(megascene_bend.cache_root(),Path("/work/explicit"))
        with patch.dict(os.environ,{"MEGASCENE_CACHE_ROOT":"relative"}), \
                self.assertRaisesRegex(ValueError,"must be an absolute path"):
            megascene_bend.cache_root()

    def test_archived_adapter_inherits_cache_in_subprocess_without_rewriting_sources(self):
        from megascene import run as run_process
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = root / "runtime"
            generator = runtime / "generator"
            generator.mkdir(parents=True)
            shutil.copyfile(megascene_bend.__file__,runtime / "megascene_bend.py")
            fixture = generator / "fixture.bend"
            fixture.write_text('import Base\ndef main() -> IO(Unit): IO.print("cache fixture")\n')
            retained = {p.relative_to(runtime):p.read_bytes() for p in runtime.rglob("*") if p.is_file()}
            command = [sys.executable,"-B","-c",
                       "import megascene_bend as b; b.DEPENDENCIES={'fixture':('fixture',)}; print(b.run('fixture'),end='')"]
            cache = root / "xdg" / "bend-voxel" / "megascene-bend"
            with patch.dict(os.environ,{"MEGASCENE_CACHE_ROOT":"","XDG_CACHE_HOME":str(root / "xdg")}):
                run_process(command,runtime,root / "stdout",root / "stderr",30)
                self.assertEqual((root / "stdout").read_bytes(),b"cache fixture\n")
                workers = [p for p in cache.iterdir() if p.suffix != ".lock"]
                self.assertEqual(len(workers),1)
                stamp = workers[0].stat().st_mtime_ns
                run_process(command,runtime,root / "stdout",root / "stderr",30)
                self.assertEqual(workers[0].stat().st_mtime_ns,stamp)
            self.assertEqual({p.relative_to(runtime):p.read_bytes() for p in runtime.rglob("*") if p.is_file()},retained)
            blocked = root / "blocked"
            blocked.write_text("a file cannot be a cache directory")
            with patch.dict(os.environ,{"MEGASCENE_CACHE_ROOT":str(blocked)}):
                result = subprocess.run(command,cwd=runtime,capture_output=True,text=True,timeout=30)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(result.stdout,"")
            self.assertIn("NotADirectoryError",result.stderr)


if __name__ == "__main__":
    unittest.main()
