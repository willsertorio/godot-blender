"""The game's modular kit in the V2 look: the pieces the generated dungeon is built from (scripts/v2/v2_dungeon.gd).

    blender -b -P v2/scripts/build_kit.py          # -> v2/kit.blend + assets/models/v2/kit.glb

The dungeon is a grid of 4 m cells (scripts/dungeon_gen.gd). Rooms are 5.2 m high (the ceiling turret's pylon ends
there), corridors 3.4 m. Blender metres, z up. Every piece is an empty with its parts under it:
  floor / ceiling pieces   origin at the cell's centre on the floor
  wall pieces              origin at the middle of the cell's edge on the floor, 4 m along x, the room on its -Y
                           side (Godot +Z), its thickness (0.3 m) toward +Y: `Wall`, `WallScreen`, `WallPipes`,
                           `WallDoor` (opening 2.4 x 2.6 m), `CWall` (corridor, 3.4 m high)
  props                    origin at the base, front toward -Y: `Tank`, `Console`, `Block`, `Locker`; `Column` (a room
                           column, floor to ceiling, for the corners of cells inside the bigger rooms)
The materials are only names here, those of the concept room and the robots (assets/models/v2/materials.json):
the game builds them (`V2Assets`) and merges a room's pieces into one mesh per material.
Nothing may reach more than 0.12 m into the cell from a wall's face (the generator keeps what stands against a
wall clear of it by that much), and layers of one surface are 4 mm or more apart (closer, they flicker).
"""
import math
import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "models", "v2", "kit.glb")
BLEND = os.path.join(HERE, "..", "kit.blend")
H, HC = 5.2, 3.4                      # room and corridor height
T = 0.3                               # wall thickness
DW, DH = 1.2, 2.6                     # doorway: half width, height

bpy.ops.wm.read_factory_settings(use_empty=True)
COLOURS = {  # what the .blend shows (base colour, emission strength); the game has its own table
    "FloorTile": ((0.6, 0.62, 0.65), 0), "WallPanel": ((0.82, 0.85, 0.9), 0), "Concrete": ((0.6, 0.62, 0.64), 0),
    "Backing": ((0.03, 0.03, 0.04), 0), "DarkSteel": ((0.1, 0.11, 0.12), 0), "Steel": ((0.5, 0.52, 0.55), 0),
    "Galvanised": ((0.7, 0.72, 0.74), 0), "Grating": ((0.3, 0.3, 0.32), 0), "Hazard": ((0.8, 0.55, 0.02), 0),
    "CeilingLight": ((1, 1, 1), 6), "CoveLight": ((0.85, 0.95, 1.0), 6), "LightStrip": ((0.95, 0.98, 1.0), 8),
    "ScreenCyan": ((0.15, 0.85, 1.0), 5), "StatusOrange": ((1.0, 0.45, 0.1), 6), "SignGreen": ((0.2, 1.0, 0.45), 5),
    "TankLiquid": ((0.2, 0.62, 0.68), 1), "TankLight": ((0.75, 0.95, 1.0), 8), "RArmor": ((0.85, 0.86, 0.88), 0),
    "RFrame": ((0.03, 0.03, 0.035), 0),
}
MATS = {}
for name, (col, emit) in COLOURS.items():
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    if emit:
        b.inputs["Emission Color"].default_value = (*col, 1)
        b.inputs["Emission Strength"].default_value = emit
    MATS[name] = m

_slot = [0]


def piece(name):
    """An empty for a piece; the pieces stand in a row in the file, 8 m apart."""
    ob = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = (_slot[0] * 8.0, 0, 0)
    _slot[0] += 1
    return ob


class Part:
    """Boxes and cylinders gathered into one mesh object under `parent` (coordinates in the parent's frame)."""

    def __init__(self, name, mat, parent, bevel=0.0):
        self.name, self.mat, self.parent, self.bevel = name, mat, parent, bevel
        self.verts, self.faces = [], []

    def box(self, lo, hi):
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        x0, x1 = min(x0, x1), max(x0, x1)
        y0, y1 = min(y0, y1), max(y0, y1)
        z0, z1 = min(z0, z1), max(z0, z1)
        n = len(self.verts)
        self.verts += [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        self.faces += [tuple(n + i for i in f) for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7))]
        return self

    def cyl(self, cx, cy, z0, z1, r, seg=20):
        n = len(self.verts)
        for z in (z0, z1):
            for i in range(seg):
                a = math.tau * i / seg
                self.verts.append((cx + r * math.cos(a), cy + r * math.sin(a), z))
        for i in range(seg):
            j = (i + 1) % seg
            self.faces.append((n + i, n + j, n + seg + j, n + seg + i))
        self.faces.append(tuple(n + i for i in reversed(range(seg))))
        self.faces.append(tuple(n + seg + i for i in range(seg)))
        return self

    def done(self):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.verts, [], self.faces)
        me.materials.append(MATS[self.mat])
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = self.parent
        if self.bevel:
            md = ob.modifiers.new("Bevel", "BEVEL")
            md.width, md.segments, md.limit_method, md.angle_limit = self.bevel, 2, "ANGLE", math.radians(40)
        return ob


# ------------------------------------------------------------------ floors and ceilings (one cell: 4 x 4 m)
p = piece("Floor")
Part("Floor_Slab", "FloorTile", p).box((-2, -2, -0.2), (2, 2, 0)).done()
seam = Part("Floor_Seams", "DarkSteel", p)                           # the joints of the 2 m tiles
for v in (-2.0, 0.0):
    seam.box((v - 0.012, -2, 0.0), (v + 0.012, 2, 0.004)).box((-2, v - 0.012, 0.0), (2, v + 0.012, 0.004))
seam.done()

p = piece("CFloor")                                                 # corridor: a grating runs down its middle (along y)
Part("CFloor_Slab", "FloorTile", p).box((-2, -2, -0.2), (2, 2, 0)).done()
Part("CFloor_Grating", "Grating", p).box((-0.7, -2, 0.0), (0.7, 2, 0.006)).done()
Part("CFloor_Edge", "DarkSteel", p).box((-0.76, -2, 0.0), (-0.7, 2, 0.01)).box((0.7, -2, 0.0), (0.76, 2, 0.01)).done()

p = piece("Ceiling")                                                # a lit panel in a dark frame
Part("Ceiling_Slab", "Concrete", p).box((-2, -2, H), (2, 2, H + 0.2)).done()
Part("Ceiling_Light", "CeilingLight", p).box((-1.2, -0.6, H - 0.03), (1.2, 0.6, H - 0.005)).done()
fr = Part("Ceiling_Frame", "DarkSteel", p)
for lo, hi in (((-1.28, -0.68), (1.28, -0.6)), ((-1.28, 0.6), (1.28, 0.68)), ((-1.28, -0.6), (-1.2, 0.6)), ((1.2, -0.6), (1.28, 0.6))):
    fr.box((*lo, H - 0.06), (*hi, H))
fr.done()

p = piece("CeilingBeams")                                           # the cells between the lights: beams and a cable tray
Part("CeilingB_Slab", "Concrete", p).box((-2, -2, H), (2, 2, H + 0.2)).done()
Part("CeilingB_Beams", "DarkSteel", p).box((-2, -0.09, H - 0.16), (2, 0.09, H)).box((-0.09, -2, H - 0.16), (0.09, 2, H)).done()
Part("CeilingB_Tray", "Galvanised", p).box((0.9, -2, H - 0.3), (1.3, 2, H - 0.26)).box((0.9, -2, H - 0.26), (0.92, 2, H - 0.2)) \
    .box((1.28, -2, H - 0.26), (1.3, 2, H - 0.2)).done()
tr = Part("CeilingB_Hangers", "DarkSteel", p)
for y in (-1.2, 1.2):
    tr.box((0.88, y - 0.02, H - 0.3), (0.9, y + 0.02, H)).box((1.3, y - 0.02, H - 0.3), (1.32, y + 0.02, H))
tr.done()

p = piece("CCeiling")                                               # corridor: a light strip along it (y)
Part("CCeiling_Slab", "Concrete", p).box((-2, -2, HC), (2, 2, HC + 0.2)).done()
Part("CCeiling_Light", "CeilingLight", p).box((-0.16, -1.3, HC - 0.03), (0.16, 1.3, HC - 0.005)).done()
Part("CCeiling_Frame", "DarkSteel", p).box((-0.22, -1.36, HC - 0.05), (-0.16, 1.36, HC)).box((0.16, -1.36, HC - 0.05), (0.22, 1.36, HC)) \
    .box((-1.5, -2, HC - 0.12), (-1.3, 2, HC)).box((1.3, -2, HC - 0.12), (1.5, 2, HC)).done()


# ------------------------------------------------------------------ walls (the room is on -y)
def wall_base(name, height, band=True):
    """Slab, kick plate, panel joints, and (rooms) the dark upper band with its cove light."""
    w = piece(name)
    Part(name + "_Slab", "WallPanel", w).box((-2, 0, 0), (2, T, height)).done()
    dk = Part(name + "_Dark", "DarkSteel", w)
    dk.box((-2, -0.03, 0), (2, 0, 0.42))                             # kick plate
    for x in (-2.0, 0.0, 2.0):                                       # panel joints (the outer two are half strips)
        dk.box((max(x - 0.015, -2), -0.006, 0.42), (min(x + 0.015, 2), 0, height if not band else 4.42))
    dk.box((-2, -0.006, 2.4), (2, 0, 2.43))
    if band:
        dk.box((-2, -0.05, 4.42), (2, 0, 4.5))                       # the ledge the cove light sits on
        dk.box((-2, -0.02, 4.56), (2, 0, height))                    # upper band
    dk.done()
    if band:
        Part(name + "_Cove", "CoveLight", w).box((-2, -0.04, 4.5), (2, 0, 4.56)).done()
    return w


wall_base("Wall", H)

w = wall_base("WallScreen", H)                                      # a status panel
Part("WallScreen_Box", "DarkSteel", w, 0.008).box((-0.5, -0.07, 1.25), (0.5, 0, 2.05)).done()
Part("WallScreen_Screen", "ScreenCyan", w).box((-0.42, -0.076, 1.5), (0.18, -0.07, 1.97)).done()
Part("WallScreen_Lamp", "StatusOrange", w).box((0.28, -0.076, 1.86), (0.4, -0.07, 1.94)).done()
Part("WallScreen_Keys", "Steel", w).box((-0.42, -0.1, 1.3), (0.4, -0.07, 1.42)).done()

w = wall_base("WallPipes", H)                                       # pipes along the wall, a conduit down to a box
pp = Part("WallPipes_Pipes", "Galvanised", w)
for z, r in ((3.5, 0.05), (3.7, 0.035), (3.86, 0.035)):
    pp.box((-2, -0.02 - 2 * r, z - r), (2, -0.02, z + r))
pp.box((1.1, -0.07, 1.6), (1.16, -0.02, 3.45))
pp.done()
Part("WallPipes_Clamps", "DarkSteel", w).box((-1.0, -0.13, 3.4), (-0.94, 0, 3.94)).box((1.0, -0.13, 3.4), (1.06, 0, 3.94)).done()
Part("WallPipes_Box", "DarkSteel", w, 0.006).box((0.9, -0.1, 1.2), (1.36, 0, 1.6)).done()
Part("WallPipes_Lamp", "SignGreen", w).box((0.96, -0.106, 1.48), (1.04, -0.1, 1.54)).done()

w = wall_base("CWall", HC, band=False)                              # corridor wall: a rail, a light strip
Part("CWall_Rail", "Steel", w).box((-2, -0.05, 0.98), (2, -0.01, 1.04)).done()
Part("CWall_Posts", "DarkSteel", w).box((-1.0, -0.05, 0.42), (-0.96, 0, 1.0)).box((1.0, -0.05, 0.42), (1.04, 0, 1.0)).done()
Part("CWall_Strip", "LightStrip", w).box((-1.6, -0.02, 2.86), (1.6, 0, 2.9)).done()
Part("CWall_StripBack", "DarkSteel", w).box((-1.7, -0.012, 2.8), (1.7, 0, 2.96)).done()

# the doorway: an opening 2.4 x 2.6 m in a room wall, a steel lining through it, finished on the corridor's side too
w = piece("WallDoor")
sl = Part("WallDoor_Slab", "WallPanel", w)
sl.box((-2, 0, 0), (-DW, T, H)).box((DW, 0, 0), (2, T, H)).box((-DW, 0, DH), (DW, T, H))
sl.done()
dk = Part("WallDoor_Dark", "DarkSteel", w)
for sx in (-1, 1):
    dk.box((sx * 2, -0.03, 0), (sx * (DW + 0.14), 0, 0.42))                          # kick plates, both sides
    dk.box((sx * 2, T, 0), (sx * (DW + 0.14), T + 0.03, 0.42))
    dk.box((sx * DW, -0.07, 0), (sx * (DW + 0.14), T + 0.07, DH + 0.14))             # the lining's jambs
dk.box((-DW - 0.14, -0.07, DH), (DW + 0.14, T + 0.07, DH + 0.14))                    # its lintel
dk.box((-2, -0.05, 4.42), (2, 0, 4.5)).box((-2, -0.02, 4.56), (2, 0, H))             # ledge and upper band, the room's side
dk.box((-0.7, -0.09, DH + 0.2), (0.7, -0.07, DH + 0.5))                              # the plate the door's lamp sits on
dk.box((-0.7, T + 0.07, DH + 0.2), (0.7, T + 0.09, DH + 0.5))
dk.done()
Part("WallDoor_Cove", "CoveLight", w).box((-2, -0.04, 4.5), (2, 0, 4.56)).done()
hz = Part("WallDoor_Hazard", "Hazard", w)                                            # stripes up the jambs' faces, both sides
for sx in (-1, 1):
    hz.box((sx * (DW + 0.02), -0.076, 0.02), (sx * (DW + 0.12), -0.07, 1.3))
    hz.box((sx * (DW + 0.02), T + 0.07, 0.02), (sx * (DW + 0.12), T + 0.076, 1.3))
hz.done()
Part("WallDoor_Sill", "Grating", w).box((-DW, -0.07, 0.0), (DW, T + 0.07, 0.006)).done()

# ------------------------------------------------------------------ what stands in the rooms (against a wall: front toward -y)
p = piece("Tank")                                                   # a specimen tank, 1 m across, 2.7 m high
Part("Tank_Base", "DarkSteel", p).cyl(0, 0, 0, 0.36, 0.5).cyl(0, 0, 2.34, 2.62, 0.5).cyl(0, 0, 2.62, 2.7, 0.2).done()
Part("Tank_Liquid", "TankLiquid", p).cyl(0, 0, 0.36, 2.3, 0.42).done()
Part("Tank_Light", "TankLight", p).cyl(0, 0, 2.3, 2.34, 0.4).done()
Part("Tank_Band", "Hazard", p).cyl(0, 0, 0.06, 0.2, 0.506, 24).done()
st = Part("Tank_Struts", "Steel", p)
for a in (30, 150, 270):
    cx, cy = 0.45 * math.cos(math.radians(a)), 0.45 * math.sin(math.radians(a))
    st.box((cx - 0.025, cy - 0.025, 0.36), (cx + 0.025, cy + 0.025, 2.34))
st.done()

p = piece("Console")                                                # a console desk, 1.4 wide, 0.56 deep
Part("Console_Body", "RArmor", p, 0.012).box((-0.7, -0.28, 0.08), (0.7, 0.28, 0.92)).done()
Part("Console_Frame", "RFrame", p, 0.006).box((-0.72, -0.3, 0.0), (0.72, 0.3, 0.08)).box((-0.72, -0.3, 0.92), (0.72, 0.3, 0.98)) \
    .box((-0.66, 0.02, 0.98), (0.66, 0.26, 1.42)).done()
Part("Console_Screens", "ScreenCyan", p).box((-0.6, 0.012, 1.04), (-0.04, 0.02, 1.36)).box((0.04, 0.012, 1.04), (0.6, 0.02, 1.36)).done()
Part("Console_Keys", "Steel", p).box((-0.56, -0.24, 0.98), (0.56, -0.06, 0.995)).done()
Part("Console_Lamp", "StatusOrange", p).box((-0.6, -0.286, 0.6), (-0.44, -0.28, 0.66)).done()

p = piece("Block")                                                  # cover: a barrier, 1.8 wide, 0.5 deep, 1.15 high
Part("Block_Body", "Concrete", p, 0.02).box((-0.9, -0.25, 0.0), (0.9, 0.25, 1.03)).done()
Part("Block_Band", "Hazard", p).box((-0.9, -0.25, 1.03), (0.9, 0.25, 1.15)).done()
Part("Block_Feet", "DarkSteel", p).box((-0.94, -0.29, 0.0), (-0.7, 0.29, 0.08)).box((0.7, -0.29, 0.0), (0.94, 0.29, 0.08)).done()

p = piece("Column")                                                 # a room column, floor to ceiling, 0.8 m square: cover
Part("Column_Shaft", "WallPanel", p).box((-0.4, -0.4, 0.42), (0.4, 0.4, H - 0.5)).done()
cd = Part("Column_Dark", "DarkSteel", p)
cd.box((-0.43, -0.43, 0.0), (0.43, 0.43, 0.42)).box((-0.43, -0.43, H - 0.5), (0.43, 0.43, H))
for sx in (-1, 1):
    for sy in (-1, 1):
        cd.box((sx * 0.4 - 0.015, sy * 0.4 - 0.015, 0.42), (sx * 0.4 + 0.015, sy * 0.4 + 0.015, H - 0.5))      # corner strips
cd.done()
Part("Column_Band", "Hazard", p).box((-0.434, -0.434, 1.0), (0.434, 0.434, 1.12)).done()
cl = Part("Column_Strip", "LightStrip", p)
for sx in (-1, 1):
    cl.box((sx * 0.404 - 0.004, -0.03, 1.6), (sx * 0.404 + 0.004, 0.03, 3.4))
    cl.box((-0.03, sx * 0.404 - 0.004, 1.6), (0.03, sx * 0.404 + 0.004, 3.4))
cl.done()

p = piece("Locker")                                                 # an equipment cabinet, 1.1 wide, 0.5 deep, 2.1 high
Part("Locker_Body", "RArmor", p, 0.01).box((-0.55, -0.25, 0.06), (0.55, 0.25, 2.1)).done()
lk = Part("Locker_Dark", "DarkSteel", p)
lk.box((-0.57, -0.27, 0.0), (0.57, 0.27, 0.06)).box((-0.01, -0.256, 0.1), (0.01, -0.25, 2.06))
for sx in (-1, 1):
    lk.box((sx * 0.08 - 0.015, -0.27, 0.95), (sx * 0.08 + 0.015, -0.25, 1.2))            # handles
    for z in (1.7, 1.78, 1.86):
        lk.box((sx * 0.3 - 0.16, -0.256, z), (sx * 0.3 + 0.16, -0.25, z + 0.03))         # vents
lk.done()
Part("Locker_Lamp", "SignGreen", p).box((0.38, -0.256, 1.98), (0.48, -0.25, 2.03)).done()

for ob in bpy.context.scene.objects:
    ob.select_set(True)
bpy.context.view_layer.objects.active = bpy.context.scene.objects[0]
bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                          export_image_format="NONE", export_materials="EXPORT", export_animations=False)
print("kit:", _slot[0], "pieces,", len(bpy.context.scene.objects), "objects ->", os.path.normpath(OUT))
