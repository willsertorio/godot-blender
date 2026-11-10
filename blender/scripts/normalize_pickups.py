"""Pickups: kit.glb + ammo.glb from Poly Haven (CC0), health_cell.glb modelled.

    blender -b -P blender/scripts/normalize_pickups.py -- assets_src/models/polyhaven assets/models

Poly Haven props keep their own photoreal textures (embedded in the glb; their material is
renamed "PH_<asset>" so Godot's MaterialLib leaves it alone). Each is turned upright with its
longest side across (X), thinnest side facing forward (Y), scaled to read at pickup size,
origin at the bottom centre, and gets loot-green neon trim so it glows against the floor.
"""
import math
import os
import sys

sys.path.append(os.path.dirname(__file__))
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from lib_hardsurface import Part, build, export_glb, reset_scene  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]

PROPS = {
    # glb name: (poly haven id, target width in metres)
    "kit": ("medical_box", 0.52),
    "ammo": ("ammo_box", 0.42),
}


def normalize(name, asset, width):
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, asset, f"{asset}_1k.gltf"))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        o.parent = None
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    for o in list(bpy.data.objects):
        if o != ob:
            bpy.data.objects.remove(o)
    me = ob.data

    # Axis permutation: longest -> X, middle -> Z (height), thinnest -> Y (faces forward).
    lo = Vector([min(v.co[i] for v in me.vertices) for i in range(3)])
    hi = Vector([max(v.co[i] for v in me.vertices) for i in range(3)])
    size = hi - lo
    order = sorted(range(3), key=lambda i: -size[i])  # [longest, middle, thinnest]
    target = {order[0]: 0, order[1]: 2, order[2]: 1}
    rot = Matrix.Identity(3)
    for src, dst in target.items():
        for r in range(3):
            rot[r][src] = 1.0 if r == dst else 0.0
    if rot.determinant() < 0:  # keep it a rotation (no mirrored print)
        for r in range(3):
            rot[r][order[2]] *= -1
    me.transform(rot.to_4x4())
    lo = Vector([min(v.co[i] for v in me.vertices) for i in range(3)])
    hi = Vector([max(v.co[i] for v in me.vertices) for i in range(3)])
    k = width / (hi.x - lo.x)
    me.transform(Matrix.Scale(k, 4) @ Matrix.Translation(-Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))))
    hi = (hi - lo) * k
    w, d, h = hi.x, hi.y, hi.z
    for m in me.materials:
        m.name = "PH_" + asset
    ob.name = name.capitalize() + "Prop"

    # Loot-green trim: a band around the middle.
    t = 0.012
    band = build(name.capitalize() + "Neon", [
        Part((-w / 2 - t, -d / 2 - t, h * 0.47), (w / 2 + t, -d / 2, h * 0.53), "NeonGreen", bevel=0),
        Part((-w / 2 - t, d / 2, h * 0.47), (w / 2 + t, d / 2 + t, h * 0.53), "NeonGreen", bevel=0),
        Part((-w / 2 - t, -d / 2, h * 0.47), (-w / 2, d / 2, h * 0.53), "NeonGreen", bevel=0),
        Part((w / 2, -d / 2, h * 0.47), (w / 2 + t, d / 2, h * 0.53), "NeonGreen", bevel=0),
    ])
    root = bpy.data.objects.new(name.capitalize(), None)
    bpy.context.scene.collection.objects.link(root)
    ob.parent = root
    band.parent = root
    export_glb(os.path.join(OUT, name + ".glb"), [root], images=True)
    print(f"{name}: {w:.2f} x {d:.2f} x {h:.2f} m")


def health_cell():
    """Immediate-health pickup: a glowing green energy cell in a metal cage."""
    reset_scene()
    root = bpy.data.objects.new("HealthCell", None)
    bpy.context.scene.collection.objects.link(root)
    r, hgt = 0.11, 0.42
    parts = [
        Part((-r * 0.75, -r * 0.75, 0.06), (r * 0.75, r * 0.75, hgt - 0.06), "NeonGreen", kind="cyl", segments=12, bevel=0),
        Part((-r * 1.15, -r * 1.15, 0.0), (r * 1.15, r * 1.15, 0.07), "PropMetal", kind="cyl", segments=12, bevel=0.012),
        Part((-r * 1.15, -r * 1.15, hgt - 0.07), (r * 1.15, r * 1.15, hgt), "PropMetal", kind="cyl", segments=12, bevel=0.012),
        Part((-r * 0.5, -r * 0.5, hgt), (r * 0.5, r * 0.5, hgt + 0.03), "WallTrim", kind="cyl", segments=12, bevel=0.006),
    ]
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        x, y = math.cos(a) * r * 0.98, math.sin(a) * r * 0.98
        parts.append(Part((x - 0.016, y - 0.016, 0.05), (x + 0.016, y + 0.016, hgt - 0.05), "PropMetal", rot=(0, 0, a), bevel=0.005))
    cell = build("CellBody", parts)
    cell.parent = root
    export_glb(os.path.join(OUT, "health_cell.glb"), [root])


for n, (asset, width) in PROPS.items():
    normalize(n, asset, width)
health_cell()
