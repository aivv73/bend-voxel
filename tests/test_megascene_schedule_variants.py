"""Shortened schedules, required-action gates and actual compact Bend references."""
import copy
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from megascene import configuration,parser
from megascene_history import schedule as history_schedule,audit_actions as history_actions
from megascene_support import schedule as support_schedule,audit_actions as support_actions
from megascene_support_references import program as support_program,check as support_check
from megascene_static import report
from test_megascene_history import action_records


BASE={'preset':'small','side_m':'64','seed':'45','threads':'6','fragment_budget':'2048',
      'resolution':'1920x1080','profile':'full','warmup':'120','frames':'3600'}


class VariantSchedules(unittest.TestCase):
    def test_history_camera_is_full_route_with_only_required_prefix_cuts(self):
        baseline=history_schedule({**BASE,'case':'history','schedule':'history-v1'})
        for count in (12,48):
            frozen=history_schedule({**BASE,'case':'history','schedule':f'history-{count}-v1'})
            self.assertEqual(frozen['actions'],baseline['actions'][:count])
            self.assertEqual([f['camera'] for f in frozen['frames']],
                             [f['camera'] for f in baseline['frames']])
            self.assertEqual(len(frozen['frames']),3721)
            self.assertEqual([f['actions'] for f in frozen['frames'][121:]],
                             [f['actions'] if i<count*12 else []
                              for i,f in enumerate(baseline['frames'][121:])])
            self.assertEqual(frozen['variant']['omitted_actions']['count'],str(120-count))
            self.assertEqual([p['name'] for p in frozen['required_checkpoints'] if p['name'].startswith('after_cut_')],
                             ['after_cut_12']+(['after_cut_48'] if count==48 else []))
            rows=action_records(frozen)
            self.assertEqual(history_actions(rows,frozen)['accepted_edits'],str(count))
            with self.assertRaises(ValueError):history_actions(rows[:-7],frozen)

    def test_support_prefix_and_motion_requirements(self):
        baseline=support_schedule({**BASE,'case':'support','schedule':'support-v1'})
        for spans in (1,2):
            frozen=support_schedule({**BASE,'case':'support','schedule':f'support-{spans}-span-v1'})
            self.assertEqual(frozen['actions'],baseline['actions'][:2*spans])
            self.assertEqual([f['camera'] for f in frozen['frames']],
                             [f['camera'] for f in baseline['frames']])
            self.assertEqual(frozen['moving_window']['distinct_spans'],str(spans))
            self.assertEqual([f['phase'] for f in frozen['frames'][152:164]],['motion']*12)
            self.assertEqual(len(frozen['supplementary_views']),2*spans)
            self.assertEqual(frozen['variant']['omitted_actions']['count'],str(6-2*spans))
            rows=action_records(frozen)
            self.assertEqual(support_actions(rows,frozen)['accepted_edits'],str(2*spans))
            damaged=copy.deepcopy(rows)
            next(r for r in damaged if r['record_type']=='action' and r['action']==str(2*spans-1))['accepted']=False
            with self.assertRaises(ValueError):support_actions(damaged,frozen)

    def test_variant_admission_keeps_baseline_identity_separate(self):
        base=['--output','build/variant-test','--archive','/home/aivv/variant-test-archive']
        for case,schedules in (('history',('history-12-v1','history-48-v1')),
                               ('support',('support-1-span-v1','support-2-span-v1'))):
            for schedule in schedules:
                c=configuration(parser().parse_args(base+['--case',case,'--schedule',schedule]))
                self.assertEqual(c['schedule_kind'],'declared_control')
                for extra in (['--frames','3599'],['--diagnostic','fill'],['--seed','46'],
                              ['--resolution','640x360'],['--threads','12']):
                    with self.assertRaises(ValueError):
                        configuration(parser().parse_args(base+['--case',case,'--schedule',schedule]+extra))

    def test_existing_support_reference_keeps_its_fixed_fixture(self):
        baseline=support_program()
        self.assertEqual(support_program({**BASE,'case':'support','schedule':'support-v1',
                                          'preset':'large','side_m':'128','seed':'46'}),baseline)
        self.assertEqual(support_program({**BASE,'case':'support','schedule':'fill-support-v1',
                                          'control':'fill'}),baseline)

    def test_synthetic_incomplete_evidence_never_completes_baseline(self):
        for case,schedule in (('history','history-12-v1'),('history','history-48-v1'),
                              ('support','support-1-span-v1'),('support','support-2-span-v1')):
            config={**BASE,'case':case,'schedule':schedule,'schedule_kind':'declared_control'}
            frozen=(history_schedule if case=='history' else support_schedule)(config)
            result=report(action_records(frozen),[],config,0,'normal_exit',0,'synthetic')
            self.assertEqual(result['schedule_completion']['status'],'inconclusive')
            self.assertEqual(result['baseline_schedule_completion']['status'],'not_applicable')
            self.assertEqual(result['accepted_edits']['count'],str(len(frozen['actions'])))
            self.assertIn('fewer than 100',result['edit_response']['reason'])


class ActualBendPrefixReference(unittest.TestCase):
    @unittest.skipUnless(shutil.which('bend'),'Bend compiler unavailable')
    def test_one_and_two_released_spans_against_dense_reference(self):
        for spans in (1,2):
            config={**BASE,'case':'support','schedule':f'support-{spans}-span-v1'}
            with tempfile.TemporaryDirectory() as folder:
                root=Path(folder)
                shutil.copytree(ROOT/'src',root/'src')
                (root/'src/megascene_support_reference_entry.bend').write_text(support_program(config))
                subprocess.run(['bend','src/megascene_support_reference_entry.bend','-o','worker'],cwd=root,
                               check=True,capture_output=True,timeout=120)
                result=subprocess.run([str(root/'worker'),'--gpu','off','--threads','6'],cwd=root,
                                      capture_output=True,text=True,check=True,timeout=30)
                checked=support_check(result.stdout,config)
                self.assertEqual(checked['status'],'pass')
                self.assertEqual(len(checked['released']),spans)


if __name__=='__main__': unittest.main()
