class_name WeaponHolder
extends Node3D
## The player's two weapons. Hitscan from the camera centre: a shot hits only the first
## thing on WORLD | HOSTILE along the ray; walls and closed doors stop it.
##   1 = pistol: semi-automatic, never runs out.
##   2 = rifle: automatic, magazine + finite reserve, R reloads (only the rifle reloads).
## Aiming down sights tightens spread (and the Player narrows FOV and slows walking).
## Greybox view models; the hero art pass swaps in the Blender weapons (node "Muzzle").

signal fired(weapon: String)
signal hit_hostile(killed: bool)
signal changed

const WEAPONS := {
	"pistol": {"damage": 25.0, "interval": 0.24, "auto": false, "spread": 0.022, "ads_spread": 0.003,
		"range": 90.0, "sound": "pistol", "kick": 1.0,
		"model": "res://assets/models/pistol.glb", "hip": Vector3(0.15, -0.17, -0.36), "ads": Vector3(0.0, -0.13, -0.33),
		# Arm poses in the weapon frame (Godot axes: -Z = barrel, +Y = up; origin = grip): [position, rotation deg].
		"arm_r": [Vector3(0, 0, 0), Vector3(-14, 0, 0)], "arm_l": [Vector3(-0.045, -0.01, -0.035), Vector3(-10, 0, -25)]},
	"rifle": {"damage": 12.0, "interval": 0.095, "auto": true, "spread": 0.035, "ads_spread": 0.009,
		"range": 90.0, "sound": "rifle", "kick": 0.55, "mag": 30, "reload": 1.5,
		"model": "res://assets/models/rifle.glb", "hip": Vector3(0.18, -0.24, -0.38), "ads": Vector3(0.0, -0.255, -0.4),
		"arm_r": [Vector3(0, 0, 0), Vector3(-14, 0, 0)], "arm_l": [Vector3(-0.01, -0.06, -0.3), Vector3(-8, 0, 8)]},
}
const RESERVE_START := 60
const RESERVE_MAX := 240
const SWITCH_TIME := 0.28

var player: Player
var current := "pistol"
var mag := 30
var reserve := RESERVE_START
var reloading := 0.0
var switching := 0.0
var cooldown := 0.0
var kick := 0.0
var bloom := 0.0
## Capture/test hook: keep muzzle flash and tracer visible until the next shot.
var hold_fx := false
var shots_fired := 0

var models: Dictionary = {}
var view_model: Node3D
var flash_light: OmniLight3D
var flash_sprite: MeshInstance3D
var tracer: MeshInstance3D
var _fx := 0.0


func setup(p: Player) -> void:
	player = p
	models["pistol"] = _load_model("pistol", _greybox_pistol)
	models["rifle"] = _load_model("rifle", _greybox_rifle)
	for k in models:
		var m: Node3D = models[k]
		add_child(m)
		m.visible = k == current
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view_model = models[current]

	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(0.6, 0.95, 1.0)
	flash_light.omni_range = 6.0
	flash_light.light_energy = 0.0
	add_child(flash_light)

	flash_sprite = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.13, 0.13)
	flash_sprite.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = _flash_texture()
	fm.albedo_color = Color(0.7, 0.97, 1.0) * 2.0
	flash_sprite.material_override = fm
	flash_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_sprite.visible = false
	add_child(flash_sprite)

	tracer = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	tracer.mesh = cyl
	tracer.material_override = MaterialLib.neon(Color(0.55, 0.95, 1.0), 2.2)
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer.visible = false
	tracer.top_level = true
	add_child(tracer)


func muzzle() -> Node3D:
	return view_model.find_child("Muzzle", true, false)


func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	bloom = maxf(0.0, bloom - delta * 2.5)
	kick = move_toward(kick, 0.0, delta * 7.0)
	if not hold_fx:
		_fx = maxf(0.0, _fx - delta * 18.0)
		flash_light.light_energy = _fx * 3.0
		flash_sprite.visible = _fx > 0.3
		tracer.visible = _fx > 0.15
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			_finish_reload()
	if switching > 0.0:
		switching -= delta

	var w0: Dictionary = WEAPONS[current]
	var target: Vector3 = w0.ads if player.ads else w0.hip
	var lower := 0.0
	if switching > 0.0:
		lower = sin(clampf(switching / SWITCH_TIME, 0, 1) * PI) * 0.25
	if reloading > 0.0:
		lower = maxf(lower, 0.12)
	view_model.position = view_model.position.lerp(target + Vector3(0, -lower, 0), 1.0 - exp(-16.0 * delta))
	view_model.position.z += kick * 0.05
	view_model.rotation.x = kick * 0.22 + (0.5 if reloading > 0.0 else 0.0) * 0.6
	flash_sprite.global_position = muzzle().global_position
	flash_light.global_position = muzzle().global_position

	if not player.input_enabled or not player.alive:
		return
	if Input.is_action_just_pressed("weapon_1"):
		switch_to("pistol")
	elif Input.is_action_just_pressed("weapon_2"):
		switch_to("rifle")
	if Input.is_action_just_pressed("reload"):
		start_reload()
	var w: Dictionary = WEAPONS[current]
	var want := Input.is_action_pressed("fire") if w.auto else Input.is_action_just_pressed("fire")
	if want:
		try_fire()


func switch_to(w: String) -> void:
	if w == current:
		return
	reloading = 0.0
	models[current].visible = false
	current = w
	view_model = models[current]
	view_model.visible = true
	switching = SWITCH_TIME
	Sfx.play("switch")
	changed.emit()


func start_reload() -> bool:
	if current != "rifle" or reloading > 0.0 or reserve <= 0 or mag >= WEAPONS.rifle.mag:
		return false
	reloading = WEAPONS.rifle.reload
	Sfx.play("reload_out")
	changed.emit()
	return true


func _finish_reload() -> void:
	var need: int = WEAPONS.rifle.mag - mag
	var take := mini(need, reserve)
	mag += take
	reserve -= take
	reloading = 0.0
	Sfx.play("reload_in")
	changed.emit()


func add_rifle_ammo(n: int) -> bool:
	if reserve >= RESERVE_MAX:
		return false
	reserve = mini(RESERVE_MAX, reserve + n)
	changed.emit()
	return true


## Fire if ready. Returns true if a shot went out.
func try_fire() -> bool:
	if cooldown > 0.0 or switching > 0.0 or reloading > 0.0:
		return false
	var w: Dictionary = WEAPONS[current]
	cooldown = w.interval
	if current == "rifle":
		if mag <= 0:
			Sfx.play("dry")
			cooldown = 0.25
			return false
		mag -= 1
	_shoot(w)
	changed.emit()
	return true


func _shoot(w: Dictionary) -> void:
	shots_fired += 1
	kick = w.kick
	_fx = 1.0
	flash_light.light_energy = 3.0
	flash_sprite.visible = true
	flash_sprite.rotation.z = randf() * TAU
	Sfx.play(w.sound)
	var cam := player.camera
	var spread: float = (w.ads_spread if player.ads else w.spread) + bloom * (0.3 if player.ads else 1.0)
	if w.auto:
		bloom = minf(bloom + 0.006, 0.03)
	var basis := cam.global_transform.basis
	var dir := -basis.z
	var ang := randf() * TAU
	var r := sqrt(randf()) * spread
	dir = (dir + basis.x * cos(ang) * r + basis.y * sin(ang) * r).normalized()
	var from := cam.global_position
	var to := from + dir * float(w.range)
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.HOSTILE)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if hit:
		end = hit.position
		var target: Node = hit.collider as Node
		while target and not target.has_method("take_damage"):
			target = target.get_parent()
		if target is Enemy:
			target.take_damage(w.damage)
			hit_hostile.emit(target.dead)
		else:
			Sfx.play_at("hit_wall", hit.position)
			_impact(hit.position, hit.normal)
	Enemy.aim_beam(tracer, muzzle().global_position, end, 0.007)
	tracer.visible = true
	fired.emit(current)


func _impact(p: Vector3, n: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.05
	s.height = 0.1
	spark.mesh = s
	spark.material_override = MaterialLib.neon(Color(0.6, 0.95, 1.0), 3.0)
	fx_root().add_child(spark)
	spark.global_position = p + n * 0.03
	var tw := spark.create_tween()
	tw.tween_property(spark, "scale", Vector3.ONE * 0.1, 0.2)
	tw.tween_callback(spark.queue_free)


const ARMS := "res://assets/models/arms.glb"
static var _arms_scene: PackedScene


## Gloved arms (blender/scripts/build_arms.py) posed on a weapon model: ArmR on the grip,
## ArmL per weapon. Nodes ArmR/ArmL, Wrist*, Hand*, Forearm* stay addressable for animation.
func _attach_arms(model: Node3D, w: String) -> void:
	if not ResourceLoader.exists(ARMS):
		return
	if _arms_scene == null:
		_arms_scene = load(ARMS)
	var inst := _arms_scene.instantiate()
	MaterialLib.rebind_tree(inst)
	for side in ["R", "L"]:
		var a := inst.find_child("Arm" + side, true, false) as Node3D
		if a == null:
			continue
		a.get_parent().remove_child(a)
		model.add_child(a)
		var pose: Array = WEAPONS[w]["arm_" + side.to_lower()]
		a.position = pose[0]
		a.rotation_degrees = pose[1]
	inst.free()


## The Quaternius weapon (normalized) or the greybox fallback.
func _load_model(w: String, fallback: Callable) -> Node3D:
	var path: String = WEAPONS[w].model
	if not ResourceLoader.exists(path):
		return fallback.call()
	var m := (load(path) as PackedScene).instantiate() as Node3D
	MaterialLib.rebind_tree(m)
	assert(m.find_child("Muzzle", true, false) != null, path + " has no Muzzle")
	m.position = WEAPONS[w].hip
	_attach_arms(m, w)
	return m


static func _flash_texture() -> Texture2D:
	var g := Gradient.new()
	# Additive blend ignores alpha: fade the colour itself to black.
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1), Color(0.45, 0.45, 0.45), Color(0, 0, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


func _part(root: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)


func _greybox_pistol() -> Node3D:
	var root := Node3D.new()
	root.name = "Pistol"
	var m := MaterialLib.get_material("PropMetal")
	var neon := MaterialLib.neon(Color("#22E5FF"), 1.8)
	_part(root, Vector3(0.035, 0.05, 0.17), Vector3(0, 0, 0), m)
	_part(root, Vector3(0.032, 0.085, 0.036), Vector3(0, -0.055, 0.045), m, Vector3(-0.2, 0, 0))
	_part(root, Vector3(0.037, 0.006, 0.12), Vector3(0, 0.026, -0.01), neon)
	var mz := Node3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(0, 0.005, -0.095)
	root.add_child(mz)
	root.position = Vector3(0.17, -0.16, -0.42)
	return root


func _greybox_rifle() -> Node3D:
	var root := Node3D.new()
	root.name = "Rifle"
	var m := MaterialLib.get_material("PropMetal")
	var neon := MaterialLib.neon(Color("#22E5FF"), 1.8)
	_part(root, Vector3(0.05, 0.07, 0.42), Vector3(0, 0, 0), m)
	_part(root, Vector3(0.03, 0.03, 0.2), Vector3(0, 0.005, -0.3), m)
	_part(root, Vector3(0.04, 0.11, 0.05), Vector3(0, -0.075, 0.07), m, Vector3(-0.25, 0, 0))
	_part(root, Vector3(0.035, 0.12, 0.06), Vector3(0, -0.08, -0.08), m, Vector3(0.15, 0, 0))
	_part(root, Vector3(0.052, 0.008, 0.3), Vector3(0, 0.038, -0.02), neon)
	var mz := Node3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(0, 0.005, -0.41)
	root.add_child(mz)
	root.position = Vector3(0.17, -0.16, -0.42)
	return root


## Parent for transient effects: the running scene, or the tree root in test harnesses.
func fx_root() -> Node:
	var t := get_tree()
	return t.current_scene if t.current_scene != null else t.root
