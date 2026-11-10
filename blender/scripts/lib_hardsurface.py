"""Shared helpers for modelled hard-surface assets (run inside Blender).

Conventions (CLAUDE.md): 1 BU = 1 m, Z-up, +Y forward, origin at the asset base.
UVs are box-projected in metres (1 UV unit = 1 m) so every texture tiles at real-world
scale; Godot sets the texture repeat per material. Material names are the contract with
Godot's MaterialLib: Godot binds texture sets and the neon shader by name.
"""
import math
import bmesh
import bpy
from mathutils import Matrix, Vector

# Viewport/preview colours only. Godot replaces these by material name.
MATERIALS = {
    "WallPanel": dict(color=(0.09, 0.095, 0.105), metallic=0.7, rough=0.5),
    "WallTrim": dict(color=(0.03, 0.032, 0.035), metallic=0.6, rough=0.45),
    "DoorMetal": dict(color=(0.2, 0.21, 0.22), metallic=0.8, rough=0.4),
    "Floor": dict(color=(0.12, 0.12, 0.125), metallic=0.8, rough=0.45),
    "Ceiling": dict(color=(0.08, 0.085, 0.09), metallic=0.6, rough=0.55),
    "CrateMetal": dict(color=(0.3, 0.32, 0.34), metallic=0.6, rough=0.45),
    "PropMetal": dict(color=(0.06, 0.065, 0.07), metallic=0.7, rough=0.45),
    "LightPanel": dict(color=(0.85, 0.95, 1.0), emit=6.0),
    "NeonCyan": dict(color=(0x22 / 255, 0xE5 / 255, 1.0), emit=8.0),
    "NeonRed": dict(color=(1.0, 0x2D / 255, 0x55 / 255), emit=8.0),
    "NeonGreen": dict(color=(0x39 / 255, 1.0, 0x88 / 255), emit=8.0),
    "NeonViolet": dict(color=(0xB4 / 255, 0x8C / 255, 1.0), emit=8.0),
}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    bpy.context.scene.render.fps = 30


def material(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    spec = MATERIALS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    c = (*spec["color"], 1.0)
    bsdf.inputs["Base Color"].default_value = c
    if "emit" in spec:
        bsdf.inputs["Emission Color"].default_value = c
        bsdf.inputs["Emission Strength"].default_value = spec["emit"]
        bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
    else:
        bsdf.inputs["Metallic"].default_value = spec["metallic"]
        bsdf.inputs["Roughness"].default_value = spec["rough"]
    return m


class Part:
    """A primitive with a material and a bevel width.
    kind "box": cuboid lo..hi (rot_z or rot=(x, y, z) radians about its centre)
    kind "cyl": cylinder fitted to lo..hi along `axis` with `segments` sides
    kind "gem": faceted icosphere fitted to lo..hi
    kind "torus": ring in the XY plane fitted to lo..hi (x/y = outer size, z = tube thickness)"""

    def __init__(self, lo, hi, mat, bevel=0.012, rot_z=0.0, rot=None, kind="box", segments=8, axis="Z"):
        self.lo = Vector(lo)
        self.hi = Vector(hi)
        self.mat = mat
        self.bevel = bevel
        self.rot = rot if rot is not None else (0.0, 0.0, rot_z)
        self.kind = kind
        self.segments = segments
        self.axis = axis


def build(name, parts, segments=2):
    """Build one mesh object from parts. Each part is bevelled on its own (so seams
    between parts stay crisp), then normals are hardened with WeightedNormal."""
    pieces = []
    for i, p in enumerate(parts):
        me = bpy.data.meshes.new(f"{name}_{i}")
        bm = bmesh.new()
        size = p.hi - p.lo
        centre = (p.hi + p.lo) * 0.5
        rot = Matrix.Rotation(p.rot[2], 4, "Z") @ Matrix.Rotation(p.rot[1], 4, "Y") @ Matrix.Rotation(p.rot[0], 4, "X")
        if p.kind == "box":
            mat = Matrix.Translation(centre) @ rot @ Matrix.Diagonal((*size, 1.0))
            bmesh.ops.create_cube(bm, size=1.0, matrix=mat)
        elif p.kind == "cyl":
            # Unit cylinder along Z (radius 0.5, depth 1), then aligned to the axis and fitted.
            align = {"Z": Matrix.Identity(4), "Y": Matrix.Rotation(math.pi / 2, 4, "X"), "X": Matrix.Rotation(math.pi / 2, 4, "Y")}[p.axis]
            dims = {"Z": (size.x, size.y, size.z), "Y": (size.x, size.z, size.y), "X": (size.z, size.y, size.x)}[p.axis]
            mat = Matrix.Translation(centre) @ rot @ align @ Matrix.Diagonal((*dims, 1.0))
            bmesh.ops.create_cone(bm, cap_ends=True, segments=p.segments, radius1=0.5, radius2=0.5, depth=1.0, matrix=mat)
        elif p.kind == "gem":
            mat = Matrix.Translation(centre) @ rot @ Matrix.Diagonal((*(size * 0.5), 1.0))
            bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0, matrix=mat)
        elif p.kind == "torus":
            r_major = (size.x + size.y) * 0.25 - size.z * 0.5
            r_minor = size.z * 0.5
            bm.free()
            bpy.ops.mesh.primitive_torus_add(major_radius=r_major, minor_radius=r_minor, major_segments=p.segments * 3,
                                             minor_segments=6, location=centre, rotation=p.rot)
            tob = bpy.context.active_object
            tob.name = f"{name}_{i}"
            tob.data.materials.append(material(p.mat))
            pieces.append(tob)
            continue
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(f"{name}_{i}", me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(material(p.mat))
        if p.bevel > 0:
            bev = ob.modifiers.new("Bevel", "BEVEL")
            bev.width = min(p.bevel, min(size) * 0.45)
            bev.segments = segments
            bev.limit_method = "ANGLE"
            bev.harden_normals = True
            bev.miter_outer = "MITER_ARC"
        _apply_modifiers(ob)
        pieces.append(ob)

    bpy.ops.object.select_all(action="DESELECT")
    for ob in pieces:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    if len(pieces) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    wn = ob.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    wn.keep_sharp = True
    wn.mode = "FACE_AREA"
    ob.modifiers.new("Triangulate", "TRIANGULATE").keep_custom_normals = True  # n-gon caps -> tangents
    _apply_modifiers(ob)
    box_uv(ob)
    return ob


def _apply_modifiers(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def box_uv(ob):
    """Box projection in metres: each face maps its two non-dominant axes to UV."""
    me = ob.data
    uv = me.uv_layers.new(name="UVMap") if not me.uv_layers else me.uv_layers[0]
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:      # X-facing: (y, z)
                u = (v.y if n.x > 0 else -v.y, v.z)
            elif ax == 1:    # Y-facing: (x, z)
                u = (-v.x if n.y > 0 else v.x, v.z)
            else:            # Z-facing: (x, y)
                u = (v.x, v.y if n.z > 0 else -v.y)
            uv.data[li].uv = u


def export_glb(path, objects, animations=False, images=False):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
        for c in ob.children_recursive:
            c.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_tangents=True,
        export_animations=animations,
        export_animation_mode="ACTIONS",
        export_image_format="JPEG" if images else "NONE",
        export_materials="EXPORT",
    )
    print("exported", path)
