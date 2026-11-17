"""XM-R4 rifle, modelled from scratch after blender/reference/rifle_concept.png -> blender/xmr4.blend.

    blender -b -P blender/scripts/build_xmr4.py

Same method and helpers as the XM9 (build_xm9.py): side profiles traced from the concept's assembled
view (image px), extruded + bevelled, live boolean cutters (vent slots, rail notches, ejection port,
stock / foregrip / trigger-guard holes, sight window). Scale: 0.82 mm per image pixel -> 88 cm overall,
8.7 cm pistol grip (a real carbine's proportions; fits the HG-7 glove).

Frame: origin at the top of the pistol grip, barrel along +Y, up +Z (like the other guns).
Moving parts (separate objects, pivots where they move):
  Trigger         pivots at its top
  Magazine        (+ MagBase, rounds) drops along MagAxis (empty, +Z = out of the magwell)
  Bolt            visible through the ejection port (right side), slides back along -Y
  DustCover       port cover, hinged at the port's bottom edge, swings open (rotation about Y)
  ChargingHandle  rear top of the upper, pulled back along -Y
Empties: Muzzle (flash-hider exit), Eject (ejection port, right side), MagAxis.
Materials: RifleBody, RifleDark, RifleCarbon, RiflePolymer, RifleMetal, RifleMagazine, RifleBrass,
RifleLens, NeonCyan, NeonOrange (Neon* are driven by Godot's neon shader).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import build_xm9 as hs  # noqa: E402  (helpers: prism / cyl / box / cut / empty / weighted)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "blender", "xmr4.blend")
REF = os.path.join(ROOT, "blender", "reference", "rifle_concept.png")
hs.K = 0.00082
hs.ORIGIN_PX = (868, 232)
hs.COLL = "XMR4"
hs.MATS.update({
    "RifleBody": dict(color=(0.40, 0.40, 0.36), metallic=0.35, rough=0.5),
    "RifleDark": dict(color=(0.08, 0.085, 0.09), metallic=0.4, rough=0.5),
    "RifleCarbon": dict(color=(0.18, 0.18, 0.17), metallic=0.2, rough=0.4),
    "RiflePolymer": dict(color=(0.30, 0.30, 0.27), metallic=0.0, rough=0.75),
    "RifleMetal": dict(color=(0.14, 0.14, 0.15), metallic=0.9, rough=0.3),
    "RifleMagazine": dict(color=(0.32, 0.33, 0.30), metallic=0.0, rough=0.25, alpha=0.6),
    "RifleBrass": dict(color=(0.78, 0.56, 0.24), metallic=1.0, rough=0.3),
    "RifleLens": dict(color=(0.08, 0.16, 0.2), metallic=0.0, rough=0.05),
    "NeonOrange": dict(color=(1.0, 0.6, 0.16), emit=(1.0, 0.6, 0.16, 8.0)),
})
P, prism, cyl, box, cut, empty = hs.P, hs.prism, hs.cyl, hs.box, hs.cut, hs.empty
K = hs.K
BORE = 160


def X(v, x):
    return v + Vector((x, 0, 0))


def glow(name, pts, width, material, parent):
    """Thin emissive strip on both sides of a part of the given width."""
    for sx in (-1, 1):
        prism(f"{name}{'LR'[sx > 0]}", pts, 0.0008, material, bevel=0, parent=parent, x0=sx * (width / 2 + 0.0002))


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.render.fps = 30
    root = bpy.data.objects.new("XMR4", None)
    root.empty_display_size = 0.05
    hs.coll("XMR4").objects.link(root)

    # ---- barrel group (static) -----------------------------------------------------------------------
    cyl("FlashHider", P(76, BORE), P(150, BORE), 0.0143, "RifleMetal", segs=20, parent=root)
    cyl("Collar", P(150, BORE), P(200, BORE), 0.0165, "RifleMetal", segs=20, parent=root)
    cyl("Barrel", P(200, BORE), P(320, BORE), 0.0105, "RifleMetal", segs=16, parent=root)
    cyl("Bore", P(74, BORE), P(80, BORE), 0.0075, "RifleDark", segs=16, bevel=0, parent=root)

    # ---- handguard + foregrip ----------------------------------------------------------------------------
    hg = prism("Handguard", [(312, 111), (648, 111), (648, 200), (318, 202), (306, 190), (305, 122)],
               0.050, "RifleBody", bevel=0.0015, parent=root)
    for row, y in (("U", 132), ("D", 179)):
        for i in range(6):
            x = 332 + i * 40
            for sx in (-1, 1):
                cut(hg, prism(f"Vent{row}{i}{'LR'[sx > 0]}", [(x, y - 4), (x + 28, y - 4), (x + 28, y + 4), (x, y + 4)],
                              0.008, "RifleBody", bevel=0, x0=sx * 0.025))
    glow("HGGlowTop", [(334, 120), (544, 120), (544, 125), (334, 125)], 0.050, "NeonCyan", hg)
    glow("HGGlowMid", [(376, 155), (476, 155), (476, 160), (376, 160)], 0.050, "NeonCyan", hg)
    glow("HGGlowOrange", [(532, 155), (578, 155), (578, 160), (532, 160)], 0.050, "NeonOrange", hg)
    fg = prism("Foregrip", [(442, 200), (655, 200), (658, 212), (645, 250), (630, 277), (585, 278), (575, 265),
                            (530, 232), (470, 212), (456, 228), (445, 226)], 0.024, "RiflePolymer", bevel=0.0015,
               parent=root)
    cut(fg, prism("ForegripHole", [(560, 211), (622, 211), (606, 248)], 0.04, "RiflePolymer", bevel=0))

    # ---- receivers -------------------------------------------------------------------------------------------
    up = prism("Upper", [(645, 113), (902, 113), (906, 121), (906, 180), (645, 180)], 0.032, "RifleCarbon",
               bevel=0.0012, parent=root)
    cut(up, box("EjectionPort", X(P(690, 140), 0.008), X(P(760, 165), 0.03), "RifleCarbon", bevel=0))
    glow("UpperGlow", [(668, 150), (728, 150), (728, 155), (668, 155)], 0.032, "NeonOrange", up)
    rail = box("TopRail", X(P(310, 107), -0.011), X(P(900, 114), 0.011), "RifleDark", bevel=0.0006, parent=root)
    notch = box("RailNotch", X(P(318, 106), -0.02), X(P(312, 110.5), 0.02), "RifleDark", bevel=0)
    arr = notch.modifiers.new("Array", "ARRAY")
    arr.count = 48
    arr.use_relative_offset = False
    arr.use_constant_offset = True
    arr.constant_offset_displace = (0, -12 * K, 0)
    cut(rail, notch)
    low = prism("Lower", [(648, 180), (905, 180), (908, 196), (895, 205), (838, 236), (830, 262), (815, 268),
                          (775, 266), (762, 252), (760, 245), (655, 248), (650, 230)], 0.030, "RifleBody",
                bevel=0.0012, parent=root)
    cut(low, prism("GuardHole", [(775, 221), (828, 221), (826, 257), (778, 258)], 0.04, "RifleBody", bevel=0))
    cut(low, prism("Magwell", [(652, 236), (756, 236), (752, 252), (650, 252)], 0.024, "RifleBody", bevel=0))
    prism("PistolGrip", [(838, 236), (896, 198), (908, 202), (926, 300), (927, 320), (915, 336), (876, 340),
                         (866, 334), (852, 290), (842, 258)], 0.030, "RiflePolymer", bevel=0.002, parent=root)

    # ---- stock -------------------------------------------------------------------------------------------------
    cyl("BufferTube", P(900, 158), P(1000, 158), 0.0145, "RifleDark", segs=20, parent=root)
    st = prism("Stock", [(948, 133), (1150, 131), (1165, 140), (1165, 290), (1155, 298), (1100, 298), (1085, 285),
                         (955, 190), (948, 180)], 0.040, "RiflePolymer", bevel=0.002, parent=root)
    cut(st, prism("StockHole", [(1025, 186), (1085, 181), (1128, 200), (1124, 266), (1100, 258), (1040, 214)], 0.06,
                  "RiflePolymer", bevel=0))
    prism("ButtPad", [(1151, 132), (1167, 138), (1167, 292), (1157, 299), (1151, 299)], 0.042, "RifleDark",
          bevel=0.0015, parent=root)

    # ---- optics -------------------------------------------------------------------------------------------------
    holo = prism("HoloSight", [(600, 82), (610, 76), (648, 74), (652, 42), (738, 38), (745, 60), (748, 108), (600, 108)],
                 0.040, "RifleDark", bevel=0.0015, parent=root)
    cut(holo, box("HoloWindow", P(760, 52) + Vector((-0.015, 0, 0)), P(640, 95) + Vector((0.015, 0, 0)),
                  "RifleDark", bevel=0))
    box("HoloGlass", P(700, 54) + Vector((-0.015, 0, 0)), P(698, 93) + Vector((0.015, 0, 0)), "RifleLens", bevel=0,
        parent=holo)
    box("HoloScreen", P(700, 85) + Vector((-0.0201, 0, 0)), P(724, 95) + Vector((-0.0199, 0, 0)), "NeonOrange",
        bevel=0, parent=holo)
    mag_ax = 70
    box("MagnifierMount", X(P(810, 86), -0.011), X(P(765, 108), 0.011), "RifleDark", bevel=0.001, parent=root)
    mg = cyl("Magnifier", P(760, mag_ax), P(848, mag_ax), 0.0185, "RifleDark", segs=24, parent=root)
    cyl("MagnifierEye", P(845, mag_ax), P(866, mag_ax), 0.021, "RifleDark", segs=24, parent=mg)
    cyl("MagnifierRing", P(858, mag_ax), P(862, mag_ax), 0.0213, "NeonCyan", segs=24, bevel=0, parent=mg)
    cyl("MagnifierLens", P(866, mag_ax), P(867, mag_ax), 0.016, "RifleLens", segs=24, bevel=0, parent=mg)

    # ---- moving parts -------------------------------------------------------------------------------------------
    prism("Trigger", [(800, 222), (808, 222), (812, 240), (808, 252), (800, 256), (797, 252), (802, 242), (800, 230)],
          0.007, "RifleDark", bevel=0.0006, parent=root, pivot=P(803, 222))
    bolt = box("Bolt", X(P(692, 142), 0.004), X(P(758, 163), 0.0135), "RifleMetal", bevel=0.0008, parent=root)
    cyl("BoltFace", X(P(692, 152), 0.009), X(P(688, 152), 0.009), 0.004, "RifleBrass", segs=12, bevel=0, parent=bolt)
    hinge = X(P(725, 165), 0.0165)
    prism("DustCover", [(690, 140), (760, 140), (760, 165), (690, 165)], 0.0015, "RifleCarbon", bevel=0.0003,
          parent=root, pivot=hinge, x0=0.0165)
    prism("ChargingHandle", [(876, 113), (906, 113), (906, 120), (876, 120)], 0.044, "RifleDark", bevel=0.0008,
          parent=root)
    mag_top = P(700, 238)
    mag = prism("Magazine", [(648, 236), (752, 236), (748, 300), (737, 360), (733, 380), (643, 382), (640, 360),
                             (644, 300)], 0.022, "RifleMagazine", bevel=0.001, parent=root, pivot=mag_top)
    prism("MagBase", [(636, 370), (738, 370), (741, 388), (634, 390)], 0.028, "RifleDark", bevel=0.0015, parent=mag)
    fwd = Vector((0, 1, 0))
    for i in range(7):
        c = P(694 - i * 1.2, 246 + i * 18)
        x = 0.0045 if i % 2 else -0.0045
        a = c + Vector((x, 0, 0)) - fwd * 0.03
        b = c + Vector((x, 0, 0)) + fwd * 0.012
        r = cyl(f"Round{i}", a, b, 0.0048, "RifleBrass", segs=12, parent=mag)
        cyl(f"Round{i}Tip", b, b + fwd * 0.016, 0.0046, "NeonCyan" if i else "NeonOrange", segs=12, r2=0.0012, parent=r)

    # ---- markers + spare casing -------------------------------------------------------------------------------------
    empty("Muzzle", P(74, BORE), root)
    empty("Eject", X(P(725, 152), 0.02), root)
    ma = empty("MagAxis", mag_top, root)
    d = (P(640, 385) - P(648, 236)).normalized()           # down the magazine's front edge
    ma.rotation_euler = Vector((0, 0, 1)).rotation_difference(d).to_euler()
    parts = hs.coll("Parts", hidden=True)
    cas = cyl("Casing", Vector((0.1, 0, 0)), Vector((0.1, 0.045, 0)), 0.0048, "RifleBrass", segs=12)
    for c in list(cas.users_collection):
        c.objects.unlink(cas)
    parts.objects.link(cas)
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            hs.weighted(ob)

    # ---- review setup --------------------------------------------------------------------------------------------
    img = bpy.data.images.load(REF)
    ref = bpy.data.objects.new("Reference", None)
    ref.empty_display_type = "IMAGE"
    ref.data = img
    w = img.size[0] * K
    ref.empty_display_size = w
    ref.empty_image_offset = (-0.5, -0.5)
    ref.rotation_euler = (math.radians(90), 0, math.radians(90))
    ref.scale = (-1, 1, 1)
    ref.location = Vector((-0.08, hs.ORIGIN_PX[0] * K - w / 2, (hs.ORIGIN_PX[1] - img.size[1] / 2) * K))
    ref.color[3] = 0.5
    hs.coll("Reference").objects.link(ref)
    bpy.data.collections["Reference"].hide_render = True
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(55), math.radians(15), math.radians(-35))
    hs.coll("Review").objects.link(sun)
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.4, 0.42, 0.46, 1)
    sc.world = world
    cam = bpy.data.objects.new("SideCamera", bpy.data.cameras.new("SideCamera"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 0.95
    cx, cy = (76 + 1167) / 2, (37 + 390) / 2
    cam.location = (-1.0, (hs.ORIGIN_PX[0] - cx) * K, (hs.ORIGIN_PX[1] - cy) * K)
    cam.rotation_euler = (math.radians(90), 0, math.radians(-90))
    hs.coll("Review").objects.link(cam)
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = 1600, 800
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print("saved", OUT, "camera centre px", cx, cy)


build()
