"""Frozen supplementary transport and before-native admission boundaries."""
import copy
import struct
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from megascene_supplementary import camera_bytes
from megascene_proxy import owners, schedule
from megascene_scale import admit_schedule
from megascene_recipe import bits

CONFIG = dict(case='traversal', diagnostic='compact-reference', preset='small',
              seed='45', threads='6', profile='proxy', warmup='120', frames='3600', resolution='1920x1080')

class SupplementaryAdmission(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.frozen = schedule(CONFIG, owners(CONFIG))

    def test_camera_transport_preserves_frame_and_null_action(self):
        view = self.frozen['supplementary_views'][0]
        words = struct.unpack('<7I', camera_bytes([view]))
        self.assertEqual(words[:2], (int(view['frame']), 0xffffffff))
        self.assertEqual(words[2:], tuple(int(x,16) for x in
            (*view['camera']['eye_m'], view['camera']['yaw'], view['camera']['pitch'])))
        with self.assertRaises(ValueError): camera_bytes([view, view])

    def test_camera_rejected_before_native_replay(self):
        frozen = copy.deepcopy(self.frozen)
        frozen['supplementary_views'][0]['camera']['eye_m'][0] = bits(4096)
        with self.assertRaisesRegex(ValueError, 'supplementary camera'):
            admit_schedule(CONFIG, frozen)

    def test_coverage_cannot_bind_a_different_frame_or_feature(self):
        admit_schedule(CONFIG, self.frozen)
        for key, value in [('frame','1'), ('features',['invented feature'])]:
            frozen = copy.deepcopy(self.frozen)
            frozen['supplementary_views'][0][key] = value
            with self.assertRaises(ValueError): admit_schedule(CONFIG, frozen)

class SupplementaryReviewScope(unittest.TestCase):
    def test_approved_coverage_and_rejection_of_wrong_frame_or_purpose(self):
        import tempfile
        import hashlib
        import json
        from test_megascene_traversal import ReviewClassification
        from megascene import snapshot
        from megascene_review import assess
        for case, diagnostic, purpose, feature in (
            ('history',None,'history_face','new exposed surfaces'),
            ('traversal','mixed-world','proxy_shadow','major shadows'),
            ('picking','compact-reference','proxy_shadow','major shadows')):
            for mutation in (None,'frame','purpose','feature'):
                with self.subTest(case=case,diagnostic=diagnostic,mutation=mutation), tempfile.TemporaryDirectory() as folder:
                    root,path,_=ReviewClassification().bundle(folder,'correct','insufficient','Original view is occluded.')
                    def read(name): return json.loads((root/name).read_text())
                    selected='building silhouettes' if mutation=='feature' else feature
                    manifest=read('manifest.json');manifest['effective'].update(case=case,diagnostic=diagnostic)
                    snapshot(root/'manifest.json',manifest)
                    plan=dict(name='extra',frame='121',purpose='unsupported' if mutation=='purpose' else purpose)
                    frozen=dict(schedule_id='history-v1' if case=='history' else f'proxy-{diagnostic}-{case}-v1',supplementary_views=[plan])
                    snapshot(root/'schedule.json',frozen)
                    review=read('review.json');review['schedule_sha256']=hashlib.sha256((root/'schedule.json').read_bytes()).hexdigest()
                    original=review['views'][0];original['frame']='121';original['features'][0].update(name=selected,covered_by='extra')
                    detail=copy.deepcopy(original);detail.update(name='extra',supplementary_to='opening',frame='122' if mutation=='frame' else '121');detail['features'][0].pop('covered_by');review['views'].append(detail)
                    snapshot(root/'review.json',review)
                    answers=read('assessments-input.json') if (root/'assessments-input.json').exists() else json.loads(path.read_text())
                    original_answer=answers['views']['opening'].pop('building silhouettes');answers['views']['opening'][selected]=original_answer
                    answers['views']['extra']={selected:dict(geometry='correct',readability='readable')};snapshot(path,answers)
                    if mutation:
                        with self.assertRaises(ValueError): assess(root,path,'synthetic fixture reviewer')
                    else:
                        self.assertEqual(assess(root,path,'synthetic fixture reviewer'),'pass')
                        retained=read('review.json')['views'][0]['features'][0]
                        self.assertEqual(retained['readability'],'insufficient')
