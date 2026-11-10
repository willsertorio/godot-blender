"""Gloved hands built around each gun's handle (option 3: hands only) -> assets/models/hands_<gun>.glb.

    blender -b -P blender/scripts/build_hands.py -- assets/models

Works in the weapon frame of pistol.glb / rifle.glb (Blender: +Y barrel, +Z up, origin at the grip).
For each hand: measure the handle from the gun mesh (vertices in a box -> centre, PCA axis, cross-section
half-sizes), then grow a glove from metaball capsules: a palm on the palm side of the handle, four
fingers arcing around it, a thumb closing the other side, and a cuff + short sleeve running back out of
view. Because the fingers follow the measured cross-section they always wrap the handle.
Materials: ArmGlove (glove), ArmSuit (sleeve), ArmAccent (cuff band) -> MaterialLib fabric shader.
Godot parents the result to the gun model at the origin (no offset).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1]

# Per hand: box (weapon frame, Blender axes) that isolates the handle vertices, "palm" = side of the
# handle the palm sits on, "wrap" = direction the fingers go around toward, "axis_hint" for PCA sign,
# finger "spacing", and "wrist" = direction the forearm leaves the hand (back toward the camera).
HANDS = {
    "pistol": [
        {"name": "HandR", "box": ((-0.05, -0.052, -0.058), (0.05, 0.004, -0.012)), "axis_hint": Vector((0, 0, -1)),
         "palm": Vector((1, 0, 0)), "wrap": Vector((0, 1, 0)), "top": 0.004, "spacing": 0.019,
         "wrist": Vector((0.25, -1.0, -0.55)), "thumb_side": Vector((-1, 0, 0))},
    ],
    "rifle": [
        {"name": "HandR", "box": ((-0.05, -0.065, -0.072), (0.05, 0.02, -0.025)), "axis_hint": Vector((0, 0, -1)),
         "palm": Vector((1, 0, 0)), "wrap": Vector((0, 1, 0)), "top": 0.004, "spacing": 0.02,
         "wrist": Vector((0.25, -1.0, -0.55)), "thumb_side": Vector((-1, 0, 0))},
        {"name": "HandL", "box": ((-0.03, 0.2, -0.02), (0.03, 0.4, 0.035)), "axis_hint": Vector((0, 1, 0)),
         "palm": Vector((0, 0, -1)), "wrap": Vector((1, 0, 0)), "top": 0.03, "spacing": 0.02,
         "wrist": Vector((-0.6, -0.5, -1.0)), "thumb_side": Vector((-1, 0, 0)), "support": True},
    ],
}
R_FINGER = 0.0105
FAT = 1.55  # metaball radius / visible radius (threshold shrinks the surface)
SEGS = 3


def handle_frame(verts, spec):
    lo, hi = Vector(spec["box"][0]), Vector(spec["box"][1])
    pts = [v for v in verts if all(lo[i] <= v[i] <= hi[i] for i in range(3))]
    c = sum(pts, Vector()) / len(pts)
    # PCA (power iteration) for the handle axis.
    cov = Matrix(((0, 0, 0), (0, 0, 0), (0, 0, 0)))
    for p in pts:
        d = p - c
        for i in range(3):
            for j in range(3):
                cov[i][j] += d[i] * d[j]
    u = spec["axis_hint"].copy()
    for _ in range(50):
        u = (cov @ u).normalized()
    if u.dot(spec["axis_hint"]) < 0:
        u = -u
    s = spec["palm"] - u * spec["palm"].dot(u)
    s.normalize()
    w = spec["wrap"] - u * spec["wrap"].dot(u) - s * spec["wrap"].dot(s)
    w.normalize()
    ext_s = max(abs((p - c).dot(s)) for p in pts)
    ext_w = max(abs((p - c).dot(w)) for p in pts)
    top = min((p - c).dot(u) for p in pts)  # most negative along u = top end of the handle
    return c, u, s, w, ext_s, ext_w, top, len(pts)


def capsule(mb, a, b, r):
    """Metaball capsule from a to b with radius r."""
    e = mb.elements.new(type="CAPSULE")
    d = b - a
    e.co = (a + b) / 2
    e.radius = r * FAT
    e.size_x = max(d.length / 2, 1e-4)
    e.rotation = Vector((1, 0, 0)).rotation_difference(d.normalized())
    e.stiffness = 2.0
    return e


def ball(mb, p, r, scale=(1, 1, 1), rot=None):
    e = mb.elements.new(type="ELLIPSOID")
    e.co = p
    e.radius = r * FAT
    e.size_x, e.size_y, e.size_z = scale
    if rot is not None:
        e.rotation = rot
    e.stiffness = 2.0
    return e


def ellipse_pt(c, s, w, a, b, th):
    """Point on the ring around the handle: th=0 palm side, 90 = wrap side, 180 = opposite side."""
    return c + s * (a * math.cos(th)) + w * (b * math.sin(th))


def make_hand(spec, verts):
    c0, u, s, w, es, ew, top, n = handle_frame(verts, spec)
    print(f"  {spec['name']}: {n} handle verts, half-sizes palm-side {es*100:.1f} cm wrap-side {ew*100:.1f} cm")
    r = R_FINGER
    a, b = es + r * 0.85, ew + r * 0.85
    glove = bpy.data.metaballs.new(spec["name"] + "Glove")
    glove.resolution = 0.0035
    glove.threshold = 0.6
    support = spec.get("support", False)
    first = top + spec["top"] + r  # first (index) finger centre along u
    heights = [first + k * spec["spacing"] for k in range(4)]
    # Fingers: index slightly straighter (rests by the trigger) on the grip hand.
    for k, h in enumerate(heights):
        c = c0 + u * h
        start, end = (math.radians(-15), math.radians(175 if not support else 125))
        if k == 0 and not support:
            end = math.radians(120)
        lengths = [1.0, 0.85, 0.7] if k != 3 else [0.8, 0.7, 0.6]
        rr = r * (0.9 if k == 3 else 1.0)
        pts = [ellipse_pt(c, s, w, a, b, start + (end - start) * t / SEGS) for t in range(SEGS + 1)]
        for j in range(SEGS):
            capsule(glove, pts[j], pts[j + 1], rr * (1.0 - 0.08 * j))
    # Palm: thick pad on the palm side, spanning the fingers.
    hmid = (heights[0] + heights[-1]) / 2
    pc = c0 + u * hmid + s * (es + r * 1.6) - w * (ew * 0.35)
    span = (heights[-1] - heights[0]) / 2 + r * 1.2
    rot = Matrix((u, w, s)).transposed().to_quaternion()
    ball(glove, pc, 0.022, scale=(span / 0.022 * 1.05, 1.25, 0.85), rot=rot)
    # Back of the hand / web behind the handle (toward the wrist side).
    back = c0 + u * (heights[0] - r * 0.2) + s * (es * 0.6) - w * (ew + r * 1.4)
    ball(glove, back, 0.02, scale=(1.4, 1.0, 1.2), rot=rot)
    # Thumb: from the web over the top / across the opposite side toward the front.
    ts = spec["thumb_side"] - u * spec["thumb_side"].dot(u)
    ts.normalize()
    t0 = back + u * (-r * 0.6)
    t1 = c0 + u * (heights[0] - r * 1.6) - w * (ew * 0.2) + ts * (es * 0.4)
    t2 = c0 + u * (heights[0] - r * 1.2) + w * (ew * 0.6) + ts * (es + r * 0.9)
    capsule(glove, t0, t1, r * 1.15)
    capsule(glove, t1, t2, r * 1.0)
    # Wrist: leaves the back of the hand toward the camera.
    wd = spec["wrist"].normalized()
    wr0 = back + s * 0.01
    wr1 = wr0 + wd * 0.06
    capsule(glove, wr0, wr1, 0.026)
    bpy.ops.object.select_all(action="DESELECT")
    gob = bpy.data.objects.new(spec["name"] + "GloveMB", glove)
    bpy.context.scene.collection.objects.link(gob)
    # Sleeve + cuff band (separate meshes, separate materials).
    sleeve = bpy.data.metaballs.new(spec["name"] + "Sleeve")
    sleeve.resolution = 0.006
    capsule(sleeve, wr1 - wd * 0.005, wr1 + wd * 0.22, 0.034)
    sob = bpy.data.objects.new(spec["name"] + "SleeveMB", sleeve)
    bpy.context.scene.collection.objects.link(sob)
    cuff = bpy.data.metaballs.new(spec["name"] + "Cuff")
    cuff.resolution = 0.004
    capsule(cuff, wr1 - wd * 0.012, wr1 + wd * 0.012, 0.037)
    cob = bpy.data.objects.new(spec["name"] + "CuffMB", cuff)
    bpy.context.scene.collection.objects.link(cob)
    parts = []
    for ob, mat in ((gob, "ArmGlove"), (sob, "ArmSuit"), (cob, "ArmAccent")):
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        mo = bpy.data.objects.new(ob.name.replace("MB", ""), me)
        bpy.context.scene.collection.objects.link(mo)
        bpy.data.objects.remove(ob)
        m = bpy.data.materials.get(mat) or bpy.data.materials.new(mat)
        me.materials.append(m)
        for p in me.polygons:
            p.use_smooth = True
        # Box-ish UVs in metres for the tiling fabric detail.
        uvl = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            nrm = poly.normal
            ax = max(range(3), key=lambda k: abs(nrm[k]))
            for li in poly.loop_indices:
                v = me.vertices[me.loops[li].vertex_index].co
                q = [v[i] for i in range(3) if i != ax]
                uvl.data[li].uv = (q[0] * 10, q[1] * 10)
        parts.append(mo)
    print(f"    glove {len(parts[0].data.polygons)} faces")
    return parts


def build(gun):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, gun + ".glb"))
    verts = [o.matrix_world @ v.co for o in bpy.data.objects if o.type == "MESH" for v in o.data.vertices]
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    root = bpy.data.objects.new("Hands", None)
    bpy.context.scene.collection.objects.link(root)
    for spec in HANDS[gun]:
        for p in make_hand(spec, verts):
            p.parent = root
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for c in root.children:
        c.select_set(True)
    path = os.path.join(OUT, f"hands_{gun}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True)
    print("exported", path)


for g in HANDS:
    build(g)
