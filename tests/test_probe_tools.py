"""Check sample retention/accounting and the official quadtree wire format."""
import io
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from benchmark import parse_run
from snapshot import decode_tree, png


class SampleTests(unittest.TestCase):
    def rows(self):
        return ('frame,4999000,4999000,4640,0\n'
                'stage,4999000,0,0,0,0,0,0,0,0,4999000,0\n'
                'frame,5000000,1000,4622,1\n'
                'stage,5000000,100,100,90,10,0,100,100,0,400,100\n'
                'edit,5000000,4294967200,101,1,100,100,90,10\n'
                'cut,4294967200,900,1,101\n'
                'frame,65300000,60300000,4622,1\n'
                'stage,65300000,0,0,0,0,0,0,60000000,0,300000,0\n')

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
        for bad in (self.rows().replace('stage,5000000,100,100,90,10,0,100,100,0,400,100\n',''),
                    self.rows().replace(',400,100\n', ',400,101\n'),
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


class SnapshotTests(unittest.TestCase):
    def test_quadrant_order_and_crop(self):
        pixels = decode_tree(['Q','16711680','65280','255','16777215'], 3, 3, 4)
        red, green, blue, white = b'\xff\0\0', b'\0\xff\0', b'\0\0\xff', b'\xff\xff\xff'
        self.assertEqual(pixels, (red*2+green)*2+blue*2+white)
        self.assertTrue(png(pixels,3,3).startswith(b'\x89PNG\r\n\x1a\n'))

    def test_solid_compressed_root(self):
        self.assertEqual(decode_tree(['66051'],2,1,4),b'\x01\x02\x03'*2)

    def test_malformed_trees_rejected(self):
        for tree in (['Q','0'], ['0','0'], ['16777216'], ['-1'], ['Q','Q']):
            with self.assertRaises(ValueError):
                decode_tree(tree,2,2,2)


if __name__ == '__main__':
    unittest.main()
