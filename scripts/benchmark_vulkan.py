#!/usr/bin/env python3
"""Run the existing 65-second voxel replay through the live Vulkan renderer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from benchmark import parse_run

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--output', type=Path, default=Path('build/vulkan-benchmarks'))
    args = parser.parse_args()
    if args.runs < 1:
        parser.error('--runs must be positive')
    out = args.output if args.output.is_absolute() else ROOT / args.output
    out.mkdir(parents=True, exist_ok=True)
    files = [ROOT / 'src/demo_vulkan.bend', ROOT / 'src/vulkan.bend',
             ROOT / 'src/vulkan/bridge.c', ROOT / 'src/vulkan/native.cpp',
             ROOT / 'src/vulkan/scene.vert', ROOT / 'src/vulkan/scene.frag']
    metadata = {
        'date': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        'bend': subprocess.check_output(['bend', 'version'], text=True).strip(),
        'git_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'working_tree_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
        'resolution': [640, 360],
        'backend': 'Bend CPU gameplay, Vulkan 1.3/Xlib presentation',
        'gpu': subprocess.check_output(['nvidia-smi', '--query-gpu=name,driver_version,memory.total',
                                        '--format=csv,noheader'], text=True).strip(),
        'source_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
        'timing_scope': 'Full frame intervals include CPU simulation/edit, Bend scene preparation, Vulkan scene and HUD mesh upload/draw/present, and X11 event synchronization. The frame effect is one combined stage.'
    }
    results = []
    for number in range(1, args.runs + 1):
        print(f'Vulkan benchmark {number}/{args.runs}: 5 s warm-up + 60 s measured', flush=True)
        path = out / f'run-{number}.csv'
        with path.open('w') as stream:
            proc = subprocess.run([str(ROOT / 'build/voxel-vulkan'), '--gpu', 'off'], cwd=ROOT,
                                  env={**os.environ, 'VOXEL_BENCH': '1'}, stdout=stream,
                                  stderr=subprocess.PIPE, text=True, timeout=180)
        (out / f'run-{number}.stderr').write_text(proc.stderr)
        with path.open() as stream:
            result = {'run': number, **parse_run(stream, proc.returncode)}
        result['stages']['vulkan_frame_effect'] = result['stages'].pop('cuda_rendering')
        results.append(result)
        print(json.dumps({k: result[k] for k in ('run', 'frames', 'cuts', 'instrumentation_pass',
                                                 'workload_pass', 'performance_pass')}, indent=2), flush=True)
    report = {'metadata': metadata, 'runs': results,
              'acceptance_pass': args.runs == 3 and all(r['pass'] for r in results),
              'note': 'The Vulkan effect includes scene and HUD presentation; visual and input checks are separate.'}
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Report: {out / "report.json"}', flush=True)
    sys.exit(0 if report['acceptance_pass'] else 1)


if __name__ == '__main__':
    main()
