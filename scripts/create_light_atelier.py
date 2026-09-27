"""Author the Light Atelier's three mesh sculptures in Blender.

blender -b --factory-startup --python-exit-code 1 --python scripts/create_light_atelier.py
Use -- --replace only when intentionally regenerating this authored source.
"""
import argparse
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "assets/light_atelier.blend"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--replace", action="store_true")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
if DEST.exists() and not args.replace:
    raise RuntimeError(f"Refusing to replace {DEST}; edit it in Blender or explicitly pass --replace")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
palette = {
    1: ("Foundation", (0.25, 0.74, 0.62, 1)),
    2: ("Concrete", (0.68, 0.49, 0.29, 1)),
    3: ("Frame", (0.25, 0.40, 0.55, 1)),
    4: ("Machinery", (0.81, 0.45, 0.18, 1)),
    5: ("Plaster", (0.83, 0.81, 0.76, 1)),
}
materials = {}
for material, (name, color) in palette.items():
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = color
    materials[material] = mat


def collection(name, asset, origin):
    group = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(group)
    if asset:
        group["voxel_asset"] = asset
        group["voxel_origin"] = origin
    return group


def assign(obj, group, name, material):
    obj.name = name
    for old in tuple(obj.users_collection):
        old.objects.unlink(obj)
    group.objects.link(obj)
    obj["voxel_material"] = material
    obj.data.materials.append(materials[material])
    return obj


def box(group, name, material, lo, hi):
    origin = group.get("voxel_origin", (0, 0, 0))
    bpy.ops.mesh.primitive_cube_add(size=1,
        location=tuple(origin[i] + (lo[i] + hi[i]) / 2 for i in range(3)))
    obj = assign(bpy.context.object, group, name, material)
    obj.dimensions = tuple(hi[i] - lo[i] for i in range(3))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def plinth(group, width, depth, height):
    box(group, "Protected footing", 1, (-width / 2, -depth / 2, 0),
        (width / 2, depth / 2, 0.2))
    box(group, "Plaster pedestal", 5, (-width / 2 + 0.1, -depth / 2 + 0.1, 0.2),
        (width / 2 - 0.1, depth / 2 - 0.1, height))


suzanne = collection("01 Suzanne / subdivided and sealed", "suzanne", (-9, 0, 0))
plinth(suzanne, 7.0, 4.6, 1.2)
bpy.ops.mesh.primitive_monkey_add()
head = assign(bpy.context.object, suzanne, "Suzanne / real Blender mesh", 3)
head["voxel_remove_isolated"] = True
head.scale = (2.2, 2.2, 2.2)
head.rotation_euler[2] = math.pi - 0.45
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
subdivision = head.modifiers.new("Rounded sculptural surface", "SUBSURF")
subdivision.levels = subdivision.render_levels = 1
seal = head.modifiers.new("Close eye sockets for solid import", "REMESH")
seal.mode = "VOXEL"
seal.voxel_size = 0.07
smooth = head.modifiers.new("Smooth remesh corners before 10 cm sampling", "SMOOTH")
smooth.factor = 0.7
smooth.iterations = 4
depsgraph = bpy.context.evaluated_depsgraph_get()
evaluated = head.evaluated_get(depsgraph)
mesh = evaluated.to_mesh()
bottom = min(vertex.co.z for vertex in mesh.vertices)
evaluated.to_mesh_clear()
head.location = (-9, 0, 1.2 - bottom)

oculus = collection("02 Oculus / hollow torus", "oculus", (0, 0, 0))
plinth(oculus, 7.6, 2.6, 1.0)
bpy.ops.mesh.primitive_torus_add(major_segments=64, minor_segments=20,
    major_radius=2.7, minor_radius=0.55, location=(0, 0, 4.25),
    rotation=(math.pi / 2, 0, 0))
assign(bpy.context.object, oculus, "Oculus / open center", 4)

twist = collection("03 Twist / swept octagonal mesh", "twist", (8, 0, 0))
plinth(twist, 4.2, 4.2, 0.8)
profile = [(-1, -0.7), (-0.7, -1), (0.7, -1), (1, -0.7),
           (1, 0.7), (0.7, 1), (-0.7, 1), (-1, 0.7)]
vertices, faces = [], []
steps = 48
for ring in range(steps + 1):
    t = ring / steps
    angle = t * math.pi * 1.15
    radius = 1.15 * (0.78 + 0.22 * math.cos(t * math.pi * 2))
    for x, y in profile:
        vertices.append((radius * (x * math.cos(angle) - y * math.sin(angle)),
                         radius * (x * math.sin(angle) + y * math.cos(angle)),
                         0.8 + t * 6.2))
for ring in range(steps):
    for side in range(8):
        a, b = ring * 8 + side, ring * 8 + (side + 1) % 8
        faces.append((a, b, b + 8, a + 8))
faces.extend([tuple(reversed(range(8))), tuple(steps * 8 + i for i in range(8))])
mesh = bpy.data.meshes.new("Twisted octagonal volume")
mesh.from_pydata(vertices, [], faces)
mesh.update()
obj = bpy.data.objects.new("Twist / 207 degree sweep", mesh)
bpy.context.scene.collection.objects.link(obj)
obj.location.x = 8
assign(obj, twist, obj.name, 3)

preview = collection("Preview only", None, (0, 0, 0))
box(preview, "Preview floor", 5, (-14, -5, -0.2), (12, 5, 0))
for label, x in (("01  SUZANNE", -9), ("02  OCULUS", 0), ("03  TWIST", 8)):
    curve = bpy.data.curves.new(label, "FONT")
    curve.body = label
    curve.size = 0.45
    obj = bpy.data.objects.new(label, curve)
    preview.objects.link(obj)
    obj.location = (x + 2, 3.2, 0.02)
    obj.rotation_euler[2] = math.pi
bpy.ops.object.camera_add(location=(14, 30, 18))
camera = bpy.context.object
camera.rotation_euler = (Vector((-1, 0, 3)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.lens = 43
bpy.context.scene.camera = camera
bpy.ops.object.light_add(type="SUN", location=(-8, 4, 12))
bpy.context.object.rotation_euler = Vector((0.62, -0.48, -0.62)).to_track_quat("-Z", "Y").to_euler()
bpy.context.object.data.energy = 2.2
bpy.context.scene.render.engine = "CYCLES"
bpy.context.scene.cycles.samples = 24
bpy.context.scene.render.resolution_x = 1280
bpy.context.scene.render.resolution_y = 720
bpy.context.scene.render.resolution_percentage = 100
bpy.context.scene.world.color = (0.17, 0.20, 0.27)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(DEST))
print(f"Created {DEST}")
