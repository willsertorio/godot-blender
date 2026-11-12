"""V2 concept scene, stage 2: the pistol held in two gloved hands, in front of the player camera.

    blender -b -P v2/scripts/build_viewmodel.py          (run after build_room.py; rebuilds the Viewmodel collection)

Everything is built in "gun space" (barrel +Y, up +Z, metres; see build_pistol.py) and
then placed in front of the camera through the `Viewmodel` empty.
- Pistol: build_pistol.py (a detailed service pistol built for this scene); its ANCHORS place the hands.
- Arms: MakeHuman base mesh + skeleton + weights (CC0, mh_arm.py). Each hand: fingers curled about their hinge
  axes, the hand placed by a target frame (wrist -> knuckles, index -> pinky, palm normal) and an anchor point, the
  arm solved from a shoulder point (two-bone solve, forearm twist spread over the twist bones), thumb aimed along
  the frame. The posed arms are then baked to static meshes.
- Gloves: the hand surface itself becomes the glove (subdivided, pushed out, knit fabric), a darker jacket sleeve on
  the forearm, and shrink-wrapped parts on top: back-of-hand pad, knuckle pads, wrist cuff with a cyan accent band.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import mh_arm  # noqa: E402
import v2lib as L  # noqa: E402

XM9 = os.path.abspath(os.path.join(L.ROOT, "..", "blender", "xm9.blend"))
K9, O9 = 0.000453, (715, 235)
RAKE = math.atan2(33, 115)
# Where the gun sits in the camera's frame: right, forward, up (m) and a small turn toward the screen centre (deg).
GUN_IN_CAM = (0.095, 0.315, -0.085)
GUN_YAW, GUN_PITCH = 9.0, 3.0


def P9(x, y, xx=0.0):
    return Vector((xx, (O9[0] - x) * K9, (O9[1] - y) * K9))


bpy.ops.wm.open_mainfile(filepath=os.path.join(L.ROOT, "scene.blend"))
sc = bpy.context.scene
old = bpy.data.collections.get("Viewmodel")
if old:
    for o in list(old.all_objects):
        bpy.data.objects.remove(o)
    bpy.data.collections.remove(old)
VM = L.coll("Viewmodel")
root = bpy.data.objects.new("Viewmodel", None)
root.empty_display_size = 0.05
VM.objects.link(root)

# ------------------------------------------------------------------ materials
# (materials saved in scene.blend by an earlier run would be reused as they were: drop them first)
for _n in ("PistolSlide", "PistolFrame", "PistolDark", "PistolGrip", "PistolCyan", "SightDot", "RedDot", "SightGlass",
           "GloveKnit", "JacketSleeve", "GlovePad", "GloveCuff", "GlovePalm", "GloveTip", "Glove"):
    if bpy.data.materials.get(_n):
        bpy.data.materials.remove(bpy.data.materials[_n])
M_SLIDE = L.pbr("PistolSlide", "Metal032", scale=0.12, tint=(1.3, 1.3, 1.28), rough=(0.28, 0.5), grunge=0.12, grunge_scale=25)
M_FRAME = L.pbr("PistolFrame", "Plastic012B", scale=0.06, bright=2.4, rough=(0.45, 0.7))
M_GDARK = L.pbr("PistolDark", "Metal032", scale=0.1, tint=(0.14, 0.145, 0.16), rough=(0.3, 0.5))
M_GRIP = L.pbr("PistolGrip", "Rubber004", scale=0.02, bright=2.0, rough=(0.6, 0.9), normal=2.0)
M_CYAN = L.plain("PistolCyan", (0, 0.02, 0.03), emit=(0.15, 0.85, 1.0), emit_strength=1.6)
M_WHITE = L.plain("SightDot", (0.9, 0.9, 0.88), rough=0.4, emit=(0.9, 1.0, 0.9), emit_strength=0.6)
M_REDDOT = L.plain("RedDot", (0, 0, 0), emit=(1.0, 0.08, 0.04), emit_strength=60.0)
M_GLASS = L.plain("SightGlass", (0.75, 0.9, 1.0), rough=0.0, transmission=1.0, ior=1.45)
# knit back, leather palm and grippy fingertips are one material: the fabrics change along smooth lines given by the
# point attributes "palm" and "tip" (bake_arm), each with a sewn seam
M_GLOVE = L.layered("Glove", [
    dict(set="Fabric045", scale=0.11, tint=(0.38, 0.4, 0.43), rough=(0.75, 1.0), normal=2.5),
    dict(set="Rubber004", scale=0.03, bright=2.6, tint=(0.75, 0.78, 0.85), rough=(0.55, 0.8), normal=1.2),
    dict(set="Rubber004", scale=0.012, bright=1.0, rough=(0.5, 0.75), normal=3.0),
], ["palm", "tip"], seam=0.09, seam_depth=0.0012, wrinkle=0.4, wrinkle_scale=70)
M_SLEEVE = L.pbr("JacketSleeve", "Fabric045", scale=0.16, tint=(0.11, 0.12, 0.14), rough=(0.8, 1.0), normal=2.5, wrinkle=0.6,
                 wrinkle_scale=35)
M_PAD = L.pbr("GlovePad", "Rubber004", scale=0.025, bright=2.2, tint=(0.8, 0.82, 0.88), rough=(0.4, 0.7), normal=1.5,
              round_edges=0.0006)
M_CUFF = L.pbr("GloveCuff", "Fabric045", scale=0.02, tint=(0.2, 0.21, 0.23), rough=(0.7, 1.0), normal=2.0)
REMAP = {"GunSlide": M_SLIDE, "GunFrame": M_FRAME, "GunDark": M_GDARK, "GunGrip": M_GRIP, "GunBarrel": M_GDARK,
         "NeonCyan": M_CYAN, "GunScreen": M_CYAN, "GunMagazine": M_FRAME, "GunBrass": M_GDARK, "GunLens": M_GLASS}

# ------------------------------------------------------------------ pistol (v2/scripts/build_pistol.py)
import build_pistol  # noqa: E402
build_pistol.build(VM, root)
AN = build_pistol.ANCHORS
RAKE = AN["rake"]


# ------------------------------------------------------------------ arms
def upd():
    bpy.context.view_layer.update()


def rot_about(pb, pivot, rot3):
    m = Matrix.Translation(pivot) @ rot3.to_4x4() @ Matrix.Translation(-pivot)
    pb.matrix = m @ pb.matrix
    upd()


def hand_frame(pb, side):
    w0 = pb["wrist"].head.copy()
    k = {f: pb[f"finger{f}-1"].head.copy() for f in range(2, 6)}
    F = (k[3] - w0).normalized()
    A = k[5] - k[2]
    A = (A - F * A.dot(F)).normalized()
    pn = F.cross(A) if side == "R" else A.cross(F)
    return w0, k, F, A, pn.normalized()


def pose_hand(side, curls, F_t, A_hint, anchor_fn, anchor_target, shoulder, pole, thumb_dirs):
    rig, ob = mh_arm.build_arm(side, VM)
    bpy.context.view_layer.objects.active = rig
    pb = rig.pose.bones
    upd()
    w0, k, F, A, pn = hand_frame(pb, side)
    tip = pb["finger1-3"].tail - w0
    print(f"  {side}: palm-normal check (thumb on palm side): {tip.dot(pn):+.3f}")
    # 1. curl the four fingers about their hinge axes (rest pose)
    for f in range(2, 6):
        d = (pb[f"finger{f}-1"].tail - pb[f"finger{f}-1"].head).normalized()
        axis = d.cross(pn).normalized()
        for j in range(3):
            b = pb[f"finger{f}-{j + 1}"]
            rot_about(b, b.head.copy(), Matrix.Rotation(math.radians(curls[f][j]), 3, axis))
    # 2. where the hand goes
    F_t = F_t.normalized()
    A_t = (A_hint - F_t * A_hint.dot(F_t)).normalized()
    pn_t = F_t.cross(A_t) if side == "R" else A_t.cross(F_t)
    R = Matrix((F_t, A_t, pn_t)).transposed() @ Matrix((F, A, pn)).transposed().inverted()
    a_rest = anchor_fn(pb, w0, k, F, A, pn)
    M = Matrix.Translation(anchor_target) @ R.to_4x4() @ Matrix.Translation(-a_rest)
    wrist_goal = M @ pb["wrist"].matrix
    P = M @ w0
    # 3. arm: two-bone solve shoulder -> elbow -> wrist
    S = Vector(shoulder)
    l1 = (pb["lowerarm01"].head - pb["upperarm01"].head).length
    l2 = (pb["wrist"].head - pb["lowerarm01"].head).length
    ax = P - S
    dist = min(ax.length, l1 + l2 - 1e-4)
    u = ax.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    pl = Vector(pole) - u * Vector(pole).dot(u)
    E = S + u * a + pl.normalized() * h
    ua = pb["upperarm01"]
    cur = (pb["lowerarm01"].head - ua.head).normalized()
    m = Matrix.Translation(S) @ cur.rotation_difference((E - S).normalized()).to_matrix().to_4x4() @ Matrix.Translation(-ua.head)
    ua.matrix = m @ ua.matrix
    upd()
    la = pb["lowerarm01"]
    cur = (pb["wrist"].head - la.head).normalized()
    rot_about(la, la.head.copy(), cur.rotation_difference((P - la.head).normalized()).to_matrix())
    fax = (pb["wrist"].head - la.head).normalized()
    q = (wrist_goal.to_3x3() @ pb["wrist"].matrix.to_3x3().inverted()).to_quaternion()
    twist = 2 * math.atan2(Vector((q.x, q.y, q.z)).dot(fax), q.w)
    twist = (twist + math.pi) % (2 * math.pi) - math.pi
    rot_about(la, la.head.copy(), Matrix.Rotation(twist * 0.35, 3, fax))
    l2b = pb["lowerarm02"]
    rot_about(l2b, l2b.head.copy(), Matrix.Rotation(twist * 0.45, 3, fax))
    pb["wrist"].matrix = wrist_goal
    upd()
    bend = math.degrees(fax.angle((pb["finger3-1"].head - pb["wrist"].head).normalized()))
    print(f"  {side}: wrist bend {bend:.0f} deg, forearm twist {math.degrees(twist):.0f} deg, reach {ax.length:.2f} / {l1 + l2:.2f} m")
    # 4. thumb: aim its three bones
    for j, tdir in enumerate(thumb_dirs):
        b = pb[f"finger1-{j + 1}"]
        cur = (b.tail - b.head).normalized()
        rot_about(b, b.head.copy(), cur.rotation_difference(Vector(tdir).normalized()).to_matrix())
    return rig, ob


def bake_arm(rig, ob, side):
    """Posed arm -> static glove + sleeve mesh, plus the shrink-wrapped pads and cuff."""
    pb = rig.pose.bones
    w0, k, F, A, pn = hand_frame(pb, side)
    fdir = (pb["wrist"].head - pb["lowerarm01"].head).normalized()
    hand_bones = [n for n in mh_arm.bone_names() if n.startswith(("wrist", "metacarpal", "finger"))]
    rb = rig.data.bones
    rest_w = rb["wrist"].head_local.copy()
    rest_f = (rb["wrist"].head_local - rb["lowerarm01"].head_local).normalized()
    vg = ob.vertex_groups.new(name="glove")
    sl = ob.vertex_groups.new(name="sleeve")
    gw = []
    for v in ob.data.vertices:
        g = sum(e.weight for e in v.groups if ob.vertex_groups[e.group].name in hand_bones)
        gw.append(g)
        vg.add([v.index], min(g, 1.0), "REPLACE")
        sl.add([v.index], max(0.0, 1.0 - g), "REPLACE")
    ob.data.materials.append(M_GLOVE)
    ob.data.materials.append(M_SLEEVE)
    # rest-pose hand frame: which faces are palm side, which are fingertips (classified before the pose deforms them)
    rk = {f: rb[f"finger{f}-1"].head_local.copy() for f in range(2, 6)}
    rF = (rk[3] - rest_w).normalized()
    rA = rk[5] - rk[2]
    rA = (rA - rF * rA.dot(rF)).normalized()
    rpn = (rF.cross(rA) if side == "R" else rA.cross(rF)).normalized()
    names = [g.name for g in ob.vertex_groups]
    tipw = [sum(e.weight for e in v.groups if names[e.group].endswith("-3")) for v in ob.data.vertices]
    # glove fabric runs to 3.5 cm behind the wrist (the edge is hidden under the cuff), then the jacket sleeve
    for p in ob.data.polygons:
        c = sum((ob.data.vertices[v].co for v in p.vertices), Vector()) / len(p.vertices)
        p.material_index = 1 if (rest_w - c).dot(rest_f) >= 0.035 else 0
    # palm side / fingertip masks as vertex groups: subdivision interpolates them, so the seams between knit, leather
    # and tips are assigned on the fine mesh and follow smooth lines
    pg = ob.vertex_groups.new(name="palmside")
    tg = ob.vertex_groups.new(name="tipside")
    pw = [min(max(v.normal.dot(rpn) / 0.5, 0.0), 1.0) for v in ob.data.vertices]
    nb = [[] for _ in pw]
    for e in ob.data.edges:
        nb[e.vertices[0]].append(e.vertices[1])
        nb[e.vertices[1]].append(e.vertices[0])
    for _ in range(4):                                      # smooth the mask so the seam is a clean line
        pw = [0.4 * pw[i] + 0.6 * sum(pw[j] for j in nb[i]) / max(len(nb[i]), 1) for i in range(len(pw))]
    for v in ob.data.vertices:
        pg.add([v.index], pw[v.index], "REPLACE")
        tg.add([v.index], min(tipw[v.index], 1.0), "REPLACE")
    PG, TG = pg.index, tg.index
    ss = ob.modifiers.new("Subsurf", "SUBSURF")
    ss.levels = ss.render_levels = 2
    for name, strength in (("glove", 0.0016), ("sleeve", 0.006)):
        dm = ob.modifiers.new("Thick_" + name, "DISPLACE")
        dm.vertex_group = name
        dm.strength = strength
        dm.mid_level = 0.0
    upd()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    def gw_of(v, gi):
        for e in v.groups:
            if e.group == gi:
                return e.weight
        return 0.0
    # the masks become point attributes; the glove material draws the fabric edges and seams from them per pixel
    for an, gi in (("palm", PG), ("tip", TG)):
        at = me.attributes.new(an, "FLOAT", "POINT")
        at.data.foreach_set("value", [gw_of(v, gi) for v in me.vertices])
    st = bpy.data.objects.new(f"Glove.{side}", me)
    VM.objects.link(st)
    for p in me.polygons:
        p.use_smooth = True
    bpy.data.objects.remove(ob)
    bpy.data.objects.remove(rig)
    st.parent = root
    out = -pn

    def wrapped(name, centre, x_axis, y_axis, sx, sy, material, power=4.0, offset=0.0022, thick=0.003):
        """A rounded pad lying on the surface: grid -> projected onto the glove -> thickness -> smooth."""
        bm = bmesh.new()                       # superellipse disc (smooth outline), rings x segments
        RINGS, SEGS = 6, 36
        centre_v = bm.verts.new((0, 0, 0))
        prev = None
        for r in range(1, RINGS + 1):
            ring = []
            for i in range(SEGS):
                t = i * math.tau / SEGS
                c, s_ = math.cos(t), math.sin(t)
                rad = 0.5 / (abs(c) ** power + abs(s_) ** power) ** (1.0 / power) * r / RINGS
                ring.append(bm.verts.new((c * rad, s_ * rad, 0)))
            for i in range(SEGS):
                j = (i + 1) % SEGS
                if prev is None:
                    bm.faces.new((centre_v, ring[i], ring[j]))
                else:
                    bm.faces.new((prev[i], ring[i], ring[j], prev[j]))
            prev = ring
        m2 = bpy.data.meshes.new(name)
        bm.to_mesh(m2)
        bm.free()
        o = bpy.data.objects.new(name, m2)
        VM.objects.link(o)
        z = x_axis.cross(y_axis).normalized()
        mat = Matrix((x_axis * sx, y_axis * sy, z)).transposed().to_4x4()
        mat.translation = centre + z * 0.004
        o.matrix_world = mat
        sw = o.modifiers.new("Wrap", "SHRINKWRAP")
        sw.target = st
        sw.wrap_method = "NEAREST_SURFACEPOINT"     # (projection left ragged edges where rays missed the hand)
        sw.wrap_mode = "ABOVE_SURFACE"
        sw.offset = offset
        so = o.modifiers.new("Solid", "SOLIDIFY")
        so.thickness = thick
        so.offset = 1.0
        s2 = o.modifiers.new("Smooth", "SUBSURF")
        s2.levels = s2.render_levels = 2
        upd()
        me2 = bpy.data.meshes.new_from_object(o.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        mw = o.matrix_world.copy()
        bpy.data.objects.remove(o)
        o2 = bpy.data.objects.new(name, me2)
        VM.objects.link(o2)
        o2.matrix_world = mw
        me2.materials.append(material)
        for p in me2.polygons:
            p.use_smooth = True
        o2.parent = root
        return o2

    kc = sum(k.values(), Vector()) / 4
    AX = A if side == "R" else -A            # so that AX x F points out of the back of the hand on both sides
    # the pads sit toward the thumb side of the back of the hand: that is the part the player's eye sees
    back = w0.lerp(kc, 0.5) - A * 0.014
    wrapped(f"BackPad.{side}", back, AX, F, 0.07, 0.05, M_PAD, power=5.0, thick=0.0035)
    # the top edge of the hand (thumb side, from the index knuckle back to the wrist): faces the player's eye
    rad_x, rad_y = (out, F) if side == "R" else (F, out)
    wrapped(f"EdgePad.{side}", k[2].lerp(w0, 0.42) - A * 0.016, rad_x, rad_y, 0.03 if side == "R" else 0.046,
            0.046 if side == "R" else 0.03, M_PAD, power=4.0, thick=0.003)
    wrapped(f"KnuckleGuard.{side}", kc + F * 0.003, AX, F, 0.08, 0.02, M_PAD, power=6.0, thick=0.004)
    t1 = pb_cache[side][1]                    # thumb: a pad along its first phalanx, facing away from the palm
    td = (t1[1] - t1[0]).normalized()
    tx = (out - td * out.dot(td)).cross(td).normalized()
    wrapped(f"ThumbPad.{side}", t1[0].lerp(t1[1], 0.6), tx if side == "R" else -tx, td, 0.015, 0.03, M_PAD, power=3.5,
            thick=0.003, offset=0.0015)
    for f in range(2, 6):
        b1 = pb_cache[side][f]
        mid = b1[0].lerp(b1[1], 0.55)
        fd = (b1[1] - b1[0]).normalized()
        ax = (AX - fd * AX.dot(fd)).normalized()
        wrapped(f"FingerPad{f}.{side}", mid, ax, fd, 0.012, 0.022, M_PAD, power=3.5, thick=0.0028, offset=0.0015)

    from mathutils.bvhtree import BVHTree
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])

    def band(name, back_off, length, offset, thick, material, rings=5):
        """A sleeve band round the forearm: rings of points found by casting rays inward at the arm surface."""
        bm = bmesh.new()
        segs = 48
        prev = None
        xa = fdir.orthogonal().normalized()
        ya = fdir.cross(xa)
        for r in range(rings):
            c = w0 - fdir * (back_off + length * r / (rings - 1))
            ring = []
            for i in range(segs):
                dv = xa * math.cos(i * math.tau / segs) + ya * math.sin(i * math.tau / segs)
                hit = bvh.ray_cast(c + dv * 0.07, -dv, 0.07)[0]
                rad = min((hit - c).length, 0.045) if hit is not None else 0.03
                ring.append(rad)
            ring = [(ring[i - 1] + 2 * ring[i] + ring[(i + 1) % segs]) / 4 for i in range(segs)]      # soften
            vs = [bm.verts.new(c + (xa * math.cos(i * math.tau / segs) + ya * math.sin(i * math.tau / segs)) * (ring[i] + offset))
                  for i in range(segs)]
            if prev:
                for i in range(segs):
                    bm.faces.new((prev[i], prev[(i + 1) % segs], vs[(i + 1) % segs], vs[i]))
            prev = vs
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        m2 = bpy.data.meshes.new(name)
        bm.to_mesh(m2)
        bm.free()
        o2 = bpy.data.objects.new(name, m2)
        VM.objects.link(o2)
        so = o2.modifiers.new("Solid", "SOLIDIFY")
        so.thickness = thick
        so.offset = 1.0
        bv = o2.modifiers.new("Bevel", "BEVEL")
        bv.width = min(thick * 0.45, 0.0012)
        bv.segments = 2
        bv.limit_method = "ANGLE"
        m2.materials.append(material)
        for p in m2.polygons:
            p.use_smooth = True
        o2.parent = root

    band(f"Cuff.{side}", 0.012, 0.055, 0.0045, 0.0035, M_CUFF, rings=6)
    band(f"CuffStrap.{side}", 0.024, 0.022, 0.0082, 0.0025, M_PAD, rings=3)
    band(f"CuffAccent.{side}", 0.052, 0.004, 0.0083, 0.0012, M_CYAN, rings=2)
    return st


pb_cache = {}
u = Vector((0, -math.sin(RAKE), -math.cos(RAKE)))
CAM = Vector((-GUN_IN_CAM[0], -GUN_IN_CAM[1], -GUN_IN_CAM[2]))      # camera position in gun space (before the small turn)
TANG, GC, HW = AN["tang"], AN["grip_centre"], AN["grip_half_width"]
arms = {}
for side, spec in (
    # Right hand: web of the thumb high under the tang, three fingers round the front strap, index straight along
    # the frame above the trigger guard, thumb forward along the left side.
    ("R", dict(curls={2: (6, 10, 5), 3: (58, 84, 40), 4: (62, 86, 42), 5: (66, 88, 44)},
               F_t=Vector((-0.14, 1.0, -0.16)), A_hint=u,
               anchor_fn=lambda pb, w0, k, F, A, pn: (pb["finger1-2"].head + k[2]) / 2 - F * 0.012,
               anchor_target=TANG + Vector((0.004, -0.004, -0.004)),
               shoulder=CAM + Vector((0.2, -0.04, -0.3)), pole=(0.7, 0.0, -1.0),
               thumb_dirs=((-0.5, 0.85, 0.15), (-0.12, 1.0, 0.06), (0.0, 1.0, 0.0)))),
    # Left hand: palm on the left side of the grip, fingers wrapped over the right hand's fingers under the trigger
    # guard, wrist dropped 45 degrees, thumb forward under the slide.
    ("L", dict(curls={2: (50, 74, 38), 3: (54, 78, 40), 4: (56, 80, 40), 5: (58, 82, 40)},
               F_t=Vector((0.25, 0.74, -0.62)), A_hint=Vector((0.0, -0.64, -0.77)),
               anchor_fn=lambda pb, w0, k, F, A, pn: w0.lerp(k[3], 0.55) + pn * 0.014,
               anchor_target=GC + Vector((-HW - 0.008, 0.004, 0.0)),
               shoulder=CAM + Vector((-0.1, -0.04, -0.3)), pole=(-0.7, 0.0, -1.0),
               thumb_dirs=((0.22, 0.92, 0.3), (0.08, 1.0, 0.1), (0.04, 1.0, 0.0))))):
    rig, ob = pose_hand(side, **spec)
    pbs = rig.pose.bones
    pb_cache[side] = {f: (pbs[f"finger{f}-1"].head.copy(), pbs[f"finger{f}-1"].tail.copy()) for f in range(1, 6)}
    arms[side] = bake_arm(rig, ob, side)

# ------------------------------------------------------------------ place in front of the camera
cam = bpy.data.objects["PlayerCamera"]
basis = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0))).to_4x4()          # gun (x, y, z) -> camera local (x, z, -y)
local = Matrix.Translation((GUN_IN_CAM[0], GUN_IN_CAM[2], -GUN_IN_CAM[1])) @ basis
local = local @ Matrix.Rotation(math.radians(GUN_YAW), 4, "Z") @ Matrix.Rotation(math.radians(GUN_PITCH), 4, "X")
root.matrix_world = cam.matrix_world @ local
bpy.ops.wm.save_mainfile()
print("viewmodel built:", len(VM.all_objects), "objects")
