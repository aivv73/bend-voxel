#!/usr/bin/env python3
import array
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

LIMIT = 1 << 20
QUAD_LIMIT = (1 << 30) // 40
ERRORS = {
    'overlap': 'overlapping nonair cuboids at sources 0 and 1',
    'contained': 'overlapping nonair cuboids at sources 0 and 1',
    'duplicate': 'overlapping nonair cuboids at sources 0 and 1',
    'invalid-box': 'invalid nonempty cuboid bounds at source 0',
    'inverted-box': 'invalid nonempty cuboid bounds at source 0',
    'coordinate-over': 'cuboid coordinates exceed 2^20 at source 0',
    'invalid-dense-side': 'dense body must be a balanced side^3 array with a positive power-of-two side <= 1024',
    'invalid-dense-shape': 'dense body must be a balanced side^3 array with a positive power-of-two side <= 1024',
    'zero-width': 'invalid face material, extent or coordinate bounds',
    'extent-over': 'invalid face material, extent or coordinate bounds',
    'extent-wrap': 'invalid face material, extent or coordinate bounds',
}


def need(condition, message):
    if not condition:
        raise AssertionError(message)


def f32(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


def bits(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def little_words(words):
    result = array.array('I', words)
    if sys.byteorder != 'little':
        result.byteswap()
    return result.tobytes()


def size_check(q, size):
    vc, ic, vw, iw = q * 4, q * 6, q * 40, q * 6
    vcap = 1 << max(0, (vw - 1).bit_length()) if vw else 1
    icap = 1 << max(0, (iw - 1).bit_length()) if iw else 1
    expected = [q, vc, ic, vw, iw, vcap, icap, vcap.bit_length() - 1, icap.bit_length() - 1]
    need(size['counts'] == expected, f'size counts {size["counts"]} != {expected}')
    for key, value in [('vertex_bytes', vw * 4), ('index_bytes', iw * 4)]:
        need(size[key] == [value & 0xffffffff, value >> 32], f'{key} overflow')
    need(max(vcap, icap) <= 1 << 30, 'array address overflow')
    need(max(vc, ic) <= 0xffffffff, 'draw/index overflow')
    return vw, iw, vcap, icap


def rgb_palette():
    authored = [(0.736340, 0.114340, 173.8965), (0.733411, 0.093103, 66.0436),
                (0.630974, 0.062930, 239.8232), (0.723628, 0.119039, 64.7019),
                (0.860000, 0.018000, 85.0000)]

    def linear(lightness, chroma, hue):
        a, b = chroma * math.cos(math.radians(hue)), chroma * math.sin(math.radians(hue))
        l = (lightness + .3963377774 * a + .2158037573 * b) ** 3
        m = (lightness - .1055613458 * a - .0638541728 * b) ** 3
        s = (lightness - .0894841775 * a - 1.2914855480 * b) ** 3
        return [4.0767416621 * l - 3.3077115913 * m + .2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - .3413193965 * s,
                -.0041960863 * l - .7034186147 * m + 1.7076147010 * s]

    def encode(channel):
        value = max(0, min(channel, 1))
        return math.floor(255 * (12.92 * value if value <= .0031308 else 1.055 * value ** (1 / 2.4) - .055))

    result = {}
    for material, (lightness, chroma, hue) in enumerate(authored, 1):
        color = linear(lightness, chroma, hue)
        if not all(0 <= c <= 1 for c in color):
            low, high = 0, chroma
            for _ in range(24):
                middle = (low + high) / 2
                if all(0 <= c <= 1 for c in linear(lightness, middle, hue)):
                    low = middle
                else:
                    high = middle
            color = linear(lightness, low, hue)
        swatches = []
        for amount in (1, .58, .35):
            r, g, b = [encode(c * amount) for c in color]
            swatches.append(r << 16 | g << 8 | b)
        result[str(material)] = swatches
    return result


def packed_check(mesh, palette):
    fs, vs, ix = mesh['faces'], mesh['vertices'], mesh['indices']
    q = len(fs)
    vw, iw, vcap, icap = size_check(q, mesh['size'])
    need(len(vs) == vcap and len(ix) == icap, 'actual array capacity mismatch')
    need(not any(vs[vw:]) and not any(ix[iw:]), 'nonzero padding')
    all_low, all_high = [LIMIT] * 3, [0] * 3
    directions = set()
    for number, f in enumerate(fs):
        kind, x, y, z, direction, material, width, height = f
        anchor = [x, y, z]
        need(kind in (0, 1) and 0 <= direction < 6, 'face tag/direction')
        need(kind == 1 or (width, height) == (1, 1), 'unit face size')
        need(material != 0 and width > 0 and height > 0, 'nonpositive/air patch')
        normal_axis = direction // 2
        tangent_axes = [axis for axis in range(3) if axis != normal_axis]
        u, v = tangent_axes
        high = anchor.copy()
        high[normal_axis] += 1
        high[u] += width
        high[v] += height
        need(all(0 <= lo < hi <= LIMIT for lo, hi in zip(anchor, high)), 'face bound')
        for axis in range(3):
            all_low[axis] = min(all_low[axis], anchor[axis])
            all_high[axis] = max(all_high[axis], high[axis])
        plane = anchor[normal_axis] + direction % 2
        expected_corners = set()
        for du in (0, width):
            for dv in (0, height):
                point = anchor.copy()
                point[normal_axis] = plane
                point[u] += du
                point[v] += dv
                expected_corners.add(tuple(point))
        records = [vs[number * 40 + i * 10:number * 40 + (i + 1) * 10] for i in range(4)]
        points = [tuple(f32(word) for word in r[:3]) for r in records]
        need(set(points) == expected_corners and len(set(points)) == 4, f'corners at {number}')
        need(points[0] == tuple(anchor[a] if a != normal_axis else plane for a in range(3)), 'first corner ordering')
        light = 0 if direction == 5 else 1 if direction < 2 else 2
        rgb = palette[str(material)][light] if str(material) in palette else 0xff00ff
        encoded = ((rgb >> 16) & 255) | (rgb & 0xff00) | ((rgb & 255) << 16) | (direction << 24)
        for record in records:
            need(record[3] == encoded, f'basic RGB/direction at {number}')
            need(record[4] == material, f'full U32 material at {number}')
            need(record[5:10] == [bits(value) for value in anchor + [width, height]], f'flat identity at {number}')
        actual_ix = ix[number * 6:number * 6 + 6]
        need(actual_ix == [number * 4 + i for i in (0, 1, 2, 2, 3, 0)], f'indices at {number}')
        normal = [0, 0, 0]
        normal[normal_axis] = 1 if direction % 2 else -1
        for start in (0, 3):
            a, b, c = [points[i - number * 4] for i in actual_ix[start:start + 3]]
            ab, ac = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
            cross = [ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0]]
            need(cross == [value * width * height for value in normal], f'outward area at {number}')
        directions.add(direction)
    need(mesh['bounds'] == (all_low + all_high if q else None), 'bounds metadata')
    vertex_bytes, index_bytes = little_words(vs[:vw]), little_words(ix[:iw])
    return {'quads': q, 'vertex_bytes': len(vertex_bytes), 'index_bytes': len(index_bytes),
            'geometry_sha256': sha(vertex_bytes + index_bytes), 'directions': sorted(directions)}


class Occupancy:
    def __init__(self, body):
        self.body = body
        self.sources = {}
        if 'side' in body:
            n = body['side']
            need(n > 0 and n & (n - 1) == 0, 'dense shape')
            need(len(body['cells']) == n ** 3, 'dense cells')
            self.low, self.shape = [0, 0, 0], [n, n, n]
            self.cells = array.array('I', body['cells'])
        else:
            boxes = body['boxes']
            for b in boxes:
                need(all(0 <= b[a] < b[a + 3] <= LIMIT for a in range(3)), 'source bounds')
            solid = [b for b in boxes if b[6]]
            self.low = [min((b[a] for b in solid), default=0) for a in range(3)]
            high = [max((b[a + 3] for b in solid), default=0) for a in range(3)]
            self.shape = [high[a] - self.low[a] for a in range(3)]
            self.cells = array.array('I', [0]) * math.prod(self.shape)
            sx, sy, sz = self.shape
            for rank, b in enumerate(boxes):
                if not b[6]:
                    continue
                lo = [b[a] - self.low[a] for a in range(3)]
                hi = [b[a + 3] - self.low[a] for a in range(3)]
                row = array.array('I', [b[6]]) * (hi[0] - lo[0])
                for z in range(lo[2], hi[2]):
                    for y in range(lo[1], hi[1]):
                        start = (z * sy + y) * sx + lo[0]
                        need(not any(self.cells[start:start + len(row)]), 'source nonair overlap')
                        self.cells[start:start + len(row)] = row
                for direction in range(6):
                    axis = direction // 2
                    plane = b[axis + 3] if direction % 2 else b[axis]
                    self.sources.setdefault((direction, plane), []).append((rank, b))
        self.occupied = sum(bool(m) for m in self.cells)
        self.expected = bytearray(len(self.cells))
        sx, sy, sz = self.shape
        strides = [1, sx, sx * sy]
        for i, mat in enumerate(self.cells):
            if not mat:
                continue
            local = [i % sx, i // sx % sy, i // (sx * sy)]
            mask = 0
            for axis in range(3):
                for positive in (0, 1):
                    direction = axis * 2 + positive
                    neighbor = local[axis] + (1 if positive else -1)
                    if neighbor < 0 or neighbor >= self.shape[axis] or not self.cells[i + (strides[axis] if positive else -strides[axis])]:
                        mask |= 1 << direction
            self.expected[i] = mask

    def index(self, xyz):
        local = [xyz[a] - self.low[a] for a in range(3)]
        need(all(0 <= local[a] < self.shape[a] for a in range(3)), 'emitted face outside source extent')
        return (local[2] * self.shape[1] + local[1]) * self.shape[0] + local[0]

    def coverage(self, mesh):
        seen = bytearray(len(self.cells))
        order = []
        for face in mesh['faces']:
            kind, x, y, z, direction, material, width, height = face
            anchor = [x, y, z]
            axis = direction // 2
            tangents = [a for a in range(3) if a != axis]
            if 'boxes' in self.body:
                candidates = []
                for rank, b in self.sources[(direction, anchor[axis] + direction % 2)]:
                    if b[6] == material and all(b[a] <= anchor[a] and anchor[a] + extent <= b[a + 3] for a, extent in zip(tangents, [width, height])):
                        candidates.append(rank)
                need(len(candidates) == 1, 'rectangle spans source/material boundaries')
                order.append((candidates[0], direction))
            for du in range(width):
                for dv in range(height):
                    xyz = anchor.copy()
                    xyz[tangents[0]] += du
                    xyz[tangents[1]] += dv
                    index = self.index(xyz)
                    mask = 1 << direction
                    need(self.cells[index] == material, f'wrong owning material {xyz} {direction}')
                    need(self.expected[index] & mask, f'extra/internal face {xyz} {direction}')
                    need(not seen[index] & mask, f'duplicate face {xyz} {direction}')
                    seen[index] |= mask
        need(seen == self.expected, 'missing exterior coverage')
        if 'side' in self.body:
            expected = []
            sx, sy, sz = self.shape
            for i in range(len(self.cells) - 1, -1, -1):
                for direction in range(5, -1, -1):
                    if self.expected[i] & (1 << direction):
                        expected.append([0, i % sx, i // sx % sy, i // (sx * sy), direction, self.cells[i], 1, 1])
            need(mesh['faces'] == expected, 'dense Surface.build ordering changed')
        else:
            need(order == sorted(order), 'source/direction ordering changed')
        return sum(mask.bit_count() for mask in self.expected)

    def raw(self):
        return little_words(self.cells)


def independent_demo_brush(occupancy):
    fp = lambda value: f32(bits(value))
    yaw, pitch = fp(1.90401163), fp(-.30)
    cy, sy, cp, sp = [fp(value) for value in (math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch))]
    right = [sy, -cy, 0.]
    up = [fp(-fp(sp * cy)), fp(-fp(sp * sy)), cp]
    forward = [fp(cp * cy), fp(cp * sy), sp]
    eye = [310., -50., 110.]
    pixel = [fp((226.5 - 256) / 420), fp((256 - 224.5) / 420)]
    ray = [fp(forward[a] + fp(fp(right[a] * pixel[0]) + fp(up[a] * pixel[1]))) for a in range(3)]
    hits = []
    for source in occupancy.body['boxes']:
        if not source[6]:
            continue
        near, far = [], []
        for axis in range(3):
            ends = sorted([(source[axis] - eye[axis]) / ray[axis], (source[axis + 3] - eye[axis]) / ray[axis]])
            near.append(ends[0])
            far.append(ends[1])
        depth = max(near)
        if .1 <= depth <= min(far):
            hits.append((depth, near.index(depth), source))
    need(bool(hits), 'independent original-box ray misses')
    _, axis, source = min(hits)
    plane = source[axis] if ray[axis] > 0 else source[axis + 3]
    depth = fp(fp(plane - eye[axis]) / ray[axis])
    point = [fp(eye[a] + fp(ray[a] * depth)) for a in range(3)]
    brush = [fp(10 * value) for value in point] + [20.]
    return brush, {'cell': [math.floor(value) for value in point], 'material': source[6],
                   'direction': axis * 2 + (0 if ray[axis] > 0 else 1)}


def metric_removed(original, carved, brush):
    need(original.low == carved.low and original.shape == carved.shape, 'Atelier extent changed')
    center = brush[:3]
    radius = brush[3]
    sx, sy, sz = original.shape
    removed = []
    for i, (before, after) in enumerate(zip(original.cells, carved.cells)):
        if not before:
            need(after == 0, 'cut added occupied cells')
            continue
        xyz = [i % sx + original.low[0], i // sx % sy + original.low[1], i // (sx * sy) + original.low[2]]
        dx, dy, dz = [value * 10 + 5 - c for value, c in zip(xyz, center)]
        expected = 0 if dx * dx + dy * dy + dz * dz <= radius * radius else before
        need(after == expected, f'pinned metric cut set differs at {xyz}')
        if after != before:
            removed.append(xyz + [before])
    return removed


def verify(path):
    palette = rgb_palette()
    rows = [json.loads(line) for line in Path(path).read_text().splitlines() if line.startswith('{')]
    cases = {r['case']: r for r in rows if 'case' in r}
    sources = {r['original_case']: r['source_body'] for r in rows if 'original_case' in r}
    for name, original in sources.items():
        need(cases[name]['body'] == original, f'build changed edit authority in {name}')
    required = set(ERRORS) | {'empty-boxes', 'empty-dense', 'cube', 'cube-carved', 'dense-materials',
                              'all-air-boxes', 'air-overlap-first', 'air-overlap-last', 'touching', 'touching-cut',
                              'dense-cavity', 'tiled', 'cavity', 'coordinate-limit', 'asymmetric',
                              'atelier-intact', 'atelier-carved', 'atelier-repeat', 'atelier-reset'}
    need(set(cases) == required, f'incomplete fixture corpus {set(cases) ^ required}')
    need(len(cases) == sum('case' in r for r in rows), 'duplicate case rows')
    need(set(sources) == {name for name, row in cases.items() if row.get('body') is not None}, 'original source coverage')
    need(len(sources) == sum('original_case' in r for r in rows), 'duplicate original sources')
    report = {}
    atelier = {}
    for row in rows:
        if 'size_q' in row:
            q = row['size_q']
            if q > QUAD_LIMIT:
                need('error' in row and 'size' not in row, 'overflow accepted')
            else:
                size_check(q, row['size'])
            continue
        if 'case' not in row:
            continue
        name = row['case']
        if name in ERRORS:
            need(row.get('error') == ERRORS[name] and 'mesh' not in row, f'wrong rejection {name}')
            report[name] = {'rejected': row['error']}
            continue
        need('mesh' in row and 'error' not in row, f'unexpected build failure {name}')
        summary = packed_check(row['mesh'], palette)
        if row['body'] is not None:
            need(name in sources, f'missing original pre-build body for {name}')
            occupancy = Occupancy(sources[name])
            summary['occupied'] = occupancy.occupied
            summary['unit_faces'] = occupancy.coverage(row['mesh'])
            summary['occupancy_sha256'] = sha(occupancy.raw())
            if name.startswith('atelier-'):
                atelier[name] = occupancy
        elif name == 'asymmetric':
            need(summary['directions'] == list(range(6)), 'asymmetric six-direction coverage')
            need(all(f[6:] == [2, 3] for f in row['mesh']['faces']), 'asymmetric extents')
        report[name] = summary
    need(cases['air-overlap-first']['mesh'] == cases['air-overlap-last']['mesh'], 'air box affected geometry')
    need(set(atelier) == {'atelier-intact', 'atelier-carved', 'atelier-repeat', 'atelier-reset'}, 'missing Atelier states')
    intact, carved = atelier['atelier-intact'], atelier['atelier-carved']
    need(intact.occupied == 803970 and carved.occupied == 803954, 'pinned occupied counts')
    need(intact.raw() == atelier['atelier-reset'].raw(), 'reset occupancy differs')
    need(carved.raw() == atelier['atelier-repeat'].raw(), 'repeat occupancy differs')
    for a, b in [('atelier-intact', 'atelier-reset'), ('atelier-carved', 'atelier-repeat')]:
        need(cases[a]['mesh'] == cases[b]['mesh'], f'{a}/{b} exact packed mesh differs')
        need(cases[a]['body'] == cases[b]['body'], f'{a}/{b} exact body differs')
    for name, occupied, faces, quads in [('atelier-intact', 803970, 423136, 10304),
                                          ('atelier-carved', 803954, 423162, 10359),
                                          ('atelier-repeat', 803954, 423162, 10359),
                                          ('atelier-reset', 803970, 423136, 10304)]:
        need(report[name]['occupied'] == occupied and report[name]['unit_faces'] == faces,
             f'{name} pinned occupied/exterior counts')
        need(cases[name]['mesh']['size']['counts'][0] == quads, f'{name} pinned quad count')
    brush_rows = [r for r in rows if 'brush_bits' in r]
    need(len(brush_rows) == 1, 'missing actual viewport brush')
    brush = [f32(word) for word in brush_rows[0]['brush_bits']]
    expected_brush, pick = independent_demo_brush(intact)
    need(brush_rows[0]['brush_bits'] == [bits(value) for value in expected_brush], 'viewport brush differs from independent original-source ray')
    removed = metric_removed(intact, carved, brush)
    need(len(removed) == 16, 'pinned demo removal count')
    report['state_differences'] = {'brush_cm': brush, 'independent_original_box_pick': pick, 'removed_cells_with_material': removed,
                                   'repeat_added': 0, 'repeat_removed': 0, 'reset_added': len(removed),
                                   'reset_mesh_identical': True}
    print(json.dumps(report, indent=2, sort_keys=True))
    print('PASS independent occupancy, exterior coverage, actual packed arrays, six-direction winding, state differences')


if __name__ == '__main__':
    verify(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'build/geometry-dump.jsonl')
