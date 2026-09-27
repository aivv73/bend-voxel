"""Export Blender asset collections into editable Bend voxel trees.

Run with: blender -b assets/showcase_assets.blend --python-exit-code 1 --python scripts/export_showcase_assets.py
Closed meshes are sampled at 10 cm cell centers and packed into cuboids.
Grid-aligned cube parts retain their exact bounds. Blender X/Y/Z maps to
engine X/Z/Y respectively.
"""

from collections import Counter
import argparse
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "src/showcase_assets.bend"
MATERIALS = {1: "foundation", 2: "concrete", 3: "frame", 4: "machinery", 5: "plaster"}
GRID = 10  # Cells per meter.
MAX_SAMPLE_CELLS = 1_000_000
MAX_ASSET_BOXES = 4096
FOOTPRINTS = {
    "beacon": (12, 12),
    "cargo_pod": (12, 12),
    "gateway": (50, 20),
}


def cell(value):
    scaled = value * GRID
    rounded = round(scaled)
    if abs(scaled - rounded) > 0.0001:
        raise ValueError(f"Asset bounds must follow the 10 cm grid: {value}")
    return rounded


def exact_box(vertices, polygons):
    """Preserve the original exact export for six-faced, grid-aligned cubes."""
    if len(vertices) != 8 or len(polygons) != 6 or any(len(face) != 4 for face in polygons):
        return None
    try:
        coords = [sorted({cell(vertex[axis] / GRID) for vertex in vertices}) for axis in range(3)]
    except ValueError:
        return None
    if any(len(values) != 2 for values in coords):
        return None
    if {tuple(cell(vertex[axis] / GRID) for axis in range(3)) for vertex in vertices} != {
            (x, y, z) for x in coords[0] for y in coords[1] for z in coords[2]}:
        return None
    faces = Counter()
    for face in polygons:
        fixed = [(axis, round(vertices[face[0]][axis])) for axis in range(3)
                 if all(abs(vertices[index][axis] - vertices[face[0]][axis]) < 0.00001
                        for index in face)]
        if len(fixed) != 1:
            return None
        faces[fixed[0]] += 1
    if faces != Counter({(axis, bound): 1 for axis, values in enumerate(coords) for bound in values}):
        return None
    x, y, z = coords
    return x[0], z[0], y[0], x[1], z[1], y[1]


def closed_mesh(polygons, name):
    edges = Counter()
    for face in polygons:
        for i, a in enumerate(face):
            b = face[(i + 1) % len(face)]
            if a == b:
                raise ValueError(f"Degenerate mesh edge on {name}")
            edges[tuple(sorted((a, b)))] += 1
    if not polygons or not edges or any(count != 2 for count in edges.values()):
        raise ValueError(f"Voxelized mesh must be closed and manifold: {name}")


def inside_mesh(bvh, point):
    # An oblique ray avoids the shared edges of grid-aligned triangles.
    direction = Vector((1.0, 0.037, 0.071)).normalized()
    ray = Vector(point) + direction * 0.000001
    crossings = 0
    for _ in range(1024):
        hit, _, _, _ = bvh.ray_cast(ray, direction)
        if hit is None:
            return bool(crossings % 2)
        crossings += 1
        ray = hit + direction * 0.0001
    raise ValueError("Mesh ray did not leave the surface; check for intersecting geometry")


def mesh_cells(vertices, polygons, name):
    closed_mesh(polygons, name)
    lo = [math.floor(min(vertex[axis] for vertex in vertices)) for axis in range(3)]
    hi = [math.ceil(max(vertex[axis] for vertex in vertices)) for axis in range(3)]
    if lo[2] < 0:
        raise ValueError(f"Asset extends below its placement plane: {name}")
    samples = math.prod(hi[axis] - lo[axis] for axis in range(3))
    if samples > MAX_SAMPLE_CELLS:
        raise ValueError(f"{name} needs {samples} sample cells; limit is {MAX_SAMPLE_CELLS}")
    bvh = BVHTree.FromPolygons(vertices, polygons)
    occupied = set()
    for x in range(lo[0], hi[0]):
        for y in range(lo[1], hi[1]):
            for z in range(lo[2], hi[2]):
                if inside_mesh(bvh, (x + 0.5, y + 0.5, z + 0.5)):
                    occupied.add((x, y, z))
    if not occupied:
        raise ValueError(f"{name} has no occupied 10 cm cell centers")
    return occupied


def pack_cells(cells):
    """Greedily merge same-material cells into disjoint X, then Y, then Z cuboids."""
    remaining = dict(cells)
    boxes = []
    for x, y, z in sorted(remaining):
        material = remaining.get((x, y, z))
        if material is None:
            continue
        x1 = x + 1
        while remaining.get((x1, y, z)) == material:
            x1 += 1
        y1 = y + 1
        while all(remaining.get((i, y1, z)) == material for i in range(x, x1)):
            y1 += 1
        z1 = z + 1
        while all(remaining.get((i, j, z1)) == material
                  for i in range(x, x1) for j in range(y, y1)):
            z1 += 1
        for i in range(x, x1):
            for j in range(y, y1):
                for k in range(z, z1):
                    del remaining[(i, j, k)]
        # Blender X/Y/Z -> engine X/Z/Y.
        boxes.append((x, z, y, x1, z1, y1, material))
    return boxes


def remove_isolated(cells):
    """Optional artist cleanup: discard only cells with no face-connected neighbor."""
    return {(x, y, z) for x, y, z in cells if any(q in cells for q in
            ((x - 1, y, z), (x + 1, y, z), (x, y - 1, z),
             (x, y + 1, z), (x, y, z - 1), (x, y, z + 1)))}


def overlaps(left, right):
    return all(left[axis] < right[axis + 3] and right[axis] < left[axis + 3]
               for axis in range(3))


def asset_boxes(group, depsgraph):
    if "voxel_origin" not in group:
        raise ValueError(f"Missing voxel_origin on {group.name}")
    origin = tuple(group["voxel_origin"])
    if len(origin) != 3:
        raise ValueError(f"Invalid origin for {group.name}")
    exact = []
    sampled = {}
    for obj in sorted(group.objects, key=lambda item: item.name):
        if obj.type != "MESH":
            raise ValueError(f"Only mesh objects are allowed in {group.name}: {obj.name}")
        material = int(obj.get("voxel_material", 0))
        if material not in MATERIALS:
            raise ValueError(f"Invalid voxel material on {obj.name}")
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            vertices = [tuple((evaluated.matrix_world @ vertex.co - Vector(origin)) * GRID)
                        for vertex in mesh.vertices]
            polygons = [tuple(face.vertices) for face in mesh.polygons]
            if not vertices or not all(math.isfinite(value) for vertex in vertices for value in vertex):
                raise ValueError(f"Invalid mesh vertices on {obj.name}")
            bounds = exact_box(vertices, polygons)
            if bounds is not None:
                if bounds[1] < 0:
                    raise ValueError(f"Asset extends below its placement plane: {obj.name}")
                exact.append((*bounds, material))
            else:
                cells = mesh_cells(vertices, polygons, obj.name)
                if obj.get("voxel_remove_isolated", False):
                    cleaned = remove_isolated(cells)
                    print(f"Discarded {len(cells) - len(cleaned)} isolated sample cells on {obj.name}")
                    cells = cleaned
                    if not cells:
                        raise ValueError(f"Isolated-cell cleanup emptied {obj.name}")
                if cells.intersection(sampled):
                    raise ValueError(f"Overlapping voxelized meshes in {group.name}: {obj.name}")
                sampled.update((cell, material) for cell in cells)
                print(f"Voxelized {obj.name}: {len(cells)} occupied cells")
        finally:
            evaluated.to_mesh_clear()
    if not exact and not sampled:
        raise ValueError(f"No solid meshes in {group.name}")
    for i, left in enumerate(exact):
        for right in exact[i + 1:]:
            if overlaps(left, right):
                raise ValueError(f"Overlapping solid boxes in {group.name}")
    for x, y, z in sampled:
        if any(left[0] <= x < left[3] and left[1] <= z < left[4] and
               left[2] <= y < left[5] for left in exact):
            raise ValueError(f"Voxelized mesh overlaps an exact box in {group.name}")
    boxes = sorted(exact + pack_cells(sampled))
    if len(boxes) > MAX_ASSET_BOXES:
        raise ValueError(f"{group.name} has {len(boxes)} boxes; limit is {MAX_ASSET_BOXES}")
    if not any(box[6] == 1 and box[1] == 0 for box in boxes):
        raise ValueError(f"{group.name} needs a ground-level foundation box")
    if group["voxel_asset"] in FOOTPRINTS:
        x_limit, z_limit = FOOTPRINTS[group["voxel_asset"]]
        if any(box[0] < -x_limit or box[3] > x_limit or
               box[2] < -z_limit or box[5] > z_limit for box in boxes):
            raise ValueError(f"{group.name} exceeds its placement footprint")
    return boxes


def bend_number(value):
    return f"{value}.0" if value >= 0 else f"(0.0 - {-value}.0 : F32)"


def bend_box(bounds):
    x0, y0, z0, x1, y1, z1, material = bounds
    low = ",".join(map(bend_number, (x0, y0, z0)))
    high = ",".join(map(bend_number, (x1, y1, z1)))
    return (f"S.Box{{R.Vec{{{low}}},R.Vec{{{high}}},"
            f"M.{MATERIALS[material]}()}}")


def export(output=OUTPUT):
    groups = sorted((group for group in bpy.data.collections if "voxel_asset" in group),
                    key=lambda group: group["voxel_asset"])
    if not groups:
        raise ValueError("No voxel asset collections found")
    source = Path(bpy.data.filepath)
    source_name = source.relative_to(ROOT) if source.is_relative_to(ROOT) else source.name
    lines = ["import Base", "import ./math.bend as R", "import ./spatial.bend as S",
             "import ./material.bend as M", "", f"# Generated from {source_name}.",
             "# Edit the Blender source and regenerate with the corresponding Makefile export target."]
    names = set()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for group in groups:
        name = str(group["voxel_asset"])
        if not name.isidentifier() or name in names:
            raise ValueError(f"Invalid or duplicate voxel asset name: {name}")
        names.add(name)
        boxes = asset_boxes(group, depsgraph)
        lines.append(f"def {name}() -> S.Tree:")
        lines.append("  S.build([" + ",\n    ".join(map(bend_box, boxes)) + "])")
        lines.append("")
        print(f"Exported {name}: {len(boxes)} boxes")
    output.write_text("\n".join(lines))
    print(f"Wrote {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    export(args.output)
