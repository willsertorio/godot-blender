"""Two-bone arm solve for the HG-7 glove rig (upperarm -> forearm -> hand), shared by the pose / anim scripts.

solve_arm(rig, shoulder, pole): keeps the hand bone exactly where it is, puts the elbow on the circle where
the forearm (wrist -> elbow) and upper arm (elbow -> shoulder) meet, on the `pole` side (world direction the
elbow points to: down and outward), and runs the upper arm toward `shoulder` (a world point: where the
player's shoulder sits relative to the camera, just below / outside the view, so the arm always leaves the
frame from a bottom corner). If the shoulder is out of reach the arm points straight at it.
"""
import math

import bpy
from mathutils import Matrix, Vector

# How each gun sits in front of the viewmodel camera, in Godot camera space (the same numbers go into
# WeaponHolder.WEAPONS[gun].hip / hip_rot once approved): position (m), rotation (deg, Godot Euler YXZ:
# x = muzzle up, y = muzzle toward screen centre (left), z = cant).
VIEWS = {
    "pistol": {"hip": (0.16, -0.15, -0.4), "rot": (0.0, 0.0, 0.0)},
    "rifle": {"hip": (0.085, -0.15, -0.10), "rot": (3.0, 8.0, -6.0)},
}
_K = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))   # Godot (x, y, z) -> Blender (x, -z, y)


def camera_matrix(gun):
    """Viewmodel camera in the gun's Blender frame: columns = camera right / forward / up (Blender-style axes),
    translation = eye position."""
    v = VIEWS[gun]
    rx, ry, rz = (math.radians(a) for a in v["rot"])
    r = Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(rz, 3, "Z")  # Godot YXZ
    rinv = r.inverted()
    eye = _K @ (rinv @ -Vector(v["hip"]))
    axes = _K @ rinv @ _K.inverted()
    m = axes.to_4x4()
    m.translation = eye
    return m


def shoulder(gun, side):
    """World / gun-frame point of the player's shoulder for `side` ("R" / "L")."""
    return camera_matrix(gun) @ (SHOULDER_R if side == "R" else SHOULDER_L)


def pole(gun, side):
    return camera_matrix(gun).to_3x3() @ (POLE_R if side == "R" else POLE_L)

# Shoulders relative to the viewmodel camera (Blender axes: +X right, +Y forward, +Z up), metres.
SHOULDER_R = Vector((0.20, -0.08, -0.22))
SHOULDER_L = Vector((-0.18, 0.08, -0.30))
POLE_R = Vector((0.6, 0.0, -1.0))
POLE_L = Vector((-0.1, 0.2, -1.0))


def camera_in_gun_frame(hip_godot):
    """Viewmodel camera position in a gun's Blender frame, from the gun's hip offset (Godot, camera space)."""
    x, y, z = hip_godot
    return Vector((-x, z, -y))


def _set_bone(rig, pb, head_w, tail_w):
    inv = rig.matrix_world.inverted()
    h, t = inv @ head_w, inv @ tail_w
    cur = pb.matrix.copy()
    y = cur.to_3x3().col[1].normalized()
    r = y.rotation_difference((t - h).normalized()).to_matrix()
    m = (r @ cur.to_3x3()).to_4x4()
    m.translation = h
    pb.matrix = m
    bpy.context.view_layer.update()


def solve_arm(rig, shoulder_w, pole_w):
    pb = rig.pose.bones
    mw = rig.matrix_world
    hand_m = pb["hand"].matrix.copy()
    wrist = mw @ pb["hand"].head
    l2, l1 = pb["forearm"].length, pb["upperarm"].length
    axis = shoulder_w - wrist
    d = axis.length
    u = axis / d
    if d >= l1 + l2 - 1e-4:
        elbow = wrist + u * l2
    else:
        a = (l2 * l2 - l1 * l1 + d * d) / (2 * d)
        h = math.sqrt(max(l2 * l2 - a * a, 0.0))
        p = pole_w - u * pole_w.dot(u)
        p = p.normalized() if p.length > 1e-6 else Vector((0, 0, -1))
        elbow = wrist + u * a + p * h
    head = elbow + (shoulder_w - elbow).normalized() * l1
    _set_bone(rig, pb["upperarm"], head, elbow)
    _set_bone(rig, pb["forearm"], elbow, wrist)
    pb["hand"].matrix = hand_m
    bpy.context.view_layer.update()
    return elbow
