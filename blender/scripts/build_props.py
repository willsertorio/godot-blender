"""Exit portal (portal.glb): modelled gate on the MegaKit round pad. (The loot container now comes
from the Quaternius pack: see normalize_quaternius.py.)

    blender -b -P blender/scripts/build_props.py -- assets/models

Container: root "Container" (origin at the floor, front faces +Y) with child "Lid" hinged
on the back top edge, action "Open" (lid swings up 105 degrees over 0.5 s). Body 1.0 x 0.7 x 0.62 m.
"""
import math
import os
import sys

sys.path.append(os.path.dirname(__file__))
import bpy  # noqa: E402
from mathutils import Matrix  # noqa: E402
from lib_hardsurface import Part, build, export_glb, reset_scene  # noqa: E402

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/models"

W, D, H = 1.0, 0.7, 0.62   # body width (x), depth (y), height (z)
LID_H = 0.14


def portal():
    """Exit gate: octagonal bevelled frame on a plinth, violet neon inner edge, and a
    "Field" disc (material PortalField) that Godot drives with the portal shader.
    Faces +Y; ring centre at 1.45 m; inner radius 1.05 m (the Area3D is radius 1.0)."""
    from lib_hardsurface import MATERIALS
    MATERIALS["PortalField"] = dict(color=(0.7, 0.55, 1.0), emit=3.0)
    root = bpy.data.objects.new("Portal", None)
    bpy.context.scene.collection.objects.link(root)
    cz, r_in, r_out, depth = 1.45, 1.08, 1.38, 0.34
    MATERIALS["PortalFrame"] = dict(color=(0.16, 0.17, 0.19), metallic=0.4, rough=0.45)
    MATERIALS["PortalTrim"] = dict(color=(0.62, 0.64, 0.67), metallic=0.3, rough=0.4)
    parts = []
    # Eight frame segments around the ring.
    seg = 2 * r_out * math.tan(math.pi / 8)
    for i in range(8):
        a = i * math.pi / 4
        mid = (r_in + r_out) / 2
        x, z = math.cos(a) * mid, cz + math.sin(a) * mid
        parts.append(Part((x - (r_out - r_in) / 2, -depth / 2, z - seg / 2), (x + (r_out - r_in) / 2, depth / 2, z + seg / 2),
                          "PortalFrame", rot=(0, -a, 0), bevel=0.035))
        # Violet light pads on both faces of every segment.
        for y0, y1 in ((depth / 2, depth / 2 + 0.012), (-depth / 2 - 0.012, -depth / 2)):
            parts.append(Part((x - 0.035, y0, z - seg * 0.32), (x + 0.035, y1, z + seg * 0.32), "NeonViolet",
                              rot=(0, -a, 0), bevel=0))
    # Inner neon lip.
    parts.append(Part((-r_in - 0.03, -0.05, cz - r_in - 0.03), (r_in + 0.03, 0.05, cz + r_in + 0.03), "NeonViolet",
                      kind="torus", segments=16, rot=(math.pi / 2, 0, 0), bevel=0))
    # Feet that tie the ring to the plinth.
    for sx in (-1, 1):
        parts.append(Part((sx * 0.55 - 0.18, -0.22, 0.12), (sx * 0.55 + 0.18, 0.22, 0.55), "PortalTrim", bevel=0.03))
    frame = build("Frame", parts)
    frame.parent = root
    field = build("Field", [Part((-r_in, -0.01, cz - r_in), (r_in, 0.01, cz + r_in), "PortalField",
                                 kind="cyl", axis="Y", segments=32, bevel=0)])
    field.parent = root
    # Base: the MegaKit's round floor pad (CC0), scaled to 3 m; keeps its Quaternius material.
    pad_src = os.path.join(os.path.dirname(__file__), "..", "..", "assets_src", "quaternius", "modular-sci-fi-megakit",
                           "Modular SciFi MegaKit[Standard]", "glTF", "Platforms", "Platform_Round1.gltf")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(pad_src))
    for o in set(bpy.data.objects) - before:
        if o.type == "MESH" and o.data.materials:
            o.data.transform(o.matrix_world)
            o.matrix_world = Matrix.Scale(0.5, 4)
            o.parent = root
            o.name = "Pad"
            for slot in o.material_slots:
                slot.material.name = slot.material.name.split(".")[0]
    return root


from lib_hardsurface import MATERIALS as _M  # noqa: E402
_M.setdefault("FrameMetal", dict(color=(0.22, 0.23, 0.25), metallic=0.8, rough=0.35))

os.makedirs(OUT, exist_ok=True)

reset_scene()
pt = portal()
export_glb(os.path.join(OUT, "portal.glb"), [pt])
