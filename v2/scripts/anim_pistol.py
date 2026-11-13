"""V2: the pistol's first-person animations, baked onto the timeline of v2/scene.blend (24 fps, one clip after another,
a marker at the start of each; the frame ranges are printed and stored in the scene property `v2_clips_pistol`).

    blender -b v2/scene.blend -P v2/scripts/anim_pistol.py            (run after build_viewmodel.py; saves the file)

Clips: Idle (loop), Walk (loop), Sprint, Fire, ADS, Draw, Reload (from empty: slide locked back), Inspect.
Every clip is a function of time returning a state for anim_lib.Baker: gun placement in the eye's frame, camera
offset, moving parts (slide, trigger, magazines, spent case, muzzle flash + light) and a pose for each hand.
The right hand never leaves the grip. The left hand has three poses besides the hold: away (low, out of frame),
carrying a magazine on the palm, and the flat palm that seats it.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import hands as H  # noqa: E402
import build_pistol as P  # noqa: E402
import fx_plan as PLAN  # noqa: E402
from anim_lib import (Baker, FPS, I4, away_left, back_out, cam_rot, ease_out, lerp, mix_m, mix_spec, move, rot, seg,  # noqa: E402
                      smooth, sway, table, xform_spec)

W = "pistol"
AN = P.ANCHORS
HOLD = dict(H.pistol_hold(AN, H.cam_in_gun(W)))
L0 = H.view_local(W)
PIV = AN["tang"] + Vector((0, 0.015, -0.04))             # the gun turns about the middle of the grip (the wrist)
TAU = math.tau

sc = bpy.context.scene
for name, cname in H.COLL.items():
    bpy.data.collections[cname].hide_render = bpy.data.collections[cname].hide_viewport = name != W
light = bpy.data.objects["P_FlashLight"].data
REST_FLASH = ("hidden", Matrix.Translation(P.MUZZLE))
B = Baker(W, HOLD, {"P_Slide": I4, "P_Trigger": I4, "P_Magazine": I4, "P_Magazine2": None, "P_Casing": None,
                    "P_Flash": REST_FLASH}, {(light, "energy"): 0.0})


def gun(right=0.0, fwd=0.0, up=0.0, pitch=0.0, yaw=0.0, roll=0.0, base=L0):
    """Gun placement: the rest placement shifted in the eye's frame and turned about the grip."""
    return move(right, fwd, up) @ base @ rot(pitch, yaw, roll, PIV)


# ---------------------------------------------------------------------- left-hand poses
PALM = HOLD["L"]["anchor_fn"]                              # all left-hand poses are anchored at the palm centre
L_AWAY_CAM = away_left(PALM)


def l_away(root_m):
    return xform_spec(L_AWAY_CAM, root_m.inverted())


# magazine on the palm: the base plate sits on the palm, fingers up the front of the magazine, thumb up its left
# side (given for the magazine in its seated place; moved with the magazine)
_d = P.MAG_AXIS
_f = Vector((0.75, 0.6, 0.0))
_f = (_f - _d * _f.dot(_d)).normalized()
MAG_BOTTOM = Vector((0, -0.025, -0.1005))
L_MAG = dict(curls={2: (52, 62, 34), 3: (56, 66, 36), 4: (58, 68, 36), 5: (60, 70, 38)},
             F_t=_f, A_hint=_f.cross(_d), anchor_fn=PALM, anchor_target=MAG_BOTTOM - _d * 0.004,
             thumb_dirs=((-0.55, 0.25, 0.8), (-0.3, 0.2, 0.93), (-0.1, 0.25, 0.96)))
L_SEAT = dict(L_MAG, curls={2: (14, 18, 10), 3: (16, 20, 10), 4: (18, 22, 12), 5: (20, 24, 12)},
              thumb_dirs=((-0.7, 0.5, 0.5), (-0.5, 0.7, 0.5), (-0.4, 0.8, 0.45)))


# ---------------------------------------------------------------------- clips
def idle(t):
    return dict(root=gun(**sway(t)))


def walk(t):
    ph = TAU * t                                           # one second = two steps
    return dict(root=gun(right=0.008 * math.sin(ph), up=-0.006 * math.cos(2 * ph), fwd=0.003 * math.sin(2 * ph + 1.0),
                         pitch=0.8 * math.sin(2 * ph + 0.5), yaw=0.6 * math.sin(ph), roll=1.6 * math.sin(ph)),
                cam=move(right=0.005 * math.sin(ph), up=-0.011 * math.cos(2 * ph)) @ cam_rot(roll=0.3 * math.sin(ph)))


SPRINT_IN, SPRINT_RUN, SPRINT_OUT = 0.25, 1.4, 0.3


def sprint(t):
    """Gun pulled in across the chest, muzzle down and to the left, swinging with the run."""
    k = smooth(seg(t, 0, SPRINT_IN)) * (1 - smooth(seg(t, SPRINT_IN + SPRINT_RUN, SPRINT_IN + SPRINT_RUN + SPRINT_OUT)))
    ph = TAU * (t - SPRINT_IN) / 0.7                       # a stride every 0.35 s
    low = gun(right=-0.06 + 0.016 * math.sin(ph), up=-0.012 + 0.014 * math.cos(2 * ph), fwd=-0.04,
              pitch=-16 + 2.5 * math.sin(2 * ph), yaw=36 + 3 * math.sin(ph), roll=-12 + 4 * math.sin(ph))
    return dict(root=mix_m(L0, low, k),
                cam=move(right=k * 0.009 * math.sin(ph), up=k * 0.018 * math.cos(2 * ph)) @ cam_rot(roll=k * 0.6 * math.sin(ph)))


def shot(f, root_fn=gun, k=1.0):
    """One shot, f = frames since the trigger broke: recoil, slide, trigger, flash, spent case, view punch."""
    r = dict(pitch=k * table(f, [(0, 0), (1, 7.0), (2, 8.6), (3, 5.2), (4, 2.4), (5, 0.4), (6, -0.7), (7, -0.5), (8, -0.2), (9, 0)]),
             fwd=k * table(f, [(0, 0), (1, -0.022), (2, -0.028), (3, -0.018), (4, -0.008), (5, -0.001), (6, 0.002), (7, 0.001), (8, 0)]),
             up=k * table(f, [(0, 0), (1, 0.006), (2, 0.010), (3, 0.006), (4, 0.002), (5, 0)]),
             roll=k * table(f, [(0, 0), (1, 1.8), (2, 1.2), (3, -0.6), (4, -0.3), (5, 0)]),
             yaw=k * table(f, [(0, 0), (1, 0.9), (2, 0.6), (4, -0.2), (6, 0)]))
    root_m = root_fn(**r)
    objs = {"P_Slide": Matrix.Translation((0, -P.SLIDE_TRAVEL * table(f, [(0, 0), (1, 1.0), (2, 0.38), (3, 0)]), 0)),
            "P_Trigger": Matrix.Translation(P.TRIGGER_PIVOT) @ Matrix.Rotation(math.radians(-13 * table(f, [(-1, 0), (0, 1), (2, 1), (4, 0)])), 4, "X")
            @ Matrix.Translation(-P.TRIGGER_PIVOT)}
    props = {}
    if 0.5 < f < 1.5:                                      # the flash lives for one frame
        objs["P_Flash"] = Matrix.Translation(P.MUZZLE) @ Matrix.Rotation(0.7, 4, "Y")
        props[(light, "energy")] = 4.0
    if 1 <= f <= 11:                                       # the case flies up and to the right, tumbling, in the eye's frame
        tt = (f - 1) / FPS
        start = root_fn(pitch=7.0 * k, fwd=-0.022 * k, up=0.006 * k) @ Matrix.Translation(P.PORT)
        pos = start.translation + Vector((1.5, 1.7, 0.45)) * tt + Vector((0, -9.8, 0)) * tt * tt / 2
        spin = Matrix.Rotation(26 * tt, 4, Vector((0.35, 1.0, 0.5)).normalized())
        objs["P_Casing"] = ("cam", Matrix.Translation(pos) @ spin @ start.to_3x3().to_4x4())
    return dict(root=root_m, objs=objs, props=props,
                cam=cam_rot(pitch=k * table(f, [(0, 0), (1, 0.9), (2, 0.6), (4, 0.15), (6, 0)])))


def fire(t):
    return shot(t * FPS - 1)                               # one frame of rest, then the shot


ADS_IN, ADS_HOLD, ADS_OUT = 0.2, 1.6, 0.25
# aimed: the gun straight ahead with the red dot on the eye's axis (the dot is 77 mm above the gun's origin)
L_ADS = Matrix.Translation((0.0, -0.077, -0.27)) @ Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0))).to_4x4()


def ads(t):
    k = ease_out(seg(t, 0, ADS_IN)) * (1 - smooth(seg(t, ADS_IN + ADS_HOLD, ADS_IN + ADS_HOLD + ADS_OUT)))
    s = sway(t, k=lerp(1.0, 0.22, k))                      # the sway tightens while aiming
    return dict(root=move(s["right"], s["fwd"], s["up"]) @ mix_m(L0, L_ADS, k) @ rot(s["pitch"], s["yaw"], s["roll"], PIV))


DRAW_T = 0.85


def draw(t):
    """Up from below the frame on the right hand; the left hand meets it; a small overshoot, then still."""
    k = back_out(seg(t, 0.0, 0.42), 1.4)
    low = gun(right=0.05, up=-0.34, fwd=-0.1, pitch=-58, roll=24, yaw=-8)
    root_m = mix_m(low, L0, min(k, 1.0)) @ rot(pitch=max(k - 1.0, 0) * 60, pivot=PIV)
    left = mix_spec(l_away(root_m), HOLD["L"], smooth(seg(t, 0.26, 0.52)))
    settle = table(t, [(0.52, 0), (0.56, 1), (0.66, -0.4), (0.76, 0)])      # the support hand lands: a small bump
    root_m = move(up=-0.003 * settle) @ root_m @ rot(pitch=-0.8 * settle, pivot=PIV)
    return dict(root=root_m, hands={"L": left})


RELOAD_T = 1.5
SLIDE_LOCK = Matrix.Translation((0, -0.036, 0))
MAG_OUT = 0.115                                            # how far along its axis the magazine is clear of the grip
MAG_START = Vector((-0.1, -0.04, -0.22))                   # where the new magazine waits (gun space, out of frame)


def reload(t):
    """From empty: the slide is locked back. Tilt the gun, drop the magazine, bring a new one up on the palm, seat
    it, back to the grip, the slide runs forward."""
    tilt = smooth(seg(t, 0.0, 0.16)) * (1 - smooth(seg(t, 0.95, 1.25)))
    bump = table(t, [(0.80, 0), (0.84, 1), (0.92, -0.3), (1.0, 0)])          # the magazine hits home
    jolt = table(t, [(1.12, 0), (1.16, 1), (1.24, -0.3), (1.32, 0)])         # the slide slams forward
    root_m = gun(right=-0.055 * tilt, up=0.08 * tilt + 0.006 * bump, fwd=0.02 * tilt + 0.004 * jolt,
                 pitch=24 * tilt + 2.0 * bump - 1.8 * jolt, roll=30 * tilt, yaw=10 * tilt)
    objs = {"P_Slide": SLIDE_LOCK if t < 1.13 else Matrix.Translation((0, -0.036 * (1 - seg(t, 1.13, 1.16)), 0))}
    # old magazine: released at 0.12 s, slides out of the grip and falls
    if t < 0.12:
        pass
    elif t < 0.46:
        tt = t - 0.12
        s = 4.9 * tt * tt * 1.6
        fall = max(s - MAG_OUT, 0.0)
        objs["P_Magazine"] = Matrix.Translation(-P.MAG_AXIS * min(s, MAG_OUT + 0.02) + Vector((0, -0.2 * fall, -fall))) \
            @ rot(pitch=-140 * fall, pivot=MAG_BOTTOM)
    else:
        objs["P_Magazine"] = None
    # new magazine: waits low, rises to the mouth of the grip, goes in most of the way, is pushed home
    if t >= 0.36:
        rise = ease_out(seg(t, 0.42, 0.64), 2)
        s = table(t, [(0.64, MAG_OUT), (0.75, 0.034), (0.80, 0.03), (0.84, 0.0)])
        mag_m = Matrix.Translation((MAG_START - P.MAG_AXIS * MAG_OUT).lerp(-P.MAG_AXIS * s, rise)) \
            @ rot(roll=-18 * (1 - rise), pitch=-12 * (1 - rise), pivot=MAG_BOTTOM)
        if t < 1.5 - 1e-6:
            objs["P_Magazine2"] = mag_m
        carry = xform_spec(mix_spec(L_MAG, L_SEAT, smooth(seg(t, 0.70, 0.80))), mag_m)
    else:
        mag_m = Matrix.Translation(MAG_START - P.MAG_AXIS * MAG_OUT) @ rot(roll=-18, pitch=-12, pivot=MAG_BOTTOM)
        carry = xform_spec(L_MAG, mag_m)
    if t >= 0.36 and t >= RELOAD_T - 1.5 / FPS:
        pass
    away = l_away(root_m)
    if t < 0.36:
        left = mix_spec(mix_spec(HOLD["L"], away, smooth(seg(t, 0.02, 0.16))), carry, smooth(seg(t, 0.24, 0.36)))
    else:
        left = mix_spec(carry, HOLD["L"], smooth(seg(t, 0.88, 1.12)))
    # right thumb dips onto the slide stop
    dip = table(t, [(1.04, 0), (1.11, 1), (1.18, 0)])
    right = dict(HOLD["R"], thumb_dirs=[Vector(d).normalized() + Vector((0.12, 0, -0.3)) * dip for d in HOLD["R"]["thumb_dirs"]])
    return dict(root=root_m, objs=objs, hands={"L": left, "R": right})


INSPECT_T = 3.0


def inspect(t):
    """The left hand lets go; the right hand turns the gun to show its left side, then its right side."""
    a = smooth(seg(t, 0.2, 0.75)) * (1 - smooth(seg(t, 1.25, 1.75)))      # left side to the eye
    b = smooth(seg(t, 1.3, 1.85)) * (1 - smooth(seg(t, 2.25, 2.75)))      # right side
    up = smooth(seg(t, 0.1, 0.6)) * (1 - smooth(seg(t, 2.3, 2.85)))
    root_m = gun(right=-0.03 * up - 0.09 * b, up=0.04 * up, fwd=0.03 * up,
                 roll=22 * a - 24 * b, yaw=48 * a - 46 * b, pitch=8 * a + 12 * b)
    left = mix_spec(HOLD["L"], l_away(root_m), smooth(seg(t, 0.0, 0.3)) * (1 - smooth(seg(t, 2.6, 2.95))))
    return dict(root=root_m, hands={"L": left})


CLIPS = [("Idle", 3.0, idle, True), ("Walk", 1.0, walk, True), ("Sprint", SPRINT_IN + SPRINT_RUN + SPRINT_OUT, sprint, False),
         ("Fire", 0.5, fire, False), ("ADS", ADS_IN + ADS_HOLD + ADS_OUT, ads, False), ("Draw", DRAW_T, draw, False),
         ("Reload", RELOAD_T, reload, False), ("Inspect", INSPECT_T, inspect, False)]
FF_BASE = dict(yaw=12.0, pitch=-15.0, right=-0.01, up=-0.01)   # the gun turned toward the spider, low on the left


def firefight(t):
    """Steady fire at the spider while the robots shoot back (fx_plan.py has the frames; no view punch: the
    camera's keys in this section are shared with the other weapon view)."""
    i = round(t * FPS)
    k = smooth(seg(t, 0.0, 0.2)) * (1 - smooth(seg(t, PLAN.FF_N / FPS - 0.25, PLAN.FF_N / FPS)))
    base = {n: v * k for n, v in FF_BASE.items()}
    last = max([x for x in PLAN.FF_PISTOL if x - 1 <= i] or [-99])
    st = shot(i - (last - 1), root_fn=lambda **r: gun(**{n: r.get(n, 0.0) + base.get(n, 0.0) for n in set(r) | set(base)}))
    st.pop("cam", None)
    return st


clips = B.run(CLIPS, sys.argv, extra=[("Firefight", PLAN.FF_START, PLAN.FF_N, firefight)])
if "nosave" not in sys.argv:
    bpy.ops.wm.save_mainfile(compress=True)
print("clips:", clips)
