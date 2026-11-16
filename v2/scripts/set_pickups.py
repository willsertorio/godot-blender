"""The environment set: pickups (see build_set.py)."""
import math

import setlib as S
from setlib import Part, T, asset, cable, chamfer, handle, pipe, rect, ring, rounded, valve_wheel
from setlib import text
from set_cover import crate_body


# ------------------------------------------------------------------ the exit portal (reference 22): 2.9 m wide, 3.4 m high
@asset("exit_portal", views=[(-0.2, -1.0, 0.1), (1.0, -0.1, 0.08)], res=[(640, 620), (520, 620)])
def exit_portal():
    hw, h = 1.35, 3.3
    ow, d = 0.95, 0.26                                       # the opening's half width; the frame's half depth

    def arch(x0, z1, r, n=6):
        """Half an arch outline from (x0, 0) up and over to the middle (0, z1), its corner rounded to r."""
        pts = [(x0, 0.0)]
        for i in range(n + 1):
            a = math.radians(180 - 90 * i / n)
            pts.append((x0 + r + r * math.cos(a), z1 - r + r * math.sin(a)))
        return pts

    def arch_pts(x0, z1, r, n=6):
        """As arch(), with the foot and the crown as points of their own, so two arches pair up point for point."""
        return arch(x0, z1, r, n) + [(0.0, z1)]

    for sx in (-1, 1):
        flip = lambda pts: [(x * -sx, z) for x, z in pts]   # noqa: E731
        Part("white", bevel=0.02, name="arch").band_xz(flip(arch_pts(-hw, h, 0.5)), flip(arch_pts(-ow - 0.16, h - 0.42, 0.3)), -d, d).done()
        Part("grey", bevel=0.012, name="inner frame").band_xz(flip(arch_pts(-ow - 0.16, h - 0.42, 0.3)), flip(arch_pts(-ow, h - 0.6, 0.2)), -d + 0.05, d - 0.05).done()
        # the leaf: a shaped panel closing each side of the opening, leaving the field between
        lf = [(-ow, 0.06), (-0.34, 0.06), (-0.34, 0.5), (-0.2, 0.72), (-0.2, 1.5), (-0.34, 1.72), (-0.34, 2.4), (-0.5, 2.62), (-ow, 2.62)]
        lf = [(x * -sx, z) for x, z in lf]
        Part("white", bevel=0.014, name="leaf").plate_xz(lf if sx < 0 else lf[::-1], -0.08, 0.08).done()
        g = Part("grey", bevel=0.008, name="leaf ribs")
        for z0, z1 in ((0.2, 0.62), (0.9, 1.4), (1.84, 2.34)):
            xa, xb = sorted((sx * (ow - 0.1), sx * 0.5))
            g.plate_xz(chamfer(xa, z0, xb, z1, 0.05), -0.1, -0.08)
        xa, xb = sorted((sx * 0.22, sx * 0.3))
        g.box((xa, -0.1, 0.74), (xb, -0.08, 1.48))
        g.done()
        hz = Part("hazard", bevel=0.0, name="leaf stripes")
        xa, xb = sorted((sx * (ow - 0.02), sx * (ow - 0.09)))
        for z0, z1 in ((0.7, 1.1), (1.5, 2.0)):
            hz.box((xa, -0.086, z0), (xb, -0.08, z1))
        xa, xb = sorted((sx * 0.36, sx * 0.43))
        hz.box((xa, -0.086, 0.86), (xb, -0.08, 1.36))
        hz.done()
        # the foot, the mid block with its plug box, the shoulder box set on the arch's corner
        x0, x1 = sorted((sx * (hw + 0.06), sx * (ow + 0.1)))
        Part("white", bevel=0.016, name="foot").plate_xz(chamfer(x0, 0.0, x1, 0.5, (0.0, 0.0, 0.08, 0.08)), -d - 0.12, d + 0.12).done()
        Part("grey", bevel=0.008, name="foot plate").box(((x0 + x1) / 2 - 0.06, -d - 0.14, 0.06), ((x0 + x1) / 2 + 0.06, -d - 0.12, 0.34)).box((x0 - 0.02, -d - 0.16, 0.0), (x1 + 0.02, d + 0.16, 0.07)).done()
        x0, x1 = sorted((sx * (hw + 0.05), sx * (hw - 0.3)))
        Part("grey", bevel=0.01, name="mid block").box((x0, -d - 0.05, 1.3), (x1, -d + 0.02, 1.7)).box((x0, -d - 0.05, 2.0), (x1, -d + 0.02, 2.2)).done()
        Part("white", bevel=0.008, name="plug box").box((x0 + 0.06, -d - 0.1, 1.36), (x1 - 0.06, -d - 0.05, 1.64)).done()
        Part("cyan", bevel=0.0, name="lamp").box((sx * (hw - 0.2) - 0.03, -d - 0.004, 1.76), (sx * (hw - 0.2) + 0.03, -d + 0.0, 1.775)).box((sx * (ow + 0.3) - 0.03, -d - 0.004, 2.82), (sx * (ow + 0.3) + 0.03, -d, 2.84)).done()
        m = T(loc=(sx * (hw - 0.26), 0, h - 0.26), ry=sx * 45)
        Part("grey", bevel=0.012, name="shoulder box").box((-0.17, -d - 0.04, -0.13), (0.17, d + 0.04, 0.13)).done(m)
        Part("darksteel", bevel=0.006, name="shoulder plate").box((-0.11, -d - 0.055, -0.08), (0.11, -d - 0.04, 0.08)).done(m)
        # the cables: from the plug box, a loop hanging down the side; from the top box over the shoulder
        for k in range(4):
            xs = sx * (hw - 0.05 + k * 0.035)
            cable([(xs, -d - 0.08, 1.36), (xs + sx * 0.1, -d - 0.12, 1.05 - k * 0.03), (xs + sx * 0.12, -d - 0.06, 0.82 - k * 0.04), (xs + sx * 0.02, -d - 0.02, 0.72), (xs - sx * 0.06, -d + 0.04, 0.9)],
                  0.02, ("cable", "cable", "cable_red", "cable")[k])
        for k in range(3):
            cable([(sx * 0.3, -0.1 + k * 0.1, h + 0.1), (sx * (hw - 0.5), -0.1 + k * 0.1, h + 0.06), (sx * (hw - 0.02), -0.1 + k * 0.1, h - 0.5), (sx * (hw + 0.03), -0.1 + k * 0.1, 2.4),
                   (sx * (hw + 0.02), -0.1 + k * 0.1, 1.72)], 0.022)
        Part("grey", bevel=0.006, name="cable clamp").box(tuple(sorted((sx * (hw - 0.02), sx * (hw + 0.08))))[0:1] + (-0.18, 2.3), tuple(sorted((sx * (hw - 0.02), sx * (hw + 0.08))))[1:2] + (0.18, 2.4)).done()
    # the top box with its clamps; the threshold; stripes at head and foot of the opening
    Part("white", bevel=0.016, name="top box").box((-0.5, -d - 0.05, h - 0.3), (0.5, d + 0.05, h + 0.12)).done()
    Part("grey", bevel=0.008, name="top detail").box((-0.36, -d - 0.062, h - 0.14), (0.36, -d - 0.05, h + 0.0)).box((-0.42, -d - 0.07, h - 0.24), (-0.34, -d - 0.05, h + 0.14)) \
        .box((0.34, -d - 0.07, h - 0.24), (0.42, -d - 0.05, h + 0.14)).done()
    Part("dark", bevel=0.0, name="top slot").box((-0.26, -d - 0.066, h - 0.09), (0.26, -d - 0.062, h - 0.05)).done()
    Part("grey", bevel=0.008, name="threshold").box((-ow - 0.16, -d - 0.1, 0.0), (ow + 0.16, d + 0.1, 0.06)).done()
    Part("hazard", bevel=0.0, name="stripes").box((-ow + 0.1, -d - 0.104, 0.008), (ow - 0.1, -d - 0.1, 0.052)).box((-0.5, -0.086, 2.66), (0.5, -0.08, 2.72)).done()
    Part("portal", bevel=0.0, name="field").box((-0.36, -0.01, 0.06), (0.36, 0.01, 2.64)).done()
    # the back: a braced frame
    bk = Part("grey", bevel=0.008, name="back frame")
    for sx in (-1, 1):
        bk.box(tuple(sorted((sx * (ow + 0.5), sx * (ow + 0.4))))[0:1] + (d, 0.1), tuple(sorted((sx * (ow + 0.5), sx * (ow + 0.4))))[1:2] + (d + 0.3, 2.9))
    for z in (0.5, 1.3, 2.1, 2.8):
        bk.box((-ow - 0.5, d + 0.2, z), (ow + 0.5, d + 0.3, z + 0.08))
    bk.done()


# ------------------------------------------------------------------ the loot crate (reference 23): 0.9 x 0.56 x 0.58 m, in three paints
def loot(shell):
    crate_body(w=0.9, d=0.56, h=0.58, shell=shell)
    hz = Part("hazard", bevel=0.0, name="ticks")
    hz.box((-0.17, -0.2885, 0.37), (0.17, -0.2865, 0.4))
    hz.done()
    for sx in (-1, 1):                                       # the straps over the lid
        x0, x1 = sorted((sx * 0.2, sx * 0.27))
        Part("grey", bevel=0.005, name="strap").box((x0, -0.29, 0.37), (x1, 0.29, 0.59)).done() if False else \
            Part("grey", bevel=0.005, name="strap").box((x0, -0.292, 0.368), (x1, -0.275, 0.585)).box((x0, -0.28, 0.555), (x1, 0.28, 0.588)).done()


@asset("loot_crate")
def loot_crate():
    loot("white")


@asset("loot_crate_olive")
def loot_crate_olive():
    loot("olive")


@asset("loot_crate_green")
def loot_crate_green():
    loot("green")


# ------------------------------------------------------------------ the med kit (reference 23): 0.42 x 0.2 x 0.3 m, a red case with a white cross
def kit_case(shell, hw=0.21, hd=0.1, h=0.3):
    Part(shell, bevel=0.022, name="case").plate_xz(rounded(-hw, 0.02, hw, h, 0.035), -hd, hd).done()
    g = Part("grey", bevel=0.006, name="trim")
    for sx in (-1, 1):                                       # the feet and the top lugs
        x0, x1 = sorted((sx * 0.07, sx * 0.13))
        g.box((x0, -hd - 0.008, 0.0), (x1, hd + 0.008, 0.06))
        g.box((x0, -hd + 0.01, h - 0.01), (x1, hd - 0.01, h + 0.012))
    g.done()
    Part("dark", bevel=0.0, name="seam").box((-hw - 0.001, -0.004, 0.05), (hw + 0.001, 0.004, h - 0.03)).done()
    for sx in (-1, 1):                                       # a latch on each end, across the seam
        x = sx * hw
        Part("white", bevel=0.006, name="end plate").plate_yz(rounded(-hd + 0.02, 0.07, hd - 0.02, h - 0.05, 0.02), x, x + sx * 0.006).done()
        lt = Part("darksteel", bevel=0.004, name="latch")
        x0, x1 = sorted((x + sx * 0.006, x + sx * 0.02))
        lt.box((x0, -0.03, h - 0.15), (x1, 0.03, h - 0.06)).box((x0, -0.04, 0.04), (x1, 0.04, 0.09))
        lt.done()
        handle((x + sx * 0.012, -0.035, h - 0.1), (x + sx * 0.012, 0.035, h - 0.1), (sx * 0.02, 0, -0.02), r=0.006)


def cross(y, cz, arm, thick, cx=0.0, back=False):
    """A cross painted on a face at y (one outline: two bars laid over each other show a black square where they meet)."""
    a, t = arm, thick
    out = [(-t, -a), (t, -a), (t, -t), (a, -t), (a, t), (t, t), (t, a), (-t, a), (-t, t), (-a, t), (-a, -t), (-t, -t)]
    Part("cross", bevel=0.0, name="cross").plate_xz([(cx + px, cz + pz) for px, pz in out], y, y + (0.002 if back else -0.002)).done()


@asset("medkit", views=[(-0.35, -1.0, 0.2), (1.0, -0.25, 0.15)], res=[(600, 620), (460, 620)])
def medkit():
    kit_case("red")
    cross(-0.1, 0.165, 0.062, 0.021)
    cross(0.1, 0.165, 0.062, 0.021, back=True)


@asset("medkit_white", views=[(-0.35, -1.0, 0.2), (1.0, -0.25, 0.15)], res=[(600, 620), (460, 620)])
def medkit_white():
    hw, hd, h = 0.21, 0.1, 0.3
    kit_case("white")
    for sx in (-1, 1):                                       # red cheeks on the front and the back
        for sy in (-1, 1):
            x0, x1 = sorted((sx * (hw - 0.012), sx * 0.075))
            y0, y1 = sorted((sy * hd, sy * (hd + 0.004)))
            Part("red", bevel=0.004, name="cheek").plate_xz(chamfer(x0, 0.075, x1, 0.2, 0.012), y0, y1).done()
    Part("grey", bevel=0.008, name="lid plate").plate_xz(chamfer(-0.1, 0.2, 0.1, 0.285, (0.02, 0.02, 0.0, 0.0)), -hd - 0.006, -hd + 0.002).done()
    cross(-hd - 0.006, 0.243, 0.028, 0.0095)
    Part("grey", bevel=0.006, name="front latch").box((-0.05, -hd - 0.016, 0.085), (0.05, -hd, 0.195)).done()
    Part("darksteel", bevel=0.004, name="front latch lever").box((-0.03, -hd - 0.026, 0.11), (0.03, -hd - 0.016, 0.175)).done()


# ------------------------------------------------------------------ the ammunition box (reference 24): card, 0.2 x 0.1 x 0.16 m
def ammo(open_top):
    hw, hd, h = 0.1, 0.05, 0.15
    t = 0.004
    b = Part("card", bevel=0.0015, name="box")
    b.box((-hw, -hd, 0.0), (hw, hd, t))
    b.box((-hw, -hd, 0.0), (hw, -hd + t, h)).box((-hw, hd - t, 0.0), (hw, hd, h))
    b.box((-hw, -hd, 0.0), (-hw + t, hd, h)).box((hw - t, -hd, 0.0), (hw, hd, h))
    if not open_top:
        b.box((-hw - 0.001, -hd - 0.001, h - t), (hw + 0.001, hd + 0.001, h + 0.001))
    b.done(None, segments=1)
    if open_top:
        import mathutils
        fl = Part("card", bevel=0.001, name="flaps")
        fl.box((-hw, hd - t, h), (hw, hd, h + 0.095), rot=mathutils.Matrix.Rotation(math.radians(-24), 4, "X"), pivot=(0, hd, h))               # the lid, up and back
        fl.box((-hw, hd - t, h + 0.095), (hw, hd, h + 0.13), rot=mathutils.Matrix.Rotation(math.radians(-24), 4, "X"), pivot=(0, hd, h))
        fl.box((-hw, -hd, h), (-hw + t, hd, h + 0.045), rot=mathutils.Matrix.Rotation(math.radians(-48), 4, "Y"), pivot=(-hw, 0, h))            # the side flaps, out
        fl.box((hw - t, -hd, h), (hw, hd, h + 0.045), rot=mathutils.Matrix.Rotation(math.radians(48), 4, "Y"), pivot=(hw, 0, h))
        fl.done(None, segments=1)
        r = 0.0057
        cs, tips, pr = Part("brass", bevel=0.0, name="cases"), Part("copper", bevel=0.0, name="bullets"), Part("steel", bevel=0.0, name="primers")
        for i in range(10):
            for j in range(5):
                x = -hw + 0.014 + i * 0.0191
                y = -hd + 0.0125 + j * 0.0188
                cs.cyl((x, y, t), (x, y, h - 0.012), r, segs=10)
                pr.cyl((x, y, h - 0.012), (x, y, h - 0.0105), r * 0.5, segs=8)
        cs.done()
        tips.cyl((0, 0, 0.001), (0, 0, 0.002), 0.001, segs=4)
        tips.done()
        pr.done()
    # the print: the word, the calibre, a crop mark, a striped band
    text("AMMO", 0.026, (-hw + 0.012, -hd - 0.0006, h - 0.045))
    text("5.56MM", 0.016, (hw - 0.082, -hd - 0.0006, 0.045))
    hz = Part("ink", bevel=0.0, name="print")
    for i in range(9):
        import mathutils
        hz.box((0.0 + i * 0.011, -hd - 0.0008, 0.012), (0.005 + i * 0.011, -hd, 0.03), rot=mathutils.Matrix.Rotation(math.radians(-30), 4, "Y"), pivot=(0.0025 + i * 0.011, -hd, 0.021))
    hz.box((hw - 0.035, -hd - 0.0008, h - 0.03), (hw - 0.012, -hd, h - 0.028)).box((hw - 0.014, -hd - 0.0008, h - 0.05), (hw - 0.012, -hd, h - 0.028))
    hz.box((-hw + 0.012, -hd - 0.0008, 0.03), (-hw + 0.032, -hd, 0.05))
    hz.done()


@asset("ammo_box", views=[(-0.5, -1.0, 0.5), (1.0, -0.5, 0.35)], res=[(600, 620), (460, 620)])
def ammo_box():
    ammo(True)


@asset("ammo_box_shut", views=[(-0.5, -1.0, 0.4), (1.0, -0.5, 0.3)], res=[(600, 620), (460, 620)])
def ammo_box_shut():
    ammo(False)
