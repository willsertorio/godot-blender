class_name V2Robot
extends Node3D
## One V2 robot as an enemy of the lab: it moves, looks for the player, shoots, takes damage, dies and comes back.
##   spider  walks about its part of the floor, runs to a firing position, steps round to face the player, fires
##   drone   the same in the air; it pitches its whole body until its gun points at the player
##   turret  hangs from its pylon: scans, then swings its arm round and pitches its head to track the player
## The clips come from Blender (v2/scripts/anim_robots.py); this script moves the node, picks the clip, and aims.
## Aiming is a servo on the barrel itself: every frame the direction the muzzle really points (clip and all) is
## compared with the direction to the target, and the aiming joints are turned by the difference (spider: turret
## yaw and gun pitch; drone: body pitch, the node's heading; turret: arm heading and head pitch). A round then
## leaves along the barrel, wherever that points: the shot is never bent. A robot aims at where the player was
## a moment ago (`AIM_LAG`), so moving makes it miss.
## A hit pushes the robot: the body is knocked back and tilted on springs and it is shoved a little way.
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
	"spider": {"hp": 150.0, "damage": 6.0, "spread": 0.5, "walk": 0.75, "run": 2.1, "turn": 110.0, "eye": 0.9,
		"keep": [5.0, 7.5], "cooldown": [1.2, 2.4], "arena": Rect2(-1.7, -6.4, 3.7, 4.8),
		"clips": ["Walk", 0.6, "Run", 1.5, "Idle"]},
	"drone": {"hp": 80.0, "damage": 7.0, "spread": 0.7, "walk": 1.3, "run": 2.6, "turn": 260.0, "eye": 2.4,
		"keep": [4.0, 7.5], "cooldown": [1.0, 2.0], "arena": Rect2(-2.3, -7.0, 5.0, 8.5),
		"clips": ["Fly", 1.3, "Fly", 2.0, "Idle"]},
	"turret": {"hp": 180.0, "damage": 7.0, "spread": 0.5, "turn": 150.0, "eye": 2.8, "cooldown": [1.1, 1.9]},
}
const AIM_LAG := 0.3              # seconds the aim point trails the player
const TURN_RATE := 60.0           # degrees a second the spider's Turn clip turns at speed 1 (anim_robots.py)
# how hard a round from the player pushes: [body knock m/s, tilt rad/s, shove along the floor / through the air m/s]
const PUSH := {"spider": [1.5, 3.2, 0.7], "drone": [1.2, 5.0, 2.2], "turret": [0.0, 4.5, 0.0]}
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
var _base := Basis.IDENTITY       # spider, drone: the Root joint's own attitude on this node
var _muzzles: Array[Node3D] = []  # the flash nodes: -Z of each is its barrel
var _aims: Array = []             # spider: [{node, pivot, axis}] yaw above the turret, pitch above the guns
var _ayaw := 0.0                  # spider: the servo's turret yaw
var _apitch := 0.0                # spider: gun pitch; drone: body pitch
var _aim_err := 9.0               # angle between the barrel and the direction to the target (radians)
var _knock := Vector3.ZERO        # the body knocked off its seat (node frame), on a spring
var _knock_v := Vector3.ZERO
var _tilt := Vector3.ZERO         # and tilted (axis * angle, node frame); the turret: (head pitch, arm yaw, 0)
var _tilt_v := Vector3.ZERO
var _shove := Vector3.ZERO        # velocity of the push along the floor (room frame), dies away
var _gap := 0.0                   # how far above the floor the wreck's lowest point is at the end of the Death clip
var _sink := 0.0                  # how much of that is taken out now


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
	for f in _flashes:
		_muzzles.append(f.node as Node3D)
	_reseat()
	if kind == "spider":
		var turret_joint := scene.find_child("Spider_Turret", true, false) as Node3D
		var guns_joint := scene.find_child("Spider_Guns", true, false) as Node3D
		# (the joints keep Blender's axes turned to Y-up: a joint's own up is the turret's axis, its X the guns')
		_aims.append({"pivot": turret_joint.position, "axis": (turret_joint.basis * Vector3.UP).normalized(),
			"node": _insert_aim(turret_joint, "AimYaw")})
		_aims.append({"pivot": guns_joint.position, "axis": (guns_joint.basis * Vector3.RIGHT).normalized(),
			"node": _insert_aim(guns_joint, "AimPitch")})
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
	_measure_wreck()
	_play("Idle", 1.0, true)


## A node between `joint` and its parent, for turning the joint about its own pivot on top of what the clips do to
## it. The clips' tracks are re-pointed through it (once: the animation library is shared by every instance).
func _insert_aim(joint: Node3D, aim_name: String) -> Node3D:
	var parent := joint.get_parent()
	var n := Node3D.new()
	n.name = aim_name
	parent.add_child(n)
	var old := "%s/%s" % [parent.name, joint.name]
	var new := "%s/%s/%s" % [parent.name, aim_name, joint.name]
	joint.reparent(n, false)
	var lib := ap.get_animation_library("")
	if not lib.has_meta("rewired_" + aim_name):
		lib.set_meta("rewired_" + aim_name, true)
		for a in ap.get_animation_list():
			var anim := ap.get_animation(a)
			for i in anim.get_track_count():
				var path := String(anim.track_get_path(i))
				if path.contains(old):
					anim.track_set_path(i, NodePath(path.replace(old, new)))
	return n


## Where the wreck ends up: the lowest point of the robot at the end of its Death clip, above the floor. The clip
## leaves the drone a few centimetres in the air; the wreck is lowered by that much as it falls.
func _measure_wreck() -> void:
	if kind == "turret" or not ap.has_animation("Death") or DisplayServer.get_name() == "headless":
		return                                         # (headless: the dummy renderer has no mesh data)
	ap.play("Death")
	ap.seek(ap.get_animation("Death").length, true)
	ap.advance(0.0)
	var gap := lowest_point() - (get_parent() as Node3D).global_position.y
	if absf(gap) < 0.4:
		_gap = gap
	ap.stop()


## The height of the robot's lowest point as it is posed now (world; needs real meshes: not in a headless run).
func lowest_point() -> float:
	var lowest := 1e9
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.global_basis.get_scale().x < 0.01 or String(mi.name).contains("Flash"):
			continue
		var xf := mi.global_transform
		for v in mi.mesh.get_faces():
			lowest = minf(lowest, (xf * v).y)
	return lowest


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
		_head_pivot = _head.position
		_aim_node = _insert_aim(_head, "AimPitch")
	else:
		var nose := seat.basis * Vector3.FORWARD
		_home_yaw = atan2(-nose.x, -nose.z)
		_base = Basis(Vector3.UP, -_home_yaw) * seat.basis      # (the drone's lean in the Blender scene; the spider is level)
		_root.basis = _base
		rotation.y = _home_yaw


func set_ai(on: bool) -> void:
	if on:
		respawn()
	else:
		state = PREVIEW
		_smoke.emitting = false
		_settle()
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


## Everything this script adds to the clips back to nothing (aim, knock, tilt, the wreck's sink).
func _settle() -> void:
	_ayaw = 0.0
	_apitch = 0.0
	_knock = Vector3.ZERO
	_knock_v = Vector3.ZERO
	_tilt = Vector3.ZERO
	_tilt_v = Vector3.ZERO
	_shove = Vector3.ZERO
	_sink = 0.0
	_flinch = 0.0
	_pose()


func respawn() -> void:
	hp = max_hp
	state = ROAM
	_smoke.emitting = false
	_settle()
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


## A round from the player, flying along `dir`.
func hit(damage: float = 34.0, dir: Vector3 = Vector3.ZERO) -> void:
	if state == PREVIEW:
		if clip != "Death":
			play("Death")
		return
	if state == DEAD:
		return
	_push(dir, 1.6 if hp - damage <= 0.0 else 1.0)
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
		_cool = maxf(_cool, 0.3)                       # it loses its aim for a moment
		if state == ROAM and kind != "turret":
			_engage()                                  # it knows where that came from


## Knocked by a round: the body jumps back on its seat and tips away from the shot (both on springs), and the
## spider is shoved a little over the floor, the drone a good way through the air; the turret's arm is swung aside.
func _push(dir: Vector3, k: float) -> void:
	if dir == Vector3.ZERO:
		dir = (global_position - player.global_position) if player != null else Vector3.FORWARD
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var p: Array = PUSH[kind]
	if kind == "turret":
		var side := signf(flat.cross(-_root.global_basis.x).y)       # which way round the shot swings the arm
		_tilt_v += Vector3(p[1] * 0.6, p[1] * (side if side != 0.0 else 1.0), 0.0) * k
		return
	var local := global_basis.inverse() * flat
	_knock_v += (local + Vector3(0, 0.25, 0)) * p[0] * k
	_tilt_v += Vector3.UP.cross(local).normalized() * p[1] * k        # (tips over away from the shot)
	_shove += flat * p[2] * k


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


func _barrel() -> Vector3:
	return -_muzzles[0].global_basis.z.normalized()


func _muzzle_point() -> Vector3:
	var p := Vector3.ZERO
	for m in _muzzles:
		p += m.global_position
	return p / _muzzles.size()


## The servo's measurement: [yaw error (counter-clockwise from above), elevation error, total angle] between where
## the barrels point and `target`.
func _aim_error(target: Vector3) -> Vector3:
	var b := _barrel()
	var t := (target - _muzzle_point()).normalized()
	return Vector3(angle_difference(atan2(-b.x, -b.z), atan2(-t.x, -t.z)), asin(clampf(t.y, -1.0, 1.0)) - asin(clampf(b.y, -1.0, 1.0)), b.angle_to(t))


## Along the barrel, as it points now.
func _fire(muzzle: Node3D) -> void:
	shots_fired += 1
	var from := muzzle.global_position
	var dir := -muzzle.global_basis.z.normalized()
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


## The spider turns on the spot by stepping round (the Turn clip, played forward for a left turn, backward for a
## right one, at the speed that matches the turn): its feet stay where they stand. Returns the angle still to go.
func _step_round(dir: Vector3, delta: float) -> float:
	var want := atan2(-dir.x, -dir.z)
	var off := angle_difference(rotation.y, want)
	if not ap.has_animation("Turn"):
		return _face(dir, _spec.turn, delta)
	var rate: float = minf(_spec.turn, maxf(absf(rad_to_deg(off)) * 6.0, 25.0))     # eases into the last degrees
	rotation.y += clampf(off, -deg_to_rad(rate) * delta, deg_to_rad(rate) * delta)
	_play("Turn", signf(off) * rate / TURN_RATE)
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
	elif kind == "spider":
		# first round to the way it is going, on the spot; then walk, turning only a little as it goes
		var off := absf(angle_difference(rotation.y, atan2(-to.x, -to.z)))
		if off > deg_to_rad(18.0) or (clip == "Turn" and off > deg_to_rad(4.0)):
			_step_round(to, delta)
			return false
		_face(to, 45.0, delta)
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
	if k <= 0.0 and kind == "spider":
		_rest_pose()                                   # (standing: no walking on the spot)
	else:
		_play(clips[2] if fast else clips[0], clampf(speed / float(clips[3] if fast else clips[1]), 0.5, 1.6))
	return false


## Spider: turret yaw and gun pitch; drone: body pitch. `on` = track the aim point, else ease back to the clips'
## own pose (the drone: to level flight, its gun a little below the horizon).
func _servo(delta: float, on: bool) -> void:
	var rate := deg_to_rad(240.0) * delta
	if kind == "drone":
		var b := _barrel()
		var want := -0.12
		_aim_err = 9.0
		if on and _aim_valid:
			var e := _aim_error(_aim_point)
			want = asin(clampf(b.y, -1.0, 1.0)) + e.y
			_aim_err = e.z
			if state == AIM or state == SHOOT:                # its heading too: the nose is not exactly where the gun points
				var turn := deg_to_rad(_spec.turn) * delta
				rotation.y += clampf(e.x * 0.8, -turn, turn)
		var s := signf(global_basis.x.cross(b).y)                 # which way a turn about the body's side axis lifts the barrel
		_apitch = clampf(_apitch + clampf((want - asin(clampf(b.y, -1.0, 1.0))) * s * 0.8, -rate, rate), -1.4, 1.4)
		return
	if not on or not _aim_valid:
		_ayaw = move_toward(_ayaw, 0.0, rate)
		_apitch = move_toward(_apitch, 0.0, rate)
		_aim_err = 9.0
		return
	var e2 := _aim_error(_aim_point)
	var b2 := _barrel()
	var yaw_axis: Vector3 = ((_aims[0].node as Node3D).get_parent() as Node3D).global_basis * (_aims[0].axis as Vector3)
	var pitch_axis: Vector3 = ((_aims[1].node as Node3D).get_parent() as Node3D).global_basis * (_aims[1].axis as Vector3)
	_ayaw = wrapf(_ayaw + clampf(e2.x * signf(yaw_axis.y) * 0.8, -rate, rate), -PI, PI)
	_apitch = clampf(_apitch + clampf(e2.y * signf(pitch_axis.cross(b2).y) * 0.8, -rate, rate), -0.7, 0.7)
	_aim_err = e2.z


func _mobile(delta: float) -> void:
	var clips: Array = _spec.clips
	if state != ROAM and _unseen > 3.0:                # lost the player
		state = ROAM
		_pick_roam()
	_servo(delta, state != ROAM)
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
			var off := 0.0
			if kind == "spider":                           # the body steps round until the player is in front, the turret does the rest
				off = absf(angle_difference(rotation.y, atan2(-_aim_dir().x, -_aim_dir().z)))
				if off > deg_to_rad(25.0) or (clip == "Turn" and off > deg_to_rad(5.0)):
					_step_round(_aim_dir(), delta)
				else:
					_rest_pose()
					off = 0.0
			else:
				_play(clips[4])                            # (the drone: the servo turns it)
			if off < deg_to_rad(8.0) and _aim_err < deg_to_rad(3.0) and _sees and _cool <= 0.0:
				state = SHOOT
				_play("Shoot", 1.0, true)
				_t = ap.get_animation("Shoot").length
			elif _t <= 0.0:
				_engage()
		SHOOT:
			if _t <= 0.0:
				_cool = randf_range(_spec.cooldown[0], _spec.cooldown[1])
				_engage()


# ---------------------------------------------------------------- turret
func _apply_turret() -> void:
	_root.basis = Basis(Vector3.UP, _tyaw + _tilt.y)
	var r := Basis(Vector3(0, 0, 1), -(_tpitch + _tilt.x))         # about the joint's side axis, down positive
	_aim_node.transform = Transform3D(r, _head_pivot - r * _head_pivot)


func _rest_pose() -> void:
	if clip != "Shoot" or ap.is_playing():
		_play("Shoot", 1.0, true)                      # the first frame of Shoot is the rest pose
		ap.pause()


## The angle between the barrels and the direction to the aim point (radians; 9 = not aiming).
func aim_error() -> float:
	return _aim_err


func _turret(delta: float) -> void:
	var tracking := _aim_valid and _unseen < 2.5
	if tracking:
		if state == ROAM:
			state = AIM
			_rest_pose()
		var e := _aim_error(_aim_point)
		_aim_err = e.z
		if _tilt.length() < 0.05:                      # (not while a hit is swinging it)
			var b := _barrel()
			var pitch_axis := (_aim_node.get_parent() as Node3D).global_basis * Vector3(0, 0, 1)
			_tyaw += clampf(e.x * 0.8, -deg_to_rad(_spec.turn) * delta, deg_to_rad(_spec.turn) * delta)
			# (_tpitch turns the head by -angle about that axis)
			_tpitch = clampf(_tpitch - clampf(e.y * signf(pitch_axis.cross(b).y) * 0.8, -1.6 * delta, 1.6 * delta), -0.8, 1.1)
		if state == AIM and _aim_err < deg_to_rad(3.0) and _cool <= 0.0 and _sees:
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
		_aim_err = 9.0
		_play("Idle")                                  # (its own scan, about the heading it was left at)
		_tyaw = rotate_toward(_tyaw, _home_yaw, 0.5 * delta)
		_tpitch = move_toward(_tpitch, 0.0, 0.6 * delta)


## The springs of a hit, the shove, and everything this script adds to the clips' pose, put on the joints.
func _springs(delta: float) -> void:
	var steps := maxi(int(ceil(delta / 0.008)), 1)     # (explicit springs: short steps, whatever the frame time)
	var h := delta / steps
	for i in steps:
		_knock_v += (-_knock * 240.0 - _knock_v * 17.0) * h
		_knock += _knock_v * h
		_tilt_v += (-_tilt * 200.0 - _tilt_v * 13.0) * h
		_tilt += _tilt_v * h
	if kind != "turret" and _shove.length() > 0.01:
		position = _clamp_arena(position + _shove * delta) if state != DEAD else position + _shove * delta
		_shove *= exp(-delta * (5.0 if kind == "drone" else 9.0))
	_flinch = maxf(_flinch - delta * 6.0, 0.0)         # and a short shake
	_pose()


func _pose() -> void:
	if _root == null:
		return
	var shake := Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 0.02 * _flinch
	if kind == "turret":
		_root.position = _seat + shake
		_apply_turret()
		return
	_root.position = _seat + _knock + shake - Vector3(0.0, _sink, 0.0)
	var tilt := Basis(_tilt.normalized(), _tilt.length()) if _tilt.length() > 0.0001 else Basis.IDENTITY
	if kind == "drone":
		_root.basis = tilt * Basis(Vector3.RIGHT, _apitch) * _base
	else:
		_root.basis = tilt * _base
		for i in _aims.size():
			var a: Dictionary = _aims[i]
			var r := Basis(a.axis as Vector3, _ayaw if i == 0 else _apitch)
			(a.node as Node3D).transform = Transform3D(r, (a.pivot as Vector3) - r * (a.pivot as Vector3))


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
	if state == DEAD:
		# the wreck: what the aim added to the clip's pose goes (the turret's head must hang, not hold its last
		# pitch), and it comes down the last of the way to the floor as the clip's fall ends
		_ayaw = move_toward(_ayaw, 0.0, 4.0 * delta)
		_apitch = move_toward(_apitch, 0.0, 3.0 * delta)
		_tpitch = move_toward(_tpitch, 0.0, 2.5 * delta)
		_sink = _gap * smoothstep(0.25, 1.05, ap.current_animation_position) if clip == "Death" else _sink
		_springs(delta)
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
	_springs(delta)
