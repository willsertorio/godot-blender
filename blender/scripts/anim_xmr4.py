"""XM-R4 animations (run after build_xmr4.py and pose_glove_xmr4.py; keeps edits made in the .blend).

    blender -b blender/xmr4.blend -P blender/scripts/anim_xmr4.py

30 fps, one action per object ("<object>_Anim"), timeline markers Fire / Reload. Frame range 1-90.
Fire (f1-24): 3-round burst, shots on f2, f5, f8 (0.1 s, the rifle's fire rate). Trigger held; bolt cycles
  in the ejection port each shot; dust cover flips open on the first; cyan muzzle flash; three casings
  fly out right / up / slightly forward, spinning; recoil kicks back and climbs per shot, settles by f20.
Reload (f31-90), hands on (the left glove is keyed relative to the rifle, it stays parented to it):
  f31-38  rifle cants right (magwell toward the left hand) and lifts; left hand leaves the handguard
  f38-44  left hand grabs the magazine and pulls it out along the magwell axis
  f44-47  carries it down / left and lets go; f47-55 it tumbles away
  f50     hand reaches down (pouch);  f56 back with a fresh magazine
  f56-66  brings it up, inserts and seats it (f66, jolt)
  f69-75  hand to the charging handle, pulls it back 6 cm (f73), lets go: handle + bolt slam forward (f74-75)
  f76-86  rifle returns, left hand back on the handguard (grip pose restored)
In the game the casings become physics objects spawned at Eject and the whole-rifle kick stays procedural.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

FPS, R, G = 30, 30, 9.8
SHOTS = (2, 5, 8)
BOLT_TRAVEL, CH_TRAVEL = 0.03, 0.06
EJECT_V = Vector((1.3, 0.15, 1.2))
SPIN = Vector((10.0, 24.0, 6.0))
K = 0.00082
ORIGIN = (868, 232)

sc = bpy.context.scene
sc.render.fps = FPS
sc.frame_start, sc.frame_end = 1, 90
O = bpy.data.objects


def P(x, y):
    return Vector((0.0, (ORIGIN[0] - x) * K, (ORIGIN[1] - y) * K))


def keys(ob, path, index, frames, interp="BEZIER", easing="AUTO"):
    if ob.animation_data is None:
        ob.animation_data_create()
    if ob.animation_data.action is None:
        ob.animation_data.action = bpy.data.actions.new(f"{ob.name}_Anim")
    fc = ob.animation_data.action.fcurves.find(path, index=index) or ob.animation_data.action.fcurves.new(path, index=index)
    for k in frames:
        kp = fc.keyframe_points.insert(k[0], k[1], options={"FAST"})
        kp.interpolation = k[2] if len(k) > 2 else interp
        kp.easing = k[3] if len(k) > 3 else easing
        if kp.interpolation == "BACK":
            kp.back = 1.3
    fc.update()


def flash_mesh():
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=10, radius1=0.016, radius2=0.003, depth=0.07,
                          matrix=Matrix.Translation((0, 0.035, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    for a in (0, math.pi / 2, math.pi / 4, -math.pi / 4):
        r = Matrix.Rotation(a, 4, "Y")
        pts = [r @ Vector((math.cos(i * math.pi / 5) * (0.04 if i % 2 == 0 else 0.011) * 0.5, 0.008,
                           math.sin(i * math.pi / 5) * (0.04 if i % 2 == 0 else 0.011))) for i in range(10)]
        bm.faces.new([bm.verts.new(p) for p in pts])
    me = bpy.data.meshes.new("MuzzleFlash")
    bm.to_mesh(me)
    bm.free()
    m = bpy.data.materials.get("MuzzleFlash") or bpy.data.materials.new("MuzzleFlash")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (0.55, 0.95, 1.0, 1)
    b.inputs["Emission Strength"].default_value = 25.0
    me.materials.append(m)
    return me


root, trig, bolt, dust, ch, mag = (O[n] for n in ("XMR4", "Trigger", "Bolt", "DustCover", "ChargingHandle", "Magazine"))
hand = O["Glove.L"]
for ob in (root, trig, bolt, dust, ch, mag, hand):
    if ob.animation_data:
        ob.animation_data_clear()
sc.frame_set(1)
t0, b0, d0, c0 = trig.rotation_euler.x, bolt.location.y, dust.rotation_euler.y, ch.location.y
m0 = mag.location.copy()
REST = hand.matrix_basis.copy()
GRIP_POSE = {b.name: tuple(b.rotation_euler) for b in hand.pose.bones if b.name[-1] in "123"}
d = math.radians

# ================================ Fire ==============================================================
keys(trig, "rotation_euler", 0, [(1, t0), (2, t0 + d(-18)), (9, t0 + d(-18)), (11, t0)])
bolt_keys = [(1, b0, "LINEAR")]
for f in SHOTS:
    bolt_keys += [(f, b0, "LINEAR"), (f + 1, b0 - BOLT_TRAVEL, "LINEAR"), (f + 2, b0, "LINEAR")]
keys(bolt, "location", 1, bolt_keys)
keys(dust, "rotation_euler", 1, [(1, d0, "CONSTANT"), (2, d0, "EXPO", "EASE_OUT"), (3, d0 + d(100))])
keys(root, "location", 1, [(1, 0.0), (2, 0.0, "EXPO", "EASE_OUT"), (3, -0.016), (4, -0.008), (5, -0.008, "EXPO", "EASE_OUT"),
                           (6, -0.02), (7, -0.011), (8, -0.011, "EXPO", "EASE_OUT"), (9, -0.022, "BACK", "EASE_OUT"), (18, 0.0)])
keys(root, "rotation_euler", 0, [(1, 0.0), (2, 0.0, "EXPO", "EASE_OUT"), (3, d(3)), (4, d(2.2)), (5, d(2.2), "EXPO", "EASE_OUT"),
                                 (6, d(5)), (7, d(4.2)), (8, d(4.2), "EXPO", "EASE_OUT"), (9, d(7), "BACK", "EASE_OUT"), (20, 0.0)])
keys(root, "rotation_euler", 2, [(1, 0.0), (3, d(0.8)), (6, d(-0.6)), (9, d(0.9)), (20, 0.0)])
flash = O.get("MuzzleFlash") or O.new("MuzzleFlash", flash_mesh())
if flash.name not in root.users_collection[0].objects:
    root.users_collection[0].objects.link(flash)
flash.parent = O["Muzzle"]
flash.location = (0, 0, 0)
if flash.animation_data:
    flash.animation_data_clear()
fk = [(1, 0.0, "CONSTANT")]
for f in SHOTS:
    fk += [(f, 1.0, "CONSTANT"), (f + 1, 0.6, "CONSTANT"), (f + 2, 0.0, "CONSTANT")]
for i in range(3):
    keys(flash, "scale", i, fk)
keys(flash, "rotation_euler", 1, [(f, d(37 * k), "CONSTANT") for k, f in enumerate(SHOTS)])
casing = O["Casing"]
cverts = casing.data.vertices
cc = sum((v.co for v in cverts), Vector()) / len(cverts)
for k, f in enumerate(SHOTS):
    name = f"CasingFX{k}"
    cas = O.get(name) or O.new(name, casing.data)
    if cas.name not in root.users_collection[0].objects:
        root.users_collection[0].objects.link(cas)
    if cas.animation_data:
        cas.animation_data_clear()
    cas.rotation_mode = "XYZ"
    sc.frame_set(f + 1)
    p0 = O["Eject"].matrix_world.translation.copy()
    v = EJECT_V + Vector((0.1 * (k - 1), 0.05 * k, 0.1 * ((k % 2) - 0.5)))
    for i in range(3):
        keys(cas, "scale", i, [(1, 0.0, "CONSTANT"), (f + 1, 1.0, "CONSTANT"), (f + 17, 0.0, "CONSTANT")])
    for fr in range(f + 1, f + 18):
        t = (fr - f - 1) / FPS
        p = p0 + v * t + Vector((0, 0, -0.5 * G * t * t)) - cc
        for i in range(3):
            keys(cas, "location", i, [(fr, p[i], "LINEAR")])
            keys(cas, "rotation_euler", i, [(fr, SPIN[i] * t, "LINEAR")])
    for i in range(3):
        keys(cas, "location", i, [(1, (p0 - cc)[i], "CONSTANT")])

# ================================ Reload: rifle + parts ======================================================
keys(dust, "rotation_euler", 1, [(R + 1, d0 + d(100), "CONSTANT")])
keys(bolt, "location", 1, [(R + 1, b0 - BOLT_TRAVEL, "CONSTANT"), (R + 44, b0 - BOLT_TRAVEL, "EXPO", "EASE_OUT"), (R + 45, b0)])
keys(ch, "location", 1, [(1, c0), (R + 41, c0, "EXPO", "EASE_OUT"), (R + 43, c0 - CH_TRAVEL, "CONSTANT"),
                         (R + 44, c0 - CH_TRAVEL, "EXPO", "EASE_OUT"), (R + 45, c0)])
keys(root, "rotation_euler", 1, [(R + 1, 0.0, "BACK", "EASE_OUT"), (R + 8, d(25)), (R + 46, d(25), "BACK", "EASE_OUT"), (R + 56, 0.0)])
keys(root, "rotation_euler", 0, [(R + 1, 0.0, "BACK", "EASE_OUT"), (R + 8, d(8)), (R + 35, d(8), "EXPO", "EASE_OUT"),
                                 (R + 36, d(11)), (R + 39, d(8)), (R + 44, d(8), "EXPO", "EASE_OUT"), (R + 45, d(11)),
                                 (R + 48, d(8), "BACK", "EASE_OUT"), (R + 56, 0.0)])
keys(root, "rotation_euler", 2, [(R + 1, 0.0, "BACK", "EASE_OUT"), (R + 8, d(-8)), (R + 46, d(-8), "BACK", "EASE_OUT"), (R + 56, 0.0)])
keys(root, "location", 2, [(R + 1, 0.0, "BACK", "EASE_OUT"), (R + 8, 0.025), (R + 35, 0.025, "EXPO", "EASE_OUT"), (R + 36, 0.032),
                           (R + 39, 0.025), (R + 46, 0.025, "BACK", "EASE_OUT"), (R + 56, 0.0)])
keys(root, "location", 0, [(R + 1, 0.0, "BACK", "EASE_OUT"), (R + 8, -0.02), (R + 46, -0.02, "BACK", "EASE_OUT"), (R + 56, 0.0)])
keys(root, "location", 1, [(R + 42, 0.0), (R + 43, -0.01), (R + 45, 0.0)])

# Magazine path (root-local): out along the magwell, carried away, tumbles; fresh one in, seated.
bpy.context.view_layer.update()
dl = (root.matrix_world.inverted() @ O["MagAxis"].matrix_world).to_3x3().col[2].normalized()
LEFT = Vector((-1, 0, 0))
p_out = m0 + dl * 0.14
p_away = p_out + dl * 0.08 + LEFT * 0.12
p_fresh = m0 + dl * 0.24 + LEFT * 0.1
path = [(1, m0, "CONSTANT"), (R + 8, m0, "EXPO", "EASE_OUT"), (R + 14, p_out, "BEZIER"), (R + 17, p_away, "LINEAR")]
for fr in range(R + 18, R + 26):
    t = (fr - R - 17) / FPS
    path.append((fr, p_away + Vector((-0.4 * t, 0, -0.5 * G * t * t)), "LINEAR"))
path[-1] = (path[-1][0], path[-1][1], "CONSTANT")
path += [(R + 26, p_fresh, "BEZIER"), (R + 32, m0 + dl * 0.06, "EXPO", "EASE_OUT"), (R + 36, m0, "CONSTANT")]
for i in range(3):
    keys(mag, "location", i, [(k[0], k[1][i], k[2], *(k[3:] or ["AUTO"])) for k in path])
mag.rotation_mode = "XYZ"
for i, spin in enumerate((4.0, 1.5, 2.5)):
    keys(mag, "rotation_euler", i, [(1, 0.0, "CONSTANT"), (R + 17, 0.0, "LINEAR"), (R + 25, spin, "CONSTANT"), (R + 26, 0.0, "CONSTANT")])

# ================================ Reload: left hand ============================================================
mv = mag.data.vertices
MAG_C = sum((v.co for v in mv), Vector()) / len(mv)          # magazine centre, mag-local
K_MID = hand.data.bones["middle1"].head_local.copy()
PALM = Vector((0.0, 0.045, -0.019))


def mag_hold(f):
    """Left hand on the magazine's left side, fingers round its front (root-local matrix) on frame f."""
    sc.frame_set(f)
    mb = mag.matrix_basis
    u = (mb.to_3x3() @ dl).normalized()
    s = (mb.to_3x3() @ Vector((-1, 0, 0))).normalized()
    w = u.cross(s)
    rot = Matrix((-u, w, s)).transposed()
    k = (mb @ MAG_C) + u * (-0.012) + s * (0.011 + 0.017) + w * 0.02
    return Matrix.Translation(k - rot @ K_MID) @ rot.to_4x4()


def charge(back=0.0, up=0.0):
    """Palm down on the rear of the upper, fingers over to the right hooking the charging handle."""
    rot = Matrix((Vector((0, -1, 0)), Vector((1, 0, 0)), Vector((0, 0, 1)))).transposed()
    target = P(892, 113) + Vector((-0.03, -back, 0.019 + 0.014 + up))
    return Matrix.Translation(target - rot @ PALM) @ rot.to_4x4()


def offset(m, v):
    return Matrix.Translation(v) @ m


hk = {R + 1: REST, R + 5: offset(mag_hold(R + 8), Vector((-0.05, 0, -0.03)))}
for f in range(R + 8, R + 18):
    hk[f] = mag_hold(f)
hk[R + 21] = offset(mag_hold(R + 17), Vector((-0.03, 0.02, -0.12)))
for f in range(R + 26, R + 37):
    hk[f] = mag_hold(f)
hk[R + 37] = offset(mag_hold(R + 36), Vector((-0.02, 0, -0.025)))
hk[R + 39] = charge(up=0.045)
hk[R + 41] = charge()
hk[R + 43] = charge(back=CH_TRAVEL)
hk[R + 45] = charge(back=CH_TRAVEL + 0.02, up=0.04)
hk[R + 50] = offset(REST, Vector((-0.06, 0.0, 0.05)))
hk[R + 56] = REST
hand.rotation_mode = "QUATERNION"
prev = None
for f in sorted(hk):
    loc, q, _ = hk[f].decompose()
    if prev is not None:
        q.make_compatible(prev)
    prev = q
    hand.location, hand.rotation_quaternion = loc, q
    hand.keyframe_insert("location", frame=f)
    hand.keyframe_insert("rotation_quaternion", frame=f)
hand.animation_data.action.name = "Glove.L_Anim"
# Finger curls: grip pose on the handguard, open, holding the magazine, flat, hooking the handle.
CURL = {R + 5: 20, R + 8: 55, R + 17: 55, R + 21: 40, R + 26: 55, R + 36: 55, R + 37: 15, R + 39: 20,
        R + 41: 75, R + 43: 75, R + 45: 25}
for b in hand.pose.bones:
    if b.name not in GRIP_POSE:
        continue
    b.rotation_mode = "XYZ"
    for f in (R + 1, R + 56):
        b.rotation_euler = GRIP_POSE[b.name]
        b.keyframe_insert("rotation_euler", frame=f)
    for f, a in CURL.items():
        thumb = b.name.startswith("thumb")
        b.rotation_euler = (math.radians(a * (0.4 if thumb else 1.0)), 0, 0)
        b.keyframe_insert("rotation_euler", frame=f)


# ---- arm follows the hand: per-frame two-bone solve toward the player's left shoulder (camera-fixed) ----------
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(__file__))
import lib_arm  # noqa: E402
_shoulder = lib_arm.shoulder("rifle", "L")
_pb = hand.pose.bones
for _b in ("upperarm", "forearm", "hand"):
    _pb[_b].rotation_mode = "QUATERNION"
for _f in range(R + 1, R + 56 + 1):
    sc.frame_set(_f)
    lib_arm.solve_arm(hand, _shoulder, lib_arm.pole("rifle", "L"))
    for _b in ("upperarm", "forearm", "hand"):
        _pb[_b].keyframe_insert("rotation_quaternion", frame=_f)
        _pb[_b].keyframe_insert("location", frame=_f)

for name, f in (("Fire", 1), ("Reload", R + 1)):
    mk = sc.timeline_markers.get(name) or sc.timeline_markers.new(name, frame=f)
    mk.frame = f
sc.frame_set(1)
bpy.ops.wm.save_mainfile()
print("animated", bpy.data.filepath, sc.frame_start, "-", sc.frame_end)
