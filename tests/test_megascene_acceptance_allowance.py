"""Closed runner roots do not charge the pause before a new authorized root."""

from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import megascene_acceptance_runner_overhead as overhead


class ConsolidatedAllowance(unittest.TestCase):
    def charge(self, folder, state):
        root = Path(folder)
        old, current = root / "old", root / "current"
        old.mkdir(); current.mkdir()
        (old / "campaign.json").write_text(json.dumps({
            "state": state, "elapsed_ns": "3000000000",
            "lease_utc_ns": "10000000000"}))
        (current / "campaign.json").write_text(json.dumps({
            "state": "ready", "elapsed_ns": "4000000000",
            "utc_start": "1970-01-01T00:00:20+00:00"}))
        path = root / "ledger.json"
        path.write_text(json.dumps({
            "allowance_ns": "1000000000000", "prior_gross_charge_ns": "0",
            "new_work_charge_ns": "2000000000",
            "runner_campaign_history": [{"path": str(old / "campaign.json")}],
            "runner_campaign": {"path": str(current / "campaign.json")},
            "new_work": [{"elapsed_ns": "1000000000", "command": [str(old)]},
                         {"elapsed_ns": "1000000000", "command": ["review-helper"],
                          "runner_campaign": str(current / "campaign.json")}]}))
        with patch.object(sys, "argv", ["overhead", "--ledger", str(path), "--write"]), \
                patch.object(overhead, "runner_remaining", return_value=900_000_000_000), \
                redirect_stdout(io.StringIO()):
            overhead.main()
            first = json.loads(path.read_text())
            overhead.main()
        self.assertEqual(json.loads(path.read_text()), first, "Repeated reconciliation must not charge twice")
        return first

    def test_closed_root_excludes_pause(self):
        with tempfile.TemporaryDirectory() as folder:
            ledger = self.charge(folder, "ready")
            self.assertEqual(ledger["new_work_charge_ns"], "7000000000")
            self.assertEqual([row["bridge_to_next_runner_ns"] for row in ledger["new_work"][2:]],
                             ["0", "0"])

    def test_active_root_retains_idle_bridge_charge(self):
        with tempfile.TemporaryDirectory() as folder:
            ledger = self.charge(folder, "active")
            self.assertEqual(ledger["new_work_charge_ns"], "17000000000")
            self.assertEqual(ledger["new_work"][2]["bridge_to_next_runner_ns"], "10000000000")


if __name__ == "__main__":
    unittest.main()
