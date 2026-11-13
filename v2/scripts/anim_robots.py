"""V2: the three robots' animations, baked onto the timeline of v2/scene.blend after the weapon views' clips
(24 fps, from frame 1201; ranges in the scene property `v2_clips_robots`).

    blender -b v2/scene.blend -P v2/scripts/anim_robots.py            (run after build_robots.py; saves the file)

The robots play together, section by section (markers "Robots ..."):
  Idle    spider breathes and scans with its turret; drone hovers; ceiling turret scans
  Shoot   each fires a short burst (recoil, muzzle flashes)
  Move    spider walks (0.6 m/s, 1 s cycle, in place); drone flies a banked figure; turret aims up / down and round
  Run     spider runs (1.5 m/s, 15-frame cycle, in place); the others idle
  Death   turret goes limp, drone falls out of the air, spider collapses; their lights go out
Only joints move (the empties build_robots.py hangs the parts from). The spider's legs are solved from foot targets
(hip swing + two-bone solve in the leg's plane), so the feet stay planted while the body moves.
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import build_robots as RB  # noqa: E402
from anim_lib import FPS, I4, Recorder, clamp, seg, smooth, table, write_fcurves  # noqa: E402

FIRST = 1201
TAU = math.tau
S = 0.001
OBJ = bpy.data.objects
JOINTS = [o for o in bpy.data.collections["Robots"].all_objects if o.type == "EMPTY"]
FLASHES = [o for o in bpy.data.collections["Robots"].all_objects if "_Flash" in o.name and o.type == "MESH"]
LIGHTS = [o for o in bpy.data.collections["Robots"].all_objects if o.type == "LIGHT"]
GLOWS = [OBJ[n] for n in ("Spider_Eyes", "Spider_TurretEye", "Spider_Lamps", "Drone_Eye", "Drone_GunGlow", "Turret_Eye")]
ANIMATED = JOINTS + FLASHES + GLOWS
for o in ANIMATED:
    o.animation_data_clear()
for o in LIGHTS:
    o.data.animation_data_clear()
    o.data.energy = 0.0
REST = {o.name: o.matrix_basis.copy() for o in ANIMATED}
for o in FLASHES:                                  # (they are stored hidden: scale 0)
    loc, quat, _ = REST[o.name].decompose()
    REST[o.name] = Matrix.Translation(loc) @ quat.to_matrix().to_4x4()


def Rx(d):
    return Matrix.Rotation(math.radians(d), 4, "X")


def Ry(d):
    return Matrix.Rotation(math.radians(d), 4, "Y")


def Rz(d):
    return Matrix.Rotation(math.radians(d), 4, "Z")


def Tm(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def flash(st, name, seed):
    """Show a muzzle flash for this frame, turned and sized a little differently every time."""
    rng = random.Random(seed)
    st[name] = REST[name] @ Matrix.Rotation(rng.uniform(0, 3.1), 4, "Y") @ Matrix.Scale(rng.uniform(0.85, 1.2), 4)
    st[("energy", name + "Light")] = 8.0


def shots(f, frames):
    """(index of the shot fired on this frame or None, recoil 0..1 that decays over three frames)."""
    hit = frames.index(f) if f in frames else None
    rec = max([(1.0, 0.45, 0.15)[f - s] for s in frames if 0 <= f - s <= 2] or [0.0])
    return hit, rec


# ====================================================================== spider
HIPS = [RB.T(hx, hy, -5) @ RB.RZ(ang) for hx, hy, ang in RB.LEGS]                 # hip frames in the body's frame
FEET0 = [h @ (Vector((RB.LEG_ANKLE[0], 0, RB.LEG_ANKLE[1])) * S) for h in HIPS]   # ankles at rest (body frame)
PIV = Vector(RB.LEG_PIVOT) * S
_k, _a = Vector(RB.LEG_KNEE) * S, Vector(RB.LEG_ANKLE) * S
L1, L2 = (_k - PIV).length, (_a - _k).length
A1, A2 = math.atan2(_k.y - PIV.y, _k.x - PIV.x), math.atan2(_a.y - _k.y, _a.x - _k.x)


def leg(i, target):
    """Joint matrices of leg i so that its ankle is at `target` (body frame): hip swing, then thigh and shin in the
    leg's plane (knee up), foot kept level."""
    p = HIPS[i].inverted() @ target
    yaw = math.atan2(p.y, p.x)
    px, pz = math.hypot(p.x, p.y) - PIV.x, p.z - PIV.y
    d = min(math.hypot(px, pz), L1 + L2 - 1e-4)
    a1 = math.atan2(pz, px) + math.acos(clamp((L1 * L1 + d * d - L2 * L2) / (2 * L1 * d), -1, 1))
    a2 = math.atan2(pz - L1 * math.sin(a1), px - L1 * math.cos(a1))
    d1, d2 = a1 - A1, a2 - A2
    R = lambda n, m: REST[f"Spider_{n}{i}"] @ m           # noqa: E731
    return {f"Spider_Hip{i}": R("Hip", Matrix.Rotation(yaw, 4, "Z")), f"Spider_Thigh{i}": R("Thigh", Matrix.Rotation(-d1, 4, "Y")),
            f"Spider_Shin{i}": R("Shin", Matrix.Rotation(-(d2 - d1), 4, "Y")), f"Spider_Foot{i}": R("Foot", Matrix.Rotation(d2, 4, "Y"))}


def spider(body=I4, feet=None, yaw=0.0, pitch=0.0, recoil=0.0, lights=True):
    """body = the body's move in its rest frame; feet = ankle targets in that rest frame (planted on the floor)."""
    st = {"Spider_Body": REST["Spider_Body"] @ body, "Spider_Turret": REST["Spider_Turret"] @ Rz(yaw),
          "Spider_Guns": REST["Spider_Guns"] @ Tm(y=-recoil) @ Rx(pitch)}
    inv = body.inverted()
    for i in range(4):
        st.update(leg(i, inv @ (feet[i] if feet else FEET0[i])))
    if not lights:
        st.update({n: None for n in ("Spider_Eyes", "Spider_TurretEye", "Spider_Lamps")})
    return st


def spider_idle(t):
    ph = TAU * t / 3.0
    return spider(Tm(0.006 * math.sin(ph), 0.004 * math.sin(2 * ph), 0.008 * math.sin(2 * ph + 0.5)) @ Ry(0.8 * math.sin(ph)),
                  yaw=13 * math.sin(ph), pitch=2.5 * math.sin(2 * ph + 1.0))


SPIDER_SHOTS = (3, 11, 19)


def spider_shoot(t):
    f = round(t * FPS)
    hit, rec = shots(f, SPIDER_SHOTS)
    st = spider(Tm(y=-0.012 * rec, z=-0.004 * rec) @ Rx(1.3 * rec), recoil=0.055 * rec, pitch=1.0 * rec)
    if hit is not None:
        flash(st, "Spider_FlashL", 10 + hit)
        flash(st, "Spider_FlashR", 20 + hit)
    return st


def gait(t, period, stride, lift, body):
    """Trot: diagonal pairs of legs. A foot is on the ground for half the cycle, moving back under the body."""
    feet = []
    for i in range(4):
        ph = (t / period + (0.0 if i in (0, 2) else 0.5)) % 1.0
        if ph < 0.5:
            y, z = stride * (0.5 - ph / 0.5), 0.0
        else:
            s = (ph - 0.5) / 0.5
            y, z = stride * (smooth(s) - 0.5), lift * math.sin(math.pi * s)
        feet.append(FEET0[i] + Vector((0, y, z)))
    return spider(body, feet, yaw=-20)                     # turret faces the way it walks


def spider_walk(t):
    ph = TAU * t
    return gait(t, 1.0, 0.30, 0.09, Tm(0.008 * math.sin(ph), 0, -0.006 - 0.008 * math.cos(2 * ph)) @ Ry(1.4 * math.sin(ph)) @ Rx(0.8 * math.sin(2 * ph)))


RUN_T = 15 / FPS


def spider_run(t):
    ph = TAU * t / RUN_T
    return gait(t, RUN_T, 0.47, 0.15, Tm(0.012 * math.sin(ph), 0, -0.03 - 0.016 * math.cos(2 * ph)) @ Rx(-4 + 1.5 * math.sin(2 * ph)) @ Ry(2.2 * math.sin(ph)))


def spider_death(t):
    """Hit, the lights flicker out, the legs give way: the body drops onto its belly, feet sliding outward."""
    k = table(t, [(0.25, 0), (0.75, 1.0), (0.85, 0.93), (0.95, 1.0)])           # fall, bounce, rest
    k = k * k if t < 0.75 else k
    jolt = table(t, [(0.0, 0), (0.06, 1), (0.25, 0)])
    body = Tm(0.03 * k, -0.02 * jolt - 0.05 * k, -0.40 * k) @ Ry(11 * k) @ Rx(-5 * k + 2 * jolt)
    feet = [p + Vector((p.x, p.y, 0)).normalized() * 0.13 * k for p in FEET0]
    on = t < 0.2 or 0.26 < t < 0.33 or 0.4 < t < 0.44
    return spider(body, feet, yaw=-14 * k, pitch=-19 * smooth(seg(t, 0.3, 0.9)), lights=on)


# ====================================================================== drone
DRONE_M = OBJ["Drone_Root"].matrix_world.copy()            # its placement (it leans toward the eye)
PROP_STEP = 53.0                                           # degrees a rotor turns per frame


def drone(f, world=None, local=I4, spin=None, recoil=0.0, lights=True):
    """world = a move of the whole drone in the room's frame; local = a turn / move in its own frame; spin = rotor
    angle (degrees; default: running at full speed)."""
    w = DRONE_M.inverted() @ world @ DRONE_M if world is not None else I4
    a = f * PROP_STEP if spin is None else spin
    st = {"Drone_Body": REST["Drone_Body"] @ w @ local, "Drone_PropL": REST["Drone_PropL"] @ Rz(a),
          "Drone_PropR": REST["Drone_PropR"] @ Rz(-a), "Drone_Gun": REST["Drone_Gun"] @ Tm(y=-recoil)}
    if not lights:
        st.update({n: None for n in ("Drone_Eye", "Drone_GunGlow")})
    return st


def hover(t):
    ph = TAU * t / 3.0
    return Tm(0.015 * math.sin(ph + 1.0), 0, 0.03 * math.sin(ph)), Ry(1.6 * math.sin(ph + 0.4)) @ Rz(2.0 * math.sin(ph))


def drone_idle(t, f):
    w, l = hover(t)
    return drone(f, w, l)


DRONE_SHOTS = (4, 12, 20)


def drone_shoot(t, f):
    hit, rec = shots(round(t * FPS), DRONE_SHOTS)
    w, l = hover(t)
    st = drone(f, w, l @ Tm(y=-0.02 * rec) @ Rx(2.2 * rec), recoil=0.03 * rec)
    if hit is not None:
        flash(st, "Drone_Flash", 30 + hit)
    return st


def drone_fly(t, f):
    """A banked figure-eight in front of the player (3 s loop)."""
    ph = TAU * t / 3.0
    return drone(f, Tm(0, 0, 0.08 * math.sin(2 * ph)),
                 Tm(0.38 * math.sin(ph), 0.12 * math.sin(2 * ph)) @ Ry(-13 * math.sin(ph)) @ Rx(-4 - 5 * math.cos(2 * ph)) @ Rz(-6 * math.cos(ph)))


DRONE_DROP = DRONE_M.translation.z - 0.31                  # how far it falls before a rotor duct hits the floor
_yaw0 = math.atan2(DRONE_M.col[1].y, DRONE_M.col[1].x) - math.pi / 2
DRONE_LAND = (Matrix.Rotation(_yaw0 + 0.5, 4, "Z") @ Ry(19)).to_quaternion()   # how it lies on the floor


DRONE_DIES = 0.15                                          # seconds into the Death section


def drone_death(ts, f):
    """Hit: the rotors run down, it rolls over and falls, bounces once and lies on a duct. ts = section time."""
    t = max(ts - DRONE_DIES, 0.0)
    tf = max(t - 0.12, 0.0)                                # falls after a moment of hanging
    t_hit = math.sqrt(2 * DRONE_DROP / 9.8)
    if tf < t_hit:
        z = -4.9 * tf * tf
    else:
        tb = tf - t_hit
        z = -DRONE_DROP + (max(0.0, 1.5 * tb - 4.9 * tb * tb) if tb < 0.31 else 0.0)
    k = smooth(seg(tf, 0.0, t_hit))
    tumble = Matrix.Rotation(math.radians(160) * k * (1 - k) * 1.6, 4, "Y")
    world_rot = DRONE_M.to_quaternion().slerp(DRONE_LAND, k).to_matrix().to_4x4() @ tumble
    pos = DRONE_M.translation + Vector((0.25 * k, -0.35 * k, z))
    # rotor angle = the integral of a speed that runs down to nothing in 0.8 s
    spin = PROP_STEP * FPS * (min(ts, DRONE_DIES) + (t - t * t / 1.6 if t < 0.8 else 0.4))
    st = drone(f, spin=spin, lights=t < 0.1 or 0.16 < t < 0.22 or 0.3 < t < 0.34)
    st["Drone_Body"] = REST["Drone_Body"] @ DRONE_M.inverted() @ Matrix.Translation(pos) @ world_rot
    return st


# ====================================================================== ceiling turret
def turret(yaw=0.0, shoulder=0.0, elbow=0.0, head=0.0, recoil=0.0, lights=True):
    """Angles in degrees from the rest pose: yaw of the mount; shoulder / elbow / head positive = swings down."""
    st = {"Turret_Yaw": REST["Turret_Yaw"] @ Rz(yaw), "Turret_Shoulder": REST["Turret_Shoulder"] @ Ry(shoulder),
          "Turret_Elbow": REST["Turret_Elbow"] @ Ry(elbow), "Turret_Head": REST["Turret_Head"] @ Ry(head),
          "Turret_Guns": REST["Turret_Guns"] @ Tm(x=-recoil)}
    if not lights:
        st["Turret_Eye"] = None
    return st


def turret_idle(t):
    ph = TAU * t / 3.0
    return turret(yaw=16 * math.sin(ph), head=3.5 * math.sin(2 * ph + 0.6), elbow=1.5 * math.sin(ph + 1.0))


TURRET_SHOTS = (3, 8, 13, 18)


def turret_shoot(t):
    hit, rec = shots(round(t * FPS), TURRET_SHOTS)
    st = turret(head=-1.8 * rec, elbow=-0.8 * rec, recoil=0.05 * rec)
    if hit is not None:
        flash(st, "Turret_FlashL" if hit % 2 == 0 else "Turret_FlashR", 40 + hit)
    return st


def turret_aim(t):
    """Swings left and up, then right and down, and back (3 s)."""
    yaw = table(t, [(0, 0), (0.6, 36), (1.1, 36), (1.9, -30), (2.4, -30), (3.0, 0)])
    head = table(t, [(0, 0), (0.6, -15), (1.1, -15), (1.9, 12), (2.4, 12), (3.0, 0)])
    return turret(yaw=yaw, head=head, elbow=0.4 * head, shoulder=-0.15 * head)


def swing(t, t0, amp, period, decay):
    """A limp part swinging to rest: 0 before t0, then amp * (1 - a damped cosine)."""
    if t < t0:
        return 0.0
    x = t - t0
    return amp * (1 - math.exp(-x / decay) * math.cos(TAU * x / period))


def turret_death(t):
    """Power out: the arm sags on its joints and the head drops and swings; the eye goes dark."""
    return turret(yaw=9 * smooth(seg(t, 0.0, 1.2)), shoulder=swing(t, 0.05, 20, 1.3, 0.5), elbow=swing(t, 0.12, 52, 1.0, 0.45),
                  head=swing(t, 0.2, 38, 0.8, 0.5), lights=t < 0.08 or 0.14 < t < 0.2 or 0.3 < t < 0.33)


# ====================================================================== baking
rec = Recorder()
clips = {}


def bake(frame, st=None):
    st = st or {}
    for o in ANIMATED:
        m = st.get(o.name, REST[o.name] if o not in FLASHES else None)
        rec.key_object(o, frame, m if m is not None else REST[o.name], hidden=m is None)
    for o in LIGHTS:
        rec.key_value(o.data, "energy", frame, st.get(("energy", o.name), 0.0))


def section(name, start, n, fn, parts):
    """n frames of fn(t, frame index) -> state; `parts` = {clip name: (first frame offset, length, loop)}."""
    bake(start - 1)
    for i in range(n):
        bake(start + i, fn(i / FPS, i))
    bake(start + n)
    for cname, (off, ln, loop) in parts.items():
        clips[cname] = dict(start=start + off, end=start + off + ln - 1, loop=loop)
    bpy.context.scene.timeline_markers.new("Robots " + name, frame=start)
    print(f"section {name}: frames {start}-{start + n - 1}")
    return start + n + 8


def merge(*states):
    out = {}
    for s_ in states:
        out.update(s_)
    return out


sc = bpy.context.scene
for mk in list(sc.timeline_markers):
    if mk.name.startswith("Robots "):
        sc.timeline_markers.remove(mk)
f = FIRST
f = section("Idle", f, 72, lambda t, i: merge(spider_idle(t), drone_idle(t, i), turret_idle(t)),
            {"Spider Idle": (0, 72, True), "Drone Idle": (0, 72, True), "Turret Idle": (0, 72, True)})
f = section("Shoot", f, 30, lambda t, i: merge(spider_shoot(t), drone_shoot(t, i), turret_shoot(t)),
            {"Spider Shoot": (0, 30, False), "Drone Shoot": (0, 30, False), "Turret Shoot": (0, 30, False)})
f = section("Move", f, 72, lambda t, i: merge(spider_walk(t), drone_fly(t, i), turret_aim(t)),
            {"Spider Walk": (0, 24, True), "Drone Fly": (0, 72, True), "Turret Aim": (0, 72, False)})
f = section("Run", f, 60, lambda t, i: merge(spider_run(t), drone_idle(t, i), turret_idle(t)), {"Spider Run": (0, 15, True)})
DEATH_N = 60
f = section("Death", f, DEATH_N, lambda t, i: merge(spider_death(max(t - 0.35, 0.0)), drone_death(t, i), turret_death(t)),
            {"Spider Death": (0, DEATH_N, False), "Drone Death": (0, DEATH_N, False), "Turret Death": (0, DEATH_N, False)})
write_fcurves(rec.ch, "Robots")
sc["v2_clips_robots"] = json.dumps(clips)
sc.render.fps = FPS
sc.frame_end = max(c["end"] for k in sc.keys() if k.startswith("v2_clips_") for c in json.loads(sc[k]).values())
sc.frame_set(1)
if "nosave" not in sys.argv:
    bpy.ops.wm.save_mainfile()
print("clips:", clips)
