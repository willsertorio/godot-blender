class_name Brawler
extends Enemy
## Fast melee. Charges the player once it has seen them and strikes in close range.
## Telegraph: a red ring on the floor shows its reach; while the player is inside it the
## ring closes in, the spikes flare and the hum rises, then the strike lands.

const SPEED := 7.2
const REACH := 2.0

var body: Node3D
var ring: MeshInstance3D
var _motor: AudioStreamPlayer3D
var _lunge := 0.0


func _init() -> void:
	kind = "brawler"
	max_hp = 50.0
	score_value = 200
	damage = 16.0
	fire_time = 0.55
	recover_time = 0.55
	lock_range = REACH
	sight_range = 30.0
	eye_height = 0.8
	anim_names = {"idle": "Idle", "aware": "Idle", "move": "Run", "lock": "Idle", "attack": "Shoot", "hit": "Idle", "die": "Death"}
	move_clip_speed = 1.5   # SD-4 Run is authored at 1.5 m/s (in place); sped up to the charge speed


func _build_visual() -> void:
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.62
	shape.height = 1.3
	cs.shape = shape
	cs.position.y = 0.65
	add_child(cs)

	var model := _adopt_model("res://assets/models/sd4.glb")
	if model == null:
		model = _adopt_model("res://assets/models/brawler.glb")
	if model:
		body = model
	else:
		_greybox_body()
	_build_ring()


func _greybox_body() -> void:
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	var metal := body_metal()
	var red := neon_red()
	# Angular wedge core with a red visor slit and four forward spikes.
	var core := PrismMesh.new()
	core.size = Vector3(1.0, 0.9, 1.1)
	_mesh(core, metal, body, Vector3(0, 0.75, 0), Vector3(-PI / 2, 0, 0))
	var visor := BoxMesh.new()
	visor.size = Vector3(0.6, 0.07, 0.02)
	_mesh(visor, red, body, Vector3(0, 0.82, -0.52))
	for i in 4:
		var sp := PrismMesh.new()
		sp.size = Vector3(0.12, 0.55, 0.12)
		var x := -0.36 + i * 0.24
		_mesh(sp, red, body, Vector3(x, 0.45 + 0.06 * (i % 2), -0.58), Vector3(-PI / 2, 0, 0))
	var skirt := CylinderMesh.new()
	skirt.top_radius = 0.42
	skirt.bottom_radius = 0.55
	skirt.height = 0.25
	_mesh(skirt, metal, body, Vector3(0, 0.15, 0))
	var glow := TorusMesh.new()
	glow.inner_radius = 0.5
	glow.outer_radius = 0.56
	_mesh(glow, red, body, Vector3(0, 0.27, 0))


func _build_ring() -> void:
	ring = MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.96
	tor.outer_radius = 1.0
	tor.rings = 32
	ring.mesh = tor
	ring.material_override = MaterialLib.neon(Enemy.HOSTILE, 1.5)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.03
	ring.scale = Vector3(REACH, 0.2, REACH)
	ring.visible = false
	add_child(ring)
	_motor = Sfx.loop_3d("brawler_motor", self)


func _move(delta: float, los: bool) -> void:
	var dir := Vector3.ZERO
	if aggro:
		var flat := player.global_position - global_position
		flat.y = 0
		if not (los and flat.length() < REACH * 0.6):
			dir = _steer_dir(last_seen if not los else player.global_position, los, delta)
	var speed := SPEED * (1.0 + _lunge)
	velocity.x = move_toward(velocity.x, dir.x * speed, 40.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 40.0 * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	_face(dir if dir.length() > 0 else (player.global_position - global_position), body, delta, 12.0)
	body.position.y = absf(sin(Time.get_ticks_msec() * 0.018)) * 0.06 * clampf(velocity.length() / SPEED, 0, 1)
	if _motor:
		var moving := velocity.length() > 0.5
		if moving and not _motor.playing:
			_motor.play()
		elif not moving and _motor.playing:
			_motor.stop()
		_motor.pitch_scale = 0.8 + velocity.length() / SPEED * 0.6
	_lunge = maxf(0.0, _lunge - delta * 3.0)


func _fire() -> void:
	super._fire()
	_lunge = 1.0
	Sfx.play_at("melee", eye_position())


func _telegraph(frac: float, active: bool) -> void:
	_glow(frac)
	ring.visible = aggro or capture_frac >= 0.0
	var m := ring.material_override as ShaderMaterial
	var s := REACH * (1.0 - 0.55 * frac) if active else REACH
	ring.scale = Vector3(s, 0.2, s)
	m.set_shader_parameter("energy", (2.6 + frac * 4.0) if active else 0.8)
	m.set_shader_parameter("flicker", 0.7 if frac > 0.6 else 0.0)
