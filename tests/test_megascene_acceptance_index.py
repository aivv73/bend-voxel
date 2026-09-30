"""The locator retains checks and recovery records from extension roots."""

import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from megascene_acceptance_index import supporting_artifacts


class SupportingArtifacts(unittest.TestCase):
    def test_extension_checks_are_indexed_without_duplicating_attempts(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            root = base / "megascene-acceptance-68-extension2"
            check = root / "checks" / "recovery.json"
            check.parent.mkdir(parents=True)
            check.write_bytes(b'{"retained": true}\n')
            attempt = root / "campaign-id" / "series-id" / "attempt-id" / "manifest.json"
            attempt.parent.mkdir(parents=True)
            attempt.write_bytes(b'{}\n')
            rows = supporting_artifacts(base)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["path"], str(check))
            self.assertEqual(rows[0]["sha256"], hashlib.sha256(check.read_bytes()).hexdigest())


if __name__ == "__main__":
    unittest.main()
