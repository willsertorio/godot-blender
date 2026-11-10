"""Modelled props: loot container (container.glb) and exit portal (portal.glb).

    blender -b -P blender/scripts/build_props.py -- assets/models

Container: root "Container" (origin at the floor, front faces +Y) with child "Lid" hinged
on the back top edge, action "Open" (lid swings up 105 degrees over 0.5 s). Body 1.0 x 0.7 x 0.62 m.
"""
import math
import os
import sys

sys.path.append(os.path.dirname(__file__))
import bpy  # noqa: E402
from lib_hardsurface import Part, build, export_glb, reset_scene  # noqa: E402

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"

W, D, H = 1.0, 0.7, 0.62   # body width (x), depth (y), height (z)
LID_H = 0.14


def container():
    root = bpy.data.objects.new("Container", None)
    bpy.context.scene.collection.objects.link(root)
    hw, hd = W / 2, D / 2
    body = [
        # Shell, with a recessed front panel and corner posts.
        Part((-hw + 0.04, -hd + 0.04, 0.06), (hw - 0.04, hd - 0.04, H), "CrateMetal", bevel=0.02),
        Part((-hw, -hd, 0), (hw, hd, 0.08), "WallTrim", bevel=0.015),          # plinth
        Part((-hw + 0.1, hd - 0.05, 0.14), (hw - 0.1, hd - 0.02, H - 0.08), "WallTrim", bevel=0.008),
        # Green status light bar on the front and the glowing interior (seen when open).
        Part((-0.22, hd - 0.02, H - 0.2), (0.22, hd + 0.004, H - 0.16), "NeonGreen", bevel=0),
        Part((-hw + 0.08, -hd + 0.08, H - 0.02), (hw - 0.08, hd - 0.08, H - 0.005), "NeonGreen", bevel=0),
        # Vertical light strips on the four corner posts (front and sides).
        *[Part((sx * hw - 0.012 if sx > 0 else -hw - 0.002, sy * hd - 0.06 if sy > 0 else -hd + 0.02, 0.12),
               (hw + 0.002 if sx > 0 else -hw + 0.012, sy * hd - 0.02 if sy > 0 else -hd + 0.06, H - 0.04), "NeonGreen", bevel=0)
          for sx in (-1, 1) for sy in (-1, 1)],
    ]
    for sx in (-1, 1):
        for sy in (-1, 1):
            x0, y0 = (hw - 0.09) * sx, (hd - 0.09) * sy
            body.append(Part((min(x0, sx * hw), min(y0, sy * hd), 0.06), (max(x0, sx * hw), max(y0, sy * hd), H),
                             "WallTrim", bevel=0.02))
    b = build("Body", body)
    b.parent = root

    # Lid geometry is built relative to its hinge (back top edge), so rotation opens it.
    hinge = (0, -hd, H)
    lid_parts = [
        Part((-hw, 0, 0), (hw, D, LID_H), "CrateMetal", bevel=0.025),
        Part((-hw + 0.12, 0.12, LID_H), (hw - 0.12, D - 0.12, LID_H + 0.02), "WallTrim", bevel=0.01),
        Part((-hw - 0.004, 0.02, 0.03), (hw + 0.004, D - 0.02, 0.06), "NeonGreen", bevel=0),
    ]
    lid = build("Lid", lid_parts)
    lid.parent = root
    lid.location = hinge

    act = bpy.data.actions.new("Open")
    lid.animation_data_create()
    lid.animation_data.action = act
    lid.rotation_mode = "XYZ"
    lid.rotation_euler = (0, 0, 0)
    lid.keyframe_insert("rotation_euler", index=0, frame=0)
    lid.rotation_euler = (math.radians(105), 0, 0)
    lid.keyframe_insert("rotation_euler", index=0, frame=15)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.easing = "EASE_OUT"
    lid.rotation_euler = (0, 0, 0)
    bpy.context.scene.frame_set(0)
    return root


def portal():
    """Exit gate: octagonal bevelled frame on a plinth, violet neon inner edge, and a
    "Field" disc (material PortalField) that Godot drives with the portal shader.
    Faces +Y; ring centre at 1.45 m; inner radius 1.05 m (the Area3D is radius 1.0)."""
    from lib_hardsurface import MATERIALS
    MATERIALS["PortalField"] = dict(color=(0.7, 0.55, 1.0), emit=3.0)
    root = bpy.data.objects.new("Portal", None)
    bpy.context.scene.collection.objects.link(root)
    cz, r_in, r_out, depth = 1.45, 1.08, 1.38, 0.34
    parts = [
        Part((-1.7, -0.9, 0.0), (1.7, 0.9, 0.12), "WallTrim", bevel=0.03),            # plinth
        Part((-1.5, -0.75, 0.12), (1.5, 0.75, 0.16), "FrameMetal", bevel=0.015),
        Part((-1.52, -0.77, 0.115), (1.52, 0.77, 0.135), "NeonViolet", bevel=0),
    ]
    # Eight frame segments around the ring.
    seg = 2 * r_out * math.tan(math.pi / 8)
    for i in range(8):
        a = i * math.pi / 4
        mid = (r_in + r_out) / 2
        x, z = math.cos(a) * mid, cz + math.sin(a) * mid
        parts.append(Part((x - (r_out - r_in) / 2, -depth / 2, z - seg / 2), (x + (r_out - r_in) / 2, depth / 2, z + seg / 2),
                          "FrameMetal", rot=(0, -a, 0), bevel=0.035))
        # Violet light pads on both faces of every segment.
        for y0, y1 in ((depth / 2, depth / 2 + 0.012), (-depth / 2 - 0.012, -depth / 2)):
            parts.append(Part((x - 0.035, y0, z - seg * 0.32), (x + 0.035, y1, z + seg * 0.32), "NeonViolet",
                              rot=(0, -a, 0), bevel=0))
    # Inner neon lip.
    parts.append(Part((-r_in - 0.03, -0.05, cz - r_in - 0.03), (r_in + 0.03, 0.05, cz + r_in + 0.03), "NeonViolet",
                      kind="torus", segments=16, rot=(math.pi / 2, 0, 0), bevel=0))
    # Feet that tie the ring to the plinth.
    for sx in (-1, 1):
        parts.append(Part((sx * 0.55 - 0.18, -0.22, 0.12), (sx * 0.55 + 0.18, 0.22, 0.55), "FrameMetal", bevel=0.03))
    frame = build("Frame", parts)
    frame.parent = root
    field = build("Field", [Part((-r_in, -0.01, cz - r_in), (r_in, 0.01, cz + r_in), "PortalField",
                                 kind="cyl", axis="Y", segments=32, bevel=0)])
    field.parent = root
    return root


from lib_hardsurface import MATERIALS as _M  # noqa: E402
_M.setdefault("FrameMetal", dict(color=(0.22, 0.23, 0.25), metallic=0.8, rough=0.35))

reset_scene()
c = container()
os.makedirs(OUT, exist_ok=True)
export_glb(os.path.join(OUT, "container.glb"), [c], animations=True)

reset_scene()
pt = portal()
export_glb(os.path.join(OUT, "portal.glb"), [pt])
