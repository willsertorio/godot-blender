"""Put both HG-7 gloves (blender/glove.blend) on the XM-R4 in blender/xmr4.blend.

    blender -b blender/xmr4.blend -P blender/scripts/pose_glove_xmr4.py

Same method as pose_glove_xm9.py, as one routine used for both hands (`grip`):
  handle frame  u = index -> pinky direction along the handle, s = from the handle centre toward the palm,
                w = where the fingers wrap (right hand: s x u, left hand: u x s); centre + half-sizes measured
                from the rifle mesh inside a box
  hand frame    right: index->pinky = +X, left: index->pinky = -X; fingers +Y; back of the hand +Z (-> s)
  then          knuckle row placed on the palm side near the front edge, every finger joint curls until its
                tip touches the handle, index optionally searched onto the trigger face, thumb laid along a
                line (follow-the-line IK), wrist bent so the forearm drops toward the shooter.
Right hand: pistol grip, index on the trigger, thumb along the lower receiver's left side (by the selector).
Left hand: under the front of the handguard (ahead of the angled foregrip), fingers up the right side, thumb
along the left side. Both gloves are parented to the XMR4 root (they ride the recoil); the reload script keys
the left hand relative to the rifle. Re-running replaces both gloves.
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
K = 0.00082
ORIGIN = (868, 232)
R_FINGER = 0.0095
FINGERS = ["index", "middle", "ring", "pinky"]
CAM = None  # set below: viewmodel camera in the rifle frame (from WeaponHolder's rifle hip offset)


def P(x, y):
    return Vector((0.0, (ORIGIN[0] - x) * K, (ORIGIN[1] - y) * K))


sc = bpy.context.scene
sc.frame_set(1)
O = bpy.data.objects
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
for m in list(bpy.data.materials):
    base = m.name.rsplit(".", 1)[0]
    if base != m.name and bpy.data.materials.get(base):
        m.user_remap(bpy.data.materials[base])
        bpy.data.materials.remove(m)
for n in ("Glove.R", "Glove.L"):
    O[n].location, O[n].rotation_euler = (0, 0, 0), (0, 0, 0)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()


def measure(names, xs, ys, u, s):
    """Handle centre and half-sizes (along s and w) from mesh vertices inside the image-px box xs x ys."""
    y0, y1 = sorted((P(xs[0], 0).y, P(xs[1], 0).y))
    z0, z1 = sorted((P(0, ys[0]).z, P(0, ys[1]).z))
    pts = []
    for name in names:
        ob = O[name].evaluated_get(dg)
        for v in ob.data.vertices:
            p = ob.matrix_world @ v.co
            if y0 <= p.y <= y1 and z0 <= p.z <= z1:
                pts.append(p)
    c = sum(pts, Vector()) / len(pts)
    return c, pts


def grip(rig, right, handle, xs, ys, u, s, u_mid_px, front, trigger_px=None, thumb_line=None, thumb_x=0.0,
         wrist_bend=35, wrist_down=None, roll=0.0):
    u, s = u.normalized(), s.normalized()
    # roll: turn the whole grip around the handle axis (deg), e.g. support palm from straight under to lower-left,
    # so the forearm can leave the wrist in line with the hand instead of snapping the wrist.
    s = (Matrix.Rotation(math.radians(roll), 3, u) @ s).normalized()
    w = s.cross(u) if right else u.cross(s)
    c, pts = measure(handle, xs, ys, u, s)
    es = max((p - c).dot(s) for p in pts)
    ew = max(abs((p - c).dot(w)) for p in pts)
    print(f"{rig.name}: {len(pts)} handle verts, half-sizes {es * 100:.1f} x {ew * 100:.1f} cm")
    pb = rig.pose.bones
    k_mid = rig.data.bones["middle1"].head_local.copy()
    xh = u if right else -u
    rot = Matrix((xh, w, s)).transposed()
    u_mid = (P(*u_mid_px) - c).dot(u)
    k_world = c + u * u_mid + s * (es + 0.017) + w * (ew * front)
    rig.matrix_world = Matrix.Translation(k_world - rot @ k_mid) @ rot.to_4x4()
    bpy.context.view_layer.update()

    def tail_w(bone):
        return rig.matrix_world @ pb[bone].tail

    def rho(p):
        d = p - c
        d = d - u * d.dot(u)
        return math.hypot(d.dot(s) / (es + R_FINGER), d.dot(w) / (ew + R_FINGER))

    for f in (FINGERS[1:] if trigger_px else FINGERS):
        for bone in (f"{f}1", f"{f}2", f"{f}3"):
            b = pb[bone]
            b.rotation_mode = "XYZ"
            best = 0
            for a in range(0, 106, 3):
                b.rotation_euler.x = math.radians(a)
                bpy.context.view_layer.update()
                best = a
                if rho(tail_w(bone)) <= 1.0:
                    break
            b.rotation_euler.x = math.radians(best)
            bpy.context.view_layer.update()
    if trigger_px:
        T = P(*trigger_px)
        best = None
        for j in range(3):
            pb[f"index{j + 1}"].rotation_mode = "XYZ"
        for a1 in range(0, 41, 4):
            for a2 in range(0, 91, 6):
                for a3 in range(0, 61, 10):
                    for j, a in enumerate((a1, a2, a3)):
                        pb[f"index{j + 1}"].rotation_euler.x = math.radians(a)
                    bpy.context.view_layer.update()
                    b = pb["index3"]
                    h, t = rig.matrix_world @ b.head, rig.matrix_world @ b.tail
                    palm = (rig.matrix_world.to_3x3() @ b.matrix.to_3x3()).col[2].normalized()
                    dist = (h.lerp(t, 0.6) + palm * R_FINGER - T).length
                    if best is None or dist < best[0]:
                        best = (dist, (a1, a2, a3))
        for j, a in enumerate(best[1]):
            pb[f"index{j + 1}"].rotation_euler.x = math.radians(a)
        print(f"  index on trigger: {best[1]} deg, pad {best[0] * 100:.1f} cm off")
    if thumb_line:
        ta = P(*thumb_line[0]) + Vector((thumb_x, 0, 0))
        tb = P(*thumb_line[1]) + Vector((thumb_x, 0, 0))
        inv_w = rig.matrix_world.inverted()
        d = (tb - ta).normalized()
        for k in range(1, 4):
            b = pb[f"thumb{k}"]
            head = rig.matrix_world @ b.head
            q = head - ta
            bq = q.dot(d)
            disc = bq * bq - (q.length_squared - b.length ** 2)
            t = bq + math.sqrt(disc) if disc > 0 else bq
            target = ta + d * max(t, 0.0)
            cur = (rig.matrix_world.to_3x3() @ (b.tail - b.head)).normalized()
            r = cur.rotation_difference((target - head).normalized()).to_matrix().to_4x4()
            m_world = rig.matrix_world @ b.matrix
            tr = m_world.translation.copy()
            b.matrix = inv_w @ (Matrix.Translation(tr) @ r @ Matrix.Translation(-tr) @ m_world)
            bpy.context.view_layer.update()
        print(f"  thumb tip {(tail_w('thumb3') - tb).length * 100:.1f} cm from target")
    # Arm: elbow down / out, upper arm toward the player's shoulder (below / outside the camera view).
    side = "R" if right else "L"
    if right:
        lib_arm.solve_arm_aligned(rig, lib_arm.shoulder("rifle", side))
    else:
        lib_arm.solve_arm(rig, lib_arm.shoulder("rifle", side), lib_arm.pole("rifle", side))
    pbw = rig.pose.bones
    fdir = (rig.matrix_world.to_3x3() @ (pbw["forearm"].tail - pbw["forearm"].head)).normalized()
    hdir = (rig.matrix_world.to_3x3() @ (pbw["middle1"].head - pbw["hand"].head)).normalized()
    print(f"  {rig.name}: wrist bend {math.degrees(fdir.angle(hdir)):.0f} deg (roll {roll})")
    mw = rig.matrix_world.copy()
    rig.parent = O["XMR4"]
    rig.matrix_world = mw


CAM = lib_arm.camera_in_gun_frame((0.18, -0.2, -0.44))
GRIP_RAKE = math.atan2(24, 76)       # pistol grip front strap (842,258) -> (866,334)
grip(O["Glove.R"], True, ["PistolGrip"], (835, 930), (250, 330),
     u=Vector((0, -math.sin(GRIP_RAKE), -math.cos(GRIP_RAKE))), s=Vector((1, 0, 0)),
     u_mid_px=(852, 274), front=0.8, trigger_px=(800, 240),
     thumb_line=((890, 206), (812, 200)), thumb_x=-0.025, wrist_bend=35,
     wrist_down=Vector((0.35, 0, -1)), roll=float(os.environ.get("RROLL", 0)))
# Left hand UNDER the handguard (the support hold in the CS references), just ahead of the angled foregrip: palm
# under it, fingers up the far (right) side, thumb along the near (left) side toward the muzzle; the wrist sits
# below-left, so the forearm comes up briefly from the bottom-left of the screen.
GRIP_MODE = os.environ.get("LGRIP", "handguard")
if GRIP_MODE == "foregrip":
    # Left hand on the angled foregrip (it hangs below the handguard, so the hand stays visible below the rifle):
    # knuckles along its slanted front bar, palm on its near (left) side, fingers round the front.
    BAR = Vector((0, -(630 - 470), -(277 - 212)))
    grip(O["Glove.L"], False, ["Foregrip"], (478, 628), (214, 276),
         u=BAR, s=Vector((-1, 0, 0)), u_mid_px=(520, 232), front=0.45,
         thumb_line=((575, 190), (480, 190)), thumb_x=-0.03, roll=float(os.environ.get("ROLL", 0)))
else:
    grip(O["Glove.L"], False, ["Handguard"], (330, 440), (105, 210),
         u=Vector((0, -1, 0)), s=Vector((0, 0, -1)), u_mid_px=(345, 0), front=0.55,
         thumb_line=((390, 150), (300, 150)), thumb_x=-0.036, roll=float(os.environ.get("ROLL", 55)))

sc.frame_set(1)
bpy.ops.wm.save_mainfile()
print("posed gloves in", bpy.data.filepath)
