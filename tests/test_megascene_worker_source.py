import copy
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from megascene_bend import run_input
from megascene_recipe import Box, Owner, bend_program, generate
from megascene_proxy import owners as proxy_owners
from megascene_static import worker_program

BASELINE = ROOT / "tests/fixtures/megascene_worker_source_baseline.json"
REAL_HELPER = "def real.bits(bits: U32) -> F32:\n  U32{word} = bits\n  F32{word}\n\n"


def old_literal(match):
    value = struct.unpack(">f", struct.pack(">I", int(match[1])))[0]
    return f"(0.0 - {abs(value)!r} : F32)" if value < 0 else repr(value)


class WorkerSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.baseline = json.loads(BASELINE.read_text())

    def test_every_recipe_preserves_complete_generated_source(self):
        for row in self.baseline["recipes"]:
            preset, seed, control = row["recipe"].split("/")
            with self.subTest(recipe=row["recipe"]):
                source = bend_program(generate(preset, int(seed), None if control == "base" else control), 2048)
                self.assertEqual(len(source), row["bytes"])
                self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), row["sha256"])

    def test_every_replay_preserves_construction_and_binary32_values(self):
        for row in self.baseline["replays"]:
            config = row["config"]
            with self.subTest(config=config):
                owners = (proxy_owners(config) if config.get("diagnostic") else
                          generate(config["preset"], int(config["seed"]), config.get("control")))
                source = worker_program(owners, config, row)
                self.assertIn(REAL_HELPER, source)
                normalized = re.sub(r"real\.bits\((\d+)\)", old_literal, source.replace(REAL_HELPER, ""))
                self.assertEqual(hashlib.sha256(normalized.encode()).hexdigest(), row["sha256"])

    def test_source_uses_supplied_owners_and_ignores_host_metadata(self):
        owners = [Owner("def main()", None, [Box((-1, 0, 0), (1, 1, 1), 5)])]
        source = bend_program(owners, 0)
        self.assertIn("R.Vec{(0.0 - 1.0 : F32),0.0,0.0}", source)
        self.assertIn("R.Vec{1.0,1.0,1.0},5", source)
        self.assertEqual(source.count("def main()"), 1)

    def test_source_rejects_inexact_and_overflowing_numeric_inputs(self):
        owners = [Owner("unit", None, [Box((0, 0, 0), (1, 1, 1), 1)])]
        for budget in (-1, 2**32, 1.0, True, "0)\ndef injected()"):
            with self.subTest(budget=budget), self.assertRaisesRegex(ValueError, "fragment budget"):
                bend_program(owners, budget)
        for value in (0.0, True, 16777217, 10**100, "0.0}):\ndef injected()"):
            changed = [Owner("unit", None, [Box((value, 0, 0), (1, 1, 1), 1)])]
            with self.subTest(coordinate=value), self.assertRaises(ValueError):
                bend_program(changed, 0)
        for material in (0, 6, 2**32, "1\ndef injected()"):
            changed = [Owner("unit", None, [Box((0, 0, 0), (1, 1, 1), material)])]
            with self.subTest(material=material), self.assertRaises(ValueError):
                bend_program(changed, 0)
        self.assertIn("],1),4294967295))", bend_program(owners, 2**32 - 1))
        self.assertIn("16777216.0", bend_program([Owner("exact", None,
                      [Box((16777216, 0, 0), (16777218, 2, 2), 1)])], 0))

    def test_replay_rejects_counter_and_nonfinite_word_inputs(self):
        row = self.baseline["replays"][0]
        owners = [Owner("unit", None, [Box((0, 0, 0), (1, 1, 1), 1)])]
        for field, value in (("fragment_budget", str(2**32)), ("warmup", str(2**32)),
                             ("frames", str(2**32)), ("frames", "0"),
                             ("resolution", "4294967296x1080")):
            config = {**row["config"], field: value}
            with self.subTest(field=field), self.assertRaises(ValueError):
                worker_program(owners, config, row)
        for value in ("0x7f800000", "0xff800000", "0x7fc00000", "0x000000000", "0x1234567g"):
            frozen = copy.deepcopy(row)
            frozen["opening"]["yaw"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                worker_program(owners, row["config"], frozen)

    def test_transport_rejects_truncation_extra_records_and_owner_counts(self):
        valid = "megascene-worker/1 admission 0 1 1 1 0 0 0 1 1 1 complete"
        for request in (valid.removesuffix(" complete"), valid + " extra",
                        valid.replace("0 1 1 1", "0 4294967296 1 1", 1),
                        valid.replace(" 1 1 1 complete", " 1 1 1 ", 1)):
            with self.subTest(request=request), self.assertRaises(ValueError):
                run_input("megascene_worker_source", request)

    def test_compiled_binary32_literals_preserve_signed_zero_and_subnormals(self):
        words = [0, 0x80000000, 1, 0x80000001, 0x007fffff, 0x00800000,
                 0x3f800000, 0xbf800000, 0x7f7fffff, 0xff7fffff]
        row = self.baseline["replays"][0]
        owners = [Owner("unit", None, [Box((0, 0, 0), (1, 1, 1), 1)])]
        emitted = []
        for word in words:
            frozen = copy.deepcopy(row)
            frozen["opening"]["yaw"] = f"0x{word:08x}"
            source = worker_program(owners, row["config"], frozen)
            camera = source.rsplit("Static.start(world,V.Camera{", 1)[1]
            emitted.append(re.findall(r"real\.bits\((\d+)\)", camera)[3])
        program = "import Base\n" + REAL_HELPER + "def bits(value: F32) -> U32:\n  F32{word} = value\n  U32{word}\n"
        program += "def main() -> IO(Unit):\n  do IO<Unit>:\n"
        program += "".join(f"    IO.print(U32.show(bits(real.bits({word}))))\n" for word in emitted)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "bits.bend").write_text(program)
            built = subprocess.run(["bend", str(path / "bits.bend"), "-o", str(path / "bits")],
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            result = subprocess.run([str(path / "bits"), "--threads", "1"],
                                    capture_output=True, text=True, check=True, timeout=30)
        self.assertEqual(result.stdout.splitlines(), list(map(str, words)))

    def test_compiled_source_preserves_world_and_geometry(self):
        from megascene_references import fixtures, check
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            shutil.copytree(ROOT / "src", path / "src")
            (path / "reference.bend").write_text(bend_program(fixtures(), 2048))
            built = subprocess.run(["bend", "reference.bend", "-o", "reference"], cwd=path,
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            outputs = [subprocess.run([str(path / "reference"), "--threads", str(threads)],
                       capture_output=True, text=True, check=True, timeout=60).stdout for threads in (1, 6, 12)]
        self.assertEqual(hashlib.sha256(outputs[0].encode()).hexdigest(), self.baseline["reference_world_sha256"])
        records = [[json.loads(line) for line in text.splitlines()] for text in outputs]
        for record in records:
            record[0]["threads"] = "1"
        self.assertEqual(records[0], records[1])
        self.assertEqual(records[0], records[2])
        self.assertEqual(check(outputs[0])["status"], "pass")


if __name__ == "__main__":
    unittest.main()
