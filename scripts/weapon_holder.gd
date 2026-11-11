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
		# XM9 (modelled from scratch, gloves included): red-dot window centre 7.7 cm above the grip origin.
		"model": "res://assets/models/xm9.glb", "hip": Vector3(0.16, -0.15, -0.4), "ads": Vector3(0.0, -0.0766, -0.3),
		"clips": "res://assets/models/xm9_clips.json", "root": "XM9", "shot": [3, 12],
		"casing": "res://assets/models/casing_9mm.glb", "eject_v": Vector3(1.4, 1.6, 0.25),
		# Grip markers (weapon frame: -Z barrel, +Y up): [position, rotation deg]; [] = no hand.
		"grip_r": [Vector3(0, -0.03, 0.012), Vector3(-18, 0, 0), Vector3.LEFT], "grip_l": []},
	"rifle": {"damage": 12.0, "interval": 0.095, "auto": true, "spread": 0.035, "ads_spread": 0.009,
		"range": 90.0, "sound": "rifle", "kick": 0.55, "mag": 30, "reload": 1.5,
		# XM-R4: magnifier / holo line 13.1 cm above the pistol-grip origin.
		"model": "res://assets/models/xmr4.glb", "hip": Vector3(0.11, -0.12, -0.22), "hip_rot": Vector3(-2, 14, -6), "ads": Vector3(0.0, -0.131, -0.14),
		"clips": "res://assets/models/xmr4_clips.json", "root": "XMR4", "shot": [2, 5],
		"casing": "res://assets/models/casing_556.glb", "eject_v": Vector3(1.6, 1.3, -0.15),
		"grip_r": [Vector3(0, -0.035, 0.0), Vector3(-15, 0, 0), Vector3.LEFT],
		# support hand under the handguard: handle axis along the barrel, palm up
		"grip_l": [Vector3(0, -0.03, -0.3), Vector3(0, 0, 0), Vector3.UP]},
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
## Firing blocks sprinting briefly (Player reads this).
var sprint_block := 0.0
# Viewmodel motion state: springs for recoil (position + rotation), smoothed sway / pose.
var _rk_pos := Vector3.ZERO
var _rk_pos_v := Vector3.ZERO
var _rk_rot := Vector3.ZERO
var _rk_rot_v := Vector3.ZERO
var _sway := Vector2.ZERO
var _pose_pos := Vector3.ZERO
var _pose_rot := Vector3.ZERO
var _t := 0.0
var _reload_mag_dropped := false
## Clip-driven guns (from-scratch models): weapon -> AnimationPlayer; scripted brass in flight.
var _anim: Dictionary = {}
var _casings: Array = []
var _casing_scenes: Dictionary = {}


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
	for k in models:
		ViewmodelRig.adopt(models[k])


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
	ViewmodelRig.adopt(flash_sprite)

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
		flash_sprite.visible = _fx > 0.3 and not _anim.has(current)
		tracer.visible = _fx > 0.15
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			_finish_reload()
	if switching > 0.0:
		switching -= delta

	_animate(delta)
	_update_casings(delta)
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
	if Input.is_action_just_pressed("arm_style"):
		cycle_arm_mode()
	var w: Dictionary = WEAPONS[current]
	var want := Input.is_action_pressed("fire") if w.auto else Input.is_action_just_pressed("fire")
	if want:
		try_fire()


func switch_to(w: String) -> void:
	if w == current:
		return
	if reloading > 0.0:
		_rest_pose(current)
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
	_reload_mag_dropped = false
	_play_clip("rifle", "Reload", WEAPONS.rifle.reload)
	Sfx.play("reload_out")
	changed.emit()
	return true


func _finish_reload() -> void:
	var need: int = WEAPONS.rifle.mag - mag
	var take := mini(need, reserve)
	mag += take
	reserve -= take
	reloading = 0.0
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
	_recoil(w)
	_fx = 1.0
	flash_light.light_energy = 3.0
	flash_sprite.visible = not _anim.has(current)   # clip guns carry their own 3D flash
	_play_clip(current, "Shot", float(w.interval))
	_eject_casing()
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
	Enemy.aim_beam(tracer, _muzzle_in_world(), end, 0.007)
	tracer.visible = true
	fired.emit(current)


## The muzzle is drawn by the viewmodel camera (different FOV): find the world point that
## appears at the same spot on screen, so tracers leave the barrel you see.
func _muzzle_in_world() -> Vector3:
	var mz := muzzle().global_position
	var rig: ViewmodelRig = player.viewmodel
	if rig == null or rig.camera == null:
		return mz
	var screen := rig.camera.unproject_position(mz)
	var depth := player.camera.global_position.distance_to(mz)
	return player.camera.project_position(screen, depth)


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


## Arm styles (H cycles them in the lab; --arms=model|hands|full|none):
##   model: the rigid hand model posed on each grip (blender/scripts/pose_rigid_hand.py + the poses tuned
##          in blender/hands_<gun>.blend), gun frame
##   hands: gloved hands built around each handle (blender/scripts/build_hands.py), gun frame
##   full:  WRAD ARMS posed per gun (blender/scripts/pose_wrad.py), camera frame -> placed at -hip
##   none:  floating guns
const ARM_MODES := ["model", "hands", "full", "none"]
static var arm_mode := "model"


func _attach_arms(model: Node3D, w: String) -> void:
	for spec in [["model", "res://assets/models/rigid_%s.glb" % w, Vector3.ZERO],
			["hands", "res://assets/models/hands_%s.glb" % w, Vector3.ZERO],
			["full", "res://assets/models/arms_%s.glb" % w, -(WEAPONS[w].hip as Vector3)]]:
		if not ResourceLoader.exists(spec[1]):
			continue
		var a := (load(spec[1]) as PackedScene).instantiate() as Node3D
		a.name = "Arms_" + spec[0]
		model.add_child(a)
		a.position = spec[2]
		MaterialLib.rebind_tree(a)
		# The hand-model file may carry a "GunBody" empty: where the gun mesh sits for those hands
		# (moved / turned / scaled in blender/hands_<gun>.blend), in the gun model's frame.
		var gb := a.find_child("GunBody", true, false) as Node3D
		if spec[0] == "model" and gb:
			model.set_meta("model_body", _rel(gb, model))
	_apply_arm_mode(model)


static func _under_arms(n: Node, root: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != root:
		if String(p.name).begins_with("Arms_"):
			return true
		p = p.get_parent()
	return false


## Transform of `n` relative to its ancestor `root`.
static func _rel(n: Node3D, root: Node) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != root and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _apply_arm_mode(model: Node3D) -> void:
	for m in ARM_MODES:
		var n := model.get_node_or_null("Arms_" + m) as Node3D
		if n:
			n.visible = m == arm_mode
	# Gun mesh + Muzzle follow the hand model's GunBody offset only while that style is shown.
	var off: Transform3D = model.get_meta("model_body", Transform3D()) if arm_mode == "model" else Transform3D()
	var targets: Array = model.find_children("*Body", "MeshInstance3D", true, false)
	targets.append_array(model.find_children("Muzzle", "", true, false))
	for n in targets:
		if not (n is Node3D) or _under_arms(n, model):
			continue
		var nd := n as Node3D
		if not nd.has_meta("rest"):
			nd.set_meta("rest", nd.transform)
		var parent_t := _rel(nd.get_parent() as Node3D, model) if nd.get_parent() != model else Transform3D()
		nd.transform = parent_t.affine_inverse() * off * parent_t * (nd.get_meta("rest") as Transform3D)


func cycle_arm_mode() -> void:
	arm_mode = ARM_MODES[(ARM_MODES.find(arm_mode) + 1) % ARM_MODES.size()]
	for k in models:
		_apply_arm_mode(models[k])
	print("[arms] ", arm_mode)


## pose = [position, rotation(, scale)]: rotation is Euler degrees (Vector3) or a Basis.
static func set_arm_pose(arm: Node3D, pose: Array) -> void:
	arm.position = pose[0]
	if pose[1] is Basis:
		arm.basis = pose[1]
	else:
		arm.rotation_degrees = pose[1]
	if pose.size() > 2:
		arm.scale = Vector3.ONE * float(pose[2])


## The Quaternius weapon (normalized) or the greybox fallback.
func _load_model(w: String, fallback: Callable) -> Node3D:
	var path: String = WEAPONS[w].model
	if not ResourceLoader.exists(path):
		return fallback.call()
	var m := (load(path) as PackedScene).instantiate() as Node3D
	MaterialLib.rebind_tree(m)
	assert(m.find_child("Muzzle", true, false) != null, path + " has no Muzzle")
	m.position = WEAPONS[w].hip
	var spec: Dictionary = WEAPONS[w]
	if spec.has("clips"):
		# Gloves are part of the model; clips cut from the baked timeline, root kick left to _recoil().
		var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
		AnimUtil.split_clips(ap, spec.clips, [spec.root], {"Shot": spec.shot})
		_anim[w] = ap
		_rest_pose(w)
		if ResourceLoader.exists(spec.casing):
			_casing_scenes[w] = load(spec.casing)
	else:
		_attach_arms(m, w)
	return m


## Hold the first frame of Fire (gloves in their grip pose, every part at rest).
func _rest_pose(w: String) -> void:
	var ap: AnimationPlayer = _anim.get(w)
	if ap == null or not ap.has_animation("Fire"):
		return
	ap.play("Fire")
	ap.seek(0.0, true)
	ap.pause()


## Play a clip once, sped up to last `duration` seconds (0 = natural speed).
func _play_clip(w: String, clip: String, duration := 0.0) -> void:
	var ap: AnimationPlayer = _anim.get(w)
	if ap == null or not ap.has_animation(clip):
		return
	var length := ap.get_animation(clip).length
	var speed := maxf(1.0, length / duration) if duration > 0.0 else 1.0
	ap.stop()
	ap.play(clip, 0.0, speed)


## Brass: flies out of the Eject marker (right, up, a little back), spins, drops; lives in weapon space.
func _eject_casing() -> void:
	var sc: PackedScene = _casing_scenes.get(current)
	var ej := view_model.find_child("Eject", true, false) as Node3D
	if sc == null or ej == null:
		return
	var c := sc.instantiate() as Node3D
	MaterialLib.rebind_tree(c)
	add_child(c)
	c.global_transform = ej.global_transform
	ViewmodelRig.adopt(c)
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var v: Vector3 = WEAPONS[current].eject_v
	v = v * randf_range(0.85, 1.15) + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.1, 0.1))
	_casings.append({"node": c, "v": view_model.basis * v, "spin": Vector3(randf_range(-30, 30), randf_range(10, 25), randf_range(-20, 20)), "t": 0.0})


func _update_casings(delta: float) -> void:
	for i in range(_casings.size() - 1, -1, -1):
		var c: Dictionary = _casings[i]
		var n: Node3D = c.node
		if not is_instance_valid(n):
			_casings.remove_at(i)
			continue
		c.t += delta
		c.v += Vector3(0, -9.8, 0) * delta
		n.position += c.v * delta
		n.rotation += c.spin * delta
		if c.t > 0.6:
			n.queue_free()
			_casings.remove_at(i)


## Recoil impulse: the gun kicks back and up with a little random twist; the view is punched up.
func _recoil(w: Dictionary) -> void:
	## Big, readable kick: the gun slams back into the hand, muzzle flips up with a random
	## twist, the view climbs and shakes, and the FOV punches in a touch.
	var k: float = w.kick
	var ads_k := 0.6 if player.ads else 1.0
	_rk_pos_v += Vector3(randf_range(-0.25, 0.25), 0.45, 3.4) * k * ads_k
	_rk_rot_v += Vector3(26.0 * k, randf_range(-6.0, 6.0) * k, randf_range(-9.0, 9.0) * k) * ads_k
	player.add_punch((0.05 if w.auto else 0.075) * ads_k, randf_range(-0.018, 0.018) * ads_k)
	player.add_shake(0.35 * k * ads_k)
	sprint_block = 0.35


## Reload timeline (rifle, 0..1): tilt in, support hand drops away with the mag, comes back,
## slams it in (gun jolts), settles.
func _reload_pose(f: float) -> Array:
	var ease_in := smoothstep(0.0, 0.18, f)
	var ease_out := 1.0 - smoothstep(0.82, 1.0, f)
	var tilt := ease_in * ease_out
	var pos := Vector3(-0.03, -0.06, 0.04) * tilt
	var rot := Vector3(deg_to_rad(18), deg_to_rad(10), deg_to_rad(-38)) * tilt
	# Slam at 70 %: quick upward jolt.
	var slam := exp(-pow((f - 0.7) * 22.0, 2.0))
	pos += Vector3(0, 0.025, -0.01) * slam
	rot += Vector3(deg_to_rad(-6), 0, deg_to_rad(4)) * slam
	return [pos, rot]


## Reload: the support arm swings down out of view and back (rotation on its bicep bone).
func _support_hand(f: float) -> void:
	var away := smoothstep(0.15, 0.32, f) * (1.0 - smoothstep(0.48, 0.66, f)) if f > 0.0 else 0.0
	for hands in [view_model.get_node_or_null("Arms_hands"), view_model.find_child("HandModel", true, false)]:
		if hands == null:
			continue
		for n in hands.get_children():
			if n is Node3D and (String(n.name).begins_with("HandL") or String(n.name).begins_with("HandModelL")):
				if not n.has_meta("rest"):
					n.set_meta("rest", n.transform)
				n.transform = n.get_meta("rest")
				n.position += Vector3(-0.12, -0.3, 0.15) * away
	var sk := view_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return
	var b := sk.find_bone("bicep.l")
	if b < 0:
		return
	if not has_meta("bicep_rest_%s" % current):
		set_meta("bicep_rest_%s" % current, sk.get_bone_pose_rotation(b))
	var rest: Quaternion = get_meta("bicep_rest_%s" % current)
	sk.set_bone_pose_rotation(b, Quaternion(Vector3(0.4, 0, 1).normalized(), deg_to_rad(-55) * away) * rest)


func _animate(delta: float) -> void:
	_t += delta
	sprint_block = maxf(0.0, sprint_block - delta)
	var w0: Dictionary = WEAPONS[current]
	var ads := player.ads
	# Base pose + state poses (run / crouch).
	var base: Vector3 = w0.ads if ads else w0.hip
	var pose_pos := base
	# Hip framing angle (deg, Godot YXZ), matched to blender/scripts/lib_arm.py VIEWS: muzzle toward the centre.
	var pose_rot: Vector3 = Vector3.ZERO if ads else (w0.get("hip_rot", Vector3.ZERO) as Vector3) * (PI / 180.0)
	# Guns framed close to the eye (hip_rot set) get gentler state poses so they never swing across the view.
	var close := w0.has("hip_rot")
	if player.running:
		pose_pos += Vector3(-0.04, -0.06, 0.03) if not close else Vector3(0.0, -0.07, 0.02)
		pose_rot += Vector3(deg_to_rad(-12), deg_to_rad(28 if not close else 6), deg_to_rad(12 if not close else 8))
	elif player.crouching and not ads:
		pose_pos += Vector3(-0.015, 0.01, 0.0)
		pose_rot += Vector3(0, 0, deg_to_rad(-6))
	var lower := 0.0
	if switching > 0.0:
		var sf := clampf(switching / SWITCH_TIME, 0, 1)
		lower = sin(sf * PI) * 0.22
		pose_rot.x += -sin(sf * PI) * 0.5
	var rf := 0.0
	if reloading > 0.0:
		rf = 1.0 - reloading / WEAPONS.rifle.reload
		var rp := _reload_pose(rf)
		var rk := 0.4 if close else 1.0
		pose_pos += rp[0] * rk
		pose_rot += rp[1] * rk
		if close:
			pose_pos.y -= 0.035 * smoothstep(0.0, 0.18, rf) * (1.0 - smoothstep(0.82, 1.0, rf))
		if rf > 0.66 and not _reload_mag_dropped:
			_reload_mag_dropped = true
			Sfx.play("reload_in")
	_support_hand(rf)
	var k := 1.0 - exp(-(18.0 if ads else 11.0) * delta)
	_pose_pos = _pose_pos.lerp(pose_pos + Vector3(0, -lower, 0), k)
	_pose_rot = _pose_rot.lerp(pose_rot, k)

	# Sway: the gun lags behind the look direction, then catches up.
	var ld := player.look_delta
	player.look_delta = Vector2.ZERO
	var sway_k := 0.35 if ads else 1.0
	_sway = _sway.lerp(Vector2(clampf(-ld.x * 0.0009, -0.06, 0.06), clampf(ld.y * 0.0009, -0.05, 0.05)) * sway_k, 1.0 - exp(-10.0 * delta))
	# Walk bob in figure-8, bigger when running; breathing when still.
	var m := clampf(player.move_speed_frac, 0.0, 1.6)
	var ph := player._bob_phase
	var bob_amp := (0.016 if player.running else 0.009) * m * (0.25 if ads else 1.0)
	var bob := Vector3(cos(ph * 0.5) * bob_amp, -absf(sin(ph * 0.5)) * bob_amp * 1.2, 0)
	var bob_rot := Vector3(0, 0, cos(ph * 0.5) * bob_amp * 1.8)
	var still := 1.0 - clampf(m, 0.0, 1.0)
	var breath := Vector3(sin(_t * 0.9) * 0.0015, sin(_t * 1.6) * 0.0035, 0) * still * (0.35 if ads else 1.0)
	var land := Vector3(0, -0.05, 0.01) * player.landed

	# Recoil springs.
	# Fixed 1/240 s sub-steps: explicit springs this stiff go unstable on long frames.
	var left := minf(delta, 0.1)
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		left -= h
		_rk_pos_v += (-_rk_pos * 300.0 - _rk_pos_v * 24.0) * h
		_rk_pos += _rk_pos_v * h
		_rk_rot_v += (-_rk_rot * 240.0 - _rk_rot_v * 20.0) * h
		_rk_rot += _rk_rot_v * h

	view_model.position = _pose_pos + bob + breath + land + Vector3(_sway.x, _sway.y, 0) * 0.5 \
		+ Vector3(_rk_pos.x * 0.02, _rk_pos.y * 0.02, _rk_pos.z * 0.05)
	view_model.rotation = _pose_rot + bob_rot + Vector3(_sway.y * 1.5 + deg_to_rad(_rk_rot.x), _sway.x * 2.0 + deg_to_rad(_rk_rot.y), -_sway.x * 1.5 + deg_to_rad(_rk_rot.z))


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
