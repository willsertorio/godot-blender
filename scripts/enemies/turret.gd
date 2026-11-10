class_name Turret
extends Enemy
## Stationary. Shoots from across a room: long lock range, slow lock, heavy hit.
## Telegraph: a thin red targeting laser from `Muzzle` to the player that thickens and
## flickers as the lock completes, the head's neon charging, and a rising hum.
## Nodes `Head` and `Muzzle` match the hero model contract (CLAUDE.md).

var head: Node3D
var muzzle: Node3D
var beam: MeshInstance3D
var _shot_flash := 0.0


func _init() -> void:
	kind = "turret"
	max_hp = 70.0
	score_value = 100
	damage = 13.0
	fire_time = 1.5
	recover_time = 0.7
	lock_range = 34.0
	sight_range = 34.0
	eye_height = 1.55


func _build_visual() -> void:
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.55
	shape.height = 1.9
	cs.shape = shape
	cs.position.y = 0.95
	add_child(cs)

	var metal := body_metal()
	var red := neon_red()
	var base := CylinderMesh.new()
	base.top_radius = 0.45
	base.bottom_radius = 0.6
	base.height = 0.5
	_mesh(base, metal, self, Vector3(0, 0.25, 0))
	var mast := CylinderMesh.new()
	mast.top_radius = 0.16
	mast.bottom_radius = 0.22
	mast.height = 0.9
	_mesh(mast, metal, self, Vector3(0, 0.9, 0))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.44
	ring.outer_radius = 0.5
	_mesh(ring, red, self, Vector3(0, 0.5, 0))

	head = Node3D.new()
	head.name = "Head"
	head.position.y = eye_height
	add_child(head)
	var hb := BoxMesh.new()
	hb.size = Vector3(0.62, 0.42, 0.7)
	_mesh(hb, metal, head)
	var eye := BoxMesh.new()
	eye.size = Vector3(0.44, 0.08, 0.02)
	_mesh(eye, red, head, Vector3(0, 0.05, -0.36))
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.06
	barrel.bottom_radius = 0.08
	barrel.height = 0.55
	_mesh(barrel, metal, head, Vector3(0, -0.08, -0.6), Vector3(PI / 2, 0, 0))
	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, -0.08, -0.9)
	head.add_child(muzzle)
	beam = _make_beam(self)


func _move(delta: float, los: bool) -> void:
	if los:
		var target := player.global_position + Vector3.UP * 1.3
		var local := head.global_position.direction_to(target)
		_face(local, head, delta, 6.0)
		head.rotation.x = lerp_angle(head.rotation.x, asin(clampf(local.y, -1, 1)), 1.0 - exp(-6.0 * delta))


func _fire() -> void:
	super._fire()
	_shot_flash = 1.0
	Sfx.play_at("enemy_fire", muzzle.global_position)


func _telegraph(frac: float, active: bool) -> void:
	_glow(frac)
	_shot_flash = maxf(0.0, _shot_flash - get_physics_process_delta_time() * 7.0)
	if (active and frac > 0.01) or _shot_flash > 0.0:
		var target := player.global_position + Vector3.UP * 1.3
		var r := 0.006 + frac * 0.018 + _shot_flash * 0.05
		aim_beam(beam, muzzle.global_position, target, r)
		var m := beam.material_override as ShaderMaterial
		m.set_shader_parameter("energy", 1.0 + frac * 3.0 + _shot_flash * 6.0)
		m.set_shader_parameter("flicker", 0.7 if frac > 0.75 and _shot_flash == 0.0 else 0.0)
	else:
		beam.visible = false
