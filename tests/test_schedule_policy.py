import copy
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from megascene_checkpoints import identity
from megascene_inventory import canonical
from megascene_schedule import camera_bytes, ray_bytes, supplementary_bytes, checkpoint_bytes

PREFIX = bytes.fromhex("0000000003000000 0100000002000000 "
                       "0200000001000000 0200000004000000")


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

    def test_field_adapters_preserve_types_and_record_boundaries(self):
        view = {"eye_m": ["0x00000000"] * 3, "yaw": "0x00000000", "pitch": "0x00000000"}
        self.assertEqual(ray_bytes({"frames": [{"picking": False, "ray": None}]}), bytes(28))
        with self.assertRaises(ValueError):
            ray_bytes({"frames": [{"picking": 0, "ray": None}]})
        with self.assertRaises(ValueError):
            camera_bytes({"frames": [{"camera": {**view, "eye_m": ["0x00000000"] * width}}
                                     for width in (4, 2)]})
        with self.assertRaises(ValueError):
            supplementary_bytes([])
        for point in ({"frame": 0, "name": "number_is_not_text"}, {"frame": "0", "name": None}):
            with self.subTest(point=point), self.assertRaises(ValueError):
                checkpoint_bytes({"frames": [None], "required_checkpoints": [point]})


if __name__ == "__main__":
    unittest.main()
