"""SD-4 animations (runs on the saved blender/sd4.blend; rebuild-safe: clears and re-keys the rig).

    blender -b blender/sd4.blend -P blender/scripts/anim_sd4.py

30 fps, one action "SD4Rig_Anim" on the rig, every bone keyed on every frame; timeline markers per clip:
  Idle   f1-60    loop: body breathing + weight shift, cannon scans left/right, lens pulse
  Shoot  f67-90   cannon shot (barrel kicks 7 cm, cannon flips up, body jolts back, main flash),
                  then the under-guns fire L/R/L/R with their flashes
  Walk   f97-126  loop (30 f cycle): alternating tripod gait (L1 R2 L3 / R1 L2 R3), stride 0.30 m -> body
                  speed 0.6 m/s in the game, feet lift 8 cm, body bob + roll
  Run    f133-152 loop (20 f cycle): stride 0.50 m (1.5 m/s), feet lift 11 cm, body 5 cm lower, nose down 6 deg
  Death  f159-203 hit jolt, legs splay and buckle, body drops to the floor, cannon tips off its mount,
                  barrel droops, lenses flicker and die, one leg twitches
Locomotion is in place (root bone never moves); the game moves the body. Legs are posed with a 2-bone solver
in each leg's plane (hip yaw toward the foot, knee up), so planted feet stay fixed and never go below Z=0.
The lens glow (NeonOrange emission strength) is keyed on the material for review; in the game the glow is
driven by code.
"""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 30
CLIPS = {"Idle": (1, 60), "Shoot": (67, 90), "Walk": (97, 126), "Run": (133, 152), "Death": (159, 203)}
TRIPOD_A = {"L1", "R2", "L3"}
LEGS = [f"{s}{k}" for s in "LR" for k in "123"]
Z = Vector((0, 0, 1))

sc = bpy.context.scene
sc.render.fps = FPS
sc.frame_start, sc.frame_end = 1, CLIPS["Death"][1]
rig = bpy.data.objects["SD4Rig"]
arm = rig.data
if rig.animation_data:
    rig.animation_data_clear()
rig.animation_data_create()
rig.animation_data.action = bpy.data.actions.new("SD4Rig_Anim")
for b in rig.pose.bones:
    b.rotation_mode = "QUATERNION"

REST = {b.name: b.matrix_local.copy() for b in arm.bones}
PARENT = {b.name: (b.parent.name if b.parent else None) for b in arm.bones}
ORDER = []


def visit(b):
    ORDER.append(b.name)
    for c in b.children:
        visit(c)


for b in arm.bones:
    if b.parent is None:
        visit(b)

# Leg rest data (armature space; the rig sits at the origin).
LEG = {}
for nm in LEGS:
    hip = arm.bones[f"{nm}_hip"].head_local.copy()
    knee = arm.bones[f"{nm}_shin"].head_local.copy()
    ankle = arm.bones[f"{nm}_foot"].head_local.copy()
    tip = arm.bones[f"{nm}_foot"].tail_local.copy()
    d0 = Vector((tip.x - hip.x, tip.y - hip.y, 0)).normalized()
    LEG[nm] = dict(hip=hip, tip=tip, L1=(knee - hip).length, L2=(ankle - knee).length,
                   dr=(tip - ankle).dot(d0), dz=(tip - ankle).z, d0=d0)


def frame_m(head, ydir, n):
    """Bone pose matrix: Y along ydir, X = n (knee axis), Z = X x Y."""
    y = ydir.normalized()
    x = (n - y * n.dot(y)).normalized()
    z = x.cross(y)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = head
    return m


def solve_leg(nm, body_pose, target):
    """Armature-space poses of <nm>_hip/_thigh/_shin/_foot for the hip carried by body_pose and the foot tip at target."""
    L = LEG[nm]
    H = body_pose @ REST["body"].inverted() @ L["hip"]
    flat = Vector((target.x - H.x, target.y - H.y, 0))
    d = flat.normalized() if flat.length > 1e-4 else L["d0"]
    n = d.cross(Z)
    A = target - d * L["dr"] - Z * L["dz"]
    ra, za = (A - H).dot(d), (A - H).z
    D = max(min(math.hypot(ra, za), L["L1"] + L["L2"] - 1e-4), abs(L["L1"] - L["L2"]) + 1e-4)
    phi = math.atan2(za, ra)
    alpha = math.acos(max(-1.0, min(1.0, (L["L1"] ** 2 + D * D - L["L2"] ** 2) / (2 * L["L1"] * D))))
    th = phi + alpha
    K = H + d * (L["L1"] * math.cos(th)) + Z * (L["L1"] * math.sin(th))
    A2 = H + (d * math.cos(phi) + Z * math.sin(phi)) * D
    return {f"{nm}_hip": frame_m(H, d, n), f"{nm}_thigh": frame_m(H, K - H, n), f"{nm}_shin": frame_m(K, A2 - K, n),
            f"{nm}_foot": frame_m(A2, target - A2 + (A - A2), n)}


def body_matrix(off=Vector(), pitch=0.0, roll=0.0, yaw=0.0):
    """Body pose: rotate about the body bone head, then offset (world)."""
    head = REST["body"].translation
    r = (Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(roll, 4, "Y") @ Matrix.Rotation(pitch, 4, "X"))
    return Matrix.Translation(head + off) @ r @ Matrix.Translation(-head) @ REST["body"]


PREV_Q = {}


def key(frame, poses, basis):
    """poses: bone -> armature-space pose; basis: bone -> local basis matrix. Everything else: identity basis."""
    pose = {}
    for name in ORDER:
        p = PARENT[name]
        rel = REST[name] if p is None else REST[p].inverted() @ REST[name]
        parent_pose = Matrix.Identity(4) if p is None else pose[p]
        if name in poses:
            pose[name] = poses[name]
            b = rel.inverted() @ parent_pose.inverted() @ poses[name]
        else:
            b = basis.get(name, Matrix.Identity(4))
            pose[name] = parent_pose @ rel @ b
        loc, q, s = b.decompose()
        if name in PREV_Q:
            q.make_compatible(PREV_Q[name])
        PREV_Q[name] = q
        pb = rig.pose.bones[name]
        pb.location, pb.rotation_quaternion, pb.scale = loc, q, s
        pb.keyframe_insert("location", frame=frame)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("scale", frame=frame)


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def R(axis, deg):
    return Matrix.Rotation(math.radians(deg), 4, axis)


def S(v):
    v = max(v, 0.001)
    return Matrix.Diagonal((v, v, v, 1))


def pulse(t, t0, attack=1.0, decay=6.0):
    """0 before t0, snaps to 1 over `attack` frames, decays exponentially."""
    if t < t0:
        return 0.0
    if t < t0 + attack:
        return (t - t0) / attack
    return math.exp(-(t - t0 - attack) / decay * 2.2)


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


FLASH_OFF = {"flash_main": S(0), "flash_L": S(0), "flash_R": S(0)}


def planted(body):
    return {k: v for nm in LEGS for k, v in solve_leg(nm, body, LEG[nm]["tip"]).items()}


# ---- Idle -----------------------------------------------------------------------------------------------------
f0, f1 = CLIPS["Idle"]
for f in range(f0, f1 + 1):
    t = (f - f0) / (f1 - f0 + 1)
    body = body_matrix(Vector((0.008 * math.sin(2 * math.pi * t), 0, 0.008 * math.sin(4 * math.pi * t))),
                       pitch=math.radians(1.0 * math.sin(2 * math.pi * t + 1)), roll=math.radians(1.5 * math.sin(2 * math.pi * t)))
    basis = dict(FLASH_OFF)
    basis["turret_yaw"] = R("Y", 28 * math.sin(2 * math.pi * t))
    basis["cannon_pitch"] = R("X", 4 * math.sin(4 * math.pi * t))
    key(f, planted(body), basis)

# ---- Shoot ----------------------------------------------------------------------------------------------------
f0, f1 = CLIPS["Shoot"]
for f in range(f0, f1 + 1):
    t = f - f0
    kick = pulse(t, 2, 1, 7)
    body = body_matrix(Vector((0, -0.025 * kick, 0.004 * kick)), pitch=math.radians(3 * kick))
    basis = {"turret_yaw": Matrix.Identity(4),
             "cannon_pitch": R("X", 2 + 7 * kick),
             "barrel": T(y=-0.07 * pulse(t, 2, 1, 5)),
             "flash_main": S(1.0 if t == 2 else 0.7 if t == 3 else 0)}
    for g, fl, shots in (("gun_L", "flash_L", (6, 12)), ("gun_R", "flash_R", (9, 15))):
        k = sum(pulse(t, s, 1, 2) for s in shots)
        basis[g] = T(y=-0.015 * min(k, 1.0))
        basis[fl] = S(1.0 if t in shots else 0.6 if t - 1 in shots else 0)
    key(f, planted(body), basis)


# ---- Walk / Run (in place) -----------------------------------------------------------------------------------------
def gait(clip, stride, lift, bob, roll, dz, pitch, duty=0.5):
    f0, f1 = CLIPS[clip]
    n = f1 - f0 + 1
    for f in range(f0, f1 + 1):
        p = (f - f0) / n
        body = body_matrix(Vector((0, 0, dz + bob * math.cos(4 * math.pi * p))), pitch=math.radians(pitch),
                           roll=math.radians(roll * math.sin(2 * math.pi * p)))
        poses = {}
        for nm in LEGS:
            q = (p + (0.0 if nm in TRIPOD_A else 0.5)) % 1.0
            if q < duty:                       # stance: foot slides back at body speed
                s = q / duty
                y, h = stride / 2 - stride * s, 0.0
            else:                              # swing: lift and carry forward
                s = (q - duty) / (1 - duty)
                y, h = -stride / 2 + stride * smooth(s), lift * math.sin(math.pi * s)
            poses.update(solve_leg(nm, body, LEG[nm]["tip"] + Vector((0, y, h))))
        basis = dict(FLASH_OFF)
        basis["turret_yaw"] = R("Y", -4 * math.sin(2 * math.pi * p))
        basis["cannon_pitch"] = R("X", -pitch * 0.6)
        key(f, poses, basis)


gait("Walk", stride=0.30, lift=0.08, bob=0.012, roll=1.5, dz=0.0, pitch=0.0)
gait("Run", stride=0.50, lift=0.11, bob=0.025, roll=2.5, dz=-0.05, pitch=-6.0)

# ---- Death ----------------------------------------------------------------------------------------------------
f0, f1 = CLIPS["Death"]
for f in range(f0, f1 + 1):
    t = f - f0
    hit = pulse(t, 0, 1, 3)
    fall = smooth((t - 3) / 12.0) ** 1.6              # gravity-ish ease-in, lands at t ~ 15
    bounce = 0.012 * math.sin(min(max(t - 15, 0) / 6.0, 1.0) * math.pi) if t >= 15 else 0.0
    body = body_matrix(Vector((0.0, -0.03 * hit, -0.145 * fall + bounce)), pitch=math.radians(8 * hit),
                       roll=math.radians(5 * hit + 2.5 * fall))
    poses = {}
    for nm in LEGS:
        tip0 = LEG[nm]["tip"]
        radial = Vector((tip0.x, tip0.y, 0)).normalized()
        splay = 0.12 * fall
        lift = 0.0
        if nm in ("L1", "R3"):                       # two legs kick up as it collapses
            lift = 0.07 * smooth((t - 6) / 8.0) * (1 - smooth((t - 22) / 10.0))
        if nm == "L1":                               # last twitch
            lift += 0.05 * math.sin(min(max(t - 30, 0) / 5.0, 1.0) * math.pi) if 30 <= t <= 35 else 0.0
        poses.update(solve_leg(nm, body, tip0 + radial * splay + Vector((0, 0, lift))))
    tip = smooth((t - 10) / 10.0)
    settle = 0.03 * math.sin(min(max(t - 20, 0) / 6.0, 1.0) * math.pi) if t >= 20 else 0.0
    basis = dict(FLASH_OFF)
    # turret_yaw local axes: X = +X, Y = up, Z = back. Cannon slides off sideways, drops, rolls over.
    basis["turret_yaw"] = T(x=0.2 * tip, y=-0.11 * tip + settle) @ R("Z", -82 * tip) @ R("Y", 25 * tip)
    basis["cannon_pitch"] = R("X", -16 * smooth((t - 14) / 8.0))
    basis["barrel"] = T(y=-0.03 * tip)
    key(f, poses, basis)

# ---- Lens glow (material, review only) -------------------------------------------------------------------------
lens = bpy.data.materials["NeonOrange"]
inp = lens.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"]
if lens.node_tree.animation_data:
    lens.node_tree.animation_data_clear()
for f in range(1, 61, 3):
    inp.default_value = 3.0 + 1.5 * math.sin(2 * math.pi * (f - 1) / 60)
    inp.keyframe_insert("default_value", frame=f)
for f, v in ((61, 3.0), (67, 4.0), (159, 4.0), (163, 4.0), (165, 0.6), (167, 3.5), (169, 0.4), (171, 2.0), (174, 0.0),
             (203, 0.0)):
    inp.default_value = v
    inp.keyframe_insert("default_value", frame=f)

for name, (a, b) in CLIPS.items():
    mk = sc.timeline_markers.get(name) or sc.timeline_markers.new(name, frame=a)
    mk.frame = a
sc.frame_set(1)
bpy.ops.wm.save_mainfile()
print("animated", {k: v for k, v in CLIPS.items()})
