class_name V2Assets
## V2 assets in Godot: the glbs carry no images; every material is rebuilt by name from
## assets/models/v2/materials.json (written by v2/scripts/export_godot.py) + assets/textures/v2.

const DIR := "res://assets/models/v2/"
const TEX := "res://assets/textures/v2/"
const SPECIAL := {  # materials that are procedural in Blender
	"TankLiquid": {"color": Color(0.2, 0.62, 0.68, 0.45), "rough": 0.08, "emit": Color(0.1, 0.5, 0.55), "energy": 0.35},
	"Hazard": {"color": Color(0.85, 0.62, 0.05), "rough": 0.6},
	"DarkGlass": {"color": Color(0.03, 0.05, 0.07, 0.75), "rough": 0.05},
}

static var _data: Dictionary = {}
static var _mats: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(DIR + "materials.json"))
	return _data


static func _tex(set_name: String, kind: String) -> Texture2D:
	var path := "%s%s_%s.jpg" % [TEX, set_name, kind]
	return load(path) if ResourceLoader.exists(path) else null


static func _flash(core: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/v2_flash.gdshader")
	m.set_shader_parameter("core", core)
	return m


static func _glove(mesh_key: String, sleeve: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/v2_glove.gdshader")
	m.set_shader_parameter("knit_albedo", _tex("Fabric045", "color"))
	m.set_shader_parameter("knit_normal", _tex("Fabric045", "normal"))
	m.set_shader_parameter("leather_albedo", _tex("Rubber004", "color"))
	var box: Dictionary = data().gloves.get(mesh_key, {"min": [0, 0, 0], "size": [1, 1, 1]})
	m.set_shader_parameter("box_min", Vector3(box.min[0], box.min[1], box.min[2]))
	m.set_shader_parameter("box_size", Vector3(box.size[0], box.size[1], box.size[2]))
	if sleeve:
		m.set_shader_parameter("sleeve", 1.0)
		m.set_shader_parameter("knit_tint", Color(0.11, 0.12, 0.14))
		m.set_shader_parameter("knit_scale", 0.16)
	return m


## The Godot material for a Blender material name (cached; gloves are per mesh: they carry their box).
static func material(mat_name: String, mesh_key: String = "") -> Material:
	if mat_name == "Glove" or mat_name == "JacketSleeve":
		var key := mat_name + "/" + mesh_key
		if not _mats.has(key):
			_mats[key] = _glove(mesh_key, mat_name == "JacketSleeve")
		return _mats[key]
	if _mats.has(mat_name):
		return _mats[mat_name]
	var d: Dictionary = data().materials.get(mat_name, {})
	var m: Material
	if mat_name.begins_with("Flash"):
		m = _flash(mat_name == "FlashCore")
	else:
		var s := StandardMaterial3D.new()
		if SPECIAL.has(mat_name):
			var sp: Dictionary = SPECIAL[mat_name]
			s.albedo_color = sp.color
			s.roughness = sp.rough
			if sp.color.a < 1.0:
				s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if sp.has("emit"):
				s.emission_enabled = true
				s.emission = sp.emit
				s.emission_energy_multiplier = sp.energy
		elif d.get("type", "") == "pbr":
			s.albedo_texture = _tex(d.set, "color")
			s.albedo_color = Color(d.tint[0], d.tint[1], d.tint[2])
			s.roughness_texture = _tex(d.set, "rough")
			s.roughness = d.rough[1]
			s.metallic = d.metallic
			var n := _tex(d.set, "normal")
			if n != null:
				s.normal_enabled = true
				s.normal_texture = n
				s.normal_scale = minf(d.normal, 2.0)
			s.uv1_triplanar = true                      # box projection in object space, as in Blender
			s.uv1_scale = Vector3.ONE / float(d.scale)
			s.uv1_triplanar_sharpness = 4.0
			s.vertex_color_use_as_albedo = d.get("vcol", false)
		elif d.get("type", "") == "plain":
			s.albedo_color = Color(d.color[0], d.color[1], d.color[2], d.alpha)
			s.roughness = d.rough
			s.metallic = d.metallic
			if d.emit_strength > 0.0 and (d.emit[0] + d.emit[1] + d.emit[2]) > 0.0:
				s.emission_enabled = true
				s.emission = Color(d.emit[0], d.emit[1], d.emit[2])
				s.emission_energy_multiplier = clampf(d.emit_strength * 0.3, 1.0, 6.0)
			if d.transmission > 0.0:
				s.albedo_color.a = 0.22
				s.roughness = 0.05
			if s.albedo_color.a < 1.0:
				s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m = s
	m.resource_name = mat_name
	_mats[mat_name] = m
	return m


## Swap every surface of every mesh under `root` for its rebuilt material.
static func apply(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src != null and src.resource_name != "":
				mi.set_surface_override_material(s, material(src.resource_name, String(mi.name)))


## Cut the one baked "Scene" animation into the clips of <asset>_clips.json. Returns the AnimationPlayer.
static func clips(root: Node, asset: String) -> AnimationPlayer:
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return null
	var path := DIR + asset + "_clips.json"
	if not ap.has_animation("Scene") and ap.get_animation_list().size() > 0:      # (whatever the importer called it)
		ap.get_animation_library("").rename_animation(ap.get_animation_list()[0], "Scene")
	AnimUtil.split_clips(ap, path)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for c in spec.loops:
		if ap.has_animation(c):
			ap.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	# Muzzle flashes are shown for one frame by their scale; the importer drops those one-frame keys, so their scale
	# tracks are rebuilt from the frames listed by the exporter (once per shared library).
	var lib := ap.get_animation_library("")
	var flashes: Dictionary = spec.get("flashes", {})
	if not flashes.is_empty() and not lib.has_meta("flashes_rebuilt"):
		lib.set_meta("flashes_rebuilt", true)
		for clip_name in spec.clips:
			var a := ap.get_animation(clip_name)
			var first: float = spec.clips[clip_name][0]
			var last: float = spec.clips[clip_name][1]
			for flash in flashes:
				var track := -1
				var fpath := NodePath()
				for i in a.get_track_count():
					var p := a.track_get_path(i)
					if String(p.get_name(p.get_name_count() - 1)) == flash:
						fpath = p
						if a.track_get_type(i) == Animation.TYPE_SCALE_3D:
							track = i
				if fpath.is_empty():
					continue
				if track < 0:
					track = a.add_track(Animation.TYPE_SCALE_3D)
					a.track_set_path(track, fpath)
				while a.track_get_key_count(track) > 0:
					a.track_remove_key(track, 0)
				a.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
				a.scale_track_insert_key(track, 0.0, Vector3.ONE * 0.001)
				for f in flashes[flash]:
					if f >= first and f <= last:
						a.scale_track_insert_key(track, (f - first) / float(spec.fps), Vector3.ONE)
						a.scale_track_insert_key(track, (f + 1.0 - first) / float(spec.fps), Vector3.ONE * 0.001)
	return ap
