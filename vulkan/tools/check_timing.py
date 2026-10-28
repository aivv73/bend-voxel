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
    source = ROOT / 'build/m7-timing-reset.c'
    source.parent.mkdir(parents=True, exist_ok=True)
    binary = source.with_suffix('')
    subprocess.run(['bend', 'tests/timing_reset.bend', '-o', str(source)], cwd=ROOT, check=True)
    emitted = source.read_text()
    probes = (ROOT / 'tests/timing_reset_probes.c').read_text()
    anchor = 'static void __attribute__((constructor)) bv_register(void)'
    assert emitted.count(anchor) == 1
    emitted = emitted.replace(anchor, probes + '\n' + anchor)
    allocator = (ROOT / '../deps/bend-vulkan/tests/probes.c').read_text().split('static unsigned bv_test_barrier_calls;')[0]
    begin = emitted.index('// Bend native effect ABI.')
    end = emitted.index(anchor)
    native = emitted[begin:end]
    native = native.replace('malloc(', 'bv_test_alloc(').replace('calloc(', 'bv_test_calloc(').replace('realloc(', 'bv_test_realloc(')
    native = re.sub(r'\bfree\(', 'bv_test_free(', native)
    native = native.replace('static BvRow* bv_add(', allocator + '\nstatic BvRow* bv_add(', 1)
    emitted = emitted[:begin] + native + emitted[end:]
    macros = re.findall(r'^#define (CID_\w+) \d+$', emitted, re.M)
    matches = [m for m in macros if m == 'CID_Fail']
    assert len(matches) == 1
    emitted = emitted.replace('CID(Fail)', matches[0])
    emitted, count = re.subn(r'(io_eff\(CID_\w+, )bv_reset_timestamp_queries(\);)', r'\1test_timing_reset\2', emitted)
    assert count == 1
    source.write_text(emitted)
    flags = ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] if args.sanitize else []
    subprocess.run(['clang', '-std=c11', '-O1', '-g', *flags, str(source), '-lpthread', '-lm', '-ldl', '-o', str(binary)], cwd=ROOT, check=True)
    environment = dict(os.environ, VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation', VK_LAYER_VALIDATE_SYNC='1',
                       ASAN_OPTIONS='detect_leaks=0:halt_on_error=1', UBSAN_OPTIONS='halt_on_error=1')
    result = subprocess.run([str(binary)], cwd=ROOT, env=environment, text=True, capture_output=True, timeout=60)
    output = result.stdout + result.stderr
    (ROOT / 'build/m7-timing-reset.log').write_text(output)
    print(output, end='', flush=True)
    result.check_returncode()
    assert 'Actual query reset recorded-ref allocation failed with old completed data retained' in output
    assert 'TIMING unavailable=gpu_frame_queries_disabled' in output
    assert 'Completed old queries plus reset-ref OOM disabled frame diagnostics and recovered on retry' in output
    assert 'gpu_scope=' not in output
    assert not any(item in output for item in ('Validation Error', 'SYNC-HAZARD', 'AddressSanitizer', 'runtime error:'))


if __name__ == '__main__':
    main()
