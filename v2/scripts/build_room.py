"""V2 concept scene, stage 1: the lab room and its lighting -> v2/scene.blend (+ render with render.py).

    blender -b -P v2/scripts/build_room.py

Metres, Z up, the player looks along +Y from (0.2, 0, 1.62). Built after v2/reference/scene_concept.png:
white panelled walls on a dark backing, tiled floor, two clad columns, a mezzanine along the back wall with a
steel stair and tube railings, a raised gallery on the right, doors with light strips and keypads, glass tanks
with liquid and bubbles, ceiling light wells with diffuser grids, conduits and cables.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import v2lib as L  # noqa: E402

random.seed(7)
XL, XR, Y0, Y1, H = -4.6, 6.4, -3.0, 14.0, 5.2
MZ = 2.6            # mezzanine floor height
MY = 10.9           # mezzanine front edge
GX = 4.9            # gallery wall on the right (lower level), for y < GY
GY = 7.0

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = L.setup_cycles()

# ---------------------------------------------------------------- materials
M_PANEL = L.pbr("WallPanel", "PaintedPlaster017", scale=2.0, tint=(0.9, 0.94, 1.0), rough=(0.3, 0.55), normal=0.6,
                tint_attr="tint", grunge=0.12, grunge_scale=1.3)
M_CONC = L.pbr("Concrete", "Concrete034", scale=3.0, tint=(0.74, 0.76, 0.79), rough=(0.5, 0.85), grunge=0.15)
M_FLOOR = L.pbr("FloorTile", "Concrete034", scale=2.5, tint=(0.66, 0.68, 0.71), rough=(0.03, 0.2), normal=0.22,
                tint_attr="tint", grunge=0.2, grunge_scale=0.45)
M_BACK = L.plain("Backing", (0.03, 0.032, 0.035), rough=0.7)
M_STEEL = L.pbr("Steel", "Metal032", scale=1.0, tint=(0.62, 0.64, 0.67), rough=(0.3, 0.55))
M_DARK = L.pbr("DarkSteel", "Metal032", scale=1.0, tint=(0.16, 0.17, 0.19), rough=(0.35, 0.6))
M_GRATE = L.pbr("Grating", "MetalWalkway010", scale=0.6, tint=(1.6, 1.6, 1.7), rough=(0.3, 0.6))
M_RUBBER = L.plain("Cable", (0.02, 0.02, 0.022), rough=0.55)
M_LIGHT = L.plain("CeilingLight", (1, 1, 1), emit=(0.97, 0.985, 1.0), emit_strength=8.0)
M_STRIP = L.plain("LightStrip", (1, 1, 1), emit=(0.95, 0.98, 1.0), emit_strength=30.0)
M_CYAN = L.plain("ScreenCyan", (0.0, 0.02, 0.03), emit=(0.15, 0.85, 1.0), emit_strength=6.0)
M_TANKLIGHT = L.plain("TankLight", (1, 1, 1), emit=(0.75, 0.95, 1.0), emit_strength=20.0)
M_GLASSDARK = L.plain("DarkGlass", (0.02, 0.03, 0.04), rough=0.05, metallic=0.6)
M_BUBBLE = L.plain("Bubble", (1.0, 1.0, 1.0), rough=0.15, emit=(0.8, 0.97, 1.0), emit_strength=0.5)


def liquid_material():
    m = bpy.data.materials.new("TankLiquid")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.82, 0.96, 0.97, 1)
    b.inputs["Roughness"].default_value = 0.02
    b.inputs["Transmission Weight"].default_value = 1.0
    b.inputs["IOR"].default_value = 1.36
    # Slightly milky, softly glowing liquid: it picks up the ring light instead of acting as a black lens.
    pv = nt.nodes.new("ShaderNodeVolumePrincipled")
    pv.inputs["Color"].default_value = (0.7, 0.95, 1.0, 1)
    pv.inputs["Density"].default_value = 0.28
    pv.inputs["Anisotropy"].default_value = 0.3
    pv.inputs["Emission Color"].default_value = (0.45, 0.9, 1.0, 1)
    pv.inputs["Emission Strength"].default_value = 0.12
    nt.links.new(pv.outputs[0], nt.nodes["Material Output"].inputs["Volume"])
    return m


M_LIQUID = liquid_material()


# ---------------------------------------------------------------- floor
floor = L.Builder("FloorTiles", M_FLOOR, bevel=0.003, tint_layer=True)
T = 1.2
nx, ny = int(math.ceil((XR - XL) / T)), int(math.ceil((Y1 - Y0) / T))
for i in range(nx):
    for j in range(ny):
        t = random.uniform(0.86, 1.0)
        floor.box((XL + i * T + 0.006, Y0 + j * T + 0.006, -0.03), (XL + (i + 1) * T - 0.006, Y0 + (j + 1) * T - 0.006, 0.0),
                  tint=(t, t, t * random.uniform(0.99, 1.01), 1))
floor.finish()
base = L.Builder("FloorBase", M_BACK, bevel=0)
base.box((XL - 0.5, Y0 - 0.5, -0.3), (XR + 0.5, Y1 + 0.5, -0.012))
base.finish()

# ---------------------------------------------------------------- walls
back = L.Builder("WallBacking", M_BACK, bevel=0)
panels = L.Builder("WallPanels", M_PANEL, bevel=0.006, tint_layer=True)
bands = L.Builder("WallBands", M_CONC, bevel=0.008)
kick = L.Builder("WallKick", M_STEEL, bevel=0.006)
trim = L.Builder("Trim", M_DARK, bevel=0.004)


def wall(axis, fixed, a0, a1, sign, z0=0.0, z1=H, rows=3, panel_w=1.55):
    """Panelled wall in the plane axis=fixed, spanning a0..a1 on the other axis; sign = direction into the room."""
    def bx(a_lo, a_hi, zl, zh, d0, d1, b):
        lo_d, hi_d = sorted((fixed + sign * d0, fixed + sign * d1))
        if axis == "x":
            b.box((lo_d, a_lo, zl), (hi_d, a_hi, zh))
        else:
            b.box((a_lo, lo_d, zl), (a_hi, hi_d, zh))
    bx(a0, a1, z0, z1, -0.3, 0.0, back)
    kz = min(z0 + 0.55, z1)
    bx(a0, a1, z0, kz, 0.0, 0.07, kick)
    top = z1 - 0.7 if z1 - z0 > 3.5 else z1 - 0.12
    n = max(1, round((a1 - a0) / panel_w))
    w = (a1 - a0) / n
    rh = (top - kz - 0.03) / rows
    for i in range(n):
        for r in range(rows):
            panels.next_tint = (random.uniform(0.93, 1.0),) * 3 + (1,)
            bx(a0 + i * w + 0.008, a0 + (i + 1) * w - 0.008, kz + 0.03 + r * rh + 0.008, kz + 0.03 + (r + 1) * rh - 0.008,
               0.0, 0.045, panels)
            # a bolt in each corner of the panel
            for da, dz in ((0.07, 0.07), (w - 0.07, 0.07), (0.07, rh - 0.07), (w - 0.07, rh - 0.07)):
                p = [0, 0, kz + 0.03 + r * rh + dz]
                p[0 if axis == "y" else 1] = a0 + i * w + da
                p[0 if axis == "x" else 1] = fixed + sign * 0.045
                q = list(p)
                q[0 if axis == "x" else 1] = fixed + sign * 0.052
                trim.cyl(p, q, 0.011, segs=8)
    if z1 - z0 > 3.5:
        bx(a0, a1, top + 0.02, z1, 0.0, 0.09, bands)


wall("x", XL, Y0, Y1, +1)                      # left
wall("y", Y1, XL, XR, -1, z0=0.0, z1=MZ - 0.25, rows=2)   # back, under the mezzanine
wall("y", Y1, XL, XR, -1, z0=MZ, z1=H, rows=2)            # back, above it
wall("x", XR, GY, Y1, -1)                      # right, far part
wall("x", GX, Y0, GY, -1, z0=0.0, z1=MZ, rows=2)          # right gallery, lower wall
wall("y", GY, GX, XR, -1, z0=0.0, z1=MZ, rows=2)          # gallery end wall
wall("x", XR, Y0, GY, -1, z0=MZ, z1=H, rows=2)            # wall above the gallery
wall("y", Y0, XL, XR, +1)                      # behind the player

# gallery slab + edge beam, conduits along it
bands.box((GX - 0.08, Y0, MZ - 0.02), (XR, GY + 0.08, MZ + 0.14))
kick.box((GX - 0.1, Y0, MZ - 0.3), (GX + 0.02, GY + 0.1, MZ - 0.02))
for k, (dz, r) in enumerate(((0.45, 0.05), (0.62, 0.035), (0.75, 0.035))):
    trim.cyl((GX + 0.5 + k * 0.02, Y0, MZ + dz), (GX + 0.5 + k * 0.02, GY - 0.3, MZ + dz), r, segs=12)
for y in (-1.5, 1.0, 3.5, 6.0):
    kick.box((GX + 0.38, y - 0.04, MZ + 0.14), (GX + 0.62, y + 0.04, MZ + 0.86))

# ---------------------------------------------------------------- columns
COLS = [(-3.3, 8.6), (2.1, 8.6)]
for cx, cy in COLS:
    back.box((cx - 0.52, cy - 0.52, 0), (cx + 0.52, cy + 0.52, H))
    kick.box((cx - 0.66, cy - 0.66, 0), (cx + 0.66, cy + 0.66, 0.42))
    bands.box((cx - 0.66, cy - 0.66, H - 0.5), (cx + 0.66, cy + 0.66, H))
    rows, z0, z1 = 4, 0.46, H - 0.54
    rh = (z1 - z0) / rows
    for r in range(rows):
        za, zb = z0 + r * rh + 0.008, z0 + (r + 1) * rh - 0.008
        panels.box((cx - 0.5, cy - 0.585, za), (cx + 0.5, cy - 0.52, zb))
        panels.box((cx - 0.5, cy + 0.52, za), (cx + 0.5, cy + 0.585, zb))
        panels.box((cx - 0.585, cy - 0.5, za), (cx - 0.52, cy + 0.5, zb))
        panels.box((cx + 0.52, cy - 0.5, za), (cx + 0.585, cy + 0.5, zb))
    for sx in (-1, 1):
        for sy in (-1, 1):   # corner posts
            kick.box((cx + sx * 0.6 - 0.035, cy + sy * 0.6 - 0.035, 0.42), (cx + sx * 0.6 + 0.035, cy + sy * 0.6 + 0.035, H - 0.5))

# ---------------------------------------------------------------- ceiling: beams + light wells
ceil = L.Builder("CeilingBeams", M_CONC, bevel=0.01)
lights = L.Builder("CeilingLights", M_LIGHT, bevel=0)
grid = L.Builder("LightGrid", M_STEEL, bevel=0.002)
WX = [(-4.3, -1.5), (-0.9, 2.3), (2.9, 6.1)]
WY = [(-2.6, 1.0), (1.7, 5.3), (6.0, 9.6), (10.3, 13.7)]
xs = [XL] + [v for w in WX for v in w] + [XR]
ys = [Y0] + [v for w in WY for v in w] + [Y1]
for i in range(0, len(xs), 2):
    ceil.box((xs[i], Y0, H), (xs[i + 1], Y1, H + 0.75))
for j in range(0, len(ys), 2):
    for (xa, xb) in WX:
        ceil.box((xa, ys[j], H), (xb, ys[j + 1], H + 0.75))
ceil.box((XL - 0.3, Y0 - 0.3, H + 0.75), (XR + 0.3, Y1 + 0.3, H + 0.9))
for (xa, xb) in WX:
    for (ya, yb) in WY:
        lights.box((xa + 0.02, ya + 0.02, H + 0.62), (xb - 0.02, yb - 0.02, H + 0.7))
        for k in (1, 2):       # diffuser grid
            x = xa + (xb - xa) * k / 3
            y = ya + (yb - ya) * k / 3
            grid.box((x - 0.02, ya, H + 0.5), (x + 0.02, yb, H + 0.6))
            grid.box((xa, y - 0.02, H + 0.5), (xb, y + 0.02, H + 0.6))

# ---------------------------------------------------------------- mezzanine, stairs, railings
mezz = L.Builder("Mezzanine", M_CONC, bevel=0.008)
steel = L.Builder("Steelwork", M_STEEL, bevel=0.004)
grate = L.Builder("Treads", M_GRATE, bevel=0)
rail = L.Builder("Railings", M_STEEL, bevel=0)
mezz.box((XL, MY, MZ - 0.22), (XR, Y1, MZ))
steel.box((XL, MY - 0.1, MZ - 0.42), (XR, MY, MZ + 0.05))                 # fascia beam
steel.box((XL, MY - 0.16, MZ - 0.42), (XR, MY - 0.1, MZ - 0.36))          # its lower flange
steel.box((XL, MY - 0.16, MZ - 0.01), (XR, MY - 0.1, MZ + 0.05))          # upper flange
for x in (-4.3, -1.7, 0.9, 3.5, 6.1):
    steel.box((x - 0.09, MY + 0.02, 0), (x + 0.09, MY + 0.2, MZ - 0.42))  # posts
    steel.box((x - 0.15, MY - 0.04, 0), (x + 0.15, MY + 0.26, 0.03))      # base plates
LX0, LX1 = -2.4, -1.2            # landing
SY0, SY1 = MY - 1.1, MY          # stair width
mezz.box((LX0, SY0, MZ - 0.12), (LX1, SY1 - 0.1, MZ))
steel.box((LX0 - 0.03, SY0 - 0.03, MZ - 0.3), (LX1, SY0 + 0.03, MZ + 0.02))
steel.box((LX0 - 0.03, SY0, MZ - 0.3), (LX0 + 0.03, SY1 - 0.1, MZ + 0.02))
steel.box((LX0 + 0.05, SY0 + 0.05, 0), (LX0 + 0.2, SY0 + 0.2, MZ - 0.3))
RUN, STEPS = 4.2, 15
rise, going = MZ / STEPS, RUN / STEPS
ang = math.atan2(MZ, RUN)
for i in range(STEPS - 1):
    x = LX1 + i * going
    z = MZ - (i + 1) * rise
    grate.box((x, SY0 + 0.05, z - 0.035), (x + going + 0.02, SY1 - 0.05, z))
    steel.box((x, SY0 + 0.05, z - 0.05), (x + 0.025, SY1 - 0.05, z))      # nosing bar
mid = Vector((LX1 + RUN / 2, 0, MZ / 2 - 0.12))
length = math.hypot(RUN, MZ) + 0.2
for y in (SY0 + 0.02, SY1 - 0.02):
    steel.box((mid.x - length / 2, y - 0.02, mid.z - 0.14), (mid.x + length / 2, y + 0.02, mid.z + 0.14),
              rot=Matrix.Rotation(ang, 4, "Y"), pivot=(mid.x, y, mid.z))


def railing(p0, p1, post_every=1.1, h=1.05, slope=False):
    """Tube railing from p0 to p1 (points on the walking surface)."""
    p0, p1 = Vector(p0), Vector(p1)
    n = max(1, round((p1 - p0).length / post_every))
    for i in range(n + 1):
        p = p0.lerp(p1, i / n)
        rail.cyl(p, p + Vector((0, 0, h)), 0.022, segs=10)
        rail.cyl(p, p + Vector((0, 0, 0.012)), 0.05, segs=10)
    up = Vector((0, 0, 1))
    rail.cyl(p0 + up * h, p1 + up * h, 0.028, segs=12)
    for f in (0.33, 0.66):
        rail.cyl(p0 + up * h * f, p1 + up * h * f, 0.014, segs=8)
    rail.cyl(p0 + up * 0.1, p1 + up * 0.1, 0.014, segs=8)


railing((XL + 0.15, MY - 0.05, MZ), (LX0, MY - 0.05, MZ))
railing((LX1, MY - 0.05, MZ), (XR - 0.15, MY - 0.05, MZ))
railing((LX0, SY0, MZ), (LX1, SY0, MZ))
railing((LX0, SY0, MZ), (LX0, MY - 0.05, MZ))
railing((LX1, SY0, MZ), (LX1 + RUN, SY0, 0.0), post_every=1.0)
railing((LX1 + 0.3, SY1, MZ - 0.2), (LX1 + RUN, SY1, 0.0), post_every=1.0)

# ---------------------------------------------------------------- doors
doorf = L.Builder("DoorFrames", M_DARK, bevel=0.006)
doorl = L.Builder("DoorLeaves", M_STEEL, bevel=0.005)
strips = L.Builder("LightStrips", M_STRIP, bevel=0)
screens = L.Builder("Screens", M_CYAN, bevel=0)
glassd = L.Builder("DoorGlass", M_GLASSDARK, bevel=0.002)


def door(axis, fixed, a, z0, sign, w=1.3, h=2.25):
    def bx(b, a_lo, a_hi, zl, zh, d0, d1):
        lo_d, hi_d = sorted((fixed + sign * d0, fixed + sign * d1))
        if axis == "x":
            b.box((lo_d, a_lo, zl), (hi_d, a_hi, zh))
        else:
            b.box((a_lo, lo_d, zl), (a_hi, hi_d, zh))
    bx(doorf, a - w / 2 - 0.14, a + w / 2 + 0.14, z0, z0 + h + 0.3, 0.0, 0.13)          # frame block
    bx(doorl, a - w / 2, a - 0.006, z0 + 0.02, z0 + h, 0.1, 0.16)                        # two leaves
    bx(doorl, a + 0.006, a + w / 2, z0 + 0.02, z0 + h, 0.1, 0.16)
    for s in (-1, 1):                                                                    # raised panels + window
        c = a + s * w / 4
        bx(doorl, c - w / 4 + 0.07, c + w / 4 - 0.07, z0 + 0.15, z0 + 0.95, 0.15, 0.175)
        bx(doorl, c - w / 4 + 0.07, c + w / 4 - 0.07, z0 + 1.75, z0 + h - 0.1, 0.15, 0.175)
        bx(glassd, c - w / 4 + 0.09, c + w / 4 - 0.09, z0 + 1.08, z0 + 1.62, 0.15, 0.168)
    bx(strips, a - w / 2 + 0.1, a + w / 2 - 0.1, z0 + h + 0.12, z0 + h + 0.2, 0.12, 0.14)  # light over the door
    k = a + w / 2 + 0.38                                                                  # keypad
    bx(doorf, k - 0.08, k + 0.08, z0 + 1.15, z0 + 1.45, 0.04, 0.09)
    bx(screens, k - 0.055, k + 0.055, z0 + 1.32, z0 + 1.42, 0.085, 0.095)


door("x", XL, 5.2, 0.0, +1)
door("x", XL, 9.0, 0.0, +1)
door("y", Y1, 5.3, 0.0, -1)
door("y", Y1, 1.0, MZ, -1)
door("y", Y1, -3.0, MZ, -1)

# ---------------------------------------------------------------- tanks
tankm = L.Builder("TankMetal", M_STEEL, bevel=0.006)
tankd = L.Builder("TankDark", M_DARK, bevel=0.004)
liquid = L.Builder("TankLiquid", M_LIQUID, bevel=0)
tlight = L.Builder("TankLights", M_TANKLIGHT, bevel=0)
bubbles = L.Builder("Bubbles", M_BUBBLE, bevel=0)
import bmesh  # noqa: E402
for tx, ty in ((-3.75, 4.3), (4.1, 4.6), (-3.75, 11.9), (4.1, 1.2)):
    tankm.cyl((tx, ty, 0), (tx, ty, 0.12), 0.86, segs=40)
    tankm.cyl((tx, ty, 0.12), (tx, ty, 0.55), 0.74, segs=40)
    tankd.cyl((tx, ty, 0.55), (tx, ty, 0.6), 0.66, segs=40)
    liquid.cyl((tx, ty, 0.6), (tx, ty, 3.2), 0.6, segs=48)
    tlight.cyl((tx, ty, 3.2), (tx, ty, 3.23), 0.56, segs=40)
    tankd.cyl((tx, ty, 3.23), (tx, ty, 3.3), 0.66, segs=40)
    tankm.cyl((tx, ty, 3.3), (tx, ty, 3.75), 0.74, segs=40)
    tankm.cyl((tx, ty, 3.75), (tx, ty, 3.85), 0.5, segs=32)
    for a in range(4):          # vertical guard rods + clamps
        ax, ay = tx + 0.68 * math.cos(a * math.pi / 2 + 0.6), ty + 0.68 * math.sin(a * math.pi / 2 + 0.6)
        tankd.cyl((ax, ay, 0.55), (ax, ay, 3.3), 0.018, segs=8)
    for k, (dx, dy) in enumerate(((0.22, 0.1), (-0.2, 0.15))):
        tankd.cyl((tx + dx, ty + dy, 3.85), (tx + dx, ty + dy, H + 0.3), 0.05 - 0.012 * k, segs=12)
    for _ in range(110):
        # bubbles rise in three loose streams from the base
        st = random.randrange(3)
        r, a = 0.18 + 0.12 * random.random() ** 2 * 2.0, st * math.tau / 3 + 0.5 + random.gauss(0, 0.22)
        z = random.uniform(0.7, 3.1)
        bmesh.ops.create_icosphere(bubbles.bm, subdivisions=1, radius=random.uniform(0.006, 0.02) * (1.0 + 0.8 * (z - 0.7) / 2.4),
                                   matrix=Matrix.Translation((tx + r * math.cos(a), ty + r * math.sin(a), z)))

# ---------------------------------------------------------------- cables, vents, signs
for k in range(5):      # bundle along the top of the left wall, sagging between clips
    pts = []
    for y in range(-2, 15, 2):
        pts.append((XL + 0.14 + k * 0.012, y, 4.25 - 0.045 * k + (0.0 if y % 4 == 0 else -0.07)))
    L.curve_tube(f"CableL{k}", pts, 0.016, M_RUBBER)
for y in range(-2, 15, 4):
    trim.box((XL + 0.05, y - 0.03, 4.0), (XL + 0.24, y + 0.03, 4.32))
L.curve_tube("CableDrop1", [(XL + 0.15, 6.0, 4.2), (XL + 0.2, 6.6, 3.2), (XL + 0.16, 7.1, 1.6), (XL + 0.15, 7.15, 0.6)], 0.02, M_RUBBER)
L.curve_tube("CableCol", [(-3.3, 7.4, H), (-3.1, 6.9, 4.5), (-2.2, 6.2, 4.75), (-1.2, 5.6, H + 0.1)], 0.022, M_RUBBER)
L.curve_tube("CableCol2", [(2.0, 7.4, H), (2.4, 6.6, 4.6), (3.4, 6.1, 4.8), (4.1, 4.9, 3.9)], 0.02, M_RUBBER)
for x, z in ((-1.0, 3.3), (3.4, 3.3)):       # vents on the back wall above the mezzanine
    trim.box((x - 0.4, Y1 - 0.07, z), (x + 0.4, Y1 - 0.045, z + 0.4))
    for i in range(6):
        kick.box((x - 0.36, Y1 - 0.1, z + 0.04 + i * 0.06), (x + 0.36, Y1 - 0.065, z + 0.065 + i * 0.06),
                 rot=Matrix.Rotation(0.5, 4, "X"))
for y, z in ((2.2, 1.5), (7.2, 1.5)):        # wall boxes on the left
    trim.box((XL + 0.045, y - 0.18, z), (XL + 0.13, y + 0.18, z + 0.5))
    screens.box((XL + 0.13, y - 0.1, z + 0.3), (XL + 0.135, y + 0.1, z + 0.42))


# ================================================================ pass 2: detail, clutter, light accents
M_GALV = L.pbr("Galvanised", "Metal032", scale=0.8, tint=(0.82, 0.84, 0.86), rough=(0.25, 0.5), grunge=0.15)
M_YELLOW = L.plain("FloorPaint", (0.75, 0.52, 0.03), rough=0.45)
M_COVE = L.plain("CoveLight", (1, 1, 1), emit=(0.85, 0.95, 1.0), emit_strength=10.0)
M_GREEN = L.plain("SignGreen", (0.0, 0.03, 0.01), emit=(0.2, 1.0, 0.45), emit_strength=5.0)
M_ORANGE = L.plain("StatusOrange", (0.03, 0.01, 0.0), emit=(1.0, 0.45, 0.1), emit_strength=8.0)


def hazard_material():
    m = bpy.data.materials.new("Hazard")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wv = nt.nodes.new("ShaderNodeTexWave")
    wv.bands_direction = "DIAGONAL"
    wv.inputs["Scale"].default_value = 9.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = (0.02, 0.02, 0.02, 1)
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = (0.8, 0.55, 0.02, 1)
    nt.links.new(tc.outputs["Object"], wv.inputs["Vector"])
    nt.links.new(wv.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.5
    return m


M_HAZ = hazard_material()
galv = L.Builder("Ducts", M_GALV, bevel=0.006)
tray = L.Builder("CableTrays", M_DARK, bevel=0.002)
paint = L.Builder("FloorPaint", M_YELLOW, bevel=0)
cove = L.Builder("CoveLights", M_COVE, bevel=0)
green = L.Builder("SignsGreen", M_GREEN, bevel=0)
orange = L.Builder("StatusLights", M_ORANGE, bevel=0)
haz = L.Builder("Hazard", M_HAZ, bevel=0.003)
pipes = L.Builder("Pipes", M_STEEL, bevel=0)
drains = L.Builder("Drains", M_GRATE, bevel=0)

# --- cove light under the top band of the long walls (washes the panels, gives the walls a gradient)
cove.box((XL + 0.05, Y0, 4.44), (XL + 0.1, Y1, 4.49))
cove.box((XR - 0.1, GY, 4.44), (XR - 0.05, Y1, 4.49))
cove.box((XL, Y1 - 0.1, 4.44), (XR, Y1 - 0.05, 4.49))
# --- strip lights under the mezzanine and joists
for x in (-3.0, -0.4, 2.2, 4.8):
    steel.box((x - 0.05, MY, MZ - 0.4), (x + 0.05, Y1, MZ - 0.22))
for x in (-1.7, 0.9, 3.5, 5.6):
    strips.box((x - 0.5, MY + 1.3, MZ - 0.26), (x + 0.5, MY + 1.42, MZ - 0.235))
    trim.box((x - 0.56, MY + 1.26, MZ - 0.235), (x + 0.56, MY + 1.46, MZ - 0.22))

# --- ceiling: cable trays with cable bundles, hung on rods; a rectangular duct; a sprinkler main
def cable_tray(x, y0, y1, z, w=0.5):
    tray.box((x - w / 2, y0, z), (x - w / 2 + 0.02, y1, z + 0.09))
    tray.box((x + w / 2 - 0.02, y0, z), (x + w / 2, y1, z + 0.09))
    y = y0
    while y < y1:
        tray.box((x - w / 2, y, z), (x + w / 2, y + 0.03, z + 0.02))
        y += 0.3
    y = y0 + 0.6
    while y < y1:
        for sx in (-1, 1):
            tray.cyl((x + sx * (w / 2 + 0.02), y, z), (x + sx * (w / 2 + 0.02), y, H + 0.1), 0.008, segs=6)
        y += 2.2
    for k in range(7):
        pts = [(x - w / 2 + 0.06 + k * (w - 0.12) / 6 + random.uniform(-0.015, 0.015), yy, z + 0.035 + random.uniform(0, 0.02))
               for yy in [y0 + i * (y1 - y0) / 8 for i in range(9)]]
        L.curve_tube(f"TrayCable_{x:.1f}_{k}", pts, random.choice((0.012, 0.016, 0.02)), M_RUBBER, resolution=3)


cable_tray(-1.2, Y0, 13.6, 4.62)
cable_tray(2.55, Y0, 10.6, 4.72, w=0.36)
# cables leaving the trays: loops down to the columns, the tanks and the wall boxes
for i, pts in enumerate((
        [(-1.2, 7.6, 4.66), (-1.5, 7.9, 4.2), (-2.3, 8.3, 4.35), (-2.72, 8.6, 4.9)],
        [(-1.3, 8.4, 4.66), (-1.6, 8.6, 3.9), (-2.4, 8.7, 4.1), (-2.72, 8.75, 4.7)],
        [(2.55, 8.0, 4.76), (2.5, 8.2, 4.3), (2.62, 8.5, 4.5), (2.68, 8.6, 4.95)],
        [(-1.2, 4.2, 4.66), (-2.0, 4.25, 4.1), (-3.0, 4.3, 4.2), (-3.55, 4.3, 3.9)],
        [(2.55, 4.6, 4.76), (3.0, 4.6, 4.2), (3.6, 4.6, 4.25), (3.95, 4.6, 3.9)],
        [(-1.15, 1.0, 4.66), (-1.0, 0.9, 4.0), (-0.95, 0.85, 3.6)],
        [(-1.25, 11.2, 4.66), (-1.3, 11.6, 4.1), (-1.0, 12.6, 4.3), (-1.0, 13.9, 3.75)])):
    L.curve_tube(f"Loop{i}", pts, 0.018 if i % 2 else 0.024, M_RUBBER)
# duct along the right side with flanges, straps and two outlet grilles
DX0, DX1, DZ0, DZ1 = 3.35, 4.15, 4.3, 4.78
galv.box((DX0, Y0, DZ0), (DX1, 10.5, DZ1))
y = Y0 + 0.4
while y < 10.5:
    galv.box((DX0 - 0.025, y - 0.02, DZ0 - 0.025), (DX1 + 0.025, y + 0.02, DZ1 + 0.025))
    if int(y * 10) % 3 == 0:
        for xx in (DX0 + 0.06, DX1 - 0.06):
            tray.cyl((xx, y + 0.1, DZ1), (xx, y + 0.1, H + 0.1), 0.008, segs=6)
    y += 1.25
for y in (2.4, 7.4):
    trim.box((DX0 + 0.12, y - 0.3, DZ0 - 0.03), (DX1 - 0.12, y + 0.3, DZ0))
    for i in range(5):
        galv.box((DX0 + 0.15, y - 0.26 + i * 0.12, DZ0 - 0.035), (DX1 - 0.15, y - 0.2 + i * 0.12, DZ0 - 0.01),
                 rot=Matrix.Rotation(0.5, 4, "X"))
# sprinkler main with drops
pipes.cyl((0.6, Y0, 4.95), (0.6, 13.8, 4.95), 0.03, segs=12)
for y in range(-2, 14, 3):
    pipes.cyl((0.6, y, 4.95), (0.6, y, 4.8), 0.012, segs=8)
    orange.cyl((0.6, y, 4.8), (0.6, y, 4.775), 0.02, segs=8)
    pipes.cyl((0.6, y, 4.775), (0.6, y, 4.765), 0.035, segs=10)

# --- left wall: three service pipes on brackets, a status light per door, door signs
for k, (z, r) in enumerate(((3.62, 0.04), (3.76, 0.028), (3.87, 0.028))):
    pipes.cyl((XL + 0.16, Y0, z), (XL + 0.16, Y1 - 0.2, z), r, segs=12)
for y in range(-2, 14, 2):
    trim.box((XL + 0.045, y - 0.025, 3.5), (XL + 0.22, y + 0.025, 3.95))
for (axis, fixed, a, z0, sign) in (("x", XL, 5.2, 0.0, 1), ("x", XL, 9.0, 0.0, 1), ("y", Y1, 5.3, 0.0, -1),
                                   ("y", Y1, 1.0, MZ, -1), ("y", Y1, -3.0, MZ, -1)):
    d0, d1 = sorted((fixed + sign * 0.13, fixed + sign * 0.15))
    if axis == "x":
        green.box((d0, a - 0.22, z0 + 2.62), (d1, a + 0.22, z0 + 2.74))
    else:
        green.box((a - 0.22, d0, z0 + 2.62), (a + 0.22, d1, z0 + 2.74))

# --- columns: vent grille, control box with screen, conduit up one side, hazard band on the plinth
for cx, cy in COLS:
    fy = cy - 0.585
    trim.box((cx - 0.34, fy - 0.02, 3.95), (cx + 0.34, fy, 4.45))
    for i in range(7):
        kick.box((cx - 0.3, fy - 0.035, 3.99 + i * 0.062), (cx + 0.3, fy - 0.005, 4.02 + i * 0.062), rot=Matrix.Rotation(-0.5, 4, "X"))
    trim.box((cx - 0.2, fy - 0.07, 1.25), (cx + 0.2, fy, 1.8))
    screens.box((cx - 0.15, fy - 0.075, 1.52), (cx + 0.05, fy - 0.07, 1.74))
    orange.box((cx + 0.1, fy - 0.075, 1.68), (cx + 0.15, fy - 0.07, 1.73))
    green.box((cx + 0.1, fy - 0.075, 1.58), (cx + 0.15, fy - 0.07, 1.63))
    for i in range(3):
        trim.box((cx - 0.15 + i * 0.07, fy - 0.078, 1.3), (cx - 0.1 + i * 0.07, fy - 0.07, 1.36))
    pipes.cyl((cx + 0.4, fy - 0.035, 0.42), (cx + 0.4, fy - 0.035, H - 0.5), 0.022, segs=10)
    for z in (0.9, 2.0, 3.1, 4.2):
        trim.box((cx + 0.36, fy - 0.07, z), (cx + 0.44, fy, z + 0.035))
    haz.box((cx - 0.665, cy - 0.665, 0.3), (cx + 0.665, cy + 0.665, 0.4))

# --- floor: painted guide lines, hazard strip at the stair foot, drains
paint.box((XL + 0.85, Y0, 0.0), (XL + 0.93, 10.4, 0.0015))
paint.box((GX - 0.93, Y0, 0.0), (GX - 0.85, GY - 0.2, 0.0015))
paint.box((XL + 0.85, 10.32, 0.0), (LX0 - 0.3, 10.4, 0.0015))
haz.box((LX1 + RUN - 0.05, SY0 - 0.05, 0.0), (LX1 + RUN + 0.2, SY1 + 0.05, 0.004))
for dx, dy in ((0.0, 3.6), (0.0, 7.2), (-2.4, 12.4)):
    trim.box((dx - 0.2, dy - 0.2, -0.002), (dx + 0.2, dy + 0.2, 0.002))
    drains.box((dx - 0.17, dy - 0.17, 0.001), (dx + 0.17, dy + 0.17, 0.004))

# --- tanks: bolt rings and a status light on each collar
for tx, ty in ((-3.75, 4.3), (4.1, 4.6), (-3.75, 11.9), (4.1, 1.2)):
    for z in (0.5, 3.36):
        for a in range(16):
            ax, ay = tx + 0.745 * math.cos(a * math.tau / 16), ty + 0.745 * math.sin(a * math.tau / 16)
            trim.cyl((ax, ay, z), (ax + 0.012 * math.cos(a * math.tau / 16), ay + 0.012 * math.sin(a * math.tau / 16), z), 0.014, segs=6)
    side = 1 if tx < 0 else -1
    trim.box((tx + side * 0.72, ty - 0.14, 3.42), (tx + side * 0.76, ty + 0.14, 3.62))
    screens.box((tx + side * 0.76, ty - 0.1, 3.47), (tx + side * 0.765, ty + 0.04, 3.57))
    orange.box((tx + side * 0.76, ty + 0.07, 3.5), (tx + side * 0.765, ty + 0.11, 3.54))
    haz.cyl((tx, ty, 0.12), (tx, ty, 0.2), 0.75, segs=40)

for b in (galv, tray, paint, cove, green, orange, haz, pipes, drains):
    b.finish()

for b in (floor, back, panels, bands, kick, trim, ceil, lights, grid, mezz, steel, grate, rail, doorf, doorl, strips,
          screens, glassd, tankm, tankd, liquid, tlight, bubbles):
    if b is not floor and b is not base:
        b.finish()

# ---------------------------------------------------------------- camera + world
cam = bpy.data.objects.new("PlayerCamera", bpy.data.cameras.new("PlayerCamera"))
cam.data.sensor_width = 36
cam.data.lens = 18 / math.tan(math.radians(40))      # 80 deg horizontal
cam.location = (0.2, 0.0, 1.62)
cam.rotation_euler = (math.radians(87.0), 0, 0)
cam.data.clip_start = 0.05
L.coll("Camera").objects.link(cam)
sc.camera = cam
world = bpy.data.worlds.new("World")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.02, 0.022, 0.025, 1)
sc.world = world
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(L.ROOT, "scene.blend"))
print("saved scene.blend:", len(bpy.data.objects), "objects")
