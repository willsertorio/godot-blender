"""The environment set: equipment (see build_set.py)."""
import math

import setlib as S
from setlib import Part, T, asset, cable, chamfer, handle, pipe, rect, ring, rounded, valve_wheel


def pedestal_feet(hw, hd, h=0.14):
    """The dark sled equipment stands on (console, locker, dock): two runners with ramped ends, a bar across."""
    g = Part("grey", bevel=0.01, name="sled")
    for sx in (-1, 1):
        x0, x1 = sorted((sx * hw, sx * (hw - 0.2)))
        g.plate_yz([(-hd - 0.12, 0.0), (hd + 0.12, 0.0), (hd + 0.12, h * 0.45), (hd, h), (-hd, h), (-hd - 0.12, h * 0.45)], x0, x1)
    g.box((-hw + 0.2, -hd + 0.05, 0.02), (hw - 0.2, hd - 0.05, h * 0.8))
    g.done()
    pipe([(-hw + 0.08, -hd - 0.12, 0.05), (-hw + 0.08, -hd - 0.19, 0.05), (hw - 0.08, -hd - 0.19, 0.05), (hw - 0.08, -hd - 0.12, 0.05)], 0.018, "darksteel", fillet=0.04)


# ------------------------------------------------------------------ the console (reference 16): 1.3 m wide, 1.6 m high
@asset("console", views=[(-0.55, -1.0, 0.22), (1.0, -0.08, 0.1)], res=[(620, 620), (540, 620)])
def console():
    hw, hd = 0.5, 0.36
    pedestal_feet(hw, hd)
    Part("white", bevel=0.014, name="pedestal").plate_xy(chamfer(-hw + 0.04, -hd, hw - 0.04, hd, 0.04), 0.14, 0.66).done()
    Part("grey", bevel=0.01, name="neck").plate_xy(chamfer(-hw + 0.1, -hd + 0.06, hw - 0.1, hd - 0.02, 0.04), 0.66, 0.9).done()
    Part("dark", bevel=0.006, name="pedestal door").plate_xz(chamfer(-0.22, 0.2, 0.22, 0.6, 0.03), -hd - 0.012, -hd + 0.01).done()
    Part("darksteel", bevel=0.003, name="door hinges").box((-0.25, -hd - 0.02, 0.28), (-0.2, -hd - 0.004, 0.34)).box((-0.25, -hd - 0.02, 0.46), (-0.2, -hd - 0.004, 0.52)).done()
    for sx in (-1, 1):
        handle((sx * (hw - 0.04), -0.14, 0.3), (sx * (hw - 0.04), -0.14, 0.56), (sx * 0.06, 0, 0), r=0.014)
        Part("dark", bevel=0.004, name="side vent").plate_yz(rounded(0.0, 0.26, 0.22, 0.58, 0.03), sx * (hw - 0.04), sx * (hw - 0.04) + sx * 0.008).done()
    # the control deck: a wedge sloping toward the user, on the neck
    deck = T(loc=(0, -0.2, 0.92), rx=-16)
    Part("white", bevel=0.016, name="deck").plate_xy(chamfer(-0.66, -0.36, 0.66, 0.3, 0.05), -0.07, 0.07).done(deck)
    Part("dark", bevel=0.004, name="deck top").plate_xy(chamfer(-0.6, -0.3, 0.6, 0.25, 0.03), 0.07, 0.078).done(deck)
    kb = Part("grey", bevel=0.003, name="keys")
    for r_ in range(4):
        for c_ in range(14):
            kb.box((-0.38 + c_ * 0.04, -0.26 + r_ * 0.04, 0.078), (-0.348 + c_ * 0.04, -0.228 + r_ * 0.04, 0.09))
    for c_ in range(4):
        for r_ in range(3):
            kb.box((0.24 + c_ * 0.04, -0.26 + r_ * 0.04, 0.078), (0.272 + c_ * 0.04, -0.228 + r_ * 0.04, 0.09))
    for i in range(5):                                       # sliders
        kb.box((-0.56 + i * 0.03, -0.1, 0.078), (-0.548 + i * 0.03, 0.06, 0.084)).box((-0.566 + i * 0.03, -0.06 + i * 0.02, 0.084), (-0.542 + i * 0.03, -0.035 + i * 0.02, 0.098))
    for i in range(4):                                       # toggles
        kb.cyl((0.28 + i * 0.05, 0.14, 0.078), (0.28 + i * 0.05, 0.15, 0.115), 0.007, segs=6)
    kb.cyl((0.12, 0.04, 0.078), (0.12, 0.04, 0.1), 0.028, segs=14)
    kb.done(deck)
    for (x, y, mat_k) in ((-0.5, 0.16, "orange"), (-0.4, 0.16, "orange"), (-0.3, 0.16, "ledblue"), (-0.05, -0.05, "ledblue"), (0.0, -0.05, "ledgreen"), (0.05, -0.05, "ledred"),
                          (0.5, -0.02, "ledred"), (0.5, 0.06, "ledgreen"), (-0.52, -0.2, "orange"), (-0.52, -0.26, "ledred")):
        Part(mat_k, bevel=0.003, name="button").cyl((x, y, 0.078), (x, y, 0.094), 0.024 if y > 0.1 else 0.014, segs=12).done(deck)
    Part("screen", bevel=0.0, name="deck display").box((-0.14, 0.1, 0.078), (0.14, 0.2, 0.082)).done(deck)
    handle((-0.3, -0.36, 0.0), (0.3, -0.36, 0.0), (0, -0.05, 0.0), r=0.014, m=deck)
    for sx in (-1, 1):
        handle((sx * 0.66, -0.2, 0.0), (sx * 0.66, 0.15, 0.0), (sx * 0.05, 0, 0.0), r=0.012, m=deck)
    # the screen: a heavy tilted housing on an arm
    scr = T(loc=(0, 0.2, 1.52), rx=-12)
    Part("white", bevel=0.02, name="screen housing").plate_xz(chamfer(-0.72, -0.4, 0.72, 0.4, 0.07), -0.06, 0.1).done(scr)
    Part("dark", bevel=0.006, name="screen bezel").plate_xz(chamfer(-0.64, -0.33, 0.64, 0.33, 0.04), -0.07, -0.058).done(scr)
    Part("screen", bevel=0.0, name="screen glass").plate_xz(chamfer(-0.6, -0.29, 0.6, 0.29, 0.03), -0.074, -0.07).done(scr)
    Part("grey", bevel=0.008, name="screen back").plate_xz(chamfer(-0.5, -0.3, 0.5, 0.3, 0.05), 0.1, 0.2).done(scr)
    sl = Part("dark", bevel=0.0, name="screen vents")
    for i in range(6):
        sl.box((-0.3 + i * 0.11, 0.2, -0.2), (-0.24 + i * 0.11, 0.204, 0.2))
    sl.done(scr)
    for sx in (-1, 1):
        handle((sx * 0.72, 0.0, -0.22), (sx * 0.72, 0.0, 0.22), (sx * 0.05, 0, 0), r=0.014, m=scr)
    Part("grey", bevel=0.01, name="arm").box((-0.14, 0.12, 0.86), (0.14, 0.3, 1.3)).done()
    for k in range(5):                                       # cables down the back, from the screen to the pedestal
        x = -0.2 + k * 0.1
        cable([(x, 0.4, 1.42), (x * 1.2, 0.46, 1.1), (x * 1.3, 0.44, 0.7), (x, hd + 0.02, 0.36)], 0.014, ("cable", "cable", "cable_red", "cable", "cable")[k])
    Part("grey", bevel=0.006, name="back box").box((-0.2, hd - 0.02, 0.22), (0.2, hd + 0.05, 0.56)).done()


# ------------------------------------------------------------------ the locker (reference 17): 1.25 m wide, 2.15 m high
@asset("locker", views=[(-0.55, -1.0, 0.18), (1.0, -0.08, 0.1)], res=[(580, 620), (540, 620)])
def locker():
    hw, hd, h = 0.55, 0.36, 2.15
    pedestal_feet(hw, hd)
    # the shell: three white courses with a waist between, the top course leaning back
    Part("white", bevel=0.018, name="base course").plate_xy(chamfer(-hw, -hd, hw, hd + 0.04, 0.05), 0.14, 0.74).done()
    Part("grey", bevel=0.012, name="waist").plate_xy(chamfer(-hw + 0.05, -hd + 0.03, hw - 0.05, hd, 0.05), 0.74, 1.36).done()
    Part("white", bevel=0.02, name="top course").plate_yz([(-hd, 1.36), (hd + 0.1, 1.36), (hd + 0.16, 1.5), (hd + 0.16, h - 0.08), (hd + 0.08, h), (-hd + 0.08, h), (-hd, h - 0.08)], -hw, hw).done()
    # the doors: two dark leaves over the whole front, each of three fields, with vents top and bottom
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.012, sx * (hw - 0.09)))
        d = Part("dark", bevel=0.008, name="door")
        d.box((x0, -hd - 0.03, 0.2), (x1, -hd + 0.01, h - 0.1))
        for z0, z1 in ((0.26, 0.72), (0.78, 1.34), (1.4, h - 0.16)):
            d.plate_xz(chamfer(x0 + 0.04, z0, x1 - 0.04, z1, 0.025), -hd - 0.045, -hd - 0.03)
        d.done()
        sl = Part("darksteel", bevel=0.0, name="door slots")
        xc = (x0 + x1) / 2
        for i in range(4):
            sl.box((xc - 0.1, -hd - 0.048, h - 0.34 + i * 0.03), (xc + 0.1, -hd - 0.045, h - 0.325 + i * 0.03))
            sl.box((xc - 0.1, -hd - 0.048, 0.32 + i * 0.03), (xc + 0.1, -hd - 0.045, 0.335 + i * 0.03))
        sl.done()
        hg = Part("grey", bevel=0.004, name="hinges")
        for z in (0.42, 1.06, 1.76):
            xa, xb = sorted((sx * (hw - 0.1), sx * (hw - 0.02)))
            hg.box((xa, -hd - 0.05, z - 0.045), (xb, -hd - 0.02, z + 0.045))
        hg.done()
        handle((sx * 0.07, -hd - 0.045, 1.5), (sx * 0.07, -hd - 0.045, 1.72), (0, -0.04, 0), r=0.01)
        handle((sx * (hw + 0.0), -0.05, 1.56), (sx * (hw + 0.0), -0.05, 1.96), (sx * 0.06, 0, 0), r=0.014)
        handle((sx * (hw + 0.0), -0.05, 0.3), (sx * (hw + 0.0), -0.05, 0.6), (sx * 0.06, 0, 0), r=0.014)
        Part("dark", bevel=0.004, name="side plate").plate_yz(chamfer(-hd + 0.1, 1.5, hd - 0.02, h - 0.2, 0.03), sx * hw, sx * hw + sx * 0.008).done()
    # the lock: a latch across the leaves and a keypad
    Part("grey", bevel=0.006, name="latch").box((-0.09, -hd - 0.07, 1.14), (0.06, -hd - 0.045, 1.26)).box((-0.02, -hd - 0.085, 1.16), (0.03, -hd - 0.07, 1.24)).done()
    Part("grey", bevel=0.006, name="keypad").box((0.1, -hd - 0.07, 1.04), (0.32, -hd - 0.045, 1.36)).done()
    Part("screen", bevel=0.0, name="keypad display").box((0.13, -hd - 0.074, 1.25), (0.29, -hd - 0.07, 1.33)).done()
    ky = Part("darksteel", bevel=0.002, name="keypad keys")
    for r_ in range(3):
        for c_ in range(3):
            ky.box((0.14 + c_ * 0.05, -hd - 0.078, 1.1 + r_ * 0.045), (0.175 + c_ * 0.05, -hd - 0.07, 1.13 + r_ * 0.045))
    ky.done()
    Part("ledgreen", bevel=0.0, name="lamp").box((0.25, -hd - 0.074, 1.06), (0.29, -hd - 0.07, 1.085)).done()
    Part("orange", bevel=0.0, name="lamp").box((0.13, -hd - 0.074, 1.06), (0.16, -hd - 0.07, 1.085)).done()
    # the back: a housing with a vent, cables down to the base
    Part("grey", bevel=0.01, name="back housing").box((-0.3, hd + 0.12, 1.42), (0.3, hd + 0.26, 2.0)).box((-0.2, hd + 0.02, 0.24), (0.2, hd + 0.1, 0.66)).done()
    for k in range(5):
        x = -0.24 + k * 0.12
        cable([(x, hd + 0.2, 1.42), (x * 1.25, hd + 0.24, 1.1), (x * 1.2, hd + 0.2, 0.78), (x * 0.7, hd + 0.08, 0.66)], 0.015, ("cable", "cable_red", "cable", "cable", "cable")[k])


def small_case(x0, y0, z0, w, d, h, shell="white", lamp="cyan"):
    """A small equipment case (what the shelves and the bench hold): shell, grey band and corner caps, a latch."""
    Part(shell, bevel=0.012, name="case").plate_xy(chamfer(x0, y0, x0 + w, y0 + d, 0.02), z0 + 0.01, z0 + h).done()
    g = Part("grey", bevel=0.005, name="case trim")
    g.plate_xy(chamfer(x0 - 0.005, y0 - 0.005, x0 + w + 0.005, y0 + d + 0.005, 0.02), z0 + h * 0.58, z0 + h * 0.58 + 0.025)
    g.box((x0 + 0.02, y0 + 0.02, z0), (x0 + w - 0.02, y0 + d - 0.02, z0 + 0.012))
    for cx in (x0 - 0.006, x0 + w - 0.04):
        g.box((cx, y0 - 0.006, z0 + h - 0.05), (cx + 0.046, y0 + 0.04, z0 + h + 0.004)).box((cx, y0 - 0.006, z0), (cx + 0.046, y0 + 0.04, z0 + 0.05))
    g.done()
    Part("darksteel", bevel=0.003, name="case latch").box((x0 + w / 2 - 0.02, y0 - 0.014, z0 + h * 0.5), (x0 + w / 2 + 0.02, y0, z0 + h * 0.5 + 0.08)).done()
    if lamp:
        Part(lamp, bevel=0.0, name="lamp").box((x0 + w * 0.2, y0 - 0.003, z0 + h * 0.72), (x0 + w * 0.2 + 0.04, y0 + 0.001, z0 + h * 0.72 + 0.01)).done()


def canister(x, y, z, r=0.07, h=0.24, shell="grey"):
    c = Part(shell, bevel=0.008, name="canister")
    c.cyl((x, y, z), (x, y, z + h), r, segs=18)
    c.done()
    Part("darksteel", bevel=0.004, name="canister cap").cyl((x, y, z + h), (x, y, z + h + 0.03), r * 0.55, segs=12).cyl((x, y, z + h * 0.45), (x, y, z + h * 0.55), r + 0.004, segs=18).done()


# ------------------------------------------------------------------ the shelving (reference 18): 2.3 m wide, 2.1 m high
@asset("shelving", views=[(-0.25, -1.0, 0.14), (1.0, -0.2, 0.1)], res=[(700, 620), (460, 620)])
def shelving():
    hw, hd, h = 1.05, 0.33, 2.05
    # the posts: chunky, in two courses with a grey shoe, a lamp on each front one
    for sx in (-1, 1):
        for sy in (-1, 1):
            x0, x1 = sorted((sx * hw, sx * (hw - 0.13)))
            y0, y1 = sorted((sy * hd, sy * (hd - 0.11)))
            Part("white", bevel=0.012, name="post").plate_xy(chamfer(x0, y0, x1, y1, 0.02), 0.18, h).done()
            Part("grey", bevel=0.01, name="post shoe").plate_xy(chamfer(x0 - 0.03, y0 - 0.03, x1 + 0.03, y1 + 0.03, 0.03), 0.0, 0.2).done()
            Part("white", bevel=0.008, name="post collar").plate_xy(chamfer(x0 - 0.012, y0 - 0.012, x1 + 0.012, y1 + 0.012, 0.02), 0.52, 0.68) \
                .plate_xy(chamfer(x0 - 0.012, y0 - 0.012, x1 + 0.012, y1 + 0.012, 0.02), h - 0.42, h - 0.26).done()
        Part("orange", bevel=0.0, name="lamp").box((sx * (hw - 0.065) - 0.012, -hd - 0.004, h - 0.37), (sx * (hw - 0.065) + 0.012, -hd, h - 0.31)).done()
        Part("ledgreen", bevel=0.0, name="lamp").box((sx * (hw - 0.065) - 0.012, -hd - 0.016, 0.57), (sx * (hw - 0.065) + 0.012, -hd - 0.012, 0.63)).done()
        # the ends: a cross brace between the posts
        x0, x1 = sorted((sx * (hw - 0.05), sx * (hw - 0.08)))
        br = Part("grey", bevel=0.004, name="brace")
        import mathutils
        for sgn in (-1, 1):
            br.box((x0, -0.025, 0.3), (x1, 0.025, 1.95), rot=mathutils.Matrix.Rotation(math.radians(sgn * 17), 4, "X"), pivot=((x0 + x1) / 2, 0, 1.12))
        br.done()
    shelves = (0.2, 0.74, 1.26, 1.78)
    sh = Part("white", bevel=0.006, name="shelves")
    for z in shelves:
        sh.box((-hw + 0.1, -hd + 0.01, z), (hw - 0.1, hd - 0.01, z + 0.05))
        sh.plate_xz(chamfer(-0.4, z - 0.03, 0.4, z + 0.0, (0.03, 0.03, 0.0, 0.0)), -hd + 0.0, -hd + 0.02)
    sh.done()
    Part("grey", bevel=0.004, name="shelf lips").box((-hw + 0.12, -hd + 0.0, shelves[0] - 0.035), (hw - 0.12, -hd + 0.015, shelves[0])).done()
    # the stores
    z = shelves[0] + 0.05
    small_case(-0.88, -0.26, z, 0.74, 0.5, 0.36, "white", "orange")
    canister(0.0, -0.05, z, 0.11, 0.3, "grey")
    Part("olive", bevel=0.01, name="jerrycan").box((0.2, -0.22, z), (0.34, 0.2, z + 0.34)).box((0.38, -0.22, z), (0.52, 0.2, z + 0.34)).done()
    small_case(0.6, -0.26, z, 0.3, 0.5, 0.17, "grey", None)
    small_case(0.6, -0.26, z + 0.18, 0.3, 0.5, 0.17, "grey", None)
    z = shelves[1] + 0.05
    small_case(-0.9, -0.26, z, 0.6, 0.5, 0.3, "white", "cyan")
    Part("olive", bevel=0.012, name="pouches").box((-0.22, -0.2, z), (-0.1, 0.1, z + 0.22)).box((-0.06, -0.24, z), (0.06, 0.06, z + 0.2)).done()
    Part("steel", bevel=0.004, name="tool").cyl((0.18, -0.1, z + 0.04), (0.46, -0.16, z + 0.04), 0.022, segs=10).cyl((0.14, -0.09, z + 0.045), (0.2, -0.1, z + 0.045), 0.045, segs=12).done()
    small_case(0.58, -0.24, z, 0.22, 0.44, 0.1, "white", None)
    small_case(0.56, -0.22, z + 0.1, 0.2, 0.4, 0.09, "white", None)
    small_case(0.84, -0.2, z, 0.1, 0.4, 0.26, "white", "orange")
    z = shelves[2] + 0.05
    canister(-0.78, -0.02, z, 0.085, 0.26, "grey")
    canister(-0.58, 0.0, z, 0.085, 0.26, "grey")
    Part("olive", bevel=0.012, name="packs").box((-0.42, -0.22, z), (-0.12, 0.08, z + 0.17)).box((0.0, -0.22, z), (0.3, 0.1, z + 0.2)).done()
    small_case(0.44, -0.26, z, 0.48, 0.5, 0.15, "white", "orange")
    z = shelves[3] + 0.05
    small_case(-0.9, -0.26, z, 0.62, 0.5, 0.32, "white", "cyan")
    canister(-0.1, 0.0, z, 0.11, 0.24, "white")
    small_case(0.08, -0.24, z, 0.3, 0.46, 0.2, "white", None)
    small_case(0.44, -0.24, z, 0.22, 0.46, 0.26, "white", "ledgreen")
    small_case(0.7, -0.24, z, 0.22, 0.46, 0.32, "grey", "orange")
    for (xa, xb, zz) in ((-0.3, 0.25, shelves[3] - 0.02), (0.0, 0.5, shelves[2] - 0.02)):         # cables slung under two shelves
        cable([(xa, -0.1, zz), ((xa + xb) / 2, -0.12, zz - 0.09), (xb, -0.1, zz)], 0.01)


# ------------------------------------------------------------------ the workbench (reference 19): 2.3 m wide, 0.95 m deep
@asset("workbench", views=[(-0.2, -1.0, 0.2), (1.0, -0.1, 0.12)], res=[(700, 620), (460, 620)])
def workbench():
    hw, hd, top = 1.1, 0.45, 0.92
    # the legs: tapering trestles on dark shoes, a rail and a cross brace between them
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (hw - 0.02), sx * (hw - 0.2)))
        Part("white", bevel=0.012, name="leg").plate_yz([(-hd + 0.02, 0.12), (hd - 0.1, 0.12), (hd - 0.04, top - 0.16), (-hd + 0.1, top - 0.16)], x0, x1).done()
        Part("grey", bevel=0.01, name="shoe").plate_yz([(-hd - 0.06, 0.0), (hd - 0.02, 0.0), (hd - 0.02, 0.08), (hd - 0.1, 0.14), (-hd + 0.02, 0.14), (-hd - 0.06, 0.08)], x0 - 0.02, x1 + 0.02).done()
        Part("grey", bevel=0.004, name="leg plate").box(((x0 + x1) / 2 - 0.035, -hd + 0.0, 0.16), ((x0 + x1) / 2 + 0.035, -hd + 0.025, 0.36)).done()
    Part("grey", bevel=0.008, name="rail").box((-hw + 0.2, hd - 0.2, 0.2), (hw - 0.2, hd - 0.12, 0.3)).box((-hw + 0.2, -0.06, 0.16), (hw - 0.2, 0.3, 0.2)).done()
    # the top: a thick slab with a dark work surface, control strips let into its front edge
    Part("white", bevel=0.014, name="top").plate_xy(chamfer(-hw - 0.08, -hd, hw + 0.08, hd, (0.06, 0.06, 0.0, 0.0)), top - 0.16, top).done()
    Part("dark", bevel=0.004, name="surface").box((-hw + 0.04, -hd + 0.05, top), (hw - 0.04, hd - 0.16, top + 0.008)).done()
    Part("dark", bevel=0.004, name="front strips").box((-0.72, -hd - 0.006, top - 0.13), (-0.34, -hd + 0.004, top - 0.04)).box((0.18, -hd - 0.006, top - 0.13), (0.72, -hd + 0.004, top - 0.04)).done()
    ky = Part("grey", bevel=0.002, name="front keys")
    for i in range(6):
        ky.box((0.24 + i * 0.035, -hd - 0.012, top - 0.11), (0.265 + i * 0.035, -hd - 0.006, top - 0.085))
        ky.box((0.24 + i * 0.035, -hd - 0.012, top - 0.075), (0.265 + i * 0.035, -hd - 0.006, top - 0.05))
    ky.box((0.5, -hd - 0.012, top - 0.115), (0.68, -hd - 0.006, top - 0.055))
    ky.box((-0.62, -hd - 0.012, top - 0.11), (-0.4, -hd - 0.006, top - 0.06))
    ky.done()
    Part("ledred", bevel=0.0, name="lamp").box((-0.7, -hd - 0.01, top - 0.075), (-0.675, -hd - 0.006, top - 0.055)).done()
    Part("ledgreen", bevel=0.0, name="lamp").box((-0.7, -hd - 0.01, top - 0.11), (-0.675, -hd - 0.006, top - 0.09)).done()
    for k in range(4):                                       # cables out of the front strip, hanging under the top
        cable([(-0.3 + k * 0.03, -hd + 0.0, top - 0.09 - k * 0.006), (-0.1 + k * 0.03, -hd + 0.02, top - 0.2 - k * 0.02), (0.1, -hd + 0.02, top - 0.11 - k * 0.012),
               (0.2, -hd + 0.0, top - 0.09 - k * 0.008)], 0.009, ("cable", "cable_red", "cable", "cable_tan")[k])
    for k in range(3):
        cable([(-0.7 + k * 0.5, 0.1, top - 0.16), (-0.5 + k * 0.5, 0.0, 0.42 - k * 0.04), (-0.2 + k * 0.4, 0.1, 0.24)], 0.014)
    # the back board with a shelf, instruments on it
    Part("white", bevel=0.012, name="back board").box((-hw + 0.08, hd - 0.14, top), (hw - 0.08, hd - 0.04, top + 0.42)).box((-hw + 0.1, hd - 0.36, top + 0.36), (hw - 0.1, hd - 0.04, top + 0.42)).done()
    Part("dark", bevel=0.004, name="board face").box((-hw + 0.14, hd - 0.15, top + 0.03), (hw - 0.14, hd - 0.14, top + 0.33)).done()
    ins = Part("grey", bevel=0.006, name="instruments")
    ins.box((-0.86, hd - 0.2, top + 0.12), (-0.6, hd - 0.15, top + 0.3)).box((-0.2, hd - 0.2, top + 0.14), (0.02, hd - 0.15, top + 0.3)).box((0.56, hd - 0.2, top + 0.1), (0.9, hd - 0.15, top + 0.3))
    ins.done()
    Part("screen", bevel=0.0, name="read-outs").box((-0.83, hd - 0.204, top + 0.2), (-0.7, hd - 0.2, top + 0.27)).box((-0.17, hd - 0.204, top + 0.2), (-0.01, hd - 0.2, top + 0.27)).done()
    Part("ledgreen", bevel=0.0, name="lamp").box((0.6, hd - 0.204, top + 0.24), (0.64, hd - 0.2, top + 0.26)).box((-0.14, hd - 0.204, top + 0.16), (-0.1, hd - 0.2, top + 0.18)).done()
    Part("ledred", bevel=0.0, name="lamp").box((-0.08, hd - 0.204, top + 0.16), (-0.04, hd - 0.2, top + 0.18)).done()
    # on the bench: a meter, tools, canisters, a part being worked on; on the shelf: canisters and a tool
    z = top + 0.008
    Part("white", bevel=0.01, name="meter").plate_yz([(-0.3, z), (-0.06, z), (-0.06, z + 0.09), (-0.3, z + 0.03)], -0.92, -0.6).done()
    Part("screen", bevel=0.0, name="meter display").box((-0.86, -0.25, z + 0.045), (-0.7, -0.14, z + 0.07)).done(T(loc=(0, 0, 0), rx=0))
    tl = Part("steel", bevel=0.003, name="tools")
    tl.cyl((-0.5, -0.2, z + 0.015), (-0.2, -0.28, z + 0.015), 0.012, segs=8).cyl((-0.42, -0.08, z + 0.012), (-0.24, -0.02, z + 0.012), 0.01, segs=8)
    tl.box((0.02, -0.26, z), (0.36, -0.2, z + 0.03)).box((0.3, -0.3, z), (0.36, -0.16, z + 0.05))
    tl.cyl((0.02, -0.23, z + 0.02), (-0.08, -0.23, z + 0.02), 0.022, segs=10)
    tl.done()
    Part("white", bevel=0.01, name="tester").box((0.28, 0.0, z), (0.5, 0.16, z + 0.2)).done()
    Part("screen", bevel=0.0, name="tester display").box((0.3, -0.004, z + 0.08), (0.48, 0.0, z + 0.17)).done()
    Part("grey", bevel=0.012, name="work piece").cyl((0.74, -0.08, z), (0.74, -0.08, z + 0.1), 0.13, segs=14).box((0.6, -0.2, z), (0.96, 0.02, z + 0.06)).done()
    Part("darksteel", bevel=0.006, name="work piece top").cyl((0.74, -0.08, z + 0.1), (0.74, -0.08, z + 0.16), 0.07, segs=8).done()
    canister(-0.48, 0.14, z, 0.045, 0.16, "white")
    canister(-0.36, 0.16, z, 0.045, 0.16, "white")
    zs = top + 0.42
    canister(-0.82, hd - 0.2, zs, 0.04, 0.13, "grey")
    canister(-0.52, hd - 0.2, zs, 0.045, 0.14, "white")
    Part("steel", bevel=0.004, name="shelf tool").cyl((-0.74, hd - 0.2, zs + 0.035), (-0.6, hd - 0.2, zs + 0.035), 0.03, segs=10).box((0.3, hd - 0.26, zs), (0.5, hd - 0.2, zs + 0.03)) \
        .cyl((0.56, hd - 0.2, zs + 0.05), (0.56, hd - 0.2, zs + 0.11), 0.05, segs=14).done()
    # under the bench: two cases on the rail
    small_case(0.3, -0.2, 0.2, 0.36, 0.44, 0.24, "grey", "ledgreen")
    small_case(0.68, -0.22, 0.2, 0.3, 0.46, 0.34, "grey", None)
    # the back: a housing, cable bundles hanging in loops
    Part("white", bevel=0.012, name="back housing").box((-0.5, hd - 0.04, top + 0.05), (0.5, hd + 0.14, top + 0.4)).done()
    for k in range(6):
        x = -0.4 + k * 0.16
        cable([(x, hd + 0.12, top + 0.1), (x * 1.1, hd + 0.2, 0.6), (x * 0.8 + 0.05, hd + 0.16, 0.36), (x * 0.6, hd + 0.05, 0.5)], 0.016, ("cable", "cable", "cable_red", "cable", "cable", "cable")[k])


# ------------------------------------------------------------------ the charging dock (reference 20): 1.4 m wide, 2.0 m high
@asset("charging_dock", views=[(-0.3, -1.0, 0.14), (1.0, 0.75, 0.2)], res=[(600, 620), (560, 620)])
def charging_dock():
    hw, hd, h = 0.62, 0.4, 1.95
    # the two side towers: white, with grey insets, rounded shoulders; a body between them
    for sx in (-1, 1):
        x0, x1 = sorted((sx * hw, sx * (hw - 0.3)))
        Part("white", bevel=0.03, name="tower").plate_xy(chamfer(x0, -hd, x1, hd, 0.05), 0.16, h).done()
        g = Part("grey", bevel=0.008, name="tower insets")
        xa, xb = sorted((sx * (hw - 0.07), sx * (hw - 0.23)))
        g.box((xa, -hd - 0.012, h - 0.34), (xb, -hd + 0.01, h - 0.06)).box((xa, -hd - 0.012, 0.84), (xb, -hd + 0.01, 1.28))
        g.done()
        ft = Part("grey", bevel=0.012, name="foot")
        ft.plate_xy(chamfer(x0 - 0.04, -hd - 0.08, x1 + 0.04, hd + 0.08, 0.04), 0.0, 0.16)
        ft.done()
        Part("white", bevel=0.006, name="foot plate").box(((x0 + x1) / 2 - 0.04, -hd - 0.1, 0.06), ((x0 + x1) / 2 + 0.04, -hd - 0.07, 0.3)).done()
        # the cable loops down the tower's side
        for k in range(4):
            xs = sx * (hw + 0.02 + k * 0.01)
            cable([(xs - sx * 0.04, -0.12 + k * 0.07, 1.5), (xs + sx * 0.1, -0.14 + k * 0.07, 1.25), (xs + sx * 0.13, -0.12 + k * 0.07, 0.95), (xs + sx * 0.06, -0.1 + k * 0.07, 0.72),
                   (xs - sx * 0.04, -0.1 + k * 0.07, 0.66)], 0.016, ("cable", "cable", "cable_red", "cable")[k])
        Part("grey", bevel=0.006, name="cable clamp").box(tuple(sorted((sx * (hw - 0.01), sx * (hw + 0.06))))[0:1] + (-0.2, 1.42), tuple(sorted((sx * (hw - 0.01), sx * (hw + 0.06))))[1:2] + (0.2, 1.54)) \
            .box(tuple(sorted((sx * (hw - 0.01), sx * (hw + 0.06))))[0:1] + (-0.2, 0.6), tuple(sorted((sx * (hw - 0.01), sx * (hw + 0.06))))[1:2] + (0.2, 0.72)).done()
    Part("white", bevel=0.016, name="head").box((-hw + 0.3, -hd + 0.02, 1.52), (hw - 0.3, hd - 0.04, h - 0.03)).box((-hw + 0.3, -hd + 0.02, 0.2), (hw - 0.3, hd - 0.04, 0.56)).done()
    Part("grey", bevel=0.006, name="head slot").plate_xz(rounded(-0.2, h - 0.2, 0.2, h - 0.13, 0.03), -hd + 0.006, -hd + 0.02).plate_xz(rounded(-0.2, 0.36, 0.2, 0.43, 0.03), -hd + 0.006, -hd + 0.02).done()
    # the bay: dark, three shelves of sockets, some with plugs and cables
    Part("dark", bevel=0.0, name="bay").box((-hw + 0.3, -hd + 0.1, 0.56), (hw - 0.3, hd - 0.04, 1.52)).done()
    Part("grey", bevel=0.006, name="bay shelves").box((-hw + 0.3, -hd + 0.06, 0.56), (hw - 0.3, -hd + 0.14, 0.6)).box((-hw + 0.3, -hd + 0.06, 0.86), (hw - 0.3, -hd + 0.14, 0.9)) \
        .box((-hw + 0.3, -hd + 0.06, 1.18), (hw - 0.3, -hd + 0.14, 1.22)).box((-hw + 0.3, -hd + 0.06, 1.48), (hw - 0.3, -hd + 0.14, 1.52)).done()
    sk = Part("grey", bevel=0.006, name="sockets")
    plugs = Part("white", bevel=0.006, name="plugs")
    y = -hd + 0.1
    plugged = {(0, 0): "cable", (2, 0): "cable", (1, 1): "cable", (2, 2): "cable", (0, 2): None}
    for r_, z in enumerate((0.62, 0.92, 1.24)):
        for c_ in range(3):
            x = -0.2 + c_ * 0.2
            sk.plate_xz(chamfer(x - 0.07, z, x + 0.07, z + 0.2, 0.02), y - 0.01, y + 0.02)
            if (c_, r_) in plugged:
                plugs.box((x - 0.035, y - 0.07, z + 0.05), (x + 0.035, y - 0.01, z + 0.15))
    sk.done()
    plugs.done()
    Part("dark", bevel=0.0, name="socket holes").box((-0.03, y - 0.012, 0.69), (0.03, y - 0.01, 0.76)).box((-0.03, y - 0.012, 1.31), (0.03, y - 0.01, 1.38)) \
        .box((-0.23, y - 0.012, 0.99), (-0.17, y - 0.01, 1.06)).box((0.17, y - 0.012, 0.99), (0.23, y - 0.01, 1.06)).done()
    for (c_, r_), _m in plugged.items():
        x, z = -0.2 + c_ * 0.2, (0.62, 0.92, 1.24)[r_]
        cable([(x, y - 0.07, z + 0.06), (x + 0.03, y - 0.13, z - 0.08), (x + 0.1 * (1 - c_) + 0.02, y - 0.1, z - 0.2), (x * 0.5, y - 0.02, 0.6 if r_ == 0 else z - 0.3)], 0.014)
    Part("cyan", bevel=0.0, name="lamp").box((-0.26, y - 0.012, 1.455), (-0.16, y - 0.01, 1.47)).box((0.16, y - 0.012, 1.455), (0.26, y - 0.01, 1.47)).box((-0.26, y - 0.012, 1.145), (-0.12, y - 0.01, 1.16)) \
        .box((-0.24, y - 0.012, 0.615), (-0.2, y - 0.01, 0.63)).done()
    Part("orange", bevel=0.0, name="lamp").box((0.0, y - 0.012, 0.835), (0.08, y - 0.01, 0.85)).box((-0.06, y - 0.012, 1.145), (-0.02, y - 0.01, 1.16)).done()
    Part("ledblue", bevel=0.0, name="lamp").box((0.14, y - 0.012, 0.835), (0.24, y - 0.01, 0.85)).done()
    # the back: a transformer housing with fins, a junction box, cables from it to the towers
    yb = hd - 0.04
    Part("white", bevel=0.014, name="back housing").box((-0.34, yb, 0.5), (0.34, yb + 0.22, 1.86)).done()
    fn = Part("darksteel", bevel=0.0, name="fins")
    for i in range(10):
        fn.box((-0.28 + i * 0.06, yb + 0.1, 1.9), (-0.25 + i * 0.06, yb + 0.2, 2.0)) if False else fn.box((-0.28 + i * 0.06, yb + 0.04, 1.86), (-0.25 + i * 0.06, yb + 0.2, 1.94))
        fn.box((-0.28 + i * 0.06, yb + 0.22, 0.62), (-0.25 + i * 0.06, yb + 0.25, 0.9))
    fn.done()
    Part("grey", bevel=0.008, name="back box").box((0.02, yb + 0.22, 1.2), (0.3, yb + 0.3, 1.6)).box((-0.3, yb + 0.22, 1.0), (-0.06, yb + 0.28, 1.76)).done()
    for sx in (-1, 1):
        for k in range(3):
            cable([(-0.18, yb + 0.28, 1.6 - k * 0.2), (sx * 0.4, yb + 0.26, 1.5 - k * 0.2), (sx * (hw - 0.04), hd + 0.02, 1.2 - k * 0.2), (sx * (hw + 0.03), 0.2, 1.0 - k * 0.12)], 0.016,
                  ("cable", "cable_red", "cable")[k])
    Part("grey", bevel=0.01, name="back brace").plate_yz([(yb, 0.16), (yb + 0.36, 0.16), (yb + 0.36, 0.26), (yb + 0.2, 0.5), (yb, 0.5)], -0.3, 0.3).done()


# ------------------------------------------------------------------ the pipe riser (reference 21): 0.25 m pipe, 2.7 m high
@asset("pipe_riser", views=[(-0.35, -1.0, 0.1), (1.0, 0.0, 0.05)], res=[(520, 620), (560, 620)])
def pipe_riser():
    r, h = 0.11, 2.7
    yw = 0.42                                               # the wall's face behind it (the brackets reach it)
    # the riser comes up from the floor and turns into the wall at the top; a branch leaves low down
    pipe([(0, 0, 0.06), (0, 0, h - 0.32), (0, 0.3, h - 0.02 - 0.1), (0, yw - 0.02, h - 0.12)], r, "pipe", fillet=0.24, res=8)
    pipe([(0, 0, 0.42), (0, 0.16, 0.42), (0, yw - 0.02, 0.42)], r * 0.8, "pipe", fillet=0.05, res=8)
    fl = Part("grey", bevel=0.006, name="flanges")
    for z in (0.0, 0.3, 0.72, 1.0, 1.9, 2.06):
        fl.cyl((0, 0, z), (0, 0, z + 0.06), r + 0.045, segs=24)
    fl.cyl((0, yw - 0.1, h - 0.12), (0, yw - 0.02, h - 0.12), r + 0.045, segs=24).cyl((0, yw - 0.1, 0.42), (0, yw - 0.02, 0.42), r * 0.8 + 0.04, segs=24)
    fl.cyl((0, 0.14, 0.42), (0, 0.2, 0.42), r * 0.8 + 0.035, segs=24)
    fl.done()
    bl = Part("steel", bevel=0.0, name="flange bolts")
    for z in (0.06, 0.36, 0.78, 1.06, 1.96, 2.12):
        for a in range(0, 360, 45):
            bl.bolt(((r + 0.025) * math.cos(math.radians(a)), (r + 0.025) * math.sin(math.radians(a)), z), axis=(0, 0, 1), r=0.011, h=0.008)
    bl.done()
    Part("grey", bevel=0.008, name="sleeves").cyl((0, 0, 0.78), (0, 0, 1.0), r + 0.012, segs=24).cyl((0, 0, 1.5), (0, 0, 1.62), r + 0.012, segs=24).cyl((0, 0, 0.06), (0, 0, 0.14), r + 0.015, segs=24).done()
    rb = Part("redband", bevel=0.0, name="bands")
    for z in (0.52, 1.72, 2.2):
        rb.cyl((0, 0, z), (0, 0, z + 0.07), r + 0.003, segs=24)
    rb.cyl((0, 0.24, h - 0.045), (0, 0.3, h - 0.045 - 0.0), r + 0.003, segs=24) if False else None
    rb.done()
    # the valve: a body on the riser, its wheel facing the room
    Part("white", bevel=0.014, name="valve body").cyl((0, -0.02, 1.16), (0, -0.02, 1.42), r + 0.035, segs=24).cyl((0, -r - 0.02, 1.29), (0, -r - 0.14, 1.29), 0.075, segs=16).done()
    valve_wheel((0, -r - 0.2, 1.29), (0, -1, 0), R=0.13, material="grey")
    Part("steel", bevel=0.003, name="valve stem").cyl((0, -r - 0.14, 1.29), (0, -r - 0.2, 1.29), 0.022, segs=10).done()
    # the switch box on the riser, the gauge and its capillary, the junction box on the wall bracket
    Part("white", bevel=0.01, name="switch").box((-0.06, -r - 0.06, 1.66), (0.06, -r + 0.02, 1.86)).done()
    Part("darksteel", bevel=0.004, name="switch lever").box((-0.02, -r - 0.085, 1.72), (0.02, -r - 0.06, 1.8)).done()
    pipe([(r - 0.02, 0.0, 1.66), (r + 0.1, 0.0, 1.66), (r + 0.1, 0.0, 2.2)], 0.012, "steel", fillet=0.03)
    Part("white", bevel=0.006, name="gauge").cyl((r + 0.1, -0.035, 2.26), (r + 0.1, 0.02, 2.26), 0.065, segs=24).done()
    Part("cross", bevel=0.0, name="gauge face").cyl((r + 0.1, -0.04, 2.26), (r + 0.1, -0.035, 2.26), 0.052, segs=24).done()
    Part("ink", bevel=0.0, name="gauge needle").box((r + 0.097, -0.043, 2.26), (r + 0.103, -0.04, 2.3)).done(T(loc=(0, 0, 0)))
    Part("white", bevel=0.01, name="junction").box((r + 0.02, 0.1, 1.5), (r + 0.16, 0.24, 1.76)).done()
    Part("dark", bevel=0.0, name="junction plate").box((r + 0.04, 0.094, 1.56), (r + 0.14, 0.1, 1.66)).done()
    cable([(r + 0.1, 0.02, 2.2), (r + 0.11, 0.12, 2.0), (r + 0.09, 0.17, 1.76)], 0.01)
    cable([(r + 0.09, 0.17, 1.5), (r + 0.1, 0.16, 1.36), (r + 0.06, 0.1, 1.24)], 0.01)
    # the brackets to the wall: a saddle on the pipe, two arms, a foot plate
    for z in (0.42, 1.62, h - 0.12):
        if z == 1.62:
            br = Part("grey", bevel=0.006, name="bracket")
            br.box((-r - 0.06, -0.02, z - 0.05), (r + 0.06, 0.05, z + 0.05))
            br.done()
        ft = Part("grey", bevel=0.006, name="bracket foot")
        ft.box((-r - 0.1, yw - 0.02, z - 0.16), (r + 0.1, yw, z + 0.16))
        for dz in (-0.1, 0.1):
            ft.box((-0.03, 0.05 if z == 1.62 else yw - 0.16, z + dz - 0.02), (0.03, yw - 0.02, z + dz + 0.02)) if z == 1.62 else None
        ft.done()
