#!/usr/bin/env python3
import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sanitize', action='store_true')
    args = parser.parse_args()
    source = ROOT / 'build/m7-generation-failures.c'
    binary = source.with_suffix('')
    subprocess.run(['bend', 'tests/chunk_device.bend', '-o', str(source)], cwd=ROOT, check=True)
    emitted = source.read_text()
    probes = (ROOT / 'tests/generation_failure_probes.c').read_text()
    anchor = 'static void __attribute__((constructor)) bv_register(void)'
    assert emitted.count(anchor) == 1
    emitted = emitted.replace(anchor, probes + '\n' + anchor)
    for native, probe in [('u64_roundtrip', 'fault'), ('create_buffer', 'create'),
                          ('allocate_memory', 'allocate'), ('write_memory_words', 'write')]:
        emitted, count = re.subn(r'(io_eff\(CID_\w+, )bv_' + native + r'(\);)',
                                 r'\1test_generation_' + probe + r'\2', emitted)
        assert count == 1, native
    source.write_text(emitted)
    flags = ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] if args.sanitize else []
    subprocess.run(['clang', '-std=c11', '-O1', '-g', *flags, str(source), '-lpthread', '-lm', '-ldl', '-o', str(binary)], cwd=ROOT, check=True)
    environment = dict(os.environ, VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation', VK_LAYER_VALIDATE_SYNC='1',
                       ASAN_OPTIONS='detect_leaks=0:halt_on_error=1', UBSAN_OPTIONS='halt_on_error=1')
    result = subprocess.run([str(binary)], cwd=ROOT, env=environment, text=True, capture_output=True, timeout=60)
    output = result.stdout + result.stderr
    (ROOT / 'build/m7-generation-failures.log').write_text(output)
    print(output, end='', flush=True)
    result.check_returncode()
    assert 'Immutable chunk generation CPU/staging/device bytes, no-op reuse, empty-after-edit, reset and cleanup passed' in output
    assert not any(item in output for item in ('Validation Error', 'SYNC-HAZARD', 'AddressSanitizer', 'runtime error:'))


if __name__ == '__main__':
    main()
