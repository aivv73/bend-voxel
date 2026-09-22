#!/usr/bin/env python3
"""Diagnostic CPU/CUDA sweep; never substitutes for forced-CUDA acceptance."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time

from benchmark import parse_run
from snapshot import decode_snapshot

ROOT = Path(__file__).resolve().parents[1]
TICKS = (0, 60, 216, 396, 408, 540, 1140)


def schedule(threads, rounds):
    """Adjacent backend pairs; reverse both thread and backend order each round."""
    return [dict(round=r+1, threads=t, backend=b)
            for r in range(rounds)
            for t in (threads if r % 2 == 0 else threads[::-1])
            for b in (('cpu', 'cuda') if r % 2 == 0 else ('cuda', 'cpu'))]


def command(binary, config):
    return [str(ROOT/'build'/binary), '--gpu', 'off' if config['backend'] == 'cpu' else 'on',
            '--threads', str(config['threads'])]


def capture(cmd):
    return subprocess.check_output(cmd, cwd=ROOT, text=True).strip()


def fingerprints():
    paths = [p for folder in ('src', 'scripts', 'tests') for p in (ROOT/folder).rglob('*')
             if p.is_file() and '__pycache__' not in p.parts]
    paths += [ROOT/'build'/name for name in ('voxel-demo', 'voxel-demo.gpu', 'voxel-snapshot', 'voxel-snapshot.gpu')]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def run_logged(cmd, env, log, timeout):
    started = time.monotonic()
    error = None
    with log.open('w') as stdout, log.with_suffix('.stderr').open('w') as stderr:
        try:
            code = subprocess.run(cmd, cwd=ROOT, env=env, stdout=stdout, stderr=stderr, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            code, error = -1, f'Timeout after {timeout} seconds'
    return dict(command=cmd, exit_code=code, wall_seconds=time.monotonic()-started, error=error)


def summarize(runs):
    groups = {}
    for run in runs:
        groups.setdefault((run['backend'], run['threads']), []).append(run)
    return [dict(backend=b, threads=t, runs=len(rs),
                 valid=all(r['workload_pass'] and r['instrumentation_pass'] for r in rs),
                 frame_p95_ms=[r['frames']['p95_ms'] for r in rs],
                 cut_p95_ms=[r['cuts']['p95_ms'] for r in rs],
                 median_frame_p95_ms=statistics.median(r['frames']['p95_ms'] for r in rs)
                 if all(r['frames']['p95_ms'] is not None for r in rs) else None)
            for (b, t), rs in groups.items()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--threads', nargs='+', type=int, default=[1, 2, 4, 6, 12])
    parser.add_argument('--rounds', type=int, default=2)
    parser.add_argument('--output', type=Path, default=ROOT/'build/backend-comparison')
    args = parser.parse_args()
    if args.rounds < 2 or any(t < 1 for t in args.threads) or len(set(args.threads)) != len(args.threads):
        parser.error('use at least two rounds and unique positive thread counts')
    out = args.output.resolve()
    if out.exists() and any(out.iterdir()):
        parser.error('output directory must be empty (preserve previous evidence)')
    out.mkdir(parents=True, exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith('VOXEL_')}
    plan = schedule(args.threads, args.rounds)
    report = dict(metadata=dict(date=time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        bend=capture(['bend', 'version']), git_revision=capture(['git', 'rev-parse', 'HEAD']),
        working_tree_dirty=bool(capture(['git', 'status', '--porcelain'])),
        fingerprints=fingerprints(), cpu=capture(['lscpu']),
        gpu=capture(['nvidia-smi', '--query-gpu=name,driver_version,memory.total', '--format=csv,noheader']),
        cpu_affinity=sorted(os.sched_getaffinity(0)),
        display=env.get('DISPLAY'), resolution=[640, 360], warmup_seconds=5, measured_seconds=60),
        schedule=plan, snapshots=[], runs=[], status='running',
        note='Diagnostic only. Identical binaries, explicit threads and GPU mode. Fixed-clock snapshots compare decoded pixels, HUD and recorded state; these are not full-world equivalence proofs. Windowed replay uses wall-clock physics steps. Stage cuda_rendering means CPU rendering when --gpu off. No acceptance decision is made here.')

    def save():
        report['summary'] = summarize(report['runs'])
        temp = out/'report.tmp'
        temp.write_text(json.dumps(report, indent=2)+'\n')
        temp.replace(out/'report.json')

    save()
    # Complete every correctness probe before any timed run, avoiding concurrent rendering.
    references = {}
    for config in plan[:2*len(args.threads)]:
        folder = out/f"snapshots-{config['backend']}-t{config['threads']}"
        folder.mkdir()
        for tick in TICKS:
            base = folder/f'tick-{tick:04d}'
            raw = base.with_suffix('.tree')
            snapshot_env = {k: v for k, v in env.items() if k != 'DISPLAY'}
            result = run_logged(command('voxel-snapshot', config),
                                {**snapshot_env, 'VOXEL_SNAPSHOT_TICK': str(tick)}, raw, 180)
            result.update(config, tick=tick)
            try:
                if result['exit_code'] != 0:
                    raise ValueError('Snapshot process failed')
                data, state = decode_snapshot(raw.read_text())
                if state['tick'] != tick:
                    raise ValueError('Snapshot tick differs from request')
                reference = references.setdefault(tick, state)
                result.update(match=state == reference,
                              differing_fields=[k for k in state if state[k] != reference[k]], metadata=state)
                base.with_suffix('.png').write_bytes(data)
            except (ValueError, IndexError) as exc:
                result.update(match=False, error=str(exc))
            base.with_suffix('.tree.gz').write_bytes(gzip.compress(raw.read_bytes(), mtime=0))
            raw.unlink()
            report['snapshots'].append(result)
            save()
        print(f"Snapshot checks: {config['backend']} threads={config['threads']}", flush=True)
    report['snapshot_match'] = all(s['match'] for s in report['snapshots'])
    if not report['snapshot_match']:
        report['status'] = 'snapshot_mismatch'
        save()
        return 1
    for index, config in enumerate(plan, 1):
        print(f"Run {index}/{len(plan)}: {config}", flush=True)
        base = out/f"run-{index:02d}-{config['backend']}-t{config['threads']}"
        log = base.with_suffix('.csv')
        telemetry = capture(['nvidia-smi', '--query-gpu=temperature.gpu,power.draw,utilization.gpu,clocks.sm', '--format=csv'])
        result = run_logged(command('voxel-demo', config), {**env, 'VOXEL_BENCH': '1'}, log, 180)
        with log.open() as stream:
            parsed = parse_run(stream, result['exit_code'])
        result.update(parsed, **config, sequence=index, gpu_before=telemetry,
                      load_after=list(os.getloadavg()))
        report['runs'].append(result)
        save()
        print(f"  frame p95={result['frames']['p95_ms']} ms; cut p95={result['cuts']['p95_ms']} ms; workload={result['workload_pass']}", flush=True)
    report['fingerprints_unchanged'] = fingerprints() == report['metadata']['fingerprints']
    report['diagnostic_pass'] = (report['fingerprints_unchanged'] and report['snapshot_match']
        and all(r['workload_pass'] and r['instrumentation_pass'] for r in report['runs']))
    report['status'] = 'complete'
    save()
    return 0 if report['diagnostic_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
