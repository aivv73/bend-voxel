"""Megascene process supervision, committed evidence, and persistent allowances.

Linux shared recorder v1 uses acquire/release 64-bit atomics and non-reused slots.
No resource, persistence, or synthetic result can qualify benchmark completion.
"""
from concurrent.futures import ThreadPoolExecutor
import ctypes
import fcntl
import json
import mmap
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import time

from megascene_inventory import SCHEMA, canonical, integer, read_json, require

active_campaign = None
NS = 1_000_000_000
POLICY = {'cadence_ns': 100_000_000, 'freshness_ns': NS, 'rss_bytes': 20*1024**3,
          'available_ram_bytes': 6*1024**3, 'device_free_bytes': 768*1024**2,
          'startup_ns': 120*NS, 'watchdog_ns': 30*NS, 'case_ns': 300*NS}


def snapshot(path, value):
    from megascene import snapshot as write
    write(path, value)


class Campaign:
    """One locked campaign per archive root, shared across all invocation kinds.

    Wall time (including build/validation/control time and idle time) is charged
    from the persisted lease. A restart never creates a fresh two-hour budget.
    Explicit additions reopen interrupted/exhausted campaigns without losing
    any prior charge. A reboot uses UTC conservatively and records the switch.
    """
    def __init__(self, root, additional=0):
        import uuid
        from datetime import datetime, timezone
        root.mkdir(parents=True, exist_ok=True)
        self.path = root/'campaign.json'
        self.lock = (root/'campaign.lock').open('a')
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close()
            raise ValueError('campaign already has an active supervisor')
        now, utc = time.monotonic_ns(), time.time_ns()
        boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
        if self.path.exists():
            self.value = read_json(self.path.read_text())
            require(self.value['schema'] == SCHEMA, 'unsupported campaign schema')
            old = self.value
            delta = now-int(old['lease_ns']) if boot == old['boot_id'] else max(0, utc-int(old['lease_utc_ns']))
            raw_elapsed = int(old['elapsed_ns'])+max(0,delta)
            self.used = min(int(old['allowance_ns']), raw_elapsed)
            self.value['expired_idle_ns'] = str(max(0, raw_elapsed-int(old['allowance_ns'])))
            if not (additional or (old['state'] == 'ready' and self.used < int(old['allowance_ns']))):
                self.lock.close()
                raise ValueError('campaign interrupted/exhausted; declare --additional-allowance SECONDS to resume')
        else:
            require(not additional, 'additional allowance requires an existing campaign')
            self.used = 0
            self.value = {'schema': SCHEMA, 'record_type': 'campaign', 'campaign_id': str(uuid.uuid4()),
                          'utc_start': datetime.now(timezone.utc).isoformat(), 'initial_allowance_s': '7200',
                          'allowance_ns': str(7200*NS), 'additional_allowances': [], 'attempts': [],
                          'policy': ['https://github.com/aivv73/bend-voxel/issues/39#issuecomment-5858595531',
                                     'https://github.com/aivv73/bend-voxel/issues/42#issuecomment-5862953507'],
                          'archive': str(root)}
        if additional:
            self.value['additional_allowances'].append({'seconds': str(additional), 'utc_ns': str(utc),
                                                        'elapsed_before_ns': str(self.used), 'explicit': True})
            self.value['allowance_ns'] = str(int(self.value['allowance_ns'])+additional*NS)
        self.start = now
        self.value.update(boot_id=boot, lease_ns=str(now), lease_utc_ns=str(utc), elapsed_ns=str(self.used), state='active')
        self.save()

    def remaining_ns(self):
        return max(0, int(self.value['allowance_ns'])-self.used-(time.monotonic_ns()-self.start))

    def save(self):
        snapshot(self.path, self.value)

    def attempt(self, attempt_id, summary_path, cause):
        self.value['attempts'].append({'attempt_id': attempt_id, 'summary': str(summary_path), 'cause': cause,
                                      'elapsed_ns': str(self.used+time.monotonic_ns()-self.start)})
        self.save()

    def close(self, completed):
        self.value['elapsed_ns'] = str(min(int(self.value['allowance_ns']),self.used+time.monotonic_ns()-self.start))
        self.value['lease_ns'] = str(time.monotonic_ns())
        self.value['lease_utc_ns'] = str(time.time_ns())
        interrupted = any(a['cause'] in ('external_interruption', 'campaign_deadline') for a in self.value['attempts'][-1:])
        self.value['state'] = 'ready' if not interrupted and self.remaining_ns() and sys.exc_info()[0] is None else 'interrupted'
        self.save()
        self.lock.close()


class Stream:
    def __init__(self, path, identity):
        self.file = path.open('xb', buffering=0)
        self.identity = {key: identity[key] for key in ('campaign_id', 'series_id', 'attempt_id')}
        self.count = 0

    def write(self, record):
        value = {'schema': SCHEMA, **self.identity, 'sequence': str(self.count),
                 'clock_id': 'linux.CLOCK_MONOTONIC', 'time_ns': str(time.monotonic_ns()), **record}
        data = canonical(value)+b'\n'
        if self.file.write(data) != len(data):
            raise OSError('short evidence write; damaged tail retained')
        self.count += 1
        return value

    def flush(self):
        os.fsync(self.file.fileno())

    def close(self):
        try:
            self.flush()
        finally:
            self.file.close()


class Durability:
    """One flush in flight; disk latency must not starve reserve supervision.

    Records are appended unbuffered before submission and never removed. A
    final barrier waits for the in-flight flush and synchronizes the last prefix.
    Flush errors are propagated to the supervisor's persistence-failure path.
    """
    def __init__(self, sync):
        self.sync = sync
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="megascene-durability")
        self.pending = None

    def check(self):
        if self.pending is not None and self.pending.done():
            self.pending.result()
            self.pending = None

    def request(self):
        self.check()
        if self.pending is None:
            self.pending = self.executor.submit(self.sync)

    def finish(self):
        try:
            if self.pending is not None:
                self.pending.result()
            self.sync()
        finally:
            self.executor.shutdown(wait=True)


class Reference:
    MAGIC = 0x4d45474152454631
    SLOT = 1024

    def __init__(self, directory, identity, capacity):
        require(1 <= capacity <= 16384, 'unsupported shared recorder capacity')
        self.path = directory/'reference.shared'
        self.file = self.path.open('x+b')
        os.posix_fallocate(self.file.fileno(), 0, 32+capacity*self.SLOT)
        self.memory = mmap.mmap(self.file.fileno(), 0)
        self.memory[:32] = struct.pack('=QQQQ', self.MAGIC, capacity, 0, 0)
        self.memory.flush()
        self.capacity, self.count = capacity, 0
        self.stream = Stream(directory/'reference.jsonl', identity)
        self.identity = self.stream.identity
        self.base = ctypes.addressof(ctypes.c_char.from_buffer(self.memory))
        self.atomic = ctypes.CDLL('libatomic.so.1')
        self.acquire = getattr(self.atomic, '__atomic_load_8')
        self.acquire.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.acquire.restype = ctypes.c_uint64
        self.records = []
        self.frame_count = 0
        self.frame_end = None

    def drain(self, sync=True):
        while self.count < self.capacity:
            offset = 32+self.count*self.SLOT
            commit = self.acquire(self.base+offset, 2)  # __ATOMIC_ACQUIRE
            if not commit:
                break
            require(commit == self.count+1, 'reference committed sequence gap')
            raw = self.memory[offset+8:offset+self.SLOT].split(b'\0', 1)[0]
            require(raw.endswith(b'\n'), 'damaged committed reference')
            record = read_json(raw.decode())
            require(record['schema'] == SCHEMA and all(record[k] == v for k,v in self.identity.items()), 'reference identity/schema mismatch')
            require(integer(record['sequence']) == self.count, 'reference sequence gap/duplicate')
            require(record['clock_id'] == 'linux.CLOCK_MONOTONIC', 'reference clock mismatch')
            now = integer(record['time_ns'])
            require(now <= time.monotonic_ns(), 'reference timestamp in future')
            require(not self.records or now >= integer(self.records[-1]['time_ns']), 'reference time regressed')
            kind = record['record_type']
            require(kind in ('frame', 'edit_begin', 'edit', 'action'), 'unsupported reference record')
            integer(record['frame'])
            if kind in ('frame', 'edit'):
                begin, end = integer(record['begin_ns']), integer(record['end_ns'])
                require(begin <= end <= now and integer(record['duration_ns']) == end-begin, 'invalid reference interval')
            if kind == 'frame':
                require(integer(record['frame']) == self.frame_count, 'reference frame sequence gap')
                require(self.frame_end is None or record['begin_ns'] == self.frame_end, 'reference frame boundary gap')
            if kind == 'edit_begin':
                require(integer(record['begin_ns']) <= now, 'invalid edit start')
            if kind in ('action', 'edit', 'edit_begin'):
                integer(record['action'])
            if kind in ('action', 'edit'):
                require(type(record['accepted']) is bool, 'missing scalar action acceptance')
                integer(record['removed_cells'])
            # Preserve original worker timestamp and sequence. Slots are never
            # reused; a supervisor crash leaves committed shared bytes intact.
            # The supervisor's durability task flushes the append-only copy.
            self.stream.write(record)
            self.records.append(record)
            if kind == 'frame':
                self.frame_count += 1
                self.frame_end = record['end_ns']
            self.count += 1
        if sync:
            self.stream.flush()
        require(not self.acquire(self.base+24, 2), 'reference recorder overflow')
        return self.records

    def audit_tail(self):
        for n in range(self.count, self.capacity):
            require(not self.acquire(self.base+32+n*self.SLOT,2), 'lost committed reference after gap')
        written = self.acquire(self.base+16,2)
        require(written <= self.count <= written+1, 'reference header/commit count mismatch')

    def close(self):
        self.memory.flush()
        self.memory.close()
        self.file.close()
        self.stream.close()


class Tail:
    """Incremental JSONL parser; malformed/truncated bytes stay at original path."""
    def __init__(self, path, identity, compact_cpu=False):
        self.path, self.identity = path, identity
        self.compact_cpu = compact_cpu
        self.offset, self.pending, self.records = 0, b'', []
        self.error = None

    def drain(self, final=False):
        if self.error:
            return []
        fresh = []
        if self.path.exists():
            with self.path.open('rb') as file:
                file.seek(self.offset)
                self.pending += file.read()
                self.offset = file.tell()
            lines = self.pending.split(b'\n')
            self.pending = lines.pop()
            for line in lines:
                try:
                    r = read_json(line.decode())
                    require(r['schema'] == SCHEMA, 'unsupported stream schema')
                    require(all(r[k] == self.identity[k] for k in ('campaign_id','series_id','attempt_id')), 'stream identity mismatch')
                    require(integer(r['sequence']) == len(self.records), 'stream sequence gap/duplicate')
                    require(r['clock_id'] == 'linux.CLOCK_MONOTONIC', 'stream clock mismatch')
                    timestamp = integer(r['time_ns'])
                    require(not self.records or timestamp >= integer(self.records[-1]['time_ns']), 'stream time regressed')
                    # Raw checkpoints remain in the append-only file. The
                    # supervisor needs full frame records for the shared-recorder
                    # comparison, and only sequence/time metadata for other CPU
                    # records. Retaining every nested payload here causes large
                    # garbage-collection pauses that starve resource supervision.
                    kept = {k:r[k] for k in ("record_type", "sequence", "time_ns")} if self.compact_cpu and r["record_type"] != "frame" else r
                    self.records.append(kept)
                    fresh.append(kept)
                except (ValueError, KeyError, TypeError, UnicodeError) as exc:
                    self.error = f'{self.path.name}: {exc}'
                    break
        if final and self.pending:
            self.error = f'{self.path.name}: damaged tail ({len(self.pending)} bytes retained)'
        return fresh


def _resource_stop(record, now, device=None):
    if record.get('status') != 'measured':
        return 'monitoring_failure', record.get('reason', 'required counter unavailable')
    begin, end = integer(record['sample_begin_ns']), integer(record['sample_end_ns'])
    if begin > end or end > now or now-begin > POLICY['freshness_ns']:
        return 'monitoring_failure', 'required resource sample stale or invalid'
    if device and record['device'] != device:
        return 'monitoring_failure', 'resource device attribution mismatch'
    if record['record_type'] == 'host_sample':
        for field, comparison, cause in (
            ('rss_bytes', lambda n:n >= POLICY['rss_bytes'], 'process_rss_reserve'),
            ('available_ram_bytes', lambda n:n < POLICY['available_ram_bytes'], 'available_ram_reserve'),
            ('device_free_bytes', lambda n:n < POLICY['device_free_bytes'], 'device_free_reserve')):
            if comparison(integer(record[field])):
                return cause, f'{field}={record[field]} at {begin}'
    elif record['record_type'] == 'heap_sample':
        require(record['heaps'], 'missing heap samples')
        seen = set()
        for heap in record['heaps']:
            require(heap['heap'] not in seen, 'duplicate heap sample')
            seen.add(heap['heap'])
            used, budget = integer(heap['usage_bytes']), integer(heap['budget_bytes'])
            if not budget:
                return 'monitoring_failure', 'heap budget unavailable (zero)'
            if used*10 >= budget*9:
                return 'heap_budget_reserve', f"heap {heap['heap']}: {used}/{budget} at {begin}"
    else:
        return 'monitoring_failure', 'unknown required resource counter'
    return None


def resource_stop(record, now, device=None):
    try:
        return _resource_stop(record, now, device)
    except (ValueError, KeyError, TypeError) as exc:
        return 'monitoring_failure', 'invalid required resource sample: '+str(exc)


def host_record(line):
    try:
        result = read_json(line.decode())
        require(isinstance(result, dict), 'resource record must be an object')
        return result
    except (ValueError, UnicodeError) as exc:
        return {'record_type':'monitor_error', 'status':'collection_failure',
                'reason':'malformed monitor record: '+str(exc), 'damaged_hex':line.hex()}


def kill_tree(process, known=None):
    # Discover descendants as well as the isolated process group. A child that
    # creates a new group must not survive a stopped attempt.
    from megascene_monitor import resident_tree
    try:
        _, members = resident_tree(process.pid, known)
    except OSError:
        members = []
    for member in reversed(members):
        try:
            os.kill(int(member['pid']), signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def preflight(library, env, timeout=1):
    """Probe capability and device; probe heap usage never becomes worker usage."""
    script = '''import ctypes,sys
lib=ctypes.CDLL(sys.argv[1]); output=ctypes.create_string_buffer(16384)
rc=lib.voxel_mega_probe(output,len(output)); print(output.value.decode(),flush=True)
sys.exit(0 if rc else 2)
'''
    result = subprocess.run([sys.executable, '-c', script, str(library)], env=env,
                            capture_output=True, text=True, timeout=timeout)
    require(result.returncode == 0, 'preflight Vulkan monitor unavailable: '+result.stdout+result.stderr)
    value = read_json(result.stdout)
    value['scope'] = 'preflight_probe_process_only'
    return value


def supervise(command, cwd, env, destination, identity, config, remaining_ns,
              probe=None, monitor_command=None):
    """Common launched-worker boundary. Controlled fixtures supply monitor inputs,
    label their manifests synthetic, and use this exact persistence/stop path.
    """
    require((probe is None and monitor_command is None) or identity.get('synthetic') is True, 'controlled monitor inputs require a synthetic manifest')
    capacity = 1+int(config['warmup'])+int(config['frames'])+3*120
    reference = Reference(destination, identity, capacity)
    resources = Stream(destination/'resources.jsonl', identity)
    env = {**env, 'MEGASCENE_REFERENCE': str(reference.path), 'MEGASCENE_GO': str(destination/'worker.go'),
           'MEGASCENE_HEAPS': str(destination/'heaps.jsonl'), 'MEGASCENE_ALLOCATIONS': str(destination/'allocations.jsonl')}
    invocation = {'schema': SCHEMA, 'record_type': 'invocation', 'attempt_id': identity['attempt_id'],
                  'command': command, 'cwd': str(cwd), 'environment': {k:v for k,v in env.items() if k.startswith(('MEGASCENE_', 'VOXEL_', 'VK_'))},
                  'synthetic':identity.get('synthetic',False), 'clock_id': 'linux.CLOCK_MONOTONIC', 'policy': {k:str(v) for k,v in POLICY.items()},
                  'reference_capacity': str(capacity), 'reference_slot_bytes': str(Reference.SLOT)}
    snapshot(destination/'invocation.json', invocation)
    cause, reason, errors = 'normal_exit', 'process completed', []
    process, monitor = None, None
    start, last_frame = time.monotonic_ns(), None
    case_deadline = start+min(int(config['deadline_s'])*NS, POLICY['case_ns'])
    campaign_deadline = start+remaining_ns
    last_host, last_heap = None, None
    device = None
    host_pending = b''
    tails = {name: Tail(destination/f'{name}.jsonl', identity, compact_cpu=name=='cpu') for name in ('cpu','heaps','allocations')}
    loaded_objects = set()
    known_worker_pids = {}
    observed_resources = []
    def persist_files():
        for name in ('cpu.jsonl','heaps.jsonl','allocations.jsonl','stdout.log','stderr.log',
                     'reference.jsonl','reference.shared','resources.jsonl'):
            path = destination/name
            if path.exists():
                with path.open('rb') as f:
                    os.fsync(f.fileno())
    durability = Durability(persist_files)
    durability_complete = False
    def final_resource(sample):
        nonlocal cause, reason, last_host, last_heap
        observed_resources.append(sample)
        persisted = sample
        if sample.get('record_type') == 'heap_sample':
            persisted = sample | {'sequence':str(resources.count), 'source_sequence':sample['sequence'],
                                  'source_time_ns':sample['time_ns'], 'time_ns':str(time.monotonic_ns())}
        try:
            resources.write(persisted)
        except OSError as exc:
            errors.append('resource persistence failed: '+str(exc))
            if cause == 'normal_exit':
                cause, reason = 'persistence_failure', str(exc)
        stop = resource_stop(sample, time.monotonic_ns(), device)
        if stop and cause == 'normal_exit':
            cause, reason = stop
        if sample.get('status') == 'measured' and (not stop or stop[0] != 'monitoring_failure'):
            if sample['record_type'] == 'heap_sample':
                last_heap = integer(sample['sample_begin_ns'])
            else:
                last_host = integer(sample['sample_begin_ns'])

    old_handlers = {}
    interrupted = []
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        old_handlers[sig] = signal.signal(sig, lambda signum, _frame: interrupted.append(signum))
    try:
        with (destination/'stdout.log').open('xb', buffering=0) as out, (destination/'stderr.log').open('xb', buffering=0) as err:
            if not remaining_ns:
                cause, reason = 'campaign_deadline', 'campaign allowance exhausted before launch'
            else:
                try:
                    pre = probe if probe is not None else preflight(env['VOXEL_VULKAN_LIBRARY'], env, min(1, remaining_ns/NS))
                    resources.write({**pre, 'record_type': 'preflight_heap_sample'})
                    stop = resource_stop(pre, time.monotonic_ns())
                    if stop:
                        cause, reason = stop
                    device = pre['device']
                    # Obtain host/device preflight without launching the worker.
                    monitor_args = monitor_command or [sys.executable, str(cwd/'megascene_monitor.py')]
                    monitor = subprocess.Popen([*monitor_args, '0', device], stdout=subprocess.PIPE, stderr=err, env=env, start_new_session=True)
                    os.set_blocking(monitor.stdout.fileno(), False)
                    pre_start = time.monotonic_ns()
                    while cause == 'normal_exit' and last_host is None:
                        chunk = os.read(monitor.stdout.fileno(), 65536) if pipe_ready(monitor.stdout) else b''
                        host_pending += chunk
                        if b'\n' in host_pending:
                            line, host_pending = host_pending.split(b'\n',1)
                            host = host_record(line)
                            resources.write({**host, 'phase':'preflight'})
                            stop = resource_stop(host, time.monotonic_ns(), device)
                            if stop:
                                cause, reason = stop
                            else:
                                last_host = integer(host['sample_begin_ns'])
                        if interrupted:
                            cause, reason = 'external_interruption', f'supervisor signal {interrupted[0]}'
                        elif time.monotonic_ns()-pre_start > NS or monitor.poll() is not None:
                            cause, reason = 'monitoring_failure', 'required preflight host/device monitor unavailable'
                        time.sleep(.005)
                    kill_tree(monitor); monitor.stdout.close(); monitor = None
                except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
                    cause, reason = ('campaign_deadline' if time.monotonic_ns() >= campaign_deadline else 'monitoring_failure'), str(exc)
            if cause == 'normal_exit':
                start = time.monotonic_ns()
                case_deadline = start+min(int(config['deadline_s'])*NS, POLICY['case_ns'])
                if start >= campaign_deadline:
                    cause, reason = 'campaign_deadline', 'allowance exhausted during preflight'
                else:
                    process = subprocess.Popen(command, cwd=cwd, env=env, stdout=out, stderr=err, start_new_session=True)
                    monitor = subprocess.Popen([*monitor_args, str(process.pid), device], stdout=subprocess.PIPE, stderr=err, env=env, start_new_session=True)
                    os.set_blocking(monitor.stdout.fileno(), False)
                    last_host, host_pending = None, b''
            last_sync = 0
            while process is not None:
                now = time.monotonic_ns()
                if pipe_ready(monitor.stdout):
                    host_pending += os.read(monitor.stdout.fileno(), 65536)
                lines = host_pending.split(b'\n'); host_pending = lines.pop()
                for line in lines:
                    host = host_record(line)
                    resources.write(host)
                    observed_resources.append(host)
                    known_worker_pids.update({int(m['pid']):m['start_ticks'] for m in host.get('members',[])})
                    stop = resource_stop(host, time.monotonic_ns(), device)
                    if stop and cause == 'normal_exit':
                        cause, reason = stop
                    if host.get('status') == 'measured' and (not stop or stop[0] != 'monitoring_failure'):
                        last_host = integer(host['sample_begin_ns'])
                for heap in tails['heaps'].drain():
                    resources.write(heap | {'sequence': str(resources.count), 'source_sequence': heap['sequence'], 'source_time_ns':heap['time_ns'], 'time_ns':str(time.monotonic_ns())})
                    observed_resources.append(heap)
                    stop = resource_stop(heap, time.monotonic_ns(), device)
                    if stop and cause == 'normal_exit':
                        cause, reason = stop
                    if heap.get('status') == 'measured' and (not stop or stop[0] != 'monitoring_failure'):
                        last_heap = integer(heap['sample_begin_ns'])
                tails['cpu'].drain(); tails['allocations'].drain()
                reference.drain(sync=False)
                durability.check()
                completed = [r for r in reference.records if r['record_type'] in ('frame','edit')]
                if completed:
                    last_frame = integer(completed[-1]['end_ns'])
                for tail in tails.values():
                    if tail.error:
                        raise ValueError(tail.error)
                if last_host is not None and last_heap is not None and cause == 'normal_exit' and not (destination/'worker.go').exists():
                    (destination/'worker.go').touch(exist_ok=False)
                now = time.monotonic_ns()
                # First observed cause is retained; resulting SIGKILL is separate.
                if cause == 'normal_exit':
                    deadlines = [(campaign_deadline,'campaign_deadline'),(case_deadline,'case_deadline'),
                                 (start+POLICY['startup_ns'],'startup_deadline') if last_frame is None else (last_frame+POLICY['watchdog_ns'],'completion_watchdog')]
                    deadline, deadline_cause = min(deadlines)
                    if interrupted:
                        cause, reason = 'external_interruption', f'supervisor signal {interrupted[0]}'
                    elif now >= deadline:
                        cause, reason = deadline_cause, f'deadline_ns={deadline}; observed_ns={now}'
                    elif any(now-(sample if sample is not None else start) > NS for sample in (last_host,last_heap)):
                        cause, reason = 'monitoring_failure', 'required resource data more than one second old'
                    elif monitor.poll() is not None and process.poll() is None:
                        cause, reason = 'monitoring_failure', 'host/device monitor exited'
                if now-last_sync >= POLICY['cadence_ns']:
                    durability.request(); last_sync = now
                    try:
                        maps = Path(f'/proc/{process.pid}/maps').read_text()
                        loaded_objects.update(line.split(None,5)[5] for line in maps.splitlines() if len(line.split(None,5)) == 6 and line.split(None,5)[5].startswith('/'))
                    except FileNotFoundError:
                        pass
                if cause != 'normal_exit' or process.poll() is not None:
                    kill_tree(process, known_worker_pids)
                    break
                time.sleep(.01)
    except (OSError, ValueError, KeyError, TypeError, UnicodeError) as exc:
        if cause == 'normal_exit':
            cause, reason = 'persistence_failure', str(exc)
        errors.append(str(exc))
    finally:
        if process is not None:
            kill_tree(process, known_worker_pids)
        ended = time.monotonic_ns()
        if monitor is not None:
            kill_tree(monitor)
            # Drain pipe bytes already committed by the isolated monitor, even
            # if the worker exited between two supervisor iterations.
            while True:
                chunk = os.read(monitor.stdout.fileno(), 65536)
                if not chunk:
                    break
                host_pending += chunk
            monitor.stdout.close()
            lines = host_pending.split(b'\n'); host_pending = lines.pop()
            for line in lines:
                try:
                    host = host_record(line)
                    final_resource(host)
                except (ValueError, KeyError, TypeError, UnicodeError) as exc:
                    errors.append('host monitor damaged record: '+str(exc))
            if host_pending:
                (destination/'monitor.damaged').write_bytes(host_pending)
                errors.append('host monitor damaged tail retained')
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)
        try:
            reference.drain(sync=False)
            reference.audit_tail()
        except (OSError, ValueError, KeyError, TypeError, UnicodeError) as exc:
            errors.append(str(exc))
            if cause == 'normal_exit':
                cause, reason = 'persistence_failure', str(exc)
        for name, tail in tails.items():
            fresh = tail.drain(final=True)
            if name == 'heaps':
                for heap in fresh:
                    final_resource(heap)
            if tail.error:
                errors.append(tail.error)
        try:
            durability.finish()
            durability_complete = True
        except OSError as exc:
            errors.append('required persistence failed: '+str(exc))
            if cause == 'normal_exit':
                cause, reason = 'persistence_failure', str(exc)
    code = process.returncode if process is not None else None
    allocations = tails['allocations'].records
    try:
        ledger_summary = audit_allocations(allocations, normal=code == 0) if process is not None else None
    except (ValueError, KeyError, TypeError) as exc:
        errors.append('allocation evidence: '+str(exc))
        ledger_summary = None
    if cause == 'normal_exit':
        if any(r['record_type'] == 'allocation_failed' or r.get('vk_result') in ('-1','-2') for r in allocations):
            cause, reason = 'allocation_error', 'explicit failed Vulkan allocation in allocations.jsonl'
        elif any(r.get('vk_result') == '-4' for r in allocations):
            cause, reason = 'device_loss', 'explicit VK_ERROR_DEVICE_LOST in allocations.jsonl'
        elif any(r['record_type'] == 'window_closed' for r in tails['cpu'].records):
            cause, reason = 'external_interruption', 'window closed'
        elif code:
            cause, reason = ('unexplained_crash' if code < 0 else 'worker_error'), 'worker exit; no exhaustion inference from signal'
        elif errors:
            cause, reason = 'persistence_failure', errors[0]
    stderr_text = (destination/'stderr.log').read_text(errors='replace')
    if cause == 'worker_error' and any(marker in stderr_text for marker in (
            'Megascene evidence persistence failed', 'Megascene native persistence failure',
            'cannot close Megascene evidence', 'Megascene reference overflow')):
        cause, reason = 'persistence_failure', 'worker reported required recorder/persistence failure'
    # Evaluate every final sample for reserves and intrinsic validity. Historical
    # samples retain their collection time, not the postmortem drain time.
    valid_resources = []
    for sample in observed_resources:
        try:
            stop = resource_stop(sample, integer(sample.get('sample_end_ns', sample.get('time_ns', '0'))), device)
            if stop and cause == 'normal_exit':
                cause, reason = stop
            if not stop or stop[0] != 'monitoring_failure':
                valid_resources.append(sample)
        except (ValueError, KeyError, TypeError) as exc:
            errors.append('invalid resource sample: '+str(exc))
            if cause == 'normal_exit':
                cause, reason = 'monitoring_failure', str(exc)
    resource_summary = {}
    for kind in ('host_sample', 'heap_sample'):
        samples = [r for r in valid_resources if r.get('record_type') == kind and r.get('status') == 'measured']
        stamps = [int(r['sample_begin_ns']) for r in samples]
        gaps = [b-a for a,b in zip([start]+stamps, stamps)]
        if process is not None:
            gaps.append(max(0, ended-(stamps[-1] if stamps else start)))
        resource_summary[kind] = {'samples':str(len(samples)), 'max_observed_gap_ns':str(max(gaps, default=0))}
        if process is not None and (not stamps or any(gap < 0 or gap > NS for gap in gaps)) and cause == 'normal_exit':
            cause, reason = 'monitoring_failure', 'missing/stale required '+kind
    cpu_frames = [r for r in tails['cpu'].records if r['record_type'] == 'frame']
    refs = [r for r in reference.records if r['record_type'] == 'frame']
    if process is not None:
        if (config.get('calibration_mode') != 'off' or env.get('MEGASCENE_VALIDATE')) and [
                (r['frame'],r['begin_ns'],r['end_ns']) for r in cpu_frames] != [
                (r['frame'],r['begin_ns'],r['end_ns']) for r in refs]:
            errors.append('CPU/reference committed frame mismatch')
        if not allocations:
            errors.append('allocation ledger unavailable')
        if last_host is None or last_heap is None:
            errors.append('required worker resource evidence unavailable')
    if errors and cause == 'normal_exit':
        cause, reason = 'persistence_failure', errors[0]
    invocation.update(launch_ns=str(start) if process is not None else None, process_end_ns=str(ended),
                      loaded_objects=sorted(loaded_objects), loaded_object_scope='sampled /proc maps; host graphics stack required',
                      termination={'cause':cause,'reason':reason,'exit_code': str(code) if code is not None and code >= 0 else None,
                                   'signal':str(-code) if code is not None and code < 0 else None})
    evidence = {'schema': SCHEMA, 'record_type':'supervision', **resources.identity,
                'termination':invocation['termination'], 'launch_ns':str(start), 'errors':errors,
                'reference_records':str(reference.count), 'reference_capacity':str(capacity),
                'shared_committed_slots':str(sum(bool(reference.acquire(reference.base+32+i*Reference.SLOT,2)) for i in range(capacity))),
                'shared_header_records':str(reference.acquire(reference.base+16,2)),
                'completed_frame_prefix':str(len(refs)), 'completed_actions':str(sum(r['record_type']=='action' for r in reference.records)),
                'last_host_sample_ns':str(last_host) if last_host is not None else None,
                'last_heap_sample_ns':str(last_heap) if last_heap is not None else None,
                'allocation_ledger':ledger_summary,
                'synthetic':identity.get('synthetic',False),
                'resource_cadence':resource_summary,
                'durability':{'mode':'single_background_flush', 'final_barrier':durability_complete},
                'observed_maxima':{field: str(max(int(r[field]) for r in valid_resources if field in r)) for field in ('rss_bytes',) if any(field in r for r in valid_resources)},
                'observed_minima':{field: str(min(int(r[field]) for r in valid_resources if field in r)) for field in ('available_ram_bytes','device_free_bytes') if any(field in r for r in valid_resources)},
                'heap_observed_maxima':{heap: str(max(int(h['usage_bytes']) for r in valid_resources for h in r.get('heaps',[]) if h['heap'] == heap))
                                        for heap in {h['heap'] for r in valid_resources for h in r.get('heaps',[])}},
                'resource_samples':str(resources.count), 'allocation_records':str(len(allocations)),
                'resource_maxima_scope':'observed samples; allocation peaks are exact ledger totals, never residency'}
    for recorder in (reference, resources):
        try:
            recorder.close()
        except OSError as exc:
            errors.append('recorder close failed: '+str(exc))
            if cause == 'normal_exit':
                evidence['termination'].update(cause='persistence_failure',reason=str(exc))
    snapshot(destination/'invocation.json', invocation)
    snapshot(destination/'supervision.json', evidence)
    return evidence


def pipe_ready(pipe):
    import select
    return bool(select.select([pipe],[],[],0)[0])


def audit_allocations(records, normal=False):
    require(records and records[0]['record_type'] == 'ledger_start', 'missing ledger initialization')
    require(records[0]['live_bytes'] == records[0]['peak_bytes'] == '0', 'nonzero initial ledger')
    live, peak, next_id = 0, 0, 1
    owned, heaps, peaks = {}, {}, {}
    device = None
    for r in records[1:]:
        kind = r['record_type']
        if kind == 'vulkan_error':
            require(int(r['vk_result']) != 0 and r['operation'], 'invalid Vulkan failure')
            continue
        require(kind in ('allocate','free','allocation_failed'), 'unexpected ledger event')
        ident, size, heap = integer(r['allocation_id']), integer(r['size_bytes']), integer(r['heap'])
        integer(r['memory_type'])
        require(size > 0, 'zero allocation size')
        device = r['device'] if device is None else device
        require(r['device'] == device, 'allocation device changed')
        if kind != 'free':
            require(ident == next_id, 'allocation identity gap/duplicate')
            next_id += 1
        if kind == 'allocate':
            require(r['vk_result'] == '0', 'successful allocation has error status')
            owned[ident] = (size,heap,r['memory_type'])
            live += size; heaps[heap] = heaps.get(heap,0)+size
        elif kind == 'free':
            require(owned.pop(ident,None) == (size,heap,r['memory_type']), 'free identity/size/type mismatch')
            require(r['vk_result'] == '0', 'invalid free result')
            live -= size; heaps[heap] -= size
        else:
            require(int(r['vk_result']) != 0, 'failed allocation has successful result')
        peak = max(peak,live); peaks[heap] = max(peaks.get(heap,0),heaps.get(heap,0))
        require((r['live_bytes'],r['peak_bytes'],r['heap_live_bytes'],r['heap_peak_bytes']) ==
                tuple(map(str,(live,peak,heaps.get(heap,0),peaks[heap]))), 'ledger totals mismatch')
    if normal:
        require(not owned, 'normal teardown left live explicit allocations')
    return {'live_bytes':str(live),'peak_bytes':str(peak),'live_allocations':str(len(owned)),
            'scope':'explicit Vulkan allocations; not residency or heap budgets'}
