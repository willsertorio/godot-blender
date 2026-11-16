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
# sounds timed to the clips: clip -> [[seconds, sound key], ...] (the moments are the ones in v2/scripts/anim_*.py)
const CUES := {
	"pistol": {"Reload": [[0.12, "pistol_mag_out"], [0.84, "pistol_mag_in"], [1.14, "slide"]], "Draw": [[0.05, "handling"]],
		"ADS": [[0.02, "handling"]], "AimOut": [[0.02, "handling"]], "Inspect": [[0.25, "handling"], [1.5, "handling"]]},
	"rifle": {"ReloadTactical": [[0.32, "rifle_mag_out"], [1.12, "rifle_mag_in"]],
		"ReloadEmpty": [[0.32, "rifle_mag_out"], [1.12, "rifle_mag_in"], [1.58, "bolt"]],
		"Draw": [[0.05, "handling"]], "ADS": [[0.02, "handling"]], "AimOut": [[0.02, "handling"]],
		"Inspect": [[0.3, "handling"], [1.6, "handling"]]},
}
const EYE := 1.62
const EYE_CROUCH := 1.0
const HEIGHT := 1.75                # the capsule, standing / crouched
const HEIGHT_CROUCH := 1.15
const GUN_LAYER := 1 << 10          # render layer of the gun and arms: drawn by their own camera, over the world
const AIM_ZOOM := 0.78              # the world camera's field of view while aiming (x the normal one)
const DAMAGE := {"pistol": 34.0, "rifle": 12.0}
const MAX_HP := 100.0
const REGEN_AFTER := 4.0            # seconds without a hit before health comes back
const REGEN := 15.0                 # health per second
# the game's rules (`rules`): magazines, the machine gun's reserve, med kits
const MAG := {"pistol": 15, "rifle": 30}
const RESERVE_MAX := 240
const KIT_HEAL := 40.0
const MAX_KITS := 3

signal died
signal interact                     # E: the game opens the door or the crate the player stands at

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
var hurt_from := Vector3.ZERO       # where the round that hit came from (the HUD shows the side)
var hit_confirm := 0.0              # > 0 just after one of the player's rounds hit a robot
var shots_hit := 0
var bot_aim := false                # the aim held by code (the checks)
var bot_jump := false               # a jump asked for by code (the bot at a wreck)
var locked := false                 # no moving, looking or shooting (the run's opening: the gun is still coming up)
var hurt_amount := 0.0              # how much the last round took (the HUD blurs the picture by it)
var _hurt_snd := 0.0
var bot_fire := false               # the trigger held by code (the game's bot and checks)
var grab := true                    # a click captures the mouse when it is free (the lab); the game's menu does it itself
var rules := false                  # the game: magazines run out, health does not come back by itself (the lab: neither)
var mag := {"pistol": 15, "rifle": 30}      # rounds in each gun
var reserve := 60                   # machine gun rounds carried; the pistol's never run out
var kits := 0
var _want_reload := false           # the magazine ran dry: reload as soon as the hands are free
var _dry_t := 0.0
var _since_hurt := 99.0
var _grace := 0.0
var _sprinting := false
var crouched := false               # X toggles
var _eye := EYE                     # eye height now (eases between standing and crouched)
var _capsule: CapsuleShape3D
var _shape: CollisionShape3D
var view_cam: Camera3D              # draws the gun and arms only, in a transparent viewport over the world
var overlay: CanvasLayer
static var world_env: Environment   # set by the lab before the player is made: the gun's camera uses a copy
var _clock := 0.0
var _cue := {"clip": "", "pos": 0.0}
var _stride := 0.5                  # where the walk is between two footfalls, 0..1
var _running := false               # Shift held and going forward (whatever the gun is doing)
# going down under the game's rules: the player falls onto their side and lies there, the gun drops in front
const FALL := 0.8                   # seconds from standing to the floor
const LIE := 0.17                   # the eye's height lying down
var fallen := -1.0                  # seconds since going down (-1 = standing)
var dropped: Node3D                 # the gun on the floor
var _fall_side := 1.0               # +1 = onto the left side
var _fall_from := Vector2.ZERO      # [eye height, pitch] when it began
var _drop_from := Transform3D.IDENTITY
var _drop_to := Transform3D.IDENTITY
var _drop_t := -1.0
var _thud := false
var steps := 0                      # footfalls heard so far (the checks)
var _air := false
var _rounds := 0
var _aimed := 0.0                   # 1 = the gun is up at the eye
var last_aim := Vector3.FORWARD     # where the last round went (for the checks)
var _shot_dir := Vector3.FORWARD    # the pistol's aim (world) when its trigger was pulled
var _settle := 0.0                  # the pistol's barrel is not yet back where its aim is measured from
var aim_dot := Vector2(-1, -1)      # where the rounds will go, on the screen (the HUD's cursor); (-1, -1) = hidden
var shot_times: Array[float] = []    # when each round left (seconds since start): for the gun check
var worst_bend := 0.0               # largest angle between a round's path and the barrel it left (degrees)


func _ready() -> void:
	_shape = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = HEIGHT
	_shape.shape = _capsule
	_shape.position.y = HEIGHT / 2.0
	add_child(_shape)
	cam = Camera3D.new()
	cam.position.y = EYE
	cam.keep_aspect = Camera3D.KEEP_WIDTH           # the Blender camera: 80 degrees across
	cam.fov = V2Assets.data().camera.fov_h
	cam.near = 0.03
	cam.far = 120.0
	cam.cull_mask &= ~GUN_LAYER                     # (the world camera does not draw the gun)
	add_child(cam)
	cam.make_current()
	var fill := OmniLight3D.new()                  # a little light on the gun and hands, wherever the player stands
	fill.light_energy = 0.1
	fill.omni_range = 2.2
	fill.position = Vector3(0.1, 0.15, 0.1)
	fill.light_cull_mask = GUN_LAYER
	cam.add_child(fill)
	_view_overlay()
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
		# The aim is held on a still clip cut from ADS at its aimed moment, and lowered by the clip's tail: the
		# player never has to park a running clip by seeking it every frame. (That was how the aim was held, and
		# while another clip was fading out, e.g. after a burst, a frame now and then came out with the arms in
		# their rest pose: a hand beside the gun.)
		var ads_len := ap.get_animation("ADS").length
		V2Assets.sub_clip(ap, "ADS", ADS_IN[w], ADS_IN[w], "AimHold")
		V2Assets.sub_clip(ap, "ADS", ads_len - ADS_OUT[w], ads_len, "AimOut")
		var flash_node := scene.find_child(FLASH[w], true, false) as Node3D
		# The machine gun's rounds go where its barrel points, and the cursor shows where that is. In the Blender
		# view the gun is held toed in (its barrel points 6 degrees left of and 4 above the line of sight), which
		# is why its tracers looked bent toward the middle of the screen. So the whole view is turned about the eye
		# until the barrel is parallel to the line of sight (found from the Idle clip): a barrel parallel to the
		# view points at the middle of the screen, whatever its place in the picture.
		var fix := Quaternion.IDENTITY
		var fire: Dictionary = {}
		var mean := Vector3.ZERO
		var idle_len := ap.get_animation("Idle").length
		ap.play("Idle")
		for k in 12:
			ap.seek(idle_len * k / 12.0, true)
			mean += -(cam.global_transform.affine_inverse() * flash_node.global_transform).basis.z.normalized()
		# The pistol's view is not turned (its picture stays as it was made: its barrel rests 9 degrees off the
		# line of sight). Its rounds and its cursor leave the middle of the screen by as much as the barrel has
		# left its place of rest: at the hip that place is the Idle clip's mean, at the eye the aimed pose.
		var rest := Quaternion(mean.normalized(), Vector3.FORWARD)
		ap.play("ADS")
		ap.seek(ADS_IN[w], true)
		var rest_aim := Quaternion(-(cam.global_transform.affine_inverse() * flash_node.global_transform).basis.z.normalized(), Vector3.FORWARD)
		if w in AUTO:
			fix = rest
			var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(V2Assets.DIR + "view_" + w + "_clips.json"))
			fire = spec.get("fire", {})
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for n in scene.find_children("*", "VisualInstance3D", true, false):
			if not (n is Light3D):
				(n as VisualInstance3D).layers = GUN_LAYER
		_views[w] = {"scene": scene, "ap": ap, "flashes": V2Fx.flashes(scene), "events": V2Assets.flash_events("view_" + w), "ev": {},
			"kick": scene.find_child("CamKick", true, false), "seat": seat, "fix": fix, "flash": flash_node, "rest": rest, "rest_aim": rest_aim,
			"loop": [fire.loop[0] / 24.0, fire.loop[1] / 24.0] if fire.has("loop") else []}
		scene.visible = w == weapon
	_ap().play("Idle")


## The gun and arms are drawn by a camera of their own into a transparent viewport laid over the world, under the
## HUD: a wall the player walks up to cannot cut into the gun (it is a separate picture), and the world camera can
## zoom while aiming without the gun growing with it. The camera sits on the world camera every frame and keeps
## the Blender camera's field of view. Same world, so the room's lights and shadows fall on the gun (the lab
## lets the lights of the room the player is in reach GUN_LAYER).
func _view_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 1                              # over the 3D view; the lab's HUD is on layer 5
	add_child(overlay)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(box)
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.handle_input_locally = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = get_viewport().msaa_3d
	box.add_child(vp)
	view_cam = Camera3D.new()
	view_cam.keep_aspect = Camera3D.KEEP_WIDTH
	view_cam.fov = V2Assets.data().camera.fov_h
	view_cam.near = 0.01
	view_cam.far = 8.0
	view_cam.cull_mask = GUN_LAYER
	# the world's look without fog and glow (glow on a transparent picture leaves halos)
	var env := world_env.duplicate() as Environment if world_env != null else Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.fog_enabled = false
	env.glow_enabled = false
	view_cam.environment = env
	vp.add_child(view_cam)
	view_cam.current = true


## Where a robot aims: the chest (lower when crouched).
func chest() -> Vector3:
	return global_position + Vector3(0.0, _eye - 0.47, 0.0)


func set_crouch(on: bool) -> void:
	if (on and not down) != crouched:
		V2Sfx.play("crouch")
	crouched = on and not down


func aiming() -> bool:
	return bot_aim or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_key_pressed(KEY_C)


## A round from a robot.
func hurt(damage: float, from: Vector3) -> void:
	if down or invulnerable or _grace > 0.0:
		return
	hurt_from = from
	hurt_amount = damage
	hp -= damage
	if _clock - _hurt_snd > 0.16:                      # (a turret's burst is twelve rounds a second: not twelve grunts)
		_hurt_snd = _clock
		V2Sfx.play("hurt")
	hurt_flash = 1.0
	_since_hurt = 0.0
	if hp <= 0.0:
		hp = 0.0
		down = true
		V2Sfx.play("down")
		if rules:
			_go_down(from)
		died.emit()


## Down for good (the game): the fall begins, away from the side the round came from; the gun leaves the hands.
func _go_down(from: Vector3) -> void:
	fallen = 0.0
	_thud = false
	_fall_from = Vector2(_eye, _pitch)
	var to := from - global_position
	_fall_side = 1.0 if to.dot(global_basis.x) > 0.0 else -1.0      # (hit from the right: over onto the left side)
	busy = ""
	bot_fire = false
	_drop_gun()


## The camera of a player who is down: `t` seconds into the fall. Falls faster and faster, rolls onto the side,
## meets the floor with a small bounce, and lies looking along it.
func _fallen_view(t: float) -> Transform3D:
	var k := clampf(t / FALL, 0.0, 1.0)
	var drop := k * k
	var after := maxf(t - FALL, 0.0)
	var bounce := 0.03 * sin(minf(after / 0.26, 1.0) * PI) + 0.008 * sin(minf(maxf(after - 0.26, 0.0) / 0.16, 1.0) * PI)
	var roll := _fall_side * deg_to_rad(83.0) * smoothstep(0.0, 1.0, k) - _fall_side * deg_to_rad(4.0) * sin(minf(after / 0.4, 1.0) * PI)
	var pitch := lerpf(_fall_from.y, 0.03, smoothstep(0.0, 1.0, k))
	var basis := Basis(Vector3(0, 0, 1), roll) * Basis(Vector3.RIGHT, pitch)
	return Transform3D(basis, Vector3(-_fall_side * 0.24 * drop, lerpf(_fall_from.x, LIE, drop) + bounce, -0.1 * drop))


## The gun leaves the hands and lands on the floor in front of the player: a copy of the view's gun without the
## arms, in the world (the view itself, which only the gun's camera draws, is switched off).
func _drop_gun() -> void:
	var live: Node3D = _views[weapon].scene
	var copy := (load(V2Assets.DIR + "view_" + weapon + ".glb") as PackedScene).instantiate() as Node3D
	V2Assets.apply(copy, "view_" + weapon)
	dropped = Node3D.new()
	get_parent().add_child(dropped)
	dropped.add_child(copy)
	var ap := V2Assets.clips(copy, "view_" + weapon)
	ap.play("Idle")
	ap.advance(0.0)
	ap.active = false
	for n in copy.find_children("ArmRig*", "", true, false):
		n.queue_free()
	var layer := int(V2Fx.layer_at.call(global_position)) if V2Fx.layer_at.is_valid() else 1
	var box := AABB()
	var first := true
	for n in copy.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var hidden := String(mi.name).contains("Flash") or String(mi.name).contains("Casing") or String(mi.name).contains("Magazine2") \
			or mi.find_parent("ArmRig*") != null
		if hidden or mi.scale.x < 0.01:
			mi.visible = false
			continue
		mi.layers = layer
		var part := (dropped.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	copy.position = -box.get_center()
	# from the hands ...
	_drop_from = live.global_transform * Transform3D(Basis.IDENTITY, box.get_center())
	# ... to the floor, on its side, a little to the side the player falls to, where the lying eye looks
	var fwd := -global_basis.z
	var lie := Basis(Vector3.UP, _yaw + randf_range(0.5, 1.1) * _fall_side) * Basis(Vector3(0, 0, 1), PI / 2.0 * _fall_side)
	var thick: float = minf(box.size.x, box.size.y)
	_drop_to = Transform3D(lie, Vector3(global_position.x, global_position.y + thick / 2.0 + 0.004, global_position.z)
		+ fwd * (0.95 if weapon == "pistol" else 1.25) - global_basis.x * _fall_side * 0.32)
	dropped.global_transform = _drop_from
	_drop_t = 0.0
	overlay.visible = false


func _drop_step(delta: float) -> void:
	if _drop_t < 0.0 or dropped == null:
		return
	var was := _drop_t
	_drop_t += delta
	var k := clampf(_drop_t / 0.55, 0.0, 1.0)
	var hop := 0.05 * sin(clampf((_drop_t - 0.55) / 0.22, 0.0, 1.0) * PI)              # one small hop where it lands
	var pos := _drop_from.origin.lerp(_drop_to.origin, k)
	pos.y = lerpf(_drop_from.origin.y, _drop_to.origin.y, k * k) + hop
	var q := _drop_from.basis.get_rotation_quaternion().slerp(_drop_to.basis.get_rotation_quaternion(), smoothstep(0.0, 1.0, k))
	dropped.global_transform = Transform3D(Basis(q), pos)
	if was < 0.55 and _drop_t >= 0.55:
		V2Sfx.play("bolt", pos, -5.0, 0.8)                 # steel on the floor
	if _drop_t > 0.8:
		_drop_t = -1.0
		dropped.global_transform = _drop_to


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
	if clip == "Fire" and rules and mag[weapon] <= 0:
		if _dry_t <= 0.0 and busy in ["", "ADS"]:
			_dry_t = 0.4
			V2Sfx.play("dry")                              # the click of an empty gun
			_want_reload = true
		return
	if clip == "Fire" and busy in ["ADS", "ADSFire"]:
		clip = "ADSFire"
		if busy == "ADS" and ap.current_animation != &"AimHold":
			return                                      # (not up at the eye yet, or on its way down)
	if not ap.has_animation(clip):
		return
	var again := busy == clip and clip in ["Fire", "ADSFire"] and not (weapon in AUTO) and ap.current_animation_position > 0.2
	var from_aim := busy == "ADS" and clip == "ADSFire"
	var from_sprint := busy == "Sprint" and clip != "Sprint"      # anything may interrupt a sprint
	if busy != "" and not (again or from_aim or from_sprint):
		return
	if clip in ["Fire", "ADSFire"] and not (weapon in AUTO):
		# (in the world's frame: by the time the clip's flash comes the camera itself has kicked up with the recoil,
		# and an aimed round went a degree or two over what the cursor was on)
		_shot_dir = (cam.global_basis * _pistol_off()).normalized()
	busy = clip
	ap.play(clip, 0.06 if from_aim else (0.12 if from_sprint else -1.0))
	ap.seek(0.0, true)


## Footsteps fall with the walk the player sees: the Walk clip's bob is lowest twice a second, the Sprint clip's
## every 0.35 s, and a step sounds as the camera reaches the bottom. (They were spaced by distance, 0.8 m: four a
## second at a walk, twice what the view shows.) While another clip plays (firing, a reload), the same pace by
## the clock.
const STEP_WALK := 0.5
const STEP_RUN := 0.35
const STEP_CROUCH := 0.62


func _footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if down or not is_on_floor() or speed < 0.6:
		_stride = 0.5                                  # (the first step comes half a pace after setting off)
		return
	var ap := _ap()
	var pos := ap.current_animation_position
	var last := _stride
	if ap.current_animation == &"Walk" and not crouched:
		_stride = fposmod(pos / STEP_WALK, 1.0)
	elif ap.current_animation == &"Sprint" and pos > SPRINT[weapon][0]:
		_stride = fposmod((pos - SPRINT[weapon][0]) / STEP_RUN - 0.5, 1.0)
	else:
		_stride += delta / (STEP_CROUCH if crouched else (STEP_RUN if _sprinting else STEP_WALK))
	if _stride >= 1.0 or _stride < last - 0.5:         # past the bottom of the bob
		_stride = fposmod(_stride, 1.0)
		steps += 1
		V2Sfx.play("step", Vector3.INF, 3.0 if _sprinting else (-5.0 if crouched else 0.0))


## Leave a held clip (automatic fire, sprint) for the rest pose, or for the aim it was fired from.
func _release() -> void:
	var ap := _ap()
	if weapon in AUTO and busy in ["Fire", "ADSFire"]:
		V2Sfx.play("rifle_tail")                        # the burst dies away (each round's own tail is cut short)
	if busy == "ADSFire":
		busy = "ADS"
		ap.play("AimHold", 0.12)
	else:
		busy = ""                                      # (_process blends into Idle / Walk)


## R: the reload that fits what is in the gun. False if there is nothing to do (full, or no rounds to put in).
func reload() -> bool:
	if not rules and (_running or busy == "Sprint"):
		return false
	if not rules:
		act("Reload" if weapon == "pistol" else "ReloadTactical")
		return true
	if mag[weapon] >= MAG[weapon] or (weapon == "rifle" and reserve <= 0):
		return false
	if _running or busy == "Sprint":                   # not at a run: the hands are busy with the gun
		return false
	if busy == "ADS":
		busy = ""
	act("Reload" if weapon == "pistol" else ("ReloadEmpty" if mag[weapon] <= 0 else "ReloadTactical"))
	return busy.begins_with("Reload")


## The fresh magazine is in (the moment of the clip's "magazine in" sound).
func _fill() -> void:
	if weapon == "pistol":
		mag[weapon] = MAG[weapon]
	else:
		var take: int = mini(MAG[weapon] - mag[weapon], reserve)
		mag[weapon] += take
		reserve -= take


## What a crate gives. Each returns false if the player has no use for it (it then stays where it lies).
func add_ammo(rounds: int) -> bool:
	if reserve >= RESERVE_MAX:
		return false
	reserve = mini(reserve + rounds, RESERVE_MAX)
	return true


func add_health(points: float) -> bool:
	if hp >= MAX_HP or down:
		return false
	hp = minf(hp + points, MAX_HP)
	return true


func add_kit() -> bool:
	if kits >= MAX_KITS:
		return false
	kits += 1
	return true


## H: a med kit.
func use_kit() -> bool:
	if kits <= 0 or hp >= MAX_HP or down:
		return false
	kits -= 1
	hp = minf(hp + KIT_HEAL, MAX_HP)
	V2Sfx.play("heal")
	return true


func select_weapon(w: String) -> void:
	if w != weapon and w in WEAPONS and not down:
		switch_weapon()


func switch_weapon() -> void:
	_want_reload = false
	_views[weapon].scene.visible = false
	weapon = WEAPONS[(WEAPONS.find(weapon) + 1) % WEAPONS.size()]
	_views[weapon].scene.visible = true
	busy = ""
	act("Draw")


func _on_finished(anim: StringName) -> void:
	if anim == &"ADSFire" and busy == "ADSFire":
		_release()
	elif anim == &"AimHold":
		pass
	elif anim == &"ADS" and busy == "ADS" and aiming():
		_ap().play("AimHold", 0.05)                    # (the clip ran out with the button still down)
	else:
		busy = ""


## (_input, not _unhandled_input: looking and shooting must not depend on what the HUD does with the mouse)
func _input(event: InputEvent) -> void:
	if down or locked:
		return
	if event is InputEventMouseMotion and mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := 0.0022 * lerpf(1.0, AIM_ZOOM, _aimed)        # (slower while zoomed in: the same hand movement, the same picture)
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if grab:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			act("Fire")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			act("ADS")
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				reload()
			KEY_T:
				if not rules:
					act("Reload" if weapon == "pistol" else "ReloadEmpty")
			KEY_E:
				interact.emit()
			KEY_H:
				if rules:
					use_kit()
			KEY_1:
				if rules:
					select_weapon("pistol")
			KEY_2:
				if rules:
					select_weapon("rifle")
			KEY_F:
				act("Inspect")
			KEY_Q:
				switch_weapon()
			KEY_C:
				act("ADS")                              # aim: held, like the right mouse button
			KEY_X:
				set_crouch(not crouched)
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
	if down or locked:
		dir = Vector3.ZERO
	var jump := (Input.is_key_pressed(KEY_SPACE) or bot_jump) and not locked
	bot_jump = false
	var sprint := Input.is_key_pressed(KEY_SHIFT) and dir.z < 0.0 and not busy.begins_with("Reload")      # (no running through a reload)
	_running = sprint
	if sprint or (is_on_floor() and jump):
		crouched = false                               # (running and jumping stand the player up)
	dir = (Basis(Vector3.UP, _yaw) * dir).normalized()
	var speed := 6.2 if sprint else (1.7 if crouched else 3.4)
	# crouching: the eye and the capsule come down together
	_eye = move_toward(_eye, 0.32 if (down and rules) else (EYE_CROUCH if crouched else EYE), 3.2 * delta)
	var h := lerpf(HEIGHT_CROUCH, HEIGHT, clampf(inverse_lerp(EYE_CROUCH, EYE, _eye), 0.0, 1.0))
	if absf(_capsule.height - h) > 0.001:
		_capsule.height = h
		_shape.position.y = h / 2.0
	velocity.x = move_toward(velocity.x, dir.x * speed, 40.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 40.0 * delta)
	velocity.y -= 15.0 * delta
	if is_on_floor() and jump:
		velocity.y = 5.0
	if is_on_floor() and velocity.y > 4.0:
		V2Sfx.play("jump")
	var fall := -velocity.y
	move_and_slide()
	if is_on_floor() and _air and fall > 2.5:          # a thud on landing (the footsteps: _footsteps)
		V2Sfx.play("land")
	_air = not is_on_floor()
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
	_dry_t = maxf(_dry_t - delta, 0.0)
	if rules and _want_reload and busy in ["", "ADS"] and not down and not _running:
		_want_reload = false
		reload()
	if not rules and not down and _since_hurt > REGEN_AFTER:
		hp = minf(hp + REGEN * delta, MAX_HP)
	rotation.y = _yaw
	# The camera: the player's pitch, then the camera motion of the gun's clip (view punch, walk bob, burst
	# shake: the CamKick node of the view, which is in the Blender camera's frame = this camera's turned 90 degrees).
	var ct := Transform3D(Basis(Vector3.RIGHT, _pitch + _kick), Vector3(0, _eye, 0))
	var kick: Node3D = _views[weapon].kick
	if fallen >= 0.0:
		fallen += delta
		ct = _fallen_view(fallen)
		if not _thud and fallen >= FALL:
			_thud = true
			V2Sfx.play("land", Vector3.INF, 7.0, 0.8)
		_drop_step(delta)
	elif kick != null:
		var rx := Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
		ct = ct * (rx * kick.transform * rx.affine_inverse())
	cam.transform = ct
	var ap := _ap()
	var view: Dictionary = _views[weapon]
	var held := not down and not locked and (bot_fire or (mouse_look and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)))
	if busy == "ADS":                              # hold the aim while the button is down, then lower the gun
		if ap.current_animation == &"ADS" and aiming() and ap.current_animation_position >= ADS_IN[weapon]:
			ap.play("AimHold", 0.05)
		elif ap.current_animation == &"AimHold" and not aiming():
			ap.play("AimOut", 0.06)
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
	_footsteps(delta)
	# the view: turned so that the barrel is parallel to the line of sight, except while aiming (the aimed pose is
	# built on the line of sight already)
	var aimed := 0.0
	if busy == "ADSFire" or ap.current_animation == &"AimHold":
		aimed = 1.0
	elif busy == "ADS" and ap.current_animation == &"ADS":
		aimed = smoothstep(0.0, ADS_IN[weapon], ap.current_animation_position)
	elif busy == "ADS":                            # AimOut
		aimed = 1.0 - smoothstep(0.0, ADS_OUT[weapon], ap.current_animation_position)
	_aimed = move_toward(_aimed, aimed, delta * 8.0)
	# (out of a sprint, a reload, a draw the gun is still on its way back for a moment)
	_settle = 0.25 if busy in NO_CURSOR else maxf(_settle - delta, 0.0)
	(view.scene as Node3D).transform = Transform3D(Basis(Quaternion.IDENTITY.slerp(view.fix, 1.0 - _aimed)), Vector3.ZERO) * view.seat
	# aiming zooms the world a little (the gun keeps its own field of view); the gun's camera rides on the world's
	cam.fov = V2Assets.data().camera.fov_h * lerpf(1.0, AIM_ZOOM, smoothstep(0.0, 1.0, _aimed))
	view_cam.global_transform = cam.global_transform
	_cursor()
	# the clip's own sounds (magazine, slide, bolt, the gun shifting in the hands)
	var cue_clip := String(ap.current_animation)
	var cue_pos := ap.current_animation_position
	if cue_clip != _cue.clip or cue_pos < _cue.pos:
		_cue = {"clip": cue_clip, "pos": -0.001}
	for c in CUES[weapon].get(cue_clip, []):
		if c[0] > _cue.pos and c[0] <= cue_pos:
			V2Sfx.play(c[1])
			if rules and String(c[1]).ends_with("mag_in"):
				_fill()
	_cue.pos = cue_pos
	# automatic fire stops when the button is let go, once a round has left: no more rounds, the gun settles
	if weapon in AUTO and busy in ["Fire", "ADSFire"] and not held and ap.current_animation == busy:
		var first: Array = view.events.get(busy, [[0.0]])[0]
		if float(view.ev.get("pos", -1.0)) >= float(first[0]) and view.ev.get("clip", "") == busy:
			_release()
	for node in V2Fx.fired(ap, _views[weapon].events, _views[weapon].ev, _views[weapon].flashes):   # a round leaves the muzzle
		if rules:
			if mag[weapon] <= 0:
				continue                                   # (the clip had more rounds in it than the magazine)
			mag[weapon] -= 1
			if mag[weapon] <= 0:
				_want_reload = true
				if weapon in AUTO:
					_release.call_deferred()               # the gun stops; the reload follows
		var from := (node as Node3D).global_position
		# (the pistol's round leaves as the barrel stood when the trigger was pulled: by the time the clip's flash
		# comes round, a frame or two later, the muzzle is already on its way up)
		var aim := aim_dir() if weapon in AUTO else _shot_dir
		last_aim = aim
		var to := cam.global_position + aim * 60.0
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, to)
		q.exclude = [get_rid()]
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty():
			to = res.position
			var robot: V2Robot = res.collider.get_meta("robot") if res.collider.has_meta("robot") else null
			if robot == null and res.collider.has_meta("wreck"):       # (the box that makes a wreck solid: the wreck is struck)
				robot = res.collider.get_meta("wreck")
			V2Fx.impact(to, res.normal, robot != null)
			if robot != null:
				robot.hit(DAMAGE[weapon], aim, to, res.collider.get_meta("joint") if res.collider.has_meta("joint") else null)
				hit_confirm = 0.15
				shots_hit += 1
		shot_times.append(_clock)
		V2Sfx.play(weapon + "_shot")
		_rounds += 1
		if weapon == "pistol" or _rounds % 2 == 0:         # the case reaches the floor half a second later
			get_tree().create_timer(randf_range(0.42, 0.6)).timeout.connect(V2Sfx.play.bind("casing"))
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


## Where the next round goes: along the machine gun's barrel. The pistol: the line of sight, turned by as much as
## its barrel has left its place of rest (the muzzle flips 8.6 degrees up in a shot and is back in a quarter of
## a second: a second round fired as fast as the gun allows, 0.2 s later, still goes 2.4 degrees high).
func aim_dir() -> Vector3:
	if weapon in AUTO:
		return -(_views[weapon].flash as Node3D).global_basis.z.normalized()
	return (cam.global_basis * _pistol_off()).normalized()


## The pistol's aim in the camera's frame: forward, turned by what its barrel is off its place of rest.
func _pistol_off() -> Vector3:
	var view: Dictionary = _views[weapon]
	var ap := view.ap as AnimationPlayer
	var aimed := busy == "ADSFire" or ap.current_animation == &"AimHold"
	if _settle > 0.0 or (busy == "ADS" and not aimed) or busy in NO_CURSOR:
		return Vector3.FORWARD                         # (on its way up or down, or out of a sprint: no place of rest to measure from)
	var barrel := -(cam.global_transform.affine_inverse().basis * (view.flash as Node3D).global_basis).z.normalized()
	var off: Vector3 = ((view.rest_aim if aimed else view.rest) as Quaternion) * barrel
	var ang := off.angle_to(Vector3.FORWARD)
	if ang > deg_to_rad(12.0):
		return Vector3.FORWARD                         # (a clip fading into another has swung the gun away)
	# The gun's breathing and the walk's bob (up to 0.8 degrees) do not move the aim: a round fired at rest goes to
	# the middle of the screen, as it always did with this gun. Only the kick of a shot does.
	var keep := maxf(ang - deg_to_rad(1.2), 0.0)
	if keep <= 0.0:
		return Vector3.FORWARD
	return Vector3.FORWARD.slerp(off.normalized(), keep / ang)


## The cursor rides on the barrel: it climbs and jumps with the recoil, and sways a little with the gun.
func _cursor() -> void:
	var d := aim_dir()
	var fwd := -cam.global_basis.z
	var busy_base := busy
	if busy_base in NO_CURSOR or down or d.angle_to(fwd) > deg_to_rad(16.0):
		aim_dot = Vector2(-1, -1)
		return
	aim_dot = cam.unproject_position(cam.global_position + d * 40.0)
