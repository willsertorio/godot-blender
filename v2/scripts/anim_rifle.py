"""V2: the machine gun's first-person animations, baked onto the timeline of v2/scene.blend after the pistol's
(24 fps, frames 601-1200, markers "MG <clip>", ranges in the scene property `v2_clips_rifle`).

    blender -b v2/scene.blend -P v2/scripts/anim_rifle.py             (run after build_viewmodel.py and anim_pistol.py)

Clips: Idle (loop), Walk (loop), Sprint, Fire (an 8-round burst), ADS (aim, a 6-round burst, lower), Draw,
ReloadTactical, ReloadEmpty (charging handle locked back; ends with a slap on the bolt catch), Inspect.
Kept simple on purpose: the right hand never leaves the grip; the left hand stays on the magazine well except in the
reloads (it slides down to the magazine, takes it out of frame and brings one back) and in Inspect (it drops away).
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import hands as H  # noqa: E402
import build_rifle as R  # noqa: E402
from anim_lib import (Baker, FPS, I4, WINDOW, away_left, back_out, cam_rot, clamp, ease_out, lerp, mix_m, mix_spec, move,  # noqa: E402
                      rot, seg, smooth, sway, table, xform_spec)

W = "rifle"
AN = R.ANCHORS
HOLD = dict(H.rifle_hold(AN, H.cam_in_gun(W)))
L0 = H.view_local(W)
PIV = AN["tang"] + Vector((0, 0.03, -0.03))                # handling turns about the grip
BUTT = Vector((0, -0.34, -0.01))                           # recoil turns about the shoulder
TAU = math.tau

for name, cname in H.COLL.items():
    bpy.data.collections[cname].hide_render = bpy.data.collections[cname].hide_viewport = name != W
light = bpy.data.objects["R_FlashLight"].data
CASINGS = [f"R_Casing{i}" for i in range(R.N_CASINGS)]
parts = {"R_ChargingHandle": I4, "R_Trigger": I4, "R_Magazine": I4, "R_Flash": ("hidden", Matrix.Translation(R.MUZZLE))}
parts.update({n: None for n in CASINGS})
B = Baker(W, HOLD, parts, {(light, "energy"): 0.0}, first_frame=1 + WINDOW, label="MG ")


def gun(right=0.0, fwd=0.0, up=0.0, pitch=0.0, yaw=0.0, roll=0.0, base=L0, pivot=PIV):
    """Gun placement: a placement shifted in the eye's frame and turned about a point of the gun."""
    return move(right, fwd, up) @ base @ rot(pitch, yaw, roll, pivot)


def heavy_sway(t, k=1.0):
    """Slower and wider than the pistol's, with almost no tremor: two hands on a heavy gun."""
    s = sway(t, k=1.25 * k, period=4.0, tremor=0.3)
    s["roll"] *= 0.6
    return s


# ---------------------------------------------------------------------- left-hand poses
PALM = HOLD["L"]["anchor_fn"]
L_AWAY_CAM = away_left(PALM)
# on the magazine, below the well (given for the seated magazine; moved with the magazine)
L_MAG = dict(HOLD["L"], curls={2: (74, 80, 42), 3: (78, 84, 44), 4: (80, 86, 44), 5: (82, 88, 46)},
             anchor_target=R.MAG_GRIP + Vector((-0.008, -0.004, 0.0)))
# flat palm on the bolt catch (left side of the receiver, behind the magazine well)
L_SLAP = dict(curls={2: (18, 22, 12), 3: (20, 24, 12), 4: (22, 26, 14), 5: (24, 28, 14)},
              F_t=Vector((0.1, 0.7, 0.7)), A_hint=Vector((0.0, 0.7, -0.7)), anchor_fn=PALM,
              anchor_target=R.BOLT_CATCH + Vector((-0.012, 0.0, -0.004)),
              thumb_dirs=((0.0, 0.3, 0.95), (0.0, 0.4, 0.9), (0.0, 0.5, 0.85)))
HANDLE_BACK = Matrix.Translation((0, -R.HANDLE_TRAVEL, 0))
TRIGGER_PULL = Matrix.Translation(R.TRIGGER_PIVOT) @ Matrix.Rotation(math.radians(-13), 4, "X") @ Matrix.Translation(-R.TRIGGER_PIVOT)


# ---------------------------------------------------------------------- automatic fire
def burst(f, n, base, k=1.0, seed=7, shake=1.0):
    """n rounds, one every 2 frames (720 rpm); f = whole frames since the first shot. Returns a state: the muzzle
    climbs round after round about the shoulder, every shot kicks, the handle cycles, cases stream out to the right,
    the flash and the view shake on every shot. k scales the recoil (aimed fire is steadier)."""
    rng = random.Random(seed)
    jit = [(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0.8, 1.25), rng.uniform(0, 3.1), rng.uniform(-1, 1)) for _ in range(n)]
    end = 2 * n
    if f < 0:
        climb, i, phase = 0.0, -1, 2
    elif f < end:
        i, phase = f // 2, f % 2
        climb = 6.2 * (1 - math.exp(-(f / 2 + 1) / 3.2))
    else:
        i, phase = n - 1, 2
        climb = 6.2 * (1 - math.exp(-n / 3.2)) * table(f - end, [(0, 0.8), (2, 0.45), (4, 0.15), (6, -0.05), (9, 0)])
    kick = (1.0, 0.4, 0.0)[phase]
    j = jit[max(i, 0)]
    root_m = move(fwd=-0.013 * k * kick, up=0.0015 * k * climb) @ base \
        @ rot(pitch=k * (climb + 1.2 * kick), yaw=k * (0.9 * j[0] * kick + 0.12 * climb * math.sin(i * 1.7)), roll=k * 1.3 * j[1] * kick, pivot=BUTT)
    objs = {"R_ChargingHandle": Matrix.Translation((0, -R.HANDLE_TRAVEL * (1.0, 0.3, 0.0)[phase], 0)),
            "R_Trigger": TRIGGER_PULL if -1 <= f <= end else I4}
    props = {}
    if phase == 0:
        objs["R_Flash"] = Matrix.Translation(R.MUZZLE) @ Matrix.Rotation(j[3], 4, "Y") @ Matrix.Scale(j[2], 4)
        props[(light, "energy")] = 6.0
    for s in range(n):                                     # every round has its case in the air for 9 frames
        age = f - 2 * s
        if 0 <= age <= 9:
            tt = age / FPS
            js = jit[s]
            start = base @ Matrix.Translation(R.PORT)
            pos = start.translation + Vector((2.0 + 0.5 * js[0], 1.2 + 0.4 * js[1], 0.3 * js[4])) * tt + Vector((0, -9.8, 0)) * tt * tt / 2
            spin = Matrix.Rotation((22 + 8 * js[4]) * tt + js[3], 4, Vector((0.4, 1.0, 0.3 + 0.4 * js[0])).normalized())
            objs[CASINGS[s % len(CASINGS)]] = ("cam", Matrix.Translation(pos) @ spin @ start.to_3x3().to_4x4())
    cam = cam_rot(pitch=shake * (0.16 * climb * k + 0.4 * j[0] * kick), yaw=shake * 0.35 * j[1] * kick, roll=shake * 0.4 * j[4] * kick) \
        @ move(fwd=-0.003 * shake * kick)
    return dict(root=root_m, objs=objs, props=props, cam=cam)


# ---------------------------------------------------------------------- clips
def idle(t):
    return dict(root=gun(**heavy_sway(t)))


def walk(t):
    ph = TAU * t                                           # one second = two steps
    return dict(root=gun(right=0.011 * math.sin(ph), up=-0.009 * math.cos(2 * ph), fwd=0.004 * math.sin(2 * ph + 1.0),
                         pitch=1.0 * math.sin(2 * ph + 0.5), yaw=0.7 * math.sin(ph), roll=2.0 * math.sin(ph)),
                cam=move(right=0.008 * math.sin(ph), up=-0.016 * math.cos(2 * ph)) @ cam_rot(roll=0.45 * math.sin(ph)))


SPRINT_IN, SPRINT_RUN, SPRINT_OUT = 0.3, 1.4, 0.35


def sprint(t):
    """Gun lowered and tilted on its side, muzzle down and to the left, swinging with the arms."""
    k = smooth(seg(t, 0, SPRINT_IN)) * (1 - smooth(seg(t, SPRINT_IN + SPRINT_RUN, SPRINT_IN + SPRINT_RUN + SPRINT_OUT)))
    ph = TAU * (t - SPRINT_IN) / 0.7
    low = gun(right=-0.07 + 0.02 * math.sin(ph), up=-0.035 + 0.016 * math.cos(2 * ph), fwd=-0.03,
              pitch=-17 + 3 * math.sin(2 * ph), yaw=30 + 4 * math.sin(ph), roll=-26 + 5 * math.sin(ph))
    return dict(root=mix_m(L0, low, k),
                cam=move(right=k * 0.012 * math.sin(ph), up=k * 0.022 * math.cos(2 * ph)) @ cam_rot(roll=k * 0.8 * math.sin(ph)))


FIRE_ROUNDS = 8


def fire(t):
    return burst(round(t * FPS) - 2, FIRE_ROUNDS, L0)      # two frames of rest, the burst, the recovery


ADS_IN, ADS_WAIT, ADS_ROUNDS, ADS_AFTER, ADS_OUT = 0.25, 0.45, 6, 0.6, 0.3
ADS_T = ADS_IN + ADS_WAIT + ADS_ROUNDS * 2 / FPS + ADS_AFTER + ADS_OUT
# aimed: the gun straight ahead with the red cross on the eye's axis (75 mm above the bore), stock back to the cheek
L_ADS = Matrix.Translation((0.0, -0.075, -0.25)) @ Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0))).to_4x4()


def ads(t):
    k = ease_out(seg(t, 0, ADS_IN)) * (1 - smooth(seg(t, ADS_T - ADS_OUT, ADS_T)))
    s = heavy_sway(t, k=lerp(1.0, 0.2, k))
    base = move(s["right"], s["fwd"], s["up"]) @ mix_m(L0, L_ADS, k) @ rot(s["pitch"], s["yaw"], s["roll"], PIV)
    return burst(round((t - ADS_IN - ADS_WAIT) * FPS), ADS_ROUNDS, base, k=0.45, seed=11, shake=1.5)


DRAW_T = 1.1


def draw(t):
    """Heaved up from below the frame in both hands; a slow overshoot, then still."""
    k = back_out(seg(t, 0.0, 0.62), 1.1)
    low = gun(right=0.03, up=-0.33, fwd=-0.08, pitch=-46, roll=14, yaw=-6)
    root_m = mix_m(low, L0, min(k, 1.0)) @ rot(pitch=max(k - 1.0, 0) * 45, pivot=BUTT)
    settle = table(t, [(0.66, 0), (0.74, 1), (0.88, -0.35), (1.0, 0)])
    return dict(root=move(up=-0.004 * settle) @ root_m @ rot(pitch=-0.9 * settle, pivot=BUTT))


MAG_OUT = 0.075                                            # along its axis, clear of the well
MAG_AWAY = Vector((-0.13, -0.1, -0.3))                     # where the magazine is swapped (gun space, out of frame)
RELOAD_T, RELOAD_EMPTY_T = 1.9, 2.3


def reload(t, empty=False):
    """Gun lifted and canted; the left hand slides down onto the magazine, pulls it out and takes it out of frame,
    brings a magazine back, pushes it home and returns to the well. Empty: the handle is locked back and the hand
    then slaps the bolt catch, the handle runs forward."""
    back = (1.38, 1.72) if not empty else (1.78, 2.12)
    tilt = smooth(seg(t, 0.0, 0.22)) * (1 - smooth(seg(t, *back)))
    bump = table(t, [(1.08, 0), (1.12, 1), (1.2, -0.3), (1.28, 0)])           # the magazine locks in
    jolt = table(t, [(1.56, 0), (1.6, 1), (1.68, -0.3), (1.76, 0)]) if empty else 0.0   # the bolt runs forward
    root_m = gun(right=-0.035 * tilt, up=0.07 * tilt + 0.005 * bump, fwd=0.01 * tilt + 0.004 * jolt,
                 pitch=16 * tilt + 1.2 * bump - 1.2 * jolt, roll=30 * tilt, yaw=5 * tilt)
    # magazine: out along its axis, away (out of frame), back, in
    out_k = ease_out(seg(t, 0.30, 0.42), 2) * (1 - seg(t, 1.02, 1.10))
    away_k = smooth(seg(t, 0.42, 0.62)) * (1 - smooth(seg(t, 0.80, 1.02)))
    mag_m = Matrix.Translation((-R.MAG_AXIS * MAG_OUT * out_k).lerp(MAG_AWAY, away_k)) \
        @ rot(roll=-22 * away_k, pitch=-14 * away_k, pivot=R.MAG_GRIP)
    objs = {"R_Magazine": mag_m}
    on_mag = xform_spec(L_MAG, mag_m)
    left = mix_spec(mix_spec(HOLD["L"], on_mag, smooth(seg(t, 0.08, 0.26))), HOLD["L"], smooth(seg(t, 1.16, 1.38)))
    if empty:
        objs["R_ChargingHandle"] = Matrix.Translation((0, -R.HANDLE_TRAVEL * (1 - seg(t, 1.56, 1.6)), 0))
        slap = smooth(seg(t, 1.40, 1.55)) * (1 - smooth(seg(t, 1.62, 1.86)))
        left = mix_spec(left, L_SLAP, slap)
    return dict(root=root_m, objs=objs, hands={"L": left})


def reload_empty(t):
    return reload(t, empty=True)


INSPECT_T = 3.2


def inspect(t):
    """The left hand lets go; the right hand turns the gun to show its left side, then cants it the other way."""
    a = smooth(seg(t, 0.25, 0.85)) * (1 - smooth(seg(t, 1.35, 1.9)))
    b = smooth(seg(t, 1.45, 2.05)) * (1 - smooth(seg(t, 2.4, 2.95)))
    up = smooth(seg(t, 0.1, 0.7)) * (1 - smooth(seg(t, 2.5, 3.05)))
    root_m = gun(right=-0.04 * up - 0.03 * a, up=0.05 * up, fwd=0.02 * up,
                 roll=34 * a - 62 * b, yaw=30 * a + 16 * b, pitch=15 * a + 22 * b)
    left = mix_spec(HOLD["L"], xform_spec(L_AWAY_CAM, root_m.inverted()),
                    smooth(seg(t, 0.0, 0.3)) * (1 - smooth(seg(t, 2.8, 3.15))))
    return dict(root=root_m, hands={"L": left})


CLIPS = [("Idle", 4.0, idle, True), ("Walk", 1.0, walk, True), ("Sprint", SPRINT_IN + SPRINT_RUN + SPRINT_OUT, sprint, False),
         ("Fire", 1.1, fire, False), ("ADS", ADS_T, ads, False), ("Draw", DRAW_T, draw, False),
         ("ReloadTactical", RELOAD_T, reload, False), ("ReloadEmpty", RELOAD_EMPTY_T, reload_empty, False),
         ("Inspect", INSPECT_T, inspect, False)]
clips = B.run(CLIPS, sys.argv)
if "nosave" not in sys.argv:
    bpy.ops.wm.save_mainfile()
print("clips:", clips)
