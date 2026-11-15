class_name V2Player
extends CharacterBody3D
## First-person preview player of the V2 lab: walks, and holds the V2 weapon views (gun + rigged arms exported
## from Blender with their clips). The view hangs from the camera exactly as it hangs from the camera in Blender.

const WEAPONS := ["pistol", "rifle"]
const FLASH := {"pistol": "P_Flash", "rifle": "R_Flash"}
const ADS_IN := {"pistol": 0.3, "rifle": 0.25}     # the aim is held here while the button is down
const ADS_OUT := {"pistol": 0.25, "rifle": 0.3}
# Sprint clip: [seconds until the gun is down, seconds of running]. The running part is two strides: it is repeated
# for as long as the player sprints, and left at once when they stop.
const SPRINT := {"pistol": [0.25, 1.4], "rifle": [0.3, 1.4]}
const AUTO := ["rifle"]             # fires for as long as the button is held
const NO_CURSOR := ["Sprint", "Draw", "Reload", "ReloadTactical", "ReloadEmpty", "Inspect"]
const EYE := 1.62
const DAMAGE := {"pistol": 34.0, "rifle": 12.0}
const MAX_HP := 100.0
const REGEN_AFTER := 4.0            # seconds without a hit before health comes back
const REGEN := 15.0                 # health per second

signal died

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
var hp := MAX_HP
var down := false                   # health ran out: the lab puts the player back at the room's start
var invulnerable := false           # (capture tour, tests)
var hurt_flash := 0.0               # 1 when hit, fades: the HUD's red flash
var hit_confirm := 0.0              # > 0 just after one of the player's rounds hit a robot
var shots_hit := 0
var _since_hurt := 99.0
var _grace := 0.0
var _sprinting := false
var _clock := 0.0
var _aimed := 0.0                   # 1 = the gun is up at the eye
var aim_dot := Vector2(-1, -1)      # where the rounds will go, on the screen (the HUD's cursor); (-1, -1) = hidden
var shot_times: Array[float] = []    # when each round left (seconds since start): for the gun check
var worst_bend := 0.0               # largest angle between a round's path and the barrel it left (degrees)


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
	fill.light_energy = 0.1
	fill.omni_range = 2.2
	fill.position = Vector3(0.1, 0.15, 0.1)
	cam.add_child(fill)
	for w in WEAPONS:
		var scene: Node3D = (load(V2Assets.DIR + "view_" + w + ".glb") as PackedScene).instantiate()
		cam.add_child(scene)
		V2Assets.apply(scene, "view_" + w)
		var eye := scene.find_child("Eye", true, false) as Node3D
		# "Eye" is the Blender camera (converted to Y-up): put it on this camera. A Blender camera looks down its
		# -Z with +Y up, as Godot's does, but the export turned its frame a quarter turn about X.
		var seat := Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO) * eye.transform.affine_inverse()
		scene.transform = seat
		var ap := V2Assets.clips(scene, "view_" + w)
		ap.animation_finished.connect(_on_finished)
		var flash_node := scene.find_child(FLASH[w], true, false) as Node3D
		# The machine gun's rounds go where its barrel points, and the cursor shows where that is. In the Blender
		# view the gun is held toed in (its barrel points 6 degrees left of and 4 above the line of sight), which
		# is why its tracers looked bent toward the middle of the screen. So the whole view is turned about the eye
		# until the barrel is parallel to the line of sight (found from the Idle clip): a barrel parallel to the
		# view points at the middle of the screen, whatever its place in the picture.
		var fix := Quaternion.IDENTITY
		var fire: Dictionary = {}
		if w in AUTO:
			var mean := Vector3.ZERO
			var idle_len := ap.get_animation("Idle").length
			ap.play("Idle")
			for k in 12:
				ap.seek(idle_len * k / 12.0, true)
				mean += -(cam.global_transform.affine_inverse() * flash_node.global_transform).basis.z.normalized()
			fix = Quaternion(mean.normalized(), Vector3.FORWARD)
			var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(V2Assets.DIR + "view_" + w + "_clips.json"))
			fire = spec.get("fire", {})
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_views[w] = {"scene": scene, "ap": ap, "flashes": V2Fx.flashes(scene), "events": V2Assets.flash_events("view_" + w), "ev": {},
			"kick": scene.find_child("CamKick", true, false), "seat": seat, "fix": fix, "flash": flash_node,
			"loop": [fire.loop[0] / 24.0, fire.loop[1] / 24.0] if fire.has("loop") else []}
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


## A round from a robot.
func hurt(damage: float, _from: Vector3) -> void:
	if down or invulnerable or _grace > 0.0:
		return
	hp -= damage
	hurt_flash = 1.0
	_since_hurt = 0.0
	if hp <= 0.0:
		hp = 0.0
		down = true
		died.emit()


func revive() -> void:
	hp = MAX_HP
	down = false
	_grace = 2.0
	busy = ""


func _ap() -> AnimationPlayer:
	return _views[weapon].ap


func flash_on() -> bool:
	for f in _views[weapon].flashes:
		if f.on:
			return true
	return false


## Play a one-shot clip of the current weapon (Fire, ADS, Reload, Draw, Inspect, Sprint ...).
## Fire while aiming (ADS held) plays ADSFire and goes back to the aim.
func act(clip: String) -> void:
	var ap := _ap()
	if down:
		return
	if clip == "Fire" and busy in ["ADS", "ADSFire"]:
		clip = "ADSFire"
		if busy == "ADS" and ap.current_animation_position < ADS_IN[weapon] - 0.02:
			return                                      # (not up at the eye yet)
	if not ap.has_animation(clip):
		return
	var again := busy == clip and clip in ["Fire", "ADSFire"] and not (weapon in AUTO) and ap.current_animation_position > 0.2
	var from_aim := busy == "ADS" and clip == "ADSFire"
	var from_sprint := busy == "Sprint" and clip != "Sprint"      # anything may interrupt a sprint
	if busy != "" and not (again or from_aim or from_sprint):
		return
	busy = clip
	ap.play(clip, 0.06 if from_aim else (0.12 if from_sprint else -1.0))
	ap.seek(0.0, true)


## Leave a held clip (automatic fire, sprint) for the rest pose, or for the aim it was fired from.
func _release() -> void:
	var ap := _ap()
	if busy == "ADSFire":
		busy = "ADS"
		ap.play("ADS", 0.12)
		ap.seek(ADS_IN[weapon], true)
	else:
		busy = ""                                      # (_process blends into Idle / Walk)


func switch_weapon() -> void:
	_views[weapon].scene.visible = false
	weapon = WEAPONS[(WEAPONS.find(weapon) + 1) % WEAPONS.size()]
	_views[weapon].scene.visible = true
	busy = ""
	act("Draw")


func _on_finished(anim: StringName) -> void:
	if anim == &"ADSFire" and busy == "ADSFire":
		_release()
	else:
		busy = ""


## (_input, not _unhandled_input: looking and shooting must not depend on what the HUD does with the mouse)
func _input(event: InputEvent) -> void:
	if down:
		return
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
	if down:
		dir = Vector3.ZERO
	var sprint := Input.is_key_pressed(KEY_SHIFT) and dir.z < 0.0
	dir = (Basis(Vector3.UP, _yaw) * dir).normalized()
	var speed := 6.2 if sprint else 3.4
	velocity.x = move_toward(velocity.x, dir.x * speed, 40.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 40.0 * delta)
	velocity.y -= 15.0 * delta
	if is_on_floor() and Input.is_key_pressed(KEY_SPACE):
		velocity.y = 5.0
	move_and_slide()
	_sprinting = sprint and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 3.6
	if sprint and busy == "" and is_on_floor():
		act("Sprint")


func _process(delta: float) -> void:
	_clock += delta
	_kick = move_toward(_kick, 0.0, delta * 0.18)
	_since_hurt += delta
	_grace = maxf(_grace - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta * 2.5, 0.0)
	hit_confirm = maxf(hit_confirm - delta, 0.0)
	if not down and _since_hurt > REGEN_AFTER:
		hp = minf(hp + REGEN * delta, MAX_HP)
	rotation.y = _yaw
	# The camera: the player's pitch, then the camera motion of the gun's clip (view punch, walk bob, burst
	# shake: the CamKick node of the view, which is in the Blender camera's frame = this camera's turned 90 degrees).
	var ct := Transform3D(Basis(Vector3.RIGHT, _pitch + _kick), Vector3(0, EYE, 0))
	var kick: Node3D = _views[weapon].kick
	if kick != null:
		var rx := Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
		ct = ct * (rx * kick.transform * rx.affine_inverse())
	cam.transform = ct
	var ap := _ap()
	var view: Dictionary = _views[weapon]
	var held := not down and mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if busy == "ADS" and ap.is_playing():          # hold the aim while the button is down
		var a := ap.get_animation("ADS")
		var t := ap.current_animation_position
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and t >= ADS_IN[weapon] and t < a.length - ADS_OUT[weapon] - 0.05:
			ap.seek(ADS_IN[weapon], true)
	if busy == "Sprint":                           # the running part repeats while the player sprints; stopping leaves it at once
		var sp: Array = SPRINT[weapon]
		if not _sprinting and ap.current_animation_position > 0.1:
			_release()
		elif ap.current_animation_position >= sp[0] + sp[1]:
			ap.seek(ap.current_animation_position - sp[1], true)
	if weapon in AUTO and held and busy in ["", "ADS"]:
		act("Fire")                                    # the machine gun fires for as long as the button is held
	if busy == "":
		var want := "Walk" if Vector2(velocity.x, velocity.z).length() > 0.6 and is_on_floor() else "Idle"
		if ap.current_animation != want:
			ap.play(want, 0.18)
	# the view: turned so that the barrel is parallel to the line of sight, except while aiming (the aimed pose is
	# built on the line of sight already)
	var aimed := 0.0
	if busy == "ADSFire":
		aimed = 1.0
	elif busy == "ADS":
		var t2 := ap.current_animation_position
		aimed = smoothstep(0.0, ADS_IN[weapon], t2) * (1.0 - smoothstep(ap.current_animation_length - ADS_OUT[weapon], ap.current_animation_length, t2))
	_aimed = move_toward(_aimed, aimed, delta * 8.0)
	(view.scene as Node3D).transform = Transform3D(Basis(Quaternion.IDENTITY.slerp(view.fix, 1.0 - _aimed)), Vector3.ZERO) * view.seat
	_cursor()
	# automatic fire stops when the button is let go, once a round has left: no more rounds, the gun settles
	if weapon in AUTO and busy in ["Fire", "ADSFire"] and not held and ap.current_animation == busy:
		var first: Array = view.events.get(busy, [[0.0]])[0]
		if float(view.ev.get("pos", -1.0)) >= float(first[0]) and view.ev.get("clip", "") == busy:
			_release()
	for node in V2Fx.fired(ap, _views[weapon].events, _views[weapon].ev, _views[weapon].flashes):   # a round leaves the muzzle
		var from := (node as Node3D).global_position
		var aim := aim_dir()
		var to := cam.global_position + aim * 60.0
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, to)
		q.exclude = [get_rid()]
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty():
			to = res.position
			var robot: V2Robot = res.collider.get_meta("robot") if res.collider.has_meta("robot") else null
			V2Fx.impact(to, res.normal, robot != null)
			if robot != null:
				robot.hit(DAMAGE[weapon], aim)
				hit_confirm = 0.15
				shots_hit += 1
		shot_times.append(_clock)
		if from.distance_to(to) > 6.0 and weapon in AUTO:
			worst_bend = maxf(worst_bend, rad_to_deg(aim.angle_to(to - from)))
		V2Fx.tracer(from, to, V2Fx.YELLOW)
		V2Fx.puff(from, aim, V2Fx.GUNSMOKE, 0.1, 2, 0.6, 0.2, 0.4)
		_kick += 0.012 if weapon == "pistol" else 0.004
	# automatic fire: the middle of the clip repeats while the button is held
	if weapon in AUTO and busy in ["Fire", "ADSFire"] and not view.loop.is_empty():
		var pos := ap.current_animation_position
		if held and pos >= view.loop[1]:
			ap.seek(pos - (view.loop[1] - view.loop[0]), true)
			view.ev["pos"] = ap.current_animation_position        # (the rounds before this point are not fired again)


## Where the next round goes: along the machine gun's barrel (the pistol: the line of sight).
func aim_dir() -> Vector3:
	if weapon in AUTO:
		return -(_views[weapon].flash as Node3D).global_basis.z.normalized()
	return -cam.global_basis.z


## The cursor rides on the barrel: it climbs and jumps with the recoil, and sways a little with the gun.
func _cursor() -> void:
	var d := aim_dir()
	var fwd := -cam.global_basis.z
	var busy_base := busy
	if busy_base in NO_CURSOR or down or d.angle_to(fwd) > deg_to_rad(16.0):
		aim_dot = Vector2(-1, -1)
		return
	aim_dot = cam.unproject_position(cam.global_position + d * 40.0)
