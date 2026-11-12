"""Shared helpers for the V2 concept scene (run inside Blender 4.2).

Materials: scanned CC0 sets from v2/textures/<Set>/ projected as a box in object space (no UV unwrapping),
with tint / roughness controls. Geometry: bmesh builders that put many parts into one mesh, then a bevel +
weighted-normal modifier, so every edge catches light.
"""
import glob
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TEX = os.path.join(ROOT, "textures")


def _img(set_name, suffix, non_color=False):
    f = glob.glob(os.path.join(TEX, set_name, f"*_{suffix}.jpg"))
    if not f:
        return None
    im = bpy.data.images.load(f[0], check_existing=True)
    if non_color:
        im.colorspace_settings.name = "Non-Color"
    return im


def pbr(name, set_name, scale=1.0, tint=(1, 1, 1), rough=(0.0, 1.0), metallic=None, normal=1.0, bright=1.0,
        tint_attr=None, grunge=0.0, grunge_scale=0.7, round_edges=0.0, edge_wear=0.0, wear_color=(0.72, 0.72, 0.7),
        cavity=0.0, wrinkle=0.0, wrinkle_scale=90.0, wear_radius=0.0012, wear_noise=260.0, cavity_dist=0.004,
        wear_metal=1.0):
    """... edge_wear (Cycles): the coating is rubbed down to `wear_color` metal along edges (found by comparing a
    bevelled normal with the flat one), broken up by noise. cavity: darkening + roughening in recesses (AO).
    wrinkle: soft cloth wrinkles as bump."""
    """Principled material from a scanned set, box-projected in object space. scale = metres per repeat.
    rough = (min, max) the roughness map is remapped to. tint_attr = name of a colour attribute multiplied in."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / scale,) * 3
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])

    def tex(suffix, non_color):
        im = _img(set_name, suffix, non_color)
        if im is None:
            return None
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = im
        n.projection = "BOX"
        n.projection_blend = 0.25
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        return n

    col = tex("Color", False)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(col.outputs["Color"], mix.inputs[6])
    mix.inputs[7].default_value = (tint[0] * bright, tint[1] * bright, tint[2] * bright, 1)
    out_col = mix.outputs[2]
    if tint_attr:
        at = nt.nodes.new("ShaderNodeAttribute")
        at.attribute_name = tint_attr
        mix2 = nt.nodes.new("ShaderNodeMix")
        mix2.data_type = "RGBA"
        mix2.blend_type = "MULTIPLY"
        mix2.inputs["Factor"].default_value = 1.0
        nt.links.new(out_col, mix2.inputs[6])
        nt.links.new(at.outputs["Color"], mix2.inputs[7])
        out_col = mix2.outputs[2]
    gr = None
    if grunge > 0:
        # Large soft stains / traffic wear: darkens the colour a little and roughens the surface where it is dirty.
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = grunge_scale
        nz.inputs["Detail"].default_value = 9.0
        nz.inputs["Roughness"].default_value = 0.62
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.42
        ramp.color_ramp.elements[1].position = 0.72
        nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
        gr = ramp.outputs["Color"]
        dk = nt.nodes.new("ShaderNodeMix")
        dk.data_type = "RGBA"
        dk.blend_type = "MULTIPLY"
        dk.inputs[7].default_value = (1 - grunge, 1 - grunge, 1 - grunge * 0.9, 1)
        nt.links.new(gr, dk.inputs["Factor"])
        nt.links.new(out_col, dk.inputs[6])
        out_col = dk.outputs[2]
    nt.links.new(out_col, bsdf.inputs["Base Color"])
    r = tex("Roughness", True)
    if r:
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["To Min"].default_value, mr.inputs["To Max"].default_value = rough
        nt.links.new(r.outputs["Color"], mr.inputs["Value"])
        if gr is not None:
            add = nt.nodes.new("ShaderNodeMath")
            add.operation = "MULTIPLY_ADD"
            add.inputs[1].default_value = grunge * 1.6
            add.use_clamp = True
            nt.links.new(gr, add.inputs[0])
            nt.links.new(mr.outputs["Result"], add.inputs[2])
            nt.links.new(add.outputs[0], bsdf.inputs["Roughness"])
        else:
            nt.links.new(mr.outputs["Result"], bsdf.inputs["Roughness"])
    mt = tex("Metalness", True)
    if metallic is not None:
        bsdf.inputs["Metallic"].default_value = metallic
    elif mt:
        nt.links.new(mt.outputs["Color"], bsdf.inputs["Metallic"])
    nr = tex("NormalGL", True)
    if nr:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal
        nt.links.new(nr.outputs["Color"], nm.inputs["Color"])
        if round_edges > 0:          # Cycles rounds every edge at render time (radius in metres): edges catch light
            bv = nt.nodes.new("ShaderNodeBevel")
            bv.samples = 4
            bv.inputs["Radius"].default_value = round_edges
            nt.links.new(nm.outputs["Normal"], bv.inputs["Normal"])
            nt.links.new(bv.outputs["Normal"], bsdf.inputs["Normal"])
        else:
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    op = tex("Opacity", True)
    if op:
        nt.links.new(op.outputs["Color"], bsdf.inputs["Alpha"])
    if edge_wear > 0 or cavity > 0 or wrinkle > 0:
        _overlay(nt, bsdf, tc, edge_wear, wear_color, cavity, wrinkle, wrinkle_scale, wear_radius, wear_noise, cavity_dist,
                 wear_metal)
    return m


def _src(nt, sock):
    """The socket feeding `sock` (a constant node is made if it is not linked)."""
    if sock.is_linked:
        return sock.links[0].from_socket
    if sock.type == "RGBA":
        n = nt.nodes.new("ShaderNodeRGB")
        n.outputs[0].default_value = sock.default_value
    else:
        n = nt.nodes.new("ShaderNodeValue")
        n.outputs[0].default_value = sock.default_value
    return n.outputs[0]


def _mixf(nt, a, b, fac):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "FLOAT"
    nt.links.new(fac, n.inputs[0])
    nt.links.new(a, n.inputs[2])
    if isinstance(b, float):
        n.inputs[3].default_value = b
    else:
        nt.links.new(b, n.inputs[3])
    return n.outputs[0]


def _mixc(nt, a, color, fac, blend="MIX"):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    n.blend_type = blend
    nt.links.new(fac, n.inputs[0])
    nt.links.new(a, n.inputs[6])
    n.inputs[7].default_value = (*color, 1)
    return n.outputs[2]


def _overlay(nt, bsdf, tc, edge_wear, wear_color, cavity, wrinkle, wrinkle_scale, wear_radius=0.0012, wear_noise=260.0,
             cavity_dist=0.004, wear_metal=1.0):
    col, rough, metal = (_src(nt, bsdf.inputs[k]) for k in ("Base Color", "Roughness", "Metallic"))
    if cavity > 0:
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.samples = 4
        ao.inputs["Distance"].default_value = cavity_dist
        inv = nt.nodes.new("ShaderNodeMath")
        inv.operation = "SUBTRACT"
        inv.inputs[0].default_value = 1.0
        nt.links.new(ao.outputs["AO"], inv.inputs[1])
        k = nt.nodes.new("ShaderNodeMath")
        k.operation = "MULTIPLY"
        k.inputs[1].default_value = cavity * 2.0
        k.use_clamp = True
        nt.links.new(inv.outputs[0], k.inputs[0])
        col = _mixc(nt, col, (0.05, 0.045, 0.04), k.outputs[0])
        rough = _mixf(nt, rough, 0.85, k.outputs[0])
    if edge_wear > 0:
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        bv = nt.nodes.new("ShaderNodeBevel")
        bv.samples = 4
        bv.inputs["Radius"].default_value = wear_radius
        dot = nt.nodes.new("ShaderNodeVectorMath")
        dot.operation = "DOT_PRODUCT"
        nt.links.new(bv.outputs["Normal"], dot.inputs[0])
        nt.links.new(geo.outputs["True Normal"], dot.inputs[1])
        e = nt.nodes.new("ShaderNodeMath")          # (1 - dot) * gain
        e.operation = "SUBTRACT"
        e.inputs[0].default_value = 1.0
        nt.links.new(dot.outputs["Value"], e.inputs[1])
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = wear_noise
        nz.inputs["Detail"].default_value = 6.0
        nz.inputs["Roughness"].default_value = 0.7
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.38
        ramp.color_ramp.elements[1].position = 0.62
        nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
        g = nt.nodes.new("ShaderNodeMath")
        g.operation = "MULTIPLY"
        g.inputs[1].default_value = 14.0 * edge_wear
        nt.links.new(e.outputs[0], g.inputs[0])
        w = nt.nodes.new("ShaderNodeMath")
        w.operation = "MULTIPLY"
        w.use_clamp = True
        nt.links.new(g.outputs[0], w.inputs[0])
        nt.links.new(ramp.outputs["Color"], w.inputs[1])
        # a few fine scratches away from the edges too
        sc = nt.nodes.new("ShaderNodeTexNoise")
        sc.inputs["Scale"].default_value = wear_noise * 0.21
        sc.inputs["Detail"].default_value = 8.0
        sc.inputs["Distortion"].default_value = 2.5
        nt.links.new(tc.outputs["Object"], sc.inputs["Vector"])
        sr = nt.nodes.new("ShaderNodeValToRGB")
        sr.color_ramp.elements[0].position = 0.492
        sr.color_ramp.elements[0].color = (0, 0, 0, 1)
        sr.color_ramp.elements[1].position = 0.5
        sr.color_ramp.elements[1].color = (1, 1, 1, 1)
        e2 = sr.color_ramp.elements.new(0.508)
        e2.color = (0, 0, 0, 1)
        nt.links.new(sc.outputs["Fac"], sr.inputs["Fac"])
        s2 = nt.nodes.new("ShaderNodeMath")
        s2.operation = "MULTIPLY_ADD"
        s2.inputs[1].default_value = 0.5 * edge_wear
        s2.use_clamp = True
        nt.links.new(sr.outputs["Color"], s2.inputs[0])
        nt.links.new(w.outputs[0], s2.inputs[2])
        wear = s2.outputs[0]
        col = _mixc(nt, col, wear_color, wear)
        rough = _mixf(nt, rough, 0.28, wear)
        metal = _mixf(nt, metal, wear_metal, wear)
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(rough, bsdf.inputs["Roughness"])
    nt.links.new(metal, bsdf.inputs["Metallic"])
    if wrinkle > 0:
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = wrinkle_scale
        nz.inputs["Detail"].default_value = 3.0
        nz.inputs["Distortion"].default_value = 1.2
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        bp = nt.nodes.new("ShaderNodeBump")
        bp.inputs["Strength"].default_value = wrinkle
        bp.inputs["Distance"].default_value = 0.002
        nt.links.new(nz.outputs["Fac"], bp.inputs["Height"])
        if bsdf.inputs["Normal"].is_linked:
            nt.links.new(bsdf.inputs["Normal"].links[0].from_socket, bp.inputs["Normal"])
        nt.links.new(bp.outputs["Normal"], bsdf.inputs["Normal"])


def plain(name, color, rough=0.5, metallic=0.0, emit=None, emit_strength=0.0, transmission=0.0, ior=1.45, alpha=1.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Transmission Weight"].default_value = transmission
    b.inputs["IOR"].default_value = ior
    b.inputs["Alpha"].default_value = alpha
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = emit_strength
    return m


class Builder:
    """Collects boxes / cylinders into one bmesh; finish() makes the object with bevel + weighted normals."""

    def __init__(self, name, material, collection="Room", bevel=0.004, tint_layer=False):
        self.name, self.material, self.collection, self.bevel = name, material, collection, bevel
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("tint") if tint_layer else None

    def box(self, lo, hi, rot=None, pivot=None, tint=None):
        lo, hi = Vector(lo), Vector(hi)
        m = Matrix.Translation((lo + hi) / 2) @ Matrix.Diagonal((*(hi - lo), 1))
        if rot is not None:
            pv = Vector(pivot) if pivot is not None else (lo + hi) / 2
            m = Matrix.Translation(pv) @ rot @ Matrix.Translation(-pv) @ m
        geo = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        if self.col is not None:
            t = tint if tint is not None else getattr(self, "next_tint", (1, 1, 1, 1))
            for v in geo["verts"]:
                for lp in v.link_loops:
                    lp[self.col] = t
        return geo

    def cyl(self, a, b, r, segs=20, r2=None, caps=True):
        a, b = Vector(a), Vector(b)
        d = b - a
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        return bmesh.ops.create_cone(self.bm, cap_ends=caps, segments=segs, radius1=r, radius2=r if r2 is None else r2,
                                     depth=d.length, matrix=Matrix.Translation((a + b) / 2) @ rot)

    def finish(self, smooth_angle=35, bevel_segments=2):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(self.name, me)
        coll(self.collection).objects.link(ob)
        me.materials.append(self.material)
        if self.bevel > 0:
            bv = ob.modifiers.new("Bevel", "BEVEL")
            bv.width = self.bevel
            bv.segments = bevel_segments
            bv.limit_method = "ANGLE"
            bv.angle_limit = math.radians(smooth_angle)
            bv.harden_normals = True
        for p in me.polygons:
            p.use_smooth = True
        wn = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
        wn.keep_sharp = True
        return ob


def coll(name):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


def curve_tube(name, points, radius, material, collection="Room", resolution=6):
    """Cable / pipe through `points` (smooth Bezier), round section."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = resolution
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for bp, p in zip(sp.bezier_points, points):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new(name, cu)
    coll(collection).objects.link(ob)
    cu.materials.append(material)
    return ob


def setup_cycles(samples=96, res=(1280, 720)):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.03
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 4
    sc.cycles.glossy_bounces = 4
    sc.cycles.transmission_bounces = 8
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.sample_clamp_indirect = 8.0
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - High Contrast"
    return sc
