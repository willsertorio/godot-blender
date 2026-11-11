"""Put both HG-7 gloves (blender/glove.blend) into blender/xm9.blend: right hand gripping the XM9, left parked.

    blender -b blender/xm9.blend -P blender/scripts/pose_glove_xm9.py

Grip frame (XM9 gun frame, Blender axes): u = down the grip (its rake), s = +X (the right side, where the
palm sits), w = s x u (forward, where the fingers wrap). The grip's centre and half-sizes are measured
from the Frame + GripPanel meshes. Hand frame -> grip frame: index->pinky (+X) -> u, fingers (+Y) -> w,
back of the hand (+Z) -> s. The middle knuckle sits just under the trigger guard on the right side, the
heel swings out by YAW, then every finger joint curls (bone X rotation) until its tip touches the grip;
the index rests on the trigger (fixed curl), the thumb curls round the back strap.
The right glove is parented to the XM9 root (it follows the Fire recoil and Reload tilt); the left glove
waits below / left of the gun for the reload. Re-running replaces both gloves.
"""
import math
import os

import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib_arm  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GLOVE = os.path.join(ROOT, "blender", "glove.blend")
K9 = 0.000453
ORIGIN9 = (715, 235)
RAKE = math.atan2(33, 115)
YAW = math.radians(float(os.environ.get("GLOVE_YAW", 0)))
FRONT = float(os.environ.get("GLOVE_FRONT", 0.8))
FINGERS = ["index", "middle", "ring", "pinky"]
R_FINGER = 0.0095
TRIGGER_PX = (600, 205)     # index fingertip pad goes here (front face of the trigger)
THUMB_LINE = ((762, 182), (676, 177))  # thumb runs along the frame's left side, below the slide (px)
THUMB_X = -0.022                         # left side of the frame + thumb radius
WRIST_BEND = math.radians(35)  # forearm drops back + down from the wrist


def P9(x, y):
    return Vector((0.0, (ORIGIN9[0] - x) * K9, (ORIGIN9[1] - y) * K9))


sc = bpy.context.scene
sc.frame_set(1)
O = bpy.data.objects

# ---- replace any previous gloves ---------------------------------------------------------------------
for n in ("Glove.R", "Glove.L", "GloveMesh.R", "GloveMesh.L"):
    if O.get(n):
        O.remove(O[n])
coll = bpy.data.collections.get("Gloves") or bpy.data.collections.new("Gloves")
if coll.name not in sc.collection.children:
    sc.collection.children.link(coll)
with bpy.data.libraries.load(GLOVE, link=False) as (src, dst):
    dst.objects = [n for n in src.objects if n.startswith(("Glove.", "GloveMesh."))]
for o in dst.objects:
    coll.objects.link(o)
# Use the file's own NeonCyan (and any other same-named material) instead of the appended copies.
for m in list(bpy.data.materials):
    base = m.name.rsplit(".", 1)[0]
    if base != m.name and bpy.data.materials.get(base):
        m.user_remap(bpy.data.materials[base])
        bpy.data.materials.remove(m)
rig_r, rig_l = O["Glove.R"], O["Glove.L"]
for rig in (rig_r, rig_l):
    rig.location = (0, 0, 0)
    rig.rotation_euler = (0, 0, 0)
bpy.context.view_layer.update()

# ---- grip frame from the gun mesh -------------------------------------------------------------------------
dg = bpy.context.evaluated_depsgraph_get()
pts = []
lo_y, hi_y = P9(800, 0).y, P9(650, 0).y
lo_z, hi_z = P9(0, 330).z, P9(0, 250).z
for name in ("Frame", "GripPanel"):
    ob = O[name].evaluated_get(dg)
    for v in ob.data.vertices:
        p = ob.matrix_world @ v.co
        if lo_y <= p.y <= hi_y and lo_z <= p.z <= hi_z:
            pts.append(p)
c = sum(pts, Vector()) / len(pts)
u = Vector((0, -math.sin(RAKE), -math.cos(RAKE)))
s = Vector((1, 0, 0))
w = s.cross(u)
es = max((p - c).dot(s) for p in pts)
ew = max(abs((p - c).dot(w)) for p in pts)
print(f"grip: {len(pts)} verts, half-width {es * 100:.1f} cm, half-depth {ew * 100:.1f} cm")

# ---- place the right hand ---------------------------------------------------------------------------------
pb = rig_r.pose.bones
arm_mw = rig_r.matrix_world
k_mid = rig_r.data.bones["middle1"].head_local.copy()       # middle knuckle, hand frame
rot = Matrix((u, w, s)).transposed()                        # hand X,Y,Z -> u,w,s
rot = Matrix.Rotation(-YAW, 3, u) @ rot                     # heel swings out (+s)
u_mid = (P9(700, 246) - c).dot(u)                           # just under the trigger guard
k_world = c + u * u_mid + s * (es + 0.017) + w * (ew * FRONT)
rig_r.matrix_world = Matrix.Translation(k_world - rot @ k_mid) @ rot.to_4x4()
bpy.context.view_layer.update()


def tail_world(bone):
    return rig_r.matrix_world @ pb[bone].tail


def rho(p):
    d = p - c
    d = d - u * d.dot(u)
    return math.hypot(d.dot(s) / (es + R_FINGER), d.dot(w) / (ew + R_FINGER))


def curl(chain, max_deg):
    for bone in chain:
        b = pb[bone]
        b.rotation_mode = "XYZ"
        best = 0
        for a in range(0, max_deg + 1, 3):
            b.rotation_euler.x = math.radians(a)
            bpy.context.view_layer.update()
            best = a
            if rho(tail_world(bone)) <= 1.0:
                break
        b.rotation_euler.x = math.radians(best)
        bpy.context.view_layer.update()
        print(f"  {bone}: {best} deg")


for f in FINGERS[1:]:
    curl([f"{f}1", f"{f}2", f"{f}3"], 105)
# Index: search its three joints for the pose that puts the fingertip pad on the trigger face.
T = P9(*TRIGGER_PX)
for j in range(3):
    pb[f"index{j + 1}"].rotation_mode = "XYZ"


def pad():
    b = pb["index3"]
    h, t = rig_r.matrix_world @ b.head, rig_r.matrix_world @ b.tail
    palm = (rig_r.matrix_world.to_3x3() @ b.matrix.to_3x3()).col[2].normalized()   # bone Z = palm side
    return h.lerp(t, 0.6) + palm * R_FINGER


best = None
for a1 in range(0, 41, 4):
    for a2 in range(0, 91, 6):
        for a3 in range(0, 61, 10):
            for j, a in enumerate((a1, a2, a3)):
                pb[f"index{j + 1}"].rotation_euler.x = math.radians(a)
            bpy.context.view_layer.update()
            dist = (pad() - T).length
            if best is None or dist < best[0]:
                best = (dist, (a1, a2, a3))
for j, a in enumerate(best[1]):
    pb[f"index{j + 1}"].rotation_euler.x = math.radians(a)
print(f"  index on trigger: {best[1]} deg, pad {best[0] * 100:.1f} cm from the trigger")
# Thumb: aim each segment along a line on the frame's left side, below the slide (simple follow-the-line IK):
# segment k points at the spot on the line one segment-length away from its head.
ta = P9(*THUMB_LINE[0]) + Vector((THUMB_X, 0, 0))
tb = P9(*THUMB_LINE[1]) + Vector((THUMB_X, 0, 0))
inv_w = rig_r.matrix_world.inverted()
for k in range(1, 4):
    b = pb[f"thumb{k}"]
    head = rig_r.matrix_world @ b.head
    length = b.length
    d = (tb - ta).normalized()
    # point on the line at distance `length` from head (forward root of |ta + d t - head| = length)
    q = head - ta
    bq = q.dot(d)
    disc = bq * bq - (q.length_squared - length * length)
    t = bq + math.sqrt(disc) if disc > 0 else bq
    target = ta + d * max(t, 0.0)
    cur = (rig_r.matrix_world.to_3x3() @ (b.tail - b.head)).normalized()
    want = (target - head).normalized()
    r = cur.rotation_difference(want).to_matrix().to_4x4()
    m_world = rig_r.matrix_world @ b.matrix
    tr = m_world.translation.copy()
    b.matrix = inv_w @ (Matrix.Translation(tr) @ r @ Matrix.Translation(-tr) @ m_world)
    bpy.context.view_layer.update()
print(f"  thumb: tip {(tail_world('thumb3') - tb).length * 100:.1f} cm from target, "
      f"{min((tail_world('thumb3') - ta).length, 1) * 100:.1f} cm from the line start")

# Arm: elbow down / out, upper arm toward the player's right shoulder (below / right of the camera).
CAM = lib_arm.camera_in_gun_frame((0.16, -0.15, -0.4))   # WeaponHolder pistol hip
lib_arm.solve_arm(rig_r, CAM + lib_arm.SHOULDER_R, lib_arm.POLE_R)

# Parent to the gun root so recoil / reload move the hand with the gun.
mw = rig_r.matrix_world.copy()
rig_r.parent = O["XM9"]
rig_r.matrix_world = mw

# ---- park the left hand below / left of the gun, relaxed ----------------------------------------------------
rig_l.matrix_world = (Matrix.Translation((-0.11, -0.06, -0.2)) @ Matrix.Rotation(math.radians(60), 4, "X")
                      @ Matrix.Rotation(math.radians(-20), 4, "Y"))
for b in rig_l.pose.bones:
    b.rotation_mode = "XYZ"
    if b.name[-1] in "123":
        b.rotation_euler.x = math.radians(15 if b.name.startswith("thumb") else 25)
bpy.context.view_layer.update()
lib_arm.solve_arm(rig_l, CAM + lib_arm.SHOULDER_L, lib_arm.POLE_L)

sc.frame_set(1)
bpy.ops.wm.save_mainfile()
print("posed gloves in", bpy.data.filepath)
