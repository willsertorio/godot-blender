"""Fire animation on the XM9 (runs on the saved file, so edits made in blender/xm9.blend are kept).

    blender -b blender/xm9.blend -P blender/scripts/anim_xm9.py

One shot, 24 frames at 30 fps; Space in Blender plays it in a loop. Snappy arcade timing:
  f1-3   trigger pulls                       f3   shot: muzzle flash, gun kicks back + flips up
  f3-5   slide snaps back 3.2 cm (barrel back 4 mm, chamber tilts down 4 deg)
  f5     casing pops out of the ejection port (flies up/right, spinning, falls)
  f7-10  slide slams forward (small overshoot), trigger resets   f4-13 gun settles
Actions are named "<object>_Fire". In the game the casing becomes a physics object spawned at the
Eject marker and the gun's kick stays procedural; this file shows the whole shot.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

FPS = 30
SLIDE_TRAVEL = 0.032
EJECT_V = Vector((1.1, -0.25, 1.5))   # casing launch velocity (m/s): right, slightly back, up
SPIN = Vector((14.0, 3.0, 22.0))      # casing spin (rad/s, Euler XYZ)
G = 9.8

sc = bpy.context.scene
sc.render.fps = FPS
sc.frame_start, sc.frame_end = 1, 24
O = bpy.data.objects


def keys(ob, path, index, frames, interp="BEZIER", easing="AUTO"):
    """frames: list of (frame, value[, interpolation, easing]); interpolation applies to the segment that starts there."""
    if ob.animation_data is None:
        ob.animation_data_create()
    if ob.animation_data.action is None:
        ob.animation_data.action = bpy.data.actions.new(f"{ob.name}_Fire")
    act = ob.animation_data.action
    fc = act.fcurves.find(path, index=index) or act.fcurves.new(path, index=index)
    for k in frames:
        f, v = k[0], k[1]
        kp = fc.keyframe_points.insert(f, v, options={"FAST"})
        kp.interpolation = k[2] if len(k) > 2 else interp
        kp.easing = k[3] if len(k) > 3 else easing
        if kp.interpolation == "BACK":
            kp.back = 1.4
    fc.update()


def clear(ob):
    if ob.animation_data:
        ob.animation_data_clear()


def flash_mesh():
    """Muzzle flash: a cone of light + two crossed star planes, pointing along +Y from its origin."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=10, radius1=0.012, radius2=0.002, depth=0.05,
                          matrix=Matrix.Translation((0, 0.025, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    for a in (0, math.pi / 2, math.pi / 4, -math.pi / 4):
        r = Matrix.Rotation(a, 4, "Y")
        pts = []
        for i in range(10):
            ang = i * math.pi / 5
            rad = 0.03 if i % 2 == 0 else 0.008
            pts.append(r @ Vector((math.cos(ang) * rad * 0.5, 0.006, math.sin(ang) * rad)))
        bm.faces.new([bm.verts.new(p) for p in pts])
    me = bpy.data.meshes.new("MuzzleFlash")
    bm.to_mesh(me)
    bm.free()
    m = bpy.data.materials.get("MuzzleFlash") or bpy.data.materials.new("MuzzleFlash")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (0.55, 0.95, 1.0, 1)
    b.inputs["Emission Strength"].default_value = 25.0
    m.diffuse_color = (0.55, 0.95, 1.0, 1)
    me.materials.append(m)
    return me


root, slide, barrel, trigger = O["XM9"], O["Slide"], O["Barrel"], O["Trigger"]
for ob in (root, slide, barrel, trigger):
    clear(ob)
sc.frame_set(1)

# Rest values (whatever they are in the file now, so hand edits are respected).
s0, b0 = slide.location.y, barrel.location.y
bx0, tx0 = barrel.rotation_euler.x, trigger.rotation_euler.x

keys(trigger, "rotation_euler", 0, [(1, tx0), (3, tx0 + math.radians(-22)), (7, tx0 + math.radians(-22)), (10, tx0)])
keys(slide, "location", 1, [(3, s0, "EXPO", "EASE_OUT"), (5, s0 - SLIDE_TRAVEL, "CONSTANT"),
                            (7, s0 - SLIDE_TRAVEL, "BACK", "EASE_OUT"), (10, s0)])
keys(barrel, "location", 1, [(3, b0, "EXPO", "EASE_OUT"), (4, b0 - 0.004, "CONSTANT"), (7, b0 - 0.004), (9, b0)])
keys(barrel, "rotation_euler", 0, [(4, bx0, "EXPO", "EASE_OUT"), (5, bx0 + math.radians(4), "CONSTANT"),
                                   (7, bx0 + math.radians(4)), (9, bx0)])
# Recoil: kick back + muzzle flip about the grip, slight twist, settle with a small overshoot.
keys(root, "location", 1, [(1, 0.0), (3, 0.0, "EXPO", "EASE_OUT"), (4, -0.022, "BEZIER"), (12, 0.0)])
keys(root, "location", 2, [(1, 0.0), (3, 0.0, "EXPO", "EASE_OUT"), (4, 0.004, "BEZIER"), (12, 0.0)])
keys(root, "rotation_euler", 0, [(1, 0.0), (3, 0.0, "EXPO", "EASE_OUT"), (5, math.radians(8), "BACK", "EASE_OUT"),
                                 (14, 0.0)])
keys(root, "rotation_euler", 2, [(1, 0.0), (3, 0.0, "EXPO", "EASE_OUT"), (5, math.radians(2), "BEZIER"), (13, 0.0)])

# Muzzle flash (child of the Muzzle marker): visible on frames 3-4 only.
flash = O.get("MuzzleFlash")
if flash is None:
    flash = O.new("MuzzleFlash", flash_mesh())
    O["XM9"].users_collection[0].objects.link(flash)
    flash.parent = O["Muzzle"]
clear(flash)
flash.location = (0, 0, 0)
for f, s, rz in ((1, 0.0, 0), (2, 0.0, 0), (3, 1.0, 0), (4, 0.7, 40), (5, 0.0, 40)):
    for i in range(3):
        keys(flash, "scale", i, [(f, s, "CONSTANT")])
    keys(flash, "rotation_euler", 1, [(f, math.radians(rz), "CONSTANT")])

# Casing: a copy of Parts/Casing, free-flying (not parented, so the gun's kick doesn't drag it).
cas = O.get("CasingFX")
if cas is None:
    cas = O.new("CasingFX", O["Casing"].data)
    O["XM9"].users_collection[0].objects.link(cas)
clear(cas)
cas.rotation_mode = "XYZ"
bpy.context.view_layer.update()
# Ejection point when the slide is fully back (Eject rides on the slide).
p0 = O["Eject"].matrix_world.translation + Vector((0, -SLIDE_TRAVEL, 0)) - O["Casing"].data.vertices[0].co * 0
c0 = sum((v.co for v in O["Casing"].data.vertices), Vector()) / len(O["Casing"].data.vertices)
for i in range(3):
    keys(cas, "scale", i, [(1, 0.0, "CONSTANT"), (5, 1.0, "CONSTANT")])
for f in range(5, 25):
    t = (f - 5) / FPS
    p = p0 + EJECT_V * t + Vector((0, 0, -0.5 * G * t * t)) - c0
    for i in range(3):
        keys(cas, "location", i, [(f, p[i], "LINEAR")])
        keys(cas, "rotation_euler", i, [(f, SPIN[i] * t, "LINEAR")])
for i in range(3):
    keys(cas, "location", i, [(1, (p0 - c0)[i], "CONSTANT")])
    keys(cas, "rotation_euler", i, [(1, 0.0, "CONSTANT")])

# The spare casing in Parts is a library piece for the game; keep it out of the view.
parts = bpy.data.collections.get("Parts")
if parts:
    parts.hide_viewport = True
    parts.hide_render = True
sc.frame_set(1)
bpy.ops.wm.save_mainfile()
print("animated", bpy.data.filepath, "frames", sc.frame_start, "-", sc.frame_end)
