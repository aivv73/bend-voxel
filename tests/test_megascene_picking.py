"""Keep schedule/report fixtures, independent references and real runtime separate."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from megascene_picking import schedule, ray_bytes, audit, checked_result, center, value
from megascene_traversal import schedule as traversal, camera_bytes
from megascene_recipe import generate, Box
from megascene_picking_references import program, check
from megascene import configuration, parser


def config(preset='small',seed='45',route='picking-v2'):
    return dict(case='picking',preset=preset,seed=seed,schedule=route,warmup='120',frames='3600')


class PickingSchedule(unittest.TestCase):
    def test_exact_holds_and_shared_complete_camera_route(self):
        for preset in ('small','large'):
            for seed in ('45','46'):
                for version in ('v1','v2'):
                    frozen=schedule(config(preset,seed,'picking-'+version))
                    control=traversal({**config(preset,seed),'schedule':'traversal-'+version})
                    self.assertEqual(camera_bytes(frozen),camera_bytes(control))
                    self.assertEqual(len(ray_bytes(frozen)),3721*28)
                    enabled=[f for f in frozen['frames'] if f['picking']]
                    self.assertEqual(len(enabled),720)
                    self.assertEqual(sum(f['expected_pick']['kind']=='1' for f in enabled),600)
                    self.assertEqual(sum(f['expected_pick']['kind']=='0' for f in enabled),120)
                    self.assertEqual({int(f['measured_ordinal'])//300 for f in enabled},{1,2,3,4,7,8})
                    self.assertTrue(all(int(f['phase_offset'])<120 for f in enabled))
                    self.assertTrue(all(not f['picking'] for f in frozen['frames'][:121]))
                    self.assertTrue(all(not f['actions'] for f in frozen['frames']))
                    self.assertEqual(len(frozen['review_views']),14)
                    self.assertEqual(len(frozen['required_checkpoints']),16)
                    for f in enabled:
                        self.assertEqual(f['ray']['origin_m'],f['camera']['eye_m'])

    def test_reject_wrong_required_target_and_truncated_schedule(self):
        owners=generate('small',45)
        owners[1].boxes=[Box(b.lo,b.hi,4 if b.material==5 else b.material) for b in owners[1].boxes]
        with self.assertRaisesRegex(ValueError,'incorrect declared wall'):
            schedule(config(),owners)
        with self.assertRaises(ValueError): schedule({**config(),'frames':'3599'})
        with self.assertRaises(ValueError): schedule({**config(),'schedule':'traversal-v2'})
        # Exactly representable endpoints alone cannot admit the operations.
        ray={'origin_m':['0x00000000','0x3f800000','0x00000000'], 'direction':['0x3f800000','0x00000000','0x00000000']}
        with self.assertRaisesRegex(ValueError,'unsupported picking cells'):
            checked_result([(1,Box((8388600,10,0),(8388601,11,1),2),0.)],ray)
        with self.assertRaisesRegex(ValueError,'unsupported picking offset'):
            checked_result([(1,Box((0,10,0),(1,11,1),2),16777216.)],ray)
        # The 256 m endpoint is exact, but subtracting this tiny positive
        # origin rounds a mathematical in-reach distance back to 256 m.
        boundary_ray={**ray,'origin_m':['0x00000001','0x3f866666','0x3d4ccccd']}
        with self.assertRaisesRegex(ValueError,'rounded picking changes exact target/reach'):
            checked_result([(1,Box((2560,10,0),(2561,11,1),2),0.)],boundary_ray)

    def test_public_settings(self):
        args=parser().parse_args(['--case','picking','--output','build/test-picking','--archive','/home/aivv/picking-test-archive'])
        self.assertEqual(configuration(args)['schedule'],'picking-v2')
        args.frames='3599'
        with self.assertRaises(ValueError): configuration(args)

    def test_synthetic_reports_reject_missing_wrong_and_disabled_samples(self):
        frozen=schedule(config())
        records=[{'record_type':'picking','synthetic':True,'frame':f['frame'],'enabled':f['picking'],
                  'ray':f['ray'],'result':f['expected_pick']} for f in frozen['frames']]
        self.assertEqual(audit(records,frozen)['hits'],'600')
        with self.assertRaises(ValueError): audit(records[:-1],frozen)
        for index,key,replacement in ((421,'enabled',False),(0,'enabled',True),(422,'frame','421'),
                (421,'result',{**records[421]['result'],'owner':'1'}),
                (421,'ray',{**records[421]['ray'],'direction':['0x00000000']*3})):
            bad=copy.deepcopy(records);bad[index][key]=replacement
            with self.assertRaises(ValueError): audit(bad,frozen)


class PickingRuntimeReferences(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='picking-reference-')
        cls.root=Path(cls.temp.name)
        shutil.copytree(ROOT/'src',cls.root/'src')
        (cls.root/'src/reference_entry.bend').write_text(program())
        built=subprocess.run(['bend','src/reference_entry.bend','-o','reference'],cwd=cls.root,capture_output=True,text=True,timeout=120)
        if built.returncode: raise AssertionError(built.stdout+built.stderr)

    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()

    def test_actual_bend_against_rational_and_dense_references_at_1_6_12_threads(self):
        outputs=[]
        for threads in ('1','6','12'):
            run=subprocess.run([str(self.root/'reference'),'--gpu','off','--threads',threads],capture_output=True,text=True,timeout=30)
            self.assertEqual(run.returncode,0,run.stderr)
            self.assertEqual(check(run.stdout)['status'],'pass')
            outputs.append(run.stdout)
        self.assertEqual(outputs[0],outputs[1]);self.assertEqual(outputs[0],outputs[2])
        by_name={r['name']:r for r in map(json.loads,outputs[0].splitlines())}
        self.assertEqual(by_name['reach_below']['distance_m'],'0x437fffff')
        self.assertEqual(by_name['reach_at']['kind'],'0')
        self.assertEqual(by_name['reach_beyond']['kind'],'0')
        self.assertEqual(by_name['protected']['kind'],'2')

    def test_actual_center_rays_match_frozen_camera_projection(self):
        from megascene_picking_references import real, vec
        views=[]
        for preset in ('small','large'):
            for seed in ('45','46'):
                frozen=schedule(config(preset,seed))
                views += [f for f in frozen['frames'] if f['picking'] and f['phase_offset']=='0']
        source=program().split('def main()',1)[0]+'''def show(ray: P.Ray) -> IO(Unit):
  P.Ray{_,origin,direction} = ray
  IO.print("[" ++ M.vec(origin) ++ "," ++ M.vec(direction) ++ "]")
def main() -> IO(Unit):
  do IO<Unit>:
'''
        for frame in views:
            c=frame['camera']
            camera='V.Camera{'+vec(map(value,c['eye_m']))+','+real(value(c['yaw']))+','+real(value(c['pitch']))+',1920,1080}'
            source+='    show(P.center(P.Ray{True{},R.Vec{0.0,0.0,0.0},R.Vec{0.0,0.0,0.0}},'+camera+'))\n'
        (self.root/'src/center.bend').write_text(source)
        built=subprocess.run(['bend','src/center.bend','-o','center'],cwd=self.root,capture_output=True,text=True,timeout=120)
        self.assertEqual(built.returncode,0,built.stdout+built.stderr)
        run=subprocess.run([str(self.root/'center')],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stderr)
        self.assertEqual([json.loads(line) for line in run.stdout.splitlines()],
                         [f['ray']['origin_m']+f['ray']['direction'] for f in views])

    def test_native_operation_guards(self):
        binary=self.root/'numeric-guards'
        run=subprocess.run(['g++','-O2','-std=c++17','-Wall','-Wextra',str(ROOT/'tests/native_picking.cpp'),'-o',str(binary)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stderr)
        run=subprocess.run([str(binary)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stderr)

    def test_actual_guard_rejects_before_unsafe_traversal(self):
        source=program().split('def main()',1)[0]+'''def main() -> IO(Unit):
  do IO<Unit>:
    hit : V.Hit <- P.pick([W.Body{1,0,16777216.0,0.0,True{},S.Leaf{S.Box{R.Vec{0.0,10.0,0.0},R.Vec{1.0,11.0,1.0},2}},Nil{},Nil{}}],P.Ray{True{},R.Vec{0.0,1.05,0.05},R.Vec{1.0,0.0,0.0}})
    emit("unsafe_was_executed",hit)
'''
        (self.root/'src/rejected.bend').write_text(source)
        built=subprocess.run(['bend','src/rejected.bend','-o','rejected'],cwd=self.root,capture_output=True,text=True,timeout=120)
        self.assertEqual(built.returncode,0,built.stderr)
        run=subprocess.run([str(self.root/'rejected')],capture_output=True,text=True)
        self.assertNotEqual(run.returncode,0)
        self.assertIn('unsupported cell/metre/offset/distance operation',run.stderr+run.stdout)
        self.assertNotIn('unsafe_was_executed',run.stdout)


if __name__=='__main__': unittest.main()
