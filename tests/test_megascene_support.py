"""Support schedules, real Bend references and deliberately synthetic report gates."""
import copy
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from functools import lru_cache

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from megascene import configuration,parser
from megascene_support import (schedule,geometry,motion,action_outcome,audit_actions,audit_window,audit,CUT_FRAMES,WINDOW,value)
from megascene_support_references import program,check
from megascene_recipe import generate,Box,bits
from megascene_inventory import digest
from megascene_static import report
from test_megascene_static import fixtures as static_fixtures
from test_megascene_gpu import fixtures as gpu_fixtures

CONFIG=dict(case='support',preset='small',side_m='64',seed='45',threads='6',fragment_budget='2048',
            resolution='640x360',profile='full',warmup='120',frames='3600',schedule='support-v1',schedule_kind='accepted')


@lru_cache(maxsize=1)
def fixtures():
    """Hand-authored support-layer splits, with deliberately synthetic mesh data."""
    frozen=schedule(CONFIG);owners=generate('small',45)
    def body(ident,boxes,offset='0x00000000',speed='0x00000000'):
        return dict(geometry(boxes),id=str(ident),revision='0',offset_m=offset,velocity_m_s=speed)
    def work(ident,boxes):
        count=sum(math.prod(b-a for a,b in zip(box.lo,box.hi)) for box in boxes)
        protected=sum(math.prod(b-a for a,b in zip(box.lo,box.hi)) for box in boxes if box.material==1)
        return dict(id=str(ident),cells=str(count),protected_cells=str(protected),vertices=str(len(boxes)*36))
    def stump(boxes,right):
        support=boxes[3 if right else 2]
        return [boxes[1 if right else 0],Box(support.lo,(support.hi[0],38,support.hi[2]),3)]
    def beam(boxes,both):
        left,right=boxes[2:4]
        left=Box((left.lo[0],42,left.lo[2]),left.hi,3)
        if both:right=Box((right.lo[0],42,right.lo[2]),right.hi,3)
        return ([boxes[1]] if not both else [])+[left,right,boxes[4]]
    phases=[];works=[]
    for phase in range(7):
        scene={i:o.boxes for i,o in enumerate(owners,1)}
        for j in range(3):
            cuts=max(0,min(2,phase-2*j));boxes=owners[j+2].boxes
            if cuts:
                del scene[j+3];scene[22+4*j]=stump(boxes,False)
                if cuts==1:scene[23+4*j]=beam(boxes,False)
                else:scene[24+4*j]=stump(boxes,True);scene[25+4*j]=beam(boxes,True)
        bs=[body(i,b) for i,b in sorted(scene.items())]
        state=dict(schema='megascene-checkpoint/1',bodies=bs,cells=str(10503360-16*phase),removed='16' if phase else '0',
                   status='1',next_id=str(22+2*phase),fragments=str(phase//2),budget='2048',
                   action_outcomes=[action_outcome(a) for a in frozen['actions'][:phase]],view=frozen['opening'])
        phases.append(state);works.append([work(i,b) for i,b in sorted(scene.items())])
    template=static_fixtures();raw=[copy.deepcopy(template[0]),copy.deepcopy(template[1])]
    previous_offsets=None
    for i,frame in enumerate(frozen['frames']):
        phase=sum(at<=i for at in CUT_FRAMES)
        state={**phases[phase], 'view':frame['camera'],'bodies':[]}
        for b in phases[phase]['bodies']:
            if not b['anchored']:
                j=(int(b['id'])-25)//4
                off,speed=motion(min(i-CUT_FRAMES[j*2+1],60))
                b=dict(b,offset_m=off,velocity_m_s=speed)
                raw.append(dict(record_type='body_motion',frame=str(i),**{k:b[k] for k in ('id','revision','offset_m','velocity_m_s')}))
            state['bodies'].append(b)
        begin=10**15+i*100;end=begin+100
        scalar=copy.deepcopy(next(r for r in template if r['record_type']=='static_state'))
        scalar.update(frame=str(i),time_ns=str(end),**frame['camera'],anchored=str(21+(phase+1)//2),
                      moving=str(sum(value(b['velocity_m_s'])!=0 for b in state['bodies'])),translated=str(sum(value(b['offset_m'])!=0 for b in state['bodies'])),
                      **{k:state[k] for k in ('cells','removed','next_id','fragments','budget')})
        raw.append(scalar)
        ids=[b['id'] for b in state['bodies']];offsets={b['id']:b['offset_m'] for b in state['bodies']}
        changed=offsets!=previous_offsets;previous_offsets=offsets
        work_record=copy.deepcopy(next(r for r in template if r['record_type']=='render_work'))
        work_record.update(frame=str(i),time_ns=str(end),body_count=str(len(ids)),full_meshes=str(len(ids)),main_body_draws=str(len(ids)),visible_bodies=str(len(ids)),
           mesh_rebuilt=str(len(ids)) if i==0 else '2' if i in CUT_FRAMES else '0',shadow_refresh=changed,shadow_body_draws=str(len(ids)) if changed else '0',
           proxy_rebuilt='0',shadow_extent_m=[bits(64)]*2,shadow_fit_min_margin_texels=bits(1),shadow_texel_m=[bits(.1)]*2)
        raw.append(work_record)
        raw.append(dict(record_type='native_audit',frame=str(i),drawn_ids=ids,reference_visible=str(len(ids)),
           vertices_checked=str(sum(int(w['vertices']) for w in works[phase])),mesh_slots={w['id']:[str(int(w['id'])*10000),w['vertices']] for w in works[phase]},
           mesh_sha256={b['id']:digest({k:v for k,v in b.items() if k not in ('offset_m','velocity_m_s')}) for b in state['bodies']},proxy_cache_sha256={}))
        names=[p['name'] for p in frozen['required_checkpoints'] if p['frame']==str(i)]
        if names:raw.append(dict(record_type='checkpoint',frame=str(i),names=names,payload=state,sha256=digest(state),body_sha256={b['id']:digest(b) for b in state['bodies']},work=works[phase]))
        stages=[r['stage'] for r in template if r['record_type']=='stage' and r['frame']==('0' if i==0 else '1')]
        if names:stages.append('checkpoint')
        if i in CUT_FRAMES:stages+=['carve','connectivity','surfaces','commit']
        ordered=('physics','carve','connectivity','surfaces','commit','view')
        for name in stages:
            a,b=begin,end
            if i in CUT_FRAMES and name in ordered:a=begin+ordered.index(name)*10;b=a+5
            raw.append(dict(record_type='stage',frame=str(i),stage=name,begin_ns=str(a),end_ns=str(b),duration_ns=str(b-a),status='measured',unit='ns'))
        if i in CUT_FRAMES:
            a=frozen['actions'][CUT_FRAMES.index(i)];action=a['action']
            raw += [dict(record_type='edit_begin',frame=str(i),action=action,begin_ns=str(begin+7)),
                    dict(record_type='action',frame=str(i),action=action,accepted=True,removed_cells='16',outcome=action_outcome(a)),
                    dict(record_type='edit',frame=str(i),action=action,accepted=True,removed_cells='16',begin_ns=str(begin+7),end_ns=str(end),duration_ns='93')]
        raw.append(dict(record_type='frame',frame=str(i),population=frame['phase'],begin_ns=str(begin),end_ns=str(end),duration_ns='100'))
    raw += [dict(record_type='stage',frame='3721',stage='teardown',begin_ns=str(10**15+372100),end_ns=str(10**15+372200)),dict(record_type='complete',frame='3721')]
    for r in raw:r['synthetic']=True
    return raw,frozen,phases[0],works[0]


class SupportSchedule(unittest.TestCase):
    def test_exact_cuts_and_preflight_both_presets_seeds(self):
        for preset,side in (('small','64'),('large','128')):
            for seed in ('45','46'):
                frozen=schedule({**CONFIG,'preset':preset,'side_m':side,'seed':seed})
                self.assertEqual([a['measured_ordinal'] for a in frozen['actions']],['0','6','12','18','24','30'])
                self.assertEqual([f['frame'] for f in frozen['frames'] if f['phase']=='motion'],list(map(str,WINDOW)))
                self.assertTrue(all(a['expected_removed_cells']=='16' for a in frozen['actions']))
                self.assertEqual([r['frame'] for r in frozen['review_views']],['0','121','127','133','139','145','151','152','163','3720'])
        for key,val in (('frames','3599'),('warmup','0'),('schedule','static-v1')):
            with self.assertRaises(ValueError):schedule({**CONFIG,key:val})
        base=['--case','support','--output','build/test-support','--archive','/home/aivv/support-test-archive']
        self.assertEqual(configuration(parser().parse_args(base))['schedule'],'support-v1')
        for opts in (['--frames','1'],['--warmup','0'],['--schedule','localized-v1'],['--capture-opening'],['--profile','proxy']):
            with self.assertRaises(ValueError):configuration(parser().parse_args(base+opts))

    def test_motion_analytic_precontact_and_floor(self):
        for steps in range(1,56):
            offset,speed=map(value,motion(steps))
            self.assertAlmostEqual(offset,-4.905*(steps/60)**2,places=4)
            self.assertAlmostEqual(speed,-9.81*steps/60,places=4)
        self.assertEqual(motion(60),motion(3600))
        self.assertEqual(value(motion(60)[1]),0)
        self.assertAlmostEqual(value(motion(60)[0]),-4.2,places=6)

    def test_synthetic_complete_case_and_separate_cpu_gpu_populations(self):
        raw,frozen,initial,work=fixtures()
        checked=audit(raw,frozen,initial,work,True)
        self.assertEqual(checked['status'],'pass',checked['failures'])
        self.assertTrue(checked['synthetic']);self.assertEqual(len(checked['beam_features']),6)
        r=report(raw,[],CONFIG,0,'normal_exit',10**15-100,'fixture',gpu_records=gpu_fixtures(3721))
        self.assertEqual(r['schedule_completion']['status'],'pass',r['evidence_errors'])
        for population,count in (('ordinary','3582'),('edit','6'),('motion','12')):
            self.assertEqual(r['populations'][population]['count'],count)
            self.assertEqual(r['gpu_execution']['populations'][population]['count'],count)
        self.assertEqual(r['accepted_edits']['count'],'6');self.assertEqual(r['accepted_edits']['max'],93)
        self.assertEqual(r['edit_response']['status'],'inconclusive');self.assertEqual(r['interactive_pass']['status'],'inconclusive')

    def test_required_cut_or_window_failures_cannot_complete(self):
        original,frozen,_,_=fixtures()
        for mutation in ('rejection','noop','missing_cut','duplicate','interval','missing_motion','landed','same_identity','wrong_span','missing_checkpoint'):
            raw=copy.deepcopy(original)
            action=next(r for r in raw if r['record_type']=='action' and r['action']=='2')
            if mutation in ('rejection','noop'):
                action.update(accepted=False,removed_cells='0');action['outcome'].update(accepted=False,removed_cells='0',outcome='rejected_budget' if mutation=='rejection' else 'no_op')
            elif mutation=='missing_cut':raw.remove(action)
            elif mutation=='duplicate':raw.append(action)
            elif mutation=='interval':next(r for r in raw if r['record_type']=='edit')['end_ns']='0'
            elif mutation=='missing_motion':raw.remove(next(r for r in raw if r['record_type']=='body_motion' and r['frame']=='158'))
            elif mutation=='landed':next(r for r in raw if r['record_type']=='body_motion' and r['frame']=='158')['velocity_m_s']=bits(0)
            elif mutation=='same_identity':next(r for r in raw if r['record_type']=='body_motion' and r['frame']=='158')['id']='29'
            elif mutation=='wrong_span':
                b=next(b for r in raw if r['record_type']=='checkpoint' and r['frame']=='151' for b in r['payload']['bodies'] if b['id']=='33')
                b['occupancy']=copy.deepcopy(next(b for r in raw if r['record_type']=='checkpoint' and r['frame']=='151' for b in r['payload']['bodies'] if b['id']=='29')['occupancy'])
            else:raw.remove(next(r for r in raw if r['record_type']=='checkpoint' and r['frame']=='158'))
            r=report(raw,[],CONFIG,0,'normal_exit',10**15-100,'fixture',gpu_records=gpu_fixtures(3721))
            self.assertNotEqual(r['schedule_completion']['status'],'pass',mutation)

    def test_inherited_motion_anchors_geometry_cache_and_shadow_mutations(self):
        original,frozen,initial,work=fixtures()
        for mutation in ('first_support','stump','removed_material','inherited_velocity','mesh','slot','shadow','floor','missing_surface','missing_feature'):
            raw=copy.deepcopy(original)
            point=next(r for r in raw if r['record_type']=='checkpoint' and r['frame']=='121')
            if mutation=='first_support':point['payload']['bodies'][-1]['anchored']=False
            elif mutation=='stump':point['payload']['bodies'][-2]['occupancy']=[]
            elif mutation=='removed_material':point['payload']['cells']='10503343'
            elif mutation=='inherited_velocity':point['payload']['bodies'][-1]['velocity_m_s']=bits(-1)
            elif mutation=='mesh':next(r for r in raw if r['record_type']=='native_audit' and r['frame']=='155')['mesh_sha256']['25']='0'*64
            elif mutation=='slot':next(r for r in raw if r['record_type']=='native_audit' and r['frame']=='155')['mesh_slots']['25']=['0','0']
            elif mutation=='shadow':next(r for r in raw if r['record_type']=='render_work' and r['frame']=='155')['shadow_refresh']=False
            elif mutation=='floor':next(r for r in raw if r['record_type']=='body_motion' and r['frame']=='3720')['offset_m']=bits(-1.8)
            elif mutation=='missing_surface':point['payload']['bodies'][-1]['surface']=[]
            else:next(r for r in raw if r['record_type']=='native_audit' and r['frame']=='152')['drawn_ids'].remove('25')
            self.assertEqual(audit(raw,frozen,initial,work,True)['status'],'fail',mutation)


class SupplementaryEvidence(unittest.TestCase):
    def test_detail_views_preserve_world_caches_restore_overview_and_never_enter_timing(self):
        from megascene_support import audit_details
        original,frozen,_,_=fixtures()
        raw=copy.deepcopy(original)
        for detail in frozen['supplementary_views']:
            frame=detail['frame']
            n=next(r for r in raw if r['record_type']=='native_audit' and r['frame']==frame)
            w=next(r for r in raw if r['record_type']=='render_work' and r['frame']==frame)
            raw.append(dict(record_type='detail_capture',frame=str(int(frame)+1),rendered_frame=frame,action=detail['action'],camera=detail['camera']))
            for phase in ('closeup','restore'):
                for evidence in (n,dict(w,mesh_rebuilt='0',proxy_rebuilt='0',shadow_refresh=False,shadow_body_draws='0')):
                    raw.append(dict(record_type='detail_render',frame=str(int(frame)+1),rendered_frame=frame,phase=phase,evidence=copy.deepcopy(evidence)))
        audit_details(raw,frozen,True)
        with self.assertRaises(ValueError):audit_details(raw,frozen,False)
        with self.assertRaises(ValueError):audit_details(original,frozen,True)
        for mutation in ('camera','missing','mesh','shadow','restore'):
            changed=copy.deepcopy(raw)
            if mutation=='camera':next(r for r in changed if r['record_type']=='detail_capture')['camera']['pitch']=bits(1)
            elif mutation=='missing':changed.remove(next(r for r in changed if r['record_type']=='detail_capture'))
            else:
                n=next(r for r in changed if r['record_type']=='detail_render' and r['phase']=='restore' and r['evidence']['record_type']=='native_audit')['evidence']
                if mutation=='mesh':n['mesh_sha256']['1']='0'*64
                elif mutation=='restore':n['drawn_ids']=[]
                else:next(r for r in changed if r['record_type']=='detail_render' and r['evidence']['record_type']=='render_work')['evidence']['shadow_refresh']=True
            with self.assertRaises(ValueError,msg=mutation):audit_details(changed,frozen,True)

    def test_closeup_can_cover_occlusion_but_cannot_override_incorrect_geometry(self):
        from test_megascene_traversal import ReviewClassification
        from megascene import snapshot
        from megascene_review import assess
        import hashlib
        for incorrect in (False,True):
            with tempfile.TemporaryDirectory() as folder:
                root,path,_=ReviewClassification().bundle(folder,'incorrect' if incorrect else 'correct',
                    'unassessable' if incorrect else 'insufficient','The feature is occluded in the overview.')
                def read(name):return json.loads((root/name).read_text())
                m=read('manifest.json');m['effective']['case']='support';snapshot(root/'manifest.json',m)
                snapshot(root/'schedule.json',{'schedule_id':'support-v1'})
                r=read('review.json');r['schedule_sha256']=hashlib.sha256((root/'schedule.json').read_bytes()).hexdigest()
                overview=r['views'][0];overview['frame']='121';overview['features'][0]['covered_by']='detail_0'
                detail=copy.deepcopy(overview);detail.update(name='detail_0',supplementary_to='opening')
                detail['features'][0].pop('covered_by');r['views'].append(detail);snapshot(root/'review.json',r)
                answers=json.loads(path.read_text());answers['views']['detail_0']={'building silhouettes':{'geometry':'correct','readability':'readable'}};snapshot(path,answers)
                self.assertEqual(assess(root,path,'fixture reviewer'),'incorrect_rendering' if incorrect else 'pass')
                reviewed=read('review.json')
                self.assertNotEqual(reviewed['views'][0]['features'][0]['readability'],'readable')



class SupportRuntime(unittest.TestCase):
    def test_actual_bend_dense_support_and_motion_at_1_6_12_threads(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);shutil.copytree(ROOT/'src',root/'src')
            (root/'src/entry.bend').write_text(program())
            built=subprocess.run(['bend','src/entry.bend','-o','worker'],cwd=root,capture_output=True,text=True,timeout=120)
            self.assertEqual(built.returncode,0,built.stdout+built.stderr)
            outputs=[]
            for threads in ('1','6','12'):
                r=subprocess.run([str(root/'worker'),'--gpu','off','--threads',threads],capture_output=True,text=True,timeout=30)
                self.assertEqual(r.returncode,0,r.stdout[-1000:]+r.stderr)
                data=[json.loads(line) for line in r.stdout.splitlines()]
                for row in data:row.pop('threads',None)
                outputs.append(data)
            self.assertEqual(outputs[0],outputs[1]);self.assertEqual(outputs[0],outputs[2])
            self.assertEqual(check(r.stdout)['status'],'pass')
            # Moving geometry stays identical in actual output; a changed velocity
            # fails the independent reference even if occupancy still matches.
            lines=r.stdout.splitlines();body=json.loads(lines[-3]);body['speed']=bits(-1)
            lines[-3]=json.dumps(body)
            with self.assertRaises(ValueError):check('\n'.join(lines)+'\n')


@unittest.skipUnless(os.environ.get('MEGASCENE_VULKAN_TEST')=='1','real Vulkan support acceptance is opt-in')
class SupportVulkan(unittest.TestCase):
    def test_complete_validated_support_case(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build',prefix='support-vulkan-') as tmp:
            archive=Path.home()/'megascene-support-test-archive'
            output=Path(tmp)/'attempt'
            run=subprocess.run([sys.executable,str(ROOT/'scripts/megascene.py'),'--case','support','--threads','6',
                '--archive',str(archive),'--output',str(output)],cwd=ROOT,capture_output=True,text=True,timeout=900)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            s=json.loads((output/'summary.json').read_text())
            self.assertEqual(s['state_correctness']['status'],'pass');self.assertEqual(s['schedule_completion']['status'],'pass')
            self.assertEqual(len(s['moving_window']['frames']),12);self.assertEqual(s['edit_response']['status'],'inconclusive')

if __name__=='__main__':unittest.main()
