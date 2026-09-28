"""Frozen route and native visibility references for issue 53."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import json
import hashlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))
from megascene_traversal import PHASES, camera_bytes, expected_payload, schedule
from megascene_review import assess
from megascene import artifact, snapshot
from megascene_inventory import digest
from megascene_checkpoints import audit
from megascene_static import schedule as static_schedule


class FrozenRoute(unittest.TestCase):
    def config(self, preset="small", seed="45"):
        return {"case":"traversal", "preset":preset, "seed":seed,
                "warmup":"120", "frames":"3600"}

    def test_complete_frozen_route_and_return(self):
        for preset in ("small", "large"):
            for seed in ("45", "46"):
                frozen = schedule(self.config(preset,seed))
                frames = frozen["frames"]
                self.assertEqual(len(frames),3721)
                self.assertEqual(len(camera_bytes(frozen)),3721*20)
                self.assertEqual(len(frozen["review_views"]),14)
                self.assertEqual(len(frozen["required_checkpoints"]),16)
                self.assertTrue(all(not f["picking"] and not f["actions"] for f in frames))
                self.assertTrue(all(f["camera"]==frozen["opening"] for f in frames[:121]))
                for i,(name,_) in enumerate(PHASES):
                    start=121+300*i
                    self.assertEqual(frames[start]["route_phase"],name)
                    self.assertEqual(frames[start+119]["camera"],frames[start]["camera"])
                    self.assertEqual(frames[start+299]["camera"],frames[start+300]["camera"] if i<11 else frames[start]["camera"])
                    self.assertEqual(frozen["review_views"][i+1]["frame"],str(start+60))
                self.assertNotEqual(frames[121+300*6]["camera"],frozen["opening"])
                self.assertEqual(frames[-1]["camera"],frozen["opening"])

    def test_binary_camera_preserves_bits_and_rejects_short_route(self):
        frozen=schedule(self.config())
        binary=camera_bytes(frozen)
        self.assertEqual([f"0x{w:08x}" for w in struct.unpack_from("<5I",binary,0)],
                         [*frozen["opening"]["eye_m"],frozen["opening"]["yaw"],frozen["opening"]["pitch"]])
        first={"bodies":[{"id":"1"}],"view":{"width":"640","height":"360"}}
        result=expected_payload(first,frozen["frames"][181])
        self.assertEqual(result["view"]["eye_m"],frozen["frames"][181]["camera"]["eye_m"])
        self.assertIs(result["bodies"],first["bodies"])
        with self.assertRaises(ValueError):
            schedule({**self.config(),"frames":"3599"})

    def test_v2_cavity_frames_show_bridge_floor_and_rim(self):
        import math
        def value(word):
            return struct.unpack(">f",bytes.fromhex(word[2:]))[0]
        def project(view, point):
            eye=list(map(value,view["eye_m"]))
            yaw,pitch=value(view["yaw"]),value(view["pitch"])
            delta=[p-e for p,e in zip(point,eye)]
            right=(-math.cos(yaw),0,math.sin(yaw))
            up=(-math.sin(yaw)*math.sin(pitch),math.cos(pitch),-math.cos(yaw)*math.sin(pitch))
            forward=(math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch))
            width=sum(a*b for a,b in zip(delta,right))
            height=sum(a*b for a,b in zip(delta,up))
            depth=sum(a*b for a,b in zip(delta,forward))
            self.assertGreater(depth,0)
            return 960+1200*width/depth,540-1200*height/depth

        for preset in ("small","large"):
            q=2 if preset=="small" else 4
            v1=schedule({**self.config(preset),"schedule":"traversal-v1"})
            v2=schedule({**self.config(preset),"schedule":"traversal-v2"})
            self.assertEqual(v1["schedule_id"],"traversal-v1")
            self.assertEqual(v2["schedule_id"],"traversal-v2")
            self.assertEqual(v1["opening"],v2["opening"])
            for index,neighborhood in ((3,0),(7,q*q-1)):
                frame=121+300*index+60
                origin_x=320*(neighborhood%q)-160*q
                origin_z=320*(neighborhood//q)-160*q
                center_x=(256+origin_x)/10
                floor=(center_x,.8,(256+origin_z)/10)
                bridge=(center_x,2.4,(272+origin_z)/10)
                rim=(center_x,2.4,(304+origin_z)/10)
                old_bridge_y=project(v1["frames"][frame]["camera"],bridge)[1]
                self.assertLess(old_bridge_y,0)
                view=v2["frames"][frame]["camera"]
                floor_y,bridge_y,rim_y=(project(view,p)[1] for p in (floor,bridge,rim))
                self.assertTrue(0<rim_y<bridge_y<floor_y<1080)
                self.assertGreater(floor_y-bridge_y,200)
                for edge_x in (224,288):
                    edge=(edge_x+origin_x)/10,2.4,bridge[2]
                    self.assertTrue(0<project(view,edge)[0]<1920)

    def test_synthetic_moving_checkpoint_rejects_stale_view(self):
        frozen=static_schedule({"side_m":"64","warmup":"1","frames":"2"})
        frozen["schedule_id"]="traversal-v1"
        frozen["frames"][1]["camera"]={**frozen["opening"],"yaw":"0x3f800000"}
        frozen["frames"][2]["camera"]={**frozen["opening"],"yaw":"0x40000000"}
        payload={"schema":"megascene-checkpoint/1","bodies":[{"id":"1","revision":"0"}],
                 "view":{**frozen["opening"],"width":"640","height":"360"}}
        work=[{"id":"1","vertices":"36","cuboids":"1","surface_rectangles":"6"}]
        records=[]
        for i in range(4):
            frame=str(i)
            names=[point["name"] for point in frozen["required_checkpoints"] if point["frame"]==frame]
            expected=expected_payload(payload,frozen["frames"][i])
            records.extend([{"record_type":"frame","frame":frame},
                {"record_type":"native_audit","frame":frame,"drawn_ids":["1"],"reference_visible":"1","vertices_checked":"36"},
                {"record_type":"render_work","frame":frame,"main_body_draws":"1","mesh_rebuilt":"1" if i==0 else "0",
                 "shadow_refresh":i==0,"shadow_body_draws":"1" if i==0 else "0","proxy_rebuilt":"0",
                 "proxy_groups":"0","proxy_vertices":"0","shadow_extent_m":["0x3f800000"]*2,"shadow_texel_m":["0x3a000000"]*2},
                {"record_type":"checkpoint" if names else "static_audit","frame":frame,"names":names,
                 "work":work,"sha256":digest(expected),"body_sha256":{"1":digest(payload["bodies"][0])},
                 **({"payload":expected} if names else {})}])
        self.assertEqual(audit(records,frozen,payload,work,True,True)["status"],"pass")
        next(r for r in records if r["record_type"]=="checkpoint" and r["frame"]=="1")["payload"]["view"]["yaw"]="0x00000000"
        self.assertEqual(audit(records,frozen,payload,work,True,True)["status"],"fail")


class NativeVisibility(unittest.TestCase):
    def test_unculled_reference_fixtures(self):
        with tempfile.TemporaryDirectory() as folder:
            binary=Path(folder)/"native-geometry"
            build=subprocess.run(["g++","-O2","-std=c++17",str(ROOT/"tests/native_geometry.cpp"),
                                  "-lvulkan","-lX11","-lcrypto","-o",str(binary)],capture_output=True,text=True)
            self.assertEqual(build.returncode,0,build.stderr)
            run=subprocess.run([str(binary)],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stderr)
            self.assertIn("ALL NATIVE BODY CACHE CHECKS PASSED",run.stdout)


class ReviewClassification(unittest.TestCase):
    def bundle(self, folder, geometry="correct", readability="readable", note=None):
        root=Path(folder)
        capture=root/"validation/captures/frame-0000.ppm"
        capture.parent.mkdir(parents=True)
        capture.write_bytes(b"P6\n1 1\n255\n\x11\x22\x33")
        frozen={"schedule_id":"traversal-v1"}
        snapshot(root/"schedule.json",frozen)
        review={"missing":[],"schedule_sha256":hashlib.sha256((root/"schedule.json").read_bytes()).hexdigest(),
                "views":[{"name":"opening","capture":artifact(capture,root),
                          "shadow_texel_m":["0x3dcccccd"]*2,"shadow_fit_min_margin_texels":"0x3f800000",
                          "features":[{"name":"building silhouettes","geometry":"pending","readability":"pending"}]}]}
        snapshot(root/"review.json",review)
        snapshot(root/"summary.json",{"schedule_completion":{"status":"pass"},"state_correctness":{"status":"pass"},
                                      "rendering_correctness":{"status":"pass"},"visual_quality":{"status":"inconclusive"}})
        snapshot(root/"manifest.json",{"effective":{"case":"traversal"},"attempt_kind":"development_observation",
                                       "evidence":[artifact(root/"review.json",root),artifact(root/"summary.json",root)]})
        answer={"geometry":geometry,"readability":readability}
        if note is not None: answer["note"]=note
        path=root/"answer.json"
        snapshot(path,{"schema":"megascene-feature-assessments/1",
                       "views":{"opening":{"building silhouettes":answer}}})
        return root,path,capture

    def test_pass_and_two_distinct_failure_classes(self):
        for geometry,readability,note,expected in (("correct","readable",None,"pass"),
                ("incorrect","unassessable","missing silhouette","incorrect_rendering"),
                ("correct","insufficient","too small to identify","insufficient_readability")):
            with tempfile.TemporaryDirectory() as folder:
                root,path,_=self.bundle(folder,geometry,readability,note)
                self.assertEqual(assess(root,path,"fixture reviewer"),expected)
                summary=json.loads((root/"summary.json").read_text())
                self.assertEqual(summary["rendering_correctness"]["status"],"fail" if geometry=="incorrect" else "pass")
                self.assertEqual(summary["visual_quality"]["status"],"inconclusive" if geometry=="incorrect" else "fail" if readability=="insufficient" else "pass")
                self.assertTrue((root/"assessments.json").exists())

    def test_missing_review_and_stale_capture_cannot_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            root,path,capture=self.bundle(folder)
            capture.write_bytes(b"stale")
            with self.assertRaisesRegex(ValueError,"stale capture"):
                assess(root,path,"fixture reviewer")
        with tempfile.TemporaryDirectory() as folder:
            root,path,_=self.bundle(folder)
            path.write_text('{"schema":"megascene-feature-assessments/1","views":{"opening":{}}}')
            with self.assertRaisesRegex(ValueError,"every named feature"):
                assess(root,path,"fixture reviewer")


if __name__ == "__main__":
    unittest.main()
