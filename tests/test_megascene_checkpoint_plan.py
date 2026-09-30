import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from megascene_checkpoint_plan import checkpoint_bytes, review_bytes


class CheckpointPlans(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory()
        cls.binary = Path(cls.folder.name) / "schedule-points"
        subprocess.run(["g++", "-O2", "-std=c++17", str(ROOT / "tests/native_schedule_points.cpp"),
                        "-lcrypto", "-o", str(cls.binary)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def invoke(self, text, frame=0, review=False, warmup=0, measured=1):
        env = {k: v for k, v in os.environ.items()
               if k not in ("MEGASCENE_CHECKPOINT_FILE", "MEGASCENE_REVIEW_FILE")}
        if text is not None:
            path = Path(self.folder.name) / "points.tsv"
            path.write_bytes(text)
            env["MEGASCENE_REVIEW_FILE" if review else "MEGASCENE_CHECKPOINT_FILE"] = str(path)
        return subprocess.run([str(self.binary), str(int(review)), str(frame), str(warmup), str(measured)],
                              capture_output=True, text=True, env=env)

    def test_transport_preserves_names_and_frame_order(self):
        frozen = {"frames": [{}, {}, {}], "required_checkpoints": [
            {"name": "finish", "frame": "2"}, {"name": "z_start", "frame": "0"},
            {"name": "a_start", "frame": "0"}],
            "review_views": [{"name": "opening", "frame": "0"}]}
        self.assertEqual(checkpoint_bytes(frozen),
                         b"megascene-checkpoints/1\t3\t3\n0\tz_start\n0\ta_start\n2\tfinish\n")
        self.assertEqual(review_bytes(frozen), b"megascene-reviews/1\t3\t1\n0\topening\n")
        result = self.invoke(checkpoint_bytes(frozen), frame=2, measured=2)
        self.assertEqual((result.returncode, result.stdout), (0, "1\n"), result.stderr)

    def test_native_selection_follows_table_at_coincident_frames(self):
        text = b"megascene-checkpoints/1\t2\t2\n1\tinitialization\n1\tmotion_0\n"
        for frame, expected in ((0, "0\n"), (1, "1\n")):
            result = self.invoke(text, frame=frame)
            self.assertEqual((result.returncode, result.stdout), (0, expected), result.stderr)
        review = b"megascene-reviews/1\t2\t1\n0\tcapture\n"
        result = self.invoke(review, review=True)
        self.assertEqual((result.returncode, result.stdout), (0, "1\n"), result.stderr)
        result = self.invoke(review, review=True, frame=1)
        self.assertEqual((result.returncode, result.stdout), (0, "0\n"), result.stderr)

    def test_native_rejects_missing_damaged_and_mismatched_plans(self):
        bad = [None, b"", b"megascene-checkpoints/2\t2\t1\n0\tname\n",
               b"megascene-checkpoints/1\t0\t1\n0\tname\n",
               b"megascene-checkpoints/1\t21722\t1\n0\tname\n",
               b"megascene-checkpoints/1\t2\t0\n", b"megascene-checkpoints/1\t2\t4097\n",
               b"megascene-checkpoints/1\t2\t4294967296\n",
               b"megascene-checkpoints/1\t3\t1\n0\tname\n",
               b"megascene-checkpoints/1\t2\t2\n0\tname\n",
               b"megascene-checkpoints/1\t2\t1\n0\tname\n1\textra\n",
               b"megascene-checkpoints/1\t2\t1\n2\tname\n",
               b"megascene-checkpoints/1\t2\t1\n00\tname\n",
               b"megascene-checkpoints/1\t2\t1\n-1\tname\n",
               b"megascene-checkpoints/1\t2\t1\n4294967296\tname\n",
               b"megascene-checkpoints/1\t2\t2\n1\tlater\n0\tearlier\n",
               b"megascene-checkpoints/1\t2\t2\n0\tname\n1\tname\n",
               b"megascene-checkpoints/1\t2\t1\n0\t\n",
               b"megascene-checkpoints/1\t2\t1\n0\tbad name\n",
               b"megascene-checkpoints/1\t2\t1\n0\tname\textra\n",
               b"megascene-checkpoints/1\t2\t1\n0\tname\r\n",
               b"megascene-checkpoints/1\t2\t1\n0\tname",
               b"megascene-checkpoints/1\t2\t1\n0\t" + b"n" * 129 + b"\n"]
        for text in bad:
            with self.subTest(text=text):
                result = self.invoke(text)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertIn("checkpoint plan", result.stderr)
        result = self.invoke(b"megascene-checkpoints/1\t2\t1\n0\tname\n", frame=2)
        self.assertEqual(result.returncode, 2)
        self.assertIn("frame outside frozen schedule", result.stderr)

    def test_serializer_rejects_names_and_frames_outside_contract(self):
        for points in ([{"name": "outside", "frame": "2"}],
                       [{"name": "bad name", "frame": "0"}],
                       [{"name": "same", "frame": "0"}, {"name": "same", "frame": "1"}], []):
            with self.subTest(points=points), self.assertRaises(ValueError):
                checkpoint_bytes({"frames": [{}, {}], "required_checkpoints": points})


if __name__ == "__main__":
    unittest.main()
