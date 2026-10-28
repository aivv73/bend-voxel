#!/usr/bin/env python3
import collections
import copy
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'


def coverage(faces):
    result = collections.Counter()
    for _, x, y, z, direction, material, width, height in faces:
        normal = (x, x + 1, y, y + 1, z, z + 1)[direction]
        u, v = (y if direction < 2 else x), (z if direction < 4 else y)
        for du, dv, sign in ((0, 0, 1), (width, 0, -1), (0, height, -1), (width, height, 1)):
            result[direction, normal, material, u + du, v + dv] += sign
    return {key: value for key, value in result.items() if value}


def check(path):
    baseline, cases = {}, {}
    for line in path.read_text().splitlines():
        row = json.loads(line)
        if 'baseline' in row:
            baseline[row['baseline']] = row['faces']
        else:
            cases[row['case']] = row
    assert cases.keys() == baseline.keys()
    assert len(cases) == 15, 'Chunk fixture census changed'
    for name, row in cases.items():
        assert row['returned_body'] == row['expected_body'], f'{name}: returned Body differs from independent original input or pinned cut'
        assert row['faces'] == baseline[name], f'{name}: original anchors, extents or source order changed'
        canonical, shadows = [], []
        keys = set()
        for chunk in row['chunks']:
            key = tuple(chunk['key'])
            assert key not in keys, f'{name}: duplicate chunk owner'
            keys.add(key)
            canonical.extend(chunk['faces'])
            shadows.extend(chunk['shadow'])
            assert coverage(chunk['faces']) == coverage(chunk['shadow']), f'{name}/{key}: merged exterior coverage changed'
        by_key = {tuple(c['key']): c['faces'] for c in row['chunks']}
        drawn = []
        for key, first, count in row['runs']:
            assert count > 0 and 0 <= first <= len(by_key[tuple(key)]) - count
            drawn.extend(by_key[tuple(key)][first:first + count])
        assert drawn == row['faces'], f'{name}: canonical draw runs changed tie/order or local ranges'
        assert coverage(canonical) == coverage(row['faces']), f'{name}: missing canonical chunk coverage'
        assert row['counts'][:2] == [len(canonical), len(shadows)], f'{name}: logical count metadata changed'
    assert cases['cube']['counts'][:2] == [384, 6], 'dense production stream did not greedily reduce'
    assert cases['merge-boxes']['counts'][:2] == [10, 6], 'analytic production stream did not greedily reduce'
    assert cases['huge']['counts'][:2] == [6, 6] and len(cases['huge']['chunks']) == 1, 'huge valid cuboid was subdivided'
    assert cases['boundary']['counts'][0] == 36, 'dense halo exposed an internal boundary'
    for old_name, new_name in [('boundary-cut', 'boundary-repeat'), ('boundary-repeat', 'boundary-miss'), ('remote-cut', 'remote-repeat')]:
        old, new = cases[old_name], cases[new_name]
        assert old['faces'] == new['faces'], f'{new_name}: repeated/no-op cut changed canonical faces'
        versions = lambda row: {tuple(c['key']): c['version'] for c in row['chunks']}
        assert versions(old) == versions(new), f'{new_name}: unchanged mesh generation replaced'
        assert new['counts'][2] == 0, f'{new_name}: unchanged chunk reported rebuilt'
    old = {tuple(c['key']): c for c in cases['boundary']['chunks']}
    new = {tuple(c['key']): c for c in cases['boundary-cut']['chunks']}
    assert old[(32, 32, 32, 32)] == new[(32, 32, 32, 32)], 'distant dense chunk changed'
    assert old[(32, 0, 0, 32)]['faces'] != new[(32, 0, 0, 32)]['faces'], 'neighbor exterior owner was not invalidated'
    far = (192, 0, 0, 32)
    find = lambda name: next(c for c in cases[name]['chunks'] if tuple(c['key']) == far)
    assert find('remote') == find('remote-cut'), 'unaffected analytic chunk changed'
    print(f'PASS {len(cases)} exact canonical streams, signed rectangle coverage, dense/cuboid greedy reductions, analytic huge source, dirty neighbors and retained generations')


def body_mutation_control(source):
    rows = [json.loads(line) for line in source.read_text().splitlines()]
    mutated = copy.deepcopy(rows)
    for row in mutated:
        if row.get('baseline') == 'cube':
            for face in row['faces']:
                face[5] = 2
        elif row.get('case') == 'cube':
            row['returned_body']['cells'] = [2] * len(row['returned_body']['cells'])
            for face in row['faces']:
                face[5] = 2
            for chunk in row['chunks']:
                for face in chunk['faces'] + chunk['shadow']:
                    face[5] = 2
    path = BUILD / 'chunks-body-mutation-control.jsonl'
    path.write_text(''.join(json.dumps(row, separators=(',', ':')) + '\n' for row in mutated))
    try:
        check(path)
    except AssertionError as error:
        assert 'returned Body differs from independent original input or pinned cut' in str(error), error
    else:
        raise AssertionError('Matching material-mutated mesh and self-derived reference passed the Body oracle')
    print('PASS material-mutated Body with matching mesh/reference rejected by independent original Body')


def main():
    BUILD.mkdir(exist_ok=True)
    binary = BUILD / 'chunks-dump'
    with (BUILD / 'chunks-dump-build.log').open('wb') as log:
        subprocess.run(['bend', 'tests/chunks_dump.bend', '-o', str(binary)], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
    for threads in (6, 1):
        path = BUILD / f'chunks-dump-{threads}.jsonl'
        with path.open('wb') as log:
            subprocess.run([str(binary), '+RTS', '--threads', str(threads), '--gpu', 'off', '-RTS'], cwd=ROOT, stdout=log, check=True, timeout=300)
        check(path)
    assert (BUILD / 'chunks-dump-6.jsonl').read_bytes() == (BUILD / 'chunks-dump-1.jsonl').read_bytes(), 'parallel chunk output differs'
    body_mutation_control(BUILD / 'chunks-dump-6.jsonl')
    linked = subprocess.run(['ldd', str(binary)], text=True, capture_output=True, check=True).stdout
    assert 'libX11' not in linked and 'libxcb' not in linked and not (BUILD / 'chunks-dump.gpu').exists()
    print('PASS deterministic chunk builds with 1 and 6 threads and no display/GPU dependency')


if __name__ == '__main__':
    main()
