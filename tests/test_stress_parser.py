"""Check stress workload and timing validation."""
import io
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from stress_parser import parse_stress


ROWS = '''init,4,500000
surface,1200
frame,1000,1000,5400,0
stage,1000,0,0,0,0,0,0,1000,0
vulkan_stage,0,0,0,0,0,0,0,0,1000,0
frame,2500,1500,5380,0
stage,2500,100,100,100,0,0,0,1100,100
vulkan_stage,1,100,100,100,100,100,100,100,200,100
edit,2500,1000,200,1,100,100,100,0
cut,1000,1500,1,200
'''


class StressParserTests(unittest.TestCase):
    def parse(self, rows=ROWS):
        return parse_stress(io.StringIO(rows), 0, 1, 1, 1)

    def test_measured_frame_and_edit(self):
        result = self.parse()
        self.assertTrue(result['pass'], result['errors'])
        self.assertEqual(result['solid_cells_start'], 5400)
        self.assertEqual(result['throughput_fps'], 1_000_000 / 1500)
        self.assertEqual(result['edits'], 1)
        self.assertEqual(result['acquire_wait_fraction'], 100 / 1500)

    def test_missing_rows_or_edits_fail(self):
        for rows in (ROWS.replace('surface,1200\n', ''),
                     ROWS.replace('cut,1000,1500,1,200\n', ''),
                     ROWS.replace('frame,2500,1500,5380,0\n', '')):
            self.assertFalse(self.parse(rows)['pass'])


if __name__ == '__main__':
    unittest.main()
