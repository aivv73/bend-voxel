#!/usr/bin/env python3
"""Decode the Slash Boss Q/Pix protocol and save fixed-clock voxel snapshots."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parent.parent


def decode_tree(lines, width, height, size):
    if size < 1 or size & (size-1) or not 0 < width <= size or not 0 < height <= size:
        raise ValueError('Invalid image dimensions')
    pixels = bytearray(width * height * 3)
    tokens = iter(lines)

    def visit(x, y, side):
        try:
            token = next(tokens).strip()
        except StopIteration as exc:
            raise ValueError('Truncated image tree') from exc
        if token == 'Q':
            if side == 1:
                raise ValueError('Tree exceeds root depth')
            half = side // 2
            for dx, dy in ((0, 0), (half, 0), (0, half), (half, half)):
                visit(x+dx, y+dy, half)
        else:
            color = int(token)
            if not 0 <= color <= 0xffffff:
                raise ValueError('Invalid RGB pixel')
            if x < width and y < height:
                row = color.to_bytes(3, 'big') * (min(x+side, width)-x)
                for py in range(y, min(y+side, height)):
                    offset = (py*width+x)*3
                    pixels[offset:offset+len(row)] = row
    visit(0, 0, size)
    if next(tokens, None) is not None:
        raise ValueError('Extra image tree data')
    return bytes(pixels)


def png(pixels, width, height):
    def chunk(name, data):
        return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name+data))
    rows = b''.join(b'\0'+pixels[y*width*3:(y+1)*width*3] for y in range(height))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>2I5B', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')


def decode_snapshot(raw):
    lines = raw.splitlines()
    header = lines[0].split(',')
    if len(header) != 6 or header[:2] != ['snapshot', '1']:
        raise ValueError('Invalid snapshot header')
    width, height, size, tick = map(int, header[2:])
    if (width, height, size) != (640, 360, 2048) or not 0 <= tick <= 1199:
        raise ValueError('Unexpected snapshot dimensions or tick')
    hud_index, tree_index = lines.index('HUD'), lines.index('TREE')
    if tree_index - hud_index != 7:
        raise ValueError('Expected six HUD lines')
    state = lines[1].split(',')
    if len(state) != 5 or state[0] != 'state':
        raise ValueError('Invalid world state')
    body_records = []
    for line in lines[2:hud_index]:
        tag, identifier, offset, speed, bottom = line.split(',')
        if tag != 'body':
            raise ValueError('Invalid body record')
        body_records.append(dict(id=int(identifier), offset=float(offset), speed=float(speed), bottom=float(bottom)))
    metadata = dict(tick=tick, fixed_step_seconds=1/60, resolution=[width,height], root_size=size,
                    state=dict(zip(('solids','bodies','removed','status'), map(int,state[1:]))), bodies=body_records,
                    hud='\n'.join(lines[hud_index+1:tree_index]), hud_in_image=False)
    pixels = decode_tree(lines[tree_index+1:], width, height, size)
    metadata['pixel_sha256'] = hashlib.sha256(pixels).hexdigest()
    return png(pixels,width,height), metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ticks', nargs='+', type=int, default=[0,60,216,396,408,540,1140])
    parser.add_argument('--output', type=Path, default=ROOT/'build/snapshots')
    parser.add_argument('--gpu', choices=('on','off'), default='on')
    args = parser.parse_args()
    if any(t < 0 or t > 1199 for t in args.ticks):
        parser.error('ticks must be between 0 and 1199 (first 20-second replay cycle)')
    args.output.mkdir(parents=True,exist_ok=True)
    sources = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'src').rglob('*')) if p.is_file()}
    for tick in args.ticks:
        proc = subprocess.run([str(ROOT/'build/voxel-snapshot'),'--gpu',args.gpu], env={**os.environ,'VOXEL_SNAPSHOT_TICK':str(tick)},
                              capture_output=True,text=True,check=True,timeout=180)
        data, metadata = decode_snapshot(proc.stdout)
        if metadata['tick'] != tick:
            raise ValueError('Snapshot tick differs from request')
        metadata.update(backend=args.gpu, bend=subprocess.check_output(['bend','version'],text=True).strip(), source_sha256=sources)
        base = args.output/f'tick-{tick:04d}'
        base.with_suffix('.png').write_bytes(data)
        base.with_suffix('.tree.gz').write_bytes(gzip.compress(proc.stdout.encode(),mtime=0))
        base.with_suffix('.json').write_text(json.dumps(metadata,indent=2)+'\n')
        base.with_suffix('.stderr').write_text(proc.stderr)
        print(f'{base.with_suffix(".png")}: {metadata["state"]}',flush=True)


if __name__ == '__main__':
    main()
