class_name MaterialLib
## Godot-side materials, bound by the material names Blender exports.
## Blender only names materials (and gives preview colours); textures, tiling and the
## neon shader live here, so visuals are tuned in Godot where they are judged.
##
## UVs are in metres, so `tile` is metres per texture repeat.

const TEX := "res://assets/textures/%s/%s.jpg"

const SURFACES := {
	"WallPanel": {"set": "Metal046A", "tile": 2.0, "tint": Color(0.7, 0.74, 0.8), "rough": 1.0, "metal": 0.3},
	"WallTrim": {"set": "Metal028", "tile": 2.0, "tint": Color(0.75, 0.78, 0.82), "rough": 0.85, "metal": 0.35},
	"DoorMetal": {"set": "Metal038", "tile": 2.0, "tint": Color(0.62, 0.66, 0.72), "rough": 0.85, "metal": 0.7},
	"Floor": {"set": "DiamondPlate008A", "tile": 1.0, "tint": Color(0.55, 0.57, 0.6), "rough": 0.9, "metal": 0.45},
	"Ceiling": {"set": "MetalPlates015B", "tile": 2.0, "tint": Color(0.5, 0.52, 0.56), "rough": 1.0, "metal": 0.3},
	"CrateMetal": {"set": "Metal038", "tile": 1.0, "tint": Color(0.78, 0.82, 0.86), "rough": 0.8, "metal": 0.45},
	"GunMetal": {"set": "Metal038", "tile": 0.5, "tint": Color(0.72, 0.75, 0.8), "rough": 0.7, "metal": 0.75},
	"GunPaint": {"set": "Metal028", "tile": 0.5, "tint": Color(0.5, 0.52, 0.56), "rough": 0.8, "metal": 0.4},
	"GunGrip": {"set": "Metal029", "tile": 0.5, "tint": Color(0.4, 0.4, 0.42), "rough": 1.0, "metal": 0.1},
	"EnemyArmor": {"set": "Metal028", "tile": 1.0, "tint": Color(0.95, 0.72, 0.76), "rough": 0.7, "metal": 0.35},
	"EnemyMetal": {"set": "Metal038", "tile": 1.0, "tint": Color(0.5, 0.52, 0.56), "rough": 0.8, "metal": 0.6},
	"FrameMetal": {"set": "Metal038", "tile": 1.0, "tint": Color(0.55, 0.57, 0.62), "rough": 0.7, "metal": 0.6},
	"PropMetal": {"set": "Metal029", "tile": 1.0, "tint": Color(0.85, 0.88, 0.92), "rough": 0.9, "metal": 0.5},
}

const NEON := {
	"NeonCyan": Color("#22E5FF"),
	"NeonRed": Color("#FF2D55"),
	"NeonGreen": Color("#39FF88"),
	"NeonViolet": Color("#B48CFF"),
}

static var _cache: Dictionary = {}


static func get_material(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m: Material = null
	if SURFACES.has(name):
		m = _surface(SURFACES[name])
	elif name.begins_with("Neon"):
		m = neon(NEON.get(name, NEON.NeonCyan))
	elif name == "PortalField":
		var pm := ShaderMaterial.new()
		pm.shader = load("res://assets/shaders/portal.gdshader")
		m = pm
	elif name == "LightPanel":
		var lp := StandardMaterial3D.new()
		lp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lp.albedo_color = Color(0.72, 0.88, 1.0) * 1.05
		m = lp
	if m:
		m.resource_name = name
		_cache[name] = m
	return m


static func neon(c: Color, energy: float = 2.6) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/neon.gdshader")
	sm.set_shader_parameter("neon_color", c)
	sm.set_shader_parameter("energy", energy)
	return sm


static func _surface(spec: Dictionary) -> ORMMaterial3D:
	var m := ORMMaterial3D.new()
	var s: String = spec.set
	m.albedo_texture = load(TEX % [s, "albedo"])
	m.albedo_color = spec.tint
	m.orm_texture = load(TEX % [s, "orm"])
	m.normal_enabled = true
	m.normal_texture = load(TEX % [s, "normal"])
	m.roughness = spec.rough
	m.metallic = spec.metal
	var k := 1.0 / float(spec.tile)
	m.uv1_scale = Vector3(k, k, k)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Replace every surface material of a mesh with the library material of the same name.
static func rebind(mesh: Mesh) -> Mesh:
	var out := mesh.duplicate() as Mesh
	for i in out.get_surface_count():
		var src := out.surface_get_material(i)
		if src == null:
			continue
		if src.resource_name.begins_with("PH_"):
			continue  # Poly Haven prop: keeps its own photoreal textures from the glb
		var lib := get_material(src.resource_name)
		if lib:
			out.surface_set_material(i, lib)
		else:
			push_warning("MaterialLib: no material named '%s'" % src.resource_name)
	return out


## Rebind every MeshInstance3D under `root` (for glb scenes instanced as-is).
static func rebind_tree(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.mesh = rebind(mi.mesh)
