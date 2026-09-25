"""Create the editable Blender source for the voxel showcase assets.

Run once with: blender -b --factory-startup --python scripts/create_showcase_assets.py
The script refuses to replace an existing .blend file. Subsequent edits belong
in Blender and are exported with scripts/export_showcase_assets.py.
"""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "assets/showcase_assets.blend"
if DEST.exists():
    raise SystemExit(f"Refusing to replace {DEST}")
DEST.parent.mkdir(parents=True, exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

palette = {
    1: ("Foundation", (0.25, 0.74, 0.62, 1.0)),
    2: ("Concrete", (0.68, 0.49, 0.29, 1.0)),
    3: ("Frame", (0.25, 0.40, 0.55, 1.0)),
    4: ("Machinery", (0.81, 0.45, 0.18, 1.0)),
}
materials = {}
for key, (name, color) in palette.items():
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = color
    materials[key] = mat


def collection(name, asset=None, origin=(0.0, 0.0, 0.0)):
    result = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(result)
    if asset:
        result["voxel_asset"] = asset
        result["voxel_origin"] = list(origin)
    return result


def box(group, name, material, bounds):
    x0, y0, z0, x1, y1, z1 = bounds
    ox, oy, oz = group.get("voxel_origin", (0.0, 0.0, 0.0))
    bpy.ops.mesh.primitive_cube_add(size=1, location=(
        ox + (x0 + x1) / 2, oy + (y0 + y1) / 2, oz + (z0 + z1) / 2))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (x1 - x0, y1 - y0, z1 - z0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for old in tuple(obj.users_collection):
        old.objects.unlink(obj)
    group.objects.link(obj)
    obj["voxel_material"] = material
    obj.data.materials.append(materials[material])
    return obj


beacon = collection("01 Beacon", "beacon", (-8.0, 0.0, 0.0))
box(beacon, "Foundation plinth", 1, (-0.8, -0.8, 0.0, 0.8, 0.8, 0.2))
for x in (-0.7, 0.5):
    for y in (-0.7, 0.5):
        box(beacon, f"Frame post {x} {y}", 3,
            (x, y, 0.2, x + 0.2, y + 0.2, 2.4))
box(beacon, "Signal housing", 4, (-0.8, -0.8, 2.4, 0.8, 0.8, 3.0))
box(beacon, "Signal cap", 1, (-0.6, -0.6, 3.0, 0.6, 0.6, 3.2))

cargo = collection("02 Cargo Pod", "cargo_pod", (0.0, 0.0, 0.0))
box(cargo, "Foundation skid", 1, (-1.2, -0.9, 0.0, 1.2, 0.9, 0.2))
box(cargo, "Machinery core", 4, (-1.0, -0.7, 0.2, 1.0, 0.7, 1.6))
for x in (-1.2, 1.0):
    for y in (-0.9, 0.7):
        box(cargo, f"Frame corner {x} {y}", 3,
            (x, y, 0.2, x + 0.2, y + 0.2, 1.6))
box(cargo, "Concrete lid", 2, (-1.2, -0.9, 1.6, 1.2, 0.9, 1.8))

gateway = collection("03 Gateway", "gateway", (9.0, 0.0, 0.0))
for x in (-3.5, 2.5):
    box(gateway, f"Anchor {x}", 1, (x, -0.7, 0.0, x + 1.0, 0.7, 0.3))
    box(gateway, f"Pier {x}", 2, (x + 0.2, -0.5, 0.3, x + 0.8, 0.5, 2.0))
    box(gateway, f"Frame {x}", 3, (x + 0.2, -0.5, 2.0, x + 0.8, 0.5, 5.2))
box(gateway, "Machinery lintel", 4, (-3.5, -0.7, 5.2, 3.5, 0.7, 5.8))
box(gateway, "Foundation crest", 1, (-3.0, -0.5, 5.8, 3.0, 0.5, 6.0))

preview = collection("Preview only")
box(preview, "Presentation floor", 2, (-12.0, -4.0, -0.2, 13.0, 4.0, 0.0))
for name, x in (("BEACON", -8.0), ("CARGO POD", 0.0), ("GATEWAY", 9.0)):
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = name
    curve.size = 0.6
    label = bpy.data.objects.new(name, curve)
    preview.objects.link(label)
    label.location = (x - 1.8, -2.4, 0.02)

bpy.ops.object.camera_add(location=(1.0, -34.0, 20.0))
camera = bpy.context.object
camera.name = "Preview camera"
direction = (Vector((0.0, 0.0, 1.8)) - camera.location).to_track_quat("-Z", "Y")
camera.rotation_euler = direction.to_euler()
camera.data.lens = 40
bpy.context.scene.camera = camera
bpy.ops.object.light_add(type="AREA", location=(-5.0, -8.0, 15.0))
bpy.context.object.data.energy = 2500
bpy.context.object.data.shape = "DISK"
bpy.context.object.data.size = 12
bpy.context.scene.render.engine = "CYCLES"
bpy.context.scene.cycles.samples = 32
bpy.context.scene.render.resolution_x = 1100
bpy.context.scene.render.resolution_y = 600
bpy.context.scene.render.resolution_percentage = 100
bpy.context.scene.world.color = (0.18, 0.18, 0.18)
bpy.context.scene.view_settings.view_transform = "AgX"

bpy.ops.wm.save_as_mainfile(filepath=str(DEST))
print(f"Created {DEST}")
