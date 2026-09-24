#!/usr/bin/env python3
"""Sweep voxel scene density and Vulkan overdraw without FIFO frame pacing."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

from stress_parser import parse_stress

ROOT = Path(__file__).resolve().parent.parent
CASES = {
    'demo': (1, 1),
    'dense': (2, 1),
    'full': (3, 1),
    'comb': (4, 1),
    'comb-4x': (4, 4),
    'comb-16x': (4, 16),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cases', nargs='+', choices=CASES, default=list(CASES))
    parser.add_argument('--warmup', type=int, default=30, help='frames per case')
    parser.add_argument('--frames', type=int, default=180, help='measured frames per case')
    parser.add_argument('--edit-every', type=int, default=30, help='0 disables edits')
    parser.add_argument('--timeout', type=int, default=180, help='seconds per case')
    parser.add_argument('--output', type=Path, default=Path('build/stress'))
    args = parser.parse_args()
    if args.warmup < 0 or args.frames < 1 or args.edit_every < 0 or args.timeout < 1:
        parser.error('warmup, edit interval and timeout must be nonnegative; frames and timeout must be positive')
    if args.warmup + args.frames > 5000:
        parser.error('at most 5000 total frames per case')
    binary = ROOT / 'build/voxel-demo'
    if not binary.exists():
        parser.error('build/voxel-demo is missing; run make build first')
    out = args.output if args.output.is_absolute() else ROOT / args.output
    out.mkdir(parents=True, exist_ok=True)
    sources = [p for folder in ('src', 'scripts') for p in sorted((ROOT / folder).rglob('*'))
               if p.is_file() and '__pycache__' not in p.parts]
    report = {
        'metadata': {
            'date': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
            'bend': subprocess.check_output(['bend', 'version'], text=True).strip(),
            'git_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'working_tree_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
            'resolution': [640, 360],
            'warmup_frames': args.warmup,
            'measured_frames': args.frames,
            'edit_every_frames': args.edit_every,
            'source_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in sources},
            'timing_scope': 'Frame throughput includes Bend simulation and edits, scene preparation, native geometry expansion, upload, Vulkan submission/presentation, and X11 synchronization. Fence and acquisition waits include GPU/presentation backpressure; these CPU wall-clock intervals are not GPU timestamps.',
            'scale_scope': 'Scene cases vary solid density and exposed surface within the fixed 40x24x20 lattice. N-x cases repeat faces at the same positions. The renderer caches the world mesh by face records, independent of camera and aim, and uploads only dynamic overlays on a hit. Face or body-offset changes rebuild and upload all copies. No case multiplies simulated voxel cells.',
        },
        'cases': [],
    }
    for name in args.cases:
        scene, copies = CASES[name]
        print(f'Stress {name}: scene {scene}, {copies} render copies', flush=True)
        csv_path = out / f'{name}.csv'
        env = {**os.environ, 'VOXEL_BENCH': '1', 'VOXEL_STRESS_SCENE': str(scene),
               'VOXEL_STRESS_COPIES': str(copies), 'VOXEL_STRESS_PRESENT': 'unpaced',
               'VOXEL_STRESS_WARMUP': str(args.warmup),
               'VOXEL_STRESS_MEASURED': str(args.frames),
               'VOXEL_STRESS_EDIT_EVERY': str(args.edit_every)}
        try:
            with csv_path.open('w') as stream:
                proc = subprocess.run([str(binary), '--gpu', 'off'], cwd=ROOT, env=env,
                                      stdout=stream, stderr=subprocess.PIPE, text=True,
                                      timeout=args.timeout)
            stderr, exit_code = proc.stderr, proc.returncode
        except subprocess.TimeoutExpired as exc:
            captured = exc.stderr or b''
            stderr, exit_code = (captured.decode(errors='replace') if isinstance(captured, bytes)
                                 else captured), 124
        (out / f'{name}.stderr').write_text(stderr)
        with csv_path.open() as stream:
            result = parse_stress(stream, exit_code, args.warmup, args.frames, args.edit_every)
        modes = re.findall(r'^stress_present_mode,(immediate|mailbox)$', stderr, re.MULTILINE)
        if not modes or len(set(modes)) != 1:
            result['errors'].append('Unpaced present mode was not confirmed')
            result['pass'] = False
        result.update({'name': name, 'render_copies': copies,
                       'present_mode': modes[0] if modes else None})
        if 'surface_rectangles' in result:
            result['face_inputs_per_rebuild'] = result['surface_rectangles'] * copies
        report['cases'].append(result)
        print(json.dumps({key: result.get(key) for key in
                          ('name', 'pass', 'solid_cells_start', 'surface_rectangles',
                           'render_copies', 'present_mode', 'throughput_fps',
                           'acquire_wait_fraction', 'errors')}, indent=2), flush=True)
    report['pass'] = all(case['pass'] for case in report['cases'])
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Report: {out / "report.json"}', flush=True)
    sys.exit(0 if report['pass'] else 1)


if __name__ == '__main__':
    main()
