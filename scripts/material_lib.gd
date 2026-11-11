class_name MaterialLib
## Godot-side materials, bound by the material names Blender exports.
## Blender only names materials (and gives preview colours); textures, tiling and the
## neon shader live here, so visuals are tuned in Godot where they are judged.
##
## UVs are in metres, so `tile` is metres per texture repeat.


## Plain materials for greybox fallbacks (the art comes from Quaternius materials).
const SURFACES := {
	"PropMetal": {"tint": Color(0.18, 0.19, 0.21), "rough": 0.6, "metal": 0.4},
}

const NEON := {
	"NeonCyan": Color("#22E5FF"),
	"NeonRed": Color("#FF2D55"),
	"NeonGreen": Color("#39FF88"),
	"NeonViolet": Color("#B48CFF"),
	"NeonOrange": Color("#FF7A1A"),
}

## Grounded-military materials for the from-scratch assets (XM9, XM-R4, HG-7 gloves, AT-9, FR-2, SD-4).
## The Blender models have no UVs, so every set is projected triplanar in the object's own space (it stays
## stuck to moving parts). CC0 ambientCG sets in assets/textures/military/<set>/ (512 px):
##   Plastic018B worn painted coating (tinted)   Metal038 bare scratched steel   Metal029 powder-coated black
##   Metal046B dirty dark metal   Plastic012B scratched black polymer   Rubber004 rubber   Metal048A brass base
## name -> [set, tint, metallic (-1 = use the set's metal map), roughness offset, tile (metres per repeat)]
const MIL_DIR := "res://assets/textures/military/"
const MILITARY := {
	# XM9 pistol
	"GunSlide": ["Metal038", Color(0.72, 0.73, 0.74), -1.0, 0.05, 0.12],
	"GunFrame": ["Plastic018B", Color(0.44, 0.45, 0.40), 0.0, 0.05, 0.14],
	"GunDark": ["Metal029", Color(1, 1, 1), -1.0, 0.0, 0.14],
	"GunGrip": ["Rubber004", Color(0.75, 0.75, 0.75), 0.0, 0.0, 0.05],
	"GunBarrel": ["Metal046B", Color(0.9, 0.9, 0.9), -1.0, -0.1, 0.1],
	"GunBrass": ["Metal048A", Color(0.86, 0.62, 0.32), 1.0, 0.2, 0.08],
	# XM-R4 rifle
	"RifleBody": ["Plastic018B", Color(0.42, 0.42, 0.37), 0.0, 0.05, 0.2],
	"RifleCarbon": ["Plastic012B", Color(0.75, 0.75, 0.72), 0.0, 0.0, 0.12],
	"RiflePolymer": ["Plastic018B", Color(0.30, 0.30, 0.27), 0.0, 0.15, 0.18],
	"RifleDark": ["Metal029", Color(1, 1, 1), -1.0, 0.0, 0.15],
	"RifleMetal": ["Metal046B", Color(0.9, 0.9, 0.9), -1.0, -0.1, 0.12],
	"RifleBrass": ["Metal048A", Color(0.86, 0.62, 0.32), 1.0, 0.2, 0.08],
	# HG-7 gloves
	"GlovePlate": ["Plastic018B", Color(0.30, 0.31, 0.31), 0.0, 0.05, 0.1],
	"GloveCuff": ["Rubber004", Color(0.45, 0.45, 0.45), 0.0, 0.0, 0.06],
	# Enemies
	"TurretArmor": ["Plastic018B", Color(0.40, 0.41, 0.33), 0.0, 0.05, 0.6],
	"TurretDark": ["Metal029", Color(1, 1, 1), -1.0, 0.0, 0.5],
	"TurretMetal": ["Metal046B", Color(0.9, 0.9, 0.9), -1.0, -0.05, 0.4],
	"TurretBrass": ["Metal048A", Color(0.86, 0.62, 0.32), 1.0, 0.2, 0.2],
	"DroneArmor": ["Plastic018B", Color(0.40, 0.41, 0.34), 0.0, 0.05, 0.6],
	"DroneArmorLight": ["Plastic018B", Color(0.52, 0.52, 0.46), 0.0, 0.05, 0.6],
	"DroneDark": ["Metal029", Color(1, 1, 1), -1.0, 0.0, 0.5],
	"DroneMetal": ["Metal046B", Color(0.9, 0.9, 0.9), -1.0, -0.05, 0.4],
	"SpiderArmor": ["Plastic018B", Color(0.40, 0.41, 0.34), 0.0, 0.05, 0.6],
	"SpiderPlate": ["Plastic018B", Color(0.48, 0.48, 0.42), 0.0, 0.05, 0.5],
	"SpiderDark": ["Metal029", Color(1, 1, 1), -1.0, 0.0, 0.5],
	"SpiderJoint": ["Metal046B", Color(0.9, 0.9, 0.9), -1.0, -0.05, 0.4],
	"SpiderTread": ["Rubber004", Color(0.6, 0.6, 0.6), 0.0, 0.0, 0.2],
}
## Glove / sleeve fabric on the from-scratch gloves (no UVs -> triplanar StandardMaterial, not the fabric shader).
const MIL_FABRIC := {
	"GloveFabric": ["res://assets/textures/fabric/Leather031/", Color(0.16, 0.16, 0.17), 0.05],
	"ArmSuit": ["res://assets/textures/fabric/Fabric045/", Color(0.2, 0.21, 0.24), 0.08],
}
const FLASH_MATS := ["MuzzleFlash", "TurretFlash", "DroneFlash"]

## Quaternius materials (glbs carry names only; see blender/scripts/normalize_quaternius.py).
const Q_TABLE := "res://assets/models/q_materials.json"
const QDIR := "res://assets/textures/quaternius/"
## Glow the free glTFs drop (the paid packs add it with custom shaders):
## material name -> [emissive mask (or ""), colour, energy].
const EMISSIVE := {
	"MI_Trim_01": ["T_Trim_01_Emissive", Color(0.55, 0.85, 1.0), 2.2],
	"MI_PaddedWall": ["T_PaddingWall_Emissive", Color(0.55, 0.85, 1.0), 1.8],
	"MI_Enemies": ["T_Enemies_Emissive", Color("#FF4A2B"), 3.0],
	"MI_Enemies_Large": ["T_Enemies_Large_Emissive", Color("#FF4A2B"), 3.0],
	"MI_Guns_Batch1": ["T_Guns_Batch1_Emissive", Color(1.0, 0.55, 0.15), 1.6],
	"MI_Props_Batch2": ["T_Props_Batch2_Emissive", Color(0.35, 1.0, 0.55), 2.0],
	"M_Light": ["", Color(0.85, 0.93, 1.0), 2.6],
}

static var _cache: Dictionary = {}

## Glove / sleeve fabric (arm_r.glb / arm_l.glb materials), see assets/shaders/fabric.gdshader.
const FABRIC := {
	"ArmSuit": {"set": "Fabric045", "tint": Color(0.085, 0.09, 0.11), "tile": 9.0, "mean": 0.765, "contrast": 0.9, "normal": 1.6, "rough": 0.0, "sheen": 0.3},
	"ArmGlove": {"set": "Leather031", "tint": Color(0.06, 0.06, 0.065), "tile": 6.0, "mean": 0.14, "contrast": 0.5, "normal": 2.5, "rough": -0.15, "sheen": 0.15},
}


static func fabric(name: String, src: Material) -> ShaderMaterial:
	var key := name + str(src.get_instance_id() if src else 0)
	if _cache.has(key):
		return _cache[key]
	var spec: Dictionary = FABRIC[name]
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/fabric.gdshader")
	var dir := "res://assets/textures/fabric/%s/" % spec.set
	m.set_shader_parameter("detail_albedo", load(dir + "albedo.jpg"))
	m.set_shader_parameter("detail_normal", load(dir + "normal.jpg"))
	m.set_shader_parameter("detail_rough", load(dir + "rough.jpg"))
	m.set_shader_parameter("tint", spec.tint)
	m.set_shader_parameter("tile", spec.tile)
	m.set_shader_parameter("detail_mean", spec.mean)
	m.set_shader_parameter("albedo_contrast", spec.contrast)
	m.set_shader_parameter("normal_strength", spec.normal)
	m.set_shader_parameter("rough_bias", spec.rough)
	m.set_shader_parameter("sheen", spec.sheen)
	if src is BaseMaterial3D and (src as BaseMaterial3D).normal_texture:
		m.set_shader_parameter("base_normal", (src as BaseMaterial3D).normal_texture)
		m.set_shader_parameter("has_base_normal", true)
	m.resource_name = name
	_cache[key] = m
	return m
static var _q: Dictionary = {}


static func _qtex(name: String) -> Texture2D:
	for ext in [".jpg", ".png"]:
		if ResourceLoader.exists(QDIR + name + ext):
			return load(QDIR + name + ext)
	return null


static func _quaternius(name: String) -> Material:
	if _q.is_empty() and ResourceLoader.exists(Q_TABLE):
		_q = JSON.parse_string(FileAccess.get_file_as_string(Q_TABLE))
	if not _q.has(name):
		return null
	var spec: Dictionary = _q[name]
	var m := ORMMaterial3D.new()
	var c: Array = spec.color
	m.albedo_color = Color(c[0], c[1], c[2], c[3])
	if spec.base != "":
		m.albedo_texture = _qtex(spec.base)
	if spec.orm != "":
		m.orm_texture = _qtex(spec.orm)
		m.roughness = 1.0
		m.metallic = 1.0
	else:
		m.roughness = spec.roughness
		m.metallic = spec.metallic
	if spec.normal != "":
		m.normal_enabled = true
		m.normal_texture = _qtex(spec.normal)
	# Blender flags every imported material as blended; only decals and glass really are.
	if name.contains("Decal") or name == "M_Glass" or float(spec.get("alpha_value", 1.0)) < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED if name == "M_Glass" else BaseMaterial3D.CULL_BACK
	if EMISSIVE.has(name):
		var e: Array = EMISSIVE[name]
		m.emission_enabled = true
		m.emission = e[1]
		m.emission_energy_multiplier = e[2]
		if e[0] != "":
			m.emission_texture = _qtex(e[0])
			# Default operator ADDs colour + texture; the mask must multiply the colour.
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func get_material(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m: Material = _quaternius(name)
	if m:
		pass
	elif MILITARY.has(name):
		m = _military(MILITARY[name])
	elif name in FLASH_MATS:
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = Color(1.0, 0.85, 0.55) if name != "MuzzleFlash" else Color(0.6, 0.95, 1.0)
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		fm.no_depth_test = false
		m = fm
	elif name in ["GunMagazine", "RifleMagazine"]:
		var mg := _military(["Plastic012B", Color(0.42, 0.44, 0.40, 0.55), 0.0, -0.3, 0.12])
		mg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m = mg
	elif name in ["GunLens", "RifleLens"]:
		var ln := StandardMaterial3D.new()
		# Nearly clear coated glass (it sits in the aim line of both sights).
		ln.albedo_color = Color(0.55, 0.75, 0.85, 0.12)
		ln.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ln.metallic = 0.0
		ln.roughness = 0.02
		ln.metallic_specular = 0.8
		m = ln
	elif name == "GunScreen":
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.02, 0.05, 0.07)
		sm.roughness = 0.2
		sm.emission_enabled = true
		sm.emission = Color(0.15, 0.6, 0.8)
		sm.emission_energy_multiplier = 0.5
		m = sm
	elif SURFACES.has(name):
		m = _surface(SURFACES[name])
	elif name.begins_with("Neon"):
		m = neon(NEON.get(name, NEON.NeonCyan))
	elif name == "ArmAccent":
		var ac := StandardMaterial3D.new()
		ac.albedo_color = Color(0.62, 0.27, 0.05)
		ac.roughness = 0.55
		m = ac
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


static func _mil_tex(set_name: String, map: String) -> Texture2D:
	var p := MIL_DIR + set_name + "/" + map + ".jpg"
	return load(p) if ResourceLoader.exists(p) else null


## Triplanar (object-local) PBR material from a MILITARY row.
static func _military(spec: Array) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var set_name: String = spec[0]
	m.albedo_texture = _mil_tex(set_name, "albedo")
	m.albedo_color = spec[1]
	m.normal_enabled = true
	m.normal_texture = _mil_tex(set_name, "normal")
	m.normal_scale = 1.0
	m.roughness_texture = _mil_tex(set_name, "rough")
	m.roughness = clampf(1.0 + float(spec[3]), 0.0, 1.0)
	var metal: float = spec[2]
	if metal < 0.0 and _mil_tex(set_name, "metal"):
		m.metallic_texture = _mil_tex(set_name, "metal")
		m.metallic = 1.0
	else:
		m.metallic = maxf(metal, 0.0)
	m.metallic_specular = 0.5
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / float(spec[4])
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Fabric for meshes without UVs (the from-scratch gloves / sleeves): triplanar StandardMaterial.
static func _mil_fabric(name: String) -> StandardMaterial3D:
	var key := "milfab_" + name
	if _cache.has(key):
		return _cache[key]
	var spec: Array = MIL_FABRIC[name]
	var dir: String = spec[0]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + "albedo.jpg")
	m.albedo_color = spec[1]
	m.normal_enabled = true
	m.normal_texture = load(dir + "normal.jpg")
	m.roughness_texture = load(dir + "rough.jpg")
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / float(spec[2])
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.resource_name = name
	_cache[key] = m
	return m


static func neon(c: Color, energy: float = 2.6) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/neon.gdshader")
	sm.set_shader_parameter("neon_color", c)
	sm.set_shader_parameter("energy", energy)
	return sm


static func _surface(spec: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = spec.tint
	m.roughness = spec.rough
	m.metallic = spec.metal
	return m


## Replace every surface material of a mesh with the library material of the same name.
static func rebind(mesh: Mesh) -> Mesh:
	var out := mesh.duplicate() as Mesh
	for i in out.get_surface_count():
		var src := out.surface_get_material(i)
		if src == null:
			continue
		# Only names the library owns are replaced (Neon*, PortalField, ...); anything else
		# (Quaternius MI_* materials with their own textures) is kept as imported.
		var base := src.resource_name.get_slice(".", 0)
		var has_uv: bool = not (out is ArrayMesh) or ((out as ArrayMesh).surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV) != 0
		if MIL_FABRIC.has(base) and not has_uv:
			out.surface_set_material(i, _mil_fabric(base))
			continue
		if FABRIC.has(base):
			out.surface_set_material(i, fabric(base, src))
			continue
		var lib := get_material(src.resource_name.get_slice(".", 0))
		if lib:
			out.surface_set_material(i, lib)
	return out


## Rebind every MeshInstance3D under `root` (for glb scenes instanced as-is).
static func rebind_tree(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.mesh = rebind(mi.mesh)
