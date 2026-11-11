"""Left-hand reload on the XM9 (run after anim_xm9.py and pose_glove_xm9.py; keeps edits made in the .blend).

    blender -b blender/xm9.blend -P blender/scripts/anim_xm9_hands.py

Reload frames 31-72 (see anim_xm9.py). The left glove is free (not parented): every key is computed from
where the gun / magazine / slide actually are on that frame, so the hand stays on them while the gun tilts.
  f31        parked below / left (out of view)
  f40        drops below the grip, palm up, as the old magazine falls
  f45-52     palm under the fresh magazine's base plate, carries it up into the grip; f52 slap (fingers flat)
  f53-56     up and over the slide: palm on the rear of the slide, fingers wrap the right side
  f57-59     tugs back 1 cm, lets go as the slide slams forward, lifts away
  f62        up and out to the left, clear of the gun;  f62-68 drops back to parked
Hand frame (glove.blend): fingers +Y, back of the hand +Z, palm -Z, left thumb +X; palm centre (0, 4.5 cm, -1.9 cm).
"""
import math

import bpy
from mathutils import Matrix, Vector

R = 30
K9 = 0.000453
ORIGIN9 = (715, 235)
RAKE = math.atan2(33, 115)
PALM = Vector((0.0, 0.045, -0.019))


def P9(x, y):
    return Vector((0.0, (ORIGIN9[0] - x) * K9, (ORIGIN9[1] - y) * K9))


sc = bpy.context.scene
O = bpy.data.objects
root, mag, base, slide, rig = O["XM9"], O["Magazine"], O["MagBase"], O["Slide"], O["Glove.L"]

# Rest measurements (frame 1): magazine base-plate bottom and slide-top point, in their own local frames.
sc.frame_set(1)
parked = rig.matrix_world.copy() if rig.animation_data is None else None
if rig.animation_data:
    rig.animation_data_clear()
    sc.frame_set(1)
if parked is None:
    parked = rig.matrix_world.copy()
drop_w = (O["MagAxis"].matrix_world.to_3x3().col[2]).normalized()
dg = bpy.context.evaluated_depsgraph_get()
be = base.evaluated_get(dg)
bv = [be.matrix_world @ v.co for v in be.data.vertices]
bc = sum(bv, Vector()) / len(bv)
bottom_w = bc + drop_w * max((v - bc).dot(drop_w) for v in bv)
bottom_l = mag.matrix_world.inverted() @ bottom_w
drop_l = (mag.matrix_world.to_3x3().inverted() @ drop_w).normalized()
top_l = slide.matrix_world.inverted() @ P9(722, 92)
W_GUN = Vector((0, math.cos(RAKE), -math.sin(RAKE)))   # forward, square to the grip


def frame_hand(x, y, z, target):
    """Hand matrix whose palm centre sits at `target`, with hand axes (fingers=y, back=z) given."""
    y = y.normalized()
    z = (z - y * z.dot(y)).normalized()
    xr = y.cross(z)
    rot = Matrix((xr, y, z)).transposed()
    return Matrix.Translation(target - rot @ PALM) @ rot.to_4x4()


def under_mag(f, extra=0.0):
    """Palm up under the magazine's base plate on frame f (extra: further down the grip axis)."""
    sc.frame_set(f)
    mw = mag.matrix_world
    d = (mw.to_3x3() @ drop_l).normalized()
    target = mw @ bottom_l + d * (0.003 + extra)
    return frame_hand(None, root.matrix_world.to_3x3() @ W_GUN, d, target)


def over_slide(f, back=0.0, up=0.0, left=0.0):
    """Palm down on the rear of the slide, fingers over the right side (thumb toward the shooter)."""
    sc.frame_set(f)
    g = root.matrix_world.to_3x3()
    top = slide.matrix_world @ top_l
    target = top + g @ Vector((-0.03 - left, -back, up))
    return frame_hand(None, g @ Vector((1, 0, 0)), g @ Vector((0, 0, 1)), target)


keys = {R + 1: parked, R + 10: under_mag(R + 15, 0.07)}
for f in range(R + 15, R + 23):
    keys[f] = under_mag(f)
keys[R + 23] = under_mag(R + 22, 0.03)
keys[R + 25] = over_slide(R + 25, up=0.04)
keys[R + 26] = over_slide(R + 26)
keys[R + 27] = over_slide(R + 27, back=0.01)
keys[R + 29] = over_slide(R + 27, back=0.025, up=0.035)
keys[R + 32] = over_slide(R + 32, back=0.05, up=0.05, left=0.1)   # clear of the gun before dropping away
keys[R + 38] = parked

rig.rotation_mode = "QUATERNION"
prev = None
for f in sorted(keys):
    sc.frame_set(f)
    loc, q, _ = keys[f].decompose()
    if prev is not None:
        q.make_compatible(prev)
    prev = q
    rig.location, rig.rotation_quaternion = loc, q
    rig.keyframe_insert("location", frame=f)
    rig.keyframe_insert("rotation_quaternion", frame=f)
act = rig.animation_data.action
act.name = "Glove.L_Anim"

# Finger curls (deg, bone X) per key: relaxed, open for the magazine, flat slap, wrap the slide.
CURL = {R + 1: (25, 15), R + 10: (35, 15), R + 15: (30, 20), R + 21: (30, 20), R + 22: (12, 10),
        R + 25: (20, 10), R + 26: (70, 25), R + 27: (75, 25), R + 29: (30, 15), R + 32: (25, 15), R + 38: (25, 15)}
for b in rig.pose.bones:
    if b.name[-1] not in "123":
        continue
    b.rotation_mode = "XYZ"
    thumb = b.name.startswith("thumb")
    for f, (fc, tc) in CURL.items():
        a = tc if thumb else fc * (0.8 if b.name.endswith("1") else 1.0)
        b.rotation_euler.x = math.radians(a)
        b.keyframe_insert("rotation_euler", index=0, frame=f)


# ---- arm follows the hand: per-frame two-bone solve toward the player's left shoulder (camera-fixed) ----------
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(__file__))
import lib_arm  # noqa: E402
_shoulder = lib_arm.shoulder("pistol", "L")
_pb = rig.pose.bones
for _b in ("upperarm", "forearm", "hand"):
    _pb[_b].rotation_mode = "QUATERNION"
for _f in range(R + 1, R + 38 + 1):
    sc.frame_set(_f)
    lib_arm.solve_arm(rig, _shoulder, lib_arm.pole("pistol", "L"))
    for _b in ("upperarm", "forearm", "hand"):
        _pb[_b].keyframe_insert("rotation_quaternion", frame=_f)
        _pb[_b].keyframe_insert("location", frame=_f)

sc.frame_set(1)
bpy.ops.wm.save_mainfile()
print("left-hand reload keyed:", len(keys), "hand keys")
