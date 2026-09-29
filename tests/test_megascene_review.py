"""Static opening review consumes a bound capture and explicit feature answers."""

from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))

from megascene import artifact, snapshot
from megascene_inventory import SCHEMA, read_json
from megascene_review import assess


class StaticReview(unittest.TestCase):
    def bundle(self,root):
        (root/"captures").mkdir()
        (root/"captures/opening.ppm").write_bytes(b"P6\n1 1\n255\n\0\0\0")
        snapshot(root/"schedule.json",{"schema":SCHEMA,"review_views":[{"name":"opening",
            "features":["building silhouettes","span silhouettes","major shadows"]}]})
        import hashlib
        snapshot(root/"review.json",{"schema":SCHEMA,"view":"opening",
            "schedule_sha256":hashlib.sha256((root/"schedule.json").read_bytes()).hexdigest(),
            "capture":artifact(root/"captures/opening.ppm",root),"status":"pending"})
        snapshot(root/"summary.json",{"schema":SCHEMA,"schedule_completion":{"status":"pass"},
            "state_correctness":{"status":"pass"},"opening_capture":{"status":"pass"}})
        snapshot(root/"manifest.json",{"schema":SCHEMA,"record_type":"manifest","synthetic":False,
            "attempt_kind":"development_observation","effective":{"case":"static"},
            "evidence":[artifact(root/name,root) for name in ("summary.json","review.json","schedule.json")]})

    def answers(self,root,missing=False):
        features={name:{"geometry":"correct","readability":"readable"} for name in
                  ("building silhouettes","span silhouettes","major shadows")}
        if missing: features.pop("major shadows")
        path=root/"answers.json"
        snapshot(path,{"schema":"megascene-feature-assessments/1","views":{"opening":features}})
        return path

    def test_static_capture_review_can_pass_with_complete_explicit_answers(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            self.bundle(root)
            self.assertEqual(assess(root,self.answers(root),"reviewer"),"pass")
            self.assertEqual(read_json((root/"summary.json").read_text())["visual_quality"]["status"],"pass")
            self.assertIn("assessments.json",[a["path"] for a in read_json((root/"manifest.json").read_text())["evidence"]])
            with self.assertRaisesRegex(ValueError,"already recorded"):
                assess(root,self.answers(root),"reviewer")

    def test_missing_feature_cannot_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            self.bundle(root)
            with self.assertRaisesRegex(ValueError,"every opening feature"):
                assess(root,self.answers(root,missing=True),"reviewer")
            self.assertFalse((root/"assessments.json").exists())


if __name__=="__main__":
    unittest.main()
