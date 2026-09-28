"""Static runner/evidence tests; synthetic reports never represent measured runs."""
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"scripts"))
from megascene_inventory import SCHEMA, canonical, read_evidence
from megascene_static import read_stream, report, schedule

CONFIG = {"case": "static", "preset": "small", "side_m": "64", "seed": "45", "threads": "6",
          "fragment_budget": "2048", "resolution": "640x360", "profile": "full", "warmup": "1", "frames": "1",
          "schedule_kind": "declared_development_prefix"}


def fixtures():
    # Wide monotonic values already beyond a U32 microsecond wrap. Nested stage
    # boundaries deliberately overlap: adding stage durations is not frame time.
    records = []
    def emit(kind, frame, **fields):
        records.append({"schema": SCHEMA, "record_type": kind, "synthetic": True,
                        "attempt_id": "fixture", "campaign_id": "fixture", "series_id": "fixture",
                        "clock_id": "linux.CLOCK_MONOTONIC", "sequence": str(len(records)),
                        "time_ns": str(10**15+frame*100+100), "frame": str(frame), **fields})
    emit("worker_start",0)
    emit("render_settings",0,width="640",height="360",profile="full",shadow_size="2048",night="0",
         ground_half_extent_m="40",present_mode="immediate")
    def bits(x):
        return "0x"+struct.pack(">f",x).hex()
    camera = {"eye_m": [bits(-17),bits(12),bits(-1)], "yaw": bits(math.atan2(-74,-234)),
              "pitch": bits(math.atan2(-72,math.hypot(74,234)))}
    for f in range(3):
        emit("static_state",f,anchored="21",moving="0",translated="0",aim_kind="0",fragments="0",removed="0",
             cells="10503360",next_id="22",budget="2048",**camera)
        emit("render_work",f,body_count="21",full_meshes="21",proxy_draws="0",main_body_draws="5",visible_bodies="5")
        stages = ["transport", "renderer", "geometry", "fence_wait", "vertex_upload", "acquire", "command_record", "submit_present", "events"]
        stages += ["generation", "initial_surfaces", "initial_inventory", "window_setup", "renderer_setup"] if f == 0 else ["physics", "view"]
        for stage in stages:
            emit("stage",f,stage=stage,begin_ns=str(10**15+f*100),end_ns=str(10**15+f*100+100),
                 duration_ns="100",status="measured",unit="ns")
        emit("frame",f,population=("startup","warmup","ordinary")[f],begin_ns=str(10**15+f*100),
             end_ns=str(10**15+f*100+100),duration_ns="100",status="measured",unit="ns")
    emit("stage",3,stage="teardown",begin_ns=str(10**15+300),end_ns=str(10**15+400),
         duration_ns="100",status="measured",unit="ns")
    emit("complete",3)
    return records


class StaticReports(unittest.TestCase):
    def summarize(self, records, code=0, cause="normal_exit"):
        result = report(records,[],CONFIG,code,cause,10**15-500,"fixture")
        result["synthetic"] = True
        return result

    def test_complete_observation_is_never_qualified(self):
        result = self.summarize(fixtures())
        self.assertEqual(result["schedule_completion"]["status"],"pass")
        self.assertEqual(result["completed_prefix"],{"startup":True,"warmup":"1","measured":"1"})
        self.assertEqual(result["populations"]["ordinary"]["mean"],100)
        self.assertEqual(result["cold_startup"]["value"],"600")
        for name in ("qualified_capacity", "interactive_pass", "state_correctness", "calibration", "rendering_correctness", "visual_quality", "responsiveness"):
            self.assertEqual(result[name]["status"],"inconclusive")

    def test_actual_settings_and_work_cannot_be_missing_or_reduced(self):
        mutations = [("render_settings","present_mode","fifo"), ("render_settings","width","1920"),
                     ("render_settings","ground_half_extent_m","512"), ("render_settings","shadow_size","1024"),
                     ("static_state","moving","1"), ("static_state","eye_m",["0x00000000"]*3),
                     ("render_work","proxy_draws","1"), ("render_work","full_meshes","20")]
        for kind,key,value in mutations:
            records = fixtures()
            next(r for r in records if r["record_type"] == kind)[key] = value
            self.assertNotEqual(self.summarize(records)["schedule_completion"]["status"],"pass",(kind,key))
        for kind in ("render_settings", "static_state", "render_work", "stage", "complete"):
            records = fixtures()
            records.remove(next(r for r in records if r["record_type"] == kind))
            self.assertNotEqual(self.summarize(records)["schedule_completion"]["status"],"pass",kind)

    def test_crash_and_policy_stop_preserve_prefix(self):
        records = fixtures()[:-1]
        result = self.summarize(records,-9,"case_deadline")
        self.assertEqual(result["termination"]["cause"],"case_deadline")
        self.assertEqual(result["termination"]["signal"],"9")
        self.assertEqual(result["completed_prefix"]["measured"],"1")
        self.assertNotEqual(result["schedule_completion"]["status"],"pass")
        empty = self.summarize([],1,"worker_error")
        self.assertIsNone(empty["cold_startup"]["value"])
        self.assertIsNone(empty["populations"]["ordinary"]["mean"])

    def test_duplicate_completion_cannot_pass(self):
        records = fixtures()
        records.append(dict(records[-1], sequence=str(len(records))))
        self.assertNotEqual(self.summarize(records)["schedule_completion"]["status"],"pass")

    def test_frame_gap_duplicate_and_wrong_boundary(self):
        for key,value in (("frame","4"),("begin_ns","100"),("population","warmup")):
            records = fixtures()
            [r for r in records if r["record_type"] == "frame"][-1][key] = value
            self.assertNotEqual(self.summarize(records)["schedule_completion"]["status"],"pass")

    def test_stream_schema_sequence_damage_and_zero(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d)/"cpu.jsonl"
            records = fixtures()
            raw = b"".join(canonical(r)+b"\n" for r in records)
            path.write_bytes(raw)
            parsed,errors = read_stream(path,"fixture")
            self.assertFalse(errors)
            self.assertEqual(len(parsed),len(records))
            path.write_bytes(raw+b'{"unfinished":')
            parsed,errors = read_stream(path,"fixture")
            self.assertEqual(len(parsed),len(records))
            self.assertIn("truncated",errors[0])
            for key,value in (("sequence","3"),("schema","megascene-evidence/2"),("attempt_id","other")):
                changed = copy.deepcopy(records)
                changed[1][key] = value
                path.write_bytes(b"".join(canonical(r)+b"\n" for r in changed))
                parsed,errors = read_stream(path,"fixture")
                self.assertEqual(len(parsed),1)
                self.assertTrue(errors)

    def test_frozen_accepted_schedule(self):
        s = schedule({**CONFIG,"frames":"3600","warmup":"120"})
        self.assertEqual(s["fixed_step"],"0x3c888889")
        self.assertEqual(len(s["frames"]),3721)
        self.assertEqual(s["frames"][121]["measured_ordinal"],"0")
        self.assertEqual(s["frames"][-1]["measured_ordinal"],"3599")
        self.assertTrue(all(f["camera"] == s["opening"] and not f["picking"] and not f["actions"] for f in s["frames"]))

    def test_prelaunch_failure_has_no_invented_worker_exit(self):
        with tempfile.TemporaryDirectory(prefix="megascene-prelaunch-", dir=Path.home()) as d:
            path = Path(d)/"output"
            result = subprocess.run([sys.executable,str(ROOT/"scripts/megascene.py"),"--case","static",
                "--output",str(path),"--archive",str(Path(d)/"archive")],
                env={**os.environ,"PATH":"/nonexistent"},capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,2)
            failure = read_evidence(path/"summary.json")
            self.assertEqual(failure["attempt_kind"],"development_observation")
            self.assertEqual(failure["termination"]["cause"],"prelaunch_failure")
            self.assertIsNone(failure["termination"]["exit_code"])
            self.assertFalse(failure["completed_prefix"]["startup"])

    def test_validator_import_failure_retains_prelaunch_evidence(self):
        from unittest.mock import patch
        from megascene import main
        with tempfile.TemporaryDirectory(prefix="megascene-import-test-",dir=Path.home()) as d:
            root=Path(d)
            with patch("megascene_static.execute",side_effect=ImportError("validator import fixture")):
                code=main(["--case","static","--output",str(root/"output"),"--archive",str(root/"archive")])
            self.assertEqual(code,2)
            result=read_evidence(root/"output/summary.json")
            self.assertEqual(result["termination"]["cause"],"prelaunch_failure")
            self.assertIsNone(result["termination"]["exit_code"])
            self.assertFalse(result["completed_prefix"]["startup"])
            self.assertEqual(read_evidence(root/"archive/campaign.json")["state"],"ready")

    def test_public_rejections_precede_build(self):
        with tempfile.TemporaryDirectory() as d:
            for i,args in enumerate((["--profile","proxy"], ["--frames","3601"], ["--warmup","121"],
                                     ["--archive",str(ROOT/"build/archive")], ["--deadline","301"],
                                     ["--resolution","1280x720"], [])):
                path = Path(d)/str(i)
                result = subprocess.run([sys.executable,str(ROOT/"scripts/megascene.py"),"--case","static","--output",str(path),*args],
                                        capture_output=True,text=True,timeout=10)
                self.assertEqual(result.returncode,2,args)
                self.assertFalse((path/"runtime").exists())
                self.assertEqual(read_evidence(path/"summary.json")["termination"]["cause"],"rejected_request")


@unittest.skipUnless(os.environ.get("MEGASCENE_VULKAN_TEST") == "1", "opt-in bounded real Vulkan integration")
class StaticVulkan(unittest.TestCase):
    def test_public_runner_archive_capture_recovery_and_abnormal_exit(self):
        with tempfile.TemporaryDirectory(prefix="megascene-static-test-",dir=Path.home()) as d:
            base = Path(d)
            output,archive = base/"output",base/"archive"
            command = [sys.executable,str(ROOT/"scripts/megascene.py"),"--case","static","--resolution","640x360",
                       "--warmup","1","--frames","2","--archive",str(archive),"--output",str(output),"--capture-opening"]
            env = {**os.environ,"VOXEL_STRESS":"1","VOXEL_STRESS_VIEW":"6"}
            proc = subprocess.run(command,capture_output=True,text=True,env=env,timeout=180)
            self.assertEqual(proc.returncode,0,proc.stderr)
            manifest = read_evidence(output/"manifest.json")
            retained = Path(manifest["reproduction"]["archive"])
            for entry in manifest["artifacts"]+manifest["evidence"]:
                self.assertEqual(hashlib.sha256((retained/entry["path"]).read_bytes()).hexdigest(),entry["sha256"])
            result = read_evidence(output/"summary.json")
            self.assertEqual(result["completed_prefix"]["measured"],"2")
            self.assertEqual(result["schedule_completion"]["status"],"pass")
            self.assertEqual(result["interactive_pass"]["status"],"inconclusive")
            self.assertEqual(result["supervision"]["allocation_ledger"]["live_bytes"],"0")
            self.assertGreater(int(result["supervision"]["allocation_ledger"]["peak_bytes"]),0)
            self.assertEqual(result["supervision"]["reference_records"],"4")
            self.assertFalse(result["supervision"]["errors"])
            self.assertTrue((retained/"resources.jsonl").exists())
            self.assertTrue((retained/"captures/opening.ppm").read_bytes().startswith(b"P6\n640 360\n255\n"))
            # Recover only archived runtime bytes at a different path, with no
            # live checkout library/shader dependency. No new compiler invocation.
            recovered = base/"recovered"
            shutil.copytree(retained/"runtime",recovered/"runtime")
            invocation = read_evidence(retained/"invocation.json")
            from megascene_static import launch
            from megascene_supervisor import Campaign
            campaign = Campaign(archive)
            loader = Path(invocation["command"][0]).name
            replay_result, _ = launch(manifest["effective"], recovered, manifest, loader, campaign=campaign)
            campaign.close(True)
            self.assertEqual(replay_result["termination"]["cause"],"normal_exit",replay_result)
            self.assertEqual((recovered/"stdout.log").read_text(),(retained/"stdout.log").read_text())
            records,errors = read_stream(recovered/"cpu.jsonl",manifest["attempt_id"])
            self.assertFalse(errors)
            self.assertEqual(len([r for r in records if r["record_type"] == "frame"]),4)
            # Controlled renderer/startup failure through the public boundary.
            bad_command = command.copy()
            bad_command[bad_command.index("--output")+1] = str(base/"bad-output")
            failed = subprocess.run(bad_command,env={**env,"DISPLAY":":9876"},capture_output=True,text=True,timeout=180)
            self.assertEqual(failed.returncode,2)
            failure = read_evidence(base/"bad-output/summary.json")
            self.assertEqual(failure["termination"]["cause"],"worker_error")
            self.assertFalse(failure["completed_prefix"]["startup"])
            self.assertIsNone(failure["cold_startup"]["value"])
            self.assertNotEqual(failure["schedule_completion"]["status"],"pass")


if __name__ == "__main__":
    unittest.main()
