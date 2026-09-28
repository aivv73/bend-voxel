"""Small source references and corrupted native evidence for proxy diagnostics."""
import sys
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts"))

from megascene_proxy import audit, group, number, owners, schedule
from megascene_recipe import bits


def config(case="traversal", diagnostic="compact-reference", resolution="1920x1080"):
    return {"case":case,"diagnostic":diagnostic,"profile":"proxy","preset":"small","seed":"45",
            "warmup":"120","frames":"3600","resolution":resolution}


class ProxyFixtureTests(unittest.TestCase):
    def test_pair_missing_evidence_is_inconclusive(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            output=root/"pair.json"
            result=subprocess.run([sys.executable,str(Path(__file__).resolve().parents[1]/"scripts/megascene_proxy.py"),
                                   "--pair",str(root/"missing-full"),str(root/"missing-proxy"),
                                   "--output",str(output)],capture_output=True,text=True)
            self.assertEqual(result.returncode,2)
            self.assertEqual(json.loads(output.read_text())["status"],"inconclusive")

    def test_source_groups_and_reachable_reference_target(self):
        compact = config("picking")
        source = owners(compact)
        self.assertEqual(group(source)["members"],["1","2","3","4"])
        self.assertEqual(group(source)["hi_cells"],["71","59","71"])
        frozen = schedule(compact,source)
        self.assertEqual(frozen["frames"][121+720]["expected_pick"]["owner"],"4")
        self.assertEqual(frozen["frames"][121+840]["expected_pick"]["kind"],"0")
        mixed = group(owners(config(diagnostic="mixed-world")))
        self.assertEqual(mixed["members"],["6","11","16","21"])
        self.assertEqual(mixed["lo_cells"],["-48","24","-152"])
        low=config(resolution="640x360")
        low_view=schedule(low,owners(low))["opening"]
        high_view=schedule(config(),owners(config()))["opening"]
        self.assertGreater(number(high_view["eye_m"][2]),number(low_view["eye_m"][2])*2)

    def test_wrong_hysteresis_and_missing_native_evidence_fail(self):
        cfg=config()
        frozen=schedule(cfg,owners(cfg))
        records=[]
        selected=False
        choices=[False,True,True,False,False,True,True,True,False]
        for frame in frozen["frames"]:
            index=int(frame["frame"])
            hold=0 if index<=120 else min((index-121)//120,8)
            selected=choices[hold]
            members=["1","2","3","4"] if selected else []
            metric=bits((105,75,90,105,90,75,75,75,105)[hold])
            records.append({"record_type":"native_audit","frame":frame["frame"],
                "proxy_group_evidence":{"0":{"members":["1","2","3","4"],"metric_bits":metric,
                    "selected":selected,"aim_suppressed":False}},
                "selected_ids":members,"proxied_ids":members})
            records.append({"record_type":"render_work","frame":frame["frame"],"proxy_groups":"1",
                "proxy_draws":"1" if selected else "0","proxied_bodies":"4" if selected else "0",
                "main_body_draws":"0" if selected else "4","visible_bodies":"4","body_count":"4","full_meshes":"4",
                "full_vertices":"744","proxy_vertices":"144","resident_vertex_bytes":"168000",
                "shadow_body_draws":"4" if index==0 else "0","shadow_extent_m":[bits(36)]*2,
                "shadow_texel_m":[bits(.02)]*2,"shadow_fit_min_margin_texels":bits(1),
                "uploaded_bytes":"0","mesh_rebuilt":"0","proxy_rebuilt":"0"})
        self.assertEqual(audit(records,frozen,cfg)["status"],"pass")
        records[2*601]["proxy_group_evidence"]["0"]["selected"]=True
        with self.assertRaisesRegex(ValueError,"hysteresis"):
            audit(records,frozen,cfg)
        records[2*601]["proxy_group_evidence"]["0"]["selected"]=False
        records[2*401]["proxy_group_evidence"]["0"]["selected"]=False
        with self.assertRaisesRegex(ValueError,"hysteresis"):
            audit(records,frozen,cfg)
        records.pop()
        with self.assertRaisesRegex(ValueError,"missing proxy"):
            audit(records,frozen,cfg)


if __name__ == "__main__":
    unittest.main()
