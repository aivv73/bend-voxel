import copy
import hashlib
import json
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
from megascene_recipe import generate, source_owners, volume
from megascene_scale import history_stride


class BendSources(unittest.TestCase):
    def test_exact_ordered_sources_for_every_supported_recipe(self):
        fixtures = json.loads((ROOT / "tests/fixtures/megascene_recipe_baseline.json").read_text())
        for key, expected in fixtures.items():
            with self.subTest(recipe=key):
                preset, seed, control = key.split("/")
                owners = generate(preset,int(seed),None if control == "base" else control)
                records = [{"role": o.role, "neighborhood": o.neighborhood,
                            "boxes": [b.record() for b in o.boxes]} for o in owners]
                content = json.dumps(records,sort_keys=True,separators=(",", ":")).encode()
                self.assertEqual(hashlib.sha256(content).hexdigest(),expected["sha256"])
                self.assertEqual(len(owners),expected["owners"])
                self.assertEqual(sum(len(o.boxes) for o in owners),expected["boxes"])
                self.assertEqual(sum(volume(b) for o in owners for b in o.boxes),expected["cells"])

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
                recipe = root/"src/megascene_recipe.bend"
                recipe.write_text(recipe.read_text().replace(
                    "box(0.0,320.0,1.0,8.0,0.0,320.0,2)",
                    "box(0.0,320.0,1.0,8.0,0.0,320.0,5)"))
                self.assertEqual(generate("small",45)[0].boxes[1].material,5)
                self.assertEqual(history_stride(4),5)
                policy = root/"src/megascene_scale.bend"
                policy.write_text(policy.read_text().replace(
                    "count,Pending{Integer.five()}","count,Pending{Integer.bit(True{},Integer.four())}"))
                self.assertEqual(history_stride(4),9)

    def test_old_archives_receive_a_separate_complete_generator(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = Path(directory)
            (runtime/"src").mkdir()
            frozen = runtime/"src/math.bend"
            frozen.write_text("retained old renderer source")
            megascene_bend.retain_sources(runtime)
            retained_files = sorted(p.relative_to(runtime).as_posix() for p in runtime.rglob("*"))
            with patch.object(megascene_bend,"ROOT",runtime), patch.object(megascene_bend,"SCRIPT_DIR",runtime):
                self.assertEqual(len(generate("small",45)),21)
                self.assertEqual(history_stride(25),6)
            self.assertEqual(frozen.read_text(),"retained old renderer source")
            self.assertEqual(sorted(p.relative_to(runtime).as_posix() for p in runtime.rglob("*")),retained_files)

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


if __name__ == "__main__":
    unittest.main()
