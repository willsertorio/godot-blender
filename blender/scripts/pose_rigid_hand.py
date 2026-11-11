"""Pose the user-supplied rigid hand (blender/source/rigid_hand.glb) on each gun -> assets/models/rigid_<gun>.glb.

    blender -b -P blender/scripts/pose_rigid_hand.py -- assets/models

The source is a LEFT hand made of rigid pieces (hand block, 3 segments per finger, thumb, forearm),
each pivoting at its base: fingers along +Y, palm facing -Z, thumb on +X, about 20x real size.
The right hand is the mirror (X flipped in the mesh data, so every piece keeps a clean rotation).

Per hand (gun frame, Blender axes, origin at the grip; see build_hands.py for the handle measurement):
  u = handle axis, pointing from the index finger toward the pinky
  s = from the handle centre toward the palm
  w = where the fingers leave the palm (derived: s x u for a right hand, u x s for a left one)
The knuckle row sits on the palm side near the front edge, then every finger/thumb segment is bent
(about its own knuckle axis, toward the palm) until its tip touches the handle surface.
POSE_OVERRIDES (filled from hand-tuned poses in blender/hands_<gun>.blend) win over the solver.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))

OUT = sys.argv[sys.argv.index("--") + 1]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "blender", "source", "rigid_hand.glb")
OVERRIDES = os.path.join(ROOT, "blender", "source", "rigid_hand_poses.json")
SCALE = 0.046  # source units -> metres (palm ~8.4 cm wide, finger spacing ~1.9 cm)
FINGERS = ["index", "middle", "ring", "pinky"]

# box: handle vertices (as build_hands); u / s as above (u is given, not measured: the boxes are too
# short for PCA to find the grip axis); at: index finger centre along u, from the top end of the
# handle (m); front: knuckle row position along w (fraction of the handle half-depth); yaw: heel of
# the hand swung away from the handle (deg); arm: direction the forearm leaves the wrist (gun frame).
HANDS = {
    "pistol": [
        {"name": "R", "box": ((-0.05, -0.052, -0.058), (0.05, 0.004, -0.012)), "u": Vector((0, -0.3, -1)),
         "s": Vector((1, 0, 0)), "at": 0.012, "front": 0.55, "yaw": 22, "arm": Vector((0.35, -1, -0.55))},
    ],
    "rifle": [
        {"name": "R", "box": ((-0.05, -0.065, -0.072), (0.05, 0.02, -0.025)), "u": Vector((0, -0.3, -1)),
         "s": Vector((1, 0, 0)), "at": 0.012, "front": 0.55, "yaw": 22, "arm": Vector((0.35, -1, -0.55))},
        {"name": "L", "box": ((-0.03, 0.2, -0.02), (0.03, 0.4, 0.035)), "u": Vector((0, -1, 0)),
         "s": Vector((0, 0, -1)), "at": 0.07, "front": 0.2, "yaw": 15, "arm": Vector((-0.6, -0.5, -1.0))},
    ],
}


def load_source(prefix, mirror):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=SRC)
    objs = {o.name.split(".")[0]: o for o in set(bpy.data.objects) - before}
    for o in objs.values():
        o.name = f"{prefix}_{o.name.split('.')[0]}"
        if o.type == "MESH":
            o.data = o.data.copy()
            me = o.data
            m = Matrix.Diagonal((-1 if mirror else 1, 1, 1, 1)) @ Matrix.Scale(SCALE, 4)
            me.transform(m)
            if mirror:
                me.flip_normals()
        o.location = Vector((-o.location.x if mirror else o.location.x, o.location.y, o.location.z)) * SCALE
        o.rotation_euler = (0, 0, 0)
    return objs


def handle_frame(verts, box, u, s):
    """Handle centre, axes and size from the gun vertices inside `box`, along the given axis u."""
    lo, hi = Vector(box[0]), Vector(box[1])
    pts = [v for v in verts if all(lo[i] <= v[i] <= hi[i] for i in range(3))]
    c = sum(pts, Vector()) / len(pts)
    u = u.normalized()
    s = (s - u * s.dot(u)).normalized()
    return c, u, s, pts


def ellipse_rho(p, c, u, s, w, a, b):
    d = p - c
    d = d - u * d.dot(u)
    return math.hypot(d.dot(s) / a, d.dot(w) / b)


def seg_tip(o, child):
    if child is not None:
        return child.matrix_world.translation.copy()
    ys = [v.co.y for v in o.data.vertices]
    return o.matrix_world @ Vector((0, max(ys) * 0.85, 0))


def curl_chain(chain, palm_n, c, u, s, w, a, b, max_deg):
    """Bend each segment about (rest direction x palm normal) until its tip reaches the handle."""
    for j, o in enumerate(chain):
        child = chain[j + 1] if j + 1 < len(chain) else None
        rest_dir = (child.location if child else Vector((0, 1, 0))).normalized()
        axis = rest_dir.cross(palm_n)
        if axis.length < 1e-6:
            continue
        axis.normalize()
        best = 0.0
        for k in range(0, int(max_deg) + 1, 2):
            o.rotation_mode = "AXIS_ANGLE"
            o.rotation_axis_angle = (math.radians(k), *axis)
            bpy.context.view_layer.update()
            best = k
            if ellipse_rho(seg_tip(o, child), c, u, s, w, a, b) <= 1.0:
                break
        o.rotation_mode = "AXIS_ANGLE"
        o.rotation_axis_angle = (math.radians(best), *axis)
        bpy.context.view_layer.update()
        print(f"    {o.name}: {best} deg")


def box_uv(me):
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        ax = max(range(3), key=lambda k: abs(poly.normal[k]))
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            q = [v[i] for i in range(3) if i != ax]
            uvl.data[li].uv = (q[0] * 10, q[1] * 10)


def make_hand(spec, verts, overrides):
    right = spec["name"] == "R"
    prefix = "HandModel" + spec["name"]
    objs = load_source(prefix, mirror=right)
    c, u, s, pts = handle_frame(verts, spec["box"], spec["u"], spec["s"])
    w = s.cross(u) if right else u.cross(s)
    es = max(abs((p - c).dot(s)) for p in pts)
    ew = max(abs((p - c).dot(w)) for p in pts)
    top = min((p - c).dot(u) for p in pts)
    n = len(pts)
    print(f"  {prefix}: {n} handle verts, half-sizes {es * 100:.1f} x {ew * 100:.1f} cm")
    hand = objs["hand"]
    # Model frame after the (optional) mirror: index -> pinky = +X (right) / -X (left), fingers +Y,
    # palm -Z.  Map: index->pinky -> u, fingers -> w, palm normal (-Z) -> -s.
    mx = u if right else -u
    rot = Matrix((mx, w, mx.cross(w))).transposed()
    if (rot @ Vector((0, 0, -1))).dot(s) > 0:
        raise SystemExit(f"{prefix}: frame handedness mismatch")
    # Swing the heel away from the handle (rotate about u through the knuckle row).
    yaw_axis = w.cross(-s)
    rot = Matrix.Rotation(math.radians(spec["yaw"]), 3, yaw_axis) @ rot
    k_local = sum((objs[f + "_0"].location for f in FINGERS), Vector()) / 4  # knuckle row centre
    idx_local = objs["index_0"].location
    r_f = 0.19 * SCALE
    # Index knuckle along u at top + at; knuckle row on the palm side, near the front edge.
    k_world = c + u * (top - 0 + spec["at"] + (k_local - idx_local).dot(Vector((1 if right else -1, 0, 0)))) \
        + s * (es + r_f * 1.1) + w * (ew * spec["front"])
    hand.matrix_world = Matrix.Translation(k_world - rot @ k_local) @ rot.to_4x4()
    bpy.context.view_layer.update()
    a, b = es + r_f, ew + r_f
    palm_n = Vector((0, 0, -1))
    for f in FINGERS:
        curl_chain([objs[f"{f}_{j}"] for j in range(3)], palm_n, c, u, s, w, a, b, 105)
    curl_chain([objs[f"thumb_{j}"] for j in range(3)], palm_n, c, u, s, w, a, b, 50)
    # Forearm: turn it (about the wrist) so its far end (-Y) points along spec["arm"].
    arm = objs["arm_lower"]
    cur = -(arm.matrix_world.to_3x3().col[1]).normalized()
    q = cur.rotation_difference(spec["arm"].normalized())
    mw = arm.matrix_world.copy()
    t = mw.translation.copy()
    arm.matrix_world = Matrix.Translation(t) @ q.to_matrix().to_4x4() @ Matrix.Translation(-t) @ mw
    # Hand-tuned poses (local transforms per piece) override the solver.
    for name, t in overrides.get(prefix, {}).items():
        o = bpy.data.objects.get(name)
        if o is None:
            continue
        o.rotation_mode = "QUATERNION"
        o.location = Vector(t["loc"])
        o.rotation_quaternion = t["rot"]
    bpy.context.view_layer.update()
    for o in objs.values():
        if o.type != "MESH":
            continue
        mat = "ArmSuit" if o.name.endswith("arm_lower") else "ArmGlove"
        o.data.materials.clear()
        o.data.materials.append(bpy.data.materials.get(mat) or bpy.data.materials.new(mat))
        if not o.data.uv_layers:
            box_uv(o.data)
        for p in o.data.polygons:
            p.use_smooth = True
    return hand


def build(gun):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, gun + ".glb"))
    verts = [o.matrix_world @ v.co for o in bpy.data.objects if o.type == "MESH" for v in o.data.vertices]
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    overrides = json.load(open(OVERRIDES)).get(gun, {}) if os.path.exists(OVERRIDES) else {}
    root = bpy.data.objects.new("HandModel", None)
    bpy.context.scene.collection.objects.link(root)
    for spec in HANDS[gun]:
        h = make_hand(spec, verts, overrides)
        mw = h.matrix_world.copy()
        h.parent = root
        h.matrix_world = mw
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        o.select_set(True)
    path = os.path.join(OUT, f"rigid_{gun}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True)
    print("exported", path)


for g in HANDS:
    build(g)
