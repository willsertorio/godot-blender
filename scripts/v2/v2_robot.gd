class_name V2Robot
extends Node3D
## One V2 robot as an enemy of the lab: it moves, looks for the player, shoots, takes damage, dies and comes back.
##   spider  walks about its part of the floor, runs to a firing position, turns to face the player, fires a burst
##   drone   the same in the air (it keeps the nose-down attitude it has in the Blender scene)
##   turret  hangs from its pylon: scans, then swings its arm round and pitches its head to track the player
## The clips come from Blender (v2/scripts/anim_robots.py); this script only moves the node, picks the clip, and
## aims. A robot shoots at where the player was a moment ago (`AIM_LAG`), so moving makes it miss.
## Preview mode (set_ai(false)): the robot stands where it stands in the Blender scene and cycles through its clips.

enum { ROAM, ENGAGE, AIM, SHOOT, DEAD, PREVIEW }
const STATE_NAMES := ["roam", "engage", "aim", "shoot", "dead", "preview"]
const ORDER := {
	"spider": ["Idle", "Shoot", "Walk", "Run", "Death"],
	"drone": ["Idle", "Shoot", "Fly", "Death"],
	"turret": ["Idle", "Shoot", "Aim", "Death"],
}
const HIT := {  # joint the hit box rides on, box size, box centre (in the joint's frame)
	"spider": ["Spider_Body", Vector3(1.0, 0.6, 1.2), Vector3.ZERO],
	"drone": ["Drone_Body", Vector3(1.7, 0.45, 0.6), Vector3.ZERO],
	"turret": ["Turret_Head", Vector3(0.7, 0.4, 0.4), Vector3(0.15, -0.14, 0.0)],
}
# arena = the part of the room's floor (x, z; room frame) it may be in: clear of the tanks, columns and stairs
# (the spider's also stays 1.6 m short of where the player starts and is put back)
const SPEC := {
	"spider": {"hp": 150.0, "damage": 6.0, "spread": 1.6, "walk": 0.75, "run": 2.1, "turn": 200.0, "eye": 0.9,
		"keep": [5.0, 7.5], "cooldown": [1.2, 2.4], "arena": Rect2(-1.7, -6.4, 3.7, 4.8),
		"clips": ["Walk", 0.6, "Run", 1.5, "Idle"]},
	"drone": {"hp": 80.0, "damage": 7.0, "spread": 2.2, "walk": 1.3, "run": 2.6, "turn": 260.0, "eye": 2.4,
		"keep": [4.0, 7.5], "cooldown": [1.0, 2.0], "arena": Rect2(-2.3, -7.0, 5.0, 8.5),
		"clips": ["Fly", 1.3, "Fly", 2.0, "Idle"]},
	"turret": {"hp": 180.0, "damage": 7.0, "spread": 1.3, "turn": 150.0, "eye": 2.8, "cooldown": [1.1, 1.9]},
}
const AIM_LAG := 0.3              # seconds the aim point trails the player
const RESPAWN := 6.0             # seconds a wreck lies before the robot is back

var kind := ""
var ap: AnimationPlayer
var clip := ""
var state := ROAM
var hp := 1.0
var max_hp := 1.0
var player: V2Player
var active := false               # the player is in this robot's room
var auto := true                  # preview: cycle through the clips
var shots_fired := 0
var travelled := 0.0
var kills := 0                    # times it was destroyed
var _spec: Dictionary
var _root: Node3D                 # the glb's <Kind>_Root joint, re-seated on this node
var _body: StaticBody3D
var _hit_joint: Node3D
var _flashes: Array = []
var _events: Dictionary = {}
var _ev := {}
var _label: Label3D
var _smoke: CPUParticles3D
var _home := Vector3.ZERO
var _home_yaw := 0.0
var _target := Vector3.ZERO
var _t := 0.0
var _cool := 1.5
var _pause := -1.0
var _idx := 0
var _left := 0.0
var _sees := false
var _unseen := 99.0
var _aim_point := Vector3.ZERO
var _aim_valid := false
var _tyaw := 0.0                  # turret: the arm's heading (the angle of its Root joint)
var _tpitch := 0.0                # turret: extra head pitch, down positive
var _head: Node3D
var _aim_node: Node3D
var _head_pivot := Vector3.ZERO
var _flinch := 0.0                # 1 when hit, dies away: a short shake
var _seat := Vector3.ZERO         # where the Root joint sits on this node


func setup(robot: String) -> void:
	kind = robot
	_spec = SPEC[kind]
	max_hp = _spec.hp
	hp = max_hp
	var scene: Node3D = (load(V2Assets.DIR + kind + ".glb") as PackedScene).instantiate()
	add_child(scene)
	V2Assets.apply(scene, kind)
	ap = V2Assets.clips(scene, kind)
	_flashes = V2Fx.flashes(scene)
	_events = V2Assets.flash_events(kind)
	_root = scene.find_child(kind.capitalize() + "_Root", true, false) as Node3D
	_reseat()
	_hit_joint = scene.find_child(HIT[kind][0], true, false) as Node3D
	_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = HIT[kind][1]
	shape.shape = box
	shape.position = HIT[kind][2]
	_body.add_child(shape)
	_body.set_meta("robot", self)
	_hit_joint.add_child(_body)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.0035
	_label.modulate = Color(0.55, 0.95, 1.0)
	_label.outline_size = 6
	add_child(_label)
	_label.global_position = _hit_joint.global_position + Vector3(0, 0.75, 0)
	_smoke = V2Fx.smoke_column(_hit_joint, Vector3.ZERO, 0.6 if kind == "drone" else 0.8)
	_target = position
	_play("Idle")


## The glb has the robot where it stands in the Blender scene. Put that place and heading on this node and seat the
## Root joint on it, so that moving / turning this node moves the robot: spider and drone face -Z of this node; the
## turret's Root keeps its own heading (the arm swings, its pylon does not).
func _reseat() -> void:
	var seat := _root.transform
	_home = Vector3(seat.origin.x, 0.0, seat.origin.z)
	position = _home
	_seat = Vector3(0.0, seat.origin.y, 0.0)
	_root.position = _seat
	for a in ap.get_animation_list():                 # (the Root's own constant track would put it back)
		var anim := ap.get_animation(a)
		for i in range(anim.get_track_count() - 1, -1, -1):
			var p := anim.track_get_path(i)
			if p.get_name_count() == 1 and String(p.get_name(0)) == String(_root.name):
				anim.remove_track(i)
	if kind == "turret":
		for n in _root.get_children():                # the pylon and its cables stay with the ceiling
			if String(n.name).contains("Pylon"):
				var gt := (n as Node3D).global_transform
				_root.remove_child(n)
				add_child(n)
				(n as Node3D).global_transform = gt
		var fwd := seat.basis * Vector3.RIGHT          # the arm reaches along the Root's +X
		_tyaw = atan2(-fwd.z, fwd.x)
		_home_yaw = _tyaw
		_root.basis = Basis(Vector3.UP, _tyaw)
		# head pitch: a node between the elbow and the head that turns about the head's pivot; the clips' tracks
		# are re-pointed through it (once: the animation library is shared by every instance)
		_head = _root.find_child("Turret_Head", true, false) as Node3D
		var elbow := _head.get_parent()
		_head_pivot = _head.position
		_aim_node = Node3D.new()
		_aim_node.name = "AimPitch"
		elbow.add_child(_aim_node)
		_head.reparent(_aim_node, false)
		var lib := ap.get_animation_library("")
		if not lib.has_meta("aim_rewired"):
			lib.set_meta("aim_rewired", true)
			for a in ap.get_animation_list():
				var anim := ap.get_animation(a)
				for i in anim.get_track_count():
					var s := String(anim.track_get_path(i))
					if s.contains("Turret_Elbow/Turret_Head"):
						anim.track_set_path(i, NodePath(s.replace("Turret_Elbow/Turret_Head", "Turret_Elbow/AimPitch/Turret_Head")))
	else:
		var nose := seat.basis * Vector3.FORWARD
		_home_yaw = atan2(-nose.x, -nose.z)
		_root.basis = Basis(Vector3.UP, -_home_yaw) * seat.basis    # the drone keeps its lean, the spider is level
		rotation.y = _home_yaw


func set_ai(on: bool) -> void:
	if on:
		respawn()
	else:
		state = PREVIEW
		_smoke.emitting = false
		_go_home()
		auto = true
		play(ORDER[kind][0])


func _go_home() -> void:
	position = _home
	if kind == "turret":
		_tyaw = _home_yaw
		_tpitch = 0.0
		_apply_turret()
	else:
		rotation.y = _home_yaw


func respawn() -> void:
	hp = max_hp
	state = ROAM
	_smoke.emitting = false
	_go_home()
	_target = position
	_pause = -1.0
	_cool = 1.5
	_aim_valid = false
	_play("Idle", 1.0, true)


func hit_point() -> Vector3:
	return _body.global_position


func flash_on() -> bool:
	for f in _flashes:
		if f.on:
			return true
	return false


## A round from the player.
func hit(damage: float = 34.0) -> void:
	if state == PREVIEW:
		if clip != "Death":
			play("Death")
		return
	if state == DEAD:
		return
	hp -= damage
	if hp <= 0.0:
		hp = 0.0
		kills += 1
		state = DEAD
		_play("Death", 1.0, true)
		_t = ap.get_animation("Death").length + RESPAWN
		_smoke.emitting = true
		V2Fx.burst(hit_point())
	else:
		_flinch = 1.0
		if state == ROAM and kind != "turret":
			_engage()                                  # it knows where that came from


# ---------------------------------------------------------------- clips
func _play(clip_name: String, speed: float = 1.0, restart: bool = false) -> void:
	if ap == null or not ap.has_animation(clip_name):
		return
	if clip != clip_name or restart or not ap.is_playing():
		clip = clip_name
		ap.play(clip_name, 0.0 if restart else 0.12)
		if restart:
			ap.seek(0.0, true)
	ap.speed_scale = speed


## Preview: play a clip from its start (and hold the pose a moment after one that does not loop).
func play(clip_name: String) -> void:
	if ap == null or not ap.has_animation(clip_name):
		return
	if state != PREVIEW:
		set_ai(false)
	_idx = ORDER[kind].find(clip_name)
	_play(clip_name, 1.0, true)
	var a := ap.get_animation(clip_name)
	_left = maxf(a.length, 3.0) if a.loop_mode != Animation.LOOP_NONE else a.length + (2.5 if clip_name == "Death" else 0.4)


func next() -> void:
	play(ORDER[kind][(_idx + 1) % ORDER[kind].size()])


# ---------------------------------------------------------------- senses and shooting
func _eye() -> Vector3:
	return _head.global_position if kind == "turret" else global_position + Vector3(0, _spec.eye, 0)


func _look(delta: float) -> void:
	var chest := player.global_position + Vector3(0, 1.15, 0)
	_sees = false
	if active and not player.down:
		var q := PhysicsRayQueryParameters3D.create(_eye(), chest)
		q.exclude = [_body.get_rid()]
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		_sees = not res.is_empty() and res.collider == player
	if _sees:
		_unseen = 0.0
		_aim_point = _aim_point.lerp(chest, 1.0 - exp(-delta / AIM_LAG)) if _aim_valid else chest
		_aim_valid = true
	else:
		_unseen += delta
		if _unseen > 3.0:
			_aim_valid = false


func _fire(muzzle: Node3D) -> void:
	shots_fired += 1
	var from := muzzle.global_position
	var aim := _aim_point if _aim_valid else from - muzzle.global_basis.z * 20.0
	var dir := (aim - from).normalized()
	var side := dir.cross(Vector3.UP)
	if side.length() > 0.01:
		var sp := deg_to_rad(_spec.spread)
		dir = dir.rotated(side.normalized(), randf_range(-sp, sp)).rotated(Vector3.UP, randf_range(-sp, sp))
	var to := from + dir * 40.0
	var q := PhysicsRayQueryParameters3D.create(from + dir * 0.15, to)
	q.exclude = [_body.get_rid()]
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if not res.is_empty():
		to = res.position
		if res.collider == player:
			player.hurt(_spec.damage, from)
			to -= dir * minf(1.3, from.distance_to(to) * 0.5)      # (a streak that ends at the eye fills the screen)
		else:
			V2Fx.impact(to, res.normal)
	V2Fx.tracer(from, to, V2Fx.RED)
	V2Fx.puff(from, dir, V2Fx.GUNSMOKE, 0.22, 2, 0.7, 0.22, 0.5)


# ---------------------------------------------------------------- spider and drone
## From here toward what it aims at (the player's place a moment ago; the player if it has not seen them yet).
func _aim_dir() -> Vector3:
	return (_aim_point if _aim_valid else player.global_position) - global_position


func _local(p: Vector3) -> Vector3:
	return p - (get_parent() as Node3D).global_position


func _clamp_arena(p: Vector3) -> Vector3:
	var a: Rect2 = _spec.arena
	return Vector3(clampf(p.x, a.position.x, a.end.x), 0.0, clampf(p.z, a.position.y, a.end.y))


func in_arena(margin: float = 0.05) -> bool:
	if kind == "turret":
		return position.distance_to(_home) < 0.01
	return (_spec.arena as Rect2).grow(margin).has_point(Vector2(position.x, position.z))


func _pick_roam() -> void:
	var a: Rect2 = _spec.arena
	var pl := _local(player.global_position)
	for k in 10:
		var c := Vector3(randf_range(a.position.x, a.end.x), 0.0, randf_range(a.position.y, a.end.y))
		if c.distance_to(position) > 1.5 and Vector2(c.x - pl.x, c.z - pl.z).length() > 3.6:
			_target = c
			return
	_target = position


## Choose where to shoot from: at a good distance from the player, inside the arena, not where it already is.
func _engage() -> void:
	state = ENGAGE
	_t = 3.5
	var pl := _local(player.global_position)
	pl.y = 0.0
	var best := position
	var best_score := 1e9
	for k in 14:
		var ang := randf() * TAU
		var c := _clamp_arena(pl + Vector3(cos(ang), 0.0, sin(ang)) * randf_range(_spec.keep[0], _spec.keep[1]))
		var d := c.distance_to(pl)
		var score := maxf(_spec.keep[0] - d, 0.0) * 4.0 + absf(c.distance_to(position) - 2.5) * 0.5
		if score < best_score:
			best_score = score
			best = c
	_target = best


func _face(dir: Vector3, rate_deg: float, delta: float) -> float:
	var want := atan2(-dir.x, -dir.z)
	rotation.y = rotate_toward(rotation.y, want, deg_to_rad(rate_deg) * delta)
	return absf(angle_difference(rotation.y, want))


## One step toward _target; true when it is there. face_player: keep the nose on the player while moving.
func _move(delta: float, fast: bool, face_player: bool) -> bool:
	var to := _target - position
	to.y = 0.0
	var dist := to.length()
	var clips: Array = _spec.clips
	if dist < 0.3:
		return true
	var k := 1.0
	if face_player:
		_face(_aim_dir(), _spec.turn, delta)
	else:
		k = clampf(1.0 - _face(to, _spec.turn, delta) / deg_to_rad(70.0), 0.0, 1.0)      # turns first, then goes
	var pl := _local(player.global_position) - position
	pl.y = 0.0
	if pl.length() < 3.0 and pl.dot(to) > 0.0:         # never into the player
		k = 0.0
	var speed: float = (_spec.run if fast else _spec.walk) * k
	var step := minf(speed * delta, dist)
	position = _clamp_arena(position + to / dist * step)
	travelled += step
	_play(clips[2] if fast else clips[0], clampf(speed / float(clips[3] if fast else clips[1]), 0.5, 1.6))
	return false


func _mobile(delta: float) -> void:
	var clips: Array = _spec.clips
	if state != ROAM and _unseen > 3.0:                # lost the player
		state = ROAM
		_pick_roam()
	match state:
		ROAM:
			if _sees and _cool <= 0.0:
				_engage()
			elif _move(delta, false, false):
				_play(clips[4])
				if _pause < 0.0:
					_pause = randf_range(0.8, 2.2)
				_pause -= delta
				if _pause <= 0.0:
					_pause = -1.0
					_pick_roam()
		ENGAGE:
			if _move(delta, true, kind == "drone") or _t <= 0.0:
				state = AIM
				_t = 3.0
		AIM:
			_play(clips[4])
			var off := _face(_aim_dir(), _spec.turn, delta)
			if off < deg_to_rad(8.0) and _sees and _cool <= 0.0:
				state = SHOOT
				_play("Shoot", 1.0, true)
				_t = ap.get_animation("Shoot").length
			elif _t <= 0.0:
				_engage()
		SHOOT:
			_face(_aim_dir(), _spec.turn * 0.3, delta)
			if _t <= 0.0:
				_cool = randf_range(_spec.cooldown[0], _spec.cooldown[1])
				_engage()


# ---------------------------------------------------------------- turret
func _apply_turret() -> void:
	_root.basis = Basis(Vector3.UP, _tyaw)
	var r := Basis(Vector3(0, 0, 1), -_tpitch)         # about the joint's side axis, down positive
	_aim_node.transform = Transform3D(r, _head_pivot - r * _head_pivot)


func _rest_pose() -> void:
	_play("Shoot", 1.0, true)                          # the first frame of Shoot is the rest pose
	ap.pause()


func aim_error() -> float:
	var d := _aim_point - _root.global_position
	return absf(angle_difference(_tyaw, atan2(-d.z, d.x)))


func _turret(delta: float) -> void:
	var tracking := _aim_valid and _unseen < 2.5
	if tracking:
		if state == ROAM:
			state = AIM
			_rest_pose()
		var d := _aim_point - _root.global_position
		var want := atan2(-d.z, d.x)
		_tyaw = rotate_toward(_tyaw, want, deg_to_rad(_spec.turn) * delta)
		var hd := _aim_point - _head.global_position
		var want_p := atan2(-hd.y, Vector2(hd.x, hd.z).length()) - deg_to_rad(14.0)    # the head rests 14 degrees down
		_tpitch = move_toward(_tpitch, clampf(want_p, -0.45, 0.8), 1.6 * delta)
		if state == AIM and absf(angle_difference(_tyaw, want)) < deg_to_rad(5.0) and _cool <= 0.0 and _sees:
			state = SHOOT
			_play("Shoot", 1.0, true)
			_t = ap.get_animation("Shoot").length
		elif state == SHOOT and _t <= 0.0:
			state = AIM
			_cool = randf_range(_spec.cooldown[0], _spec.cooldown[1])
			_rest_pose()
	else:
		if state != ROAM:
			state = ROAM
		_play("Idle")                                  # (its own scan, about the heading it was left at)
		_tyaw = rotate_toward(_tyaw, _home_yaw, 0.5 * delta)
		_tpitch = move_toward(_tpitch, 0.0, 0.6 * delta)
	_apply_turret()


# ---------------------------------------------------------------- every frame
func _process(delta: float) -> void:
	var fired := V2Fx.fired(ap, _events, _ev, _flashes)
	if state == PREVIEW:
		_label.text = "%s  ·  %s" % [kind.to_upper(), clip]
		for node in fired:                             # along the barrel
			var n := node as Node3D
			var from := n.global_position
			var dir := -n.global_basis.z.normalized()
			var to := from + dir * 30.0
			var q := PhysicsRayQueryParameters3D.create(from + dir * 0.3, to)
			var res := get_world_3d().direct_space_state.intersect_ray(q)
			if not res.is_empty():
				to = res.position
				V2Fx.impact(to, res.normal)
			V2Fx.tracer(from, to, V2Fx.RED)
		_left -= delta
		if _left <= 0.0:
			if auto or clip == "Death":
				next()
			else:
				play(clip)
		return
	_label.text = kind.to_upper()
	_t -= delta
	_cool -= delta
	_flinch = maxf(_flinch - delta * 6.0, 0.0)         # a hit shakes it for a moment
	_root.position = _seat + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 0.035 * _flinch
	if state == DEAD:
		if _t <= 0.0:
			respawn()
		return
	if player == null:
		return
	_look(delta)
	if state == SHOOT:
		for node in fired:
			_fire(node as Node3D)
	if kind == "turret":
		_turret(delta)
	else:
		_mobile(delta)
