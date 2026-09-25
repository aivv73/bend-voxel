"""Export box meshes from assets/showcase_assets.blend into Bend voxel trees.

Run with: blender -b assets/showcase_assets.blend --python scripts/export_showcase_assets.py
The editable .blend file is the asset source; the generated Bend file is built
into the demo. Blender X/Y/Z map to engine X/Z/Y respectively.
"""

from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "src/showcase_assets.bend"
MATERIALS = {1: "foundation", 2: "concrete", 3: "frame", 4: "machinery"}
GRID = 10  # Cells per meter.
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


def asset_boxes(group):
    origin = tuple(group["voxel_origin"])
    if len(origin) != 3:
        raise ValueError(f"Invalid origin for {group.name}")
    boxes = []
    for obj in sorted(group.objects, key=lambda item: item.name):
        if obj.type != "MESH":
            raise ValueError(f"Only box meshes are allowed in {group.name}: {obj.name}")
        material = int(obj.get("voxel_material", 0))
        if material not in MATERIALS:
            raise ValueError(f"Invalid voxel material on {obj.name}")
        vertices = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
        if len(vertices) != 8:
            raise ValueError(f"A voxel asset part must be a cube mesh: {obj.name}")
        coords = []
        for axis in range(3):
            values = {cell(vertex[axis] - origin[axis]) for vertex in vertices}
            if len(values) != 2:
                raise ValueError(f"A voxel asset part must be axis-aligned: {obj.name}")
            coords.append(sorted(values))
        if len({tuple(cell(vertex[axis] - origin[axis]) for axis in range(3))
                for vertex in vertices}) != 8:
            raise ValueError(f"A voxel asset part must have eight corners: {obj.name}")
        # Blender is Z-up; the engine is Y-up.
        x, z, y = coords
        bounds = (x[0], y[0], z[0], x[1], y[1], z[1], material)
        if y[0] < 0:
            raise ValueError(f"Asset extends below its placement plane: {obj.name}")
        boxes.append(bounds)
    if not boxes or not any(b[6] == 1 and b[1] == 0 for b in boxes):
        raise ValueError(f"{group.name} needs a ground-level foundation box")
    if group["voxel_asset"] in FOOTPRINTS:
        x_limit, z_limit = FOOTPRINTS[group["voxel_asset"]]
        if any(b[0] < -x_limit or b[3] > x_limit or
               b[2] < -z_limit or b[5] > z_limit for b in boxes):
            raise ValueError(f"{group.name} exceeds its placement footprint")
    for i, left in enumerate(boxes):
        for right in boxes[i + 1:]:
            if all(left[axis] < right[axis + 3] and right[axis] < left[axis + 3]
                   for axis in range(3)):
                raise ValueError(f"Overlapping solid boxes in {group.name}")
    return sorted(boxes)


def bend_number(value):
    return f"{value}.0" if value >= 0 else f"(0.0 - {-value}.0 : F32)"


def bend_box(bounds):
    x0, y0, z0, x1, y1, z1, material = bounds
    low = ",".join(map(bend_number, (x0, y0, z0)))
    high = ",".join(map(bend_number, (x1, y1, z1)))
    return (f"S.Box{{R.Vec{{{low}}},R.Vec{{{high}}},"
            f"M.{MATERIALS[material]}()}}")


groups = sorted((group for group in bpy.data.collections if "voxel_asset" in group),
                key=lambda group: group["voxel_asset"])
if not groups:
    raise ValueError("No voxel asset collections found")

lines = ["import Base", "import ./math.bend as R", "import ./spatial.bend as S",
         "import ./material.bend as M", "", "# Generated from assets/showcase_assets.blend.",
         "# Edit the Blender boxes, then run make export-showcase-assets."]
names = set()
for group in groups:
    name = str(group["voxel_asset"])
    if not name.isidentifier() or name in names:
        raise ValueError(f"Invalid or duplicate voxel asset name: {name}")
    names.add(name)
    boxes = asset_boxes(group)
    lines.append(f"def {name}() -> S.Tree:")
    lines.append("  S.build([" + ",\n    ".join(map(bend_box, boxes)) + "])")
    lines.append("")
    print(f"Exported {name}: {len(boxes)} boxes")
OUTPUT.write_text("\n".join(lines))
print(f"Wrote {OUTPUT}")
