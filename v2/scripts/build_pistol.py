"""V2 concept: a detailed service pistol, built for this scene (replaces the V1 XM9 in the viewmodel).

    blender -b -P v2/scripts/build_pistol.py -- /tmp/pistol      # stand-alone review renders (EEVEE, 4 views)
    (build_viewmodel.py imports build() and places the result in the player's hands)

Millimetres in the code, metres in the scene. Gun frame: +Y = muzzle, +Z = up, X = 0 the centre plane, the bore
axis at Z = 43, the frame's rail line (underside of the slide) at Z = 28, the tang of the grip at about (Y -50, Z 18).
Every part is real geometry: profiles extruded to their width, boolean cuts (serrations, ejection port, top port,
rail slots, sight notch, trigger-guard opening), then a bevel on every sharp edge and weighted normals.
Parts: slide, barrel + chamber hood + guide rod, frame with accessory rail, trigger guard, rounded grip with
textured panels, magazine base plate, trigger with safety tab, slide stop, takedown levers, magazine release, pins,
extractor, rear plate, iron sights with dots, reflex sight (hood, tilted lens, emitter, buttons, screws), weapon light.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import v2lib as L  # noqa: E402

S = 0.001
BORE_Z = 43.0
ANCHORS = {                      # metres, gun frame: used by build_viewmodel.py to place the hands
    "tang": Vector((0, -50, 18)) * S,
    "grip_centre": Vector((0, -22, -42)) * S,
    "grip_half_width": 15 * S,
    "slide_top": 56 * S,
    "rake": math.atan2(22, 66),
    "trigger": Vector((0, 46, -6)) * S,
}


class Part:
    def __init__(self, name, material=None, bevel=0.4, segs=2, angle=30):
        self.name, self.material, self.bevel, self.segs, self.angle = name, material, bevel, segs, angle
        self.bm = bmesh.new()
        self.cutters = []

    def _extrude(self, verts, vec):
        f = self.bm.faces.new(verts)
        ext = bmesh.ops.extrude_face_region(self.bm, geom=[f])
        bmesh.ops.translate(self.bm, vec=vec, verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])

    def prism_x(self, pts_yz, x0, x1):
        """Side profile [(y, z), ...] extruded across the gun from x0 to x1."""
        self._extrude([self.bm.verts.new(Vector((x0, y, z)) * S) for y, z in pts_yz], Vector((x1 - x0, 0, 0)) * S)

    def prism_y(self, pts_xz, y0, y1):
        """Cross-section [(x, z), ...] extruded along the barrel from y0 to y1."""
        self._extrude([self.bm.verts.new(Vector((x, y0, z)) * S) for x, z in pts_xz], Vector((0, y1 - y0, 0)) * S)

    def box(self, lo, hi, rx=0.0, rz=0.0):
        lo, hi = Vector(lo), Vector(hi)
        m = Matrix.Translation((lo + hi) / 2 * S) @ Matrix.Rotation(math.radians(rz), 4, "Z") @ \
            Matrix.Rotation(math.radians(rx), 4, "X") @ Matrix.Diagonal((*((hi - lo) * S), 1))
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)

    def cyl(self, a, b, r, segs=28, r2=None):
        a, b = Vector(a) * S, Vector(b) * S
        d = b - a
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=r * S, radius2=(r if r2 is None else r2) * S,
                              depth=d.length, matrix=Matrix.Translation((a + b) / 2) @ rot)

    def cut(self):
        c = Part(self.name + "_cut%d" % len(self.cutters))
        self.cutters.append(c)
        return c

    def _raw(self, collection):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(self.name, me)
        collection.objects.link(ob)
        return ob

    def finish(self, collection, parent=None):
        ob = self._raw(collection)
        tmp = []
        for c in self.cutters:
            co = c._raw(collection)
            tmp.append(co)
            bo = ob.modifiers.new("Cut", "BOOLEAN")
            bo.object = co
            bo.operation = "DIFFERENCE"
            bo.solver = "EXACT"
            bo.use_self = True
        if self.bevel > 0:
            bv = ob.modifiers.new("Bevel", "BEVEL")
            bv.width = self.bevel * S
            bv.segments = self.segs
            bv.limit_method = "ANGLE"
            bv.angle_limit = math.radians(self.angle)
            bv.harden_normals = True
        bpy.context.view_layer.update()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        for o in [ob] + tmp:
            bpy.data.objects.remove(o)
        out = bpy.data.objects.new(self.name, me)
        collection.objects.link(out)
        me.materials.append(self.material)
        for p in me.polygons:
            p.use_smooth = True
        wn = out.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
        wn.keep_sharp = True
        if parent is not None:
            out.parent = parent
        return out


def materials():
    for n in ("PSlide", "PFrame", "PGripTex", "PSteel", "PBlack", "PBarrel", "PLens", "PDotRed", "PSightDot", "PCyan",
              "PLightLens", "PRubber"):
        if bpy.data.materials.get(n):
            bpy.data.materials.remove(bpy.data.materials[n])
    m = {}
    m["slide"] = L.pbr("PSlide", "Metal032", scale=0.09, tint=(0.94, 0.9, 0.84), rough=(0.34, 0.52), metallic=0.25,
                       normal=0.5, grunge=0.1, grunge_scale=40, round_edges=0.0004)
    m["frame"] = L.pbr("PFrame", "Plastic012B", scale=0.05, tint=(0.62, 0.68, 0.78), bright=1.25, rough=(0.5, 0.72), normal=0.8,
                       round_edges=0.0005)
    m["grip"] = L.pbr("PGripTex", "Rubber004", scale=0.012, bright=0.55, rough=(0.7, 0.95), normal=4.0)
    m["steel"] = L.pbr("PSteel", "Metal032", scale=0.06, tint=(0.2, 0.2, 0.21), rough=(0.28, 0.45), metallic=1.0,
                       round_edges=0.0003)
    m["black"] = L.pbr("PBlack", "Metal032", scale=0.06, tint=(0.05, 0.05, 0.055), rough=(0.35, 0.55), metallic=0.6,
                       round_edges=0.0003)
    m["barrel"] = L.pbr("PBarrel", "Metal032", scale=0.05, tint=(0.75, 0.74, 0.72), rough=(0.12, 0.3), metallic=1.0)
    m["rubber"] = L.pbr("PRubber", "Rubber004", scale=0.02, bright=1.0, rough=(0.6, 0.9), normal=1.5)
    m["lens"] = L.plain("PLens", (0.55, 0.8, 1.0), rough=0.0, transmission=1.0, ior=1.5)
    m["dot"] = L.plain("PDotRed", (0, 0, 0), emit=(1.0, 0.07, 0.03), emit_strength=80.0)
    m["sightdot"] = L.plain("PSightDot", (0.85, 0.9, 0.8), rough=0.4, emit=(0.6, 1.0, 0.6), emit_strength=0.8)
    m["cyan"] = L.plain("PCyan", (0, 0.02, 0.03), emit=(0.15, 0.85, 1.0), emit_strength=3.0)
    m["lightlens"] = L.plain("PLightLens", (0.9, 0.95, 1.0), rough=0.05, transmission=0.6, ior=1.5,
                             emit=(0.9, 0.95, 1.0), emit_strength=0.4)
    return m


def build(collection, parent=None):
    M = materials()
    out = []

    def done(p):
        out.append(p.finish(collection, parent))

    # ------------------------------------------------------------------ slide
    sl = Part("P_Slide", M["slide"], bevel=0.5, segs=2)
    sl.prism_y([(-13, 28), (13, 28), (13, 48.5), (9.5, 56), (-9.5, 56), (-13, 48.5)], -38, 150)
    c = sl.cut()                                   # nose relief under the muzzle + chamfered top front + rear rake
    c.prism_x([(151, 27), (151, 35.5), (134, 27)], -20, 20)
    c = sl.cut()
    c.prism_x([(151, 57), (151, 51.5), (143, 57)], -20, 20)
    c = sl.cut()
    c.prism_x([(-39, 57), (-39, 46), (-35.5, 57)], -20, 20)
    c = sl.cut()                                   # serrations: 8 rear, 6 front, both sides, leaning forward
    for y0, n in ((-31, 8), (100, 6)):
        for i in range(n):
            for sx in (-1, 1):
                c.box((sx * 13.6 - 1.4, y0 + i * 3.7, 29.5), (sx * 13.6 + 1.4, y0 + i * 3.7 + 1.7, 49.5), rx=-14)
    c = sl.cut()                                   # ejection port (right side + top)
    c.box((-4.5, 30, 46), (16, 63, 60))
    c = sl.cut()                                   # top port over the barrel
    c.box((-3.6, 74, 52), (3.6, 96, 60))
    c = sl.cut()
    c.box((-3.6, 100, 52), (3.6, 126, 60))
    c = sl.cut()                                   # side panel line + muzzle holes (barrel, guide rod)
    for sx in (-1, 1):
        c.box((sx * 13.4 - 0.9, -20, 35.3), (sx * 13.4 + 0.9, 132, 36.2))
    c = sl.cut()
    c.cyl((0, 120, BORE_Z), (0, 152, BORE_Z), 7.7)
    c = sl.cut()
    c.cyl((0, 136, 32.6), (0, 152, 32.6), 3.3, segs=16)
    done(sl)

    br = Part("P_Barrel", M["barrel"], bevel=0.3)
    br.cyl((0, 20, BORE_Z), (0, 152.5, BORE_Z), 7.1, segs=32)
    br.box((-9.3, 30.4, 43), (9.3, 62.6, 55.6))                # chamber hood, seen through the ejection port
    c = br.cut()
    c.cyl((0, 120, BORE_Z), (0, 154, BORE_Z), 4.6, segs=24)    # bore
    done(br)
    st = Part("P_SteelBits", M["steel"], bevel=0.25)
    st.cyl((0, 80, 32.6), (0, 150.4, 32.6), 2.6, segs=16)      # guide rod
    st.box((12.6, 6, 41.5), (13.5, 29, 44.8))                  # extractor
    st.box((-8.6, -38.7, 31), (8.6, -37.6, 52))                # rear cover plate
    st.cyl((0, -39.0, 43), (0, -37.6, 43), 2.6, segs=14)       # striker indicator
    for y, z, r in ((31, 20, 1.7), (-12, 12, 1.7), (47, 22.5, 2.3), (-30, 22, 1.5)):   # pins, both sides
        st.cyl((-13.9, y, z), (13.9, y, z), r, segs=14)
    done(st)

    # ------------------------------------------------------------------ frame
    fr = Part("P_Frame", M["frame"], bevel=0.7, segs=3)
    fr.prism_x([(-40, 14), (-44, 21), (-41, 28), (148, 28), (148, 14.5), (143.5, 9.5), (52, 9.5), (45, 14)], -13.5, 13.5)
    c = fr.cut()                                   # accessory-rail slots + the groove that makes the rail lip
    for y in (60, 80, 100, 120):
        c.box((-16, y, 7), (16, y + 5.2, 12.6))
    c = fr.cut()
    for sx in (-1, 1):
        c.box((sx * 13.5 - 1.6, 54, 15.2), (sx * 13.5 + 1.6, 149, 17.6))
    c = fr.cut()                                   # thumb scallops above the trigger
    for sx in (-1, 1):
        c.cyl((sx * 20.5, 30, 20), (sx * 20.5, 62, 20), 8.2, segs=24)
    done(fr)

    tg = Part("P_TriggerGuard", M["frame"], bevel=1.6, segs=3)
    tg.prism_x([(16, 16), (83, 16), (85, 8), (82, -21), (73, -31), (26, -32), (14, -22)], -7.2, 7.2)
    c = tg.cut()
    c.prism_x([(27, 10.5), (74, 10.5), (76.5, 5), (74.5, -17.5), (68, -24.5), (32, -25.5), (25.5, -18)], -12, 12)
    done(tg)

    gr = Part("P_Grip", M["frame"], bevel=5.5, segs=5)
    gr.prism_x([(27, 15), (24, -22), (17, -46), (8, -70), (2.5, -88), (-56.5, -92), (-55, -70), (-50, -40), (-45.5, -12),
                (-47, 4), (-54.5, 15.5), (-51, 21.5), (-40, 22.5), (-40, 15)], -15, 15)
    done(gr)
    gp = Part("P_GripPanels", M["grip"], bevel=0.9, segs=2)
    gp.prism_x([(13, -32), (7.5, -52), (-0.5, -80), (-48.5, -83.5), (-46.5, -58), (-41, -30), (-20, -27)], -15.7, 15.7)
    gp.prism_y([(-9, -27), (9, -27), (9, -84), (-9, -84)], -57.2, -43)       # back-strap texture
    c = gp.cut()                                                              # keep only what stands proud of the grip
    c.prism_x([(9, -34), (4, -54), (-3.5, -78), (-45, -81), (-43.5, -58), (-38.5, -33), (-20, -30)], -15.0, 15.0)
    done(gp)
    fs = Part("P_FrontStrap", M["grip"], bevel=0.6)
    for i in range(9):                                                         # front-strap ribs
        t = i / 8
        y, z = 22.2 - t * 19.2, -27 - t * 56
        fs.box((-8.5, y - 0.4, z - 2.2), (8.5, y + 1.6, z + 2.2), rx=-18.4)
    done(fs)
    bp = Part("P_MagBase", M["black"], bevel=1.4, segs=3)
    bp.prism_x([(7.5, -88), (-59, -92.6), (-60, -100.5), (9.5, -97.5)], -15.6, 15.6)
    c = bp.cut()
    for sx in (-1, 1):
        for i in range(3):
            c.box((sx * 15.6 - 0.8, -40 + i * 6, -98.5), (sx * 15.6 + 0.8, -37.5 + i * 6, -92.5), rx=20)
    done(bp)

    # ------------------------------------------------------------------ controls
    tr = Part("P_Trigger", M["black"], bevel=0.9, segs=3)
    tr.prism_x([(40, 10), (47, 10), (48.5, -1), (46, -13), (41, -20), (37.5, -19), (41, -10), (41, 0)], -3.6, 3.6)
    done(tr)
    tb = Part("P_TriggerTab", M["steel"], bevel=0.3)
    tb.prism_x([(41.8, 3), (43.6, 3), (42.2, -18.5), (39.8, -18.5)], -1.0, 1.0)
    done(tb)
    ct = Part("P_Controls", M["black"], bevel=0.5, segs=2)
    ct.prism_x([(-8, 22.6), (27, 22.6), (30, 25), (27, 27.4), (-8, 27.4)], -15.4, -13.3)      # slide stop (left)
    ct.box((-17.4, -9, 22.4), (-13.3, 2, 28))                                                # its thumb shelf
    for sx in (-1, 1):                                                                       # takedown levers
        ct.box((sx * 14.4 - 1.0, 43.5, 19.5), (sx * 14.4 + 1.0, 50.5, 25.5))
    ct.cyl((-17.6, 20, -5), (-13.0, 20, -5), 4.4, segs=20)                                   # magazine release
    ct.cyl((13.0, 20, -5), (15.0, 20, -5), 3.6, segs=20)
    c = ct.cut()
    for i in range(4):
        c.box((-18.5, -8.2 + i * 2.5, 27.2), (-14.5, -7.2 + i * 2.5, 29))                    # shelf ribs
    c = ct.cut()
    for i in range(3):
        c.box((-18.6, 17.2 + i * 2.4, -10), (-17.0, 18.0 + i * 2.4, 0))                      # button ribs
    done(ct)

    # ------------------------------------------------------------------ iron sights
    sg = Part("P_Sights", M["black"], bevel=0.4)
    sg.prism_x([(140.5, 56), (133, 56), (134.5, 62), (139.5, 62)], -1.9, 1.9)
    sg.prism_x([(-34.5, 56), (-23, 56), (-24.5, 62.6), (-34.5, 62.6)], -10.5, 10.5)
    c = sg.cut()
    c.box((-2.3, -36, 58.6), (2.3, -22, 64))
    done(sg)
    sd = Part("P_SightDots", M["sightdot"], bevel=0)
    sd.cyl((0, 132.6, 59.6), (0, 134.6, 59.6), 1.1, segs=12)
    for sx in (-1, 1):
        sd.cyl((sx * 6.2, -35.0, 59.8), (sx * 6.2, -33.5, 59.8), 1.1, segs=12)
    done(sd)

    # ------------------------------------------------------------------ reflex sight
    op = Part("P_Optic", M["black"], bevel=0.9, segs=3)
    op.box((-12.6, -19, 56), (12.6, 27, 59.2))                                                # mounting plate
    op.prism_x([(-17, 59), (27.5, 59), (27.5, 66), (9, 66), (5, 63.5), (-17, 63.5)], -13.2, 13.2)   # deck
    op.prism_x([(11, 63), (27.5, 63), (27.5, 87), (24.5, 91.5), (15, 91.5), (11, 86)], -13.2, 13.2)  # hood
    c = op.cut()
    c.prism_x([(4, 66.2), (40, 66.2), (40, 85.5), (22.5, 88), (15.5, 88), (4, 85)], -10.6, 10.6)    # the window
    c = op.cut()
    for sx in (-1, 1):                                                                        # side lightening flats
        c.box((sx * 13.6 - 0.9, 13.5, 69), (sx * 13.6 + 0.9, 25, 84))
    done(op)
    ob = Part("P_OpticBits", M["steel"], bevel=0.25)
    for sx in (-1, 1):
        for y in (-12, 2):
            ob.cyl((sx * 13.0, y, 61.3), (sx * 14.2, y, 61.3), 1.7, segs=12)                 # plate screws
    ob.cyl((0, -9, 63.2), (0, -9, 64.6), 5.2, segs=24)                                        # battery cap
    ob.box((-3.2, 4.4, 63.4), (3.2, 8.6, 66.2))                                               # emitter
    done(ob)
    obc = Part("P_OpticCapSlot", M["black"], bevel=0)
    obc.box((-4.2, -9.5, 64.4), (4.2, -8.5, 64.9))
    done(obc)
    rb = Part("P_OpticButtons", M["rubber"], bevel=0.5)
    for sx in (-1, 1):
        rb.box((sx * 13.6 - 0.8, -6, 59.8), (sx * 13.6 + 0.8, -1, 62.8))
    done(rb)
    ln = Part("P_OpticLens", M["lens"], bevel=0)
    ln.box((-10.9, 20.2, 66), (10.9, 21.4, 88.2), rx=-4)
    done(ln)
    dt = Part("P_OpticDot", M["dot"], bevel=0)
    bmesh.ops.create_icosphere(dt.bm, subdivisions=2, radius=0.00045, matrix=Matrix.Translation(Vector((0, 19.6, 77)) * S))
    done(dt)
    cy = Part("P_Accent", M["cyan"], bevel=0)
    cy.box((-13.35, 4, 60.3), (-13.2, 22, 61.0))
    cy.box((13.2, 4, 60.3), (13.35, 22, 61.0))
    done(cy)

    # ------------------------------------------------------------------ weapon light
    wl = Part("P_Light", M["black"], bevel=1.2, segs=3)
    wl.prism_x([(88, 9.5), (131, 9.5), (131, -15), (126, -18.5), (92, -18.5), (88, -14)], -12.6, 12.6)
    wl.cyl((0, 129, -4), (0, 151, -4), 13.6, segs=36)
    wl.cyl((0, 149, -4), (0, 153.5, -4), 14.6, segs=36)
    for sx in (-1, 1):                                                                        # paddles
        wl.box((sx * 11.5 - 3.2, 80, -11), (sx * 11.5 + 3.2, 89, 4))
    c = wl.cut()
    c.cyl((0, 150.5, -4), (0, 156, -4), 12.2, segs=36)
    c = wl.cut()
    for i in range(10):                                                                       # bezel flutes
        a = i * math.tau / 10
        c.cyl((14.6 * math.cos(a), 147, -4 + 14.6 * math.sin(a)), (14.6 * math.cos(a), 155, -4 + 14.6 * math.sin(a)), 2.0, segs=10)
    for sx in (-1, 1):
        for i in range(4):
            wl.box((sx * 12.9 - 0.5, 96 + i * 7, -12), (sx * 12.9 + 0.5, 99.5 + i * 7, 3))    # cooling ribs
    done(wl)
    ws = Part("P_LightScrew", M["steel"], bevel=0.3)
    ws.cyl((-15.5, 110, 12.5), (15.5, 110, 12.5), 2.6, segs=14)
    ws.cyl((0, 149.6, -4), (0, 150.6, -4), 11.9, segs=36)                                     # reflector
    done(ws)
    wg = Part("P_LightLens", M["lightlens"], bevel=0)
    wg.cyl((0, 150.6, -4), (0, 151.8, -4), 12.1, segs=36)
    done(wg)
    return out


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    prefix = argv[0] if argv else "/tmp/pistol"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    parts = build(sc.collection)
    tris = sum(len(o.data.polygons) for o in parts)
    print(f"pistol: {len(parts)} parts, {tris} faces")
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.eevee.taa_render_samples = 16
    sc.render.resolution_x, sc.render.resolution_y = 1000, 620
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.52, 0.55, 1)
    sc.world = w
    sun = bpy.data.objects.new("s", bpy.data.lights.new("s", "SUN"))
    sun.data.energy = 3.5
    sc.collection.objects.link(sun)
    cd = bpy.data.cameras.new("c")
    cd.type = "ORTHO"
    cd.ortho_scale = 0.3
    cam = bpy.data.objects.new("c", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    ctr = Vector((0, 0.05, -0.015))
    for name, d in (("right", (1, 0, 0.0)), ("left", (-1, 0, 0.0)), ("top3q", (0.55, -0.5, 0.65)), ("front3q", (-0.6, 0.75, 0.35))):
        dv = Vector(d).normalized()
        cam.location = ctr + dv
        cam.rotation_euler = (-dv).to_track_quat("-Z", "Y").to_euler()
        sun.rotation_euler = ((-dv + Vector((0.3, 0.2, -0.6))).normalized()).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{prefix}_{name}.png"
        bpy.ops.render.render(write_still=True)
