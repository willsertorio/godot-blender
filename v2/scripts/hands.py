"""Rigged, gloved arms for the V2 weapon views (used by build_viewmodel.py and the animation scripts).

Each arm is the MakeHuman base mesh with its skeleton and skin weights (CC0, mh_arm.py), and it stays rigged:
- `Hands.new_arm(side)`: the glove is made in the rest pose (subdivided, pushed out to glove / sleeve thickness,
  fabric masks and rest positions stored as point attributes) and then skinned to the armature. Nothing is frozen.
- `pose(rig, side, **spec)`: one hand pose = finger curls about their hinge axes, a hand target frame (wrist ->
  knuckles, index -> pinky, palm normal) with an anchor point, a two-bone arm solve from a shoulder point (forearm
  twist spread over the twist bones) and thumb directions. It starts from the rest pose every time, so it can be
  called again for any frame of an animation. Everything is in gun space (= armature space).
- Pads are shrink-wrapped onto the glove, frozen, and parented to the bone they sit on: the finger pads in the rest
  pose (`add_finger_pads`), the hand and thumb pads and the forearm cuff bands in the hold pose (`add_pads`).
- `pistol_hold()` / `rifle_hold()`: the hold poses of the two weapons.

Bones (no side suffix): upperarm01/02, lowerarm01/02, wrist, metacarpal1-4, finger<1-5>-<1-3> (finger1 = thumb).
Objects are named <Name>.<side>.<tag>, e.g. ArmRig.R.pistol, Glove.L.rifle, BackPad.R.pistol.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import mh_arm
import v2lib as L

# Two weapon views share the player camera. Where each gun sits in the camera's frame: right, forward, up (m), then a
# turn toward the screen centre, a tilt up and a roll (deg).
PLACE = {
    "pistol": dict(at=(0.095, 0.315, -0.085), yaw=9.0, pitch=3.0, roll=0.0),
    "rifle": dict(at=(0.165, 0.365, -0.07), yaw=5.0, pitch=4.0, roll=0.0),
}
COLL = {"pistol": "Viewmodel", "rifle": "ViewmodelRifle"}


def cam_in_gun(weapon):
    """The camera position in gun space (before the small turn): shoulders are given relative to it."""
    return -Vector(PLACE[weapon]["at"])


def view_local(weapon):
    """Matrix of a view's root empty in the camera's frame (the root is a child of the camera): gun space placed in
    front of the eye."""
    pl = PLACE[weapon]
    basis = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0))).to_4x4()          # gun (x, y, z) -> camera local (x, z, -y)
    local = Matrix.Translation((pl["at"][0], pl["at"][2], -pl["at"][1])) @ basis
    local = local @ Matrix.Rotation(math.radians(pl["yaw"]), 4, "Z") @ Matrix.Rotation(math.radians(pl["pitch"]), 4, "X") \
        @ Matrix.Rotation(math.radians(pl["roll"]), 4, "Y")
    return local


MATERIAL_NAMES = ("Glove", "JacketSleeve", "GlovePad", "GloveCuff", "GloveAccent")


def materials():
    """The glove materials (dropped and rebuilt: a material saved in scene.blend would be reused unchanged).
    Glove and sleeve project their fabrics from the `rest` attribute, so the weave stays on the moving surface."""
    for n in MATERIAL_NAMES + ("GloveKnit", "GlovePalm", "GloveTip", "PistolCyan"):
        if bpy.data.materials.get(n):
            bpy.data.materials.remove(bpy.data.materials[n])
    m = {}
    # knit back, leather palm and grippy fingertips are one material: the fabrics change along smooth lines given by
    # the point attributes "palm" and "tip", each with a sewn seam
    m["glove"] = L.layered("Glove", [
        dict(set="Fabric045", scale=0.11, tint=(0.38, 0.4, 0.43), rough=(0.75, 1.0), normal=2.5),
        dict(set="Rubber004", scale=0.03, bright=2.6, tint=(0.75, 0.78, 0.85), rough=(0.55, 0.8), normal=1.2),
        dict(set="Rubber004", scale=0.012, bright=1.0, rough=(0.5, 0.75), normal=3.0),
    ], ["palm", "tip"], seam=0.09, seam_depth=0.0012, wrinkle=0.4, wrinkle_scale=70, coord_attr="rest")
    m["sleeve"] = L.pbr("JacketSleeve", "Fabric045", scale=0.16, tint=(0.11, 0.12, 0.14), rough=(0.8, 1.0), normal=2.5,
                        wrinkle=0.6, wrinkle_scale=35, coord_attr="rest")
    m["pad"] = L.pbr("GlovePad", "Rubber004", scale=0.025, bright=2.2, tint=(0.8, 0.82, 0.88), rough=(0.4, 0.7), normal=1.5,
                     round_edges=0.0006)
    m["cuff"] = L.pbr("GloveCuff", "Fabric045", scale=0.02, tint=(0.2, 0.21, 0.23), rough=(0.7, 1.0), normal=2.0)
    m["accent"] = L.plain("GloveAccent", (0, 0.02, 0.03), emit=(0.15, 0.85, 1.0), emit_strength=1.6)
    return m


def upd():
    bpy.context.view_layer.update()


def rot_about(pb, pivot, rot3):
    m = Matrix.Translation(pivot) @ rot3.to_4x4() @ Matrix.Translation(-pivot)
    pb.matrix = m @ pb.matrix
    upd()


def hand_frame(pb, side):
    """Wrist, knuckles and the hand's axes: F wrist -> knuckles, A index -> pinky, pn out of the palm."""
    w0 = pb["wrist"].head.copy()
    k = {f: pb[f"finger{f}-1"].head.copy() for f in range(2, 6)}
    F = (k[3] - w0).normalized()
    A = k[5] - k[2]
    A = (A - F * A.dot(F)).normalized()
    pn = F.cross(A) if side == "R" else A.cross(F)
    return w0, k, F, A, pn.normalized()


def pose(rig, side, curls, F_t, A_hint, anchor_fn, anchor_target, shoulder, pole, thumb_dirs, quiet=False, reach=None):
    """Put one arm in a pose (gun space). Starts from the rest pose, so the result depends only on the arguments.
    reach (0..1): the shoulder follows the hand when the target is further than that share of the arm's length."""
    pb = rig.pose.bones
    for b in pb:
        b.matrix_basis = Matrix()
    upd()
    w0, k, F, A, pn = hand_frame(pb, side)
    # 1. curl the four fingers about their hinge axes (rest pose)
    for f in range(2, 6):
        d = (pb[f"finger{f}-1"].tail - pb[f"finger{f}-1"].head).normalized()
        axis = d.cross(pn).normalized()
        for j in range(3):
            b = pb[f"finger{f}-{j + 1}"]
            rot_about(b, b.head.copy(), Matrix.Rotation(math.radians(curls[f][j]), 3, axis))
    # 2. where the hand goes
    F_t = Vector(F_t).normalized()
    A_hint = Vector(A_hint)
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
    if reach and (P - S).length > (l1 + l2) * reach:           # the shoulder gives way before the arm overstretches
        S = P - (P - S).normalized() * (l1 + l2) * reach
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
    if not quiet:
        bend = math.degrees(fax.angle((pb["finger3-1"].head - pb["wrist"].head).normalized()))
        print(f"  {side}: wrist bend {bend:.0f} deg, forearm twist {math.degrees(twist):.0f} deg, "
              f"reach {ax.length:.2f} / {l1 + l2:.2f} m")
    # 4. thumb: aim its three bones
    for j, tdir in enumerate(thumb_dirs):
        b = pb[f"finger1-{j + 1}"]
        cur = (b.tail - b.head).normalized()
        rot_about(b, b.head.copy(), cur.rotation_difference(Vector(tdir).normalized()).to_matrix())


class Hands:
    """The two arms of one weapon view. Build while `root` is still at the origin (gun space = world space)."""

    def __init__(self, collection, root, tag, mats):
        self.coll, self.root, self.tag, self.mats = collection, root, tag, mats
        self.rigs, self.gloves = {}, {}

    def name(self, base, side):
        return f"{base}.{side}.{self.tag}"

    # ------------------------------------------------------------------ glove: made in the rest pose, then skinned
    def new_arm(self, side):
        rig, ob = mh_arm.build_arm(side, self.coll)
        rig.name = self.name("ArmRig", side)
        rb = rig.data.bones
        hand_bones = [n for n in mh_arm.bone_names() if n.startswith(("wrist", "metacarpal", "finger"))]
        rest_w = rb["wrist"].head_local.copy()
        rest_f = (rb["wrist"].head_local - rb["lowerarm01"].head_local).normalized()
        names = [g.name for g in ob.vertex_groups]
        vg = ob.vertex_groups.new(name="glove")
        sl = ob.vertex_groups.new(name="sleeve")
        for v in ob.data.vertices:
            g = sum(e.weight for e in v.groups if names[e.group] in hand_bones)
            vg.add([v.index], min(g, 1.0), "REPLACE")
            sl.add([v.index], max(0.0, 1.0 - g), "REPLACE")
        ob.data.materials.append(self.mats["glove"])
        ob.data.materials.append(self.mats["sleeve"])
        # which faces are palm side, which are fingertips
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
        # palm side / fingertip masks as vertex groups: subdivision interpolates them, so the seams between knit,
        # leather and tips follow smooth lines
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
        # the fine mesh is made here, in the rest pose (no armature yet): the skeleton then moves the finished glove
        for mod in list(ob.modifiers):
            ob.modifiers.remove(mod)
        ss = ob.modifiers.new("Subsurf", "SUBSURF")
        ss.levels = ss.render_levels = 2
        for gname, strength in (("glove", 0.0016), ("sleeve", 0.006)):
            dm = ob.modifiers.new("Thick_" + gname, "DISPLACE")
            dm.vertex_group = gname
            dm.strength = strength
            dm.mid_level = 0.0
        upd()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        me.name = self.name("Glove", side)

        def gw_of(v, gi):
            for e in v.groups:
                if e.group == gi:
                    return e.weight
            return 0.0
        # point attributes read by the materials: fabric masks, and the rest position the fabrics are projected from
        for an, gi in (("palm", PG), ("tip", TG)):
            at = me.attributes.new(an, "FLOAT", "POINT")
            at.data.foreach_set("value", [gw_of(v, gi) for v in me.vertices])
        at = me.attributes.new("rest", "FLOAT_VECTOR", "POINT")
        at.data.foreach_set("vector", [c for v in me.vertices for c in v.co])
        glove = bpy.data.objects.new(self.name("Glove", side), me)
        self.coll.objects.link(glove)
        for p in me.polygons:
            p.use_smooth = True
        bpy.data.objects.remove(ob)
        missing = [n for n in mh_arm.bone_names() if n not in glove.vertex_groups]
        assert not missing, f"skin weights lost on the fine mesh: {missing[:4]}"
        for gname in ("glove", "sleeve", "palmside", "tipside"):      # working groups: not needed any more
            glove.vertex_groups.remove(glove.vertex_groups[gname])
        glove.parent = rig
        mod = glove.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
        rig.parent = self.root
        rig.show_in_front = True
        self.rigs[side], self.gloves[side] = rig, glove
        upd()
        return rig, glove

    # ------------------------------------------------------------------ pads and cuffs (hold pose)
    def _to_bone(self, o, rig, bone):
        """Parent a finished part to a bone, where it is."""
        upd()
        mw = o.matrix_world.copy()
        pbone = rig.pose.bones[bone]
        par = rig.matrix_world @ pbone.matrix @ Matrix.Translation((0, pbone.bone.length, 0))
        o.parent = rig
        o.parent_type = "BONE"
        o.parent_bone = bone
        o.matrix_parent_inverse = par.inverted()
        o.matrix_basis = mw

    def _wrapped(self, rig, glove, side, name, bone, centre, x_axis, y_axis, sx, sy, material, power=4.0, offset=0.0022,
                 thick=0.003):
        """A rounded pad lying on the surface: disc -> wrapped onto the glove -> thickness -> smooth -> frozen."""
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
        self.coll.objects.link(o)
        z = x_axis.cross(y_axis).normalized()
        mat = Matrix((x_axis * sx, y_axis * sy, z)).transposed().to_4x4()
        mat.translation = centre + z * 0.004
        o.matrix_world = mat
        sw = o.modifiers.new("Wrap", "SHRINKWRAP")
        sw.target = glove
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
        o2 = bpy.data.objects.new(self.name(name, side), me2)
        self.coll.objects.link(o2)
        o2.matrix_world = mw
        me2.materials.append(material)
        for p in me2.polygons:
            p.use_smooth = True
        self._to_bone(o2, rig, bone)
        return o2

    def add_finger_pads(self, rig, glove, side):
        """Pads on the first phalanx of each finger. Fitted in the rest pose, where the fingers are apart: fitted on
        a closed hand, a pad also wraps onto the neighbouring finger and sits crooked once the hand opens."""
        pb = rig.pose.bones
        w0, k, F, A, pn = hand_frame(pb, side)
        AX = A if side == "R" else -A
        for f in range(2, 6):
            b0, b1 = pb[f"finger{f}-1"].head.copy(), pb[f"finger{f}-1"].tail.copy()
            fd = (b1 - b0).normalized()
            ax = (AX - fd * AX.dot(fd)).normalized()
            self._wrapped(rig, glove, side, f"FingerPad{f}", f"finger{f}-1", b0.lerp(b1, 0.55), ax, fd, 0.012, 0.022,
                          self.mats["pad"], power=3.5, thick=0.0028, offset=0.0015)

    def add_pads(self, rig, glove, side):
        pb = rig.pose.bones
        mats = self.mats
        w0, k, F, A, pn = hand_frame(pb, side)
        fdir = (pb["wrist"].head - pb["lowerarm01"].head).normalized()
        out = -pn
        coll = self.coll

        kc = sum(k.values(), Vector()) / 4
        AX = A if side == "R" else -A            # so that AX x F points out of the back of the hand on both sides
        # the pads sit toward the thumb side of the back of the hand: that is the part the player's eye sees
        back = w0.lerp(kc, 0.5) - A * 0.014
        self._wrapped(rig, glove, side, "BackPad", "wrist", back, AX, F, 0.07, 0.05, mats["pad"], power=5.0, thick=0.0035)
        # the top edge of the hand (thumb side, from the index knuckle back to the wrist): faces the player's eye
        rad_x, rad_y = (out, F) if side == "R" else (F, out)
        self._wrapped(rig, glove, side, "EdgePad", "wrist", k[2].lerp(w0, 0.42) - A * 0.016, rad_x, rad_y, 0.03 if side == "R" else 0.046,
                0.046 if side == "R" else 0.03, mats["pad"], power=4.0, thick=0.003)
        # knuckle guard: along the real knuckle line (index -> pinky) and wholly behind it, on the back of the hand:
        # a guard that reaches past the knuckles cuts through the finger bases when the hand opens
        kx = (k[5] - k[2]).normalized() * (1 if side == "R" else -1)
        ky = (F - kx * F.dot(kx)).normalized()
        self._wrapped(rig, glove, side, "KnuckleGuard", "wrist", kc - ky * 0.013, kx, ky, 0.078, 0.017, mats["pad"], power=6.0, thick=0.004)
        t0, t1 = pb["finger1-1"].head.copy(), pb["finger1-1"].tail.copy()     # thumb: along its first bone, facing out
        td = (t1 - t0).normalized()
        tx = (out - td * out.dot(td)).cross(td).normalized()
        self._wrapped(rig, glove, side, "ThumbPad", "finger1-1", t0.lerp(t1, 0.6), tx if side == "R" else -tx, td, 0.015, 0.03, mats["pad"],
                power=3.5, thick=0.003, offset=0.0015)

        ev = glove.evaluated_get(bpy.context.evaluated_depsgraph_get())
        em = ev.to_mesh()
        bvh = BVHTree.FromPolygons([v.co.copy() for v in em.vertices], [tuple(p.vertices) for p in em.polygons])
        ev.to_mesh_clear()

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
                    ring.append(min((hit - c).length, 0.045) if hit is not None else 0.03)
                ring = [(ring[i - 1] + 2 * ring[i] + ring[(i + 1) % segs]) / 4 for i in range(segs)]      # soften
                vs = [bm.verts.new(c + (xa * math.cos(i * math.tau / segs) + ya * math.sin(i * math.tau / segs))
                                   * (ring[i] + offset)) for i in range(segs)]
                if prev:
                    for i in range(segs):
                        bm.faces.new((prev[i], prev[(i + 1) % segs], vs[(i + 1) % segs], vs[i]))
                prev = vs
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            m2 = bpy.data.meshes.new(name)
            bm.to_mesh(m2)
            bm.free()
            o2 = bpy.data.objects.new(self.name(name, side), m2)
            coll.objects.link(o2)
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
            self._to_bone(o2, rig, "lowerarm02")

        band("Cuff", 0.012, 0.055, 0.0045, 0.0035, mats["cuff"], rings=6)
        band("CuffStrap", 0.024, 0.022, 0.0082, 0.0025, mats["pad"], rings=3)
        band("CuffAccent", 0.052, 0.004, 0.0083, 0.0012, mats["accent"], rings=2)

    def hold(self, specs):
        """Both arms: build, put in the hold pose, add the pads."""
        for side, spec in specs:
            rig, glove = self.new_arm(side)
            self.add_finger_pads(rig, glove, side)
            pose(rig, side, **spec)
            self.add_pads(rig, glove, side)


# ---------------------------------------------------------------------- hold poses (gun space, metres)
def trigger_hand(AN, CAM, shoulder=(0.2, -0.04, -0.3)):
    """Right hand on a pistol-type grip: web of the thumb high under the tang, three fingers round the front strap,
    index straight along the frame above the trigger guard, thumb forward along the left side."""
    rake = AN["rake"]
    return ("R", dict(curls={2: (6, 10, 5), 3: (58, 84, 40), 4: (62, 86, 42), 5: (66, 88, 44)},
                      F_t=Vector((-0.14, 1.0, -0.16)), A_hint=Vector((0, -math.sin(rake), -math.cos(rake))),
                      anchor_fn=lambda pb, w0, k, F, A, pn: (pb["finger1-2"].head + k[2]) / 2 - F * 0.012,
                      anchor_target=AN["tang"] + Vector((0.004, -0.004, -0.004)),
                      shoulder=CAM + Vector(shoulder), pole=(0.7, 0.0, -1.0),
                      thumb_dirs=((-0.5, 0.85, 0.15), (-0.12, 1.0, 0.06), (0.0, 1.0, 0.0))))


def pistol_hold(AN, CAM):
    """Two-handed pistol grip. Left hand: palm on the left side of the grip, fingers wrapped over the right hand's
    fingers under the trigger guard, wrist dropped 45 degrees, thumb forward under the slide."""
    return (
        trigger_hand(AN, CAM),
        ("L", dict(curls={2: (50, 74, 38), 3: (54, 78, 40), 4: (56, 80, 40), 5: (58, 82, 40)},
                   F_t=Vector((0.25, 0.74, -0.62)), A_hint=Vector((0.0, -0.64, -0.77)),
                   anchor_fn=lambda pb, w0, k, F, A, pn: w0.lerp(k[3], 0.55) + pn * 0.014,
                   anchor_target=AN["grip_centre"] + Vector((-AN["grip_half_width"] - 0.008, 0.004, 0.0)),
                   shoulder=CAM + Vector((-0.1, -0.04, -0.3)), pole=(-0.7, 0.0, -1.0),
                   thumb_dirs=((0.22, 0.92, 0.3), (0.08, 1.0, 0.1), (0.04, 1.0, 0.0)))))


def rifle_hold(AN, CAM):
    """Machine gun. Left hand: palm flat on the left face of the magazine well, knuckles at its front corner, fingers
    wrapped round the front face, thumb forward and up along the left face. The forearm comes up from below."""
    return (
        trigger_hand(AN, CAM, shoulder=(0.2, -0.02, -0.28)),
        ("L", dict(curls={2: (70, 70, 35), 3: (74, 74, 36), 4: (76, 76, 36), 5: (78, 78, 38)},
                   F_t=Vector((0.15, 0.85, 0.4)), A_hint=Vector((0.0, 0.35, -1.0)),
                   anchor_fn=lambda pb, w0, k, F, A, pn: w0.lerp(k[3], 0.55) + pn * 0.014,
                   anchor_target=AN["magwell_left"] + Vector((-0.008, -0.008, 0.0)),
                   shoulder=CAM + Vector((0.02, 0.16, -0.3)), pole=(-0.5, 0.0, -1.0),
                   thumb_dirs=((0.0, 0.8, 0.6), (0.05, 0.9, 0.45), (0.05, 1.0, 0.3)))))
