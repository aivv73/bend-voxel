#!/usr/bin/env python3
"""Build and measure the throwaway Vulkan rasterizer on fixed Bend replay scenes."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess

from snapshot import decode_snapshot, decode_tree, png

ROOT = Path(__file__).resolve().parent.parent


def command(args, *, env=None, stdout=subprocess.PIPE):
    result = subprocess.run(args, cwd=ROOT, env=env, stdout=stdout,
                            stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(map(str, args))} failed ({result.returncode}):\n{result.stderr}")
    return result


def reference_pixels(raw):
    lines = raw.splitlines()
    return decode_tree(lines[lines.index('TREE') + 1:], 640, 360, 2048)


def ppm_pixels(path):
    data = path.read_bytes()
    header = b'P6\n640 360\n255\n'
    if not data.startswith(header) or len(data) != len(header) + 640 * 360 * 3:
        raise ValueError(f'Unexpected Vulkan PPM: {path}')
    return data[len(header):]


def compare(a, b):
    if len(a) != len(b):
        raise ValueError('Image sizes differ')
    different = sum(a[i:i+3] != b[i:i+3] for i in range(0, len(a), 3))
    absolute = sum(abs(x-y) for x, y in zip(a, b))
    return {'different_pixels': different, 'different_percent': 100*different/(len(a)//3),
            'mean_absolute_channel_error': absolute/len(a),
            'vulkan_pixel_sha256': hashlib.sha256(a).hexdigest(),
            'bend_pixel_sha256': hashlib.sha256(b).hexdigest()}


def difference_image(a, b):
    image = bytearray(len(a))
    for i in range(0, len(a), 3):
        if a[i:i+3] != b[i:i+3]:
            image[i:i+3] = b'\xff\x40\x40'
    return png(image, 640, 360)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('build/vulkan-prototype'))
    parser.add_argument('--frames', type=int, default=100)
    args = parser.parse_args()
    if args.frames < 1:
        parser.error('--frames must be positive')
    out = args.output if args.output.is_absolute() else ROOT / args.output
    out.mkdir(parents=True, exist_ok=True)
    bend = subprocess.check_output(['bend', 'version'], text=True).strip()
    if bend != 'bend 2.0.26':
        parser.error(f'This prototype was checked with bend 2.0.26, found {bend}')
    cuda_env = {**os.environ, 'CUDA_HOME': os.environ.get('CUDA_HOME', '/opt/cuda')}
    print('Building Bend scene exporter and reference renderer', flush=True)
    command(['bend', 'src/prototype/vulkan-scene.bend', '-o', str(out/'scene-export')], env=cuda_env)
    command(['bend', 'src/snapshot.bend', '-o', str(out/'bend-snapshot')], env=cuda_env)
    if not (out/'bend-snapshot.gpu').exists():
        raise RuntimeError('Bend snapshot CUDA module is missing')
    print('Building Vulkan shaders and rasterizer', flush=True)
    command(['glslc', '--target-env=vulkan1.3', 'src/prototype/vulkan.vert', '-o', str(out/'vulkan.vert.spv')])
    command(['glslc', '--target-env=vulkan1.3', 'src/prototype/vulkan.frag', '-o', str(out/'vulkan.frag.spv')])
    command(['g++', '-O2', '-std=c++17', '-Wall', '-Wno-missing-field-initializers',
             'src/prototype/vulkan_offscreen.cpp', '-lvulkan', '-o', str(out/'vulkan-offscreen')])
    results = []
    for tick in (0, 408, 540, 1140):
        print(f'Rendering tick {tick}', flush=True)
        env={**cuda_env, 'VOXEL_SNAPSHOT_TICK': str(tick)}
        ref=command([str(out/'bend-snapshot'), '--gpu', 'on'], env=env).stdout
        reference_png, metadata=decode_snapshot(ref)
        ref_pixels=reference_pixels(ref)
        (out/f'tick-{tick:04d}-bend.png').write_bytes(reference_png)
        (out/f'tick-{tick:04d}-bend.tree.gz').write_bytes(gzip.compress(ref.encode(), mtime=0))
        scene=command([str(out/'scene-export'), '--gpu', 'off'], env=env).stdout
        (out/f'tick-{tick:04d}.scene').write_text(scene)
        native=command([str(out/'vulkan-offscreen'), str(out/f'tick-{tick:04d}.scene'),
                        str(out/'vulkan.vert.spv'), str(out/'vulkan.frag.spv'),
                        str(out/f'tick-{tick:04d}.ppm'), str(args.frames)])
        timing=json.loads(native.stdout)
        image=ppm_pixels(out/f'tick-{tick:04d}.ppm')
        (out/f'tick-{tick:04d}-vulkan.png').write_bytes(png(image, 640, 360))
        (out/f'tick-{tick:04d}-difference.png').write_bytes(difference_image(image, ref_pixels))
        record={'tick': tick, 'state': metadata['state'], 'render': timing, **compare(image, ref_pixels)}
        assert timing['tick']==tick and timing['solids']==metadata['state']['solids']
        assert timing['bodies']==metadata['state']['bodies']
        results.append(record)
        print(f"  pixels different: {record['different_percent']:.3f}%"
              f"; Vulkan offscreen wall median: {timing['wall_median_ms']:.3f} ms", flush=True)
    files=[ROOT/'src/prototype/vulkan-scene.bend',ROOT/'src/prototype/vulkan_offscreen.cpp',
           ROOT/'src/prototype/vulkan.vert',ROOT/'src/prototype/vulkan.frag',
           ROOT/'scripts/prototype_vulkan.py']
    report={'prototype': 'offscreen Vulkan face rasterization', 'bend': bend,
            'resolution': [640,360], 'backend': results[0]['render']['device'],
            'timing_scope': 'Fixed cached geometry; command recording, GPU draw, readback and fence wait per frame. No scene export, edits, HUD, window or presentation in timed frame.',
            'image_scope': 'Raw RGB comparison; brush preview is not rendered by Vulkan.',
            'source_sha256': {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
            'scenes': results}
    (out/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f'Report: {out/"report.json"}', flush=True)


if __name__=='__main__':
    main()
