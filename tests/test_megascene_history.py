"""Frozen history admission, synthetic action gates and actual compact Bend replay."""
import copy
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from megascene import configuration, parser
from megascene_history import schedule, audit_actions, CUT_FRAMES, NAMED
from megascene_history_references import program, check
from megascene_picking import value
from megascene_support import motion
from megascene_recipe import f32


CONFIG=dict(case='history',preset='small',side_m='64',seed='45',threads='6',fragment_budget='2048',
            resolution='640x360',profile='full',warmup='120',frames='3600',schedule='history-v1',schedule_kind='accepted')


def action_records(frozen):
    """Synthetic records exercise reporting gates, never runtime correctness."""
    rows=[]
    for action in frozen['actions']:
        frame=action['frame'];number=action['action'];start=10**12+int(frame)*1000
        outcome={k:action[k] for k in ('action','frame','target_m')} | {
            'accepted':True,'outcome':'accepted','removed_cells':action['expected_removed_cells']}
        rows += [{'record_type':'frame','frame':frame,'begin_ns':str(start),'end_ns':str(start+100)},
                 {'record_type':'edit_begin','frame':frame,'action':number,'begin_ns':str(start+10)},
                 {'record_type':'action','frame':frame,'action':number,'accepted':True,
                  'removed_cells':action['expected_removed_cells'],'outcome':outcome},
                 {'record_type':'edit','frame':frame,'action':number,'accepted':True,
                  'removed_cells':action['expected_removed_cells'],'begin_ns':str(start+10),
                  'end_ns':str(start+100),'duration_ns':'90'}]
        for i,name in enumerate(('physics','carve','connectivity','surfaces','commit','view')):
            rows.append({'record_type':'stage','frame':frame,'stage':name,
                         'begin_ns':str(start+10*i),'end_ns':str(start+10*i+5)})
    return rows


class HistorySchedule(unittest.TestCase):
    def test_all_presets_seeds_exact_targets_populations_and_revisits(self):
        for preset,side,total in (('small','64',2440),('large','128',2472)):
            for seed in ('45','46'):
                frozen=schedule({**CONFIG,'preset':preset,'side_m':side,'seed':seed})
                self.assertEqual(len(frozen['actions']),120)
                self.assertEqual(tuple(int(a['frame']) for a in frozen['actions']),CUT_FRAMES)
                self.assertEqual(sum(int(a['expected_removed_cells']) for a in frozen['actions']),total)
                self.assertTrue(all(int(a['expected_removed_cells'])>0 for a in frozen['actions']))
                self.assertEqual([frozen['frames'][i]['phase'] for i in CUT_FRAMES],['edit']*120)
                self.assertEqual([p['frame'] for p in frozen['required_checkpoints'] if p['name'].startswith('after_cut_')],
                                 [str(frame) for _,frame in NAMED])
                self.assertEqual(frozen['frames'][1681]['camera'],frozen['frames'][3720]['camera'])
                # A revisit enters old damage but must still remove fresh material.
                first={tuple(map(int,p[:3])) for p in frozen['actions'][0]['reference_removed_cells']}
                revisit=frozen['actions'][3]
                target=[f32(value(x)*10) for x in revisit['target_m']]
                self.assertTrue(any(sum((x+.5-t)**2 for x,t in zip(p,target))<=4.00001 for p in first))
                self.assertLess(int(revisit['expected_removed_cells']),int(frozen['actions'][0]['expected_removed_cells']))
                q=2 if preset=='small' else 4
                n=(int(seed)-45)%(q*q)
                variation=(3*(n%q)+5*(n//q)+int(seed)-45)%4
                self.assertEqual(value(frozen['actions'][5]['target_m'][1]),
                                 f32(f32((74+variation)*f32(.1))+value(motion(12,42)[0])))

    def test_explicit_admission_and_rejection(self):
        base=['--case','history','--output','build/history-test','--archive','/home/aivv/history-test-archive']
        self.assertEqual(configuration(parser().parse_args(base))['schedule'],'history-v1')
        for options in (['--frames','1'],['--warmup','0'],['--schedule','support-v1'],
                        ['--profile','proxy'],['--capture-opening']):
            with self.assertRaises(ValueError):configuration(parser().parse_args(base+options))

    def test_synthetic_action_intervals_and_rejection_gate(self):
        frozen=schedule(CONFIG)
        rows=action_records(frozen)
        self.assertEqual(audit_actions(rows,frozen)['accepted_edits'],'120')
        for mutation in ('missing','rejected','noop','wrong_target','short_interval'):
            changed=copy.deepcopy(rows)
            action=next(r for r in changed if r['record_type']=='action' and r['action']=='105')
            if mutation=='missing': changed.remove(action)
            elif mutation in ('rejected','noop'):
                action['accepted']=False;action['removed_cells']='0'
                action['outcome'].update(accepted=False,removed_cells='0',outcome='rejected_budget' if mutation=='rejected' else 'no_op')
            elif mutation=='wrong_target': action['outcome']['target_m']=['0x00000000']*3
            else: next(r for r in changed if r['record_type']=='edit' and r['action']=='105')['duration_ns']='1'
            with self.assertRaises(ValueError,msg=mutation):audit_actions(changed,frozen)


class FocusedBendReference(unittest.TestCase):
    @unittest.skipUnless(shutil.which('bend'),'Bend compiler unavailable')
    def test_moved_beam_and_overlapping_revisit(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            shutil.copytree(ROOT/'src',root/'src')
            (root/'src/megascene_history_reference_entry.bend').write_text(program())
            subprocess.run(['bend','src/megascene_history_reference_entry.bend','-o','worker'],cwd=root,check=True,
                           capture_output=True,timeout=120)
            result=subprocess.run([str(root/'worker'),'--gpu','off','--threads','6'],cwd=root,
                                  capture_output=True,text=True,check=True,timeout=30)
            report=check(result.stdout)
            self.assertEqual(report['status'],'pass')
            self.assertEqual([a['frame'] for a in report['actions']],['1','2','3','4','16'])
            damaged=result.stdout.replace('"removed":"28"','"removed":"27"',1)
            with self.assertRaises(ValueError):check(damaged)


if __name__=='__main__':unittest.main()
