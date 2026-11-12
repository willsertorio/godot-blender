"""V2 concept: the machine gun (a compact white-polymer carbine), modelled after v2/reference/scene_concept_rifle.png.

    xvfb-run -a blender -b -P v2/scripts/build_rifle.py -- /tmp/rifle     # stand-alone review renders (EEVEE, 4 views)
    (build_viewmodel.py imports build() and places the result in the player's hands)

Millimetres in the code, metres in the scene. Gun frame: +Y = muzzle, +Z = up, X = 0 the centre plane (-X is the
gun's left side, the one the player sees), the bore axis at Z = 0. The pistol grip, trigger and trigger guard have
the pistol's proportions (build_pistol.py) moved by (Y -32, Z -64), so the same right-hand pose fits.
The body is slim (60 mm tall receiver) and the sight large and low, as in the reference: that is what lets the
trigger hand show under the gun from the player's eye.
Parts: lofted rear body in two shells (white upper, grey lower) over a dark core that shows through the panel gaps
and vents, butt pad, shoulder pods with the ammo screen, receiver with charging slot, light strip and ejection port,
full-length top rail, vented handguard, barrel, muzzle brake, lower housing, trigger guard, trigger, grip with
textured panels, magazine well, magazine, holographic sight (hood, lens, red cross reticle), folded back-up sights,
pins, selector, lights.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import v2lib as L  # noqa: E402
from build_pistol import Part, S  # noqa: E402

DY, DZ = -32.0, -64.0            # pistol grip frame -> rifle frame
RT, RB = 30.0, -30.0             # receiver top / bottom
MAGWELL = dict(y0=62.0, y1=120.0, z0=-96.0, z1=RB, hw=18.0)
ANCHORS = {                      # metres, gun frame: used by build_viewmodel.py to place the hands
    "tang": Vector((0, -50 + DY, 18 + DZ)) * S,
    "grip_centre": Vector((0, -22 + DY, -42 + DZ)) * S,
    "grip_half_width": 15 * S,
    "rake": math.atan2(22, 66),
    "trigger": Vector((0, 46 + DY, -6 + DZ)) * S,
    "magwell_left": Vector((-MAGWELL["hw"], 92, -58)) * S,       # centre of the left face the support palm lies on
    "magwell_front": MAGWELL["y1"] * S,
    "magwell_half_width": MAGWELL["hw"] * S,
}


def materials():
    for n in ("RfWhite", "RfGrey", "RfDark", "RfGripTex", "RfSteel", "RfBlack", "RfTan", "RfRubber", "RfLens", "RfReticle",
              "RfCyan", "RfScreen", "RfPod", "RfMatte", "RfShell2"):
        if bpy.data.materials.get(n):
            bpy.data.materials.remove(bpy.data.materials[n])
    m = {}
    m["white"] = L.pbr("RfWhite", "PaintedPlaster017", scale=0.16, tint=(0.86, 0.87, 0.89), rough=(0.3, 0.5), normal=0.3,
                       grunge=0.16, grunge_scale=22, round_edges=0.0007, edge_wear=0.55, wear_color=(0.22, 0.23, 0.25),
                       wear_radius=0.0012, wear_noise=200, cavity=0.7, cavity_dist=0.006, wear_metal=0.6)
    m["grey"] = L.pbr("RfGrey", "PaintedPlaster017", scale=0.12, tint=(0.36, 0.37, 0.39), rough=(0.35, 0.55), normal=0.3,
                      round_edges=0.0005, edge_wear=0.5, wear_color=(0.6, 0.6, 0.6), cavity=0.6)
    m["dark"] = L.pbr("RfDark", "Plastic012B", scale=0.05, tint=(0.62, 0.66, 0.74), bright=1.2, rough=(0.5, 0.72), normal=0.8,
                      round_edges=0.0005, edge_wear=0.35, wear_color=(0.3, 0.31, 0.33), cavity=0.5)
    m["grip"] = L.pbr("RfGripTex", "Rubber004", scale=0.012, bright=0.55, rough=(0.7, 0.95), normal=4.0)
    m["steel"] = L.pbr("RfSteel", "Metal032", scale=0.06, tint=(0.2, 0.2, 0.21), rough=(0.28, 0.45), metallic=1.0,
                       round_edges=0.0003)
    m["black"] = L.pbr("RfBlack", "Metal032", scale=0.06, tint=(0.05, 0.05, 0.055), rough=(0.35, 0.55), metallic=0.6,
                       round_edges=0.0003, edge_wear=0.3, wear_color=(0.45, 0.45, 0.45), cavity=0.3)
    m["pod"] = L.pbr("RfPod", "PaintedPlaster017", scale=0.12, tint=(0.17, 0.18, 0.2), rough=(0.32, 0.5), normal=0.3,
                     cavity=0.5)
    m["matte"] = L.plain("RfMatte", (0.012, 0.012, 0.014), rough=0.45)
    m["tan"] = L.pbr("RfTan", "Metal032", scale=0.07, tint=(0.6, 0.43, 0.25), rough=(0.4, 0.62), metallic=0.35,
                     round_edges=0.0004, edge_wear=0.3, wear_color=(0.7, 0.66, 0.58), cavity=0.5)
    m["shell2"] = L.pbr("RfShell2", "PaintedPlaster017", scale=0.16, tint=(0.6, 0.62, 0.65), rough=(0.32, 0.52), normal=0.3,
                        grunge=0.16, grunge_scale=22, round_edges=0.0007, edge_wear=0.5, wear_color=(0.2, 0.21, 0.23),
                        wear_radius=0.0012, wear_noise=200, cavity=0.7, cavity_dist=0.006, wear_metal=0.6)
    m["rubber"] = L.pbr("RfRubber", "Rubber004", scale=0.02, bright=1.0, rough=(0.6, 0.9), normal=1.5)
    m["lens"] = L.plain("RfLens", (0.6, 0.85, 0.8), rough=0.0, transmission=1.0, ior=1.45)
    m["reticle"] = L.plain("RfReticle", (0, 0, 0), emit=(1.0, 0.06, 0.03), emit_strength=9.0)
    m["cyan"] = L.plain("RfCyan", (0, 0.02, 0.03), emit=(0.15, 0.85, 1.0), emit_strength=3.5)
    m["screen"] = L.plain("RfScreen", (0, 0.01, 0.015), rough=0.08, emit=(0.1, 0.6, 0.72), emit_strength=0.9)
    return m


STOCK = [(-340, -12, 18, 28, 46, 3.0), (-300, -8, 24, 36, 50, 3.0), (-230, -3, 27.5, 38, 44, 3.2),
         (-160, 0, 29, 36, 36, 3.4), (-90, 1, 28, 34, 34, 3.6), (-28, 0, 25, 32, 31, 4.2)]
SPLIT = -13.0                    # height of the seam between the two shells of the rear body


def build(collection, parent=None):
    M = materials()
    out = []

    def done(p):
        out.append(p.finish(collection, parent))

    def P(y, z):                     # a point of the pistol's grip / guard / trigger profiles, in the rifle frame
        return (y + DY, z + DZ)

    # ------------------------------------------------------------------ rear body (stock): two shells over a core
    su = Part("R_StockUpper", M["white"], bevel=0.6, segs=2)
    su.loft(STOCK)
    c = su.cut()
    c.box((-60, -370, -110), (60, 0, SPLIT + 0.7))
    c = su.cut()                                   # panel gaps: the dark core shows through
    c.box((-50, -216, -90), (50, -214.2, 70))
    c = su.cut()
    c.box((-50, -122, -90), (50, -120.2, 70), rx=24)
    c = su.cut()                                   # cooling slits behind the pods
    for sx in (-1, 1):
        for i in range(5):
            c.box((sx * 29 - 7, -164 + i * 8.5, -8), (sx * 29 + 7, -160.6 + i * 8.5, 9), rx=28)
    done(su)
    sl = Part("R_StockLower", M["shell2"], bevel=0.6, segs=2)
    sl.loft(STOCK)
    c = sl.cut()
    c.box((-60, -370, SPLIT - 0.7), (60, 0, 110))
    c = sl.cut()
    c.box((-50, -252, -90), (50, -250.2, 70), rx=-18)
    done(sl)
    core = Part("R_StockCore", M["black"], bevel=0)
    core.loft([(y + (4 if i == 0 else -4 if i == len(STOCK) - 1 else 0), zc, hw - 1.6, ht - 1.6, hb - 1.6, n)
               for i, (y, zc, hw, ht, hb, n) in enumerate(STOCK)])
    done(core)
    bp = Part("R_ButtPad", M["rubber"], bevel=1.5, segs=3)
    bp.loft([(-356, -14, 15, 23, 40, 3.0), (-349, -13, 18.5, 28, 46, 3.0), (-339, -12, 19, 29, 47, 3.0)], smooth=1)
    done(bp)
    ck = Part("R_CheekPad", M["rubber"], bevel=1.2, segs=3)                 # rubber comb on top of the stock
    ck.loft([(-300, 24, 11, 6, 6, 2.6), (-270, 31, 14, 7, 6, 2.6), (-200, 35, 14.5, 6.5, 6, 2.6), (-150, 34, 12, 5, 6, 2.6)],
            segs=28, smooth=2)
    done(ck)

    # shoulder pods on the upper corners of the body; the left one carries the ammo screen, tilted up toward the eye
    PC, PR = (17.5, -62.0, 18.0), (16.5, 60.0, 19.5)
    th = math.radians(45)                                                   # where on the pod's section the screen sits
    px, pz = -PC[0] - PR[0] * math.cos(th), PC[2] + PR[2] * math.sin(th)
    nrm = Vector((-math.cos(th) / PR[0], 0, math.sin(th) / PR[2])).normalized()
    phi = math.degrees(math.atan2(nrm.x, nrm.z))                            # box turn about Y: local Z -> the normal
    tan = Vector((math.cos(math.radians(phi)), 0, -math.sin(math.radians(phi))))

    def sbox(part, u, v, h, su_, sv, sh):
        """A box on the screen plane: u across, v along the gun (from the pod centre), h out of the surface (mm)."""
        c_ = Vector((px, PC[1] + v, pz)) + tan * u + nrm * h
        part.box((c_.x - su_ / 2, c_.y - sv / 2, c_.z - sh / 2), (c_.x + su_ / 2, c_.y + sv / 2, c_.z + sh / 2), ry=phi)

    for sx, nm in ((-1, "L"), (1, "R")):
        base = Part(f"R_PodBase{nm}", M["shell2"], bevel=0)                 # a lighter step under the dark pod
        base.ellipsoid((sx * (PC[0] - 2.5), PC[1], PC[2] - 1), (PR[0], PR[1] + 6, PR[2] + 4.5), segs=40, rings=24)
        if sx < 0:                                                          # keep the step clear of the screen
            c = base.cut()
            sbox(c, 0, 0, 5.0, 23, 62, 18)
        done(base)
        pod = Part(f"R_Pod{nm}", M["pod"], bevel=0.5)
        pod.ellipsoid((sx * PC[0], PC[1], PC[2]), PR, segs=40, rings=24)
        if sx < 0:                                                          # flat seat for the screen
            c = pod.cut()
            sbox(c, 0, 0, 3.0, 19.5, 58.5, 12)
        done(pod)
    bz = Part("R_ScreenBezel", M["matte"], bevel=1.6, segs=3)     # low frame, sunk into the pod
    sbox(bz, 0, 0, -3.4, 20, 59, 5.4)
    c = bz.cut()
    sbox(c, 0, 0, -0.2, 16.6, 55, 1.6)
    done(bz)
    scr = Part("R_Screen", M["screen"], bevel=0)
    sbox(scr, 0, 0, -1.2, 16.6, 55, 0.4)
    done(scr)
    sd = Part("R_ScreenInk", M["cyan"], bevel=0)   # read-out: bar graph, frame line, two digit blocks
    for i in range(9):
        hgt = 3.2 + (i * 5 % 4) * 1.0
        sbox(sd, -6.0 + hgt / 2, -24 + i * 3.1, -0.9, hgt, 2.0, 0.3)
    sbox(sd, 6.0, 0, -0.9, 0.6, 49, 0.3)
    for i in range(2):
        sbox(sd, -2.3, 11 + i * 8.5, -0.9, 8.2, 5.6, 0.3)
    done(sd)
    tb = Part("R_TopPlate", M["grey"], bevel=0.8)
    tb.box((-8, -146, 33.6), (8, -126, 37.4))
    done(tb)

    # ------------------------------------------------------------------ receiver
    rc = Part("R_Receiver", M["white"], bevel=0.7, segs=3)
    rc.prism_y([(-23, RB + 6), (-18, RB), (18, RB), (23, RB + 6), (23, 20), (15, RT), (-15, RT), (-23, 20)], -32, 156)
    c = rc.cut()                                   # charging slot (left), ejection port (right)
    c.box((-26, 34, 5), (-13, 136, 15))
    c = rc.cut()
    c.box((11, 22, 1), (26, 78, 20))
    c = rc.cut()                                   # recessed side panels, a panel line, the groove of the light strip
    for sx in (-1, 1):
        c.box((sx * 23.6 - 2.2, 8, -24), (sx * 23.6 + 2.2, 144, -6))
    c = rc.cut()
    for sx in (-1, 1):
        c.box((sx * 23 - 0.7, -14, -26), (sx * 23 + 0.7, -12.6, 21))
    c = rc.cut()
    c.box((-24, 39, -2.6), (-21.6, 99, 0.2))
    c = rc.cut()                                   # finger flutes above the charging slot
    for i in range(6):
        c.box((-25, 12 + i * 3.6, 17.4), (-21.8, 13.8 + i * 3.6, 21.5), rx=0)
    done(rc)
    sp = Part("R_SidePanels", M["grey"], bevel=0.5)
    for sx in (-1, 1):
        sp.box((sx * 21.6 - 0.9, 9.5, -22.5), (sx * 21.6 + 0.9, 142.5, -7.5))
        for i in range(4):                                                  # raised ribs on the panel
            sp.box((sx * 22.6 - 0.5, 104 + i * 8, -20), (sx * 22.6 + 0.5, 108 + i * 8, -10))
    done(sp)
    bc = Part("R_Bolt", M["steel"], bevel=0.6)
    bc.box((-13.6, 34.5, 5.4), (-12, 135.5, 14.6))                             # slot floor
    bc.box((8, 24, 2.5), (17, 76, 18.5))                                       # bolt carrier in the port
    for i in range(5):
        bc.box((17, 30 + i * 8, 5), (18, 34 + i * 8, 16))
    done(bc)
    ch = Part("R_ChargingHandle", M["tan"], bevel=1.0, segs=3)
    ch.box((-25, 102, 6.2), (-12, 116, 13.8))
    ch.prism_y([(-24, 4.5), (-37, 7), (-37, 13), (-24, 15.5)], 100, 118)
    done(ch)
    rl = Part("R_Rail", M["black"], bevel=0.35)
    rl.prism_y([(-10.6, RT - 0.5), (10.6, RT - 0.5), (10.6, RT + 4.5), (7.8, RT + 7.5), (-7.8, RT + 7.5), (-10.6, RT + 4.5)],
               -30, 256)
    c = rl.cut()
    for i in range(28):
        c.box((-12, -25 + i * 10, RT + 4.6), (12, -19.8 + i * 10, RT + 9))
    done(rl)

    # ------------------------------------------------------------------ handguard, barrel, muzzle brake
    hg = Part("R_Handguard", M["white"], bevel=0.7, segs=3)
    hg.prism_y([(-21, -18), (-14, -26), (14, -26), (21, -18), (21, 18), (13, RT - 0.6), (-13, RT - 0.6), (-21, 18)], 156.8, 264)
    c = hg.cut()
    c.cyl((0, 150, 0), (0, 270, 0), 14.0, segs=36)
    c = hg.cut()                                   # side vents (slanted), upper vents on the chamfers, lower slots
    for sx in (-1, 1):
        for i in range(5):
            c.box((sx * 21 - 8, 168 + i * 17, 1), (sx * 21 + 8, 176 + i * 17, 14.5), rx=-24)
            c.box((sx * 17 - 7, 167 + i * 17, 21), (sx * 17 + 7, 177 + i * 17, 26.5), ry=sx * 55)
        for i in range(3):
            c.box((sx * 21 - 8, 170 + i * 29, -15), (sx * 21 + 8, 191 + i * 29, -9))
    c = hg.cut()                                   # slanted nose
    c.prism_x([(265, -27), (265, -6), (246, -27)], -30, 30)
    done(hg)
    br = Part("R_Barrel", M["steel"], bevel=0.4)
    br.cyl((0, 120, 0), (0, 272, 0), 8.5, segs=32)
    br.cyl((0, 150, 0), (0, 186, 0), 11.5, segs=32)                            # barrel nut / gas block
    for i in range(6):
        br.cyl((0, 196 + i * 10, 0), (0, 201 + i * 10, 0), 10.0, segs=32)      # cooling rings
    done(br)
    mz = Part("R_Muzzle", M["tan"], bevel=0.6, segs=2)
    mz.cyl((0, 266, 0), (0, 272, 0), 11.0, segs=36)
    mz.cyl((0, 271, 0), (0, 318, 0), 13.4, segs=36)
    mz.cyl((0, 317, 0), (0, 324, 0), 13.4, segs=36, r2=11.0)
    c = mz.cut()
    c.cyl((0, 284, 0), (0, 330, 0), 5.0, segs=24)
    c = mz.cut()
    for i in range(3):
        c.box((-20, 281 + i * 11.5, -5.2), (20, 287.5 + i * 11.5, 5.2))
    c = mz.cut()
    for i in range(3):
        c.box((-3.0, 282 + i * 11.5, 8), (3.0, 286.5 + i * 11.5, 20))
    done(mz)

    # ------------------------------------------------------------------ lower housing, trigger guard, trigger, grip
    lo = Part("R_Lower", M["dark"], bevel=0.8, segs=3)
    lo.prism_x([P(-40, 14), P(-44, 21), (-74, RB + 0.5), (61, RB + 0.5), (61, -50), (55, -56.5), P(52, 9.5), P(45, 14)], -15, 15)
    c = lo.cut()                                   # thumb scallops above the trigger
    for sx in (-1, 1):
        c.cyl((sx * 22.5, *P(30, 20)), (sx * 22.5, *P(62, 20)), 8.6, segs=24)
    done(lo)
    tg = Part("R_TriggerGuard", M["dark"], bevel=1.6, segs=3)
    tg.prism_x([P(16, 16), P(83, 16), P(85, 8), P(82, -21), P(73, -31), P(26, -32), P(14, -22)], -7.2, 7.2)
    c = tg.cut()
    c.prism_x([P(27, 10.5), P(74, 10.5), P(76.5, 5), P(74.5, -17.5), P(68, -24.5), P(32, -25.5), P(25.5, -18)], -12, 12)
    done(tg)
    tr = Part("R_Trigger", M["steel"], bevel=0.8, segs=3)
    tr.prism_x([P(43, 11), P(50, 11), P(49.5, -2), P(47, -12), P(43, -17), P(40.5, -15), P(43.5, -6)], -3.6, 3.6)
    done(tr)
    gr = Part("R_Grip", M["dark"], bevel=5.5, segs=5)
    gr.prism_x([P(27, 15), P(24, -22), P(17, -46), P(8, -70), P(2.5, -88), P(-56.5, -92), P(-55, -70), P(-50, -40),
                P(-45.5, -12), P(-47, 4), P(-54.5, 15.5), P(-51, 21.5), P(-40, 22.5), P(-40, 15)], -15, 15)
    done(gr)
    gp = Part("R_GripPanels", M["grip"], bevel=0.9, segs=2)
    gp.prism_x([P(13, -32), P(7.5, -52), P(-0.5, -80), P(-48.5, -83.5), P(-46.5, -58), P(-41, -30), P(-20, -27)], -15.7, 15.7)
    gp.prism_y([(-9, -27 + DZ), (9, -27 + DZ), (9, -84 + DZ), (-9, -84 + DZ)], -57.2 + DY, -43 + DY)
    c = gp.cut()
    c.prism_x([P(9, -34), P(4, -54), P(-3.5, -78), P(-45, -81), P(-43.5, -58), P(-38.5, -33), P(-20, -30)], -15.0, 15.0)
    done(gp)
    gb = Part("R_GripCap", M["tan"], bevel=1.2, segs=3)
    gb.prism_x([P(4.5, -87), P(3, -94), P(-58, -98), P(-58, -91)], -15.6, 15.6)
    done(gb)

    # ------------------------------------------------------------------ magazine well + magazine
    W = MAGWELL
    mw = Part("R_Magwell", M["white"], bevel=2.2, segs=4)
    mw.prism_x([(W["y0"] - 2, W["z1"]), (W["y1"], W["z1"]), (W["y1"] + 3, -56), (W["y1"], W["z0"] + 6), (W["y0"] + 2, W["z0"]),
                (W["y0"] - 4, -62)], -W["hw"], W["hw"])
    c = mw.cut()
    c.box((-13.2, 70, -112), (13.2, 113, -52))
    c = mw.cut()                                   # grip grooves on the front face, side windows
    for i in range(5):
        c.box((-22, W["y1"] + 1.2, -84 + i * 9), (22, W["y1"] + 6, -80.5 + i * 9))
    c = mw.cut()
    for sx in (-1, 1):
        c.box((sx * 18.4 - 1.6, 74, -82), (sx * 18.4 + 1.6, 108, -44))
    done(mw)
    wp = Part("R_MagwellPanels", M["grey"], bevel=0.5)
    for sx in (-1, 1):
        wp.box((sx * 16.4 - 0.8, 75.5, -80.5), (sx * 16.4 + 0.8, 106.5, -45.5))
    done(wp)
    mg = Part("R_Magazine", M["dark"], bevel=1.4, segs=3)
    mg.prism_x([(71, -52), (112, -52), (116, -142), (123, -218), (80, -223), (74, -142)], -12.6, 12.6)
    c = mg.cut()
    for sx in (-1, 1):
        for i in range(6):
            c.box((sx * 12.6 - 1.0, 78 + i * 0.9, -120 - i * 15), (sx * 12.6 + 1.0, 114 + i * 1.1, -116 - i * 15), rx=-5)
    done(mg)
    mb = Part("R_MagBase", M["tan"], bevel=1.4, segs=3)
    mb.prism_x([(76, -218), (126, -212.5), (127, -223), (77, -229)], -14.6, 14.6)
    done(mb)
    ml = Part("R_MagLight", M["cyan"], bevel=0)
    ml.box((-12.9, 76.5, -108), (-12.4, 78.5, -58), rx=-2.5)
    done(ml)
    mr = Part("R_MagRelease", M["tan"], bevel=0.8)
    mr.box((-17.4, 50, -46), (-14.6, 60, -36))
    mr.box((14.6, 50, -46), (17.4, 60, -36))
    done(mr)

    # ------------------------------------------------------------------ holographic sight (wide hood, low on the rail)
    Y0, RTOP = 66.0, RT + 7.5                                                                   # rear face, rail top
    sb = Part("R_SightBody", M["tan"], bevel=1.0, segs=3)
    sb.box((-13.5, Y0 + 2, RTOP - 0.5), (13.5, Y0 + 74, RTOP + 7.5))                            # rail clamp
    sb.prism_x([(Y0, 44), (Y0 + 74, 44), (Y0 + 74, 55), (Y0 + 68, 58), (Y0 + 6, 58), (Y0, 52)], -20, 20)   # housing
    sb.prism_x([(Y0 + 34, 56), (Y0 + 74, 56), (Y0 + 74, 90), (Y0 + 71, 96), (Y0 + 65, 99), (Y0 + 45, 99), (Y0 + 38, 96),
                (Y0 + 34, 90)], -26, 26)                                                        # hood
    c = sb.cut()
    c.prism_y([(-21, 60), (21, 60), (21, 88), (16, 94), (-16, 94), (-21, 88)], Y0 + 16, Y0 + 90)
    c = sb.cut()
    for sx in (-1, 1):
        c.box((sx * 26.4 - 1.0, Y0 + 40, 64), (sx * 26.4 + 1.0, Y0 + 68, 84))                   # hood side flats
        c.box((sx * 20.4 - 0.9, Y0 + 10, 46.5), (sx * 20.4 + 0.9, Y0 + 30, 54))                 # housing side flats
    c = sb.cut()
    for i in range(4):                                                                          # grip cuts on the hood roof
        c.box((-12, Y0 + 46 + i * 5, 98.2), (12, Y0 + 48.2 + i * 5, 100))
    done(sb)
    sk = Part("R_SightBits", M["black"], bevel=0.5)
    for y in (Y0 + 16, Y0 + 60):
        sk.cyl((-21.5, y, 41), (-13, y, 41), 4.6, segs=16)                                      # clamp knobs
        sk.cyl((13, y, 41), (15.5, y, 41), 3.4, segs=6)                                         # clamp nuts
    sk.cyl((20, Y0 + 20, 51), (27, Y0 + 20, 51), 5.5, segs=24)                                  # battery cap
    for sx in (-1, 1):
        for y in (Y0 + 42, Y0 + 68):
            sk.cyl((sx * 25.6, y, 93), (sx * 26.6, y, 93), 1.6, segs=10)                        # hood screws
    done(sk)
    sr = Part("R_SightButtons", M["rubber"], bevel=0.6)
    for sx in (-1, 1):
        sr.box((sx * 9 - 5.5, Y0 - 1.2, 45.5), (sx * 9 + 5.5, Y0 + 1, 51))
    done(sr)
    ln = Part("R_SightLens", M["lens"], bevel=0)
    ln.box((-21.4, Y0 + 56, 59.6), (21.4, Y0 + 57.4, 94.4), rx=-5)
    done(ln)
    rt = Part("R_Reticle", M["reticle"], bevel=0)       # red cross: four arms + centre dot
    RZ_ = 75.0
    for a0, a1 in ((-11.0, -2.6), (2.6, 11.0)):
        rt.box((a0, Y0 + 55.0, RZ_ - 0.45), (a1, Y0 + 55.4, RZ_ + 0.45))
        rt.box((-0.45, Y0 + 55.0, RZ_ + a0), (0.45, Y0 + 55.4, RZ_ + a1))
    rt.box((-0.6, Y0 + 55.0, RZ_ - 0.6), (0.6, Y0 + 55.4, RZ_ + 0.6))
    done(rt)

    # ------------------------------------------------------------------ back-up sights, pins, controls, lights
    bs = Part("R_BackupSights", M["black"], bevel=0.8, segs=2)
    bs.prism_x([(-27, RTOP), (-2, RTOP), (-2, RTOP + 3.5), (-8, RTOP + 7), (-24, RTOP + 7), (-27, RTOP + 4.5)], -9.5, 9.5)
    bs.prism_x([(226, RTOP), (252, RTOP), (252, RTOP + 4), (247, RTOP + 7), (230, RTOP + 7), (226, RTOP + 4.5)], -9.5, 9.5)
    done(bs)
    pn = Part("R_Pins", M["steel"], bevel=0.3)
    for sx in (-1, 1):
        for y, z, r in ((-20, -18, 3.0), (150, -20, 3.0), (150, 14, 2.2), (-20, 12, 2.2), (-2, -39, 2.4), (40, -38, 2.4)):
            hw = 23 if z > RB else 15
            pn.cyl((sx * (hw - 1), y, z), (sx * (hw + 0.9), y, z), r, segs=14)
    for y, z in ((-262, -30), (-262, 8), (-190, -24)):
        for sx in (-1, 1):
            pn.cyl((sx * 18, y, z), (sx * 29.8, y, z), 3.2, segs=14)                            # stock screws
    done(pn)
    sel = Part("R_Selector", M["tan"], bevel=0.7, segs=2)
    for sx in (-1, 1):
        sel.cyl((sx * 14, -44, -40), (sx * 18.2, -44, -40), 5.0, segs=20)
        sel.box((sx * 17.2 - 1.2, -47, -42), (sx * 17.2 + 1.2, -28, -38), rx=-12)
    sel.box((-25.6, 30, -4.5), (-23, 44, 1))                                                    # bolt catch
    done(sel)
    lb = Part("R_LightBezels", M["matte"], bevel=0.5)
    lb.box((-28.2, -100, -9), (-24, -64, 3.5))
    done(lb)
    lt = Part("R_Lights", M["cyan"], bevel=0)
    lt.box((-28.6, -96, -5), (-28.0, -78, -0.5))
    lt.box((-22.2, 40, -2.0), (-21.6, 98, -0.4))                                                # receiver light strip
    lt.box((-7.4, -122, 34.8), (-3.8, -118.5, 36.6))                                            # top indicator
    done(lt)
    return out


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    prefix = argv[0] if argv else "/tmp/rifle"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    parts = build(sc.collection)
    print(f"rifle: {len(parts)} parts, {sum(len(o.data.polygons) for o in parts)} faces")
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.eevee.taa_render_samples = 16
    sc.render.resolution_x, sc.render.resolution_y = 1200, 620
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.52, 0.55, 1)
    sc.world = w
    sun = bpy.data.objects.new("s", bpy.data.lights.new("s", "SUN"))
    sun.data.energy = 3.5
    sc.collection.objects.link(sun)
    cd = bpy.data.cameras.new("c")
    cd.type = "ORTHO"
    cd.ortho_scale = 0.78
    cam = bpy.data.objects.new("c", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    ctr = Vector((0, -0.01, -0.06))
    for name, d in (("right", (1, 0, 0.0)), ("left", (-1, 0, 0.0)), ("top3q", (-0.55, -0.5, 0.65)), ("player", (-0.35, -1, 0.45))):
        dv = Vector(d).normalized()
        cam.location = ctr + dv
        cam.rotation_euler = (-dv).to_track_quat("-Z", "Y").to_euler()
        sun.rotation_euler = ((-dv + Vector((0.3, 0.2, -0.6))).normalized()).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{prefix}_{name}.png"
        bpy.ops.render.render(write_still=True)
