#!/usr/bin/env python3
"""Compare serialized native-window flight and edit workloads using completed STATE frames.

Run only when other device workloads have stopped. Candidate configurations are
arbitrary argv arrays, so CPU scaling and frame-overlap sweeps can run separately.
Runtime flags in those arrays must go between +RTS and -RTS. Only the verified
preserved baseline uses the pre-2.0.38 runtime argument format.
"""

import argparse
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import struct
import subprocess
import sys
import time

from check_window import BUILD, ROOT, X11, isolated_display


BASELINE = BUILD / 'milestone-7-baseline-window'
SINGLE_FRAME_BASELINE = dict(
    binary_sha256='93a9ef7f43e457323d08d2754d55e4e60fb97eb4ee7b1ced0a4fd4c0f9e52ec2',
    source_commit='928bee9e677983c063811e0540f8783d86467a83')
REQUIRED_STATE = ('rows', 'frame', 'generation', 'revision', 'installed', 'uploads',
                  'quads', 'width', 'height', 'mapped', 'captured')
DIAGNOSTIC = re.compile(
    r'Validation (?:Error|Warning|Performance Warning)|SYNC-HAZARD|VUID-|'
    r'AddressSanitizer|LeakSanitizer|UndefinedBehaviorSanitizer|ThreadSanitizer|'
    r'MemorySanitizer|runtime error:|assertion.*failed', re.IGNORECASE)
LIMITS = [
    'STATE.frame counts observed presentation-resource fence completions for successful presents. Full presentation completion and physical scanout are unmeasured.',
    'Trace receipt timestamps include application logging, file visibility, driver polling and scheduling delay.',
    'Both native executables use the same stdbuf -oL wrapper. Line buffering and trace logging overhead are unmeasured; logging delay remains unbounded.',
    'Polling gaps and read intervals bound observer resolution only; application logging delay has no measured bound.',
    'Several trace records may share a receipt timestamp. Per-frame physical or GPU durations cannot be inferred.',
    'Timed edits start before X11 event dispatch. Candidates require exact producer revision tags and frame advancement from the pre-edit state.',
    'Only the preserved, hash- and provenance-verified single-frame baseline may use untagged installation followed by later frame advancement.',
    'Untagged candidates cannot establish revision-specific presentation latency from STATE.frame alone.',
    'Screenshots and post-edit resource settling are outside timed edit regions.',
    'Trace logging is enabled on both sides. Its overhead is unmeasured.',
    'Validation is opt-in. Inherited Vulkan layers are retained and recorded. Build optimization and sanitizer instrumentation are unverified.',
    'Rows and optional metadata counters bound observed resources, not all driver allocations or GPU bytes.',
    'Reset checks bound row range and compare half-window maxima. They do not establish full tail stability or bounded frame-slot ownership.',
    'Paired static captures require exact RGB hashes and geometry/view fields. Time-driven flight-final cameras and images are not compared across sides.',
    'Static capture checks supplement the independent full geometry gate; they do not replace its original-Body coverage and identity checks.',
    'No limiter profile is collected here. Comparative performance conclusions remain inconclusive pending separate profile evidence.',
    'Caller must serialize all device workloads. CPU thread scaling and frame overlap require separate invocations.',
]


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def parse_record(line):
    kind, _, rest = line.partition(' ')
    values = {}
    for key, value in re.findall(r'([\w.]+)=([^\s]+)', rest):
        if re.fullmatch(r'[+-]?\d+', value):
            value = int(value)
        elif re.fullmatch(r'[+-]?(?:\d+\.?\d*|\d*\.\d+)(?:[eE][+-]?\d+)?', value):
            number = float(value)
            value = number if math.isfinite(number) else value
        values[key] = value
    if kind == 'STATE':
        missing = [key for key in REQUIRED_STATE if not isinstance(values.get(key), int)]
        camera = values.get('camera')
        if missing or not isinstance(camera, str) or not re.fullmatch(r'\d+(?:,\d+){4}', camera):
            raise ValueError(f'Invalid STATE fields {missing} or camera in {line}')
    return kind, values


def distribution(values):
    values = list(values)
    if not values:
        return None
    return {'count': len(values), 'median': statistics.median(values),
            'minimum': min(values), 'maximum': max(values)}


@dataclass
class Run:
    id: str
    side: str
    configuration: str
    workload: str
    pair: int
    command: list
    native_command: list
    binary_sha256: str
    log: str
    environment: dict
    instrumentation: dict
    started_utc: str = field(default_factory=utc_now)
    clock_origin_ns: int = field(default_factory=time.monotonic_ns)
    ended_utc: str | None = None
    returncode: int | None = None
    pid: int | None = None
    window: int | None = None
    native_executable: str | None = None
    states: list = field(default_factory=list)
    completed_frames: list = field(default_factory=list)
    edit_latencies: list = field(default_factory=list)
    images: list = field(default_factory=list)
    assertions: list = field(default_factory=list)
    resource_samples: list = field(default_factory=list)
    diagnostics: list = field(default_factory=list)
    observations: list = field(default_factory=list)
    errors: list = field(default_factory=list)
    metrics: dict = field(default_factory=dict)
    stage_timings: dict = field(default_factory=dict)
    legacy_completion_provenance: dict | None = None
    measurement_limits: list = field(default_factory=lambda: list(LIMITS))

    def elapsed_ns(self):
        return time.monotonic_ns() - self.clock_origin_ns

    def require(self, condition, description, **evidence):
        self.assertions.append(dict(passed=bool(condition), description=description, **evidence))
        if not condition:
            raise AssertionError(description)


class Trace:
    def __init__(self, run, stream):
        self.run = run
        self.stream = stream
        self.pending = b''
        self.line = 0

    def poll(self):
        start = self.run.elapsed_ns()
        data = self.stream.read(1024 * 1024)
        received = self.run.elapsed_ns()
        lines = (self.pending + data).split(b'\n')
        self.pending = lines.pop()
        count = 0
        for encoded in lines:
            self.line += 1
            line = encoded.decode('utf-8', errors='replace').rstrip('\r')
            try:
                kind, values = parse_record(line)
            except ValueError as error:
                self.run.errors.append(dict(kind='trace', line=self.line, message=str(error)))
                continue
            record = dict(observed_ns=received, line=self.line, values=values)
            if DIAGNOSTIC.search(line):
                self.run.errors.append(dict(kind='diagnostic', line=self.line, message=line))
            if kind == 'STATE':
                prior = self.run.states[-1]['values'] if self.run.states else None
                if prior and values['frame'] < prior['frame']:
                    raise AssertionError('Completed frame counter decreased')
                self.run.states.append(record)
                count += 1
                if prior and values['frame'] > prior['frame']:
                    self.run.completed_frames.append(dict(
                        observed_ns=received, frame=values['frame'],
                        increment=values['frame'] - prior['frame'], state_index=len(self.run.states) - 1))
                self.run.resource_samples.append(dict(source='STATE', observed_ns=received,
                                                     frame=values['frame'], rows=values['rows']))
            elif kind == 'COUNTS':
                self.run.resource_samples.append(dict(source='COUNTS', **record))
            elif line:
                self.run.diagnostics.append(dict(raw=line, **record))
        self.run.observations.append(dict(start_ns=start, end_ns=received,
                                         bytes=len(data), states=count))
        return self.run.states[-1] if self.run.states else None


def process_resources(pid):
    try:
        status = (Path('/proc') / str(pid) / 'status').read_text()
        values = {key: int(value) for key, value in
                  re.findall(r'^(VmRSS|VmHWM|VmSize|Threads):\s+(\d+)', status, re.MULTILINE)}
        stat = (Path('/proc') / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()
        ticks = os.sysconf('SC_CLK_TCK')
        return dict(available=True, rss_kib=values.get('VmRSS'), peak_rss_kib=values.get('VmHWM'),
                    virtual_kib=values.get('VmSize'), threads=values.get('Threads'),
                    cpu_user_seconds=int(stat[11]) / ticks, cpu_system_seconds=int(stat[12]) / ticks)
    except (OSError, ValueError, IndexError) as error:
        return dict(available=False, reason=str(error))


def application_environment(validation, inherited):
    environment = dict(inherited)
    if validation:
        layers = [v for v in environment.get('VK_INSTANCE_LAYERS', '').split(':') if v]
        if 'VK_LAYER_KHRONOS_validation' not in layers:
            layers.append('VK_LAYER_KHRONOS_validation')
        environment.update(VK_INSTANCE_LAYERS=':'.join(layers), VK_LAYER_VALIDATE_SYNC='1')
    environment.setdefault('ASAN_OPTIONS', 'halt_on_error=1')
    environment.setdefault('UBSAN_OPTIONS', 'halt_on_error=1:print_stacktrace=1')
    return environment


class WindowRun:
    def __init__(self, run, x, process, trace, directory, args):
        self.run, self.x, self.process, self.trace = run, x, process, trace
        self.directory, self.args = directory, args

    def wait(self, predicate, description, timeout=None):
        deadline = time.monotonic() + (self.args.timeout if timeout is None else timeout)
        while time.monotonic() < deadline:
            latest = self.trace.poll()
            if self.process.poll() is not None:
                raise RuntimeError(f'{description}. Process exited {self.process.returncode}')
            if latest is not None and predicate(latest['values']):
                return latest
            time.sleep(self.args.poll_ms / 1000)
        raise TimeoutError(description)

    def settle(self, previous, frames=None):
        count = self.args.settle_frames if frames is None else frames
        return self.wait(lambda s: s['frame'] >= previous['values']['frame'] + count
                         and s['installed'] == s['revision'], 'Wait for settled installed frames')

    def checkpoint(self, label, state):
        counts = next((s for s in reversed(self.run.resource_samples) if s['source'] == 'COUNTS'), None)
        self.run.resource_samples.append(dict(source='checkpoint', label=label,
            observed_ns=self.run.elapsed_ns(), state=state['values'],
            native_counts=counts,
            process=process_resources(self.process.pid)))

    def capture(self, label, state, expected=None, different=None):
        from PIL import Image

        path = self.directory / f'{label}.png'
        command = ['import', '-window', str(self.x.owned), str(path)]
        deadline = time.monotonic() + self.args.timeout
        attempts = []
        while time.monotonic() < deadline:
            start = self.run.elapsed_ns()
            subprocess.run(command, check=True, timeout=self.args.timeout)
            with Image.open(path) as image:
                image = image.convert('RGB')
                pixels = image.tobytes()
                signature = dict(width=image.width, height=image.height,
                                 rgb_sha256=hashlib.sha256(pixels).hexdigest())
                nonblank = len(image.getcolors(image.width * image.height) or []) > 3
            passed = (nonblank and (expected is None or signature == expected)
                      and (different is None or signature != different))
            attempts.append(dict(start_ns=start, end_ns=self.run.elapsed_ns(),
                                 signature=signature, nonblank=nonblank, passed=passed))
            if passed:
                break
            if self.process.poll() is not None:
                break
            self.settle(self.trace.poll(), frames=1)
        self.run.images.append(dict(label=label, path=str(path), command=command,
            file_sha256=digest(path) if path.exists() else None,
            state=state, expected=expected, different=different, attempts=attempts))
        self.run.require(bool(attempts) and attempts[-1]['passed'], f'{label} image assertion')
        return signature

    def flight(self, initial):
        original = self.capture('flight-initial', initial)
        before_input = self.run.elapsed_ns()
        self.x.key(ord('w'), True)
        try:
            start = self.wait(lambda s: s['camera'] != initial['values']['camera']
                              and s['frame'] > initial['values']['frame'],
                              'Camera motion and a completed flight frame')
            deadline_ns = start['observed_ns'] + int(self.args.flight_seconds * 1e9)
            end = self.wait(lambda s: self.run.states[-1]['observed_ns'] >= deadline_ns
                            and s['frame'] > start['values']['frame'], 'Completed camera flight interval',
                            timeout=self.args.flight_seconds + self.args.timeout)
        finally:
            self.x.key(ord('w'), False)
        timed = [s['values'] for s in self.run.states
                 if start['observed_ns'] <= s['observed_ns'] <= end['observed_ns']]
        self.run.require(all(s['uploads'] == initial['values']['uploads'] for s in timed),
                         'Camera flight kept geometry upload counter unchanged')
        self.run.require(all(s['revision'] == initial['values']['revision'] and
                             s['quads'] == initial['values']['quads'] for s in timed),
                         'Camera flight kept geometry state unchanged')
        self.run.require(start['values']['camera'] != end['values']['camera'],
                         'Camera continued moving inside measured interval')
        frames = end['values']['frame'] - start['values']['frame']
        seconds = (end['observed_ns'] - start['observed_ns']) / 1e9
        self.run.metrics.update(completed_frames=frames, observed_seconds=seconds,
                                completed_frames_per_second=frames / seconds,
                                input_start_ns=before_input, start=start, end=end)
        final = self.settle(end)
        self.checkpoint('flight-end', final)
        self.capture('flight-final', final, different=original)

    def edit(self, action, previous, cycle, warmup):
        target = previous['values']['revision'] + 1
        start_index = len(self.run.states)
        sample = dict(action=action, cycle=cycle, warmup=warmup,
                      target_revision=target, before=previous, completed=False)
        self.run.edit_latencies.append(sample)
        sample['input_start_ns'] = self.run.elapsed_ns()
        if action == 'cut':
            self.x.button(1, True)
            self.x.button(1, False)
        else:
            self.x.key(ord('r'), True)
            self.x.key(ord('r'), False)
        sample['input_dispatched_ns'] = self.run.elapsed_ns()
        self.wait(lambda s: s['revision'] >= target and s['installed'] >= target,
                  f'{action} revision installed')
        installed_index = next(i for i in range(start_index, len(self.run.states))
                               if self.run.states[i]['values']['revision'] >= target
                               and self.run.states[i]['values']['installed'] >= target)
        installed = self.run.states[installed_index]
        sample['installed'] = installed
        sample['installed_state_index'] = installed_index
        def complete(s):
            tags = [s[key] for key in ('completed_revision', 'presented_revision') if key in s]
            if s['revision'] != target or s['installed'] != target:
                return False
            if tags:
                return (s['frame'] > previous['values']['frame']
                        and all(type(tag) is int and tag == target for tag in tags))
            return (self.run.side == 'baseline' and self.run.legacy_completion_provenance is not None
                    and s['frame'] > installed['values']['frame'])
        if not any(complete(s['values']) for s in self.run.states[installed_index:]):
            self.wait(lambda _: any(complete(s['values']) for s in self.run.states[installed_index:]),
                      f'{action} completed frame for exactly revision {target}')
        end_index = next(i for i in range(installed_index, len(self.run.states))
                         if complete(self.run.states[i]['values']))
        end = self.run.states[end_index]
        sample.update(end=end, completed=True,
                      observed_latency_ms=(end['observed_ns'] - sample['input_start_ns']) / 1e6,
                      completed_frame_increment=end['values']['frame'] - previous['values']['frame'])
        sample['completion_revision_tags'] = {key: end['values'][key]
            for key in ('completed_revision', 'presented_revision') if key in end['values']}
        sample['completion_evidence'] = ('Exact producer revision tag and completed frame advancement from pre-edit state.'
            if sample['completion_revision_tags'] else
            'Verified single-frame baseline installation followed by later frame advancement; no revision tag available.')
        self.run.require(end['values']['revision'] == target and end['values']['installed'] == target,
                         f'{action} installed exactly the requested revision', target_revision=target)
        self.run.require(end['observed_ns'] >= sample['input_start_ns'],
                         f'{action} completion observed after actual input dispatch')
        return end

    def edits(self, initial):
        intact = self.capture('edit-original', initial)
        previous = initial
        reset_checkpoints = []
        for cycle in range(self.args.warmup_edits + self.args.edits):
            warmup = cycle < self.args.warmup_edits
            cut = self.edit('cut', previous, cycle, warmup)
            self.run.require(cut['values']['quads'] != initial['values']['quads'],
                             'Cut changed geometry quad count', cycle=cycle,
                             original=initial['values']['quads'], cut=cut['values']['quads'])
            cut = self.settle(cut)
            carved = self.capture(f'edit-{cycle:02d}-cut', cut, different=intact)
            reset = self.edit('reset', cut, cycle, warmup)
            reset = self.settle(reset)
            fields = ('quads', 'camera', 'width', 'height', 'mapped', 'captured')
            self.run.require(all(reset['values'][key] == initial['values'][key] for key in fields),
                             'Reset restored its own original geometry and view state', cycle=cycle,
                             original={key: initial['values'][key] for key in fields},
                             restored={key: reset['values'][key] for key in fields})
            self.capture(f'edit-{cycle:02d}-reset', reset, expected=intact, different=carved)
            self.checkpoint(f'reset-{cycle:02d}', reset)
            if not warmup:
                reset_checkpoints.append(reset)
            previous = reset
        rows = [sample['values']['rows'] for sample in reset_checkpoints]
        half = len(rows) // 2
        self.run.require(max(rows) - min(rows) <= self.args.row_tolerance,
                         'Post-warmup reset rows remained bounded', rows=rows,
                         allowed_range=self.args.row_tolerance)
        self.run.require(max(rows[half:]) <= max(rows[:half]),
                         'Post-warmup reset-row second-half maximum did not exceed first-half maximum', rows=rows)
        checkpoints = [s for s in self.run.resource_samples if s['source'] == 'checkpoint'
                       and s['label'].startswith('reset-')][self.args.warmup_edits:]
        allocations = [s['native_counts']['values']['allocations'] for s in checkpoints
                       if s['native_counts'] and 'allocations' in s['native_counts']['values']]
        if allocations:
            self.run.require(len(allocations) == self.args.edits and
                             max(allocations[half:]) <= max(allocations[:half]),
                             'Post-warmup metadata allocation samples were complete and second-half maximum did not exceed first-half maximum',
                             allocations=allocations)
        else:
            self.run.measurement_limits.append(
                'Native metadata allocation counters were absent at reset checkpoints. No native metadata allocation bound is established.')
        for action in ('cut', 'reset'):
            samples = [s['observed_latency_ms'] for s in self.run.edit_latencies
                       if s['action'] == action and not s['warmup'] and s['completed']]
            self.run.metrics[f'{action}_observed_latency_ms'] = distribution(samples)


def stage_timings(run):
    categories = dict(cpu_meshing=r'mesh|build', upload=r'upload|transfer',
                      gpu_render=r'gpu|render|shadow', presentation=r'present|acquire')
    records = run.states + run.diagnostics
    result = {}
    for category, pattern in categories.items():
        fields = {}
        for record in records:
            for name, value in record['values'].items():
                unit = re.search(r'(?:_|\.)(ns|us|ms|seconds)$', name, re.IGNORECASE)
                capability = re.search(r'period|resolution|wrap|valid|bits|supported|available', name, re.IGNORECASE)
                if (unit and not capability and re.search(pattern, name, re.IGNORECASE)
                        and isinstance(value, (int, float))):
                    fields.setdefault(name, dict(unit=unit[1], samples=[]))['samples'].append(
                        dict(observed_ns=record['observed_ns'], value=value, line=record['line']))
        result[category] = dict(available=bool(fields), fields=fields,
            scope='Producer-defined diagnostic fields. No unreported stage costs are inferred.' if fields else
                  'Unavailable. This binary emitted no recognized stage timing with an explicit unit.')
    protocol = {
        ('cpu_scope', 'edit_mesh_events'): 'cpu_meshing',
        ('cpu_scope', 'upload_prepare'): 'upload',
        ('cpu_scope', 'record_and_submit'): 'cpu_recording',
        ('cpu_scope', 'present_call'): 'presentation',
        ('gpu_scope', 'upload'): 'upload',
        ('gpu_scope', 'shadow'): 'gpu_render',
        ('gpu_scope', 'main'): 'gpu_render',
    }
    for record in records:
        values = record['values']
        for (label, scope), category in protocol.items():
            if values.get(label) != scope:
                continue
            if label == 'cpu_scope':
                lo, hi = values.get('ns_lo'), values.get('ns_hi')
                if not all(type(v) is int and 0 <= v <= 0xffffffff for v in (lo, hi)):
                    continue
                value = (hi << 32) | lo
            else:
                bits = values.get('ns_f32_bits')
                if type(bits) is not int or not 0 <= bits <= 0xffffffff:
                    continue
                value = struct.unpack('<f', struct.pack('<I', bits))[0]
                if not math.isfinite(value) or value < 0:
                    continue
            result.setdefault(category, dict(available=False, fields={}, scope='Unavailable.'))
            field = label + '.' + scope + '_ns'
            result[category]['fields'].setdefault(field, dict(unit='ns', producer_label=label,
                producer_scope=scope, samples=[]))['samples'].append(dict(
                    observed_ns=record['observed_ns'], value=value, line=record['line']))
            result[category]['available'] = True
            result[category]['scope'] = ('Explicit milestone 7 producer scopes. CPU integer limbs are exact; '
                'GPU values are finite decoded F32 nanoseconds. GPU TOP-to-BOTTOM windows can include preceding completion and overlap following work; they are not isolated costs. CPU scopes can realize deferred pure work and include polling/warmup/settling. CPU and GPU observations must not be added.')
    capabilities = {}
    for record in records:
        for name, value in record['values'].items():
            if re.search(r'timestamp|query', name, re.IGNORECASE):
                capabilities.setdefault(name, []).append(dict(observed_ns=record['observed_ns'],
                                                              value=value, line=record['line']))
    for item in capabilities.get('timestamp_period_ns_f32_bits', []):
        bits = item['value']
        if type(bits) is int and 0 <= bits <= 0xffffffff:
            period = struct.unpack('<f', struct.pack('<I', bits))[0]
            if math.isfinite(period) and period > 0:
                capabilities.setdefault('timestamp_period_ns', []).append(dict(item, value=period))
    result['gpu_render']['timestamp_capabilities'] = dict(available=bool(capabilities), fields=capabilities,
        scope='Producer diagnostics only. Query support, tick period, valid bits and wrap limits are unavailable unless emitted.')
    return result


def execute_run(run, directory, args, environment):
    directory.mkdir()
    x = process = trace = None
    with Path(run.log).open('wb') as output, Path(run.log).open('rb') as input_stream:
        trace = Trace(run, input_stream)
        try:
            x = X11()
            process = subprocess.Popen(run.command, cwd=ROOT, env=environment,
                                       stdout=output, stderr=subprocess.STDOUT)
            run.pid = process.pid
            deadline = time.monotonic() + args.timeout
            while not x.find(process.pid):
                trace.poll()
                if process.poll() is not None:
                    raise RuntimeError(f'Process exited {process.returncode} before creating a window')
                if time.monotonic() >= deadline:
                    raise TimeoutError('Spawned native window not found by PID')
                time.sleep(args.poll_ms / 1000)
            run.window = int(x.owned)
            run.native_executable = os.readlink(f'/proc/{process.pid}/exe')
            run.require(run.native_executable == run.native_command[0] and
                        digest(Path(f'/proc/{process.pid}/exe')) == run.binary_sha256,
                        'Launched PID owns the native executable and expected binary hash')
            driver = WindowRun(run, x, process, trace, directory, args)
            initial = driver.wait(lambda s: s['frame'] >= args.warmup_frames and
                                  s['revision'] == s['installed'] and s['mapped'] == 1,
                                  'Initial completed frames and installed geometry')
            x.focus()
            x.move(*args.edit_point)
            initial = driver.settle(initial)
            driver.checkpoint('initial', initial)
            if run.workload == 'flight':
                driver.flight(initial)
            else:
                driver.edits(initial)
        except Exception as error:
            run.errors.append(dict(kind=type(error).__name__, message=str(error)))
        finally:
            if process is not None:
                if process.poll() is None:
                    try:
                        if x is None or x.owned is None:
                            raise RuntimeError('No owned window for orderly shutdown')
                        x.close()
                        process.wait(timeout=args.timeout)
                    except Exception as error:
                        run.errors.append(dict(kind='shutdown', message=str(error)))
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                run.returncode = process.returncode
                if process.returncode != 0:
                    run.errors.append(dict(kind='exit', message=f'Exit code {process.returncode}'))
            try:
                while trace.stream.tell() < Path(run.log).stat().st_size:
                    trace.poll()
            except Exception as error:
                run.errors.append(dict(kind='trace', message=str(error)))
            if x is not None:
                x.x.XCloseDisplay(x.d)
    text = Path(run.log).read_text(errors='replace')
    recorded_diagnostics = {error.get('line') for error in run.errors if error['kind'] == 'diagnostic'}
    for number, line in enumerate(text.splitlines(), 1):
        if DIAGNOSTIC.search(line) and number not in recorded_diagnostics:
            run.errors.append(dict(kind='diagnostic', line=number, message=line))
    if not re.search(r'^Native interactive shutdown rows=0\s*$', text, re.MULTILINE):
        run.errors.append(dict(kind='shutdown', message='Missing successful zero-live-row shutdown evidence'))
    counts = [s['values'] for s in run.resource_samples if s['source'] == 'COUNTS']
    if counts and (counts[-1].get('rows') != 0 or counts[-1].get('allocations', 0) != 0):
        run.errors.append(dict(kind='shutdown', message='Final native COUNTS were not zero', counts=counts[-1]))
    if trace.pending:
        run.errors.append(dict(kind='trace', message='Log ended with an incomplete line',
                               tail=trace.pending.decode(errors='replace')))
    if digest(Path(run.native_command[0])) != run.binary_sha256:
        run.errors.append(dict(kind='binary', message='Binary changed during this run'))
    run.stage_timings = stage_timings(run)
    intervals = [(b['start_ns'] - a['start_ns']) / 1e6
                 for a, b in zip(run.observations, run.observations[1:])]
    run.metrics['observer_poll_gap_ms'] = distribution(intervals)
    run.metrics['observer_read_ms'] = distribution((s['end_ns'] - s['start_ns']) / 1e6
                                                  for s in run.observations)
    run.metrics['maximum_states_per_read'] = max((s['states'] for s in run.observations), default=0)
    run.metrics['attempted_edits'] = len(run.edit_latencies)
    run.metrics['completed_edits'] = sum(sample['completed'] for sample in run.edit_latencies)
    run.ended_utc = utc_now()
    return run


def compare_pair(baseline, candidate):
    if any(a.get('paired_run') == candidate.id for a in baseline.assertions):
        return
    fields = ('quads', 'camera', 'width', 'height', 'mapped', 'captured')
    images = [{i['label']: i for i in run.images if i['label'] != 'flight-final'}
              for run in (baseline, candidate)]
    labels = {'flight-initial'} if baseline.workload == 'flight' else {
        'edit-original', *(f"edit-{s['cycle']:02d}-{s['action']}"
                           for run in (baseline, candidate) for s in run.edit_latencies)}
    mismatches = []
    if any(set(side) != labels for side in images):
        mismatches.append(dict(field='capture_labels', expected=sorted(labels),
                               baseline=sorted(images[0]), candidate=sorted(images[1])))
    for label in sorted(labels & images[0].keys() & images[1].keys()):
        before, after = (side[label] for side in images)
        for key in fields:
            a, b = before['state']['values'][key], after['state']['values'][key]
            if a != b:
                mismatches.append(dict(label=label, field=key, baseline=a, candidate=b))
        a, b = (image['attempts'][-1]['signature'] for image in (before, after))
        if a != b:
            mismatches.append(dict(label=label, field='image_signature', baseline=a, candidate=b))
    for run, partner in ((baseline, candidate), (candidate, baseline)):
        run.assertions.append(dict(passed=not mismatches,
            description='Paired static geometry, view and exact image signatures matched',
            paired_run=partner.id, mismatches=mismatches))
        if mismatches:
            run.errors.append(dict(kind='pair_comparison', message='Paired static output mismatch',
                                   paired_run=partner.id, mismatches=mismatches))


def summarize(runs, pairs, smoke=False):
    groups = {}
    for run in runs:
        groups.setdefault((run.configuration, run.workload), []).append(run)
    result = []
    for (configuration, workload), group in groups.items():
        for pair in range(pairs):
            sides = {r.side: r for r in group if r.pair == pair}
            if (set(sides) == {'baseline', 'candidate'}
                    and all(r.ended_utc is not None and not r.errors for r in sides.values())):
                compare_pair(sides['baseline'], sides['candidate'])
        comparative = not smoke and pairs >= 5
        entry = dict(configuration=configuration, workload=workload, required_pairs=pairs,
                     comparative=comparative, insufficient_replication=pairs < 5,
                     failed_runs=sum(bool(r.errors) or r.ended_utc is None for r in group),
                     failure_count=sum(len(r.errors) for r in group), sides={}, paired_samples=[])
        metrics = ['completed_frames_per_second'] if workload == 'flight' else [
            'cut_observed_latency_ms', 'reset_observed_latency_ms']
        good_pairs = [pair for pair in range(pairs)
                      if {r.side for r in group if r.pair == pair and not r.errors
                          and r.ended_utc is not None and all(key in r.metrics for key in metrics)}
                      == {'baseline', 'candidate'}]
        entry['successful_pairs'] = len(good_pairs)
        for side in ('baseline', 'candidate'):
            selected = [r for r in group if r.side == side and r.pair in good_pairs]
            entry['sides'][side] = {}
            for metric in metrics:
                values = [r.metrics[metric]['median'] if isinstance(r.metrics.get(metric), dict)
                          else r.metrics[metric] for r in selected if metric in r.metrics]
                entry['sides'][side][metric] = distribution(values)
        for pair in good_pairs if comparative else []:
            sides = {r.side: r for r in group if r.pair == pair}
            values = {}
            for metric in metrics:
                def value(side):
                    raw = sides[side].metrics[metric]
                    return raw['median'] if isinstance(raw, dict) else raw
                before, after = value('baseline'), value('candidate')
                values[metric] = dict(baseline=before, candidate=after,
                                      candidate_minus_baseline=after - before)
            entry['paired_samples'].append(dict(pair=pair, metrics=values))
        entry['verdict'] = 'inconclusive' if comparative else 'noncomparative'
        entry['reason'] = ('Correctness smoke run. No performance comparison; fewer than five pairs is insufficient replication.'
                           if not comparative else 'Verification failures or incomplete pairs.'
                           if len(good_pairs) < pairs else
                           'Pending separate limiter profile evidence. Trace logging overhead is unmeasured.')
        entry['range_overlap'] = {}
        for metric in metrics if comparative else []:
            before = entry['sides']['baseline'][metric]
            after = entry['sides']['candidate'][metric]
            entry['range_overlap'][metric] = (None if before is None or after is None else
                max(before['minimum'], after['minimum']) <= min(before['maximum'], after['maximum']))
        result.append(entry)
    return result


def positive_int(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError('Must be positive')
    return number


def positive_float(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError('Must be finite and positive')
    return number


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, epilog=
        'Use --candidate-arg=--flag for a flag token, then --candidate-arg=VALUE for its value. '
        'Repeat --candidate-config NAME \'["--flag", "VALUE"]\' to sweep arbitrary candidate argv arrays. '
        'Run thread scaling and frame-overlap sweeps separately, after all other GPU workloads stop.')
    parser.add_argument('--baseline', type=Path, default=BASELINE)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--pairs', type=positive_int, help='Default 5, or 1 with --smoke')
    parser.add_argument('--smoke', action='store_true', help='Noncomparative real-window correctness run')
    parser.add_argument('--validation', action='store_true', help='Enable Vulkan and synchronization validation')
    parser.add_argument('--threads', type=positive_int, default=6)
    parser.add_argument('--baseline-arg', action='append', default=[])
    parser.add_argument('--candidate-arg', action='append', default=[])
    parser.add_argument('--candidate-config', nargs=2, action='append', default=[], metavar=('NAME', 'ARGV_JSON'))
    parser.add_argument('--isolated-display', action='store_true')
    parser.add_argument('--output', type=Path, default=BUILD / 'milestone-7-measurements.json')
    parser.add_argument('--flight-seconds', type=positive_float, default=3)
    parser.add_argument('--edits', type=positive_int, default=6, help='Measured cut/reset cycles per fresh process')
    parser.add_argument('--warmup-edits', type=positive_int, default=2)
    parser.add_argument('--warmup-frames', type=positive_int, default=8)
    parser.add_argument('--settle-frames', type=positive_int, default=4)
    parser.add_argument('--poll-ms', type=positive_float, default=2)
    parser.add_argument('--timeout', type=positive_float, default=30)
    parser.add_argument('--row-tolerance', type=int, default=8)
    parser.add_argument('--edit-point', type=int, nargs=2, default=(292, 210), metavar=('X', 'Y'))
    parser.add_argument('--workload', choices=('all', 'flight', 'edits'), default='all')
    args = parser.parse_args(argv)
    if args.pairs is None:
        args.pairs = 1 if args.smoke else 5
    if (not args.smoke and args.pairs < 5) or args.edits < 4 or args.row_tolerance < 0:
        parser.error('Require at least five pairs unless --smoke, four measured edit cycles, and nonnegative row tolerance')
    configs = []
    for name, raw in args.candidate_config or [('default', '[]')]:
        try:
            extra = json.loads(raw)
        except json.JSONDecodeError as error:
            parser.error(f'Invalid candidate argv JSON for {name}. {error}')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', name):
            parser.error('Configuration names must contain only letters, digits, underscore, dot or hyphen')
        if not isinstance(extra, list) or any(not isinstance(v, str) or '\x00' in v for v in extra):
            parser.error('Candidate argv must be a JSON array of strings without NUL bytes')
        if name in [n for n, _ in configs]:
            parser.error(f'Duplicate configuration {name}')
        configs.append((name, extra))
    args.configurations = configs
    return args


def write_report(path, report, runs, pairs):
    report['summary'] = summarize(runs, pairs, smoke=report.get('mode') == 'smoke')
    report['runs'] = [dict(**asdict(run), failure_count=len(run.errors),
                          passed=not run.errors and run.ended_utc is not None) for run in runs]
    report['failure_count'] = sum(len(run.errors) for run in runs) + len(report['errors'])
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    temporary.replace(path)


def main(argv=None):
    args = arguments(argv)
    stdbuf = shutil.which('stdbuf')
    if stdbuf is None:
        raise SystemExit('stdbuf is required for identical line-buffered native traces')
    wrapper = [str(Path(stdbuf).resolve()), '-oL']
    instrumentation = dict(wrapper_command=wrapper, wrapper_sha256=digest(Path(wrapper[0])),
        stdout_buffering='line', pid_ownership='stdbuf exec preserves the native PID; verified through /proc and X11.',
        overhead='Unmeasured. Logging, observation and scheduling delays have no measured bound.')
    for binary in (args.baseline, args.candidate):
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise SystemExit(f'Executable binary required. {binary}')
    args.baseline, args.candidate = args.baseline.resolve(), args.candidate.resolve()
    args.output = args.output.resolve()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    artifacts = args.output.parent / f'{args.output.stem}-runs-{time.time_ns()}'
    artifacts.mkdir()
    environment = application_environment(args.validation, os.environ)
    layers = [v for v in environment.get('VK_INSTANCE_LAYERS', '').split(':') if v]
    selected_env = {key: value for key, value in environment.items() if
                    key.startswith(('VK_', 'ASAN_', 'UBSAN_', 'BEND_', 'OMP_', 'MESA_',
                                    'NVIDIA_', '__GL_', 'WAYLAND_')) or
                    key in ('BENDRTS', 'DISPLAY', 'LD_PRELOAD', 'LD_LIBRARY_PATH')}
    selected_env['VK_INSTANCE_LAYERS'] = environment.get('VK_INSTANCE_LAYERS', '')
    selected_env['VK_LAYER_VALIDATE_SYNC'] = environment.get('VK_LAYER_VALIDATE_SYNC')
    metadata = {}
    for name in ('milestone-7-baseline-window.sha256', 'milestone-7-baseline-commit.txt',
                 'milestone-7-device.txt'):
        source = BUILD / name
        if source.exists():
            shutil.copyfile(source, artifacts / name)
            metadata[name] = dict(source=str(source), archive=str(artifacts / name), text=source.read_text())
        else:
            metadata[name] = dict(available=False)
    hashes = {side: digest(getattr(args, side)) for side in ('baseline', 'candidate')}
    if args.baseline == BASELINE.resolve() and 'text' in metadata['milestone-7-baseline-window.sha256']:
        expected = metadata['milestone-7-baseline-window.sha256']['text'].split()[0]
        if hashes['baseline'] != expected:
            raise SystemExit('Preserved baseline SHA256 does not match its manifest')
    legacy_provenance = None
    if (args.baseline == BASELINE.resolve()
            and hashes['baseline'] == SINGLE_FRAME_BASELINE['binary_sha256']
            and metadata['milestone-7-baseline-window.sha256'].get('text', '').split()[:1]
                == [hashes['baseline']]
            and metadata['milestone-7-baseline-commit.txt'].get('text', '').strip()
                == SINGLE_FRAME_BASELINE['source_commit']):
        legacy_provenance = dict(**SINGLE_FRAME_BASELINE, frames_in_flight=1,
                                 executable=str(args.baseline))
    host_commands = {}
    for command in (['uptime'], ['nproc']):
        result = subprocess.run(command, capture_output=True, text=True, timeout=5)
        host_commands[command[0]] = dict(command=command, returncode=result.returncode,
                                        stdout=result.stdout, stderr=result.stderr)
    report = dict(schema_version=1, mode='smoke' if args.smoke else 'comparative',
        validation=dict(requested=args.validation, effective_instance_layers=layers,
                        synchronization_validation=environment.get('VK_LAYER_VALIDATE_SYNC'),
                        scope='Effective layer environment. Implicit layers and application-enabled layers are not independently enumerated.'),
        started_utc=utc_now(), output=str(args.output),
        artifacts=str(artifacts), options={key: str(value) if isinstance(value, Path) else value
                                         for key, value in vars(args).items()},
        host=dict(platform=platform.platform(), cpu_count=os.cpu_count(),
                  cpu_affinity=sorted(os.sched_getaffinity(0)), load_average=os.getloadavg(),
                  commands=host_commands), metadata=metadata, binary_sha256=hashes,
        instrumentation=instrumentation, measurement_limits=LIMITS, errors=[], runs=[], summary=[])
    runs = []
    try:
        with isolated_display(args.isolated_display):
            selected_env['DISPLAY'] = os.environ.get('DISPLAY')
            environment['DISPLAY'] = os.environ.get('DISPLAY', '')
            workloads = ('flight', 'edits') if args.workload == 'all' else (args.workload,)
            for name, extra in args.configurations:
                for workload in workloads:
                    for pair in range(args.pairs):
                        for side in ('baseline', 'candidate'):
                            identifier = f'{name}-{workload}-{pair + 1:02d}-{side}'
                            directory = artifacts / identifier
                            runtime = ['--threads', str(args.threads)]
                            if not (side == 'baseline' and legacy_provenance):
                                runtime = ['+RTS', *runtime, '-RTS']
                            native_command = [str(getattr(args, side)), *runtime, '--trace',
                                              *getattr(args, side + '_arg'), *([] if side == 'baseline' else extra)]
                            run = Run(identifier, side, name, workload, pair, wrapper + native_command,
                                      native_command, hashes[side], str(directory / 'application.log'),
                                      dict(selected_env), dict(instrumentation))
                            if side == 'baseline':
                                run.legacy_completion_provenance = legacy_provenance
                            if args.smoke:
                                run.measurement_limits.append('Noncomparative smoke workload. Insufficient replication for performance conclusions when fewer than five pairs run.')
                            runs.append(run)
                            execute_run(run, directory, args, environment)
                            write_report(args.output, report, runs, args.pairs)
                            print(f'{identifier} {"FAIL" if run.errors else "PASS"} '
                                  f'failures={len(run.errors)} log={run.log}', flush=True)
    except KeyboardInterrupt:
        if runs and runs[-1].ended_utc is None:
            runs[-1].errors.append(dict(kind='interrupted', message='Run interrupted before completion'))
        report['errors'].append(dict(kind='interrupted', message='Measurement interrupted'))
    except Exception as error:
        if runs and runs[-1].ended_utc is None:
            runs[-1].errors.append(dict(kind=type(error).__name__, message=str(error)))
        report['errors'].append(dict(kind=type(error).__name__, message=str(error)))
    finally:
        if args.isolated_display and (BUILD / 'window-xwayland.log').exists():
            shutil.copyfile(BUILD / 'window-xwayland.log', artifacts / 'display.log')
        report['ended_utc'] = utc_now()
        write_report(args.output, report, runs, args.pairs)
    verdict = 'noncomparative smoke run' if args.smoke else 'inconclusive pending separate profile evidence'
    print(f'Report {args.output}. failures={report["failure_count"]}. Performance verdict {verdict}.')
    return 1 if report['failure_count'] else 0


if __name__ == '__main__':
    sys.exit(main())
