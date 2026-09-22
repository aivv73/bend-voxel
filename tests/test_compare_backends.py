"""Protect comparison ordering and prevent invalid runs from looking valid."""
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from compare_backends import command, schedule, summarize


class ComparisonTests(unittest.TestCase):
    def test_pairs_are_adjacent_and_reverse_across_rounds(self):
        plan = schedule([1, 6, 12], 2)
        self.assertEqual(len(plan), 12)
        for i in range(0, len(plan), 2):
            a, b = plan[i:i+2]
            self.assertEqual(a['threads'], b['threads'])
            self.assertEqual(a['round'], b['round'])
            self.assertEqual({a['backend'], b['backend']}, {'cpu', 'cuda'})
        self.assertEqual([(r['threads'], r['backend']) for r in plan[:6]],
                         [(r['threads'], r['backend']) for r in reversed(plan[6:])])

    def test_backend_and_threads_are_explicit(self):
        for backend, flag in [('cpu', 'off'), ('cuda', 'on')]:
            self.assertEqual(command('voxel-demo', dict(backend=backend, threads=6))[1:],
                             ['--gpu', flag, '--threads', '6'])

    def test_invalid_run_cannot_be_hidden_by_aggregate(self):
        good = dict(backend='cpu', threads=1, workload_pass=True, instrumentation_pass=True,
                    frames={'p95_ms': 30}, cuts={'p95_ms': 80})
        bad = {**good, 'workload_pass': False, 'frames': {'p95_ms': None}}
        group = summarize([good, bad])[0]
        self.assertFalse(group['valid'])
        self.assertIsNone(group['median_frame_p95_ms'])
        self.assertEqual(group['frame_p95_ms'], [30, None])


if __name__ == '__main__':
    unittest.main()
