import copy
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from megascene_checkpoints import identity
from megascene_inventory import canonical


PREFIX = bytes.fromhex("0000000003000000 0100000002000000 "
                       "0200000001000000 0200000004000000")
STARTUP = bytes.fromhex("0000000000000000")
WARMUP = bytes.fromhex("0100000000000000")
ORDINARY = bytes.fromhex("0200000000000000")


class SchedulePolicyReader(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory()
        cls.binary = Path(cls.folder.name) / "schedule-policy"
        subprocess.run(["g++", "-O2", "-std=c++17", str(ROOT / "tests/native_schedule_policy.cpp"),
                        "-o", str(cls.binary)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def invoke(self, data=PREFIX, count=4, warmup=1):
        path = Path(self.folder.name) / "policy.bin"
        path.write_bytes(data)
        return subprocess.run([str(self.binary), str(path), str(count), str(warmup)],
                              capture_output=True, text=True)

    def decoded(self, data, count, warmup):
        result = self.invoke(data, count, warmup)
        self.assertEqual(result.returncode, 0, result.stderr)
        return [tuple(map(int, row.split("\t"))) for row in result.stdout.splitlines()]

    def test_literal_prefix_preserves_phases_and_flags(self):
        self.assertEqual(self.decoded(PREFIX, 4, 1), [(0, 3), (1, 2), (2, 1), (2, 4)])

    def test_support_events_are_read_at_their_declared_frames(self):
        rows = [STARTUP] + [WARMUP] * 120 + [ORDINARY] * 44
        rows[121] = bytes.fromhex("0300000003000000")
        rows[152] = bytes.fromhex("0400000002000000")
        rows[164] = bytes.fromhex("0200000001000000")
        actual = self.decoded(b"".join(rows), 165, 120)
        self.assertEqual(len(actual), 165)
        self.assertEqual(actual[0], (0, 0))
        self.assertEqual(actual[1:121], [(1, 0)] * 120)
        self.assertEqual([actual[frame] for frame in (121, 122, 151, 152, 153, 163, 164)],
                         [(3, 3), (2, 0), (2, 0), (4, 2), (2, 0), (2, 0), (2, 1)])

    def test_zero_warmup_accepts_edit_and_motion(self):
        literal = bytes.fromhex("0000000000000000 0300000007000000 0400000005000000")
        self.assertEqual(self.decoded(literal, 3, 0), [(0, 0), (3, 7), (4, 5)])

    def test_minimum_and_maximum_frame_counts(self):
        self.assertEqual(self.decoded(STARTUP, 1, 0), [(0, 0)])
        actual = self.decoded(STARTUP + ORDINARY * 21720, 21721, 0)
        self.assertEqual(len(actual), 21721)
        self.assertEqual(actual[0], (0, 0))
        self.assertEqual(actual[1:], [(2, 0)] * 21720)

    def test_rejects_phase_flag_and_prefix_violations(self):
        mutations = {
            "unknown phase": (2, bytes.fromhex("0500000001000000")),
            "unknown flag": (2, bytes.fromhex("0200000008000000")),
            "high phase bit": (2, bytes.fromhex("0200008001000000")),
            "high flag bit": (2, bytes.fromhex("0200000001000080")),
            "big endian phase": (2, bytes.fromhex("0000000201000000")),
            "startup is warmup": (0, bytes.fromhex("0100000003000000")),
            "warmup is ordinary": (1, bytes.fromhex("0200000002000000")),
            "warmup is edit": (1, bytes.fromhex("0300000002000000")),
            "measured is startup": (2, bytes.fromhex("0000000001000000")),
            "measured is warmup": (2, bytes.fromhex("0100000001000000")),
        }
        for label, (frame, row) in mutations.items():
            with self.subTest(label=label):
                damaged = PREFIX[:frame * 8] + row + PREFIX[(frame + 1) * 8:]
                result = self.invoke(damaged)
                self.assertEqual((result.returncode, result.stdout), (2, ""), result.stderr)

    def test_rejects_counts_and_warmup_outside_bounds(self):
        for count, warmup in ((0, 0), (21722, 1), (4294967295, 1),
                              (4, 4), (4, 5), (4, 4294967295), (1, 1)):
            with self.subTest(count=count, warmup=warmup):
                result = self.invoke(PREFIX, count, warmup)
                self.assertEqual((result.returncode, result.stdout), (2, ""), result.stderr)

    def test_rejects_truncation_and_trailing_data(self):
        for data in (b"", PREFIX[:7], PREFIX[:-8], PREFIX[:-1], PREFIX + b"\x00",
                     PREFIX + ORDINARY):
            with self.subTest(data=data):
                result = self.invoke(data)
                self.assertEqual((result.returncode, result.stdout), (2, ""), result.stderr)


class SchedulePlanIdentity(unittest.TestCase):
    def test_rehashed_runtime_plans_still_match_the_frozen_schedule(self):
        frozen = {
            "schedule_id": "static-v1",
            "frames": [{"phase": "startup", "policy_flags": "3"},
                       {"phase": "warmup", "policy_flags": "2"},
                       {"phase": "ordinary", "policy_flags": "1"},
                       {"phase": "ordinary", "policy_flags": "4"}],
            "required_checkpoints": [{"name": "initial", "frame": "0"},
                                     {"name": "finish", "frame": "3"}],
            "review_views": [{"name": "opening", "frame": "0"}],
        }
        contents = {
            "runtime/worker": b"worker fixture",
            "schedule.json": canonical(frozen),
            "checkpoints.tsv": b"megascene-checkpoints/1\t4\t2\n0\tinitial\n3\tfinish\n",
            "reviews.tsv": b"megascene-reviews/1\t4\t1\n0\topening\n",
            "frame-policy.bin": PREFIX,
        }
        manifest = {
            "artifacts": [{"path": name, "sha256": hashlib.sha256(data).hexdigest(),
                           "size_bytes": str(len(data))} for name, data in contents.items()],
            "worker_command": ["runtime/worker"],
            "worker_environment": {"MEGASCENE_CHECKPOINT_FILE": "../checkpoints.tsv",
                                   "MEGASCENE_REVIEW_FILE": "../reviews.tsv",
                                   "MEGASCENE_FRAME_POLICY": "../frame-policy.bin"},
            "runtime": {}, "constants": {},
        }
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "runtime").mkdir()
            for name, data in contents.items():
                (root / name).write_bytes(data)
            valid = identity(manifest, root, {"schedule": "static-v1"})
            self.assertEqual(valid["artifacts"]["frame-policy.bin"], hashlib.sha256(PREFIX).hexdigest())
            stale = {
                "checkpoints.tsv": contents["checkpoints.tsv"].replace(b"finish", b"different"),
                "reviews.tsv": contents["reviews.tsv"].replace(b"opening", b"other"),
                "frame-policy.bin": PREFIX[:16] + bytes.fromhex("0300000001000000") + PREFIX[24:],
            }
            for name, data in stale.items():
                with self.subTest(name=name):
                    changed = copy.deepcopy(manifest)
                    artifact = next(item for item in changed["artifacts"] if item["path"] == name)
                    artifact.update(sha256=hashlib.sha256(data).hexdigest(), size_bytes=str(len(data)))
                    (root / name).write_bytes(data)
                    with self.assertRaisesRegex(ValueError, "runtime plan does not match frozen schedule: " + name):
                        identity(changed, root, {"schedule": "static-v1"})
                    (root / name).write_bytes(contents[name])


if __name__ == "__main__":
    unittest.main()
