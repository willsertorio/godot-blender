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
	"GunSlide": ["Metal038", Color(0.95, 0.96, 0.97), -1.0, 0.05, 0.12],
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
	"GloveFabric": ["Leather031", Color(0.75, 0.75, 0.78), 0.0, 0.0, 0.05],
	"ArmSuit": ["Fabric045", Color(0.2, 0.21, 0.24), 0.0, 0.0, 0.08],
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
		m = _military(name, MILITARY[name])
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
		var mg := _military_std(["Plastic012B", Color(0.42, 0.44, 0.40, 0.55), 0.0, -0.3, 0.12])
		mg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m = mg
	elif name in ["GunLens", "RifleLens"]:
		var ln := StandardMaterial3D.new()
		# Dark coated glass: reflects the room, hides the tube behind it.
		ln.albedo_color = Color(0.015, 0.03, 0.045, 0.93)
		ln.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ln.metallic = 0.9
		ln.roughness = 0.04
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
	for dir in [MIL_DIR, "res://assets/textures/fabric/"]:
		var p: String = dir + set_name + "/" + map + ".jpg"
		if ResourceLoader.exists(p):
			return load(p)
	return null


## Wear per texture set: [wear amount, wear colour (what shows under the coating), wear metallic, wear roughness,
## scratches, dirt]. Painted / coated sets chip down to steel; polymer scuffs to a lighter grey; rubber only gets dirty.
const MIL_WEAR := {
	"Plastic018B": [0.75, Color(0.60, 0.60, 0.58), 1.0, 0.32, 0.5, 0.35],
	"Metal029": [0.85, Color(0.58, 0.58, 0.57), 1.0, 0.30, 0.6, 0.35],
	"Metal038": [0.45, Color(0.80, 0.80, 0.80), 1.0, 0.22, 0.8, 0.12],
	"Metal046B": [0.55, Color(0.66, 0.66, 0.66), 1.0, 0.25, 0.6, 0.4],
	"Plastic012B": [0.4, Color(0.34, 0.34, 0.33), 0.0, 0.5, 0.5, 0.5],
	"Rubber004": [0.0, Color(0.2, 0.2, 0.2), 0.0, 0.8, 0.0, 0.6],
	"Metal048A": [0.3, Color(0.95, 0.78, 0.45), 1.0, 0.2, 0.5, 0.3],
	"Leather031": [0.0, Color(0.2, 0.2, 0.2), 0.0, 0.8, 0.0, 0.5],
	"Fabric045": [0.0, Color(0.2, 0.2, 0.2), 0.0, 0.9, 0.0, 0.5],
}


## Physical look per texture set. The scans are far darker than a real finish (the black coat reflects ~1 %), so
## `bright` lifts the base colour to a plausible albedo; `metal` overrides the row (the powder coat and paints are
## dielectric coatings, only bare steel / brass are metal); `rough` scales the roughness map.
const MIL_LOOK := {
	"Plastic018B": {"bright": 3.6, "rough": 1.05},                # paint: ~0.08 after the olive tint
	"Metal029": {"bright": 4.5, "metal": 0.0, "rough": 1.7},      # black powder coat: ~0.05, satin
	"Metal038": {"bright": 4.5, "rough": 1.0, "contrast": 0.3},                    # steel: ~0.5 reflectance
	"Metal046B": {"bright": 7.0, "rough": 1.1},                   # dark worn metal: ~0.3
	"Plastic012B": {"bright": 4.0, "rough": 1.2},                 # black polymer: ~0.04
	"Rubber004": {"bright": 3.0, "rough": 1.2},
	"Metal048A": {"bright": 1.0, "rough": 2.5},
	"Leather031": {"bright": 3.0, "rough": 1.0, "contrast": 1.0},  # black leather: ~0.03
	"Fabric045": {"bright": 1.0, "rough": 1.0, "contrast": 1.0},   # the weave is the texture: keep its contrast
}


## Worn hardware (assets/shaders/military.gdshader) from a MILITARY row. Bevels are ~1 mm on the guns / gloves and
## ~6 mm on the enemies, which sets what counts as an edge.
static func _military(name: String, spec: Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/military.gdshader")
	var set_name: String = spec[0]
	m.set_shader_parameter("tex_albedo", _mil_tex(set_name, "albedo"))
	m.set_shader_parameter("tex_normal", _mil_tex(set_name, "normal"))
	m.set_shader_parameter("tex_rough", _mil_tex(set_name, "rough"))
	m.set_shader_parameter("tex_imperfections", load(MIL_DIR + "_detail/imperfections.png"))
	m.set_shader_parameter("tint", spec[1])
	var look: Dictionary = MIL_LOOK.get(set_name, {})
	var metal: float = look.get("metal", spec[2])
	if metal < 0.0 and _mil_tex(set_name, "metal"):
		m.set_shader_parameter("tex_metal", _mil_tex(set_name, "metal"))
		m.set_shader_parameter("use_metal_map", true)
		m.set_shader_parameter("metallic", 1.0)
	else:
		m.set_shader_parameter("metallic", maxf(metal, 0.0))
	# The enemies stand under the room lights (far stronger than the weapon's own lights): darker finish.
	var world_scale := 0.42 if (name.begins_with("Turret") or name.begins_with("Drone") or name.begins_with("Spider")) else 1.0
	m.set_shader_parameter("brightness", float(look.get("bright", 1.0)) * world_scale)
	m.set_shader_parameter("albedo_contrast", float(look.get("contrast", 0.55)))
	m.set_shader_parameter("rough_scale", maxf(1.0 + float(spec[3]), 0.0) * float(look.get("rough", 1.0)))
	m.set_shader_parameter("tile", float(spec[4]))
	var big := name.begins_with("Turret") or name.begins_with("Drone") or name.begins_with("Spider")
	m.set_shader_parameter("edge_radius", 0.007 if big else 0.0013)
	var w: Array = MIL_WEAR.get(set_name, [0.5, Color(0.6, 0.6, 0.6), 1.0, 0.3, 0.5, 0.4])
	m.set_shader_parameter("wear", w[0])
	m.set_shader_parameter("wear_color", w[1])
	m.set_shader_parameter("wear_metallic", w[2])
	m.set_shader_parameter("wear_rough", w[3])
	m.set_shader_parameter("scratch", w[4])
	m.set_shader_parameter("dirt", w[5])
	return m


## Triplanar (object-local) StandardMaterial from a MILITARY row (kept for the see-through magazines).
static func _military_std(spec: Array) -> StandardMaterial3D:
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
## `mask` = the model's baked AO / edge texture ("" = none): military materials get a per-model copy that reads it.
static func rebind(mesh: Mesh, mask: String = "") -> Mesh:
	var out := mesh.duplicate() as Mesh
	for i in out.get_surface_count():
		var src := out.surface_get_material(i)
		if src == null:
			continue
		# Only names the library owns are replaced (Neon*, PortalField, ...); anything else
		# (Quaternius MI_* materials with their own textures) is kept as imported.
		var base := src.resource_name.get_slice(".", 0)
		var has_uv: bool = not (out is ArrayMesh) or ((out as ArrayMesh).surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV) != 0
		if MILITARY.has(base) and mask != "":
			out.surface_set_material(i, _masked(base, mask))
			continue
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
## `model_path`: the glb the scene came from; if "<model>_mask.png" exists next to it, it is used.
static func rebind_tree(root: Node, model_path: String = "") -> void:
	var mask := model_path.replace(".glb", "_mask.png") if model_path != "" else ""
	if mask != "" and not ResourceLoader.exists(mask):
		mask = ""
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.mesh = rebind(mi.mesh, mask)


static func _masked(name: String, mask: String) -> ShaderMaterial:
	var key := name + "@" + mask
	if _cache.has(key):
		return _cache[key]
	var m := _military(name, MILITARY[name])
	m.set_shader_parameter("tex_mask", load(mask))
	m.set_shader_parameter("use_mask", true)
	m.resource_name = name
	_cache[key] = m
	return m
