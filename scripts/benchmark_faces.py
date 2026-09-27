#!/usr/bin/env python3
"""Profile face-builder work for the six fixed Light Atelier cuts."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
EXHIBITS = ('Suzanne', 'Oculus', 'Twist')
FIELDS = ('ordinal', 'body_id', 'removed_cells', 'carve_us', 'connectivity_us',
          'surface_us', 'finalize_us', 'audit_us', 'cuboids', 'candidate_faces',
          'tree_nodes', 'cuboid_candidates', 'face_checks', 'face_clips',
          'output_faces', 'reference_faces')


def parse_rows(output):
    cuts = []
    for row in csv.reader(output.splitlines()):
        if len(row) != len(FIELDS) + 1 or row[0] != 'face_build':
            raise ValueError(f'Unexpected profiler row: {row}')
        values = [int(value) for value in row[1:]]
        if any(value < 0 or value > 0xffffffff for value in values):
            raise ValueError(f'Invalid profiler counts: {row}')
        cut = dict(zip(FIELDS, values))
        if (cut['ordinal'] != len(cuts) or cut['candidate_faces'] != 6 * cut['cuboids']
                or cut['face_clips'] > cut['face_checks']
                or cut['face_checks'] > cut['cuboid_candidates'] * cut['candidate_faces']
                or min(cut['removed_cells'], cut['cuboids'], cut['face_checks'],
                       cut['face_clips'], cut['output_faces'], cut['reference_faces']) == 0):
            raise ValueError(f'Inconsistent face-builder sample: {row}')
        cut['exhibit'] = EXHIBITS[cut['ordinal'] % len(EXHIBITS)]
        cut['cut_number'] = cut['ordinal'] // len(EXHIBITS) + 1
        for field in ('carve', 'connectivity', 'surface', 'finalize', 'audit'):
            cut[f'{field}_ms'] = cut[f'{field}_us'] / 1000
        cuts.append(cut)
    if len(cuts) != 6:
        raise ValueError(f'Expected six profiled cuts, got {len(cuts)}')
    return cuts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('build/faces'))
    parser.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error('timeout must be positive')
    out = args.output if args.output.is_absolute() else ROOT / args.output
    out.mkdir(parents=True, exist_ok=True)
    binary = ROOT / 'build/atelier-face-profile'
    binary.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.pop('CUDA_HOME', None)
    version = subprocess.check_output(['bend', 'version'], text=True).strip()
    if version != 'bend 2.0.31':
        parser.error('this benchmark requires Bend 2.0.31')
    subprocess.run(['bend', 'src/face_profile.bend', '-o', str(binary)], cwd=ROOT,
                   env=env, check=True, timeout=args.timeout)
    run = subprocess.run([str(binary)], cwd=ROOT, env=env, capture_output=True,
                         text=True, timeout=args.timeout)
    (out / 'raw.csv').write_text(','.join(('tag', *FIELDS)) + '\n' + run.stdout)
    (out / 'stderr.log').write_text(run.stderr)
    if run.returncode:
        raise RuntimeError(f'Face profiler exited {run.returncode}: {run.stderr}')
    cuts = parse_rows(run.stdout)
    sources = [p for folder in ('src', 'scripts') for p in sorted((ROOT / folder).rglob('*'))
               if p.is_file() and '__pycache__' not in p.parts]
    report = {
        'metadata': {
            'date': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
            'bend': version,
            'git_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                                                    text=True).strip(),
            'working_tree_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
            'source_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in sources},
            'timing_scope': 'Headless CPU Bend edit stages use the production local face builder and construct cached Bend vertices. The counted full-face diagnostic runs after each timed edit; audit_ms is separate and should not be added to surface_ms.',
            'count_scope': 'tree_nodes counts visited tree nodes including pruned nodes; cuboid_candidates counts reached leaves; face_checks counts face.covered calls; face_clips counts face.subtract calls. output_faces counts the full diagnostic rebuild and reference_faces counts the local production rebuild. Their surface coverage, sides, and materials are checked for equivalence; rectangle counts may differ.',
        },
        'cuts': cuts,
        'exhibits': {name: {
            'surface_ms_total': sum(c['surface_ms'] for c in cuts if c['exhibit'] == name),
            'face_checks_total': sum(c['face_checks'] for c in cuts if c['exhibit'] == name),
            'face_clips_total': sum(c['face_clips'] for c in cuts if c['exhibit'] == name),
        } for name in EXHIBITS},
        'pass': True,
    }
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    for cut in cuts:
        print(f"{cut['exhibit']} cut {cut['cut_number']}: surface {cut['surface_ms']:.3f} ms, "
              f"{cut['cuboids']} cuboids, {cut['face_checks']} face checks, "
              f"{cut['face_clips']} clips, {cut['reference_faces']} local faces "
              f"({cut['output_faces']} full rebuild)", flush=True)
    print(f'Report: {out / "report.json"}', flush=True)


if __name__ == '__main__':
    main()
