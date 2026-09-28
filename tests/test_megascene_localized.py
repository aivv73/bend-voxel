"""Localized runner reports, independent edit references and numeric guards."""
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
from megascene import configuration,parser
from megascene_localized import schedule,action_outcome,audit_actions,edited_payload
from megascene_edit_references import program,check
from megascene_static import report
from test_megascene_static import fixtures as static_fixtures
from test_megascene_gpu import fixtures as gpu_fixtures

CONFIG=dict(case='localized',preset='small',side_m='64',seed='45',threads='6',fragment_budget='2048',
            resolution='640x360',profile='full',warmup='120',frames='3600',schedule='localized-v1',schedule_kind='accepted')


def records():
    frozen=schedule(CONFIG);template=static_fixtures();result=[template[0],template[1]]
    for i,frame in enumerate(frozen['frames']):
        start=10**15+i*100;end=start+100
        state=copy.deepcopy(next(r for r in template if r['record_type']=='static_state'))
        state.update(frame=str(i),time_ns=str(end),**frame['camera'])
        if i>=121: state.update(cells='10503344',removed='16',next_id='23')
        result.append(state)
        work=copy.deepcopy(next(r for r in template if r['record_type']=='render_work'))
        work.update(frame=str(i),time_ns=str(end));result.append(work)
        stages=[r['stage'] for r in template if r['record_type']=='stage' and r['frame']==('0' if i==0 else '1')]
        if i==121: stages+=['carve','connectivity','surfaces','commit']
        ordered=('physics','carve','connectivity','surfaces','commit','view')
        for name in stages:
            a,b=start,end
            if i==121 and name in ordered:
                a=start+ordered.index(name)*10;b=a+5
            result.append(dict(record_type='stage',frame=str(i),stage=name,begin_ns=str(a),end_ns=str(b),duration_ns=str(b-a),status='measured',unit='ns'))
        if i==121:
            result += [dict(record_type='edit_begin',frame='121',action='0',begin_ns=str(start+7)),
                dict(record_type='action',frame='121',action='0',accepted=True,removed_cells='16',outcome=action_outcome(frozen)),
                dict(record_type='edit',frame='121',action='0',accepted=True,removed_cells='16',begin_ns=str(start+7),end_ns=str(end),duration_ns='93')]
        result.append(dict(record_type='frame',frame=str(i),population=frame['phase'],begin_ns=str(start),end_ns=str(end),duration_ns='100'))
    result += [dict(record_type='stage',frame='3721',stage='teardown',begin_ns=str(10**15+372100),end_ns=str(10**15+372200)),dict(record_type='complete',frame='3721')]
    for r in result:r['synthetic']=True
    return result,frozen


class LocalizedSchedule(unittest.TestCase):
    def test_exact_cut_and_preflight_both_presets_seeds(self):
        for preset,side in (('small','64'),('large','128')):
            for seed in ('45','46'):
                frozen=schedule({**CONFIG,'preset':preset,'side_m':side,'seed':seed})
                self.assertEqual(len(frozen['frames']),3721)
                self.assertEqual([f['frame'] for f in frozen['frames'] if f['actions']],['121'])
                self.assertEqual(len(frozen['actions']),1)
                self.assertEqual(frozen['actions'][0]['expected_removed_cells'],'16')
                self.assertEqual(frozen['actions'][0]['pre_edit_hit']['owner'],'1')
                self.assertEqual({f['phase'] for f in frozen['frames'][122:]},{'ordinary'})
                self.assertTrue(all(f['camera']==frozen['frames'][121]['camera'] for f in frozen['frames'][121:]))
                self.assertEqual([p['frame'] for p in frozen['review_views']],['0','121','3720'])
        for key,val in (('frames','3599'),('warmup','0'),('schedule','static-v1')):
            with self.assertRaises(ValueError):schedule({**CONFIG,key:val})

    def test_public_configuration_rejects_reduced_or_changed_work(self):
        base=['--case','localized','--output','build/test-localized','--archive','/home/aivv/localized-test-archive']
        c=configuration(parser().parse_args(base));self.assertEqual(c['schedule'],'localized-v1')
        for opts in (['--frames','1'],['--warmup','0'],['--schedule','static-v1'],['--capture-opening'],['--profile','proxy']):
            with self.assertRaises(ValueError):configuration(parser().parse_args(base+opts))

    def test_one_edit_keeps_cpu_gpu_populations_and_gate_separate(self):
        raw,frozen=records();audit_actions(raw,frozen)
        r=report(raw,[],CONFIG,0,'normal_exit',10**15-100,'fixture',gpu_records=gpu_fixtures(3721))
        self.assertEqual(r['schedule_completion']['status'],'pass',r['evidence_errors'])
        self.assertEqual(r['populations']['ordinary']['count'],'3599')
        self.assertEqual(r['populations']['edit']['count'],'1')
        self.assertEqual(r['accepted_edits']['count'],'1');self.assertEqual(r['accepted_edits']['max'],93)
        self.assertEqual(r['gpu_execution']['populations']['ordinary']['count'],'3599')
        self.assertEqual(r['gpu_execution']['populations']['edit']['count'],'1')
        self.assertEqual(r['edit_response']['status'],'inconclusive')
        self.assertEqual(r['interactive_pass']['status'],'inconclusive')

    def test_required_rejection_noop_duplicate_missing_and_bad_interval_cannot_complete(self):
        original,frozen=records()
        for mutate in ('rejected','noop','duplicate','missing','end','order'):
            raw=copy.deepcopy(original)
            action=next(r for r in raw if r['record_type']=='action')
            if mutate in ('rejected','noop'):
                action['accepted']=False;action['removed_cells']='0'
                action['outcome'].update(accepted=False,removed_cells='0',outcome='rejected_budget' if mutate=='rejected' else 'no_op')
            elif mutate=='duplicate':raw.append(copy.deepcopy(action))
            elif mutate=='missing':raw.remove(action)
            elif mutate=='end':next(r for r in raw if r['record_type']=='edit')['end_ns']='0'
            else:next(r for r in raw if r.get('stage')=='commit')['begin_ns']='0'
            with self.assertRaises(ValueError,msg=mutate):audit_actions(raw,frozen)
            r=report(raw,[],CONFIG,0,'normal_exit',10**15-100,'fixture',gpu_records=gpu_fixtures(3721))
            self.assertNotEqual(r['schedule_completion']['status'],'pass',mutate)

    def test_canonical_edit_state_and_missing_payload_or_changed_cache(self):
        from megascene_checkpoints import occupancy,strings,surface
        from megascene_inventory import digest,surface_reference
        from megascene_recipe import Box
        from megascene_localized import audit,expected_payload
        raw,frozen=records()
        boxes=[Box((-164,0,-164),(-156,1,-156),1),Box((-164,1,-164),(-156,24,-156),2)]
        body=dict(id='1',revision='0',anchored=True,offset_m='0x00000000',velocity_m_s='0x00000000',
                  occupancy=strings(occupancy(boxes)),surface=surface(surface_reference(boxes)))
        initial=dict(schema='megascene-checkpoint/1',bodies=[body],cells='1536',removed='0',status='1',next_id='2',
                     fragments='0',budget='2048',action_outcomes=[],view=frozen['opening'])
        edited=edited_payload(initial,frozen)
        works=[[dict(id='1',cells='1536',protected_cells='64',vertices='72')],
               [dict(id='2',cells='1520',protected_cells='64',vertices='144')]]
        payloads=[expected_payload(initial,edited,frozen['frames'][i]) for i in (0,121)]
        hashes=[digest(p) for p in payloads]
        bodies=[{b['id']:digest(b) for b in p['bodies']} for p in payloads]
        raw=[r for r in raw if r['record_type']!='render_work']
        for i in range(3721):
            phase=int(i>=121);ident=str(phase+1)
            raw += [dict(record_type='native_audit',frame=str(i),drawn_ids=[ident],reference_visible='1',vertices_checked=works[phase][0]['vertices'],
                         mesh_slots={ident:['0',works[phase][0]['vertices']]},proxy_cache_sha256={}),
                    dict(record_type='render_work',frame=str(i),main_body_draws='1',mesh_rebuilt='1' if i in (0,121) else '0',
                         shadow_refresh=i in (0,121),shadow_body_draws='1' if i in (0,121) else '0',proxy_rebuilt='0',proxy_groups='0',proxy_vertices='0',
                         shadow_extent_m=['0x3f800000']*2,shadow_texel_m=['0x3a000000']*2)]
            names=[p['name'] for p in frozen['required_checkpoints'] if p['frame']==str(i)]
            if names:
                raw.append(dict(record_type='checkpoint',frame=str(i),names=names,work=works[phase],payload=payloads[phase],sha256=hashes[phase],body_sha256=bodies[phase]))
        for r in raw:r['synthetic']=True
        good=audit(raw,frozen,initial,works[0],True)
        self.assertEqual(good['status'],'pass',good)
        for mutation in ('payload','kind','history','cache','geometry'):
            bad=copy.deepcopy(raw)
            point=next(r for r in bad if r['record_type']=='checkpoint' and r['frame']=='121')
            if mutation=='payload':point.pop('payload')
            elif mutation=='kind':point['record_type']='static_audit'
            elif mutation=='history':point['payload']['action_outcomes']=[]
            elif mutation=='geometry':point['body_sha256']['2']='0'*64
            else:next(r for r in bad if r['record_type']=='native_audit' and r['frame']=='122')['proxy_cache_sha256']={'0':'0'*64}
            self.assertEqual(audit(bad,frozen,initial,works[0],True)['status'],'fail',mutation)


class EditReferences(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory();cls.root=Path(cls.temp.name)
        shutil.copytree(ROOT/'src',cls.root/'src')
        (cls.root/'src/reference_entry.bend').write_text(program())
        r=subprocess.run(['bend','src/reference_entry.bend','-o','reference'],cwd=cls.root,capture_output=True,text=True,timeout=120)
        if r.returncode:raise AssertionError(r.stdout+r.stderr)

    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()

    def test_dense_references_and_exact_rollback_match_at_1_6_12_threads(self):
        outputs=[]
        for threads in ('1','6','12'):
            r=subprocess.run([str(self.root/'reference'),'--gpu','off','--threads',threads],capture_output=True,text=True,timeout=30)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            result=check(r.stdout);self.assertEqual(result['status'],'pass')
            entries=[json.loads(line) for line in r.stdout.splitlines()]
            for entry in entries:entry.pop('threads',None)
            outputs.append(entries)
        self.assertEqual(outputs[0],outputs[1]);self.assertEqual(outputs[0],outputs[2])
        self.assertEqual(len(result['fixtures']),7)
        # Corrupt a protected cell's material without changing the totals.
        bad=copy.deepcopy(outputs[0]);body=next(r for r in bad if r['record_type']=='body')
        body['boxes'][0][6]='5'
        with self.assertRaises(ValueError):check('\n'.join(map(json.dumps,bad))+'\n')

    def test_actual_recorder_retains_rejected_and_noop_actions(self):
        shutil.copy2(ROOT/'tests/edit_record.c',self.root/'src/edit_record.c')
        (self.root/'src/test_record.bend').write_text('''import Base
def start() -> IO(Unit):
  import "./edit_record.c"
def end() -> IO(Unit):
  import "./edit_record.c"
''')
        source=program().split('def main()',1)[0].replace('import Base','import Base\nimport ./vulkan.bend as VK\nimport ./test_record.bend as Test')
        source+='''def record(+w: W.World, +point: R.Vec, +action: U32) -> IO(Unit):
  do IO<Unit>:
    VK.vulkan.editbegin(action,point)
    VK.vulkan.mark(19)
    E.guard(w,point)
    +w : W.World <- IO.pure(W.World,W.carve(w,point))
    VK.vulkan.mark(20)
    VK.vulkan.editrecord(w,action,point)
    Test.end()
def main() -> IO(Unit):
  do IO<Unit>:
    Test.start()
    record(fixture(W.assemblies([owner2(),owner3()],1),1,(0.0 - 1.0 : F32),(0.0 - 2.0 : F32)),R.Vec{(0.0 - 0.05 : F32),9.05,0.05},0)
    record(fixture(W.assemblies([owner6(),owner7()],1),0,0.0,0.0),R.Vec{0.0,0.0,0.0},1)
'''
        (self.root/'src/record_entry.bend').write_text(source)
        r=subprocess.run(['bend','src/record_entry.bend','-o','record'],cwd=self.root,capture_output=True,text=True,timeout=120)
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        r=subprocess.run([str(self.root/'record')],capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        entries=[json.loads(line) for line in r.stdout.splitlines()]
        actions=[r['outcome'] for r in entries if r['record_type']=='action']
        self.assertEqual([a['outcome'] for a in actions],['rejected_budget','no_op'])
        self.assertTrue(all(a['accepted'] is False and a['removed_cells']=='0' for a in actions))
        self.assertEqual([a['action'] for a in actions],['0','1'])
        histories=[r['action_outcomes'] for r in entries if r['record_type']=='history']
        self.assertEqual(histories,[actions[:1],actions])

    def test_native_predicates_and_coordinate_boundaries(self):
        binary=self.root/'guard'
        r=subprocess.run(['g++','-O2','-std=c++17','-include','initializer_list',str(ROOT/'tests/native_edit.cpp'),'-o',str(binary)],capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr)
        r=subprocess.run([str(binary)],capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)

    def test_actual_guard_stops_before_unsafe_id_allocation(self):
        source=program().split('def main()',1)[0]+'''def invalid(world: W.World) -> W.World:
  W.World{bs,n,c,r,s,_,b} = world
  W.World{bs,n,c,r,s,4294967295,b}
def main() -> IO(Unit):
  do IO<Unit>:
    w : W.World <- apply(invalid(W.from.bodies(W.assemblies([owner0()],1),2048)),R.Vec{0.0,0.0,0.0})
    IO.print("unsafe_was_executed")
'''
        (self.root/'src/rejected.bend').write_text(source)
        r=subprocess.run(['bend','src/rejected.bend','-o','rejected'],cwd=self.root,capture_output=True,text=True,timeout=120)
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        r=subprocess.run([str(self.root/'rejected')],capture_output=True,text=True)
        self.assertNotEqual(r.returncode,0);self.assertIn('evolving count/ID/native size',r.stdout+r.stderr)
        self.assertNotIn('unsafe_was_executed',r.stdout)

if __name__=='__main__':unittest.main()
