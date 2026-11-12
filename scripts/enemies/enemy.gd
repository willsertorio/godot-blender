class_name Enemy
extends CharacterBody3D
## Base hostile construct. No projectiles (GDD): while an enemy has a clear line of
## sight to the player and the player is within `lock_range`, its lock timer fills;
## when it reaches `fire_time` the player takes `damage` at once (re-checked LOS).
## Losing the sight line drains the lock quickly. The telegraph (beam / glow / rising
## hum) is driven by lock / fire_time so damage never arrives unannounced.
##
## Subclasses implement _build_visual(), _move(delta, los) and _telegraph(frac, los).

signal died(enemy: Enemy)

const SIGHT_MASK := Layers.WORLD | Layers.PLAYER
## Hostile glow (eyes, beams, bursts): warm red-orange, in the Quaternius palette.
const HOSTILE := Color("#FF4A2B")
const DORMANT_DISTANCE := 48.0

var kind := "enemy"
var max_hp := 50.0
var hp := 50.0
var score_value := 100
var damage := 10.0
var fire_time := 1.2
var recover_time := 0.5
var lock_range := 20.0
var sight_range := 32.0
var eye_height := 1.2

var room := -1
var main  # Main node: player, layout, navigation
var player: Player
var lock := 0.0
var aggro := false
var last_seen := Vector3.ZERO
var dead := false
## Capture/test control: when frozen the AI does nothing; capture_frac >= 0 forces
## the telegraph to that fraction so a still frame shows it.
var frozen := false
var capture_frac := -1.0

## Animated model (Quaternius rig) and clip names per state; subclasses override names.
var model: Node3D
## Extra yaw if the model's face is not along -Z (Godot forward).
var model_yaw := 0.0
var anim: AnimationPlayer
var anim_names := {"idle": "Idle", "aware": "Look", "move": "Run", "lock": "Look", "attack": "Attack", "hit": "Hit", "die": "TurnOff"}
var _attack_t := 0.0
var _hit_t := 0.0
## From-scratch models: their Death clip does the falling, so the wreck is not dropped to the floor.
var wreck_falls := true
## Node names the game drives itself (stripped from every clip except Death), e.g. the turret's Yaw / Pitch.
var clip_strip: Array = []
## ... and the ones also stripped from Death (e.g. the turret keeps facing where it died).
var death_strip: Array = []
## Speed (m/s) the "move" clip is authored for; the clip is sped up / slowed to the real speed (0 = off).
var move_clip_speed := 0.0

var _path_timer := 0.0
var _next_cell := Vector2i(-9999, -9999)
var _hit_flash := 0.0
var _neon_mats: Array[ShaderMaterial] = []
var _hum: AudioStreamPlayer3D


# Virtual: subclasses override.
func _build_visual() -> void:
	pass


func _move(_delta: float, _los: bool) -> void:
	pass


func _telegraph(_frac: float, _active: bool) -> void:
	pass


func setup(p_main, p_room: int, hp_mult: float) -> void:
	main = p_main
	player = p_main.player
	room = p_room
	max_hp *= hp_mult
	hp = max_hp


func _ready() -> void:
	add_to_group("hostiles")
	collision_layer = Layers.HOSTILE
	collision_mask = Layers.WORLD | Layers.HOSTILE | Layers.PLAYER
	_build_visual()
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m = (mi as MeshInstance3D).material_override
		if m is ShaderMaterial:
			_neon_mats.append(m)
	_hum = Sfx.loop_3d("telegraph", self)
	DungeonBuilder.limit_view_range(self)
	_hum.position.y = eye_height


func _physics_process(delta: float) -> void:
	if dead or player == null:
		return
	_hit_flash = maxf(0.0, _hit_flash - delta * 6.0)
	_attack_t = maxf(0.0, _attack_t - delta)
	_hit_t = maxf(0.0, _hit_t - delta)
	if frozen:
		_telegraph(maxf(capture_frac, 0.0), capture_frac >= 0.0)
		_update_hum(maxf(capture_frac, 0.0), capture_frac >= 0.0)
		_update_anim(maxf(capture_frac, 0.0), capture_frac >= 0.0)
		return
	var to_player := player.global_position - global_position
	if to_player.length() > DORMANT_DISTANCE:
		_telegraph(0.0, false)
		_update_hum(0.0, false)
		return
	var los := player.alive and to_player.length() <= sight_range and has_los()
	if los:
		aggro = true
		last_seen = player.global_position
	_move(delta, los)

	var in_range := los and _range_to_player() <= lock_range
	if in_range:
		lock += delta
		if lock >= fire_time:
			if has_los():
				_fire()
			lock = -recover_time
	else:
		lock = move_toward(lock, 0.0, delta * 3.0) if lock > 0.0 else minf(lock + delta, 0.0)
	var frac := clampf(lock / fire_time, 0.0, 1.0)
	_telegraph(frac, in_range)
	_update_hum(frac, in_range)
	_update_anim(frac, in_range)


func _update_anim(frac: float, locking: bool) -> void:
	if anim == null:
		return
	var state := "idle"
	if _hit_t > 0.0:
		state = "hit"
	elif _attack_t > 0.0:
		state = "attack"
	elif locking and frac > 0.02:
		state = "lock"
	elif Vector2(velocity.x, velocity.z).length() > 0.6:
		state = "move"
	elif aggro:
		state = "aware"
	if not AnimUtil.play(anim, anim_names[state]):
		AnimUtil.play(anim, "Idle")
	var hs := Vector2(velocity.x, velocity.z).length()
	anim.speed_scale = clampf(hs / move_clip_speed, 0.5, 3.5) if state == "move" and move_clip_speed > 0.0 else 1.0


func eye_position() -> Vector3:
	return global_position + Vector3.UP * eye_height


func _range_to_player() -> float:
	return eye_position().distance_to(player.global_position + Vector3.UP * 1.2)


## Clear line from this enemy's eye to the player's chest, blocked by WORLD only.
func has_los() -> bool:
	var from := eye_position()
	var to := player.global_position + Vector3.UP * 1.3
	var q := PhysicsRayQueryParameters3D.create(from, to, SIGHT_MASK)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider == player


func _fire() -> void:
	player.take_damage(damage, self)
	_attack_t = 0.45


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	_hit_flash = 1.0
	_hit_t = 0.22
	aggro = true
	last_seen = player.global_position
	Sfx.play_at("hit_enemy", eye_position())
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	collision_layer = 0
	collision_mask = 0
	if _hum:
		_hum.stop()
	Sfx.play_at("enemy_die", eye_position())
	_shatter()
	_leave_wreck()
	died.emit(self)
	queue_free()


func _leave_wreck() -> void:
	## The body stays where it fell: switch-off clip, glow fades out, flying ones drop to the floor.
	if model == null or not is_instance_valid(model):
		return
	var xf := model.global_transform
	remove_child(model)
	var holder := get_parent() if get_parent() else fx_root()
	holder.add_child(model)
	model.global_transform = xf
	model.add_to_group("wrecks")
	if not AnimUtil.play(anim, anim_names.die, 0.05):
		AnimUtil.play(anim, "Hit", 0.05)
	if anim:
		# Hold the last frame of the death clip instead of looping back to idle.
		anim.animation_finished.connect(func(_n): anim.pause(), CONNECT_ONE_SHOT)
	var wreck := model
	_dim_glow(wreck)
	var lift := wreck.global_position.y - global_position.y
	if wreck_falls and (lift > 0.05 or wreck.position.y > 0.05):
		# Drone: tumble down and settle with a small bounce.
		var floor_y := global_position.y
		var tw := wreck.create_tween()
		tw.tween_property(wreck, "global_position:y", floor_y, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(wreck, "global_position:y", floor_y + 0.12, 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(wreck, "global_position:y", floor_y, 0.12).set_ease(Tween.EASE_IN)
		var rt := wreck.create_tween()
		rt.tween_property(wreck, "rotation", wreck.rotation + Vector3(randf_range(0.6, 1.2), randf_range(-1, 1), randf_range(-0.5, 0.5)), 0.6)
	model = null


## Per-wreck copies of glowing materials, faded to a dull ember.
func _dim_glow(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m == null:
				m = mi.mesh.surface_get_material(i)
			if m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled:
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				mi.set_surface_override_material(i, d)
				mi.create_tween().tween_property(d, "emission_energy_multiplier", 0.08, 1.5)
			elif m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("neon.gdshader"):
				var d2 := (m as ShaderMaterial).duplicate() as ShaderMaterial
				mi.set_surface_override_material(i, d2)
				d2.set_shader_parameter("energy", 0.15)


func _shatter() -> void:
	## Red shards burst out and fade; a short red flash lights the room.
	var root := fx_root()
	var origin := eye_position()
	var mat := MaterialLib.neon(HOSTILE, 3.0)
	# Expanding shell: reads as a burst even from across a room.
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	shell.mesh = sm
	var shell_mat := StandardMaterial3D.new()
	shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shell_mat.albedo_color = Color(1.0, 0.18, 0.33, 0.55)
	shell.material_override = shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shell)
	shell.global_position = origin
	var st := shell.create_tween().set_parallel()
	st.tween_property(shell, "scale", Vector3.ONE * 2.6, 0.3).from(Vector3.ONE * 0.4).set_ease(Tween.EASE_OUT)
	st.tween_property(shell_mat, "albedo_color:a", 0.0, 0.3)
	st.chain().tween_callback(shell.queue_free)
	for i in 18:
		var s := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3.ONE * randf_range(0.1, 0.28)
		s.mesh = b
		s.material_override = mat
		root.add_child(s)
		s.global_position = origin + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
		var v := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized() * randf_range(2.0, 5.0)
		var tw := s.create_tween().set_parallel()
		tw.tween_property(s, "global_position", s.global_position + v * 0.6 + Vector3.DOWN * 0.5, 0.7).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 0.7)
		tw.tween_property(s, "scale", Vector3.ONE * 0.05, 0.7).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(s.queue_free)
	var l := OmniLight3D.new()
	l.light_color = HOSTILE
	l.light_energy = 4.0
	l.omni_range = 7.0
	root.add_child(l)
	l.global_position = origin
	var lt := l.create_tween()
	lt.tween_property(l, "light_energy", 0.0, 0.35)
	lt.tween_callback(l.queue_free)


func _update_hum(frac: float, active: bool) -> void:
	if not _hum:
		return
	if active and frac > 0.02:
		if not _hum.playing:
			_hum.play()
		_hum.pitch_scale = 0.7 + frac * 1.3
		_hum.volume_db = -18.0 + frac * 12.0
	elif _hum.playing:
		_hum.stop()


## Neon energy for body glow: base glow, telegraph charge, hit flash.
func _glow(frac: float) -> void:
	var e := 1.6 + frac * 3.5 + _hit_flash * 4.0
	for m in _neon_mats:
		m.set_shader_parameter("energy", e)
		m.set_shader_parameter("flicker", 0.6 if frac > 0.7 else 0.0)


# --- movement helpers -----------------------------------------------------------

## Direction to steer toward `target`: straight if visible, else along grid cells.
func _steer_dir(target: Vector3, los: bool, delta: float) -> Vector3:
	var d := target - global_position
	d.y = 0
	if los:
		return d.normalized() if d.length() > 0.05 else Vector3.ZERO
	_path_timer -= delta
	var here := DungeonGen.world_to_cell(global_position)
	if _path_timer <= 0.0 or here == _next_cell:
		_path_timer = 0.4
		_next_cell = main.nav_next_cell(here, DungeonGen.world_to_cell(target))
	if _next_cell == here:
		return d.normalized() if d.length() > 0.3 else Vector3.ZERO
	var c := DungeonGen.cell_center(_next_cell) - global_position
	c.y = 0
	return c.normalized()


## Turn the model (or its yawing part) to the player at once (capture tour / spawn).
func face_player_now() -> void:
	var node: Node3D = get("head") if get("head") != null else get("body")
	if node == null:
		node = model
	if node == null:
		return
	var d := player.global_position - global_position
	node.rotation.y = atan2(-d.x, -d.z) + model_yaw


func _face(dir: Vector3, node: Node3D, delta: float, speed: float = 8.0) -> void:
	if dir.length() < 0.01:
		return
	var want := atan2(-dir.x, -dir.z) + (model_yaw if node == model else 0.0)
	node.rotation.y = lerp_angle(node.rotation.y, want, 1.0 - exp(-speed * delta))


# --- visuals helpers -------------------------------------------------------------

## Instance a Blender enemy model with per-instance neon materials (so one enemy's
## telegraph glow does not light up every other enemy). Returns null if missing.
func _adopt_model(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var m := (load(path) as PackedScene).instantiate() as Node3D
	MaterialLib.rebind_tree(m, path)
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			# Only the glow (neon shader) is per-instance; the wear materials are shared.
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path.ends_with("neon.gdshader"):
				var d := mat.duplicate() as ShaderMaterial
				mi.set_surface_override_material(i, d)
				_neon_mats.append(d)
	add_child(m)
	model = m
	anim = m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clips_json := path.replace(".glb", "_clips.json")
	if FileAccess.file_exists(clips_json):
		AnimUtil.split_clips(anim, clips_json, clip_strip)
		if not clip_strip.is_empty():
			AnimUtil.split_clips(anim, clips_json, death_strip, {}, ["Death"])
		wreck_falls = false
	AnimUtil.play(anim, "Idle", 0.0)
	return m


static func neon_red() -> ShaderMaterial:
	return MaterialLib.neon(HOSTILE, 1.6)


static func body_metal() -> Material:
	return MaterialLib.get_material("PropMetal")


func _mesh(mesh: Mesh, mat: Material, parent: Node3D, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## A red laser beam (unit cylinder along -Z, scaled to length).
func _make_beam(parent: Node3D) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = MaterialLib.neon(HOSTILE, 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	parent.add_child(mi)
	return mi


## Stretch `beam` from world point a to b with given radius.
static func aim_beam(beam: MeshInstance3D, a: Vector3, b: Vector3, radius: float) -> void:
	var len := a.distance_to(b)
	if len < 0.01:
		beam.visible = false
		return
	var mid := (a + b) * 0.5
	var up := (b - a) / len
	var x := up.cross(Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP).normalized()
	var z := x.cross(up)
	beam.global_transform = Transform3D(Basis(x * radius, up * len, z * radius), mid)
	beam.visible = true


## Parent for transient effects: the running scene, or the tree root in test harnesses.
func fx_root() -> Node:
	var t := get_tree()
	return t.current_scene if t.current_scene != null else t.root
