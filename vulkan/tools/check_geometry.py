#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'


def run(args, output):
    print('+', ' '.join(map(str, args)), flush=True)
    with (BUILD / output).open('wb') as log:
        subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=300)


def main():
    BUILD.mkdir(exist_ok=True)
    for source, binary in [('tests/geometry_dump.bend', 'geometry-dump'),
                           ('tests/geometry_clips.bend', 'geometry-clips')]:
        run(['bend', source, '-o', str(BUILD / binary)], f'{binary}-build.log')
        linked = subprocess.run(['ldd', str(BUILD / binary)], check=True, text=True, capture_output=True).stdout
        if 'libX11' in linked or 'libxcb' in linked or (BUILD / f'{binary}.gpu').exists():
            raise SystemExit(f'Geometry CPU executable gained a display or Bend GPU dependency: {binary}')
    run([str(BUILD / 'geometry-clips'), '+RTS', '--threads', '6', '--gpu', 'off', '-RTS'], 'geometry-clips.jsonl')
    run([sys.executable, 'tools/geometry_clips.py'], 'geometry-clips-oracle.log')
    run([str(BUILD / 'geometry-dump'), '+RTS', '--threads', '6', '--gpu', 'off', '-RTS'], 'geometry-dump.jsonl')
    run([sys.executable, 'tools/geometry_oracle.py'], 'geometry-oracle.log')
    run([str(BUILD / 'geometry-dump'), '+RTS', '--threads', '1', '--gpu', 'off', '-RTS'], 'geometry-dump-serial.jsonl')
    if (BUILD / 'geometry-dump.jsonl').read_bytes() != (BUILD / 'geometry-dump-serial.jsonl').read_bytes():
        raise SystemExit('Production geometry output differs between 1 and 6 CPU threads')
    print((BUILD / 'geometry-clips-oracle.log').read_text(), end='')
    print('PASS original-Body exterior oracle and byte-identical production output with 1 and 6 CPU threads')


if __name__ == '__main__':
    main()
