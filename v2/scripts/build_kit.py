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
    "RFrame": ((0.03, 0.03, 0.035), 0), "Seam": ((0.06, 0.065, 0.07), 0),
    # the second set of pieces (themes): accents of paint, what is stored, cables
    "PaintBlue": ((0.1, 0.24, 0.5), 0), "PaintOrange": ((0.8, 0.33, 0.05), 0), "PaintGreen": ((0.12, 0.33, 0.2), 0),
    "Cardboard": ((0.5, 0.38, 0.24), 0), "Cable": ((0.02, 0.02, 0.022), 0), "RRed": ((0.5, 0.03, 0.02), 0),
    "RSteel": ((0.62, 0.63, 0.65), 0), "FloorPaint": ((0.75, 0.52, 0.03), 0), "DarkGlass": ((0.02, 0.03, 0.04), 0),
    "RBrass": ((0.75, 0.55, 0.22), 0), "PaintGrey": ((0.5, 0.52, 0.55), 0),
    "CoreGlow": ((0.35, 0.8, 1.0), 2),
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

    def cone(self, cx, cy, z0, z1, r0, r1, seg=16):
        """A vertical cylinder whose radius goes from r0 (bottom) to r1 (top)."""
        n = len(self.verts)
        for z, r in ((z0, r0), (z1, r1)):
            for i in range(seg):
                a = math.tau * i / seg
                self.verts.append((cx + r * math.cos(a), cy + r * math.sin(a), z))
        for i in range(seg):
            j = (i + 1) % seg
            self.faces.append((n + i, n + j, n + seg + j, n + seg + i))
        self.faces.append(tuple(n + i for i in reversed(range(seg))))
        self.faces.append(tuple(n + seg + i for i in range(seg)))
        return self

    def tube(self, p0, p1, r, seg=12):
        """A cylinder of radius r from p0 to p1, in any direction."""
        ax = [p1[i] - p0[i] for i in range(3)]
        ln = math.sqrt(sum(c * c for c in ax))
        ax = [c / ln for c in ax]
        ref = (0.0, 0.0, 1.0) if abs(ax[2]) < 0.9 else (1.0, 0.0, 0.0)
        u = [ax[1] * ref[2] - ax[2] * ref[1], ax[2] * ref[0] - ax[0] * ref[2], ax[0] * ref[1] - ax[1] * ref[0]]
        un = math.sqrt(sum(c * c for c in u))
        u = [c / un for c in u]
        v = [ax[1] * u[2] - ax[2] * u[1], ax[2] * u[0] - ax[0] * u[2], ax[0] * u[1] - ax[1] * u[0]]
        n = len(self.verts)
        for p in (p0, p1):
            for i in range(seg):
                a = math.tau * i / seg
                self.verts.append(tuple(p[k] + r * (math.cos(a) * u[k] + math.sin(a) * v[k]) for k in range(3)))
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
# the joints of the 2 m tiles: 3.6 cm of dull dark grey (2.4 cm of near-black steel was a line thinner than a
# pixel a few rooms away, and crawled as the player walked)
seam = Part("Floor_Seams", "Seam", p)
for v in (-2.0, 0.0):
    seam.box((v - 0.018, -2, 0.0), (v + 0.018, 2, 0.004)).box((-2, v - 0.018, 0.0), (2, v + 0.018, 0.004))
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
LIN = 0.03
w = piece("WallDoor")
sl = Part("WallDoor_Slab", "WallPanel", w)
sl.box((-2, 0, 0), (-DW, T, H)).box((DW, 0, 0), (2, T, H)).box((-DW, 0, DH), (DW, T, H))
sl.done()
dk = Part("WallDoor_Dark", "DarkSteel", w)
for sx in (-1, 1):
    dk.box((sx * 2, -0.03, 0), (sx * (DW + 0.14), 0, 0.42))                          # kick plates, both sides
    dk.box((sx * 2, T, 0), (sx * (DW + 0.14), T + 0.03, 0.42))
    # the lining's jambs and lintel stand LIN proud of the opening's faces: flush with them, the dark lining and
    # the white slab behind it lay in one plane and fought for the pixels (the doorways flickered)
    dk.box((sx * (DW - LIN), -0.07, 0), (sx * (DW + 0.14), T + 0.07, DH + 0.14))
dk.box((-DW - 0.14, -0.07, DH - LIN), (DW + 0.14, T + 0.07, DH + 0.14))
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
# the threshold: a steel plate that stands clear above the corridor's grating (0.006) and its edge strips (0.01);
# level with the grating, it flickered against it
Part("WallDoor_Sill", "DarkSteel", w, 0.004).box((-DW + LIN, -0.09, 0.0), (DW - LIN, T + 0.09, 0.018)).done()
Part("WallDoor_SillGrip", "Galvanised", w).box((-DW + 0.12, -0.03, 0.018), (DW - 0.12, T + 0.03, 0.022)).done()

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


# ====================================================================== the second set: variety (room themes)
# Flat things on the floor lie between 0.008 and 0.012: clear of the tiles' joints (top at 0.004). Nothing lies in
# the same plane as anything else of another material (that flickers). Wall pieces reach 0.12 m into the cell at most.

# ------------------------------------------------------------------ more room walls
w = wall_base("WallVent", H)                                        # a ventilation grille high up, a warning plate
Part("WallVent_Frame", "DarkSteel", w, 0.006).box((-0.9, -0.06, 2.75), (0.9, 0, 3.75)).done()
lv = Part("WallVent_Louvres", "PaintGrey", w)
for i in range(8):
    lv.box((-0.82, -0.085, 2.83 + i * 0.11), (0.82, -0.06, 2.88 + i * 0.11))
lv.done()
Part("WallVent_Plate", "Hazard", w).box((-0.35, -0.016, 1.5), (0.35, -0.01, 1.64)).done()

w = wall_base("WallCables", H)                                      # cable runs, drops to a junction box
cb = Part("WallCables_Cables", "Cable", w)
for z in (2.62, 2.71, 2.8):
    cb.box((-2, -0.055, z), (2, -0.02, z + 0.05))
cb.box((-1.26, -0.05, 1.7), (-1.21, -0.02, 2.62)).box((-1.14, -0.05, 1.7), (-1.09, -0.02, 2.71))
cb.done()
cl = Part("WallCables_Clips", "PaintGrey", w)
for x in (-1.7, -0.3, 1.2):
    cl.box((x - 0.03, -0.065, 2.58), (x + 0.03, 0, 2.89))
cl.done()
Part("WallCables_Box", "DarkSteel", w, 0.006).box((-1.42, -0.1, 1.1), (-0.94, 0, 1.7)).done()
Part("WallCables_Lamp", "SignGreen", w).box((-1.36, -0.106, 1.56), (-1.3, -0.1, 1.62)).done()
Part("WallCables_Lamp2", "StatusOrange", w).box((-1.26, -0.106, 1.56), (-1.2, -0.1, 1.62)).done()

w = wall_base("WallWindow", H)                                      # an observation window, dark behind
Part("WallWindow_Frame", "DarkSteel", w, 0.008).box((-1.5, -0.07, 1.15), (1.5, 0, 2.35)).done()
Part("WallWindow_Glass", "DarkGlass", w).box((-1.4, -0.078, 1.25), (1.4, -0.072, 2.25)).done()
Part("WallWindow_Bars", "Steel", w).box((-0.48, -0.09, 1.25), (-0.44, -0.08, 2.25)).box((0.44, -0.09, 1.25), (0.48, -0.08, 2.25)).done()
Part("WallWindow_Sill", "PaintGrey", w).box((-1.5, -0.11, 1.09), (1.5, 0, 1.15)).done()
Part("WallWindow_Read", "ScreenCyan", w).box((-1.3, -0.0785, 1.3), (-0.95, -0.0782, 1.36)).box((-1.3, -0.0785, 1.4), (-1.1, -0.0782, 1.44)).done()

w = wall_base("WallStripe", H)                                      # a painted band, a sign plate with a code of bars
Part("WallStripe_Band", "FloorPaint", w).box((-2, -0.014, 0.98), (2, -0.008, 1.2)).done()
Part("WallStripe_Sign", "DarkSteel", w, 0.004).box((0.45, -0.03, 2.6), (1.55, 0, 3.3)).done()
sg = Part("WallStripe_Code", "RArmor", w)
for k, wd in enumerate((0.34, 0.2, 0.28)):
    sg.box((0.56, -0.036, 3.1 - k * 0.17), (0.56 + wd, -0.03, 3.2 - k * 0.17))
sg.box((1.14, -0.036, 2.72), (1.44, -0.03, 3.2))
sg.done()

w = wall_base("WallPanels", H)                                      # two access hatches
ht = Part("WallPanels_Hatch", "PaintGrey", w, 0.006)
ht.box((-1.6, -0.04, 0.6), (-0.5, 0, 2.2)).box((0.5, -0.04, 0.6), (1.6, 0, 2.2))
ht.done()
hd = Part("WallPanels_Dark", "DarkSteel", w)
for sx in (-1, 1):
    hd.box((sx * 0.6 - 0.03, -0.075, 1.25), (sx * 0.6 + 0.03, -0.04, 1.6))                # handles
    for z in (0.75, 2.0):
        hd.box((sx * 1.56 - 0.03, -0.055, z), (sx * 1.56 + 0.03, -0.04, z + 0.14))        # hinges
hd.done()
hz = Part("WallPanels_Hazard", "Hazard", w)
for sx in (-1, 1):
    hz.box((sx * 1.05 - 0.5, -0.046, 0.64), (sx * 1.05 + 0.5, -0.04, 0.76))
hz.done()
Part("WallPanels_Lamp", "StatusOrange", w).box((-0.05, -0.012, 1.9), (0.05, -0.006, 2.0)).done()

w = wall_base("WallPilaster", H)                                    # a buttress with a light strip up it
Part("WallPilaster_Body", "WallPanel", w).box((-0.3, -0.12, 0.42), (0.3, 0, 4.42)).done()
Part("WallPilaster_Dark", "DarkSteel", w).box((-0.33, -0.12, 0.0), (0.33, -0.03, 0.42)).box((-0.33, -0.12, 4.42), (0.33, -0.05, 4.5)).done()
Part("WallPilaster_Strip", "LightStrip", w).box((-0.03, -0.126, 1.4), (0.03, -0.12, 3.6)).done()

w = wall_base("WallValves", H)                                      # low pipes with valves, a gauge
vp = Part("WallValves_Pipes", "PaintGrey", w)
vp.tube((-2, -0.07, 0.74), (2, -0.07, 0.74), 0.045).tube((-2, -0.065, 0.93), (2, -0.065, 0.93), 0.032)
vp.done()
vb = Part("WallValves_Brackets", "DarkSteel", w)
for x in (-1.5, 0.2, 1.6):
    vb.box((x - 0.03, -0.12, 0.42), (x + 0.03, 0, 1.0))
vb.box((1.08, -0.09, 1.2), (1.36, 0, 1.46))
vb.done()
Part("WallValves_Wheels", "RRed", w).tube((-0.6, -0.12, 0.74), (-0.6, -0.105, 0.74), 0.09, 10) \
    .tube((0.9, -0.105, 0.93), (0.9, -0.09, 0.93), 0.07, 10).done()
Part("WallValves_Dial", "RArmor", w).tube((1.22, -0.096, 1.33), (1.22, -0.09, 1.33), 0.09, 14).done()

# ------------------------------------------------------------------ more corridor walls (each keeps the light strip)
def cwall(name):
    w = wall_base(name, HC, band=False)
    Part(name + "_Strip", "LightStrip", w).box((-1.6, -0.02, 2.86), (1.6, 0, 2.9)).done()
    Part(name + "_StripBack", "DarkSteel", w).box((-1.7, -0.012, 2.8), (1.7, 0, 2.96)).done()
    return w


w = cwall("CWallPipes")
Part("CWallPipes_Pipes", "PaintGrey", w).tube((-2, -0.07, 2.3), (2, -0.07, 2.3), 0.045).tube((-2, -0.06, 2.48), (2, -0.06, 2.48), 0.03).done()
cbk = Part("CWallPipes_Brackets", "DarkSteel", w)
for x in (-1.3, 0.0, 1.3):
    cbk.box((x - 0.025, -0.12, 2.2), (x + 0.025, 0, 2.56))
cbk.done()
Part("CWallPipes_Band", "Hazard", w).box((-2, -0.014, 0.98), (2, -0.008, 1.1)).done()

w = cwall("CWallPanel")
Part("CWallPanel_Hatch", "PaintGrey", w, 0.006).box((-0.7, -0.04, 0.6), (0.7, 0, 2.1)).done()
Part("CWallPanel_Dark", "DarkSteel", w).box((0.5, -0.075, 1.2), (0.56, -0.04, 1.5)).box((-0.66, -0.055, 0.75), (-0.6, -0.04, 0.9)) \
    .box((-0.66, -0.055, 1.85), (-0.6, -0.04, 2.0)).done()
Part("CWallPanel_Hazard", "Hazard", w).box((-0.64, -0.046, 0.64), (0.64, -0.04, 0.74)).done()
Part("CWallPanel_Lamp", "StatusOrange", w).box((-1.2, -0.012, 1.5), (-1.1, -0.006, 1.6)).done()

w = cwall("CWallVent")
Part("CWallVent_Frame", "DarkSteel", w, 0.006).box((-1.1, -0.06, 0.55), (1.1, 0, 1.25)).done()
lv = Part("CWallVent_Louvres", "PaintGrey", w)
for i in range(5):
    lv.box((-1.02, -0.085, 0.62 + i * 0.12), (1.02, -0.06, 0.67 + i * 0.12))
lv.done()
Part("CWallVent_Rail", "Steel", w).box((-2, -0.05, 1.5), (2, -0.01, 1.56)).done()


# ------------------------------------------------------------------ more floors
def floor_base(name):
    p = piece(name)
    Part(name + "_Slab", "FloorTile", p).box((-2, -2, -0.2), (2, 2, 0)).done()
    seam = Part(name + "_Seams", "Seam", p)
    for v in (-2.0, 0.0):
        seam.box((v - 0.018, -2, 0.0), (v + 0.018, 2, 0.004)).box((-2, v - 0.018, 0.0), (2, v + 0.018, 0.004))
    seam.done()
    return p


p = floor_base("FloorHazard")                                       # a striped frame (in front of doors, round the exit)
fh = Part("FloorHazard_Frame", "Hazard", p)
fh.box((-1.7, -1.7, 0.008), (1.7, -1.52, 0.012)).box((-1.7, 1.52, 0.008), (1.7, 1.7, 0.012))
fh.box((-1.7, -1.52, 0.008), (-1.52, 1.52, 0.012)).box((1.52, -1.52, 0.008), (1.7, 1.52, 0.012))
fh.done()

p = floor_base("FloorPlates")                                       # inspection plates let into two of the four tiles
Part("FloorPlates_Grating", "Grating", p).box((-1.6, -1.6, 0.008), (-0.4, -0.4, 0.012)).done()
fp = Part("FloorPlates_Frame", "DarkSteel", p)
fp.box((-1.66, -1.66, 0.008), (-0.34, -1.6, 0.016)).box((-1.66, -0.4, 0.008), (-0.34, -0.34, 0.016))
fp.box((-1.66, -1.6, 0.008), (-1.6, -0.4, 0.016)).box((-0.4, -1.6, 0.008), (-0.34, -0.4, 0.016))
fp.done()
Part("FloorPlates_Plate", "PaintGrey", p, 0.003).box((0.5, 0.5, 0.008), (1.5, 1.5, 0.016)).done()
Part("FloorPlates_Bolts", "DarkSteel", p).box((0.56, 0.56, 0.016), (0.62, 0.62, 0.02)).box((1.38, 0.56, 0.016), (1.44, 0.62, 0.02)) \
    .box((0.56, 1.38, 0.016), (0.62, 1.44, 0.02)).box((1.38, 1.38, 0.016), (1.44, 1.44, 0.02)).done()

p = floor_base("FloorLines")                                        # painted lane lines
Part("FloorLines_Paint", "FloorPaint", p).box((-1.36, -2, 0.008), (-1.24, 2, 0.011)).box((1.24, -2, 0.008), (1.36, 2, 0.011)).done()

p = floor_base("FloorDrain")                                        # a drain in one tile
Part("FloorDrain_Grate", "Grating", p).box((0.75, 0.75, 0.008), (1.25, 1.25, 0.012)).done()
fd = Part("FloorDrain_Frame", "DarkSteel", p)
fd.box((0.7, 0.7, 0.008), (1.3, 0.75, 0.016)).box((0.7, 1.25, 0.008), (1.3, 1.3, 0.016))
fd.box((0.7, 0.75, 0.008), (0.75, 1.25, 0.016)).box((1.25, 0.75, 0.008), (1.3, 1.25, 0.016))
fd.done()

# ------------------------------------------------------------------ more ceilings (the cells between the lights)
p = piece("CeilingDuct")                                            # a ventilation duct, down from the slab and back up
Part("CeilingDuct_Slab", "Concrete", p).box((-2, -2, H), (2, 2, H + 0.2)).done()
dc = Part("CeilingDuct_Duct", "PaintGrey", p, 0.01)
dc.box((-1.5, -1.6, H - 0.56), (-0.8, 1.6, H - 0.14)).box((-1.45, -1.6, H - 0.14), (-0.85, -1.05, H)).box((-1.45, 1.05, H - 0.14), (-0.85, 1.6, H))
dc.done()
dd = Part("CeilingDuct_Dark", "DarkSteel", p)
dd.box((-1.36, -0.45, H - 0.59), (-0.94, 0.45, H - 0.56))                                 # the outlet
for y in (-0.6, 0.6):
    dd.box((-1.54, y - 0.02, H - 0.6), (-1.5, y + 0.02, H)).box((-0.8, y - 0.02, H - 0.6), (-0.76, y + 0.02, H))
    dd.box((-1.54, y - 0.02, H - 0.62), (-0.76, y + 0.02, H - 0.58))
dd.done()
Part("CeilingDuct_Beams", "DarkSteel", p).box((0.6, -2, H - 0.14), (0.78, 2, H)).done()

p = piece("CeilingPipes")                                           # pipes along the cell, up into the slab at both ends
Part("CeilingPipes_Slab", "Concrete", p).box((-2, -2, H), (2, 2, H + 0.2)).done()
cp = Part("CeilingPipes_Pipes", "PaintGrey", p)
for y, r in ((-1.25, 0.08), (-1.0, 0.05), (-0.82, 0.05)):
    cp.tube((-1.7, y, H - 0.3), (1.7, y, H - 0.3), r).tube((-1.7, y, H - 0.3), (-1.7, y, H), r).tube((1.7, y, H - 0.3), (1.7, y, H), r)
cp.done()
ch = Part("CeilingPipes_Hangers", "DarkSteel", p)
for x in (-0.9, 0.9):
    ch.box((x - 0.025, -1.4, H - 0.42), (x + 0.025, -0.7, H - 0.39)).box((x - 0.02, -1.4, H - 0.42), (x + 0.02, -1.36, H)) \
        .box((x - 0.02, -0.74, H - 0.42), (x + 0.02, -0.7, H))
ch.box((-2, 0.9, H - 0.14), (2, 1.08, H))
ch.done()
Part("CeilingPipes_Band", "Hazard", p).tube((-0.3, -1.25, H - 0.3), (0.3, -1.25, H - 0.3), 0.084).done()

p = piece("CeilingVent")                                            # a square extraction unit
Part("CeilingVent_Slab", "Concrete", p).box((-2, -2, H), (2, 2, H + 0.2)).done()
Part("CeilingVent_Housing", "DarkSteel", p, 0.01).box((-0.9, -0.9, H - 0.24), (0.9, 0.9, H)).done()
vl = Part("CeilingVent_Louvres", "PaintGrey", p)
for i in range(7):
    vl.box((-0.78, -0.72 + i * 0.22, H - 0.27), (0.78, -0.62 + i * 0.22, H - 0.24))
vl.done()
Part("CeilingVent_Lamp", "StatusOrange", p).box((0.74, 0.74, H - 0.25), (0.84, 0.84, H - 0.24)).done()
Part("CeilingVent_Beams", "DarkSteel", p).box((-2, -1.5, H - 0.12), (2, -1.36, H)).box((-2, 1.36, H - 0.12), (2, 1.5, H)).done()

p = piece("CCeilingDuct")                                           # corridor: the light strip, and a duct down one side
Part("CCeilingDuct_Slab", "Concrete", p).box((-2, -2, HC), (2, 2, HC + 0.2)).done()
Part("CCeilingDuct_Light", "CeilingLight", p).box((-0.16, -1.3, HC - 0.03), (0.16, 1.3, HC - 0.005)).done()
Part("CCeilingDuct_Frame", "DarkSteel", p).box((-0.22, -1.36, HC - 0.05), (-0.16, 1.36, HC)).box((0.16, -1.36, HC - 0.05), (0.22, 1.36, HC)) \
    .box((-1.5, -2, HC - 0.12), (-1.3, 2, HC)).done()
Part("CCeilingDuct_Duct", "PaintGrey", p, 0.008).box((1.1, -2, HC - 0.34), (1.62, 2, HC - 0.04)).done()
Part("CCeilingDuct_Straps", "DarkSteel", p).box((1.08, -1.02, HC - 0.36), (1.64, -0.98, HC)).box((1.08, 0.98, HC - 0.36), (1.64, 1.02, HC)).done()


# ------------------------------------------------------------------ more of what stands in the rooms
def crate(body, frame, x0, y0, z0, x1, y1, z1):
    """A plain equipment crate: shell, a rim round the foot and the top."""
    body.box((x0 + 0.015, y0 + 0.015, z0 + 0.03), (x1 - 0.015, y1 - 0.015, z1 - 0.03))
    frame.box((x0, y0, z0), (x1, y1, z0 + 0.05)).box((x0, y0, z1 - 0.05), (x1, y1, z1))


p = piece("CrateStack")                                             # crates stacked: 1.4 x 1.4, 1.5 high (cover)
cb_, cf_ = Part("CrateStack_Body", "RArmor", p, 0.01), Part("CrateStack_Frame", "RFrame", p, 0.006)
crate(cb_, cf_, -0.7, -0.7, 0.0, 0.3, 0.3, 0.85)
crate(cb_, cf_, -0.58, -0.58, 0.85, 0.12, 0.12, 1.5)
crate(cb_, cf_, 0.34, -0.66, 0.0, 0.7, 0.2, 0.55)
crate(cb_, cf_, -0.66, 0.34, 0.0, 0.1, 0.7, 0.45)
cb_.done()
cf_.done()
Part("CrateStack_Band", "Hazard", p).box((-0.704, -0.704, 0.36), (0.304, 0.304, 0.5)).done()
Part("CrateStack_Label", "StatusOrange", p).box((-0.4, -0.586, 1.2), (-0.1, -0.58, 1.3)).done()

p = piece("Barrels")                                                # three drums: 1.3 x 1.2, 0.9 high (cover)
DRUMS = ((-0.33, -0.28, "PaintBlue"), (0.33, -0.22, "PaintGrey"), (0.02, 0.32, "PaintOrange"))
for i, (cx, cy, mat) in enumerate(DRUMS):
    Part("Barrels_Drum%d" % i, mat, p).cyl(cx, cy, 0.02, 0.88, 0.29, 20).done()
br_ = Part("Barrels_Rims", "DarkSteel", p)
for cx, cy, _m in DRUMS:
    for z in (0.0, 0.3, 0.6, 0.86):
        br_.cyl(cx, cy, z, z + 0.04, 0.3, 20)
    br_.cyl(cx + 0.14, cy, 0.9, 0.93, 0.045, 10)
br_.done()
Part("Barrels_Band", "Hazard", p).cyl(0.33, -0.22, 0.4, 0.54, 0.294, 20).done()

p = piece("Pallet")                                                 # boxes on a pallet: 1.2 x 1.0, 1.0 high
pl_ = Part("Pallet_Wood", "Cardboard", p)
for y in (-0.45, 0.0, 0.45):
    pl_.box((-0.6, y - 0.05, 0.0), (0.6, y + 0.05, 0.1))
pl_.box((-0.6, -0.5, 0.1), (0.6, 0.5, 0.14))
pl_.done()
pbx = Part("Pallet_Boxes", "RArmor", p, 0.008)
pbx.box((-0.56, -0.46, 0.14), (-0.02, 0.0, 0.58)).box((0.02, -0.46, 0.14), (0.56, 0.0, 0.58))
pbx.box((-0.56, 0.02, 0.14), (0.0, 0.46, 0.58)).box((0.04, 0.02, 0.14), (0.56, 0.46, 0.5)).box((-0.4, -0.3, 0.58), (0.2, 0.2, 1.0))
pbx.done()
Part("Pallet_Straps", "DarkSteel", p).box((-0.57, -0.24, 0.14), (0.57, -0.2, 0.585)).box((-0.57, 0.22, 0.14), (0.57, 0.26, 0.585)).done()
Part("Pallet_Label", "PaintBlue", p).box((-0.3, -0.306, 0.7), (0.1, -0.3, 0.9)).done()

p = piece("Barrier")                                                # a steel barricade: 1.8 wide, 0.5 deep, 1.1 high (cover)
Part("Barrier_Panel", "RArmor", p, 0.01).box((-0.9, -0.05, 0.14), (0.9, 0.05, 1.0)).done()
bf_ = Part("Barrier_Frame", "RFrame", p, 0.006)
bf_.box((-0.92, -0.07, 1.0), (0.92, 0.07, 1.1)).box((-0.92, -0.07, 0.1), (0.92, 0.07, 0.16))
for sx in (-1, 1):
    bf_.box((sx * 0.7 - 0.05, -0.25, 0.0), (sx * 0.7 + 0.05, 0.25, 0.1)).box((sx * 0.7 - 0.03, -0.2, 0.1), (sx * 0.7 + 0.03, 0.2, 0.4))
bf_.done()
Part("Barrier_Hazard", "Hazard", p).box((-0.86, -0.056, 0.52), (0.86, 0.056, 0.72)).done()
Part("Barrier_Lamps", "StatusOrange", p).box((-0.8, -0.03, 1.1), (-0.66, 0.03, 1.15)).box((0.66, -0.03, 1.1), (0.8, 0.03, 1.15)).done()


def rack(prefix, parent, x0):
    """A server rack 0.7 wide (x0 .. x0 + 0.7), 0.9 deep, 2.15 high, front toward -y."""
    Part(prefix + "_Body", "RFrame", parent, 0.008).box((x0, -0.45, 0.05), (x0 + 0.7, 0.45, 2.15)).done()
    Part(prefix + "_Base", "DarkSteel", parent).box((x0 - 0.01, -0.46, 0.0), (x0 + 0.71, 0.46, 0.05)).done()
    Part(prefix + "_Door", "DarkGlass", parent).box((x0 + 0.06, -0.462, 0.2), (x0 + 0.64, -0.456, 2.0)).done()
    Part(prefix + "_Units", "Steel", parent).box((x0 + 0.1, -0.455, 0.3), (x0 + 0.6, -0.451, 1.9)).done()
    g, c = Part(prefix + "_Green", "SignGreen", parent), Part(prefix + "_Cyan", "ScreenCyan", parent)
    for i in range(9):
        z = 0.38 + i * 0.17
        g.box((x0 + 0.14, -0.468, z), (x0 + 0.17, -0.463, z + 0.03)).box((x0 + 0.2, -0.468, z), (x0 + 0.23, -0.463, z + 0.03))
        if i % 3 != 1:
            c.box((x0 + 0.32, -0.468, z), (x0 + 0.52, -0.463, z + 0.025))
    g.done()
    c.done()
    Part(prefix + "_Top", "PaintGrey", parent).box((x0 + 0.1, -0.3, 2.15), (x0 + 0.6, 0.3, 2.19)).done()


p = piece("ServerRack")                                             # one rack against a wall
rack("ServerRack", p, -0.35)
p = piece("RackPair")                                               # two side by side: 1.4 x 0.9, 2.2 high (cover)
rack("RackPairA", p, -0.7)
rack("RackPairB", p, 0.0)

p = piece("Generator")                                              # a generator set: 1.7 wide, 0.8 deep, 1.35 high
Part("Generator_Body", "RArmor", p, 0.012).box((-0.85, -0.38, 0.14), (0.85, 0.38, 1.3)).done()
gf = Part("Generator_Frame", "DarkSteel", p, 0.006)
gf.box((-0.88, -0.4, 0.0), (0.88, -0.28, 0.14)).box((-0.88, 0.28, 0.0), (0.88, 0.4, 0.14)).box((-0.88, -0.4, 1.3), (0.88, 0.4, 1.35))
gf.box((0.3, -0.4, 0.5), (0.8, -0.38, 1.15))
gf.done()
gl = Part("Generator_Louvres", "PaintGrey", p)
for i in range(6):
    gl.box((-0.75, -0.4, 0.4 + i * 0.13), (0.15, -0.38, 0.46 + i * 0.13))
gl.done()
Part("Generator_Exhaust", "PaintGrey", p).tube((-0.55, 0.15, 1.35), (-0.55, 0.15, 2.3), 0.07).tube((-0.55, 0.15, 2.3), (-0.55, 0.4, 2.3), 0.07).done()
Part("Generator_Screen", "ScreenCyan", p).box((0.36, -0.406, 0.88), (0.66, -0.4, 1.06)).done()
Part("Generator_Lamp", "StatusOrange", p).box((0.36, -0.406, 0.62), (0.44, -0.4, 0.7)).done()
Part("Generator_Button", "RRed", p).box((0.56, -0.416, 0.6), (0.66, -0.4, 0.7)).done()
Part("Generator_Band", "Hazard", p).box((-0.854, -0.384, 0.16), (0.854, 0.384, 0.28)).done()

p = piece("Shelf")                                                  # shelving with stores: 1.9 wide, 0.5 deep, 2.05 high
sh = Part("Shelf_Frame", "PaintGrey", p)
for sx in (-1, 1):
    for sy in (-1, 1):
        sh.box((sx * 0.93 - 0.025, sy * 0.23 - 0.025, 0.0), (sx * 0.93 + 0.025, sy * 0.23 + 0.025, 2.05))
for z in (0.12, 0.72, 1.32, 1.92):
    sh.box((-0.95, -0.25, z), (0.95, 0.25, z + 0.035))
sh.done()
sb = Part("Shelf_Boxes", "RArmor", p, 0.008)
sb.box((-0.85, -0.2, 0.155), (-0.25, 0.2, 0.55)).box((0.1, -0.2, 0.155), (0.8, 0.2, 0.48)).box((-0.8, -0.2, 0.755), (-0.4, 0.2, 1.1))
sb.box((0.3, -0.2, 1.355), (0.85, 0.2, 1.7))
sb.done()
Part("Shelf_Card", "Cardboard", p, 0.006).box((-0.3, -0.18, 0.755), (0.2, 0.18, 1.15)).box((-0.8, -0.18, 1.355), (-0.3, 0.18, 1.62)) \
    .box((-0.2, -0.18, 1.355), (0.2, 0.18, 1.55)).done()
Part("Shelf_Cans", "PaintBlue", p).cyl(0.45, 0.0, 0.755, 1.15, 0.11, 14).cyl(0.7, -0.05, 0.755, 1.15, 0.11, 14).done()
Part("Shelf_Cans2", "PaintOrange", p).cyl(-0.6, 0.0, 1.955, 2.3, 0.1, 14).done()
Part("Shelf_Caps", "DarkSteel", p).cyl(0.45, 0.0, 1.15, 1.19, 0.05, 10).cyl(0.7, -0.05, 1.15, 1.19, 0.05, 10).cyl(-0.6, 0.0, 2.3, 2.34, 0.05, 10).done()

p = piece("Workbench")                                              # a bench with a tool board: 1.9 wide, 0.65 deep, 1.75 high
Part("Workbench_Top", "PaintGrey", p, 0.006).box((-0.95, -0.32, 0.88), (0.95, 0.32, 0.94)).done()
wb = Part("Workbench_Dark", "DarkSteel", p)
for sx in (-1, 1):
    wb.box((sx * 0.9 - 0.04, -0.28, 0.0), (sx * 0.9 + 0.04, 0.28, 0.88))
wb.box((-0.95, 0.27, 0.94), (0.95, 0.32, 1.75)).box((-0.86, -0.26, 0.2), (0.86, 0.26, 0.24))
wb.box((0.55, -0.2, 0.94), (0.8, 0.0, 1.1))                                               # the vice
wb.done()
Part("Workbench_Drawers", "RArmor", p, 0.008).box((-0.82, -0.3, 0.42), (-0.2, 0.26, 0.86)).done()
wt = Part("Workbench_Tools", "PaintGrey", p)
for k, (x, hgt) in enumerate(((-0.75, 0.35), (-0.6, 0.28), (-0.45, 0.4), (-0.3, 0.22), (0.1, 0.3), (0.25, 0.36))):
    wt.box((x - 0.02, 0.255, 1.55 - hgt), (x + 0.02, 0.27, 1.55))
wt.box((-0.76, -0.31, 0.6), (-0.26, -0.3, 0.63)).box((-0.76, -0.31, 0.75), (-0.26, -0.3, 0.78))
wt.done()
Part("Workbench_Lamp", "LightStrip", p).box((-0.5, 0.1, 1.62), (0.5, 0.2, 1.64)).done()
Part("Workbench_LampArm", "DarkSteel", p).box((-0.52, 0.08, 1.64), (0.52, 0.27, 1.68)).done()
Part("Workbench_Box", "RRed", p, 0.006).box((-0.1, -0.2, 0.94), (0.35, 0.02, 1.12)).done()
Part("Workbench_Parts", "RBrass", p).cyl(-0.4, -0.1, 0.94, 1.0, 0.05, 10).cyl(-0.52, -0.02, 0.94, 0.98, 0.04, 10).done()

p = piece("Cabinet")                                                # a tool cabinet: 1.0 wide, 0.5 deep, 1.25 high
Part("Cabinet_Body", "RArmor", p, 0.01).box((-0.5, -0.25, 0.08), (0.5, 0.25, 1.2)).done()
cbd = Part("Cabinet_Dark", "DarkSteel", p)
cbd.box((-0.52, -0.27, 0.0), (0.52, 0.27, 0.08)).box((-0.52, -0.27, 1.2), (0.52, 0.27, 1.25))
for z in (0.36, 0.62, 0.88):
    cbd.box((-0.46, -0.256, z), (0.46, -0.25, z + 0.015)).box((-0.12, -0.275, z + 0.1), (0.12, -0.25, z + 0.13))
cbd.done()
Part("Cabinet_Band", "Hazard", p).box((-0.504, -0.254, 1.08), (0.504, 0.254, 1.16)).done()
Part("Cabinet_Case", "PaintBlue", p, 0.006).box((-0.3, -0.14, 1.25), (0.2, 0.12, 1.43)).done()

p = piece("ChargeDock")                                             # a charging dock: 1.3 wide, 0.6 deep, 2.3 high
Part("ChargeDock_Base", "DarkSteel", p, 0.008).box((-0.65, -0.3, 0.0), (0.65, 0.3, 0.1)).done()
Part("ChargeDock_Pad", "ScreenCyan", p).box((-0.4, -0.22, 0.1), (0.4, -0.16, 0.106)).box((-0.4, 0.04, 0.1), (0.4, 0.1, 0.106)).done()
dkp = Part("ChargeDock_Posts", "RArmor", p, 0.01)
for sx in (-1, 1):
    dkp.box((sx * 0.56 - 0.07, 0.12, 0.1), (sx * 0.56 + 0.07, 0.28, 2.2))
dkp.box((-0.63, 0.12, 2.1), (0.63, 0.28, 2.3))
dkp.done()
dka = Part("ChargeDock_Arms", "PaintGrey", p)
for sx in (-1, 1):
    dka.box((sx * 0.5 - 0.03, -0.2, 1.3), (sx * 0.5 + 0.03, 0.14, 1.36)).box((sx * 0.5 - 0.06, -0.26, 1.24), (sx * 0.5 + 0.06, -0.2, 1.42))
dka.done()
Part("ChargeDock_Cable", "Cable", p).tube((0.56, 0.2, 2.3), (0.56, 0.2, 2.7), 0.03).tube((0.56, 0.2, 2.7), (0.56, 0.32, 2.7), 0.03).done()
Part("ChargeDock_Lamp", "SignGreen", p).box((-0.2, 0.114, 2.16), (0.2, 0.12, 2.22)).done()
Part("ChargeDock_Strip", "ScreenCyan", p).box((-0.565, 0.114, 0.5), (-0.555, 0.12, 1.9)).box((0.555, 0.114, 0.5), (0.565, 0.12, 1.9)).done()

p = piece("PipeRiser")                                              # pipes up the wall, floor to ceiling: 0.8 wide, 0.34 deep
pr = Part("PipeRiser_Pipes", "PaintGrey", p)
pr.tube((-0.18, 0.02, 0.0), (-0.18, 0.02, H), 0.12, 16).tube((0.2, 0.06, 0.0), (0.2, 0.06, H), 0.07, 14)
pr.done()
prd = Part("PipeRiser_Dark", "DarkSteel", p)
for z in (1.25, 3.4):
    prd.cyl(-0.18, 0.02, z, z + 0.06, 0.16, 16).cyl(0.2, 0.06, z + 0.3, z + 0.35, 0.1, 14)
for z in (0.5, 2.4, 4.3):
    prd.box((-0.38, 0.1, z), (0.36, 0.17, z + 0.06))
prd.box((0.08, -0.12, 1.5), (0.34, -0.02, 1.76))
prd.done()
Part("PipeRiser_Wheel", "RRed", p).tube((-0.18, -0.16, 1.05), (-0.18, -0.13, 1.05), 0.12, 12).done()
Part("PipeRiser_Stem", "Steel", p).tube((-0.18, -0.13, 1.05), (-0.18, -0.08, 1.05), 0.02, 8).done()
Part("PipeRiser_Dial", "RArmor", p).tube((0.21, -0.126, 1.63), (0.21, -0.12, 1.63), 0.09, 14).done()
Part("PipeRiser_Band", "Hazard", p).cyl(-0.18, 0.02, 1.9, 2.1, 0.124, 16).done()

p = piece("CoreUnit")                                               # a power core in a cage: 1.3 across, 2.9 high (cover)
Part("CoreUnit_Base", "DarkSteel", p).cyl(0, 0, 0.0, 0.42, 0.64, 8).cyl(0, 0, 2.2, 2.56, 0.58, 8).cyl(0, 0, 2.56, 2.9, 0.22, 12).done()
Part("CoreUnit_Core", "CoreGlow", p).cyl(0, 0, 0.62, 2.0, 0.2, 20).done()
Part("CoreUnit_Coils", "DarkSteel", p).cyl(0, 0, 0.8, 0.92, 0.25, 20).cyl(0, 0, 1.62, 1.74, 0.25, 20).done()
Part("CoreUnit_Rings", "PaintGrey", p).cyl(0, 0, 0.42, 0.62, 0.36, 20).cyl(0, 0, 2.0, 2.2, 0.36, 20).cyl(0, 0, 1.24, 1.36, 0.3, 20).done()
cs = Part("CoreUnit_Struts", "PaintGrey", p)
for a in range(0, 360, 60):
    cx, cy = 0.5 * math.cos(math.radians(a)), 0.5 * math.sin(math.radians(a))
    cs.box((cx - 0.03, cy - 0.03, 0.42), (cx + 0.03, cy + 0.03, 2.2))
cs.done()
Part("CoreUnit_Band", "Hazard", p).cyl(0, 0, 0.08, 0.22, 0.646, 8).done()
Part("CoreUnit_Lamp", "StatusOrange", p).cyl(0, 0, 2.9, 2.94, 0.1, 12).done()

p = piece("Cart")                                                   # a trolley with canisters: 1.0 x 0.6, 1.0 high
ct = Part("Cart_Frame", "PaintGrey", p)
for sx in (-1, 1):
    for sy in (-1, 1):
        ct.box((sx * 0.46 - 0.02, sy * 0.26 - 0.02, 0.1), (sx * 0.46 + 0.02, sy * 0.26 + 0.02, 0.92))
ct.box((-0.5, -0.3, 0.2), (0.5, 0.3, 0.24)).box((-0.5, -0.3, 0.7), (0.5, 0.3, 0.74)).box((0.48, -0.3, 0.92), (0.52, 0.3, 0.96))
ct.done()
cw = Part("Cart_Wheels", "DarkSteel", p)
for sx in (-1, 1):
    for sy in (-1, 1):
        cw.tube((sx * 0.46, sy * 0.26 - 0.02, 0.06), (sx * 0.46, sy * 0.26 + 0.02, 0.06), 0.06, 10)
cw.done()
Part("Cart_Cans", "PaintGreen", p).cyl(-0.25, 0.0, 0.74, 1.14, 0.12, 14).cyl(0.05, 0.08, 0.74, 1.14, 0.12, 14).done()
Part("Cart_Caps", "DarkSteel", p).cyl(-0.25, 0.0, 1.14, 1.19, 0.05, 10).cyl(0.05, 0.08, 1.14, 1.19, 0.05, 10).done()
Part("Cart_Box", "RArmor", p, 0.006).box((-0.42, -0.24, 0.24), (0.1, 0.22, 0.56)).done()

# small things beside the big ones (nothing stops at them)
p = piece("Cone")
Part("Cone_Body", "PaintOrange", p).cone(0, 0, 0.03, 0.5, 0.13, 0.03, 14).done()
Part("Cone_Foot", "DarkSteel", p).box((-0.17, -0.17, 0.0), (0.17, 0.17, 0.03)).done()
Part("Cone_Band", "RArmor", p).cone(0, 0, 0.26, 0.34, 0.085, 0.07, 14).done()

p = piece("Toolbox")
Part("Toolbox_Body", "RRed", p, 0.006).box((-0.24, -0.11, 0.0), (0.24, 0.11, 0.2)).done()
Part("Toolbox_Dark", "DarkSteel", p).box((-0.25, -0.12, 0.13), (0.25, 0.12, 0.15)).box((-0.1, -0.015, 0.2), (0.1, 0.015, 0.25)).done()

p = piece("Canisters")
Part("Canisters_A", "PaintBlue", p).cyl(-0.14, 0.0, 0.0, 0.46, 0.11, 14).done()
Part("Canisters_B", "PaintGrey", p).cyl(0.13, 0.06, 0.0, 0.46, 0.11, 14).cyl(0.02, -0.2, 0.0, 0.34, 0.09, 14).done()
Part("Canisters_Caps", "DarkSteel", p).cyl(-0.14, 0.0, 0.46, 0.5, 0.05, 10).cyl(0.13, 0.06, 0.46, 0.5, 0.05, 10).cyl(0.02, -0.2, 0.34, 0.38, 0.04, 10).done()

p = piece("CableReel")
Part("CableReel_Drum", "Cable", p).tube((0, -0.14, 0.34), (0, 0.14, 0.34), 0.24, 16).done()
Part("CableReel_Sides", "Cardboard", p).tube((0, -0.17, 0.34), (0, -0.14, 0.34), 0.34, 18).tube((0, 0.14, 0.34), (0, 0.17, 0.34), 0.34, 18).done()

for ob in bpy.context.scene.objects:
    ob.select_set(True)
bpy.context.view_layer.objects.active = bpy.context.scene.objects[0]
bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                          export_image_format="NONE", export_materials="EXPORT", export_animations=False)
print("kit:", _slot[0], "pieces,", len(bpy.context.scene.objects), "objects ->", os.path.normpath(OUT))
