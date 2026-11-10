"""Environment kit: floor, ceiling, wall, doorframe, pillar (kit_env.glb) and door (door.glb).

    blender -b -P blender/scripts/build_kit.py -- assets/models

Piece frames (Blender; Godot frames in CLAUDE.md follow from +Y forward -> Godot -Z):
  Floor / Ceiling / CeilingLight : origin at the cell centre (4 x 4 m); floor top z=0, ceiling underside z=4.
  Wall            : origin at the edge midpoint, spans x -2..2, room-side face at y=0 facing +Y,
                    thickness behind it toward -Y (0.3 m), height 4 m.
  Doorframe       : same frame; 2.4 x 3 m opening centred on x=0, protrudes 6 cm both sides.
  Pillar          : origin at the grid vertex, 0.9 m footprint.
  Door            : root "Door" with child "Panel" (2.4 x 3 m) + action "Open" (slides up 2.95 m).
"""
import math
import os
import sys

sys.path.append(os.path.dirname(__file__))
import bpy  # noqa: E402
from lib_hardsurface import Part, build, export_glb, reset_scene  # noqa: E402

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"


def floor():
    parts = [Part((-2, -2, -0.25), (2, 2, -0.05), "WallTrim", bevel=0)]
    # Four 2 x 2 m deck plates with bevelled edges and a 2 cm seam.
    for x0 in (-2, 0):
        for y0 in (-2, 0):
            parts.append(Part((x0 + 0.012, y0 + 0.012, -0.06), (x0 + 1.988, y0 + 1.988, 0.0), "Floor", bevel=0.008))
    return build("Floor", parts)


def ceiling(with_light):
    parts = [Part((-2, -2, 4.02), (2, 2, 4.25), "WallTrim", bevel=0)]
    for x0 in (-2, 0):
        for y0 in (-2, 0):
            parts.append(Part((x0 + 0.015, y0 + 0.015, 4.0), (x0 + 1.985, y0 + 1.985, 4.05), "Ceiling", bevel=0.01))
    if with_light:
        # Square light fixture in the cell centre: housing + diffuser.
        parts.append(Part((-0.75, -0.75, 3.9), (0.75, 0.75, 4.01), "WallTrim", bevel=0.025))
        parts.append(Part((-0.62, -0.62, 3.885), (0.62, 0.62, 3.9), "LightPanel", bevel=0.004))
    return build("CeilingLight" if with_light else "Ceiling", parts)


def wall():
    p = [
        # Structural backing (visible in panel seams).
        Part((-2, -0.3, 0), (2, -0.05, 4), "WallTrim", bevel=0),
        # Kick plate and cornice protrude slightly into the room.
        Part((-2, -0.06, 0), (2, 0.035, 0.3), "WallTrim", bevel=0.015),
        Part((-2, -0.06, 3.9), (2, 0.04, 4.0), "WallTrim", bevel=0.015),
        # Neon channel: recessed band with the cyan strip.
        Part((-2, -0.07, 2.86), (2, -0.035, 3.14), "WallTrim", bevel=0.006),
        Part((-2, -0.045, 2.97), (2, -0.02, 3.03), "NeonCyan", bevel=0.004),
        # Floor-level glow line under the kick plate lip.
        Part((-2, 0.02, 0.305), (2, 0.032, 0.325), "NeonCyan", bevel=0),
    ]
    # Two lower and two upper panels per 4 m wall, 4 cm seams.
    for x0, x1 in ((-1.98, -0.02), (0.02, 1.98)):
        p.append(Part((x0, -0.06, 0.32), (x1, 0.0, 2.84), "WallPanel", bevel=0.018))
        p.append(Part((x0, -0.06, 3.16), (x1, 0.0, 3.88), "WallPanel", bevel=0.018))
        # Inset service hatch on the lower panel.
        cx = (x0 + x1) * 0.5
        p.append(Part((cx - 0.45, -0.005, 0.7), (cx + 0.45, 0.012, 1.5), "WallTrim", bevel=0.01))
    return build("Wall", p)


def doorframe():
    d = 0.06  # protrusion either side of the 0..-0.3 wall slab
    p = [
        Part((-2, -0.3 - d, 0), (-1.2, d, 4), "WallTrim", bevel=0.04),
        Part((1.2, -0.3 - d, 0), (2, d, 4), "WallTrim", bevel=0.04),
        Part((-1.2, -0.3 - d, 3), (1.2, d, 4), "WallTrim", bevel=0.04),
    ]
    # Neon outline around the opening, on both faces.
    for y0, y1 in ((d, d + 0.012), (-0.3 - d - 0.012, -0.3 - d)):
        p += [
            Part((-1.32, y0, 0.05), (-1.27, y1, 3.12), "NeonCyan", bevel=0),
            Part((1.27, y0, 0.05), (1.32, y1, 3.12), "NeonCyan", bevel=0),
            Part((-1.32, y0, 3.07), (1.32, y1, 3.12), "NeonCyan", bevel=0),
        ]
    return build("Doorframe", p)


def pillar():
    r = 0.36
    p = [
        Part((-0.45, -0.45, 0), (0.45, 0.45, 0.3), "WallTrim", bevel=0.03),
        Part((-0.45, -0.45, 3.7), (0.45, 0.45, 4.0), "WallTrim", bevel=0.03),
        Part((-r, -r, 0.3), (r, r, 3.7), "WallPanel", bevel=0.07),
    ]
    # Neon strips on the four chamfered corners.
    k = r - 0.03
    for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1)):
        c = (sx * k, sy * k)
        p.append(Part((c[0] - 0.012, c[1] - 0.03, 0.5), (c[0] + 0.012, c[1] + 0.03, 3.5), "NeonCyan",
                      bevel=0, rot_z=math.atan2(sy, sx)))
    return build("Pillar", p, segments=1)


def door():
    root = bpy.data.objects.new("Door", None)
    bpy.context.scene.collection.objects.link(root)
    y0, y1 = -0.22, -0.08  # Godot z 0.08..0.22: inside the frame depth
    p = [
        Part((-1.2, y0, 0), (1.2, y1, 3.0), "DoorMetal", bevel=0.02),
        # Horizontal ribs and kick strip, both faces.
        Part((-1.15, y0 - 0.02, 0.95), (1.15, y1 + 0.02, 1.08), "WallTrim", bevel=0.012),
        Part((-1.15, y0 - 0.02, 2.0), (1.15, y1 + 0.02, 2.13), "WallTrim", bevel=0.012),
        Part((-1.15, y0 - 0.02, 0.0), (1.15, y1 + 0.02, 0.22), "WallTrim", bevel=0.012),
        # Centre seam glow on both faces.
        Part((-0.025, y1, 0.3), (0.025, y1 + 0.03, 2.8), "NeonCyan", bevel=0),
        Part((-0.025, y0 - 0.03, 0.3), (0.025, y0, 2.8), "NeonCyan", bevel=0),
    ]
    panel = build("Panel", p)
    panel.parent = root

    act = bpy.data.actions.new("Open")
    panel.animation_data_create()
    panel.animation_data.action = act
    panel.location = (0, 0, 0)
    panel.keyframe_insert("location", index=2, frame=0)
    panel.location = (0, 0, 2.95)
    panel.keyframe_insert("location", index=2, frame=18)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.easing = "EASE_IN_OUT"
    panel.location = (0, 0, 0)
    bpy.context.scene.frame_set(0)
    return root


reset_scene()
pieces = [floor(), ceiling(False), ceiling(True), wall(), doorframe(), pillar()]
os.makedirs(OUT, exist_ok=True)
export_glb(os.path.join(OUT, "kit_env.glb"), pieces)

reset_scene()
d = door()
export_glb(os.path.join(OUT, "door.glb"), [d], animations=True)
