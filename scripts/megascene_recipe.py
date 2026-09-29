"""Mixed Megascene source generator; arithmetic precedes Bend construction."""

from dataclasses import dataclass
from itertools import combinations
import math
import struct
from megascene_scale import side_count, preset_for

U32_MAX = 2**32 - 1


def checked(value, label, maximum=U32_MAX):
    if type(value) is not int or not 0 <= value <= maximum:
        raise ValueError(f"{label}: unsigned integer exceeds supported range")
    return value


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def bits(value):
    if not math.isfinite(value):
        raise ValueError("nonfinite binary32 value")
    return "0x" + struct.pack(">f", value).hex()


@dataclass(frozen=True)
class Box:
    lo: tuple
    hi: tuple
    material: int

    def record(self):
        return {"lo": list(map(str, self.lo)), "hi": list(map(str, self.hi)),
                "material": str(self.material)}


@dataclass
class Owner:
    role: str
    neighborhood: int | None
    boxes: list


CONTROLS = ("spread", "material-detail", "surface-detail", "fill", "body-rich")


def envelope_cells(preset, control=None):
    q = side_count(preset)
    return 640 * (q-1) + 320 if control == "spread" else 320 * q


def generate(preset, seed, control=None):
    q = side_count(preset)
    preset_for(q)
    if seed not in (45, 46):
        raise ValueError("only seeds 45/46 are supported")
    if control not in (None, *CONTROLS):
        raise ValueError("unsupported terrain control")
    spacing = 640 if control == "spread" else 320
    half = envelope_cells(preset, control)//2
    terrain = Owner("terrain", None, [])
    owners = [terrain]
    for iz in range(q):
        for ix in range(q):
            n = checked(ix + checked(q * iz, "row offset"), "neighborhood")
            v = (3 * ix + 5 * iz + seed - 45) % 4
            ox, oz = spacing * ix - half, spacing * iz - half

            def add(owner, x, y, z, material):
                def append(x0, x1, y0, y1, z0, z1, m):
                    owner.boxes.append(Box((x0+ox,y0,z0+oz),(x1+ox,y1,z1+oz),m))
                if control == "fill":
                    if owner is terrain:
                        if y[0] >= 8:
                            y = (y[0]+8,y[1]+8)
                    else:
                        y = (y[0]+8,y[1]+8)
                if control == "surface-detail" and owner is terrain and (x,y,z) == ((224,288),(8,24),(0,240)):
                    append(224,288,8,22,0,240,material)
                    cursor = 224
                    for u in range(8):
                        x0 = 224+6*u
                        if cursor < x0:
                            append(cursor,x0,22,24,0,240,material)
                        zcursor = 0
                        for w in range(8):
                            z0 = 16+6*w
                            if zcursor < z0:
                                append(x0,x0+2,22,24,zcursor,z0,material)
                            zcursor = z0+2
                        append(x0,x0+2,22,24,zcursor,240,material)
                        cursor = x0+2
                    append(cursor,288,22,24,0,240,material)
                elif control == "material-detail" and owner is terrain and material == 2:
                    for x0 in range(x[0],x[1],4):
                        x1 = min(x0+4,x[1])
                        append(x0,x1,*y,*z,2 if (x0//4)%2 == 0 else 5)
                else:
                    append(*x,*y,*z,material)

            for x, y, z, m in [
                ((0,320),(0,1),(0,320),1),
                ((0,320),(1,8),(0,320),2),
                ((0,224),(8,24),(0,320),2),
                ((288,320),(8,24),(0,320),2),
                ((224,288),(8,24),(0,240),2),
                ((224,288),(8,24),(304,320),2),
                ((224,288),(22,24),(271,273),2),
                ((160,208),(24,32+2*v),(16,64),2),
                ((160,184),(24,32+2*v),(64,96),2),
                ((184,208),(24,28),(64,96),2),
            ]:
                add(terrain, x, y, z, m)
            if control == "fill":
                # The lower layers and y=0 foundation stay in place. The new
                # concrete fills the whole patch between old and raised layers.
                terrain.boxes.append(Box((ox,8,oz),(ox+320,16,oz+320),2))
            building = Owner("building", n, [])
            h = 80 + 2 * v
            for x in ((16,24),(128,136)):
                for z in ((16,24),(128,136)):
                    add(building, x, (24,26), z, 1)
            for x, y, z, m in [
                ((16,136),(26,28),(16,136),5),
                ((16,20),(28,h),(20,132),5),
                ((16,136),(28,h),(132,136),5),
                ((16,64),(28,h),(16,20),5),
                ((88,136),(28,h),(16,20),5),
                ((64,88),(60,h),(16,20),5),
                ((132,136),(28,h),(20,56),5),
                ((132,136),(28,h),(80,132),5),
                ((132,136),(28,44),(56,80),5),
                ((132,136),(64,h),(56,80),5),
                ((76,80),(28,h),(48,72),2),
                ((76,80),(28,h),(88,112),2),
                ((76,80),(60,h),(72,88),2),
                ((16,48),(h,h+3),(16,136),3),
                ((72,136),(h,h+3),(16,136),3),
                ((48,72),(h,h+3),(16,96),3),
                ((48,72),(h,h+3),(120,136),3),
            ]:
                add(building, x, y, z, m)
            if control == "body-rich":
                left = Owner("building_left", n, [])
                right = Owner("building_right", n, [])
                for box in building.boxes:
                    for piece, x0, x1 in ((left, box.lo[0], ox+72), (right, ox+80, box.hi[0])):
                        lo, hi = max(box.lo[0], x0), min(box.hi[0], x1)
                        if lo < hi:
                            piece.boxes.append(Box((lo,*box.lo[1:]),(hi,*box.hi[1:]),box.material))
                owners.extend((left,right))
            else:
                owners.append(building)
            for j in range(3):
                span = Owner(f"span{j}", n, [])
                owners.append(span)
                z, b = 176 + 24*j, 72 + v
                for x, y, zr, m in [
                    ((22,28),(24,26),(z+1,z+7),1),
                    ((124,130),(24,26),(z+1,z+7),1),
                    ((24,26),(26,b),(z+3,z+5),3),
                    ((126,128),(26,b),(z+3,z+5),3),
                    ((16,136),(b,b+4),(z,z+8),2),
                ]:
                    add(span, x, y, zr, m)
            assembly = Owner("irregular", n, [])
            owners.append(assembly)
            for x, y, z, m in [
                ((280,288),(24,26),(176,184),1),
                ((280,288),(26,42),(176,184),4),
                ((272,288),(42,50),(168,184),4),
                ((280,296),(50,58+v%2),(176,192),3),
                ((288,302+v%2),(34,50),(184,199),4),
            ]:
                add(assembly, x, y, z, m)
    if control == "spread":
        def connector(x0,x1,z0,z1):
            terrain.boxes.append(Box((x0,0,z0),(x1,1,z1),1))
            terrain.boxes.append(Box((x0,1,z0),(x1,24,z1),2))
        for iz in range(q):
            for ix in range(q-1):
                x0 = spacing*ix-half+320
                z0 = spacing*iz-half+158
                connector(x0,x0+320,z0,z0+2)
        for iz in range(q-1):
            x0 = 158-half
            z0 = spacing*iz-half+320
            connector(x0,x0+2,z0,z0+320)
    return owners


def volume(box):
    value = 1
    for lo, hi in zip(box.lo, box.hi):
        value = checked(value * checked(hi - lo, "box dimension"), "box volume")
    return value


def overlaps(a, b):
    return all(max(l, x) < min(h, y) for l, h, x, y in zip(a.lo, a.hi, b.lo, b.hi))


def connected(boxes):
    if not boxes:
        return False
    reached, pending = {0}, [0]
    while pending:
        a = boxes[pending.pop()]
        for j, b in enumerate(boxes):
            if j in reached:
                continue
            if any((a.hi[k] == b.lo[k] or b.hi[k] == a.lo[k]) and
                   all(max(a.lo[t], b.lo[t]) < min(a.hi[t], b.hi[t])
                       for t in range(3) if t != k) for k in range(3)):
                reached.add(j)
                pending.append(j)
    return len(reached) == len(boxes)


def surface_bound(boxes):
    """Bound clipping output before calling unsafe Bend surface construction.

    All cut lines are source endpoints. A nonempty output rectangle contains
    at least one unique elementary rectangle in this face's endpoint grid.
    Counting that grid (including covered cells) bounds every clipping stage.
    """
    total = 0
    for box in boxes:
        for axis in range(3):
            u, v = (axis+1) % 3, (axis+2) % 3
            for side in (0, 1):
                plane = (box.lo, box.hi)[side][axis]
                edges = [{box.lo[t], box.hi[t]} for t in (u, v)]
                for other in boxes:
                    if (other.hi, other.lo)[side][axis] != plane:
                        continue
                    if all(max(box.lo[t], other.lo[t]) < min(box.hi[t], other.hi[t])
                           for t in (u, v)):
                        for e, t in zip(edges, (u, v)):
                            e.update((max(box.lo[t], other.lo[t]), min(box.hi[t], other.hi[t])))
                total = checked(total + checked((len(edges[0])-1) * (len(edges[1])-1),
                                               "face grid"), "surface bound")
    return total


def admit_sources(owners, half_extent, budget):
    checked(budget, "fragment budget")
    checked(len(owners) + 1, "next ownership ID")
    all_boxes = [b for o in owners for b in o.boxes]
    total = 0
    bounds = []
    for owner in owners:
        for box in owner.boxes:
            if box.material not in range(1, 6):
                raise ValueError("unsupported material")
            for k, (lo, hi) in enumerate(zip(box.lo, box.hi)):
                low, high = (0, 128) if k == 1 else (-half_extent, half_extent)
                if type(lo) is not int or type(hi) is not int or not low <= lo < hi <= high:
                    raise ValueError("box outside supported fixed generation envelope")
                if f32(lo) != lo or f32(hi) != hi or f32(hi - lo) != hi - lo:
                    raise ValueError("inexact coordinate conversion")
                # S.build uses endpoint sums, twice-midpoints and dimension
                # subtraction. These integer/half-integer values are exact here.
                if f32(lo + hi) != lo + hi:
                    raise ValueError("inexact spatial split")
            total = checked(total + volume(box), "world cell sum")
        if not connected(owner.boxes):
            raise ValueError(f"{owner.role}: not positive-face connected")
        if not any(b.material == 1 for b in owner.boxes):
            raise ValueError(f"{owner.role}: missing protected anchor")
        checked(2 * len(owner.boxes) - 1, "tree nodes")
        bound = surface_bound(owner.boxes)
        vertices = checked(bound * 6, "generated vertices")
        # Conservative 64-byte slot covers both current native structs (20/28
        # bytes) and index/transport sizes. No Vulkan allocation occurs here.
        checked(vertices * 64, "potential geometry bytes")
        bounds.append(bound)
    for a, b in combinations(all_boxes, 2):
        if overlaps(a, b):
            raise ValueError("overlapping source ownership")
    checked(sum(bounds), "world surface bound")
    checked(sum(bounds) * 6 * 64, "world geometry byte bound")
    return {"cells": str(total), "surface_rectangle_bounds": list(map(str, bounds)),
            "vertex_bound": str(sum(bounds) * 6), "geometry_byte_bound": str(sum(bounds) * 6 * 64)}


def bend_program(owners, budget):
    """Only call after admission; serialize integer literals, never user code."""
    def number(n):
        return f"(0.0 - {-n}.0 : F32)" if n < 0 else f"{n}.0"

    def vec(v):
        return "R.Vec{" + ",".join(map(number, v)) + "}"

    lines = ["import Base", "import ./src/math.bend as R",
             "import ./src/spatial.bend as S", "import ./src/showcase.bend as Showcase",
             "import ./src/world.bend as W", "import ./src/megascene.bend as M"]
    for i, owner in enumerate(owners):
        boxes = [f"S.Box{{{vec(b.lo)},{vec(b.hi)},{b.material}}}" for b in owner.boxes]
        lines += [f"def owner{i}() -> Showcase.Assembly:",
                  "  Showcase.Assembly{S.build([" + ",\n    ".join(boxes) + "])}"]
    lines += ["def main() -> IO(Unit):", "  M.emit(W.from.bodies(W.assemblies([" +
              ",".join(f"owner{i}()" for i in range(len(owners))) + f"],1),{budget}))"]
    return "\n".join(lines) + "\n"
