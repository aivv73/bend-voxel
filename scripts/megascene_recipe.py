from dataclasses import dataclass
from itertools import combinations
import math
import json
import struct
from megascene_scale import side_count, preset_for
from megascene_bend import run

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


def _source(q, seed, control):
    return run("megascene_source", q, seed, control or "base")


def source_owners(text, q, seed, control=None):
    """Decode a complete source stream; callers receive fresh mutable owners."""
    if not text.endswith("\n"):
        raise ValueError("truncated Bend source stream")
    def object_pairs(pairs):
        result = dict(pairs)
        if len(result) != len(pairs):
            raise ValueError("duplicate Bend source field")
        return result
    records = [json.loads(line, object_pairs_hook=object_pairs) for line in text.splitlines()]
    if len(records) < 3 or records[-1] != {"record_type": "complete"}:
        raise ValueError("incomplete Bend source stream")
    header = records[0]
    expected_extent = 640*(q-1)+320 if control == "spread" else 320*q
    roles = (("building_left", "building_right") if control == "body-rich" else ("building",)) + (
        "span0", "span1", "span2", "irregular")
    expected_owners = [("terrain", None)] + [(role, n) for n in range(q*q) for role in roles]
    if (type(header) is not dict or
            set(header) != {"record_type", "schema", "side", "seed", "control", "envelope_cells"} or
            header["record_type"] != "source" or header["schema"] != "megascene-source/1" or
            type(header["side"]) is not int or type(header["seed"]) is not int or
            header["side"] != q or header["seed"] != seed or
            header["control"] != (control or "base") or
            type(header["envelope_cells"]) is not int or header["envelope_cells"] != expected_extent or
            len(records) != len(expected_owners)+2):
        raise ValueError("Bend source identity mismatch")
    owners = []
    def coordinate(value):
        if (type(value) not in (int, float) or abs(value) > 2**23 or
                not math.isfinite(value) or value != int(value)):
            raise ValueError("inexact Bend source coordinate")
        return int(value)
    for record, expected_owner in zip(records[1:-1], expected_owners):
        if (type(record) is not dict or set(record) != {"record_type", "role", "neighborhood", "boxes"} or
                record["record_type"] != "owner" or type(record["role"]) is not str or
                (record["role"], record["neighborhood"]) != expected_owner or
                type(record["boxes"]) is not list or not record["boxes"]):
            raise ValueError("invalid Bend source owner")
        n = record["neighborhood"]
        if (n is None and record["role"] != "terrain" or
                n is not None and (type(n) is not int or not 0 <= n < q*q or record["role"] == "terrain")):
            raise ValueError("invalid Bend source neighborhood")
        boxes = []
        for b in record["boxes"]:
            if (type(b) is not dict or set(b) != {"lo", "hi", "material"} or type(b["lo"]) is not list or
                    type(b["hi"]) is not list or len(b["lo"]) != 3 or len(b["hi"]) != 3 or
                    type(b["material"]) is not int or not 1 <= b["material"] <= 5):
                raise ValueError("invalid Bend source box")
            boxes.append(Box(tuple(map(coordinate,b["lo"])),tuple(map(coordinate,b["hi"])),b["material"]))
        owners.append(Owner(record["role"],n,boxes))
    if owners[0].role != "terrain" or sum(o.role == "terrain" for o in owners) != 1:
        raise ValueError("invalid Bend terrain ownership")
    return owners


def generate(preset, seed, control=None):
    q = side_count(preset)
    preset_for(q)
    if type(seed) is not int or seed not in (45, 46):
        raise ValueError("only seeds 45/46 are supported")
    if control not in (None, *CONTROLS):
        raise ValueError("unsupported terrain control")
    return source_owners(_source(q,seed,control),q,seed,control)


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
