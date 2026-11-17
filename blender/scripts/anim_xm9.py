"""Fire + Reload animations on the XM9 (runs on the saved file, so edits made in blender/xm9.blend are kept).

    blender -b blender/xm9.blend -P blender/scripts/anim_xm9.py

One shot, 24 frames at 30 fps; Space in Blender plays it in a loop. Snappy arcade timing:
  f1-3   trigger pulls                       f3   shot: muzzle flash, gun kicks back + flips up
  f3-5   slide snaps back 3.2 cm (barrel back 4 mm, chamber tilts down 4 deg)
  f5     casing pops out of the ejection port (flies up/right, spinning, falls)
  f7-10  slide slams forward (small overshoot), trigger resets   f4-13 gun settles
Reload (frames 31-72, ~1.4 s, empty reload, no hands yet; markers "Fire" / "Reload" on the timeline):
  f31    slide locked back (empty)            f31-37 gun tilts up, rolls, swings in
  f34-36 magazine pops out along the grip, f36-44 falls away
  f45-52 fresh magazine flies up into the grip, f52 seats (gun jolts)
  f57-59 slide slams forward (gun jolts)    f60-70 gun returns to the hip
One action per object ("<object>_Anim") holds both clips; the game export splits them by marker. In the game the casing becomes a physics object spawned at the
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
sc.frame_start, sc.frame_end = 1, 72
O = bpy.data.objects


def keys(ob, path, index, frames, interp="BEZIER", easing="AUTO"):
    """frames: list of (frame, value[, interpolation, easing]); interpolation applies to the segment that starts there."""
    if ob.animation_data is None:
        ob.animation_data_create()
    if ob.animation_data.action is None:
        ob.animation_data.action = bpy.data.actions.new(f"{ob.name}_Anim")
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


root, slide, barrel, trigger, mag = O["XM9"], O["Slide"], O["Barrel"], O["Trigger"], O["Magazine"]
for ob in (root, slide, barrel, trigger, mag):
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
    keys(cas, "scale", i, [(1, 0.0, "CONSTANT"), (5, 1.0, "CONSTANT"), (25, 0.0, "CONSTANT")])
for f in range(5, 25):
    t = (f - 5) / FPS
    p = p0 + EJECT_V * t + Vector((0, 0, -0.5 * G * t * t)) - c0
    for i in range(3):
        keys(cas, "location", i, [(f, p[i], "LINEAR")])
        keys(cas, "rotation_euler", i, [(f, SPIN[i] * t, "LINEAR")])
for i in range(3):
    keys(cas, "location", i, [(1, (p0 - c0)[i], "CONSTANT")])
    keys(cas, "rotation_euler", i, [(1, 0.0, "CONSTANT")])

# ---- Reload (frames 31-72) ---------------------------------------------------------------------------
R = 30  # offset: reload frame n is timeline frame R + n
m0 = mag.location.copy()
bpy.context.view_layer.update()
drop = (root.matrix_world.inverted() @ O["MagAxis"].matrix_world).to_3x3().col[2].normalized()  # down the grip
d = math.radians
# Slide locked back for the whole reload until the release, barrel tilted with it.
keys(slide, "location", 1, [(R + 1, s0 - SLIDE_TRAVEL, "CONSTANT"), (R + 27, s0 - SLIDE_TRAVEL, "EXPO", "EASE_OUT"),
                            (R + 29, s0)])
keys(barrel, "location", 1, [(R + 1, b0 - 0.004, "CONSTANT"), (R + 27, b0 - 0.004, "EXPO", "EASE_OUT"), (R + 29, b0)])
keys(barrel, "rotation_euler", 0, [(R + 1, bx0 + d(4), "CONSTANT"), (R + 27, bx0 + d(4), "EXPO", "EASE_OUT"), (R + 29, bx0)])
# Gun: tilt up, roll the grip toward the camera, swing in; jolts at the seat (f52) and slide release (f58).
keys(root, "rotation_euler", 0, [(R + 1, 0.0, "BACK", "EASE_OUT"), (R + 7, d(14)), (R + 21, d(14), "EXPO", "EASE_OUT"),
                                 (R + 22, d(9)), (R + 24, d(14)), (R + 27, d(14), "EXPO", "EASE_OUT"), (R + 28, d(19)),
                                 (R + 31, d(14), "BACK", "EASE_OUT"), (R + 40, 0.0)])
keys(root, "rotation_euler", 1, [(R + 1, 0.0, "BACK", "EASE_OUT"), (R + 7, d(-30)), (R + 30, d(-30), "BACK", "EASE_OUT"),
                                 (R + 40, 0.0)])
keys(root, "rotation_euler", 2, [(R + 1, 0.0, "BACK", "EASE_OUT"), (R + 7, d(12)), (R + 30, d(12), "BACK", "EASE_OUT"),
                                 (R + 40, 0.0)])
keys(root, "location", 2, [(R + 1, 0.0, "BACK", "EASE_OUT"), (R + 7, 0.02), (R + 21, 0.02, "EXPO", "EASE_OUT"),
                           (R + 22, 0.028), (R + 25, 0.02), (R + 30, 0.02, "BACK", "EASE_OUT"), (R + 40, 0.0)])
keys(root, "location", 0, [(R + 1, 0.0, "BACK", "EASE_OUT"), (R + 7, -0.02), (R + 30, -0.02, "BACK", "EASE_OUT"),
                           (R + 40, 0.0)])
# Magazine: pops out along the grip, falls away (accelerating), then a fresh one flies in and seats.
for i in range(3):
    def a(t, i=i):
        return (m0 + drop * t)[i]
    keys(mag, "location", i, [(1, m0[i], "CONSTANT"), (R + 4, a(0.0), "EXPO", "EASE_OUT"), (R + 6, a(0.03), "QUAD", "EASE_IN"),
                              (R + 14, a(0.32), "CONSTANT"), (R + 15, a(0.16), "EXPO", "EASE_OUT"),
                              (R + 21, a(0.012), "QUAD", "EASE_IN"), (R + 22, a(0.0))])
for name, f in (("Fire", 1), ("Reload", R + 1)):
    mk = sc.timeline_markers.get(name) or sc.timeline_markers.new(name, frame=f)
    mk.frame = f

# The spare casing in Parts is a library piece for the game; keep it out of the view.
parts = bpy.data.collections.get("Parts")
if parts:
    parts.hide_viewport = True
    parts.hide_render = True
sc.frame_set(1)
bpy.ops.wm.save_mainfile()
print("animated", bpy.data.filepath, "frames", sc.frame_start, "-", sc.frame_end)
