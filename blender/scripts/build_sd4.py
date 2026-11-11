"""SD-4 spider drone, modelled + rigged from scratch after blender/reference/spider_concept.png -> blender/sd4.blend.

    blender -b -P blender/scripts/build_sd4.py

Traced from the concept's side view (body, cannon, leg shape) and front view (body width, lenses, legs).
Scale: 3.3 mm per image pixel (feet to top of the cannon 272 px -> 0.90 m; 510 px across the feet -> 1.6 m
with the legs at their walking yaw).
Frame: origin on the floor under the body centre, Z up, optics facing +Y (robot's left = -X).
Side view px -> Y = (860 - x) * K, Z = (400 - y) * K;  front view px -> X = (300 - x) * K, Z = (400 - y) * K.

Parts (one mesh "SD4Mesh", rigid skinning: every part 100 % to one bone, so plates never bend):
  Carapace (side profile intersected with front profile, bevelled; side window recesses)  -> body
  Undercarriage + 4 drive rollers                                                         -> body
  SensoryOptics: 4 lens housings + NeonOrange cores                                       -> body
  Under-body guns (twin 3-barrel guns, front, under the body)                              -> gun_L / gun_R
  TopCannon: neck (yaw), pivot + housing (pitch), barrel with collar + muzzle brake        -> turret_yaw / cannon_pitch / barrel
  6 legs (L1 L2 L3 = left front / middle / rear, R1..R3): hip mount, hip disc, thigh + plate,
  knee disc, long shin + plate, ankle disc, foot claw + grip tread                           -> <leg>_hip/_thigh/_shin/_foot
  Muzzle flashes (scale 0 except while firing)                                             -> flash_main / flash_L / flash_R
Rig "SD4Rig": root -> body -> {turret_yaw -> cannon_pitch -> barrel -> flash_main, gun_L -> flash_L,
  gun_R -> flash_R, <leg>_hip -> _thigh -> _shin -> _foot}. Leg bones are rolled so their X axis is the
  knee axis (across the leg plane); turret_yaw points up (yaw = rotation about its Y); cannon_pitch: +X lifts.
Empties (bone-parented): Muzzle (cannon tip), Muzzle_L / Muzzle_R (under guns), Eye (between the lenses).
Materials: SpiderArmor, SpiderPlate, SpiderDark, SpiderJoint, SpiderTread, NeonOrange (#FF7A1A), MuzzleFlash.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "blender", "sd4.blend")
REF = os.path.join(ROOT, "blender", "reference", "spider_concept.png")
K = 0.0033

MATS = {
    "SpiderArmor": dict(color=(0.40, 0.40, 0.35), metallic=0.3, rough=0.55),
    "SpiderPlate": dict(color=(0.55, 0.55, 0.48), metallic=0.3, rough=0.5),
    "SpiderDark": dict(color=(0.07, 0.07, 0.075), metallic=0.4, rough=0.55),
    "SpiderJoint": dict(color=(0.20, 0.20, 0.21), metallic=0.8, rough=0.35),
    "SpiderTread": dict(color=(0.04, 0.04, 0.045), metallic=0.0, rough=0.9),
    "NeonOrange": dict(color=(1.0, 0x7A / 255, 0x1A / 255), emit=4.0),
    "MuzzleFlash": dict(color=(1.0, 0.75, 0.35), emit=25.0),
}

# Legs: hip (x, y) on the body side, yaw of the leg plane from the lateral axis (+ = forward).
HIP_X, HIP_Z = 0.29, 0.45
LEGS = {"1": (0.30, 45.0), "2": (0.0, 0.0), "3": (-0.33, -45.0)}
# Leg geometry in the leg plane (r outward, z up) relative to the hip.
KNEE = (0.10, 0.17)
ANKLE = (0.40, -0.27)
TIP = (0.47, -0.45)            # foot tip on the floor (hip is 0.45 up)


def SP(x, y):
    return Vector((0.0, (860 - x) * K, (400 - y) * K))


def FP(x, y):
    return Vector(((300 - x) * K, 0.0, (400 - y) * K))


def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    s = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    if "emit" in s:
        b.inputs["Base Color"].default_value = (0, 0, 0, 1)
        b.inputs["Emission Color"].default_value = (*s["color"], 1)
        b.inputs["Emission Strength"].default_value = s["emit"]
    else:
        b.inputs["Base Color"].default_value = (*s["color"], 1)
        b.inputs["Metallic"].default_value = s["metallic"]
        b.inputs["Roughness"].default_value = s["rough"]
    m.diffuse_color = (*s["color"], 1)
    return m


PARTS = []   # (object, bone)


def apply_mods(ob):
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def make(name, bm, material, bone, bevel=0.0, segs=2, limit="ANGLE", keep=False):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat(material))
    if bevel > 0:
        bv = ob.modifiers.new("Bevel", "BEVEL")
        bv.width = bevel
        bv.segments = segs
        bv.limit_method = limit
        bv.angle_limit = math.radians(35)
        bv.harden_normals = True
    apply_mods(ob)
    for p in me.polygons:
        p.use_smooth = True
    if not keep:
        PARTS.append((ob, bone))
    return ob


def prism(name, pts, origin, a, b, n, width, material, bone, bevel=0.004, segs=2, keep=False, offset=0.0):
    """Polygon (u, v) in the plane origin + a*u + b*v, extruded along n by width (centred, + offset)."""
    bm = bmesh.new()
    base = origin + n * (offset - width / 2)
    f = bm.faces.new([bm.verts.new(base + a * u + b * v) for u, v in pts])
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=n * width, verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
    return make(name, bm, material, bone, bevel, segs, keep=keep)


def cyl(name, p0, p1, r, material, bone, segs=20, bevel=0.003, r2=None, keep=False):
    bm = bmesh.new()
    d = p1 - p0
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2,
                          depth=d.length, matrix=Matrix.Translation((p0 + p1) / 2) @ rot)
    return make(name, bm, material, bone, bevel, 2, keep=keep)


def rbox(name, p0, p1, width, depth, n, material, bone, round_=0.3, offset=Vector()):
    """Rounded box from p0 to p1; `width` in the plane (perpendicular to the segment), `depth` along n."""
    d = (p1 - p0).normalized()
    side = n.cross(d).normalized()
    m = Matrix((side, d, n)).transposed().to_4x4()
    m.translation = (p0 + p1) / 2 + offset
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=m @ Matrix.Diagonal((width, (p1 - p0).length, depth, 1)))
    return make(name, bm, material, bone, bevel=min(width, depth) * round_, segs=3, limit="NONE")


def side_prism(name, pts, width, material, bone, bevel=0.004, keep=False, x0=0.0):
    return prism(name, [((860 - x) * K, (400 - y) * K) for x, y in pts], Vector((x0, 0, 0)),
                 Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((1, 0, 0)), width, material, bone, bevel, keep=keep)


def cut(target, cutter, op="DIFFERENCE"):
    bo = target.modifiers.new("Bool", "BOOLEAN")
    bo.object = cutter
    bo.operation = op
    bo.solver = "EXACT"
    apply_mods(target)
    bpy.data.objects.remove(cutter)


def build_body():
    # Carapace: side profile ∩ front profile, then bevel.
    side = side_prism("CarapaceSide", [(755, 238), (790, 215), (860, 193), (975, 196), (1052, 212), (1050, 236),
                                       (1005, 242), (1000, 282), (955, 298), (805, 298), (760, 282)],
                      1.2, "SpiderArmor", "body", bevel=0, keep=True)
    front = prism("CarapaceFront", [((300 - x) * K, (400 - y) * K) for x, y in
                                    [(240, 195), (360, 195), (395, 240), (395, 300), (378, 340), (222, 340), (205, 300),
                                     (205, 240)]],
                  Vector(), Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, 1, 0)), 2.0, "SpiderArmor", "body",
                  bevel=0, keep=True)
    cut(side, front, "INTERSECT")
    side.name = "Carapace"
    bv = side.modifiers.new("Bevel", "BEVEL")
    bv.width, bv.segments, bv.limit_method = 0.012, 3, "ANGLE"
    bv.angle_limit = math.radians(30)
    apply_mods(side)
    for sx in (-1, 1):   # side window recesses
        win = side_prism("Win", [(905, 207), (990, 205), (995, 232), (910, 236)], 0.06, "SpiderDark", "body",
                         bevel=0, keep=True, x0=sx * 0.31)
        cut(side, win)
        side_prism(f"WinGlass{'LR'[sx > 0]}", [(908, 210), (988, 208), (992, 230), (912, 233)], 0.004, "SpiderDark",
                   "body", bevel=0, x0=sx * 0.287)
    for p in side.data.polygons:
        p.use_smooth = True
    PARTS.append((side, "body"))
    # Top plate along the spine and a front brow plate.
    side_prism("SpinePlate", [(800, 212), (860, 196), (970, 198), (1040, 213), (1040, 222), (970, 207), (860, 205),
                              (805, 220)], 0.24, "SpiderPlate", "body", bevel=0.006)
    # Undercarriage + rollers.
    rbox("Undercarriage", SP(790, 314), SP(1000, 314), 0.14, 0.44, Vector((1, 0, 0)), "SpiderDark", "body",
         round_=0.25)
    for sx in (-1, 1):
        for y in (805, 945):
            c = SP(y, 308) + Vector((sx * 0.255, 0, 0))
            cyl(f"Roller{y}{'LR'[sx > 0]}", c - Vector((0.03, 0, 0)), c + Vector((0.03, 0, 0)), 0.075, "SpiderJoint",
                "body", segs=24)
            cyl(f"RollerHub{y}{'LR'[sx > 0]}", c - Vector((0.034, 0, 0)), c + Vector((0.034, 0, 0)), 0.035,
                "SpiderDark", "body", segs=16)
    # Sensory optics: 4 lenses on the face (front view), housings dark, cores NeonOrange.
    for x, y, r in ((257, 265, 0.036), (285, 272, 0.03), (327, 272, 0.03), (355, 265, 0.036)):
        xx = (306 - x) * K
        z = (400 - y) * K
        y0 = 0.325
        cyl(f"LensHousing{x}", Vector((xx, y0, z)), Vector((xx, y0 + 0.035, z)), r * 1.35, "SpiderDark", "body", segs=20)
        cyl(f"Lens{x}", Vector((xx, y0 + 0.03, z)), Vector((xx, y0 + 0.045, z)), r, "NeonOrange", "body", segs=20,
            bevel=0.002)
    # Visor slot above the lenses.
    prism("Visor", [(-0.07, 0.465), (0.07, 0.465), (0.06, 0.49), (-0.06, 0.49)], Vector((0, 0.33, 0)),
          Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, 1, 0)), 0.03, "NeonOrange", "body", bevel=0.002)


def build_guns():
    for sx, bone in ((-1, "gun_L"), (1, "gun_R")):
        x = sx * 0.14
        mount_top, z = Vector((x, 0.22, 0.27)), 0.19
        rbox(f"GunMount{bone}", mount_top, Vector((x, 0.22, z)), 0.06, 0.06, Vector((0, 1, 0)), "SpiderDark", bone)
        cyl(f"GunBody{bone}", Vector((x, 0.16, z)), Vector((x, 0.30, z)), 0.035, "SpiderJoint", bone, segs=16)
        for i in range(3):
            a = 2 * math.pi * i / 3 + math.pi / 2
            off = Vector((math.cos(a) * 0.017, 0, math.sin(a) * 0.017))
            cyl(f"GunBarrel{bone}{i}", Vector((x, 0.29, z)) + off, Vector((x, 0.46, z)) + off, 0.009, "SpiderDark",
                bone, segs=10, bevel=0.001)
        cyl(f"GunRing{bone}", Vector((x, 0.43, z)), Vector((x, 0.445, z)), 0.03, "SpiderJoint", bone, segs=16)


def build_cannon():
    neck = SP(955, 0)
    cyl("CannonNeck", Vector((0, neck.y, (400 - 202) * K)), Vector((0, neck.y, (400 - 180) * K)), 0.08, "SpiderJoint",
        "turret_yaw", segs=24)
    rbox("CannonYoke", Vector((0, neck.y, (400 - 182) * K)), Vector((0, neck.y, (400 - 158) * K)), 0.06, 0.2,
         Vector((1, 0, 0)), "SpiderDark", "turret_yaw", round_=0.2)
    p = SP(955, 165)
    cyl("CannonPivot", p - Vector((0.105, 0, 0)), p + Vector((0.105, 0, 0)), 0.045, "SpiderJoint", "cannon_pitch", segs=20)
    side_prism("CannonHousing", [(878, 128), (1012, 130), (1027, 140), (1027, 172), (1005, 180), (882, 180), (870, 168),
                                 (870, 140)], 0.15, "SpiderArmor", "cannon_pitch", bevel=0.008)
    side_prism("CannonSlot", [(896, 148), (940, 148), (940, 158), (896, 158)], 0.154, "SpiderDark", "cannon_pitch",
               bevel=0)
    side_prism("CannonLight", [(880, 123), (906, 123), (906, 130), (880, 130)], 0.05, "NeonOrange", "cannon_pitch",
               bevel=0.002)
    side_prism("CannonVent", [(1000, 136), (1022, 138), (1022, 150), (1000, 150)], 0.156, "SpiderDark",
               "cannon_pitch", bevel=0)
    a, b = SP(878, 153), SP(682, 153)
    cyl("CannonBarrel", a, b, 0.021, "SpiderDark", "barrel", segs=18)
    cyl("CannonCollar", SP(770, 153), SP(758, 153), 0.027, "SpiderJoint", "barrel", segs=18)
    cyl("CannonBrake", SP(682, 153), SP(648, 153), 0.03, "SpiderJoint", "barrel", segs=18)
    cyl("CannonBore", SP(649, 153), SP(646, 153), 0.017, "SpiderTread", "barrel", segs=14, bevel=0)


def leg_frame(side, key):
    hy, yaw = LEGS[key]
    yaw = math.radians(yaw)
    d = Vector((side * math.cos(yaw), math.sin(yaw), 0)).normalized()
    hip = Vector((side * HIP_X, hy, HIP_Z))
    n = d.cross(Vector((0, 0, 1)))
    return hip, d, n


def build_leg(side, key):
    name = f"{'L' if side < 0 else 'R'}{key}"
    hip, d, n = leg_frame(side, key)
    Z = Vector((0, 0, 1))

    def L(r, z):
        return hip + d * r + Z * z

    knee, ankle, tip = L(*KNEE), L(*ANKLE), L(*TIP)
    cyl(f"{name}HipMount", L(-0.05, 0), L(0.03, 0), 0.05, "SpiderJoint", f"{name}_hip", segs=18)
    cyl(f"{name}HipDisc", hip - n * 0.065, hip + n * 0.065, 0.058, "SpiderDark", f"{name}_thigh", segs=20)
    rbox(f"{name}Thigh", hip, knee, 0.10, 0.09, n, "SpiderArmor", f"{name}_thigh")
    rbox(f"{name}ThighPlate", hip.lerp(knee, 0.15), knee.lerp(hip, 0.1), 0.115, 0.1, n, "SpiderPlate", f"{name}_thigh",
         offset=n * 0.0)
    cyl(f"{name}KneeDisc", knee - n * 0.06, knee + n * 0.06, 0.055, "SpiderJoint", f"{name}_shin", segs=20)
    rbox(f"{name}Shin", knee, ankle, 0.115, 0.085, n, "SpiderArmor", f"{name}_shin")
    # Armour plate on the outer/upper face of the shin.
    up = (ankle - knee).normalized().cross(n).normalized()
    if up.z < 0:
        up = -up
    rbox(f"{name}ShinPlate", knee.lerp(ankle, 0.1), knee.lerp(ankle, 0.85), 0.1, 0.03, up.cross(
        (ankle - knee).normalized()).normalized(), "SpiderPlate", f"{name}_shin", offset=up * 0.06)
    cyl(f"{name}AnkleDisc", ankle - n * 0.05, ankle + n * 0.05, 0.042, "SpiderJoint", f"{name}_foot", segs=18)
    # Foot claw + grip tread (plane coords relative to the ankle).
    claw = [(-0.04, 0.035), (0.045, 0.035), (0.09, -0.11), (0.085, -0.18), (0.025, -0.18), (0.01, -0.08)]
    prism(f"{name}Claw", claw, ankle, d, Z, n, 0.08, "SpiderArmor", f"{name}_foot", bevel=0.006)
    prism(f"{name}Tread", [(0.06, -0.09), (0.093, -0.115), (0.088, -0.18), (0.045, -0.18)], ankle, d, Z, n, 0.086,
          "SpiderTread", f"{name}_foot", bevel=0.003)
    return {f"{name}_hip": (hip, L(0.05, 0), n.cross(d)), f"{name}_thigh": (hip, knee, n.cross((knee - hip).normalized())),
            f"{name}_shin": (knee, ankle, n.cross((ankle - knee).normalized())),
            f"{name}_foot": (ankle, tip, n.cross((tip - ankle).normalized()))}, n


def flash_mesh(name, origin, fwd, scale, bone):
    """Muzzle flash: cone + crossed star planes along `fwd` (built at full size, keyed to scale 0 in the clips)."""
    bm = bmesh.new()
    rot = Vector((0, 1, 0)).rotation_difference(fwd).to_matrix().to_4x4()
    m = Matrix.Translation(origin) @ rot @ Matrix.Scale(scale, 4)
    bmesh.ops.create_cone(bm, cap_ends=False, segments=10, radius1=0.012, radius2=0.002, depth=0.05,
                          matrix=m @ Matrix.Translation((0, 0.025, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    for a in (0, math.pi / 2, math.pi / 4, -math.pi / 4):
        r = Matrix.Rotation(a, 4, "Y")
        pts = []
        for i in range(10):
            ang = i * math.pi / 5
            rad = 0.03 if i % 2 == 0 else 0.008
            pts.append(m @ r @ Vector((math.cos(ang) * rad * 0.5, 0.006, math.sin(ang) * rad)))
        bm.faces.new([bm.verts.new(p) for p in pts])
    return make(name, bm, "MuzzleFlash", bone)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.render.fps = 30
    build_body()
    build_guns()
    build_cannon()
    leg_bones = {}
    for side in (-1, 1):
        for key in LEGS:
            bones, _ = build_leg(side, key)
            leg_bones.update(bones)
    muzzle = SP(646, 153)
    flash_mesh("FlashMain", muzzle, Vector((0, 1, 0)), 4.5, "flash_main")
    for sx, bone in ((-1, "flash_L"), (1, "flash_R")):
        flash_mesh(f"Flash{bone}", Vector((sx * 0.14, 0.46, 0.19)), Vector((0, 1, 0)), 2.8, bone)

    # ---- rig -------------------------------------------------------------------------------------------
    arm = bpy.data.armatures.new("SD4Rig")
    rig = bpy.data.objects.new("SD4Rig", arm)
    sc.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}

    def bone(name, head, tail, roll_to, parent=None):
        b = arm.edit_bones.new(name)
        b.head, b.tail = head, tail
        b.align_roll(roll_to)
        if parent:
            b.parent = eb[parent]
        eb[name] = b

    X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
    bone("root", Vector((0, 0, 0)), Vector((0, 0.3, 0)), Z)
    bone("body", Vector((0, 0, HIP_Z)), Vector((0, 0.3, HIP_Z)), Z, "root")
    neck = SP(955, 0)
    bone("turret_yaw", Vector((0, neck.y, (400 - 200) * K)), Vector((0, neck.y, (400 - 170) * K)), -Y, "body")
    piv = SP(955, 165)
    bone("cannon_pitch", piv, piv + Vector((0, 0.1, 0)), Z, "turret_yaw")
    bone("barrel", SP(878, 153), SP(878, 153) + Vector((0, 0.1, 0)), Z, "cannon_pitch")
    mz = SP(646, 153)
    bone("flash_main", mz, mz + Vector((0, 0.05, 0)), Z, "barrel")
    for sx, g, f in ((-1, "gun_L", "flash_L"), (1, "gun_R", "flash_R")):
        bone(g, Vector((sx * 0.14, 0.22, 0.19)), Vector((sx * 0.14, 0.32, 0.19)), Z, "body")
        bone(f, Vector((sx * 0.14, 0.46, 0.19)), Vector((sx * 0.14, 0.51, 0.19)), Z, g)
    for side in (-1, 1):
        for key in LEGS:
            nm = f"{'L' if side < 0 else 'R'}{key}"
            for part, parent in (("hip", "body"), ("thigh", f"{nm}_hip"), ("shin", f"{nm}_thigh"), ("foot", f"{nm}_shin")):
                h, t, roll = leg_bones[f"{nm}_{part}"]
                bone(f"{nm}_{part}", h, t, roll, parent)
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.display_type = "STICK"
    rig.show_in_front = True

    for p, b in PARTS:
        vg = p.vertex_groups.new(name=b)
        vg.add(list(range(len(p.data.vertices))), 1.0, "REPLACE")
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for p, _ in PARTS:
        p.select_set(True)
    body = PARTS[0][0]
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = body.data.name = "SD4Mesh"
    body.parent = rig
    body.modifiers.new("Armature", "ARMATURE").object = rig
    wn = body.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    wn.keep_sharp = True

    # Bone-parented empties.
    bpy.context.view_layer.update()
    for name, bname, loc in (("Muzzle", "barrel", SP(646, 153)), ("Muzzle_L", "gun_L", Vector((-0.14, 0.46, 0.19))),
                             ("Muzzle_R", "gun_R", Vector((0.14, 0.46, 0.19))), ("Eye", "body", Vector((0, 0.37, 0.44)))):
        e = bpy.data.objects.new(name, None)
        e.empty_display_size = 0.04
        e.empty_display_type = "ARROWS"
        sc.collection.objects.link(e)
        e.parent = rig
        e.parent_type = "BONE"
        e.parent_bone = bname
        bpy.context.view_layer.update()
        e.matrix_world = Matrix.Translation(loc)

    # Review setup: reference image behind the side view (robot's left, -X), light, world.
    img = bpy.data.images.load(REF)
    ref = bpy.data.objects.new("Reference", None)
    ref.empty_display_type = "IMAGE"
    ref.data = img
    w = img.size[0] * K
    ref.empty_display_size = w
    ref.empty_image_offset = (-0.5, -0.5)
    ref.rotation_euler = (math.radians(90), 0, math.radians(-90))
    ref.location = Vector((0.8, (860 - img.size[0] / 2) * K, (400 - img.size[1] / 2) * K))
    ref.color[3] = 0.5
    rc = bpy.data.collections.new("Reference")
    sc.collection.children.link(rc)
    rc.objects.link(ref)
    rc.hide_render = True
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), math.radians(15), math.radians(-35))
    sc.collection.objects.link(sun)
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.4, 0.42, 0.46, 1)
    sc.world = world
    # Hide the flashes in the rest pose (the clips key their scale).
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for b in ("flash_main", "flash_L", "flash_R"):
        rig.pose.bones[b].scale = (0.001, 0.001, 0.001)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    bpy.ops.file.make_paths_relative()     # reference image path relative to the .blend
    bpy.ops.wm.save_mainfile()
    print("saved", OUT, "parts", len(PARTS), "bones", len(arm.bones))


build()
