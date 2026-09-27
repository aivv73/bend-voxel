#!/usr/bin/env python3
"""Measure the Light Atelier and optional demolition district stress workloads."""
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
    'atelier': (4, 'static'),
    'atelier-night': (4, 'night'),
    'atelier-camera': (4, 'camera'),
    'atelier-aim': (4, 'aim'),
    'atelier-carve': (4, 'carve'),
    'district': (1, 'static'),
    'district-4': (2, 'static'),
    'district-16': (3, 'static'),
    'district-camera': (1, 'camera'),
    'district-camera-4': (2, 'camera'),
    'district-camera-16': (3, 'camera'),
    'district-aim': (1, 'aim'),
    'district-aim-16': (3, 'aim'),
    'district-carve': (1, 'carve'),
    'district-bridge': (1, 'bridge'),
    'district-fragments': (1, 'fragments'),
    'district-fragments-4': (2, 'fragments'),
}
DEFAULT_CASES = [name for name in CASES if name.startswith('atelier')]
VIEW_IDS = {'static': 0, 'camera': 1, 'aim': 2, 'carve': 3, 'bridge': 4, 'fragments': 5,
            'night': 6}
DISTRICTS = {1: 1, 2: 4, 3: 16, 4: 0}


def resolution(value):
    match = re.fullmatch(r'(\d+)x(\d+)', value)
    if match is None:
        raise argparse.ArgumentTypeError('resolution must be WIDTHxHEIGHT')
    width, height = map(int, match.groups())
    if not (640 <= width <= 7680 and 360 <= height <= 4320 and width * height <= 8294400):
        raise argparse.ArgumentTypeError('resolution must be 640..7680 by 360..4320, at most 8294400 pixels')
    return width, height


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cases', nargs='+', choices=CASES, default=DEFAULT_CASES)
    parser.add_argument('--warmup', type=int, default=30, help='frames per case')
    parser.add_argument('--frames', type=int, default=180, help='measured frames per case')
    parser.add_argument('--edit-every', type=int, default=30, help='carve/bridge interval; 0 disables those edits; fragment bursts use 1')
    parser.add_argument('--body-budget', type=int, default=2048)
    parser.add_argument('--timeout', type=int, default=180, help='seconds per case')
    parser.add_argument('--resolution', type=resolution, default=(640, 360), help='render size WIDTHxHEIGHT (default: 640x360)')
    parser.add_argument('--output', type=Path, default=Path('build/stress'))
    args = parser.parse_args()
    if args.warmup < 0 or args.frames < 1 or args.edit_every < 0 or args.timeout < 1:
        parser.error('warmup, edit interval and timeout must be nonnegative; frames and timeout must be positive')
    if not 1 <= args.body_budget <= 65536:
        parser.error('body budget must be 1..65536')
    if args.frames < 4 and any(CASES[name][1] in ('camera', 'aim', 'fragments') for name in args.cases):
        parser.error('moving view workloads need at least four measured frames')
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
            'resolution': list(args.resolution),
            'warmup_frames': args.warmup,
            'measured_frames': args.frames,
            'edit_every_frames': args.edit_every,
            'body_budget': args.body_budget,
            'source_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in sources},
            'timing_scope': 'Frame throughput includes Bend simulation, edits and body triangle construction, scene preparation, native proxy and overlay geometry, upload, Vulkan submission/presentation, and X11 synchronization. Fence and acquisition waits include GPU/presentation backpressure; these CPU wall-clock intervals are not GPU timestamps.',
            'scene_scope': 'Default cases use the six-body Light Atelier with 803,970 occupied 10 cm cells, three editable Blender sculptures, sun shadows, and a plaster courtyard. Optional district cases retain the 1/4/16 district scale and fragment workloads. Physics advances exactly 1/60 second per frame.',
            'scale_scope': 'Each district contains 2,443,284 real editable 10 cm cells at distinct signed coordinates. Scale cases contain 1, 4, or 16 districts. Sparse solid cuboids compress occupancy; there are no render copies. Fragment workloads sever eight supports per district per frame for sixteen frames, then follow falling fragments.',
        },
        'cases': [],
    }
    for name in args.cases:
        scene, view = CASES[name]
        scale = DISTRICTS[scene]
        scene_kind = 'atelier' if scene == 4 else 'district'
        edit_every = 1 if view == 'fragments' else args.edit_every if view in ('carve', 'bridge') else 0
        print(f'Stress {name}: {scene_kind}, {view} workload, {args.resolution[0]}x{args.resolution[1]}', flush=True)
        csv_path = out / f'{name}.csv'
        env = {**os.environ, 'VOXEL_RESOLUTION': f'{args.resolution[0]}x{args.resolution[1]}', 'VOXEL_STRESS_SCENE': str(scene),
               'VOXEL_BODY_BUDGET': str(args.body_budget), 'VOXEL_STRESS_PRESENT': 'unpaced',
               'VOXEL_STRESS_VIEW': str(VIEW_IDS[view]),
               'VOXEL_STRESS_WARMUP': str(args.warmup),
               'VOXEL_STRESS_MEASURED': str(args.frames),
               'VOXEL_STRESS_EDIT_EVERY': str(edit_every)}
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
            result = parse_stress(stream, exit_code, args.warmup, args.frames,
                                  edit_every, view, world_scale=scale, resolution=args.resolution,
                                  scene_kind=scene_kind)
        modes = re.findall(r'^stress_present_mode,(immediate|mailbox)$', stderr, re.MULTILINE)
        if not modes or len(set(modes)) != 1:
            result['errors'].append('Unpaced present mode was not confirmed')
            result['pass'] = False
        result.update({'name': name, 'scene_kind': scene_kind, 'districts': scale, 'view_mode': view,
                       'edit_every_frames': edit_every,
                       'present_mode': modes[0] if modes else None})
        report['cases'].append(result)
        print(json.dumps({key: result.get(key) for key in
                          ('name', 'pass', 'solid_cells_start', 'surface_rectangles',
                           'scene_kind', 'max_bodies', 'max_moving_bodies', 'present_mode', 'throughput_fps',
                           'visible_bodies_mean', 'draw_calls_mean', 'lod_proxied_bodies_mean',
                           'lod_proxy_rebuilds', 'acquire_wait_fraction', 'errors')}, indent=2), flush=True)
    report['pass'] = all(case['pass'] for case in report['cases'])
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Report: {out / "report.json"}', flush=True)
    sys.exit(0 if report['pass'] else 1)


if __name__ == '__main__':
    main()
