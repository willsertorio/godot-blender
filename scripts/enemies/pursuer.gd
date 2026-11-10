class_name Pursuer
extends Enemy
## Hovering, in between: follows the player through rooms and corridors and holds a
## middle distance, firing a medium-speed lock. Telegraph: a pulsing red core plus a
## targeting beam like the turret's (shorter lock, lighter hit).

const SPEED := 4.2
const HOVER := 2.1
const NEAR := 6.0
const FAR := 11.0

var body: Node3D
var core: MeshInstance3D
var muzzle: Node3D
var beam: MeshInstance3D
var _shot_flash := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _hover_sfx: AudioStreamPlayer3D


func _init() -> void:
	kind = "pursuer"
	max_hp = 55.0
	score_value = 150
	damage = 9.0
	fire_time = 1.05
	recover_time = 0.6
	lock_range = 22.0
	sight_range = 30.0
	eye_height = HOVER


func _build_visual() -> void:
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.55
	cs.shape = shape
	cs.position.y = HOVER
	add_child(cs)

	body = Node3D.new()
	body.name = "Body"
	body.position.y = HOVER
	add_child(body)
	var metal := body_metal()
	var red := neon_red()
	var shell := SphereMesh.new()
	shell.radius = 0.36
	shell.height = 0.72
	shell.radial_segments = 16
	shell.rings = 8
	_mesh(shell, metal, body)
	core = _mesh(_sphere(0.17), red, body, Vector3(0, 0, -0.3))
	for a in [0.0, PI / 2]:
		var r := TorusMesh.new()
		r.inner_radius = 0.48
		r.outer_radius = 0.54
		_mesh(r, red, body, Vector3.ZERO, Vector3(PI / 2, a, 0))
	for sx in [-1, 1]:
		var fin := BoxMesh.new()
		fin.size = Vector3(0.5, 0.05, 0.32)
		_mesh(fin, metal, body, Vector3(sx * 0.62, 0, 0.05))
	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -0.45)
	body.add_child(muzzle)
	beam = _make_beam(self)
	_hover_sfx = Sfx.loop_3d("pursuer_hover", body)


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	return s


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not dead and _hover_sfx and not _hover_sfx.playing and aggro:
		_hover_sfx.play()


func _move(delta: float, los: bool) -> void:
	var dir := Vector3.ZERO
	if aggro:
		var flat := player.global_position - global_position
		flat.y = 0
		var dist := flat.length()
		if los:
			_strafe_t -= delta
			if _strafe_t <= 0.0:
				_strafe_t = randf_range(1.2, 2.4)
				_strafe = -_strafe
			var side := flat.normalized().cross(Vector3.UP) * _strafe
			if dist > FAR:
				dir = flat.normalized()
			elif dist < NEAR:
				dir = -flat.normalized() * 0.8
			dir += side * 0.6
		else:
			dir = _steer_dir(last_seen, false, delta)
	velocity.x = move_toward(velocity.x, dir.x * SPEED, 12.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * SPEED, 12.0 * delta)
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0
	body.position.y = HOVER + sin(Time.get_ticks_msec() * 0.003 + get_instance_id()) * 0.12
	var look := player.global_position + Vector3.UP * 1.3 - body.global_position
	_face(look, body, delta, 6.0)


func _fire() -> void:
	super._fire()
	_shot_flash = 1.0
	Sfx.play_at("enemy_fire", muzzle.global_position, -3.0)


func _telegraph(frac: float, active: bool) -> void:
	_glow(frac)
	var pulse := 1.0 + frac * 0.6 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03 * (1.0 + frac * 2.0)))
	core.scale = Vector3.ONE * pulse
	_shot_flash = maxf(0.0, _shot_flash - get_physics_process_delta_time() * 7.0)
	if (active and frac > 0.01) or _shot_flash > 0.0:
		var r := 0.005 + frac * 0.014 + _shot_flash * 0.04
		aim_beam(beam, muzzle.global_position, player.global_position + Vector3.UP * 1.3, r)
		var m := beam.material_override as ShaderMaterial
		m.set_shader_parameter("energy", 0.8 + frac * 3.0 + _shot_flash * 6.0)
		m.set_shader_parameter("flicker", 0.7 if frac > 0.75 and _shot_flash == 0.0 else 0.0)
	else:
		beam.visible = false
