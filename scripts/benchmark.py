#!/usr/bin/env python3
"""Run the agreed CUDA/window workload and evaluate each run independently."""
import argparse, csv, hashlib, json, math, os, pathlib, subprocess, sys, time
root = pathlib.Path(__file__).resolve().parent.parent
def quantile(values, p):
    return sorted(values)[max(0, math.ceil(len(values) * p) - 1)] if values else None
def stats(values):
    return {'samples': len(values), 'p50_ms': quantile(values, .5), 'p95_ms': quantile(values, .95), 'p99_ms': quantile(values, .99), 'max_ms': max(values) if values else None, 'mean_ms': sum(values)/len(values) if values else None, 'total_ms': sum(values)}
STAGES = ('carving', 'connectivity', 'surface_generation', 'edit_finalization', 'update_other', 'scene_preparation',
          'cuda_rendering', 'cell_disposal', 'presentation', 'overhead')


def parse_run(lines, exit_code=0):
    frames, stages, edits, cuts, attempts, errors = {}, {}, [], [], [], []
    for row in csv.reader(lines):
        if not row:
            continue
        tag = row[0]
        if tag not in ('frame', 'stage', 'edit', 'cut', 'attempt'):
            errors.append(f'Unexpected row: {row}')
            continue
        try:
            v = [int(x) for x in row[1:]]
            expected = {'frame': 4, 'stage': 11, 'edit': 8, 'cut': 4, 'attempt': 4}[tag]
            if len(v) != expected or any(x < 0 or x > 0xffffffff for x in v):
                raise ValueError('invalid fields')
            if tag in ('frame', 'stage'):
                target = frames if tag == 'frame' else stages
                if v[0] in target:
                    errors.append(f'Duplicate {tag} at {v[0]}')
                target[v[0]] = v[1:]
            elif tag == 'edit':
                edits.append(v)
            elif tag == 'cut':
                cuts.append(v)
            else:
                attempts.append(v)
        except ValueError as exc:
            errors.append(f'Invalid {tag}: {exc}')
    if frames.keys() != stages.keys():
        errors.append('Frame/stage timestamps do not match')
    previous = 0
    for t, (duration, _, _) in frames.items():
        if t - previous != duration:
            errors.append(f'End-to-end interval mismatch at {t}')
        previous = t
        if t in stages and sum(stages[t]) != duration:
            errors.append(f'Stage sum mismatch at {t}')
        own = [e for e in edits if e[0] == t]
        if t in stages and [sum(e[i] for e in own) for i in (4, 5, 6, 7)] != stages[t][:4]:
            errors.append(f'Edit/stage mismatch at {t}')
    if any(e[0] not in frames for e in edits):
        errors.append('Orphan edit')
    # Match every edit with its original complete latency sample, including rejected attempts.
    from collections import Counter
    if Counter((e[1], e[3], e[2]) for e in edits) != Counter((e[0], e[2], e[3]) for e in cuts + attempts):
        errors.append('Edit/latency samples do not match')
    if any(e[2] != 1 for e in cuts):
        errors.append('Non-accepted cut row')
    measured = [t for t in frames if t >= 5_000_000]
    f = [frames[t][0] / 1000 for t in measured]
    c = [v[1] / 1000 for v in cuts]
    a = [{'latency_ms': v[1]/1000, 'status': v[2], 'kind': v[3]} for v in attempts]
    complete = bool(measured) and measured[0] < 5_250_000 and measured[-1] >= 65_000_000
    attempts_ok = len(a) == 6 and all(v['status'] == 2 for v in a) and sum(v['kind'] == 112 for v in a) == 3 and sum(v['kind'] == 113 for v in a) == 3
    workload = exit_code == 0 and complete and len(c) == 33 and attempts_ok and max((v[2] for v in frames.values()), default=0) > 0
    instrumentation = bool(frames) and not errors
    performance = bool(f and c) and quantile(f, .95) <= 33.3 and quantile(c, .95) <= 100 and max(c) <= 250
    return {'exit_code': exit_code, 'complete_window': complete, 'expected_accepted_cuts': 33,
            'raw_frame_samples': len(frames), 'warmup_frame_samples': len(frames)-len(measured),
            'frames': stats(f), 'cuts': stats(c), 'protected_and_empty_attempts': a,
            'max_bodies': max((v[2] for v in frames.values()), default=0),
            'stages': {name: stats([stages[t][i]/1000 for t in measured if t in stages]) for i, name in enumerate(STAGES)},
            'active_edits': {name: stats([e[i]/1000 for e in edits if e[0] >= 5_000_000 and e[3] == 1]) for name, i in [('carving', 4), ('connectivity', 5), ('surface_generation', 6), ('edit_finalization', 7)]},
            'instrumentation_pass': instrumentation, 'instrumentation_errors': errors,
            'attempts_pass': attempts_ok, 'workload_pass': workload, 'performance_pass': performance,
            'pass': workload and instrumentation and performance}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--output', default='build/benchmarks')
    args = parser.parse_args()
    if args.runs < 1:
        parser.error('--runs must be positive')
    out = root / args.output
    out.mkdir(parents=True, exist_ok=True)
    metadata = {'date': time.strftime('%Y-%m-%dT%H:%M:%S%z'), 'bend': subprocess.check_output(['bend', 'version'], text=True).strip(), 'git_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(), 'working_tree_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root)), 'resolution': [640, 360], 'backend': 'forced CUDA (--gpu on)', 'warmup_seconds': 5, 'measured_seconds': 60, 'gpu': subprocess.check_output(['nvidia-smi', '--query-gpu=name,driver_version,memory.total', '--format=csv,noheader'], text=True).strip()}
    metadata['source_sha256'] = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for folder in ('src', 'scripts', 'tests') for p in sorted((root / folder).rglob('*')) if p.is_file() and '__pycache__' not in p.parts}
    metadata['cpu'] = subprocess.check_output(['lscpu'], text=True)
    metadata['cuda'] = subprocess.check_output([str(pathlib.Path(os.environ.get('CUDA_HOME', '/opt/cuda')) / 'bin/nvcc'), '--version'], text=True)
    results = []
    for run in range(1, args.runs + 1):
        print(f'CUDA benchmark {run}/{args.runs}: 5 s warm-up + 60 s measured', flush=True)
        log = out / f'run-{run}.csv'
        with log.open('w') as stream:
            proc = subprocess.run([str(root / 'build/voxel-demo'), '--gpu', 'on'], cwd=root, env={**os.environ, 'VOXEL_BENCH': '1'}, stdout=stream, stderr=subprocess.PIPE, text=True, timeout=180)
        (out / f'run-{run}.stderr').write_text(proc.stderr)
        with log.open() as stream:
            result = {'run': run, **parse_run(stream, proc.returncode)}
        results.append(result)
        print(json.dumps(result, indent=2), flush=True)
    report = {'metadata': metadata, 'runs': results, 'acceptance_pass': args.runs == 3 and all(r['pass'] for r in results), 'note': 'Desktop visual/input and correctness checks are separate requirements.'}
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Report: {out / "report.json"}')
    sys.exit(0 if report['acceptance_pass'] else 1)

if __name__ == '__main__':
    main()
