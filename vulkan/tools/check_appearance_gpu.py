import argparse
from collections import Counter
import json
import os
from pathlib import Path
import subprocess
import sys

import appearance_cases as cases

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/milestone-6-shader-gpu'
COMMANDS = []
COMPILE_TIMEOUT = 1800
FORBIDDEN = ('Validation Error', 'SYNC-HAZARD', 'ERROR: AddressSanitizer',
             'runtime error:', 'SOME PROOFS FAIL')


def run(args, name, env=None, timeout=180):
    command = list(map(str, args))
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True, timeout=timeout)
    output = result.stdout + result.stderr
    (BUILD / (name + '.stdout')).write_text(result.stdout)
    (BUILD / (name + '.stderr')).write_text(result.stderr)
    COMMANDS.append(dict(command=command, status=result.returncode, log=name))
    (BUILD / 'commands.json').write_text(json.dumps(COMMANDS, indent=2) + '\n')
    if result.returncode or any(marker in output for marker in FORBIDDEN):
        raise AssertionError(f'{name} failed, see build/{name}.stdout and .stderr')
    return result.stdout


def expected_word(c, mode):
    if mode == 0:
        return 0xff00ffff if c.selected else 0xffff00ff
    if mode == 1:
        return 0xff332211
    if mode == 2:
        return c.material
    if mode == 3:
        return 0xff000000 | c.direction
    if mode in (4, 5, 6):
        return c.cell[mode - 4]
    if mode == 7:
        return 0xff0000ff if c.selected else 0xff000000
    raise AssertionError(mode)


def check_output(output, name):
    parsed = {}
    host = {}
    selected = {}
    samples = {}
    abi = {'abi_host': {}, 'abi_gpu': {}}
    live = []
    for line in output.splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] in abi:
            index, word = map(int, fields[1:])
            assert index not in abi[fields[0]]
            abi[fields[0]][index] = word
        elif fields[0] == 'pixel':
            label, kind, mode, word = fields[1:]
            key = (label, int(kind), int(mode))
            assert key not in parsed
            parsed[key] = int(word)
        elif fields[0] == 'host':
            assert fields[1] not in host
            host[fields[1]] = tuple(map(int, fields[2:]))
        elif fields[0] == 'selected':
            selected.setdefault(fields[1], []).append(tuple(map(int, fields[2:])))
        elif fields[0] == 'sample':
            samples[int(fields[1])] = int(fields[2])
        elif fields[0] == 'live':
            live.append(int(fields[1]))
    literal_abi = {i: 0x3f000000 + i if i < 584 else 0 for i in range(1024)}
    for label in abi:
        assert abi[label] == literal_abi, f'{name} {label} sentinel mismatch'
    assert samples == {0: 0xff404040, 1: 0xff404040}, samples
    assert live == [0], live
    expected = {}
    for c in cases.rows():
        assert host[c.name] == (*c.cell, int(c.selected), 0xffff00 if c.selected else 0xff00ff), (name, c.name, host[c.name])
        assert selected.get(c.name, []) == cases.selected_cells(c.brush), (name, c.name, 'CPU selected list')
        kind = 2 if c.production else 1
        for mode in c.modes:
            key = (c.name, kind, mode)
            expected[key] = expected_word(c, mode)
            actual = parsed.get(key)
            assert actual == expected[key], f'{name} {key}: actual {actual!r}, expected 0x{expected[key]:08x}'
        if c.production:
            expected[(c.name, 4, 7)] = 0
    assert parsed == expected, f'{name} missing, extra or incorrect pixel rows'
    assert len(host) == len(cases.rows())
    count = Counter(mode for _, kind, mode in expected if kind in (1, 2))
    return dict(status='pass', cases=len(host), abi_payload_words=584, abi_zero_tail_words=440,
                host_abi_words=1024, gpu_abi_words=1024, diagnostic_and_tint_pixels=sum(count.values()),
                modes=dict(count), production_rectangles=6, rejected_winding_pixels=6,
                sampled_depth_checks=2, submitted_frames=795, uniform_uploads=787,
                descriptor_rewrites_after_reset=786, live_rows=0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sanitize', action='store_true')
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True, parents=True)
    run([sys.executable, 'tools/build_shaders.py', '--check'], 'shaders')
    run([sys.executable, 'tools/appearance_cases.py'], 'cases')
    run(['bend', 'PROOF.bend'], 'proof')
    run(['bend', 'tests/appearance_gpu_main.bend', '-o', 'build/milestone-6-shader-gpu/shader-gpu'], 'bend-compile', timeout=COMPILE_TIMEOUT)
    device = run(['vulkaninfo', '--summary'], 'device')
    validation_available = 'VK_LAYER_KHRONOS_validation' in device
    normal = run(['build/milestone-6-shader-gpu/shader-gpu', '+RTS', '--threads', '4', '-RTS'], 'normal')
    results = {'normal': check_output(normal, 'normal')}
    validation_env = dict(os.environ, VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation',
                          VK_LAYER_ENABLES='VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT',
                          VK_LOADER_DEBUG='layer')
    if validation_available:
        validation = run(['build/milestone-6-shader-gpu/shader-gpu', '+RTS', '--threads', '4', '-RTS'], 'validation', validation_env)
        results['validation'] = check_output(validation, 'validation')
    else:
        results['validation'] = dict(status='unavailable')
        validation_env = dict(os.environ)
    if args.sanitize:
        run(['bend', 'tests/appearance_gpu_main.bend', '-o', 'build/milestone-6-shader-gpu/shader-gpu.c'], 'bend-c', timeout=COMPILE_TIMEOUT)
        run(['clang', '-std=c11', '-O1', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
             'build/milestone-6-shader-gpu/shader-gpu.c', '-lpthread', '-lm', '-ldl', '-o', 'build/milestone-6-shader-gpu/shader-gpu-sanitized'], 'sanitizer-compile', timeout=COMPILE_TIMEOUT)
        env = dict(validation_env, ASAN_OPTIONS='detect_leaks=0:halt_on_error=1', UBSAN_OPTIONS='halt_on_error=1')
        sanitized = run(['build/milestone-6-shader-gpu/shader-gpu-sanitized', '+RTS', '--threads', '4', '-RTS'], 'sanitized', env)
        results['sanitized'] = check_output(sanitized, 'sanitized')
    (BUILD / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
