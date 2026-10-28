#!/usr/bin/env python3
import argparse
from collections import deque
from contextlib import nullcontext
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def make_run(side='candidate', workload='edits', pair=0):
    return subject.Run(f'{side}-{workload}-{pair}', side, 'test', workload, pair,
                       ['/native'], ['/native'], 'binary-hash', '/unused/log', {}, {})


def state(frame=10, revision=0, **extra):
    return dict(rows=32, frame=frame, generation=1, revision=revision,
                installed=revision, uploads=2 + 2 * revision, quads=100,
                width=640, height=480, mapped=1, captured=0,
                camera='1,2,3,4,5', **extra)


def line(values):
    return 'STATE ' + ' '.join(f'{key}={value}' for key, value in values.items()) + '\n'


class FakeInput:
    def button(self, *_):
        pass

    def key(self, *_):
        pass


class ScriptedTrace:
    def __init__(self, run, batches):
        self.batches = deque(batches)
        self.stream = io.BytesIO()
        self.trace = subject.Trace(run, self.stream)

    def poll(self):
        if self.batches:
            position = self.stream.tell()
            self.stream.seek(0, io.SEEK_END)
            self.stream.write(''.join(line(s) for s in self.batches.popleft()).encode())
            self.stream.seek(position)
        return self.trace.poll()


def edit_driver(batches, side='candidate', provenance=None):
    run = make_run(side)
    run.legacy_completion_provenance = provenance
    trace = ScriptedTrace(run, [[state()], *batches])
    previous = trace.poll()
    process = SimpleNamespace(poll=lambda: None)
    args = SimpleNamespace(timeout=0.05, poll_ms=0.01)
    driver = subject.WindowRun(run, FakeInput(), process, trace, SCRATCH, args)
    return driver, run, previous


def static_image(label, values, rgb_hash):
    return dict(label=label, state=dict(values=values), attempts=[dict(
        passed=True, nonblank=True,
        signature=dict(width=640, height=480, rgb_sha256=rgb_hash))])


def paired_runs(workload='edits', pairs=1):
    runs = []
    for pair in range(pairs):
        for side in ('baseline', 'candidate'):
            run = make_run(side, workload, pair)
            run.ended_utc = '2026-10-17T00:00:00+00:00'
            if workload == 'flight':
                run.metrics['completed_frames_per_second'] = 20
                run.images = [static_image('flight-initial', state(), 'intact'),
                              static_image('flight-final', state(frame=50), side)]
            else:
                run.metrics.update(cut_observed_latency_ms=dict(median=10),
                                   reset_observed_latency_ms=dict(median=20))
                run.images = [static_image('edit-original', state(), 'intact')]
                for action, revision, quads, rgb in [('cut', 1, 90, 'cut'),
                                                      ('reset', 2, 100, 'intact')]:
                    values = state(frame=10 + revision, revision=revision)
                    values['quads'] = quads
                    run.images.append(static_image(f'edit-00-{action}', values, rgb))
                    run.edit_latencies.append(dict(action=action, cycle=0,
                                                   completed=True, warmup=False))
            runs.append(run)
    return runs


class CompletionTests(unittest.TestCase):
    def test_stale_untagged_overlap_cannot_complete(self):
        driver, run, before = edit_driver([[state(frame=10, revision=1)],
                                          [state(frame=11, revision=1)]])
        with self.assertRaises(TimeoutError):
            driver.edit('cut', before, 0, False)
        self.assertEqual(run.edit_latencies[0]['completed'], False)

    def test_first_installed_tagged_record_is_completion(self):
        driver, run, before = edit_driver([
            [state(frame=11, revision=1, completed_revision=1, presented_revision=1)],
            [state(frame=12, revision=1, completed_revision=1, presented_revision=1)]])
        end = driver.edit('cut', before, 0, False)
        self.assertEqual(end['line'], 2)
        self.assertEqual(run.edit_latencies[0]['completed'], True)
        self.assertEqual(run.edit_latencies[0]['completed_frame_increment'], 1)

    def test_buffered_first_tagged_completion_is_not_lost(self):
        driver, _, before = edit_driver([
            [state(frame=11, revision=1, completed_revision=1),
             state(frame=12, revision=1, completed_revision=2)],
            [state(frame=13, revision=1, completed_revision=2)]])
        self.assertEqual(driver.edit('cut', before, 0, False)['line'], 2)

    def test_completion_needs_frame_advance_from_before_edit(self):
        driver, run, before = edit_driver([
            [state(frame=10, revision=1, completed_revision=1)],
            [state(frame=11, revision=1, completed_revision=1)]])
        self.assertEqual(driver.edit('cut', before, 0, False)['values']['frame'], 11)
        self.assertEqual(run.edit_latencies[0]['completed'], True)

    def test_first_completion_keeps_raw_receipt_and_dispatch_timestamps(self):
        driver, run, before = edit_driver([
            [state(frame=11, revision=1, completed_revision=1)],
            [state(frame=12, revision=1, completed_revision=1)]])
        run.elapsed_ns = iter((1_000_000_000, 1_000_000_100,
                               1_000_000_200, 1_250_000_000,
                               1_300_000_000, 1_500_000_000)).__next__
        end = driver.edit('cut', before, 0, False)
        self.assertEqual(end['observed_ns'], 1_250_000_000)
        self.assertEqual(run.edit_latencies[0]['input_start_ns'], 1_000_000_000)
        self.assertEqual(run.edit_latencies[0]['input_dispatched_ns'], 1_000_000_100)
        self.assertEqual(run.edit_latencies[0]['observed_latency_ms'], 250.0)

    def test_future_and_sentinel_tags_do_not_complete(self):
        for tag in (2, 4294967295, 18446744073709551615):
            for name in ('completed_revision', 'presented_revision'):
                with self.subTest(tag=tag, name=name):
                    driver, run, before = edit_driver([
                        [state(frame=10, revision=1)],
                        [state(frame=11, revision=1, **{name: tag})]])
                    with self.assertRaises(TimeoutError):
                        driver.edit('cut', before, 0, False)
                    self.assertEqual(run.edit_latencies[0]['completed'], False)

    def test_conflicting_completion_tags_do_not_complete(self):
        driver, _, before = edit_driver([
            [state(frame=10, revision=1)],
            [state(frame=11, revision=1, completed_revision=1,
                   presented_revision=4294967295)]])
        with self.assertRaises(TimeoutError):
            driver.edit('cut', before, 0, False)

    def test_legacy_provenance_does_not_allow_candidate_fallback(self):
        driver, _, before = edit_driver([[state(frame=10, revision=1)],
                                        [state(frame=11, revision=1)]],
                                       provenance=dict(frames_in_flight=1))
        with self.assertRaises(TimeoutError):
            driver.edit('cut', before, 0, False)

    def test_unverified_baseline_cannot_use_untagged_fallback(self):
        driver, _, before = edit_driver([[state(frame=10, revision=1)],
                                        [state(frame=11, revision=1)]], side='baseline')
        with self.assertRaises(TimeoutError):
            driver.edit('cut', before, 0, False)

    def test_verified_single_frame_baseline_has_separate_fallback(self):
        provenance = dict(binary_sha256='93a9ef7f43e457323d08d2754d55e4e60fb97eb4ee7b1ced0a4fd4c0f9e52ec2',
                          source_commit='928bee9e677983c063811e0540f8783d86467a83',
                          frames_in_flight=1)
        driver, run, before = edit_driver([[state(frame=10, revision=1)],
                                          [state(frame=11, revision=1)]],
                                         side='baseline', provenance=provenance)
        self.assertEqual(driver.edit('cut', before, 0, False)['values']['frame'], 11)
        self.assertEqual(run.edit_latencies[0]['completed'], True)

    def test_verified_baseline_cannot_fall_back_from_future_tags(self):
        driver, _, before = edit_driver([
            [state(frame=10, revision=1)],
            [state(frame=11, revision=1, completed_revision=4294967295)]],
            side='baseline', provenance=dict(frames_in_flight=1))
        with self.assertRaises(TimeoutError):
            driver.edit('cut', before, 0, False)


class PairTests(unittest.TestCase):
    def test_matching_static_pairs_are_eligible(self):
        runs = paired_runs(pairs=5)
        result = subject.summarize(runs, 5)[0]
        self.assertEqual(result['successful_pairs'], 5)
        self.assertEqual(len(result['paired_samples']), 5)
        self.assertEqual(result['verdict'], 'inconclusive')

    def test_wrong_static_images_fail_before_metrics(self):
        for label in ('edit-original', 'edit-00-cut', 'edit-00-reset'):
            with self.subTest(label=label):
                runs = paired_runs(pairs=5)
                image = next(i for i in runs[1].images if i['label'] == label)
                image['attempts'][-1]['signature']['rgb_sha256'] = 'wrong-scene-or-cut'
                result = subject.summarize(runs, 5)[0]
                self.assertEqual(result['successful_pairs'], 4)
                self.assertEqual(len(result['paired_samples']), 4)
                self.assertEqual(result['failure_count'], 2)
                self.assertEqual(result['failed_runs'], 2)
                self.assertEqual(runs[0].errors[0]['kind'], 'pair_comparison')

    def test_wrong_static_geometry_or_view_fails(self):
        for label in ('edit-original', 'edit-00-cut', 'edit-00-reset'):
            for field, value in [('quads', 123), ('camera', '6,7,8,9,10'),
                                 ('width', 800), ('height', 600),
                                 ('mapped', 0), ('captured', 1)]:
                with self.subTest(label=label, field=field):
                    runs = paired_runs()
                    image = next(i for i in runs[1].images if i['label'] == label)
                    image['state']['values'][field] = value
                    result = subject.summarize(runs, 1, smoke=True)[0]
                    self.assertEqual(result['successful_pairs'], 0)
                    self.assertEqual(result['failure_count'], 2)

    def test_missing_static_capture_fails(self):
        runs = paired_runs()
        runs[1].images.pop()
        result = subject.summarize(runs, 1, smoke=True)[0]
        self.assertEqual(result['successful_pairs'], 0)
        self.assertEqual(result['failure_count'], 2)

    def test_time_driven_flight_final_need_not_match(self):
        runs = paired_runs('flight')
        runs[1].images[-1]['state']['values']['camera'] = '6,7,8,9,10'
        result = subject.summarize(runs, 1, smoke=True)[0]
        self.assertEqual(result['successful_pairs'], 1)
        self.assertEqual(result['failure_count'], 0)

    def test_flight_initial_static_mismatch_fails(self):
        runs = paired_runs('flight')
        runs[1].images[0]['attempts'][-1]['signature']['rgb_sha256'] = 'wrong-scene'
        result = subject.summarize(runs, 1, smoke=True)[0]
        self.assertEqual(result['successful_pairs'], 0)
        self.assertEqual(result['failure_count'], 2)

    def test_report_serializes_pair_failures_and_does_not_duplicate_them(self):
        runs = paired_runs()
        runs[1].images[1]['attempts'][-1]['signature']['rgb_sha256'] = 'wrong-cut'
        report = dict(mode='smoke', errors=[])
        path = SCRATCH / 'report.json'
        for _ in range(2):
            subject.write_report(path, report, runs, 1)
        actual = json.loads(path.read_text())
        self.assertEqual(actual['failure_count'], 2)
        self.assertEqual([run['passed'] for run in actual['runs']], [False, False])
        self.assertEqual(actual['summary'][0]['successful_pairs'], 0)

    def test_partial_pair_is_not_eligible(self):
        result = subject.summarize(paired_runs()[:1], 1, smoke=True)[0]
        self.assertEqual(result['successful_pairs'], 0)
        self.assertEqual(result['sides']['baseline']['cut_observed_latency_ms'], None)


class ProvenanceTests(unittest.TestCase):
    def test_main_enables_legacy_only_for_known_manifest_commit_and_baseline_side(self):
        for case in ('verified', 'wrong-hash', 'wrong-commit', 'missing-manifest',
                     'missing-commit', 'alternate-path'):
            with self.subTest(case=case):
                directory = SCRATCH / f'provenance-{case}'
                directory.mkdir(exist_ok=True)
                binary = directory / 'baseline-native'
                binary.write_bytes(b'Not a native executable. Never executed.\n')
                binary.chmod(0o700)
                sha256 = hashlib.sha256(binary.read_bytes()).hexdigest()
                commit = 'known-single-frame-fixture'
                trusted = dict(binary_sha256='different-hash' if case == 'wrong-hash' else sha256,
                               source_commit=commit)
                if case != 'missing-manifest':
                    (directory / 'milestone-7-baseline-window.sha256').write_text(sha256 + '\n')
                if case != 'missing-commit':
                    (directory / 'milestone-7-baseline-commit.txt').write_text(
                        'different-commit' if case == 'wrong-commit' else commit)
                captured = []

                def execute(run, *_):
                    captured.append(run)
                    run.errors.append(dict(kind='fixture', message='No native execution'))
                    run.ended_utc = '2026-10-17T00:00:00+00:00'
                    return run

                with (patch.object(subject, 'BUILD', directory),
                      patch.object(subject, 'BASELINE', directory / 'other-native'
                                   if case == 'alternate-path' else binary),
                      patch.object(subject, 'SINGLE_FRAME_BASELINE', trusted, create=True),
                      patch.object(subject, 'isolated_display', lambda _: nullcontext()),
                      patch.object(subject, 'execute_run', execute),
                      patch.object(subject.shutil, 'which', return_value=sys.executable),
                      patch.object(subject.subprocess, 'run', return_value=SimpleNamespace(
                          returncode=0, stdout='', stderr='')),
                      patch.object(subject.os, 'sched_getaffinity', return_value={0}, create=True),
                      patch.object(subject.os, 'getloadavg', return_value=(0.0, 0.0, 0.0), create=True),
                      patch.object(sys, 'stdout', io.StringIO())):
                    result = subject.main(['--baseline', str(binary), '--candidate', str(binary),
                                           '--smoke', '--workload', 'flight',
                                           '--output', str(directory / 'report.json')])
                self.assertEqual(result, 1)
                self.assertEqual(len(captured), 2)
                provenance = getattr(captured[0], 'legacy_completion_provenance', None)
                self.assertEqual(provenance is not None, case == 'verified')
                if case == 'verified' and provenance is not None:
                    self.assertEqual(provenance['frames_in_flight'], 1)
                    self.assertEqual(provenance['binary_sha256'], sha256)
                self.assertIsNone(getattr(captured[1], 'legacy_completion_provenance', None))


class ResourceAndStageTests(unittest.TestCase):
    def test_missing_stage_data_remains_unavailable(self):
        result = subject.stage_timings(make_run())
        self.assertEqual({name: data['available'] for name, data in result.items()},
                         dict(cpu_meshing=False, upload=False, gpu_render=False,
                              presentation=False))
        self.assertEqual(result['gpu_render']['timestamp_capabilities']['available'], False)

    def test_resource_report_does_not_claim_unproven_plateau(self):
        run = make_run()
        initial = dict(values=state())
        args = SimpleNamespace(warmup_edits=1, edits=4, row_tolerance=8)
        driver = subject.WindowRun(run, FakeInput(), None, None, SCRATCH, args)
        driver.capture = lambda *_args, **_kwargs: 'image-signature'
        driver.settle = lambda record: record

        def edit(action, previous, cycle, warmup):
            values = state(frame=previous['values']['frame'] + 1,
                           revision=previous['values']['revision'] + 1)
            values['quads'] = 90 if action == 'cut' else 100
            values['rows'] = [32, 32, 34, 33, 34][cycle]
            run.edit_latencies.append(dict(action=action, completed=True, warmup=warmup,
                                           observed_latency_ms=10))
            return dict(values=values)

        driver.edit = edit
        driver.checkpoint = lambda label, _: run.resource_samples.append(
            dict(source='checkpoint', label=label, native_counts=None))
        driver.edits(initial)
        self.assertEqual(run.metrics['cut_observed_latency_ms']['count'], 4)
        descriptions = ' '.join(a['description'] for a in run.assertions)
        self.assertNotIn('stable plateau', descriptions)
        self.assertTrue(any('counters were absent' in text for text in run.measurement_limits))


class StageProtocolTests(unittest.TestCase):
    def test_exact_cpu_limbs_and_labels(self):
        run = make_run()
        run.diagnostics = [dict(observed_ns=7, line='producer', values=dict(
            cpu_scope='upload_prepare', ns_lo=0xffffffff, ns_hi=0xffffffff))]
        output = subject.stage_timings(run)['upload']['fields']['cpu_scope.upload_prepare_ns']
        self.assertEqual(output['samples'][0]['value'], (1 << 64) - 1)
        self.assertEqual(output['producer_scope'], 'upload_prepare')

    def test_finite_gpu_bits_and_capability(self):
        run = make_run()
        run.diagnostics = [dict(observed_ns=7, line='producer', values=dict(
            gpu_scope='shadow', ns_f32_bits=0x41800000,
            timestamp_valid_bits=36, timestamp_period_ns_f32_bits=0x3f800000,
            timestamp_supported=1))]
        output = subject.stage_timings(run)['gpu_render']
        self.assertEqual(output['fields']['gpu_scope.shadow_ns']['samples'][0]['value'], 16.0)
        self.assertEqual(output['timestamp_capabilities']['fields']['timestamp_period_ns'][0]['value'], 1.0)

    def test_invalid_protocol_values_are_unavailable(self):
        for values in (dict(cpu_scope='upload_prepare', ns_lo=-1, ns_hi=0),
                       dict(cpu_scope='upload_prepare', ns_lo=True, ns_hi=0),
                       dict(gpu_scope='main', ns_f32_bits=0x7f800000),
                       dict(gpu_scope='main', ns_f32_bits=0x7fc00000),
                       dict(gpu_scope='main', ns_f32_bits=0xbf800000)):
            run = make_run()
            run.diagnostics = [dict(observed_ns=7, line='producer', values=values)]
            self.assertFalse(any(row['available'] for row in subject.stage_timings(run).values()))


def main(argv=None):
    global subject, SCRATCH
    parser = argparse.ArgumentParser(
        description='Check measurement-driver regression behavior without native execution.')
    parser.add_argument('module', nargs='?', type=Path, default=ROOT / 'tools/measure_m7.py',
                        help='measurement driver to check (default: sibling measure_m7.py)')
    options, unittest_args = parser.parse_known_args(argv)
    module = options.module.resolve()
    sys.path.insert(0, str(ROOT / 'tools'))
    sys.path.insert(0, str(module.parent))
    spec = importlib.util.spec_from_file_location('measured_subject', module)
    subject = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = subject
    with TemporaryDirectory(prefix='measurement-check-') as directory:
        SCRATCH = Path(directory)
        spec.loader.exec_module(subject)
        result = unittest.main(argv=[sys.argv[0], *unittest_args], exit=False).result
        return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main())
