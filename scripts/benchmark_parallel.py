#!/usr/bin/env python3
"""Compare two builds of tests/parallel-profile.bend in alternating order."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess

from benchmark_faces import parse_rows

ROOT = Path(__file__).resolve().parent.parent
STAGES = ('carve', 'connectivity', 'surface', 'finalize')


def sample(binary, threads, output, timeout):
    run = subprocess.run([str(binary), '--threads', str(threads), '--gpu', 'off'],
                         cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    output.with_suffix('.csv').write_text(run.stdout)
    output.with_suffix('.stderr').write_text(run.stderr)
    run.check_returncode()
    first, _, rows = run.stdout.partition('\n')
    tag, init = first.split(',')
    if tag != 'init' or int(init) < 0:
        raise ValueError(f'Invalid initialization row: {first}')
    cuts = parse_rows(rows)
    # All non-timing output must be identical, including surface work counts.
    signature = [{k: v for k, v in cut.items()
                  if not k.endswith(('_us', '_ms'))} for cut in cuts]
    timing = {stage: sum(c[f'{stage}_ms'] for c in cuts) for stage in STAGES}
    timing['init'] = int(init) / 1000
    timing['edit'] = sum(timing[stage] for stage in STAGES)
    return {'ms': timing, 'cuts': cuts}, signature


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--runs', type=int, default=4)
    parser.add_argument('--threads', nargs='+', type=int, default=[1, 6, 12])
    parser.add_argument('--timeout', type=int, default=180)
    parser.add_argument('--output', type=Path, default=Path('build/parallel'))
    args = parser.parse_args()
    if args.runs < 2 or args.timeout < 1 or any(t < 1 for t in args.threads):
        parser.error('use at least two runs, positive timeout and thread counts')
    binaries = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    args.output.mkdir(parents=True, exist_ok=True)
    report = {'binaries': {name: {'path': str(path),
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
                for name, path in binaries.items()}, 'runs': args.runs,
              'scope': 'Initialization and sums over six production Atelier edits; '
                       'full-face correctness audits run outside timed stages.',
              'threads': {}}
    reference = None
    for threads in args.threads:
        samples = {name: [] for name in binaries}
        # Warm both executables before measured AB / BA pairs.
        for name in binaries:
            _, signature = sample(binaries[name], threads,
                args.output / f't{threads}-{name}-warmup', args.timeout)
            if reference is None:
                reference = signature
            if signature != reference:
                raise ValueError('Baseline/candidate correctness counters differ')
        for index in range(args.runs):
            order = list(binaries) if index % 2 == 0 else list(reversed(binaries))
            for name in order:
                result, signature = sample(binaries[name], threads,
                    args.output / f't{threads}-{name}-{index}', args.timeout)
                if signature != reference:
                    raise ValueError('Baseline/candidate correctness counters differ')
                samples[name].append(result)
        medians = {name: {stage: statistics.median(s['ms'][stage] for s in rows)
                         for stage in (*STAGES, 'init', 'edit')}
                   for name, rows in samples.items()}
        report['threads'][threads] = {'samples': samples, 'median_ms': medians}
        print(json.dumps({'threads': threads, 'median_ms': medians}), flush=True)
        (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
