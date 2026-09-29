"""Check actual Bend bodies against admitted inputs and an integer face sweep.

This is a runtime reference, independent of Bend's tree traversal and repeated
rectangle subtraction. It never imports or calls those production algorithms.
"""

from collections import Counter, defaultdict
import hashlib
import json
import math
import re
import struct

from megascene_recipe import Box, bits, checked, connected, f32, volume

SCHEMA = "megascene-evidence/1"


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(text):
    return json.loads(text, object_pairs_hook=unique_object,
                      parse_constant=lambda value: fail(f"nonfinite JSON token: {value}"))


def fail(reason):
    raise ValueError(reason)


def require(ok, reason):
    if not ok:
        fail(reason)


def integer(value, signed=False):
    pattern = r"(?:0|[1-9][0-9]*|-[1-9][0-9]*)" if signed else r"(?:0|[1-9][0-9]*)"
    require(isinstance(value, str) and re.fullmatch(pattern, value) is not None,
            "noncanonical integer")
    return int(value)


def real(value):
    require(isinstance(value, str) and re.fullmatch(r"0x[0-9a-f]{8}", value) is not None,
            "noncanonical binary32")
    result = struct.unpack(">f", bytes.fromhex(value[2:]))[0]
    require(math.isfinite(result), "nonfinite binary32")
    return result


def coordinate(value):
    result = real(value)
    require(result.is_integer(), "nonintegral cell coordinate")
    return int(result)


def plane_sweep(front, back=()):
    """Canonical labelled coverage of front rectangles minus the back mask.

    Sweep endpoint events, merging equal adjacent strips/intervals. Front
    overlaps are rejected even when their materials agree. No unit-cell
    expansion and no production face-clipping routines are used.
    """
    if not front:
        return []
    xs = sorted({x for rect in (*front, *back) for x in rect[:2]})
    strips = []
    for lo, hi in zip(xs, xs[1:]):
        events = defaultdict(list)
        for group, rectangles in enumerate((front, back)):
            for x0, x1, y0, y1, material in rectangles:
                require(x0 < x1 and y0 < y1, "empty surface rectangle")
                if x0 <= lo and hi <= x1:
                    events[y0].append((group, material, 1))
                    events[y1].append((group, material, -1))
        active = [Counter(), Counter()]
        intervals = []
        ys = sorted(events)
        for j, y in enumerate(ys):
            for group, material, delta in events[y]:
                active[group][material] += delta
            if j + 1 == len(ys):
                break
            count = sum(active[0].values())
            require(count <= 1, "duplicate surface coverage")
            if count == 1 and sum(active[1].values()) == 0:
                material = next(m for m, n in active[0].items() if n)
                end = ys[j+1]
                if intervals and intervals[-1][1] == y and intervals[-1][2] == material:
                    intervals[-1][1] = end
                else:
                    intervals.append([y, end, material])
        if intervals:
            if strips and strips[-1][1] == lo and strips[-1][2] == intervals:
                strips[-1][1] = hi
            else:
                strips.append([lo, hi, intervals])
    return strips


def occupancy_sweep(boxes):
    """X slabs of Y slabs of material-labelled Z intervals; no dense cells."""
    xs = sorted({c for box in boxes for c in (box.lo[0], box.hi[0])})
    result = []
    for lo, hi in zip(xs, xs[1:]):
        rectangles = [(b.lo[1], b.hi[1], b.lo[2], b.hi[2], b.material)
                      for b in boxes if b.lo[0] <= lo and hi <= b.hi[0]]
        content = plane_sweep(rectangles)
        if content:
            if result and result[-1][1] == lo and result[-1][2] == content:
                result[-1][1] = hi
            else:
                result.append([lo, hi, content])
    return result


def surface_reference(boxes):
    boundaries = defaultdict(list)
    for b in boxes:
        for side in range(6):
            axis = side // 2
            u, v = (axis+1) % 3, (axis+2) % 3
            p = (b.lo, b.hi)[side % 2][axis]
            boundaries[side, p].append((b.lo[u], b.hi[u], b.lo[v], b.hi[v], b.material))
    result = {}
    for (side, p), rectangles in boundaries.items():
        coverage = plane_sweep(rectangles, boundaries.get((side ^ 1, p), ()))
        if coverage:
            result[side, p] = coverage
    return result


def surface_actual(faces):
    rectangles = defaultdict(list)
    for lo, hi, side, material in faces:
        require(0 <= side < 6 and 1 <= material <= 5, "invalid surface label")
        axis = side // 2
        require(lo[axis] == hi[axis], "nonplanar surface")
        u, v = (axis+1) % 3, (axis+2) % 3
        rectangles[side, lo[axis]].append((lo[u], hi[u], lo[v], hi[v], material))
    return {key: plane_sweep(value) for key, value in rectangles.items()}


def verify_vertices(faces, vertices):
    require(len(vertices) == checked(len(faces)*6, "actual vertex count"),
            "surface/vertex count mismatch")
    for i, (lo, hi, side, material) in enumerate(faces):
        axis = side // 2
        u, v = (axis+1) % 3, (axis+2) % 3
        expected = {tuple(bits(f32(c * f32(0.1))) for c in point)
                    for point in (lo, hi,
                                  tuple(hi[k] if k == u else lo[k] for k in range(3)),
                                  tuple(hi[k] if k == v else lo[k] for k in range(3)))}
        group = vertices[i*6:i*6+6]
        require(all(len(vertex) == 5 and integer(vertex[3]) == side and
                    integer(vertex[4]) == material for vertex in group), "vertex labels mismatch")
        require({tuple(vertex[:3]) for vertex in group} == expected, "vertex corner mismatch")
        triangles = []
        for j in (0, 3):
            a, b, c = [tuple(real(n) for n in vertex[:3]) for vertex in group[j:j+3]]
            cross = (b[u]-a[u])*(c[v]-a[v]) - (b[v]-a[v])*(c[u]-a[u])
            require(cross * (1 if side % 2 else -1) > 0, "incorrect mesh winding")
            triangles.append(frozenset(tuple(vertex[:3]) for vertex in group[j:j+3]))
        require(triangles[0] != triangles[1] and len(triangles[0] & triangles[1]) == 2,
                "duplicate or incomplete triangles")
        shared = list(triangles[0] & triangles[1])
        require(shared[0][u] != shared[1][u] and shared[0][v] != shared[1][v],
                "triangles must share the rectangle diagonal")


def outcome(status, reason, scope, evidence=()):
    require(status in ("pass", "fail", "inconclusive", "not_applicable"), "unknown check status")
    return {"status": status, "reason": reason, "scope": scope, "evidence": list(evidence)}


def measurement(status, reason, scope, unit, value=None):
    require(status in ("measured", "unsupported", "disabled", "not_ready", "not_executed",
                       "incomplete", "collection_failure"), "unknown measurement status")
    require((status == "measured" and value is not None) or
            (status != "measured" and value is None and bool(reason)), "invalid measurement status/value")
    if status == "measured":
        if isinstance(value, str):
            real(value) if value.startswith("0x") else integer(value, signed=True)
        else:
            require(type(value) is float and math.isfinite(value), "measurement needs an exact string or finite statistic")
    return dict(status=status, reason=reason, scope=scope, unit=unit, value=value)


def read_evidence(path):
    record = read_json(path.read_text())
    require(record.get("schema") == SCHEMA, "unsupported evidence schema")
    return record


def inventory(text, owners, config, numeric):
    require(text.endswith("\n"), "truncated worker output")
    records = [read_json(line) for line in text.splitlines()]
    require(len(records) == len(owners)+2, "missing/extra worker records")
    world, *bodies, end = records
    require(world.get("schema") == "megascene-worker/1" and world.get("record_type") == "world",
            "unsupported worker schema")
    require(end == {"record_type": "complete"}, "incomplete worker output")
    for key, expected in {"threads": config["threads"], "cells": numeric["cells"],
                          "budget": config["fragment_budget"], "next_id": str(len(owners)+1),
                          "fragments": "0", "removed": "0", "status": "1"}.items():
        require(world.get(key) == expected, f"world {key} mismatch")
    by_material, by_role = Counter(), Counter()
    area_by_material = Counter()
    result = []
    all_boxes = []
    for ordinal, (owner, body) in enumerate(zip(owners, bodies), 1):
        prefix = f"body {ordinal}: "
        require(body.get("record_type") == "body" and body.get("id") == str(ordinal),
                prefix + "initial owner ordering/ID mismatch")
        require(body.get("revision") == "0" and body.get("offset") == bits(0.0) and
                body.get("speed") == bits(0.0) and body.get("anchored") is True and
                body.get("connected") is True, prefix + "initial state mismatch")
        boxes = []
        for b in body["boxes"]:
            require(len(b) == 7, prefix + "invalid box")
            boxes.append(Box(tuple(map(coordinate, b[:3])), tuple(map(coordinate, b[3:6])), integer(b[6])))
        require(occupancy_sweep(boxes) == occupancy_sweep(owner.boxes), prefix + "occupancy/material mismatch")
        require(connected(boxes) and any(b.material == 1 for b in boxes), prefix + "connectivity/anchor mismatch")
        cells = checked(sum(volume(b) for b in boxes), "actual cell sum")
        require(body["cells"] == str(cells) and body["cuboids"] == str(len(boxes)) and
                body["tree_nodes"] == str(2*len(boxes)-1), prefix + "tree inventory mismatch")
        faces = []
        for face in body["faces"]:
            require(len(face) == 8, prefix + "invalid face")
            faces.append((tuple(map(coordinate, face[:3])), tuple(map(coordinate, face[3:6])),
                          integer(face[6]), integer(face[7])))
        require(len(faces) <= integer(numeric["surface_rectangle_bounds"][ordinal-1]),
                prefix + "surface bound exceeded")
        require(surface_actual(faces) == surface_reference(boxes), prefix + "exposed surface mismatch")
        verify_vertices(faces, body["vertices"])
        area = checked(sum(math.prod(hi[k]-lo[k] for k in range(3) if k != side//2)
                           for lo, hi, side, _ in faces), "actual surface area")
        for lo, hi, side, material in faces:
            area_by_material[str(material)] += math.prod(hi[k]-lo[k] for k in range(3) if k != side//2)
        for b in boxes:
            by_material[str(b.material)] += volume(b)
        by_role[owner.role] += cells
        all_boxes.extend(boxes)
        result.append({"id": str(ordinal), "role": owner.role,
                       "neighborhood": None if owner.neighborhood is None else str(owner.neighborhood),
                       "cells": str(cells), "authored_boxes": str(len(owner.boxes)),
                       "cuboids": body["cuboids"], "tree_nodes": body["tree_nodes"],
                       "surface_rectangles": str(len(faces)), "exposed_area_cell_faces": str(area),
                       "vertices": str(len(body["vertices"])), "revision": body["revision"],
                       "anchored": True, "offset_m": body["offset"], "speed_m_s": body["speed"],
                       "production_record_sha256": digest(body)})
    total = checked(sum(by_material.values()), "actual world cells")
    require(str(total) == numeric["cells"], "production cell total mismatch")
    half = int(config.get("envelope_side_m", config["side_m"]))*5
    out = {"schema": SCHEMA, "record_type": "inventory", "requested_controls": config,
           "generation_envelope_cells": {"lo": [str(-half), "0", str(-half)],
                                         "hi": [str(half), "128", str(half)]},
           "occupied_bounds_cells": {"lo": [str(min(b.lo[k] for b in all_boxes)) for k in range(3)],
                                     "hi": [str(max(b.hi[k] for b in all_boxes)) for k in range(3)]},
           "cell_size_m": bits(0.1), "cells": str(total),
           "cells_by_material": {str(m): str(by_material[str(m)]) for m in range(1,6)},
           "cells_by_role": {k: str(v) for k, v in sorted(by_role.items())},
           "protected_cells": str(by_material["1"]),
           "exposed_area_by_material_cell_faces": {str(m): str(area_by_material[str(m)]) for m in range(1,6)},
           "surface_scope": "per-owner exposed faces; includes contact between different owners; internal material interfaces are hidden",
           "bodies": {"initial_owners": str(len(bodies)), "total": str(len(bodies)),
                      "anchored": str(len(bodies)), "detached_fragments": "0", "moving": "0"},
           "fragment_budget": world["budget"], "next_id": world["next_id"],
           "density": {"numerator": str(total), "denominator": str((2*half)**2*128)},
           "owners": result, "validation": "validation.json"}
    for key in ("authored_boxes", "cuboids", "tree_nodes", "surface_rectangles", "exposed_area_cell_faces", "vertices"):
        out[key] = str(checked(sum(integer(body[key]) for body in result), key))
    if "control_effects" in numeric:
        out["control_comparison"] = {**numeric["control_effects"],
            "achieved": {key: out[key] for key in ("cells", "cells_by_material", "protected_cells",
                "generation_envelope_cells", "occupied_bounds_cells", "cuboids", "surface_rectangles",
                "exposed_area_cell_faces", "exposed_area_by_material_cell_faces", "vertices")}}
    return out
