"""Check Vulkan replay sample retention and accounting."""
import io
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from benchmark_parser import parse_run


class SampleTests(unittest.TestCase):
    def rows(self):
        return ('frame,4999000,4999000,4640,0\n'
                'stage,4999000,0,0,0,0,0,0,4999000,0\n'
                'frame,5000000,1000,4622,1\n'
                'stage,5000000,100,100,90,10,0,100,500,100\n'
                'edit,5000000,4294967200,101,1,100,100,90,10\n'
                'cut,4294967200,900,1,101\n'
                'frame,65300000,60300000,4622,1\n'
                'stage,65300000,0,0,0,0,0,0,60300000,0\n')

    def detailed_rows(self):
        return self.rows() + (
            'vulkan_stage,0,0,0,0,0,0,0,0,4999000,0\n'
            'vulkan_stage,1,100,100,50,50,50,50,50,20,20\n'
            'vulkan_stage,2,0,0,0,0,0,0,0,60300000,0\n')

    def test_retains_warmup_and_slow_final_frame(self):
        r = parse_run(io.StringIO(self.rows()))
        self.assertTrue(r['instrumentation_pass'])
        self.assertEqual(r['raw_frame_samples'], 3)
        self.assertEqual(r['warmup_frame_samples'], 1)
        self.assertEqual(r['frames']['samples'], 2)
        self.assertEqual(r['frames']['max_ms'], 60300)
        self.assertTrue(r['complete_window'])
        self.assertEqual(r['active_edits']['carving']['samples'], 1)
        self.assertEqual(r['active_edits']['surface_generation']['total_ms'], 0.09)

    def test_missing_or_corrupt_stage_fails(self):
        for bad in (self.rows().replace('stage,5000000,100,100,90,10,0,100,500,100\n',''),
                    self.rows().replace(',500,100\n', ',500,101\n'),
                    self.rows().replace('101,1,100,100,90,10', '101,1,100,100,91,10')):
            self.assertFalse(parse_run(io.StringIO(bad))['instrumentation_pass'])

    def test_multiple_edits_per_frame(self):
        rows = self.rows().replace('edit,5000000,4294967200,101,1,100,100,90,10',
            'edit,5000000,4294967200,101,1,40,40,35,5\nedit,5000000,42,102,1,60,60,55,5\ncut,42,800,1,102')
        r = parse_run(io.StringIO(rows))
        self.assertTrue(r['instrumentation_pass'])
        self.assertEqual(r['active_edits']['carving']['samples'], 2)
        self.assertEqual(r['active_edits']['surface_generation']['samples'], 2)

    def test_duplicate_or_orphan_samples_fail(self):
        for extra in ('frame,5000000,1000,4622,1\n', 'edit,7,9,101,1,0,0,0,0\n', 'cut,42,800,1,102\n'):
            self.assertFalse(parse_run(io.StringIO(self.rows()+extra))['instrumentation_pass'])

    def test_vulkan_detail_is_joined_to_frames(self):
        r = parse_run(io.StringIO(self.detailed_rows()), require_vulkan_detail=True)
        self.assertTrue(r['instrumentation_pass'])
        self.assertEqual(r['vulkan_stages']['geometry_generation']['total_ms'], 0.1)
        self.assertEqual(r['vulkan_stages']['bend_effect_overhead']['total_ms'], 0.01)

    def test_missing_or_oversized_vulkan_detail_fails(self):
        rows = self.detailed_rows()
        for bad in (rows.replace('vulkan_stage,1,100,100,50,50,50,50,50,20,20\n', ''),
                    rows.replace('vulkan_stage,1,100,100', 'vulkan_stage,1,100,120'),
                    rows + 'vulkan_stage,1,100,100,50,50,50,50,50,20,20\n'):
            self.assertFalse(parse_run(io.StringIO(bad), require_vulkan_detail=True)['instrumentation_pass'])
        self.assertFalse(parse_run(io.StringIO(self.rows()), require_vulkan_detail=True)['instrumentation_pass'])


if __name__ == '__main__':
    unittest.main()
