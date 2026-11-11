"""XM9 pistol, modelled from scratch after blender/reference/pistol_concept.png -> blender/xm9.blend.

    blender -b -P blender/scripts/build_xm9.py

Every part is a side profile traced from the concept's assembled view (image pixels), extruded to
its width and bevelled; serrations, rail slots, vents and the ejection port are live Boolean cutters
(collection "Cutters", hidden), so the .blend stays editable. Scale: the gun is ~23 cm long, which
makes 1 image px = 0.453 mm (checked against the sheet's 10 / 15 / 36 unit marks: sight 2.4 cm,
slide 3.4 cm, grip 8.2 cm).

Frame (gun frame like the other weapons): origin at the top of the grip, barrel along +Y, up +Z.
Moving parts are separate objects with their pivots where they move, ready for the Fire / Reload clips:
  Slide (+ red dot, sights, glow, screen)  slides back along -Y
  Barrel                                   pivots at its front (tilts the chamber down)
  Trigger                                  pivots at its top
  Magazine (+ base plate, rounds)          slides out along the grip axis
Empties: Muzzle (bore exit), Eject (ejection port, for the casing), MagAxis (direction the magazine drops).
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "blender", "xm9.blend")
REF = os.path.join(ROOT, "blender", "reference", "pistol_concept.png")

K = 0.000453                 # metres per image pixel
ORIGIN_PX = (715, 235)        # top of the grip, in the concept image
BORE_Y = 122                  # bore height (image px)
RAKE = math.atan2(33, 115)    # grip angle: front strap (655,235) -> (688,350)

MATS = {
    "GunSlide": dict(color=(0.55, 0.57, 0.60), metallic=0.75, rough=0.35),
    "GunFrame": dict(color=(0.40, 0.42, 0.45), metallic=0.4, rough=0.5),
    "GunDark": dict(color=(0.06, 0.065, 0.07), metallic=0.3, rough=0.6),
    "GunGrip": dict(color=(0.03, 0.03, 0.035), metallic=0.0, rough=0.9),
    "GunBarrel": dict(color=(0.12, 0.12, 0.13), metallic=0.9, rough=0.3),
    "GunMagazine": dict(color=(0.10, 0.12, 0.15), metallic=0.0, rough=0.2, alpha=0.55),
    "GunBrass": dict(color=(0.78, 0.56, 0.24), metallic=1.0, rough=0.3),
    "GunLens": dict(color=(0.35, 0.05, 0.04), metallic=0.0, rough=0.05),
    "GunScreen": dict(color=(0.02, 0.05, 0.07), metallic=0.0, rough=0.2, emit=(0.1, 0.5, 0.7, 0.6)),
    "NeonCyan": dict(color=(0x22 / 255, 0xE5 / 255, 1.0), emit=(0x22 / 255, 0xE5 / 255, 1.0, 8.0)),
}


def P(x, y):
    """Image pixel -> gun frame (Y forward, Z up), metres."""
    return Vector((0.0, (ORIGIN_PX[0] - x) * K, (ORIGIN_PX[1] - y) * K))


def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    s = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*s["color"], 1)
    b.inputs["Metallic"].default_value = s.get("metallic", 0.0)
    b.inputs["Roughness"].default_value = s.get("rough", 0.5)
    if "emit" in s:
        b.inputs["Emission Color"].default_value = (*s["emit"][:3], 1)
        b.inputs["Emission Strength"].default_value = s["emit"][3]
    if "alpha" in s:
        b.inputs["Alpha"].default_value = s["alpha"]
        m.blend_method = "BLEND"
    m.diffuse_color = (*s["color"], s.get("alpha", 1.0))
    return m


def coll(name, hidden=False):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
        if hidden:
            c.hide_viewport = True
            c.hide_render = True
    return c


def finish(ob, material, bevel, parent, pivot, collection="XM9"):
    """Material, bevel + weighted normals (live modifiers), pivot (origin) and parent."""
    ob.data.materials.append(mat(material))
    coll(collection).objects.link(ob)
    if pivot is not None:
        ob.data.transform(Matrix.Translation(-pivot))
        ob.location = pivot
    if bevel > 0:
        bv = ob.modifiers.new("Bevel", "BEVEL")
        bv.width = bevel
        bv.segments = 2
        bv.limit_method = "ANGLE"
        bv.angle_limit = math.radians(35)
        bv.harden_normals = True
    for p in ob.data.polygons:
        p.use_smooth = True
    if parent is not None:
        bpy.context.view_layer.update()
        mw = ob.matrix_world.copy()
        ob.parent = parent
        ob.matrix_world = mw
    return ob


def prism(name, pts, width, material, bevel=0.0007, parent=None, pivot=None, x0=0.0):
    """Side profile (image px) extruded along X, centred on x0."""
    bm = bmesh.new()
    vs = [bm.verts.new(P(*p) + Vector((x0 - width / 2, 0, 0))) for p in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=Vector((width, 0, 0)),
                        verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return finish(bpy.data.objects.new(name, me), material, bevel, parent, pivot)


def cyl(name, a, b, r, material, segs=16, bevel=0.0004, parent=None, pivot=None, r2=None):
    """Cylinder (or cone with r2) from a to b (gun-frame metres)."""
    bm = bmesh.new()
    d = b - a
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    m = Matrix.Translation((a + b) / 2) @ rot
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2,
                          depth=d.length, matrix=m)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return finish(bpy.data.objects.new(name, me), material, bevel, parent, pivot)


def box(name, lo, hi, material, bevel=0.0005, parent=None, rot=None, collection="XM9"):
    """Box between two gun-frame corners, optionally rotated (Euler XYZ, radians) about its centre."""
    bm = bmesh.new()
    lo, hi = Vector(lo), Vector(hi)
    r = Matrix.Identity(4) if rot is None else (Matrix.Rotation(rot[0], 4, "X") @ Matrix.Rotation(rot[1], 4, "Y")
                                                @ Matrix.Rotation(rot[2], 4, "Z"))
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((lo + hi) / 2) @ r @ Matrix.Diagonal((*(hi - lo), 1)))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return finish(bpy.data.objects.new(name, me), material, bevel, parent, None, collection)


def cut(target, cutter):
    """Live boolean: cutter (hidden, parented to the target so it moves with it) removed from target."""
    for c in list(cutter.users_collection):
        c.objects.unlink(cutter)
    coll("Cutters", hidden=True).objects.link(cutter)
    cutter.display_type = "WIRE"
    bpy.context.view_layer.update()
    mw = cutter.matrix_world.copy()
    cutter.parent = target
    cutter.matrix_world = mw
    bo = target.modifiers.new(f"Cut_{cutter.name}", "BOOLEAN")
    bo.object = cutter
    bo.operation = "DIFFERENCE"
    bo.solver = "EXACT"
    # Keep the bevel first, then the cuts, then weighted normals at the end.
    return bo


def empty(name, loc, parent, size=0.01):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    e.empty_display_type = "ARROWS"
    coll("XM9").objects.link(e)
    e.location = loc
    if parent is not None:
        bpy.context.view_layer.update()
        mw = e.matrix_world.copy()
        e.parent = parent
        e.matrix_world = mw
    return e


def weighted(ob):
    wn = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    wn.keep_sharp = True


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.render.fps = 30
    root = bpy.data.objects.new("XM9", None)
    root.empty_display_size = 0.03
    coll("XM9").objects.link(root)

    # ---- Frame (static) -------------------------------------------------------------------------
    frame = prism("Frame", [(517, 163), (787, 163), (796, 170), (781, 178), (766, 192), (763, 215), (771, 250),
                            (783, 290), (791, 336), (686, 337), (683, 320), (675, 293), (667, 266), (659, 244),
                            (652, 230), (646, 226), (640, 218), (632, 180), (537, 180), (530, 195), (520, 195)],
                  0.028, "GunFrame", parent=root)
    dust = prism("DustCover", [(282, 160), (520, 160), (520, 195), (505, 212), (291, 212), (282, 203)],
                 0.028, "GunDark", parent=root)
    for i, x in enumerate((315, 335, 353, 412)):
        cut(dust, box(f"RailSlot{i}", P(x + 7, 214) + Vector((-0.02, 0, 0)), P(x, 205) + Vector((0.02, 0, 0)),
                      "GunDark", bevel=0))
    guard = prism("TriggerGuard", [(521, 170), (522, 214), (534, 235), (560, 240), (646, 240), (660, 232),
                                   (660, 214), (648, 224), (640, 227), (560, 228), (543, 222), (537, 210),
                                   (537, 170)], 0.012, "GunFrame", parent=root)
    panel = prism("GripPanel", [(663, 236), (712, 226), (745, 262), (760, 330), (700, 334), (688, 331), (676, 290)],
                  0.031, "GunGrip", bevel=0.001, parent=root)
    prism("GripGlow", [(744, 266), (751, 265), (758, 300), (751, 302)], 0.0318, "NeonCyan", bevel=0.0003, parent=root)
    comp = prism("Compensator", [(276, 100), (283, 92), (402, 92), (402, 158), (283, 158), (276, 150)],
                 0.030, "GunDark", bevel=0.001, parent=root)
    for sx in (-1, 1):  # vent windows on both sides
        cut(comp, prism(f"Vent{'LR'[sx > 0]}", [(299, 112), (322, 112), (333, 142), (310, 142)], 0.006,
                        "GunDark", bevel=0, x0=sx * 0.0165))
    prism("FrontSight", [(298, 92), (300, 80), (328, 80), (330, 92)], 0.004, "GunDark", bevel=0.0004, parent=comp)
    prism("FrontSightDot", [(304, 84), (309, 84), (309, 89), (304, 89)], 0.0042, "NeonCyan", bevel=0, parent=comp)

    # ---- Slide (moves back on fire) ------------------------------------------------------------
    slide_pivot = P(600, 128)
    slide = prism("Slide", [(402, 92), (745, 92), (781, 97), (787, 106), (787, 145), (779, 166), (402, 166)],
                  0.026, "GunSlide", parent=root, pivot=slide_pivot)
    # Ejection port: top right of the slide, shows the barrel hood.
    cut(slide, box("EjectionPort", P(547, 91) + Vector((0.001, 0, 0.002)), P(635, 108) + Vector((0.02, 0, 0)),
                   "GunSlide", bevel=0))
    lean = math.radians(-18)
    for i in range(3):   # front serrations
        y = 427 + i * 9
        for sx in (-1, 1):
            cut(slide, box(f"SerrF{i}{'LR'[sx > 0]}", P(y, 96) + Vector((sx * 0.0125 - 0.0018, -0.001, -0.016)),
                           P(y, 96) + Vector((sx * 0.0125 + 0.0018, 0.001, 0.0)), "GunSlide", bevel=0, rot=(lean, 0, 0)))
    for i in range(5):   # rear serrations
        y = 682 + i * 7
        for sx in (-1, 1):
            cut(slide, box(f"SerrR{i}{'LR'[sx > 0]}", P(y, 100) + Vector((sx * 0.0125 - 0.0018, -0.001, -0.019)),
                           P(y, 100) + Vector((sx * 0.0125 + 0.0018, 0.001, 0.0)), "GunSlide", bevel=0, rot=(lean, 0, 0)))
    for sx in (-1, 1):   # glow strips + ammo screen, both sides
        for nm, pts in (("A", [(465, 120), (522, 120), (522, 124), (465, 124)]),
                        ("B", [(562, 120), (620, 120), (632, 100), (636, 102), (623, 124), (562, 124)])):
            prism(f"SlideGlow{nm}{'LR'[sx > 0]}", pts, 0.0008, "NeonCyan", bevel=0, parent=slide, x0=sx * 0.0131)
        prism(f"Screen{'LR'[sx > 0]}", [(712, 110), (767, 110), (767, 137), (712, 137)], 0.0008, "GunScreen",
              bevel=0, parent=slide, x0=sx * 0.0131)
    rear = prism("RearSight", [(742, 92), (743, 78), (762, 78), (764, 92)], 0.022, "GunDark", bevel=0.0006, parent=slide)
    cut(rear, box("RearNotch", P(746, 77) + Vector((-0.002, 0, 0)), P(760, 84) + Vector((0.002, 0, 0)), "GunDark", bevel=0))
    dot = prism("RedDot", [(640, 97), (640, 85), (645, 85), (645, 42), (705, 40), (733, 85), (736, 85), (736, 97)],
                0.020, "GunDark", bevel=0.001, parent=slide)
    cut(dot, prism("RedDotWindow", [(650, 50), (700, 48), (722, 82), (650, 82)], 0.016, "GunDark", bevel=0))
    prism("RedDotLens", [(688, 50), (700, 48), (722, 82), (708, 82)], 0.015, "GunLens", bevel=0, parent=dot)

    # ---- Barrel (inside the slide; hood shows through the port) -------------------------------------
    bore = P(0, BORE_Y)
    barrel_pivot = P(402, BORE_Y)
    barrel = cyl("Barrel", P(280, BORE_Y) + Vector((0, 0.0, 0)), P(560, BORE_Y), 0.0055, "GunBarrel",
                 parent=root, pivot=barrel_pivot)
    hood = box("BarrelHood", P(548, 96) + Vector((-0.0068, 0, -0.012)), P(640, 96) + Vector((0.0068, 0, 0)),
               "GunBarrel", bevel=0.0006, parent=barrel)
    cyl("Bore", P(279, BORE_Y), P(285, BORE_Y), 0.0042, "GunDark", segs=16, bevel=0, parent=barrel)

    # ---- Trigger (pivots at its top) --------------------------------------------------------------
    prism("Trigger", [(600, 178), (612, 178), (620, 195), (618, 215), (608, 228), (596, 229), (594, 224),
                      (603, 214), (605, 198), (598, 186)], 0.007, "GunDark", bevel=0.0007, parent=root,
          pivot=P(606, 180))

    # ---- Magazine (drops along the grip axis) -------------------------------------------------------
    mag_top = P(706, 190)
    mag = prism("Magazine", [(665, 193), (745, 193), (772, 335), (692, 335)], 0.022, "GunMagazine",
                bevel=0.0008, parent=root, pivot=mag_top)
    prism("MagBase", [(686, 335), (778, 335), (782, 351), (690, 353)], 0.030, "GunDark", bevel=0.0012, parent=mag)
    # Rounds stacked along the grip axis (double stack, staggered), casings brass with cyan tips.
    axis = Vector((0, -math.sin(RAKE), -math.cos(RAKE)))
    fwd = Vector((0, math.cos(RAKE), -math.sin(RAKE)))
    for i in range(6):
        c = mag_top + axis * (0.006 + i * 0.0085) + fwd * 0.0
        x = 0.0035 if i % 2 else -0.0035
        a = c + Vector((x, 0, 0)) - fwd * 0.012
        b = c + Vector((x, 0, 0)) + fwd * 0.007
        rnd = cyl(f"Round{i}", a, b, 0.0047, "GunBrass", segs=12, parent=mag)
        cyl(f"Round{i}Tip", b, b + fwd * 0.008, 0.0045, "NeonCyan", segs=12, r2=0.0016, parent=rnd)

    # ---- Markers ---------------------------------------------------------------------------------
    empty("Muzzle", P(276, BORE_Y), root)
    empty("Eject", P(590, 100) + Vector((0.014, 0, 0)), slide)
    ma = empty("MagAxis", mag_top, root)
    ma.rotation_euler = (math.pi - RAKE, 0, 0)  # empty's +Z points down the grip

    # ---- Spare casing (spawned by the game when firing) --------------------------------------------
    parts = coll("Parts")
    cas = cyl("Casing", Vector((0.06, -0.01, 0.0)), Vector((0.06, 0.009, 0.0)), 0.0047, "GunBrass", segs=12)
    for c in list(cas.users_collection):
        c.objects.unlink(cas)
    parts.objects.link(cas)

    for ob in bpy.data.objects:
        if ob.type == "MESH":
            weighted(ob)

    # ---- Review setup: reference image behind the side view, cameras, light ----------------------------
    img = bpy.data.images.load(REF)
    ref = bpy.data.objects.new("Reference", None)
    ref.empty_display_type = "IMAGE"
    ref.data = img
    ref.empty_image_side = "FRONT"
    ref.color[3] = 0.5
    ref.show_empty_image_perspective = False
    w = img.size[0] * K
    ref.empty_display_size = w
    # Image pixel (0,0) is its top-left; place it so every traced pixel lands on the model (side view, -X).
    ref.rotation_euler = (math.radians(90), 0, math.radians(90))
    ref.location = Vector((-0.05, ORIGIN_PX[0] * K - w / 2, (ORIGIN_PX[1] - img.size[1] / 2) * K))
    ref.empty_image_offset = (-0.5, -0.5)
    coll("Reference").objects.link(ref)
    ref.scale = (-1, 1, 1)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(55), math.radians(15), math.radians(-35))
    coll("Review").objects.link(sun)
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.4, 0.42, 0.46, 1)
    sc.world = world
    cam = bpy.data.objects.new("SideCamera", bpy.data.cameras.new("SideCamera"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 0.27
    cam.location = (-0.5, 0.081, 0.0177)
    cam.rotation_euler = (math.radians(90), 0, math.radians(-90))
    coll("Review").objects.link(cam)
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print("saved", OUT)


build()
