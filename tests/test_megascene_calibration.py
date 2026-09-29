"""Synthetic off-control report faults; real Vulkan comparisons are separate."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from megascene import snapshot
from megascene import configuration, parser
from megascene_calibration import off_result


def fixture():
    reference = [
        {'record_type':'frame','frame':'0','population':'startup','begin_ns':'0','end_ns':'10','duration_ns':'10'},
        {'record_type':'frame','frame':'1','population':'ordinary','begin_ns':'10','end_ns':'20','duration_ns':'10'},
    ]
    cpu = [
        {'record_type':'worker_start','frame':'0'},
        {'record_type':'checkpoint','frame':'0','time_ns':'5','names':['initialization','review_opening'],
         'sha256':'a','body_sha256':{'1':'b'}},
        {'record_type':'checkpoint','frame':'1','time_ns':'25','names':['completion'],
         'sha256':'c','body_sha256':{'1':'d'}},
        {'record_type':'complete','frame':'2'},
    ]
    validation = {'status':'pass','checked_frames':'2','checkpoints':[
        {'name':'initialization','sha256':'a','body_sha256':{'1':'b'}},
        {'name':'completion','sha256':'c','body_sha256':{'1':'d'}}]}
    supervision = {'termination':{'cause':'normal_exit'},'errors':[],
                   'reference_records':'2','shared_committed_slots':'2','shared_header_records':'2',
                   'allocation_ledger':{'peak_bytes':'1'}}
    return reference,cpu,validation,supervision


class CalibrationOffEvidence(unittest.TestCase):
    def test_complete_control_requires_both_mode_validations(self):
        base = ['--case','static','--calibration','off','--output','build/calibration-fixture',
                '--archive','/home/aivv/calibration-fixture-archive']
        with self.assertRaisesRegex(ValueError,'prior opposite-mode validation'):
            configuration(parser().parse_args(base))
        self.assertTrue(configuration(parser().parse_args(base+['--validation-only']))['validation_only'])
        self.assertEqual(configuration(parser().parse_args(base+['--calibration-peer-validation',
            '/home/aivv/calibration-peer']))['calibration_mode'],'off')

    def classify(self, mutation=None):
        reference,cpu,validation,supervision = fixture()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            snapshot(root/'schedule.json', {'frames':[{'phase':'startup'},{'phase':'ordinary'}],
                                            'actions':[]})
            streams = {'reference.jsonl':reference,'resources.jsonl':[{'record_type':'host_sample'}],
                       'allocations.jsonl':[{'record_type':'allocate'}]}
            if mutation:
                mutation(root,streams,cpu,validation,supervision)
            with patch('megascene_calibration.read_stream',side_effect=lambda path,manifest:(streams[path.name],[])):
                return off_result({'schedule':'static-v1','profile':'full'},root,
                                  {'attempt_id':'fixture','synthetic':True},validation,supervision,cpu,[])

    def test_endpoint_agreement_has_explicit_transient_limit(self):
        result = self.classify()
        self.assertEqual(result['endpoint_agreement']['status'],'pass')
        self.assertEqual(result['state_correctness']['status'],'inconclusive')
        self.assertEqual(result['qualified_capacity']['status'],'inconclusive')
        self.assertEqual(result['interactive_pass']['status'],'inconclusive')
        self.assertEqual(set(result['disabled_evidence']),
                         {'intermediate_checkpoints','detailed_inventory_transitions','stage_timing','gpu_queries','ordinary_logging'})
        self.assertEqual(result['populations']['ordinary']['count'],'1')

    def test_worker_loss_overflow_and_missing_endpoint_invalidate_control(self):
        mutations = [
            lambda root,streams,cpu,val,sup: sup['termination'].update(cause='unexplained_crash'),
            lambda root,streams,cpu,val,sup: sup.update(shared_committed_slots='1'),
            lambda root,streams,cpu,val,sup: cpu.pop(2),
            lambda root,streams,cpu,val,sup: cpu.insert(2,{'record_type':'stage'}),
            lambda root,streams,cpu,val,sup: (root/'gpu.jsonl').write_text('unexpected'),
            lambda root,streams,cpu,val,sup: cpu[2].update(sha256='changed'),
            lambda root,streams,cpu,val,sup: streams.update(**{'resources.jsonl':[]}),
        ]
        for mutate in mutations:
            with self.subTest(mutation=str(mutate)):
                result = self.classify(mutate)
                self.assertNotEqual(result['endpoint_agreement']['status'],'pass')
                self.assertNotEqual(result['schedule_completion']['status'],'pass')


if __name__ == '__main__':
    unittest.main()
