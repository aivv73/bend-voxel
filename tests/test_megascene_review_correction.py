"""Review corrections retain prior evidence and restore it on invalid input."""

import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import test_megascene_review as fixtures
from megascene_acceptance_review_correct import correct
from megascene_review import assess


class ReviewCorrection(unittest.TestCase):
    def reviewed_bundle(self, root):
        fixture = fixtures.StaticReview()
        fixture.bundle(root)
        answers = fixture.answers(root)
        self.assertEqual(assess(root, answers, "original reviewer"), "pass")
        originals = {name: (root / name).read_bytes() for name in
                     ("review.json", "assessments.json", "summary.json", "manifest.json")}
        return fixture, answers, originals

    def test_correction_retains_hashed_originals_and_changes_verdict(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            _, answers, originals = self.reviewed_bundle(root)
            value = json.loads(answers.read_text())
            value["views"]["opening"]["major shadows"].update(
                readability="insufficient", note="Shadow is not discernible.")
            answers.write_text(json.dumps(value))
            result = correct(root, answers, "correcting reviewer", "Original review was too broad.")
            self.assertEqual(result["prior_status"], "pass")
            self.assertEqual(result["status"], "insufficient_readability")
            audit_path = Path(result["audit"])
            audit = json.loads(audit_path.read_text())
            self.assertEqual(audit["reason"], "Original review was too broad.")
            manifest = json.loads((root / "manifest.json").read_text())
            evidence = {item["path"]: item for item in manifest["evidence"]}
            for name, original in originals.items():
                retained = audit_path.parent / name
                self.assertEqual(retained.read_bytes(), original)
                entry = evidence[str(retained.relative_to(root))]
                self.assertEqual(entry["sha256"], hashlib.sha256(original).hexdigest())
            self.assertIn(str(audit_path.relative_to(root)), evidence)
            self.assertEqual(json.loads((root / "summary.json").read_text())[
                "visual_quality"]["status"], "fail")

    def test_invalid_correction_restores_all_canonical_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            fixture, _, originals = self.reviewed_bundle(root)
            with self.assertRaisesRegex(ValueError, "every opening feature"):
                correct(root, fixture.answers(root, missing=True), "reviewer", "Reassessment")
            for name, original in originals.items():
                self.assertEqual((root / name).read_bytes(), original)
            audits = list((root / "review-revisions").glob("*/audit.json"))
            self.assertEqual(len(audits), 1)
            self.assertIn("every opening feature", json.loads(audits[0].read_text())[
                "correction_error"])


if __name__ == "__main__":
    unittest.main()
