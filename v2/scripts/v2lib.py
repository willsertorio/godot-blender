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
        tint_attr=None, grunge=0.0, grunge_scale=0.7):
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
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    op = tex("Opacity", True)
    if op:
        nt.links.new(op.outputs["Color"], bsdf.inputs["Alpha"])
    return m


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
