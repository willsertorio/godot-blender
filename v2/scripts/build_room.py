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
M_FLOOR = L.pbr("FloorTile", "Concrete034", scale=2.5, tint=(0.80, 0.82, 0.85), rough=(0.07, 0.3), normal=0.3,
                tint_attr="tint", grunge=0.22, grunge_scale=0.45)
M_BACK = L.plain("Backing", (0.03, 0.032, 0.035), rough=0.7)
M_STEEL = L.pbr("Steel", "Metal032", scale=1.0, tint=(0.62, 0.64, 0.67), rough=(0.3, 0.55))
M_DARK = L.pbr("DarkSteel", "Metal032", scale=1.0, tint=(0.16, 0.17, 0.19), rough=(0.35, 0.6))
M_GRATE = L.pbr("Grating", "MetalWalkway010", scale=0.6, tint=(1.6, 1.6, 1.7), rough=(0.3, 0.6))
M_RUBBER = L.plain("Cable", (0.02, 0.02, 0.022), rough=0.55)
M_LIGHT = L.plain("CeilingLight", (1, 1, 1), emit=(0.97, 0.985, 1.0), emit_strength=9.5)
M_STRIP = L.plain("LightStrip", (1, 1, 1), emit=(0.95, 0.98, 1.0), emit_strength=30.0)
M_CYAN = L.plain("ScreenCyan", (0.0, 0.02, 0.03), emit=(0.15, 0.85, 1.0), emit_strength=6.0)
M_TANKLIGHT = L.plain("TankLight", (1, 1, 1), emit=(0.75, 0.95, 1.0), emit_strength=20.0)
M_GLASSDARK = L.plain("DarkGlass", (0.02, 0.03, 0.04), rough=0.05, metallic=0.6)
M_BUBBLE = L.plain("Bubble", (0.95, 0.98, 1.0), rough=0.05, transmission=1.0, ior=1.0)


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
    pv.inputs["Density"].default_value = 0.55
    pv.inputs["Anisotropy"].default_value = 0.3
    pv.inputs["Emission Color"].default_value = (0.45, 0.9, 1.0, 1)
    pv.inputs["Emission Strength"].default_value = 0.25
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
    for _ in range(140):
        r, a = 0.5 * math.sqrt(random.random()), random.random() * math.tau
        z = random.uniform(0.7, 3.1)
        bmesh.ops.create_icosphere(bubbles.bm, subdivisions=1, radius=random.uniform(0.008, 0.03),
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
