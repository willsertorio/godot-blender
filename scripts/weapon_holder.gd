class_name WeaponHolder
extends Node3D
## Holds the player's weapons, fires hitscan shots from the camera centre.
## Greybox: pistol only. A shot hits only the first thing on WORLD | HOSTILE along
## the ray; if that is a hostile it takes damage, if it is a wall the shot stops.

signal fired(weapon: String)

const PISTOL := {
	"name": "pistol", "damage": 25.0, "interval": 0.28, "auto": false,
	"spread": 0.025, "ads_spread": 0.004, "range": 80.0,
}

var player: Player
var current := PISTOL
var cooldown := 0.0
var view_model: Node3D
var muzzle: Node3D
var flash: OmniLight3D
var kick := 0.0


func setup(p: Player) -> void:
	player = p
	view_model = _greybox_pistol()
	add_child(view_model)
	for mi in view_model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle = view_model.get_node("Muzzle")
	flash = OmniLight3D.new()
	flash.light_color = Color("#22E5FF")
	flash.omni_range = 5.0
	flash.light_energy = 0.0
	muzzle.add_child(flash)


func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	flash.light_energy = move_toward(flash.light_energy, 0.0, delta * 60.0)
	kick = move_toward(kick, 0.0, delta * 6.0)
	var hip := Vector3(0.16, -0.15, -0.42)
	var aimed := Vector3(0.0, -0.085, -0.36)
	var target := aimed if player.ads else hip
	view_model.position = view_model.position.lerp(target, 1.0 - exp(-16.0 * delta))
	view_model.position.z += kick * 0.06
	view_model.rotation.x = kick * 0.25
	if not player.input_enabled or not player.alive:
		return
	var want := Input.is_action_pressed("fire") if current.auto else Input.is_action_just_pressed("fire")
	if want and cooldown <= 0.0:
		_fire()


func _fire() -> void:
	cooldown = current.interval
	kick = 1.0
	flash.light_energy = 3.0
	var cam := player.camera
	var spread: float = current.ads_spread if player.ads else current.spread
	var dir := -cam.global_transform.basis.z
	dir = dir.rotated(cam.global_transform.basis.x, randf_range(-spread, spread))
	dir = dir.rotated(cam.global_transform.basis.y, randf_range(-spread, spread))
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * current.range, Layers.WORLD | Layers.HOSTILE)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		var col: Object = hit.collider
		var target: Node = col as Node
		while target and not target.has_method("take_damage"):
			target = target.get_parent()
		if target and target != player:
			target.take_damage(current.damage)
		_impact(hit.position, hit.normal)
	fired.emit(current.name)


func _impact(p: Vector3, n: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.06
	s.height = 0.12
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("#22E5FF")
	s.material = m
	spark.mesh = s
	get_tree().current_scene.add_child(spark)
	spark.global_position = p + n * 0.03
	var tw := spark.create_tween()
	tw.tween_property(spark, "scale", Vector3.ONE * 0.1, 0.25)
	tw.tween_callback(spark.queue_free)


func _greybox_pistol() -> Node3D:
	var root := Node3D.new()
	root.name = "Pistol"
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.21, 0.23)
	m.metallic = 0.6
	m.roughness = 0.4
	var body := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.05, 0.07, 0.24)
	b.material = m
	body.mesh = b
	root.add_child(body)
	var grip := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(0.045, 0.12, 0.05)
	gb.material = m
	grip.mesh = gb
	grip.position = Vector3(0, -0.08, 0.06)
	grip.rotation_degrees.x = -12
	root.add_child(grip)
	var strip := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.052, 0.008, 0.18)
	var nm := StandardMaterial3D.new()
	nm.resource_name = "NeonCyan"
	nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nm.albedo_color = Color("#22E5FF")
	sb.material = nm
	strip.mesh = sb
	strip.position.y = 0.02
	root.add_child(strip)
	var mz := Node3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(0, 0.0, -0.13)
	root.add_child(mz)
	root.position = Vector3(0.16, -0.15, -0.42)
	root.scale = Vector3.ONE * 0.7
	return root
