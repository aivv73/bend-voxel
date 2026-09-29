"""Deterministic control-matrix and exact calibration decision boundaries."""
from fractions import Fraction
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from megascene_calibration_series import ORDER, assess, classify_statistic, plan, run_series, scope
from megascene import snapshot
from megascene_inventory import SCHEMA, read_json


def controls(off=(100,100,100), on=(100,100,100), sufficient=True):
    # Adjacent pair order is off/on, on/off, off/on.
    values = (off[0],on[0],on[1],off[1],off[2],on[2])
    return [{"mode": mode, "attempt_id": str(i), "sufficient": sufficient,
             "ordinary_count": 3480, "accepted_edit_count": 120,
             "measured_duration_ns": 10_000_000_000,
             "statistics": {"ordinary_mean": float(value)},
             "exact_statistics": {"ordinary_mean": [value.numerator,value.denominator]}}
            for i,(mode,value) in enumerate(zip(ORDER,map(Fraction,values)))]


class CalibrationSeries(unittest.TestCase):
    def test_exact_matrix(self):
        value = plan()
        self.assertEqual((value['configuration_count'],value['control_count']), (12,72))
        self.assertEqual(value['pairs'], [[0,1],[2,3],[4,5]])
        self.assertEqual({(c['case'],c['preset'],c['threads']) for c in value['configurations']},
                         {(case,preset,threads) for case in ('static','history')
                          for preset in ('small','large') for threads in ('1','6','12')})
        self.assertTrue(all(c['resolution']=='1920x1080' and c['profile']=='full' and
                            c['order']==list(ORDER) for c in value['configurations']))

    def test_exact_five_percent_boundaries_pass(self):
        result = classify_statistic('ordinary_mean', controls(
            off=(Fraction(100),Fraction(105),Fraction(100)),
            on=(Fraction(105),Fraction(441,4),Fraction(105))))
        self.assertEqual(result['status'],'pass')
        self.assertEqual(result['off_variation'],0.05)

    def test_noise_is_inconclusive_even_when_pairs_are_fast(self):
        result = classify_statistic('ordinary_mean', controls(off=(100,106,100),on=(100,106,100)))
        self.assertEqual(result['status'],'noisy')
        self.assertEqual(len(result['observations']),6)

    def test_one_failed_pair_is_not_averaged_away(self):
        result = classify_statistic('ordinary_mean', controls(on=(100,106,100)))
        self.assertEqual(result['status'],'failed')
        self.assertEqual(result['max_paired_on_over_off'],1.06)

    def test_zero_denominator_and_missing_population_are_insufficient(self):
        self.assertEqual(classify_statistic('ordinary_mean',controls(off=(100,0,100)))['status'],
                         'insufficient')
        self.assertEqual(classify_statistic('ordinary_mean',controls(sufficient=False))['status'],
                         'insufficient')

    def test_missing_validation_cannot_pass_and_scope_is_exact(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'series.json'
            value = {"schema":SCHEMA,"record_type":"calibration_series",
                     "scope":scope(plan()['configurations'][0]),
                     "order":list(ORDER),"validations":{},"controls":[]}
            snapshot(path,value)
            result = assess(path)
            self.assertEqual(result['status'],'insufficient')
            self.assertIn('validation',result['reason'])
            value['scope']['resolution'] = '640x360'
            snapshot(path,value)
            with self.assertRaisesRegex(ValueError,'outside accepted calibration matrix'):
                assess(path)

    def test_failed_control_is_preserved_without_automatic_retry(self):
        with tempfile.TemporaryDirectory() as folder:
            archive,work = Path(folder)/'archive',Path(folder)/'work'
            path = archive/'calibration-series'/'static-small-6'/'series.json'
            path.parent.mkdir(parents=True)
            value = {"schema":SCHEMA,"record_type":"calibration_series",
                     "scope":scope(plan()['configurations'][1]),
                     "order":list(ORDER),"validations":{},
                     "controls":[{"kind":"control","mode":"off","archive":None,
                                  "output":"failed","returncode":2}],
                     "runs":[{"kind":"control","mode":"off","archive":None,
                              "output":"failed","returncode":2}],
                     "archive_root":str(archive),"work_root":str(work)}
            snapshot(path,value)
            with self.assertRaisesRegex(ValueError,'without automatic rerun'):
                run_series(archive,work,'static','small',6)
            self.assertEqual(len(read_json(path.read_text())['controls']),1)

    def test_incomplete_series_requires_declared_resume_allowance(self):
        with tempfile.TemporaryDirectory() as folder:
            archive,work = Path(folder)/'archive',Path(folder)/'work'
            path = archive/'calibration-series'/'static-small-6'/'series.json'
            path.parent.mkdir(parents=True)
            snapshot(path,{"schema":SCHEMA,"record_type":"calibration_series",
                           "scope":scope(plan()['configurations'][1]),"order":list(ORDER),
                           "validations":{},"controls":[],"runs":[],
                           "archive_root":str(archive),"work_root":str(work)})
            with self.assertRaisesRegex(ValueError,'requires --additional-allowance'):
                run_series(archive,work,'static','small',6)


if __name__ == '__main__':
    unittest.main()
