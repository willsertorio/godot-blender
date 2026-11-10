class_name Player
extends CharacterBody3D
## First-person controller: WASD + mouse look, mouse captured while playing.
## Stopped by anything on the WORLD layer (walls, closed doors, pillars).

signal died
signal damaged(amount: float)
signal picked_up(payoff: String)
signal kit_used

const EYE_HEIGHT := 1.6
const WALK_SPEED := 6.0
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
	var speed := WALK_SPEED * (ADS_SPEED_MULT if ads else 1.0)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	var target_fov := FOV * (0.62 if ads else 1.0)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-14.0 * delta))
	if viewmodel and viewmodel.camera:
		var vm_fov := ViewmodelRig.FOV * (0.85 if ads else 1.0)
		viewmodel.camera.fov = lerpf(viewmodel.camera.fov, vm_fov, 1.0 - exp(-14.0 * delta))


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
