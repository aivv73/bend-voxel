"""Run with: blender -b --factory-startup --python-exit-code 1 --python tests/blender_voxelize.py"""

import importlib.util
from pathlib import Path

import bpy
from mathutils import Vector


root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "voxel_export", root / "scripts/export_showcase_assets.py")
voxel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voxel)


def cube(lo, hi):
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    vertices = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
             (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return vertices, faces


outer_v, outer_f = cube((-3, -3, 0), (3, 3, 6))
inner_v, inner_f = cube((-1, -1, 2), (1, 1, 4))
hollow = voxel.mesh_cells(
    outer_v + inner_v, outer_f + [tuple(i + 8 for i in face) for face in inner_f],
    "hollow fixture")
assert (2, 0, 3) in hollow
assert (0, 0, 3) not in hollow
assert len(hollow) == 208
try:
    voxel.mesh_cells(outer_v, outer_f[:-1], "open fixture")
    raise AssertionError("open mesh was accepted")
except ValueError as exc:
    assert "closed and manifold" in str(exc)

cells = {(x, y, z): 2 for x, y, z in hollow}
boxes = voxel.pack_cells(cells)
reconstructed = {}
for x0, z0, y0, x1, z1, y1, material in boxes:
    for x in range(x0, x1):
        for y in range(y0, y1):
            for z in range(z0, z1):
                assert (x, y, z) not in reconstructed
                reconstructed[(x, y, z)] = material
assert reconstructed == cells

# An artist can discard solitary sampling specks without losing thin connected parts.
assert voxel.remove_isolated({(0, 0, 0), (1, 0, 0), (2, 1, 0)}) == {(0, 0, 0), (1, 0, 0)}
assert voxel.remove_isolated({(0, 0, 0)}) == set()

group = bpy.data.collections.new("Voxel fixture")
bpy.context.scene.collection.children.link(group)
group["voxel_asset"] = "fixture"
group["voxel_origin"] = [2.0, -3.0, 0.0]

bpy.ops.mesh.primitive_cube_add(size=1, location=(2.0, -3.0, 0.05))
anchor = bpy.context.object
anchor.name = "Foundation"
anchor.dimensions = (1.0, 1.0, 0.1)
anchor["voxel_material"] = 1
for old in tuple(anchor.users_collection):
    old.objects.unlink(anchor)
group.objects.link(anchor)

bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.3, depth=0.8,
                                    location=(2.0, -3.0, 0.5))
shape = bpy.context.object
shape.name = "Modified cylinder"
shape["voxel_material"] = 4
bevel = shape.modifiers.new("Rounded rims", "BEVEL")
bevel.width = 0.04
bevel.segments = 2
for old in tuple(shape.users_collection):
    old.objects.unlink(shape)
group.objects.link(shape)

asset = voxel.asset_boxes(group, bpy.context.evaluated_depsgraph_get())
assert any(box[6] == 1 and box[1] == 0 for box in asset)
assert any(box[6] == 4 for box in asset)
assert all(not voxel.overlaps(a, b) for i, a in enumerate(asset) for b in asset[i + 1:])
assert len(asset) < 40
print("PASS Blender closed-mesh voxelization, cavity, packing, modifiers, and asset export")
