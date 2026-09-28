"""Native/reference, replay runner and synthetic report boundaries for issue 51."""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from megascene_inventory import canonical, digest, read_json, surface_reference
from megascene_checkpoints import (applicable, audit, checkpoint_bytes, identity, mismatch, occupancy, strings, surface)
from megascene_recipe import Box
from megascene_static import schedule


class NativeCheckpoints(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder=tempfile.TemporaryDirectory()
        cls.binary=Path(cls.folder.name)/'native-checkpoints'
        subprocess.run(['g++','-O2','-std=c++17',str(ROOT/'tests/native_checkpoints.cpp'),'-lvulkan','-lX11','-lcrypto','-o',str(cls.binary)],check=True,capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def record(self, mode='whole'):
        result=subprocess.run([str(self.binary),mode],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        return read_json(result.stdout)

    def test_native_checkpoint_matches_independent_sparse_oracle(self):
        record=self.record(); body=record['payload']['bodies'][0]
        boxes=[Box((-2,0,-1),(2,2,1),1)]
        self.assertEqual(body['occupancy'],strings(occupancy(boxes)))
        self.assertEqual(body['surface'],surface(surface_reference(boxes)))
        self.assertEqual(record['sha256'],hashlib.sha256(checkpoint_bytes(record['payload'])).hexdigest())
        self.assertEqual(record['body_sha256'],{'1':digest(body)})
        self.assertEqual(record['names'],['initialization','review_opening','warmup_end'])

    def test_equivalent_partitions_compare_equal_and_keep_actual_work(self):
        whole, split, rects=map(self.record,('whole','partitioned','rectangles'))
        self.assertEqual(whole['payload'],split['payload'])
        self.assertEqual(whole['sha256'],rects['sha256'])
        self.assertNotEqual(whole['work'][0]['cuboids'],split['work'][0]['cuboids'])
        self.assertNotEqual(whole['work'][0]['surface_rectangles'],rects['work'][0]['surface_rectangles'])

    def test_reject_corruption_before_normalization(self):
        reasons={'overlap':'duplicate','missing':'coverage','duplicate':'duplicate','material':'coverage',
                 'winding':'winding','tree':'tree node','stale_native':'stale native mesh'}
        for mode, reason in reasons.items():
            result=subprocess.run([str(self.binary),mode],capture_output=True,text=True)
            self.assertEqual(result.returncode,2,(mode,result.stdout,result.stderr))
            self.assertIn(reason,result.stderr,mode)

    def test_signed_zero_and_body_field_diagnostics(self):
        a,b=self.record()['payload'],self.record('negative_zero')['payload']
        self.assertNotEqual(digest(a),digest(b))
        diff=mismatch(a,b)
        self.assertEqual(diff['field'],'payload/bodies/body:1/velocity_m_s')
        self.assertEqual(diff['actual'],'0x80000000')


class CanonicalContracts(unittest.TestCase):
    def test_exact_schema_vocabulary_and_numbers(self):
        for value in (1,1.0,'space text','comma,','é','\\'):
            with self.assertRaises(ValueError): checkpoint_bytes({'schema':'megascene-checkpoint/1','field':value})
        with self.assertRaises(ValueError): checkpoint_bytes({'schema':'megascene-checkpoint/2'})
        with self.assertRaises(ValueError): read_json('{"a":"1","a":"2"}')
        self.assertEqual(checkpoint_bytes({'z':True,'schema':'megascene-checkpoint/1','a':None}),b'{"a":null,"schema":"megascene-checkpoint/1","z":true}')

    def test_sparse_signed_occupancy_and_overlap(self):
        a=Box((-2,-3,-4),(4,5,6),1)
        b=[Box((-2,-3,-4),(0,5,6),1),Box((0,-3,-4),(4,5,6),1)]
        self.assertEqual(occupancy([a]),occupancy(b))
        with self.assertRaises(ValueError): occupancy([a,a])
        large=Box((-8388608,0,0),(8388608,1,1),2)
        self.assertEqual(len(occupancy([large])),1)

    def test_checkpoint_stream_rejects_escaped_or_reordered_payload(self):
        from megascene_static import read_stream
        payload = {"schema":"megascene-checkpoint/1", "bodies":[]}
        record = {"schema":"megascene-evidence/1", "record_type":"checkpoint", "attempt_id":"fixture",
                  "campaign_id":"fixture", "series_id":"fixture", "sequence":"0", "frame":"0",
                  "clock_id":"linux.CLOCK_MONOTONIC", "time_ns":"1", "payload":payload}
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"cpu.jsonl"
            raw=canonical(record)+b"\n"; path.write_bytes(raw)
            self.assertFalse(read_stream(path,"fixture")[1])
            for changed in (raw.replace(b'"bodies":[],"schema":"megascene-checkpoint/1"',b'"schema":"megascene-checkpoint/1","bodies":[]'),
                            raw.replace(b'megascene-checkpoint/1',b'megascene-checkpoint'+bytes([92])+b'/1')):
                path.write_bytes(changed)
                self.assertTrue(read_stream(path,"fixture")[1])

    def test_actual_artifact_and_configuration_reuse_guards(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); (root/'runtime').mkdir()
            artifacts=[]
            for name in ('runtime/worker','schedule.json'):
                (root/name).write_bytes(b'actual bytes')
                artifacts.append({'path':name,'sha256':hashlib.sha256(b'actual bytes').hexdigest(),'size_bytes':'12'})
            manifest={'artifacts':artifacts,'worker_command':['worker','--threads','6'],'worker_environment':{},'runtime':{},'constants':{}}
            config={'threads':'6','profile':'full','warmup':'120','frames':'3600'}
            good=identity(manifest,root,config)
            validation={'status':'pass','synthetic':False,'identity':good}
            applicable(validation,good)
            for key,val in (('threads','12'),('profile','proxy'),('frames','1'),('warmup','0')):
                with self.assertRaises(ValueError): applicable(validation,identity(manifest,root,{**config,key:val}))
            for bad in ({**validation,'synthetic':True},{**validation,'status':'fail'}):
                with self.assertRaises(ValueError): applicable(bad,good)
            (root/'runtime/worker').write_bytes(b'stale bytes!')
            with self.assertRaisesRegex(ValueError,'stale'): identity(manifest,root,config)
            (root/'runtime/worker').unlink()
            with self.assertRaisesRegex(ValueError,'missing'): identity(manifest,root,config)


class SyntheticReplay(unittest.TestCase):
    def fixture(self, thorough=False):
        config={'side_m':'64','warmup':'1','frames':'2'}
        frozen=schedule(config)
        payload={'schema':'megascene-checkpoint/1','bodies':[{'id':'1','revision':'0'}]}
        work=[{'id':'1','vertices':'36','cuboids':'1','surface_rectangles':'6'}]
        records=[]
        for f in range(4):
            records += [{'record_type':'frame','frame':str(f)},
                {'record_type':'native_audit','frame':str(f),'drawn_ids':['1'],'reference_visible':'1','vertices_checked':'36'},
                {'record_type':'render_work','frame':str(f),'main_body_draws':'1','mesh_rebuilt':'1' if f==0 else '0',
                 'shadow_refresh':f==0,'shadow_body_draws':'1' if f==0 else '0','proxy_rebuilt':'0',
                 'proxy_groups':'0','proxy_vertices':'0','shadow_extent_m':['0x3f800000']*2,'shadow_texel_m':['0x3a000000']*2}]
            names=[p['name'] for p in frozen['required_checkpoints'] if p['frame']==str(f)]
            if names or thorough:
                r={'record_type':'checkpoint' if names else 'static_audit','frame':str(f),'names':names,'work':work,
                   'sha256':digest(payload),'body_sha256':{'1':digest(payload['bodies'][0])}}
                if names: r['payload']=copy.deepcopy(payload)
                records.append(r)
        for record in records:
            record["synthetic"]=True
        return records,frozen,payload,work

    def test_correct_missing_corrupted_and_incomplete_replays(self):
        for thorough in (False,True):
            records,frozen,payload,work=self.fixture(thorough)
            self.assertEqual(audit(records,frozen,payload,work,True,thorough)['status'],'pass')
            self.assertEqual(audit(records,frozen,payload,work,False,thorough)['status'],'fail')
            for kind in ('checkpoint','native_audit','frame','render_work'):
                bad=copy.deepcopy(records); bad.remove(next(r for r in bad if r['record_type']==kind))
                self.assertEqual(audit(bad,frozen,payload,work,True,thorough)['status'],'fail')
            bad=copy.deepcopy(records); r=next(r for r in bad if r['record_type']=='checkpoint')
            r['payload']['bodies'][0]['revision']='1'; r['sha256']=digest(r['payload'])
            result=audit(bad,frozen,payload,work,True,thorough)
            self.assertEqual(result['status'],'fail')
            self.assertEqual(result['failures'][0]['field'],'payload/bodies/body:1/revision')
            bad=copy.deepcopy(records); bad.append(next(r for r in bad if r['record_type']=='checkpoint'))
            self.assertEqual(audit(bad,frozen,payload,work,True,thorough)['status'],'fail')

    def test_equivalent_geometry_keeps_work_difference_separate(self):
        records,frozen,payload,work=self.fixture()
        alternative=copy.deepcopy(work)
        alternative[0].update(vertices="42",surface_rectangles="7")
        for r in records:
            if r["record_type"]=="checkpoint": r["work"]=alternative
            if r["record_type"]=="native_audit": r["vertices_checked"]="42"
        result=audit(records,frozen,payload,work,True)
        self.assertEqual(result["status"],"pass")
        self.assertFalse(result["representation_work"]["equal_to_validation"])
        self.assertEqual(result["actual_work"][0]["surface_rectangles"],"7")

    def test_intermediate_static_change_and_stale_mesh(self):
        records,frozen,payload,work=self.fixture(True)
        next(r for r in records if r['record_type']=='static_audit')['sha256']='0'*64
        self.assertEqual(audit(records,frozen,payload,work,True,True)['status'],'fail')
        records,frozen,payload,work=self.fixture()
        [r for r in records if r['record_type']=='render_work'][-1]['mesh_rebuilt']='1'
        self.assertEqual(audit(records,frozen,payload,work,True)['status'],'fail')


@unittest.skipUnless(os.environ.get("MEGASCENE_VULKAN_TEST") == "1", "opt-in real Vulkan validation/reuse")
class ValidationRunner(unittest.TestCase):
    def test_separate_validation_reuse_corruption_and_missing_evidence(self):
        from megascene_static import read_stream
        with tempfile.TemporaryDirectory(prefix="megascene-validation-test-",dir=Path.home()) as folder:
            root=Path(folder)
            base=[sys.executable,str(ROOT/"scripts/megascene.py"),"--case","static","--resolution","640x360",
                  "--warmup","1","--frames","3","--archive",str(root/"archive")]
            def run(name, extra):
                proc=subprocess.run([*base,"--output",str(root/name),*extra],capture_output=True,text=True,timeout=180)
                return proc,root/name
            proc,validated=run("validation-only",["--validation-only"])
            self.assertEqual(proc.returncode,0,proc.stderr)
            v=read_json((validated/"validation.json").read_text())
            self.assertEqual(v["checked_frames"],"5")
            self.assertFalse((validated/"cpu.jsonl").exists())
            proc,timed=run("timed",["--validated",str(validated)])
            self.assertEqual(proc.returncode,0,proc.stderr)
            summary=read_json((timed/"summary.json").read_text())
            self.assertTrue(summary["validation"]["reused"])
            self.assertEqual(summary["state_correctness"]["status"],"pass")
            for key in ("calibration","qualified_capacity","interactive_pass","visual_quality"):
                self.assertEqual(summary[key]["status"],"inconclusive")
            m=read_json((timed/"manifest.json").read_text())
            records,errors=read_stream(timed/"cpu.jsonl",m["attempt_id"])
            self.assertFalse(errors)
            self.assertNotEqual(m["attempt_id"],v["attempt_id"])
            old=read_json((validated/"validation/invocation.json").read_text())
            new=read_json((timed/"invocation.json").read_text())
            self.assertLess(int(old["process_end_ns"]),int(new["launch_ns"]))
            frozen=read_json((timed/"schedule.json").read_text())
            self.assertEqual(audit(records,frozen,v["expected"],v["actual_work"],True)["status"],"pass")
            changed=copy.deepcopy(records)
            c=next(r for r in changed if r["record_type"]=="checkpoint")
            c["payload"]["bodies"][0]["revision"]="99";c["sha256"]=digest(c["payload"])
            result=audit(changed,frozen,v["expected"],v["actual_work"],True)
            self.assertEqual(result["status"],"fail")
            self.assertIn("body:1/revision",result["failures"][0]["field"])
            absent=[r for r in records if r["record_type"]!="checkpoint"]
            self.assertEqual(audit(absent,frozen,v["expected"],v["actual_work"],True)["status"],"fail")
            proc,wrong=run("wrong-threads",["--validated",str(validated),"--threads","12"])
            self.assertEqual(proc.returncode,2)
            self.assertFalse((wrong/"cpu.jsonl").exists())
            self.assertIn("identity mismatch",(wrong/"validation.json").read_text())
            resources=validated/"validation/resources.jsonl"
            original_resources=resources.read_bytes()
            resources.write_bytes(original_resources+b"corrupt tail")
            proc,damaged=run("damaged-validation",["--validated",str(validated)])
            self.assertEqual(proc.returncode,2)
            self.assertFalse((damaged/"cpu.jsonl").exists())
            self.assertIn("stale validation evidence",(damaged/"validation.json").read_text())
            resources.write_bytes(original_resources)
            worker=validated/"runtime/worker"
            with worker.open("ab") as stream: stream.write(b"stale-artifact")
            proc,stale=run("stale-artifact",["--validated",str(validated)])
            self.assertEqual(proc.returncode,2)
            self.assertIn("stale runtime artifact",proc.stderr)
            self.assertFalse((stale/"cpu.jsonl").exists())


if __name__=='__main__': unittest.main()
