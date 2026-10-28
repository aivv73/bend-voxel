from dataclasses import dataclass
from fractions import Fraction
import itertools
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
HIGH_MATERIAL = 0x80000102


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def contains(cell, center):
    squared = []
    for c, p in zip(cell, center):
        delta = Fraction(f32(float(Fraction(10 * c + 5) - Fraction(p))))
        squared.append(Fraction(f32(float(delta * delta))))
    total = Fraction(f32(float(squared[0] + squared[1])))
    total = Fraction(f32(float(total + squared[2])))
    return total <= 400


def selected_cells(center):
    if center is None:
        return []
    ranges = [range(max(0, int(p / 10) - 4), min(1048576, int(p / 10) + 5)) for p in center]
    return [c for c in itertools.product(*ranges) if contains(c, center)]


@dataclass(frozen=True)
class Case:
    name: str
    direction: int
    anchor: tuple[int, int, int]
    u: float
    v: float
    width: float
    height: float
    material: int
    brush: tuple[float, float, float] | None
    cell: tuple[int, int, int]
    selected: bool
    production: bool = False

    @property
    def modes(self):
        return (0, 1, 2, 3, 4, 5, 6, 7) if self.material == HIGH_MATERIAL or self.selected else (1, 2, 3, 4, 5, 6, 7)


def rows():
    result = []
    offsets = ((0, 0), (0, 1), (0, 2), (0, 2),
               (1, 0), (1, 1), (1, 2), (1, 2),
               (1, 0), (1, 1), (1, 2), (1, 2))
    for d in range(6):
        for index, (u, v) in enumerate(itertools.product((0, 1, 2), (0, 1, 2, 3))):
            du, dv = offsets[index]
            expected = ((7, 11 + du, 13 + dv), (7 + du, 11, 13 + dv), (7 + du, 11 + dv, 13))[d // 2]
            result.append(Case(f'grid-{d}-{u}-{v}', d, (7, 11, 13), u, v, 2, 3,
                               HIGH_MATERIAL, None, expected, False))
    result.append(Case('normalized-width-41', 5, (7, 11, 13), 1, 0, 41, 3,
                       HIGH_MATERIAL, None, (7, 11, 13), False))
    for d in range(6):
        for selected in (False, True):
            result.append(Case(f'known-{d}-{int(selected)}', d, (7, 11, 13), .5, .5, 2, 3,
                               d % 5 + 1, (75, 115, 135) if selected else None,
                               (7, 11, 13), selected))
    selection = (
        ('inclusive', (6, 6, 6), (45, 65, 65), True),
        ('adjacent-outside', (6, 6, 6), (f32(44.999996185302734375), 65, 65), False),
        ('adjacent-inside', (6, 6, 6), (f32(45.000003814697265625), 65, 65), True),
        ('orthogonal-f32-inclusive', (4, 4, 6), (f32(44.999996185302734375), 65, 65), True),
        ('demo-selected', (6, 6, 6), (65, 65, 65), True),
        ('demo-outside', (0, 0, 0), (65, 65, 65), False),
        ('scene-edge-inclusive', (0, 0, 0), (25, 5, 5), True),
        ('limit-selected', (1048575, 1048575, 1048575), (10485760, 10485760, 10485760), True),
    )
    for name, cell, center, selected in selection:
        assert contains(cell, center) == selected
        result.append(Case(name, 4 if name == 'limit-selected' else 5, cell, .5, .5, 1 if name == 'limit-selected' else 2,
                           1 if name == 'limit-selected' else 3, HIGH_MATERIAL, center, cell, selected))
    for d in range(6):
        result.append(Case(f'production-rectangle-{d}', d, (7, 11, 13), .5, .5, 2, 3,
                           HIGH_MATERIAL, (75, 115, 135), (7, 11, 13), True, True))
    return result


def float_literal(value):
    return repr(float(value))


def cell_literal(cell):
    return 'X.Cell{' + ','.join(map(str, cell)) + '}'


def generate():
    code = ['import Base\nimport ./appearance_gpu.bend as G\nimport ../../voxel.bend as X\n\n',
            'def rows() -> List<&2,G.Case>:\n  [\n']
    for c in rows():
        brush = 'None{}' if c.brush is None else 'Some{X.MetricSphere.brush(X.PointCm{' + ','.join(map(float_literal, c.brush)) + '})}'
        fields = [json.dumps(c.name), str(c.direction), cell_literal(c.anchor),
                  *map(float_literal, (c.u, c.v, c.width, c.height)), str(c.material), brush,
                  cell_literal(c.cell), 'True{}' if c.selected else 'False{}',
                  'True{}' if c.production else 'False{}']
        code.append('    G.Case{' + ','.join(fields) + '},\n')
    code.append('  ]\n')
    (ROOT / 'tests/appearance_cases.bend').write_text(''.join(code))
    (ROOT / 'build/milestone-6-shader-cases.json').write_text(json.dumps([c.__dict__ for c in rows()], indent=2) + '\n')
    print(f'{len(rows())} literal cases generated')


if __name__ == '__main__':
    generate()
