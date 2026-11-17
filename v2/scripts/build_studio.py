"""The lab's test room: a plain studio, the size of the concept room, so the robots' arenas, the doorways and the
player's start stay where they are. (The detailed room of scene.blend is kept for the real game.)

    blender -b -P v2/scripts/build_studio.py          # -> v2/studio.blend + assets/models/v2/studio.glb

Blender metres, z up; the game's room frame is (x, z, -y). Inside: x -4.6..6.4, y -3..14, floor z 0, ceiling 5.2
(the turret's pylon ends there). Doorways through both side walls at y 10.2, 1.3 wide, 2.25 high: the same
opening `export_godot.py cut_doorways` cuts into the concept room; `v2_lab.gd` lines them with steel.
The materials are only names here: the game builds them (`V2Assets.SPECIAL`, the floor's grid is `v2_grid.gdshader`).
What stands in the room: three blocks to take cover behind, all outside the spider's and the drone's arenas
(`V2Robot.SPEC`): a low wall right of the start, a chest-high crate on the left, a tall block on the right.
"""
import os

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "models", "v2", "studio.glb")
BLEND = os.path.join(HERE, "..", "studio.blend")

XL, XR, Y0, Y1, H = -4.6, 6.4, -3.0, 14.0, 5.2
WALL = 0.3
DOOR_Y, DOOR_W, DOOR_H = 10.2, 1.3, 2.25

bpy.ops.wm.read_factory_settings(use_empty=True)
COLOURS = {  # (base colour, roughness, emission strength): what the .blend shows; the game has its own table
    "StudioFloor": ((0.33, 0.35, 0.37), 0.7, 0.0), "StudioWall": ((0.6, 0.61, 0.63), 0.85, 0.0),
    "StudioDark": ((0.02, 0.022, 0.026), 0.6, 0.0), "StudioBlock": ((0.25, 0.27, 0.3), 0.7, 0.0),
    "StudioLight": ((1, 1, 1), 0.5, 6.0), "Hazard": ((0.8, 0.55, 0.02), 0.5, 0.0),
}
MATS = {}
for name, (col, rough, emit) in COLOURS.items():
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (1, 1, 1, 1)
        b.inputs["Emission Strength"].default_value = emit
    MATS[name] = m


class Part:
    """Boxes gathered into one mesh object."""

    def __init__(self, name, mat, bevel=0.0):
        self.name, self.mat, self.bevel = name, mat, bevel
        self.verts, self.faces = [], []

    def box(self, lo, hi):
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        n = len(self.verts)
        self.verts += [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        self.faces += [tuple(n + i for i in f) for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7))]

    def done(self):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.verts, [], self.faces)
        me.materials.append(MATS[self.mat])
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        if self.bevel:
            md = ob.modifiers.new("Bevel", "BEVEL")
            md.width, md.segments, md.limit_method = self.bevel, 2, "ANGLE"
        return ob


floor = Part("StudioFloor", "StudioFloor")
floor.box((XL - WALL, Y0 - WALL, -0.2), (XR + WALL, Y1 + WALL, 0.0))
floor.done()

ceil = Part("StudioCeiling", "StudioWall")
ceil.box((XL - WALL, Y0 - WALL, H), (XR + WALL, Y1 + WALL, H + 0.2))
ceil.done()

walls = Part("StudioWalls", "StudioWall")
walls.box((XL - WALL, Y0 - WALL, 0), (XR + WALL, Y0, H))                      # behind the player
walls.box((XL - WALL, Y1, 0), (XR + WALL, Y1 + WALL, H))                      # the far end
d0, d1 = DOOR_Y - DOOR_W / 2, DOOR_Y + DOOR_W / 2
for x0, x1 in ((XL - WALL, XL), (XR, XR + WALL)):                             # the sides, each with its doorway
    walls.box((x0, Y0, 0), (x1, d0, H))
    walls.box((x0, d1, 0), (x1, Y1, H))
    walls.box((x0, d0, DOOR_H), (x1, d1, H))
walls.done()

trim = Part("StudioTrim", "StudioDark")                                      # skirting, and a band where the ceiling starts
T = 0.02
for z0, z1 in ((0.0, 0.16), (H - 0.12, H)):
    trim.box((XL, Y0, z0), (XR, Y0 + T, z1))
    trim.box((XL, Y1 - T, z0), (XR, Y1, z1))
    for x0, x1 in ((XL, XL + T), (XR - T, XR)):
        if z0 == 0.0:                                                         # (the skirting stops at the doorway)
            trim.box((x0, Y0, z0), (x1, d0 - 0.06, z1))
            trim.box((x0, d1 + 0.06, z0), (x1, Y1, z1))
        else:
            trim.box((x0, Y0, z0), (x1, Y1, z1))
trim.done()

# six light panels in the ceiling, over the six lights the game hangs there (x -2 / 3.8; y 0, 5.5, 11)
lights = Part("StudioLights", "StudioLight")
frames = Part("StudioLightFrames", "StudioDark")
for y in (0.0, 5.5, 11.0):
    for x in (-2.0, 3.8):
        lights.box((x - 1.2, y - 0.6, H - 0.03), (x + 1.2, y + 0.6, H + 0.01))
        for lo, hi in (((x - 1.28, y - 0.68), (x + 1.28, y - 0.6)), ((x - 1.28, y + 0.6), (x + 1.28, y + 0.68)),
                       ((x - 1.28, y - 0.6), (x - 1.2, y + 0.6)), ((x + 1.2, y - 0.6), (x + 1.28, y + 0.6))):
            frames.box((*lo, H - 0.05), (*hi, H + 0.01))
lights.done()
frames.done()

# cover: (x0, y0, x1, y1, height)
blocks = Part("StudioBlocks", "StudioBlock", bevel=0.015)
bands = Part("StudioBlockBands", "Hazard")
for x0, y0, x1, y1, h in ((2.9, 1.2, 4.5, 1.6, 1.1), (-3.9, 2.0, -2.9, 3.2, 1.3), (4.0, 4.5, 5.2, 5.5, 2.2)):
    blocks.box((x0, y0, 0.0), (x1, y1, h - 0.1))
    bands.box((x0, y0, h - 0.1), (x1, y1, h))
blocks.done()
bands.done()

for ob in bpy.context.scene.objects:
    ob.select_set(True)
bpy.context.view_layer.objects.active = bpy.context.scene.objects[0]
bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                          export_image_format="NONE", export_materials="EXPORT", export_animations=False)
print("studio:", len(bpy.context.scene.objects), "objects ->", os.path.normpath(OUT))
