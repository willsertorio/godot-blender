class_name V2Player
extends CharacterBody3D
## First-person preview player of the V2 lab: walks, and holds the V2 weapon views (gun + rigged arms exported
## from Blender with their clips). The view hangs from the camera exactly as it hangs from the camera in Blender.

const WEAPONS := ["pistol", "rifle"]
const FLASH := {"pistol": "P_Flash", "rifle": "R_Flash"}
const ADS_IN := {"pistol": 0.3, "rifle": 99.0}     # pistol: the aim is held while the button is down
const ADS_OUT := {"pistol": 0.25, "rifle": 0.3}
const EYE := 1.62

var cam: Camera3D
var weapon := "pistol"
var busy := ""                    # the one-shot clip that is playing ("" = idle / walk)
var mouse_look := true
var auto_move := Vector3.ZERO       # walks by itself in this direction (local; for the capture tour)
var _views: Dictionary = {}
var _yaw := 0.0
var _pitch := 0.0
var _kick := 0.0
var _layer := 1


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	shape.shape = capsule
	shape.position.y = 0.875
	add_child(shape)
	cam = Camera3D.new()
	cam.position.y = EYE
	cam.keep_aspect = Camera3D.KEEP_WIDTH           # the Blender camera: 80 degrees across
	cam.fov = V2Assets.data().camera.fov_h
	cam.near = 0.03
	cam.far = 120.0
	add_child(cam)
	cam.make_current()
	var fill := OmniLight3D.new()                  # a little light on the gun and hands, wherever the player stands
	fill.light_energy = 0.3
	fill.omni_range = 2.2
	fill.position = Vector3(0.1, 0.15, 0.1)
	cam.add_child(fill)
	for w in WEAPONS:
		var scene: Node3D = (load(V2Assets.DIR + "view_" + w + ".glb") as PackedScene).instantiate()
		cam.add_child(scene)
		V2Assets.apply(scene)
		var eye := scene.find_child("Eye", true, false) as Node3D
		# "Eye" is the Blender camera (converted to Y-up): put it on this camera. A Blender camera looks down its
		# -Z with +Y up, as Godot's does, but the export turned its frame a quarter turn about X.
		scene.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO) * eye.transform.affine_inverse()
		var ap := V2Assets.clips(scene, "view_" + w)
		ap.animation_finished.connect(_on_finished)
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_views[w] = {"scene": scene, "ap": ap, "flashes": V2Fx.flashes(scene)}
		scene.visible = w == weapon
	_ap().play("Idle")


## Put the gun and arms on a room's render layer (its lights only reach that layer).
func set_layer(layer: int) -> void:
	if layer == _layer:
		return
	_layer = layer
	for w in _views:
		for n in (_views[w].scene as Node).find_children("*", "VisualInstance3D", true, false):
			(n as VisualInstance3D).layers = layer


func _ap() -> AnimationPlayer:
	return _views[weapon].ap


func flash_on() -> bool:
	for f in _views[weapon].flashes:
		if f.on:
			return true
	return false


## Play a one-shot clip of the current weapon (Fire, ADS, Reload, Draw, Inspect, Sprint ...).
func act(clip: String) -> void:
	var ap := _ap()
	if not ap.has_animation(clip):
		return
	if busy != "" and not (busy == "Fire" and clip == "Fire" and weapon == "pistol" and ap.current_animation_position > 0.2):
		return
	busy = clip
	ap.play(clip)
	ap.seek(0.0, true)


func switch_weapon() -> void:
	_views[weapon].scene.visible = false
	weapon = WEAPONS[(WEAPONS.find(weapon) + 1) % WEAPONS.size()]
	_views[weapon].scene.visible = true
	busy = ""
	act("Draw")


func _on_finished(_anim: StringName) -> void:
	busy = ""


## (_input, not _unhandled_input: looking and shooting must not depend on what the HUD does with the mouse)
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0022
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			act("Fire")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			act("ADS")
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				act("Reload" if weapon == "pistol" else "ReloadTactical")
			KEY_T:
				act("Reload" if weapon == "pistol" else "ReloadEmpty")
			KEY_F:
				act("Inspect")
			KEY_Q:
				switch_weapon()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if auto_move != Vector3.ZERO:
		dir = auto_move
	var sprint := Input.is_key_pressed(KEY_SHIFT) and dir.z < 0.0
	dir = (Basis(Vector3.UP, _yaw) * dir).normalized()
	var speed := 6.2 if sprint else 3.4
	velocity.x = move_toward(velocity.x, dir.x * speed, 40.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 40.0 * delta)
	velocity.y -= 15.0 * delta
	if is_on_floor() and Input.is_key_pressed(KEY_SPACE):
		velocity.y = 5.0
	move_and_slide()
	if sprint and busy == "" and is_on_floor():
		act("Sprint")


func _process(delta: float) -> void:
	_kick = move_toward(_kick, 0.0, delta * 0.18)
	rotation.y = _yaw
	cam.rotation.x = _pitch + _kick
	var ap := _ap()
	if busy == "ADS" and ap.is_playing():          # hold the aim while the button is down
		var a := ap.get_animation("ADS")
		var t := ap.current_animation_position
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and t >= ADS_IN[weapon] and t < a.length - ADS_OUT[weapon] - 0.05:
			ap.seek(ADS_IN[weapon], true)
	if busy == "":
		var want := "Walk" if Vector2(velocity.x, velocity.z).length() > 0.6 and is_on_floor() else "Idle"
		if ap.current_animation != want:
			ap.play(want, 0.15)
	for node in V2Fx.poll(_views[weapon].flashes):   # a round leaves the muzzle
		var from := (node as Node3D).global_position
		var aim := -cam.global_basis.z
		var to := cam.global_position + aim * 60.0
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, to)
		q.exclude = [get_rid()]
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty():
			to = res.position
			var robot: V2Robot = res.collider.get_meta("robot") if res.collider.has_meta("robot") else null
			V2Fx.impact(to, res.normal, robot != null)
			if robot != null:
				robot.hit()
		V2Fx.tracer(from, to, V2Fx.YELLOW)
		_kick += 0.012 if weapon == "pistol" else 0.006
