"""V2: the three robots' animations, baked onto the timeline of v2/scene.blend after the weapon views' clips
(24 fps, from frame 1201; ranges in the scene property `v2_clips_robots`).

    blender -b v2/scene.blend -P v2/scripts/anim_robots.py            (run after build_robots.py; saves the file)

The robots play together, section by section (markers "Robots ..."):
  Idle    spider shifts its weight, snaps its turret from target to target, stamps a foot; drone hovers and looks
          about; ceiling turret scans in snaps
  Shoot   each braces, fires a short burst (recoil running through the whole body, muzzle flashes) and settles
  Move    spider walks (0.6 m/s, 1 s cycle, in place); drone flies a banked figure; turret whips up / down and round
  Run     spider runs (1.5 m/s, 15-frame cycle, in place); the others idle
  Death   turret spasms and goes limp, drone spirals out of the air and bounces, spider staggers and slams down
  Firefight (frames from fx_plan.py, with the weapon views' Firefight clips): all three keep firing at the player
The motion is deliberately broad: anticipation before an action, overshoot and settle on every stop (`steps`),
recoil as damped oscillation (`imp`) that the lighter parts pick up later than the heavy ones.
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
import fx_plan as PLAN  # noqa: E402
from anim_lib import FPS, I4, Recorder, back_out, clamp, seg, smooth, table, write_fcurves  # noqa: E402

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


def steps(t, keys, d=0.28, s=2.0, start=0.0):
    """Snappy moves: at each (time, value) go to that value in d seconds, overshooting and settling."""
    prev = val = start
    for ti, vi in keys:
        if t >= ti:
            val = prev + (vi - prev) * back_out(seg(t, ti, ti + d), s)
        prev = vi
    return val


def imp(t, times, period, decay):
    """What a hit at each of `times` leaves behind: a swing that dies away (1 at the hit, then ringing)."""
    return sum(math.exp(-(t - x) / decay) * math.cos(TAU * (t - x) / period) for x in times if t >= x)


def bump(t, times, decay):
    """1 at each of `times`, falling straight back (no ringing): a barrel's recoil."""
    return sum(math.exp(-(t - x) / decay) for x in times if t >= x)


def swing(t, t0, amp, period, decay):
    """A limp part swinging to rest: 0 before t0, then amp * (1 - a damped cosine)."""
    if t < t0:
        return 0.0
    x = t - t0
    return amp * (1 - math.exp(-x / decay) * math.cos(TAU * x / period))


def flicker(t, until):
    """Lights failing: on, then stuttering, then off for good."""
    return t < until and (t < 0.12 or math.sin(t * 61.0) * math.sin(t * 23.0 + 1.0) > -0.15)


SHOT_T = tuple(x / FPS for x in PLAN.SHOOT_SPIDER)  # when the bursts' rounds go off (s into the Shoot section)


def fired(t, times=SHOT_T):
    """Index of the round fired on this frame, or None."""
    f = round(t * FPS)
    hits = [i for i, x in enumerate(times) if round(x * FPS) == f]
    return hits[0] if hits else None


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
    """Weight shifting from side to side, the turret snapping from target to target, one foot stamped."""
    ph = TAU * t / 3.0
    stamp = seg(t, 1.7, 2.0)
    feet = list(FEET0)
    feet[1] = FEET0[1] + Vector((0, 0.04 * math.sin(math.pi * stamp), 0.11 * math.sin(math.pi * stamp)))
    land = imp(t, [2.0], 0.3, 0.12)
    body = Tm(0.03 * math.sin(ph), 0.012 * math.sin(ph + 1.0), 0.022 * math.sin(2 * ph + 0.5) - 0.012 * land) \
        @ Ry(2.2 * math.sin(ph) + 1.0 * land) @ Rx(1.2 * math.sin(2 * ph))
    snaps = [(0.25, 30), (1.25, -26), (2.35, 0)]
    return spider(body, feet, yaw=steps(t, snaps, 0.28, 2.2),
                  pitch=4 * math.sin(2 * ph) - 4 * imp(t, [x + 0.05 for x, _ in snaps], 0.25, 0.12))


def spider_shoot(t, times=SHOT_T, end=1.4):
    """Crouch and lean in, twin shots that rock the whole machine back on its legs, rise again (by `end` s)."""
    c = smooth(seg(t, 0.0, 0.18)) * (1 - smooth(seg(t, end - 0.4, end)))
    rock = imp(t, times, 0.36, 0.13)                        # the body takes the shot and rings
    st = spider(Tm(0, 0.03 * c - 0.04 * rock, -0.05 * c + 0.012 * rock) @ Rx(-3 * c + 4.5 * rock) @ Ry(0.8 * rock),
                recoil=0.09 * bump(t, times, 0.055), pitch=3.5 * imp(t, [x + 0.03 for x in times], 0.3, 0.1) - 2 * c)
    hit = fired(t, times)
    if hit is not None:
        flash(st, "Spider_FlashL", 10 + hit)
        flash(st, "Spider_FlashR", 20 + hit)
    return st


def gait(t, period, stride, lift, body, yaw, pitch):
    """Trot: diagonal pairs of legs. A foot is on the ground for half the cycle, moving back under the body; in the
    air it snaps up high early and reaches forward before it comes down."""
    feet = []
    for i in range(4):
        ph = (t / period + (0.0 if i in (0, 2) else 0.5)) % 1.0
        if ph < 0.5:
            y, z = stride * (0.5 - ph / 0.5), 0.0
        else:
            s_ = (ph - 0.5) / 0.5
            y, z = stride * (back_out(s_, 1.2) - 0.5), lift * math.sin(math.pi * s_ ** 0.7)
        feet.append(FEET0[i] + Vector((0, y, z)))
    return spider(body, feet, yaw=yaw, pitch=pitch)


def spider_walk(t):
    """A heavy swagger: the body rolls and sways over the planted pair, the turret lags behind it."""
    ph = TAU * t
    body = Tm(0.025 * math.sin(ph), 0, -0.01 - 0.022 * math.cos(2 * ph)) @ Rz(2.5 * math.sin(ph)) @ Ry(3.5 * math.sin(ph)) \
        @ Rx(1.8 * math.sin(2 * ph + 0.6))
    return gait(t, 1.0, 0.30, 0.16, body, yaw=-20 + 5 * math.sin(ph + 1.2), pitch=3 * math.sin(2 * ph + 1.5))


RUN_T = 15 / FPS


def spider_run(t):
    """Nose down, pounding: the body pitches and drops with every pair of feet, guns bouncing."""
    ph = TAU * t / RUN_T
    body = Tm(0.02 * math.sin(ph), 0, -0.035 - 0.04 * math.cos(2 * ph)) @ Rx(-7 + 4 * math.sin(2 * ph)) @ Ry(4 * math.sin(ph))
    return gait(t, RUN_T, 0.47, 0.24, body, yaw=-20 + 7 * math.sin(ph + 1.0), pitch=5 * math.sin(2 * ph + 1.2))


SPIDER_DIES = 0.35                                         # seconds into the Death section


def spider_death(ts):
    """Hit: knocked back, it staggers with the turret whipping round and a front leg pawing the air, the lights
    stutter, then the legs give way and it slams down, bounces, and a rear leg twitches twice."""
    t = max(ts - SPIDER_DIES, 0.0)
    jolt = imp(t, [0.0], 0.4, 0.16) if ts >= SPIDER_DIES else 0.0
    stag = math.sin(TAU * 2.6 * t) * math.exp(-t / 0.45) * seg(t, 0.0, 0.1)
    k = table(t, [(0.7, 0), (1.05, 1.0), (1.17, 0.83), (1.3, 1.0), (1.37, 0.96), (1.45, 1.0)])   # fall, bounce, rest
    if t < 1.05:
        k = k * k                                           # (falls faster and faster)
    body = Tm(0.05 * stag + 0.03 * k, -0.06 * jolt - 0.05 * k, 0.03 * jolt - 0.40 * k) \
        @ Ry(6 * stag + 14 * k) @ Rx(8 * jolt - 5 * k)
    feet = [p + Vector((p.x, p.y, 0)).normalized() * 0.16 * k for p in FEET0]
    paw = seg(t, 0.18, 0.55)                                # a front leg off the ground
    feet[0] = feet[0] + Vector((0, 0.1 * math.sin(math.pi * paw), 0.22 * math.sin(math.pi * paw) ** 0.6 if paw > 0 else 0))
    for t0 in (1.75, 2.05):                                 # after the fall: a rear leg kicks
        tw = seg(t, t0, t0 + 0.16)
        feet[2] = feet[2] + Vector((0, 0, 0.07 * math.sin(math.pi * tw)))
    return spider(body, feet, yaw=steps(t, [(0.05, 150), (0.6, 110)], 0.4, 2.4) * (1 if ts >= SPIDER_DIES else 0),
                  pitch=12 * stag - swing(t, 1.0, 24, 0.5, 0.25), lights=flicker(t, 0.95))


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


LOOKS = [(0.3, 22), (1.3, -18), (2.3, 0)]


def hover(t):
    """Never still: it drifts and bobs, and snaps its nose from side to side, banking into each look."""
    ph = TAU * t / 3.0
    look = steps(t, LOOKS, 0.26, 2.4)
    lean = imp(t, [x for x, _ in LOOKS], 0.45, 0.16)
    return (Tm(0.04 * math.sin(ph + 1.0), 0, 0.05 * math.sin(ph) + 0.015 * math.sin(3 * ph)),
            Rz(look) @ Ry(3.5 * math.sin(ph + 0.4) + 5 * lean) @ Rx(2.5 * math.sin(2 * ph)))


def drone_idle(t, f):
    w, l = hover(t)
    return drone(f, w, l)


def drone_shoot(t, f, times=SHOT_T, end=1.4):
    """Rises and drops its nose to aim, shots that throw it back and up, swings back level (by `end` s)."""
    c = smooth(seg(t, 0.0, 0.2)) * (1 - smooth(seg(t, end - 0.45, end)))
    kick = imp(t, times, 0.38, 0.14)
    st = drone(f, Tm(0, 0, 0.04 * c + 0.02 * kick), Tm(y=-0.03 * c - 0.07 * kick) @ Rx(-6 * c + 8 * kick) @ Ry(1.5 * kick),
               recoil=0.05 * bump(t, times, 0.05))
    hit = fired(t, times)
    if hit is not None:
        flash(st, "Drone_Flash", 30 + hit)
    return st


def drone_fly(t, f):
    """A wide, steeply banked figure-eight (3 s loop), nose swinging into each turn."""
    ph = TAU * t / 3.0
    return drone(f, Tm(0, 0, 0.16 * math.sin(2 * ph + 0.5)),
                 Tm(0.6 * math.sin(ph), 0.2 * math.sin(2 * ph)) @ Rz(-14 * math.cos(ph)) @ Ry(-24 * math.sin(ph)) @ Rx(-6 - 8 * math.cos(2 * ph)))


DRONE_DROP = DRONE_M.translation.z - 0.34                  # how far it falls before a rotor duct hits the floor
_yaw0 = math.atan2(DRONE_M.col[1].y, DRONE_M.col[1].x) - math.pi / 2
DRONE_DIES = 0.15                                          # seconds into the Death section
DRONE_G = 7.0                                              # it falls slower than a stone: the rotors still bite
DRONE_HIT = 0.12 + math.sqrt(2 * DRONE_DROP / DRONE_G)     # when it reaches the floor (s after it is hit)


def drone_death(ts, f):
    """Hit: thrown sideways, it corkscrews down spinning about its own axis with the rotors sputtering, slams into
    the floor, bounces twice while skidding, and rocks to rest on a duct. ts = section time."""
    t = max(ts - DRONE_DIES, 0.0)
    jolt = imp(t, [0.0], 0.3, 0.1) if ts >= DRONE_DIES else 0.0
    tf = max(t - 0.12, 0.0)
    k = seg(t, 0.12, DRONE_HIT)                            # 0 at the start of the fall, 1 on the floor
    tb = t - DRONE_HIT
    if tb < 0:
        z = -0.5 * DRONE_G * tf * tf
    elif tb < 0.47:
        z = -DRONE_DROP + 2.3 * tb - 4.9 * tb * tb         # first bounce
    elif tb < 0.71:
        x = tb - 0.47
        z = -DRONE_DROP + 1.15 * x - 4.9 * x * x           # second, smaller
    else:
        z = -DRONE_DROP
    ang = 9.0 * min(tf, DRONE_HIT - 0.12)                  # the corkscrew (stops where it lands)
    rad = 0.1 + 0.3 * k
    skid = 0.35 * smooth(seg(tb, 0.0, 0.9))
    # (it drifts toward the middle of the floor: the other way it ends against the tank, half out of the frame)
    pos = DRONE_M.translation + Vector((-0.12 * jolt + rad * math.sin(ang) - 0.3 * k - skid * 0.7,
                                        -0.06 * jolt + rad * (1 - math.cos(ang)) - 0.15 * k - skid * 0.5, z))
    turns = math.radians(900) * smooth(seg(t, 0.05, DRONE_HIT + 0.5))             # spinning about the vertical
    rock = 14 * math.exp(-max(tb, 0) / 0.3) * math.cos(TAU * max(tb, 0) / 0.36) if tb >= 0 else 0.0
    land = (Matrix.Rotation(_yaw0 + 0.5, 4, "Z") @ Ry(19 + rock)).to_quaternion()
    fall_rot = (Matrix.Rotation(turns, 4, "Z") @ DRONE_M.to_3x3().to_4x4() @ Ry(25 * jolt + 38 * math.sin(7.0 * tf) * (1 - k))).to_quaternion()
    world_rot = fall_rot.slerp(Matrix.Rotation(turns, 4, "Z").to_quaternion() @ land, smooth(seg(t, DRONE_HIT - 0.25, DRONE_HIT + 0.05)))
    # rotor angle = the integral of a speed that sputters and runs down in a second
    run = t - t * t / 2.0 if t < 1.0 else 0.5
    spin = PROP_STEP * FPS * (min(ts, DRONE_DIES) + run + 0.03 * math.sin(30 * t) * (1 - seg(t, 0, 1.0)))
    st = drone(f, spin=spin, lights=flicker(t, DRONE_HIT))
    st["Drone_Body"] = REST["Drone_Body"] @ DRONE_M.inverted() @ Matrix.Translation(pos) @ world_rot.to_matrix().to_4x4()
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
    """Scans in snaps: the mount whips round and stops dead, the head nods as the arm catches up, then it peers."""
    ph = TAU * t / 3.0
    snaps = [(0.2, 24), (1.2, -20), (2.3, 0)]
    stop = imp(t, [x + 0.12 for x, _ in snaps], 0.3, 0.13)
    return turret(yaw=steps(t, snaps, 0.3, 2.2), head=steps(t, [(0.6, -8), (1.6, 7), (2.55, 0)], 0.22, 2.0) + 3 * stop,
                  elbow=3 * math.sin(ph + 1.0) - 2 * stop, shoulder=0.8 * math.sin(ph))


TURRET_SHOT_T = tuple(x / FPS for x in PLAN.SHOOT_TURRET)


def turret_shoot(t, times=TURRET_SHOT_T, end=1.35):
    """Draws its head back and locks, then the shots: the guns slam back, the head kicks up, and the kick runs up
    the arm joint by joint; then it shakes itself still (by `end` s)."""
    c = smooth(seg(t, 0.0, 0.2)) * (1 - smooth(seg(t, end - 0.4, end)))
    kick = imp(t, times, 0.3, 0.1)
    st = turret(yaw=1.3 * imp(t, [x + 0.02 for x in times], 0.22, 0.08), head=-3 * c - 5 * kick,
                elbow=6 * c + 3.2 * imp(t, [x + 0.03 for x in times], 0.34, 0.12),
                shoulder=-1.8 * imp(t, [x + 0.06 for x in times], 0.4, 0.14), recoil=0.09 * bump(t, times, 0.05))
    hit = fired(t, times)
    if hit is not None:
        flash(st, "Turret_FlashL" if hit % 2 == 0 else "Turret_FlashR", 40 + hit)
    return st


def turret_aim(t):
    """Whips left and up, then right and down, and back (3 s): the head leads, the mount follows, the elbow reaches
    last, and everything overshoots its mark and settles."""
    return turret(yaw=steps(t, [(0.1, 42), (1.2, -36), (2.3, 0)], 0.36, 2.0),
                  head=steps(t, [(0.05, -18), (1.15, 14), (2.25, 0)], 0.25, 2.4),
                  elbow=steps(t, [(0.18, -10), (1.28, 8), (2.38, 0)], 0.42, 2.6),
                  shoulder=steps(t, [(0.2, 3), (1.3, -3), (2.4, 0)], 0.45, 2.0))


def turret_death(t):
    """Short circuit: half a second of spasms (head whipping, mount jerking), then the power goes: the arm drops on
    its joints, the head hangs and swings a long time, and it twitches once more at the end."""
    sp = math.exp(-t / 0.22) * seg(t, 0.0, 0.04)            # the spasms
    off = 0.45
    late = imp(t, [2.2], 0.18, 0.07)                        # the last twitch
    return turret(yaw=16 * math.sin(41 * t) * sp + swing(t, off, 30, 2.2, 0.9),
                  shoulder=5 * math.sin(33 * t + 1) * sp + swing(t, off, 26, 1.4, 0.7),
                  elbow=-9 * math.sin(37 * t) * sp + swing(t, off + 0.05, 66, 1.1, 0.6) + 3 * late,
                  head=22 * math.sin(47 * t + 2) * sp + swing(t, off + 0.1, 55, 0.85, 0.7) - 7 * late,
                  lights=flicker(t, 0.6))


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
f = section("Shoot", f, 40, lambda t, i: merge(spider_shoot(t), drone_shoot(t, i), turret_shoot(t)),
            {"Spider Shoot": (0, 40, False), "Drone Shoot": (0, 40, False), "Turret Shoot": (0, 40, False)})
f = section("Move", f, 72, lambda t, i: merge(spider_walk(t), drone_fly(t, i), turret_aim(t)),
            {"Spider Walk": (0, 24, True), "Drone Fly": (0, 72, True), "Turret Aim": (0, 72, False)})
f = section("Run", f, 60, lambda t, i: merge(spider_run(t), drone_idle(t, i), turret_idle(t)), {"Spider Run": (0, 15, True)})
DEATH_N = 76
f = section("Death", f, DEATH_N, lambda t, i: merge(spider_death(t), drone_death(t, i), turret_death(t)),
            {"Spider Death": (0, DEATH_N, False), "Drone Death": (0, DEATH_N, False), "Turret Death": (0, DEATH_N, False)})
FF_END = PLAN.FF_N / FPS
_sp, _dr, _tu = (tuple(x / FPS for x in v) for v in (PLAN.FF_SPIDER, PLAN.FF_DRONE, PLAN.FF_TURRET))
section("Firefight", PLAN.FF_START, PLAN.FF_N,
        lambda t, i: merge(spider_shoot(t, _sp, FF_END), drone_shoot(t, i, _dr, FF_END), turret_shoot(t, _tu, FF_END)),
        {"Spider Firefight": (0, PLAN.FF_N, False), "Drone Firefight": (0, PLAN.FF_N, False), "Turret Firefight": (0, PLAN.FF_N, False)})
write_fcurves(rec.ch, "Robots")
sc["v2_clips_robots"] = json.dumps(clips)
sc.render.fps = FPS
sc.frame_end = max(c["end"] for k in sc.keys() if k.startswith("v2_clips_") for c in json.loads(sc[k]).values())
sc.frame_set(1)
if "nosave" not in sys.argv:
    bpy.ops.wm.save_mainfile(compress=True)
print("clips:", clips)
