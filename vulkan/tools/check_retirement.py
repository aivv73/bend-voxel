#!/usr/bin/env python3
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sanitize', action='store_true')
    args = parser.parse_args()
    flags = ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] if args.sanitize else []
    environment = dict(os.environ, VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation', VK_LAYER_VALIDATE_SYNC='1',
                       ASAN_OPTIONS='detect_leaks=0:halt_on_error=1', UBSAN_OPTIONS='halt_on_error=1')
    for name, markers in (
        ('generation_recording', ('Index-only Recording publication rejection preserved all old bytes/handles/counters/rows',
                                  'Mixed reused/changed/removed generation retained exact resident handles')),
        ('legacy_retirement', ('Legacy complete upload and empty replacement retirement rejection preserved old bytes',)),
    ):
        source = ROOT / f'build/m7-{name}.c'
        binary = source.with_suffix('')
        subprocess.run(['bend', f'tests/{name}.bend', '-o', str(source)], cwd=ROOT, check=True)
        subprocess.run(['clang', '-std=c11', '-O1', '-g', *flags, str(source), '-lpthread', '-lm', '-ldl', '-o', str(binary)], cwd=ROOT, check=True)
        result = subprocess.run([str(binary)], cwd=ROOT, env=environment, text=True, capture_output=True, timeout=60)
        output = result.stdout + result.stderr
        (ROOT / f'build/m7-{name}.log').write_text(output)
        print(output, end='', flush=True)
        result.check_returncode()
        assert all(marker in output for marker in markers)
        assert not any(item in output for item in ('Validation Error', 'SYNC-HAZARD', 'AddressSanitizer', 'runtime error:'))


if __name__ == '__main__':
    main()
