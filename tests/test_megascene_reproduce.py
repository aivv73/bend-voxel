"""Archived retrieval faults through the public Megascene recovery entry point."""
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"scripts"))
from megascene import artifact, snapshot
from megascene_inventory import SCHEMA, canonical, read_json
from megascene_reproduce import compare_source, main, retain_file
from megascene_static import schedule


class RecoveryBoundary(unittest.TestCase):
    def setUp(self):
        self.area = tempfile.TemporaryDirectory(prefix="issue63-", dir=ROOT)
        self.addCleanup(self.area.cleanup)
        self.root = Path(self.area.name)
        self.source = self.root/"source"
        self.source.mkdir()
        self.archive = self.root/"archive"
        self.output = self.root/"output"
        self.config = {"case":"static", "preset":"small", "side_m":"64", "envelope_side_m":"64",
                       "seed":"45", "threads":"6", "fragment_budget":"2048", "warmup":"0",
                       "frames":"1", "schedule":"static-v1", "resolution":"640x360", "profile":"full",
                       "control":None, "diagnostic":None, "archive":str(self.source),
                       "deadline_s":"30", "source_cells":"10503360"}
        self.required = ("runtime/worker", "runtime/reference-worker", "runtime/build/libvoxel_vulkan.so",
                         "runtime/build/vulkan-scene.vert.spv", "runtime/build/vulkan-scene.frag.spv",
                         "runtime/build/vulkan-shadow.vert.spv", "runtime/src/megascene_entry.bend",
                         "runtime/megascene_recipe.py", "runtime/megascene_static.py",
                         "runtime/lib/ld-linux-fixture.so", "inputs.json", "schedule.json")
        for name in self.required:
            path = self.source/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
        frozen = schedule(self.config)
        snapshot(self.source/"schedule.json", frozen)
        snapshot(self.source/"inputs.json", {"schema":SCHEMA, "record_type":"generation_inputs",
                 "configuration":{key:self.config[key] for key in
                                  ("preset","seed","side_m","envelope_side_m","control","fragment_budget")},
                 "owners":[]})
        self.manifest = {"schema":SCHEMA, "record_type":"manifest", "attempt_kind":"development_observation", "synthetic":False,
                         "attempt_id":"source", "effective":self.config,
                         "reproduction":{"archive":str(self.source), "status":"runtime_archived_before_execution"},
                         "worker_command":["runtime/lib/ld-linux-fixture.so", "--library-path", "runtime/lib",
                                           "runtime/worker", "--gpu", "off", "--threads", "6"],
                         "worker_environment":{"MEGASCENE_SCHEDULE_SHA256":hashlib.sha256((self.source/"schedule.json").read_bytes()).hexdigest(),
                                               "MEGASCENE_WARMUP":"0", "MEGASCENE_MEASURED":"1",
                                               "MEGASCENE_GROUND":"40", "VOXEL_VULKAN_LIBRARY":"runtime/build/libvoxel_vulkan.so",
                                               "VOXEL_STRESS_PRESENT":"unpaced"},
                         "artifacts":[artifact(self.source/name,self.source) for name in self.required],
                         "evidence":[], "runtime":{}, "constants":{}, "source":{}, "build":{},
                         "numeric_admission":{"status":"pass"}, "numeric_bounds":{}}
        snapshot(self.source/"manifest.json", self.manifest)

    def command(self, *extra):
        return [sys.executable, str(ROOT/"scripts/megascene.py"), "--reproduce-from", str(self.source),
                "--archive", str(self.archive), "--output", str(self.output), *extra]

    def failure(self):
        bundles = list(self.archive.glob("*/*/*/summary.json"))
        self.assertEqual(len(bundles),1)
        durable = read_json(bundles[0].read_text())
        self.assertEqual(durable["reproduction"]["status"],"fail")
        self.assertEqual(read_json((self.output/"summary.json").read_text()), durable)
        self.assertTrue((bundles[0].parent/"manifest.json").is_file())
        return durable, bundles[0].parent

    def test_missing_and_tampered_artifact_retains_failed_attempt(self):
        (self.source/"runtime/worker").unlink()
        result = subprocess.run(self.command(), capture_output=True, text=True)
        self.assertEqual(result.returncode,2,result.stderr)
        self.assertIn("missing runtime artifact",self.failure()[0]["reproduction"]["reason"])
        self.output.rename(self.root/"first-output")
        self.archive.rename(self.root/"first-archive")
        (self.source/"runtime/worker").write_bytes(b"runtime/worker")
        (self.source/"runtime/build/libvoxel_vulkan.so").write_bytes(b"tampered")
        result = subprocess.run(self.command(), capture_output=True, text=True)
        self.assertEqual(result.returncode,2,result.stderr)
        self.assertIn("stale runtime artifact",self.failure()[0]["reproduction"]["reason"])

    def test_saved_runtime_configuration_cannot_change(self):
        self.manifest["worker_environment"]["MEGASCENE_MEASURED"] = "2"
        snapshot(self.source/"manifest.json",self.manifest)
        result = subprocess.run(self.command(), capture_output=True, text=True)
        self.assertEqual(result.returncode,2,result.stderr)
        self.assertIn("runtime environment/configuration mismatch",self.failure()[0]["reproduction"]["reason"])

    def test_changed_configuration_and_retrieval_failure_are_durable(self):
        result = subprocess.run(self.command("--threads","12"), capture_output=True, text=True)
        self.assertEqual(result.returncode,2,result.stderr)
        self.assertIn("changed options",self.failure()[0]["reproduction"]["reason"])
        self.output.rename(self.root/"first-output")
        self.archive.rename(self.root/"first-archive")
        self.source.rename(self.root/"lost-source")
        result = subprocess.run(self.command(), capture_output=True, text=True)
        self.assertEqual(result.returncode,2,result.stderr)
        self.assertIn("manifest.json",self.failure()[0]["reproduction"]["reason"])

    def test_interrupted_retrieval_keeps_partial_bytes_and_never_overwrites(self):
        def interrupted(_source, destination, item):
            target = destination/item["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"partial archive write")
            raise OSError("injected interrupted archive write")
        with patch("megascene_reproduce.retain_file", side_effect=interrupted):
            self.assertEqual(main(self.command()[2:]),2)
        report, bundle = self.failure()
        self.assertIn("interrupted archive write",report["reproduction"]["reason"])
        self.assertEqual((bundle/self.required[0]).read_bytes(),b"partial archive write")
        item = self.manifest["artifacts"][0]
        with self.assertRaises(FileExistsError):
            retain_file(self.source,bundle,item)
        self.assertEqual((bundle/self.required[0]).read_bytes(),b"partial archive write")

    def test_checkpoint_comparison_reports_exact_field(self):
        bundle = self.root/"comparison"
        old, new = bundle/"source_evidence", bundle
        old.mkdir(parents=True)
        payload = {"schema":"megascene-checkpoint/1", "bodies":[], "cells":"1"}
        point = {"name":"initialization", "frame":"0", "sha256":"a"*64, "body_sha256":{}}
        for root, ident in ((old,"source"),(new,"replay")):
            snapshot(root/"manifest.json", {"attempt_id":ident, "evidence":[]})
            snapshot(root/"validation.json", {"status":"pass", "attempt_id":ident,
                     "expected":payload, "actual_work":[], "checkpoints":[point]})
            snapshot(root/"comparison.json", {"status":"pass", "actual_work":[], "checkpoints":[point]})
            snapshot(root/"inventory.json", {"cells":"1", "requested_controls":{"archive":str(root)}})
            snapshot(root/"summary.json", {"state_correctness":{"status":"pass"},
                     "schedule_completion":{"status":"pass"}})
            record = {"schema":SCHEMA, "record_type":"checkpoint", "campaign_id":"campaign",
                      "series_id":"series", "attempt_id":ident, "sequence":"0",
                      "clock_id":"linux.CLOCK_MONOTONIC", "time_ns":"1", "frame":"0",
                      "payload":payload, "sha256":point["sha256"]}
            (root/"cpu.jsonl").write_bytes(canonical(record)+b"\n")
            if root == old:
                manifest = read_json((root/"manifest.json").read_text())
                manifest["evidence"] = [artifact(root/name,root) for name in
                                        ("validation.json","comparison.json","inventory.json","summary.json","cpu.jsonl")]
                snapshot(root/"manifest.json",manifest)
        self.assertEqual(compare_source(bundle)["status"],"pass")
        changed = read_json((new/"validation.json").read_text())
        changed["expected"]["cells"] = "2"
        snapshot(new/"validation.json",changed)
        result = compare_source(bundle)
        self.assertEqual(result["status"],"fail")
        self.assertEqual(result["failures"][0]["field"],"initial_state/cells")


if __name__ == "__main__":
    unittest.main()
