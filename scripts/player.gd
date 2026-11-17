class_name Player
extends CharacterBody3D
## First-person controller: WASD + mouse look, mouse captured while playing.
## Stopped by anything on the WORLD layer (walls, closed doors, pillars).

signal died
signal damaged(amount: float)
signal picked_up(payoff: String)
signal kit_used

const EYE_HEIGHT := 1.6
const CROUCH_EYE := 1.05
const WALK_SPEED := 6.0
const RUN_MULT := 1.6
const CROUCH_MULT := 0.5
const JUMP_VELOCITY := 5.0
const GRAVITY := 15.0
const ADS_SPEED_MULT := 0.45
const MOUSE_SENS := 0.0022
const FOV := 80.0
const RADIUS := 0.4
const MAX_KITS := 3
const KIT_HEAL := 40.0

var max_health := 100.0
var health := 100.0
var alive := true
var input_enabled := true
var ads := false
var kits := 0
## Tests / capture tour: take no damage.
var invulnerable := false
## Mouse look starts this many ms after spawn / re-capture (see _unhandled_input).
var _look_ready_ms := 0
## Movement state, read by WeaponHolder for viewmodel motion.
var running := false
var crouching := false
var move_speed_frac := 0.0  # horizontal speed / walk speed
var look_delta := Vector2.ZERO  # mouse motion since last frame (sway)
var landed := 0.0  # impact strength of the last landing (decays)
var _bob_phase := 0.0
var _eye := EYE_HEIGHT
var _was_on_floor := true
var _fall_speed := 0.0
## View punch (recoil kick on the camera, recovers by itself): pitch, yaw in radians.
var punch := Vector2.ZERO
var _punch_vel := Vector2.ZERO
var _shake := 0.0
var _shape: CapsuleShape3D
var _shape_node: CollisionShape3D

var head: Node3D
var camera: Camera3D
var viewmodel: ViewmodelRig
var weapons: WeaponHolder


func _ready() -> void:
	add_to_group("player")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.HOSTILE
	floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_shape = cap
	_shape_node = cs

	head = Node3D.new()
	head.name = "Head"
	head.position.y = EYE_HEIGHT
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 120.0
	camera.current = true
	head.add_child(camera)

	viewmodel = ViewmodelRig.new()
	viewmodel.name = "Viewmodel"
	add_child(viewmodel)
	viewmodel.setup(camera, get_world_3d().environment)

	weapons = WeaponHolder.new()
	weapons.name = "Weapons"
	camera.add_child(weapons)
	weapons.setup(self)
	hold_look()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Ignore the burst a browser can deliver as pointer lock engages, and clamp spikes.
		if Time.get_ticks_msec() < _look_ready_ms:
			return
		var rel: Vector2 = event.relative.limit_length(250.0)
		look_delta += rel
		var sens := MOUSE_SENS * (0.6 if ads else 1.0)
		rotate_y(-rel.x * sens)
		head.rotation.x = clampf(head.rotation.x - rel.y * sens, -1.45, 1.45)
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("use_kit"):
		use_kit()


func hold_look(ms: int = 150) -> void:
	_look_ready_ms = Time.get_ticks_msec() + ms


func _physics_process(delta: float) -> void:
	ads = input_enabled and alive and Input.is_action_pressed("aim")
	var wish := Vector2.ZERO
	if input_enabled and alive:
		wish = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(wish.x, 0, wish.y))
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	var can_act := input_enabled and alive
	crouching = can_act and Input.is_action_pressed("crouch")
	# Run: forward-ish only, not while aiming, crouching or firing (see WeaponHolder.sprint_block).
	running = can_act and Input.is_action_pressed("sprint") and wish.y < -0.3 and not ads and not crouching \
		and weapons.sprint_block <= 0.0
	var speed := WALK_SPEED
	if ads:
		speed *= ADS_SPEED_MULT
	elif crouching:
		speed *= CROUCH_MULT
	elif running:
		speed *= RUN_MULT
	# A little acceleration so starts and stops don't snap.
	var accel := 40.0 if is_on_floor() else 8.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	if is_on_floor():
		velocity.y = 0.0
		if can_act and Input.is_action_just_pressed("jump") and not crouching:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	move_and_slide()
	if is_on_floor() and not _was_on_floor:
		landed = clampf(_fall_speed / 7.0, 0.25, 1.0)
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()
	landed = move_toward(landed, 0.0, delta * 2.5)
	move_speed_frac = Vector2(velocity.x, velocity.z).length() / WALK_SPEED if is_on_floor() else 0.0
	_update_head(delta)
	var target_fov := FOV * (0.62 if ads else 1.0) * (1.0 - _shake * 0.025)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-14.0 * delta))
	if viewmodel and viewmodel.camera:
		var vm_fov := ViewmodelRig.FOV * (0.85 if ads else 1.0)
		viewmodel.camera.fov = lerpf(viewmodel.camera.fov, vm_fov, 1.0 - exp(-14.0 * delta))


## Crouch height, head bob, breathing, landing dip and view punch on the camera.
func _update_head(delta: float) -> void:
	var target_eye := CROUCH_EYE if crouching else EYE_HEIGHT
	_eye = lerpf(_eye, target_eye, 1.0 - exp(-10.0 * delta))
	_shape.height = lerpf(_shape.height, 1.25 if crouching else 1.8, 1.0 - exp(-10.0 * delta))
	_shape_node.position.y = _shape.height * 0.5
	var t := Time.get_ticks_msec() / 1000.0
	# Steps: phase advances with distance walked (stride ~ 2.2 m per cycle).
	_bob_phase += move_speed_frac * WALK_SPEED * delta / 2.2 * TAU
	var amp := (0.035 if running else 0.022) * clampf(move_speed_frac, 0.0, 1.4) * (0.3 if ads else 1.0)
	var bob := Vector3(cos(_bob_phase * 0.5) * amp * 0.8, -absf(sin(_bob_phase * 0.5)) * amp * 1.6, 0)
	# Breathing: always on, smaller when aiming.
	var breath := sin(t * 1.6) * 0.006 * (0.4 if ads else 1.0)
	head.position = Vector3(0, _eye - landed * 0.12, 0) + bob + Vector3(0, breath, 0)
	# Punch spring (critically damped-ish).
	var left := minf(delta, 0.1)
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		left -= h
		_punch_vel += (-punch * 180.0 - _punch_vel * 22.0) * h
		punch += _punch_vel * h
	_shake = move_toward(_shake, 0.0, delta * 7.0)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * _shake * 0.012
	camera.rotation = Vector3(punch.x, punch.y, -cos(_bob_phase * 0.5) * amp * 0.25 + sin(t * 0.8) * 0.002) + sh


## Recoil kick on the view (radians); recovers by itself.
func add_punch(pitch: float, yaw: float) -> void:
	_punch_vel += Vector2(pitch, yaw) * 30.0


## Short camera shake (decays in ~0.15 s) and a small FOV punch.
func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)


func _try_interact() -> void:
	## Nearest interactable within its range; no prompt is ever shown (GDD).
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		if not n.can_interact():
			continue
		var p: Vector3 = n.interact_point()
		var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
		if d <= n.interact_range() and d < best_d:
			best = n
			best_d = d
	if best:
		best.interact(self)


## Spend a carried kit. Refused (no kit spent) at full health.
func use_kit() -> bool:
	if kits <= 0 or health >= max_health or not alive:
		return false
	kits -= 1
	heal(KIT_HEAL)
	Sfx.play("use_kit")
	kit_used.emit()
	return true


func take_damage(amount: float, _source: Node = null) -> void:
	if not alive or invulnerable:
		return
	health = maxf(0.0, health - amount)
	Sfx.play("hurt")
	Sfx.play("hurt_glitch")
	damaged.emit(amount)
	if health <= 0.0:
		alive = false
		died.emit()


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)


func look_at_point(p: Vector3) -> void:
	## Aim body yaw + head pitch at a world point (used by the capture tool).
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var d := p - eye
	rotation.y = DungeonGen.yaw_facing(d)
	head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
