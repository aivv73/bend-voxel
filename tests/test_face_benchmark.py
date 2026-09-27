"""Validate the per-exhibit face profile report parser."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from benchmark_faces import parse_rows


def rows():
    return '\n'.join('face_build,' + ','.join(map(str, (
        i, i + 7, 1, 100, 200, 300, 50, 400, 2, 12, 30, 6, 4, 2, 8, 8)))
        for i in range(6))


class FaceBenchmarkTests(unittest.TestCase):
    def test_six_cuts_are_mapped_to_exhibits(self):
        cuts = parse_rows(rows().replace(',12,30,6,4,2,8,8', ',12,30,6,4,2,8,9'))
        self.assertEqual([(c['exhibit'], c['cut_number']) for c in cuts],
                         [('Suzanne', 1), ('Oculus', 1), ('Twist', 1),
                          ('Suzanne', 2), ('Oculus', 2), ('Twist', 2)])
        self.assertEqual(cuts[0]['surface_ms'], 0.3)

    def test_missing_or_inconsistent_samples_fail(self):
        for data in (rows().rsplit('\n', 1)[0],
                     rows().replace('face_build,1,8', 'face_build,0,8'),
                     rows().replace(',12,30,6,4,2,8,8', ',12,30,6,4,2,8,0'),
                     rows().replace(',12,30,6,4,2,8,8', ',12,30,6,1,2,8,8')):
            with self.subTest(data=data[:40]), self.assertRaises(ValueError):
                parse_rows(data)


if __name__ == '__main__':
    unittest.main()
