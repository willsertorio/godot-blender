"""Kenney Blaster Kit -> our pistol.glb and rifle.glb.

    blender -b -P blender/scripts/normalize_weapons.py -- assets_src/models/blaster-kit assets/models

Per weapon: import the Kenney glb, join its parts, rotate so the barrel points +Y, scale to a
real-world length, put the origin at the grip (where the hand holds it, for the view model),
replace the palette-texture material with our named materials by sampling each face's palette
colour (light metal -> GunMetal, coloured accent -> GunPaint, dark -> GunGrip), re-UV in metres,
harden normals, add cyan neon strips on both sides and a "Muzzle" empty at the barrel tip.
"""
import math
import os
import sys

sys.path.append(os.path.dirname(__file__))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from lib_hardsurface import MATERIALS, Part, box_uv, build, export_glb, material, reset_scene  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]

MATERIALS.update({
    "GunMetal": dict(color=(0.45, 0.47, 0.5), metallic=0.85, rough=0.35),
    "GunPaint": dict(color=(0.05, 0.055, 0.06), metallic=0.4, rough=0.5),
    "GunGrip": dict(color=(0.02, 0.02, 0.022), metallic=0.0, rough=0.8),
})

WEAPONS = {
    # name: (kenney file, length in metres, grip point as fraction of length from the back,
    #        neon strip height as fraction of height)
    "Pistol": ("blaster-a.glb", 0.27, 0.32, 0.72),
    "Rifle": ("blaster-n.glb", 0.78, 0.36, 0.64),
}


def classify(rgb):
    r, g, b = rgb
    mx, mn = max(rgb), min(rgb)
    sat = (mx - mn) / mx if mx > 1e-4 else 0.0
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if sat > 0.3 and lum > 0.08:
        return "GunPaint"
    if lum > 0.32:
        return "GunMetal"
    return "GunGrip"


def normalize(name, fname, length, grip_frac, strip_frac):
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, "Models", "GLB format", fname))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    img = None
    for m in bpy.data.materials:
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE":
                    img = n.image
    W, H = img.size
    px = list(img.pixels)

    # Bake world transforms, then join into one object.
    for o in meshes:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        o.parent = None
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active

    # Classify faces by palette colour before the UVs are replaced.
    me = ob.data
    uvl = me.uv_layers.active
    names = ["GunMetal", "GunPaint", "GunGrip"]
    me.materials.clear()
    for n in names:
        me.materials.append(material(n))
    for poly in me.polygons:
        u = sum(uvl.data[li].uv.x for li in poly.loop_indices) / poly.loop_total
        v = sum(uvl.data[li].uv.y for li in poly.loop_indices) / poly.loop_total
        x = min(W - 1, max(0, int(u * W)))
        y = min(H - 1, max(0, int(v * H)))
        i = (y * W + x) * 4
        poly.material_index = names.index(classify(px[i:i + 3]))

    # Kenney blasters point -Y after import; turn to +Y, scale to length, origin at the grip.
    me.transform(Matrix.Rotation(math.pi, 4, "Z"))
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    xs = [v.co.x for v in me.vertices]
    k = length / (max(ys) - min(ys))
    me.transform(Matrix.Scale(k, 4))
    ys = [y * k for y in ys]
    zs = [z * k for z in zs]
    xs = [x * k for x in xs]
    grip = Vector((0, min(ys) + (max(ys) - min(ys)) * grip_frac, max(zs) - (max(zs) - min(zs)) * 0.45))
    me.transform(Matrix.Translation(-grip))
    y0, y1 = min(ys) - grip.y, max(ys) - grip.y
    z0, z1 = min(zs) - grip.z, max(zs) - grip.z
    hx = max(abs(min(xs)), abs(max(xs)))

    # Smooth-by-angle shading + hardened normals; UVs in metres for the tiling materials.
    for p in me.polygons:
        p.use_smooth = True
    ob.modifiers.new("Bevel", "BEVEL").width = 0.0015
    ob.modifiers["Bevel"].limit_method = "ANGLE"
    ob.modifiers["Bevel"].harden_normals = True
    wn = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    wn.keep_sharp = True
    ob.modifiers.new("Triangulate", "TRIANGULATE").keep_custom_normals = True
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    while len(me.uv_layers) > 1:
        me.uv_layers.remove(me.uv_layers[-1])
    box_uv(ob)
    ob.name = name + "Body"
    ob.data.name = name + "Body"

    # Neon strips along both flanks (env cyan: the player's kit belongs to the dataspace).
    zc = z0 + (z1 - z0) * strip_frac
    ya, yb = y0 + (y1 - y0) * 0.22, y0 + (y1 - y0) * 0.78
    strips = build(name + "Neon", [
        Part((hx - 0.004, ya, zc - 0.004), (hx + 0.0015, yb, zc + 0.004), "NeonCyan", bevel=0),
        Part((-hx - 0.0015, ya, zc - 0.004), (-hx + 0.004, yb, zc + 0.004), "NeonCyan", bevel=0),
    ])

    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    ob.parent = root
    strips.parent = root
    muzzle = bpy.data.objects.new("Muzzle", None)
    bpy.context.scene.collection.objects.link(muzzle)
    muzzle.parent = root
    # Barrel tip: front-most vertices, averaged.
    front = [v.co for v in me.vertices if v.co.y > y1 - 0.01]
    c = sum(front, Vector()) / len(front)
    muzzle.location = (0, y1 + 0.005, c.z)
    for o in list(bpy.data.objects):
        if o not in (root, ob, strips, muzzle) and o.type in ("EMPTY", "MESH"):
            bpy.data.objects.remove(o)
    export_glb(os.path.join(OUT, name.lower() + ".glb"), [root])
    print(f"{name}: length {y1 - y0:.3f} m, height {z1 - z0:.3f} m, muzzle {tuple(round(x, 3) for x in muzzle.location)}")


for n, spec in WEAPONS.items():
    normalize(n, *spec)
