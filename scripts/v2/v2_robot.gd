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

enum { ROAM, ENGAGE, AIM, SHOOT, DEAD, PREVIEW, TRAVEL, WATCH }
const STATE_NAMES := ["roam", "engage", "aim", "shoot", "dead", "preview", "travel", "watch"]
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
	"turret": {"hp": 180.0, "damage": 2.5, "spread": 0.8, "turn": 150.0, "eye": 2.8, "cooldown": [1.1, 1.9]},
}
const AIM_LAG := 0.3              # seconds the aim point trails the player
# The turret is a rotary gun (user: "a sound like a rolling gatling gun before firing", "fire longer, like 15-20
# shots instead of 2-3"): its barrels run up for SPIN_UP seconds, heard, before the first round; then the firing
# part of its Shoot clip (four rounds, frames 4 to 20 of it) is run GATLING[0] times as fast and repeated, 4 or 5
# times: 16 or 20 rounds at 12 a second; then it runs down. A round does 2.5 (it was 7 for four rounds).
const SPIN_UP := 0.85
const GATLING := [2.0, 4.0 / 24.0, 20.0 / 24.0]      # clip speed; the repeated part, seconds into the clip
# A wreck is in the way (user: "make all dead robots solid, so the character has to jump through them"): once it
# lies still it gets one low box over its footprint, WRECK_TOP high at most: the player jumps 0.83 m.
const WRECK_TOP := 0.55
const TURN_RATE := 60.0           # degrees a second the spider's Turn clip turns at speed 1 (anim_robots.py)
# how hard a round from the player pushes: [body knock m/s, tilt rad/s, shove along the floor / through the air m/s]
const PUSH := {"spider": [1.5, 3.2, 0.7], "drone": [1.2, 5.0, 2.2], "turret": [0.0, 4.5, 0.0]}
# a joint knocked by a round swings on a spring: [natural frequency rad/s, damping 1/s] of a live robot's joint (a
# quick twitch: the motors hold it) and of a wreck's (limp: the spider's legs and the drone's ducts flop and
# settle; the turret's arm hangs from the ceiling and swings a long time)
const FLOP_LIVE := [30.0, 16.0]
const FLOP_DEAD := {"spider": [15.0, 3.2], "drone": [15.0, 3.2], "turret": [7.0, 3.0]}
# how much of a round's push a wreck takes: [struck joint, the whole body]. The turret is a heavy arm on a ceiling
# mount: a round rocks it a few degrees and it settles within a second (it used to swing 80 degrees for a long time, like a
# lamp on a cord).
const WRECK_PUSH := {"spider": [1.0, 0.45], "drone": [1.0, 0.45], "turret": [0.22, 0.08]}
const DIVE := 0.6                # the drone shot down: its Death clip's fall is played at this speed (1.7 s to the floor)
const ROOM := Rect2(-3.6, -13.0, 9.0, 15.0)     # where a wreck may be shoved to and the falling drone may fly (room frame)
const BLAST := [3.5, 40.0]                      # the drone's explosion: reach (m), damage at its centre
const RESPAWN := 6.0             # seconds a wreck lies before the robot is back
const LOW := 1.7                  # a drone's height in a corridor or a doorway (they are lower than a room)

signal destroyed(robot: V2Robot)
signal struck                       # a training dummy was hit (`dummy`)
signal arrived(robot: V2Robot)      # at the end of its way (`follow`), or stopped on it: the game gives it its new arena

var kind := ""
var ap: AnimationPlayer
var clip := ""
var state := ROAM
var hp := 1.0
var max_hp := 1.0
var player: V2Player
var active := false               # the player is in this robot's room
var auto := true                  # preview: cycle through the clips
var _dummy_last := false          # the next round that strikes the dummy destroys it (`finish_off`)
var dummy := false                # a target to practise on: it stands (the preview's Idle), a hit jars it, nothing more
var shots_fired := 0
var travelled := 0.0
var kills := 0                    # times it was destroyed
# the game makes its robots a little sharper than the lab's (v2_game.gd TOUGH): against the lab's numbers a player
# who keeps moving sideways is seldom hit (measured with the bot)
var aim_lag := AIM_LAG            # seconds its aim point trails the player
var damage_scale := 1.0
var haste := 1.0                  # > 1 = shorter pauses between its bursts
var respawns := true              # the lab: a wreck is replaced after RESPAWN seconds. The game: it stays a wreck
var arena := Rect2()              # the part of its room's floor it may be in (room frame): SPEC's, or its own (the game)
var rail := Vector2.ZERO          # turret: the z it may travel between along its ceiling rail (room frame); equal = fixed
var show_label := true
var alerted := false              # it has seen the player or been hit by them
var room := 0                     # which room it is in (the game: the dungeon's area)
var bounds := ROOM                # where a wreck may be shoved to and a falling drone may fly (its parent's frame)
var grid := 0.0                   # > 0 (the game: the dungeon's cells, 4 m): it goes from the middle of a cell to the middle of
#                                   another along the rows and columns, never across a cell's corner: columns and tanks stand there
var others: Array = []            # the robots it shares its floor with: it keeps its firing position off theirs
var _route: Array = []            # on its way somewhere (`follow`): [[point (its parent's frame), low: bool], ...]
var _watch := Vector3.INF         # the player is down: what it has come to look at (world); INF = nothing
var _watch_spot := Vector3.ZERO   # and where it stands to look (its parent's frame)
var _rail_dir := 1.0
var _spec: Dictionary
var _root: Node3D                 # the glb's <Kind>_Root joint, re-seated on this node
var _bodies: Array[RID] = []        # the hit boxes, one per part (on its joint)
var _solids: Array[StaticBody3D] = []
var _wreck_body: StaticBody3D     # what stops the player at a wreck
var _spin_up := 0.0               # turret: seconds its barrels have been running up (0 = at rest)
var _passes := 0                  # turret: how often the firing part of the clip is still to be repeated
var floor_y := 0.0                # what it stands on (the training dummy: its pad)
var _flop: Dictionary = {}          # joint -> {off, vel (axis * angle, the joint's frame), base, mine}
var _spin := 0.0                    # drone, shot down: seconds of flight out of control still to go
var _spin_total := 1.0
var _vel := Vector3.ZERO            # its velocity then (room frame)
var _own_vel := Vector3.ZERO        # where it is flying / walking to, and how fast (room frame): a drone shot down keeps this line
var _wob := 0.0
var _spark_t := 0.0
var _short_t := 0.0                 # wreck: seconds to its next short circuit
var _dead_for := 0.0
var _parts: Array = []              # [joint, centre of its meshes (the joint's frame)]: where a wreck can spark
var _seat_y := 0.0
var _exploded := true
var _rotor: AudioStreamPlayer3D     # drone: the loop of its rotors
var _step_i := -1                   # spider: which footfall of its gait was last heard
var _servo_t := 0.0
var _crashed := true
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
var _wounds := 0                  # the training dummy: how often it was struck
var _twitch := 0.0
const REACTIONS := ["cower", "stagger", "buckle", "rear", "turn"]
var _react := ""                  # the training dummy: the reaction it is in ("" = calm), `_dummy_tick`
var force_react := ""             # (for the pictures: the reaction the next hit starts)
var _last_react := ""
var _rt := 0.0                    # seconds into it
var _rhold := 0.0                 # until when it holds it (a new hit pushes this on)
var _rdur := 0.0                  # when it is over
var _rside := 1.0                 # the side it goes to
var _ramp := 1.0                  # how deep (grows when struck again while it lasts)
var _rhome := INF                 # its heading at rest (one reaction turns the whole of it away)
var _rx_tilt := Vector3.ZERO      # what the reaction adds to the body's tilt (axis * angle, its own frame) and place
var _rx_pos := Vector3.ZERO
var _list := 0.0                  # how far it lists to a side for good
var _breath := 0.0
## Squares that spiders and drones go round: [middle (world), half its side with room for the robot]. Set by the
## scene (the game: the training cage), emptied by every scene's `_ready`.
static var no_go: Array = []
var _via := Vector3.INF           # the corner of such a square it is going round by
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
	_spec = (SPEC[kind] as Dictionary).duplicate()     # (its own copy: the game changes a robot's numbers)
	max_hp = _spec.hp
	hp = max_hp
	arena = _spec.get("arena", Rect2())
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
	_part_boxes(scene)
	_seat_y = _seat.y
	if kind == "drone":
		_rotor = V2Sfx.loop("drone_rotor", _hit_joint)
	# the clips are advanced from _process (not by the player on its own), so that what this script adds to a
	# joint (aim, a knock from a round) goes on top of the clip's pose of the same frame
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
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


## A hit box on every joint that carries meshes (body, each leg segment, turret, guns, arm segments, ducts): a
## round hits the part it is aimed at, alive or wrecked, and the robot knows which joint to knock.
func _part_boxes(scene: Node) -> void:
	for n in scene.find_children("*", "Node3D", true, false):
		if n is MeshInstance3D or n is Light3D:
			continue
		var box := AABB()
		var any := false
		for c in n.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null or String(mi.name).contains("Flash") or mi.scale.x < 0.01:
				continue
			var bb := mi.transform * mi.mesh.get_aabb()
			box = box.merge(bb) if any else bb
			any = true
		if not any or box.get_longest_axis_size() < 0.08:
			continue
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box.size.max(Vector3(0.06, 0.06, 0.06))
		shape.shape = bs
		shape.position = box.get_center()
		body.add_child(shape)
		body.set_meta("robot", self)
		body.set_meta("joint", n)
		n.add_child(body)
		_bodies.append(body.get_rid())
		_solids.append(body)
		_parts.append([n, box.get_center()])


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
		V2Fx.set_smoke(_smoke, false)
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


## Stand it somewhere else in its room than where the Blender scene has it (the game). yaw in degrees.
func place(at: Vector3, yaw_deg: float) -> void:
	_home = Vector3(at.x, 0.0, at.z)
	_home_yaw = deg_to_rad(yaw_deg)
	_go_home()
	_target = position


## Turret: a rail under the ceiling from z0 to z1 (room frame) that its pylon runs along, and the carriage it hangs
## from. Call before the room's render layer is set.
func set_rail(z0: float, z1: float, layer: int = 0) -> void:
	rail = Vector2(minf(z0, z1), maxf(z0, z1))
	var top := _seat.y + 1.7                           # the ceiling: the pylon's upper end
	for spec in [[Vector3(0.5, 0.05, rail.y - rail.x + 0.9), Vector3(_home.x, top - 0.025, (rail.x + rail.y) / 2.0), "DarkSteel", get_parent()],
			[Vector3(0.09, 0.07, rail.y - rail.x + 0.9), Vector3(_home.x - 0.17, top - 0.085, (rail.x + rail.y) / 2.0), "Steel", get_parent()],
			[Vector3(0.09, 0.07, rail.y - rail.x + 0.9), Vector3(_home.x + 0.17, top - 0.085, (rail.x + rail.y) / 2.0), "Steel", get_parent()],
			[Vector3(0.62, 0.1, 0.62), Vector3(0.0, top - 0.17, 0.0), "DarkSteel", self]]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[0]
		mi.mesh = box
		mi.material_override = V2Assets.material(spec[2])
		(spec[3] as Node3D).add_child(mi)
		mi.position = spec[1]
		if layer != 0:
			mi.layers = layer


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
	_spin = 0.0
	_exploded = true
	_crashed = true
	_route.clear()
	_seat.y = _seat_y
	for j in _flop:
		(j as Node3D).transform = _flop[j].base
	_flop.clear()
	_pose()


## A working robot stands in the player's way; a wreck does not (rounds still strike it: they ask every layer).
## A wreck that blocked could shut a doorway or the gap by the stairs for good.
func _solid(on: bool) -> void:
	for b in _solids:
		b.collision_layer = 1 if on else 2


func respawn() -> void:
	_solid(true)
	if is_instance_valid(_wreck_body):
		_wreck_body.queue_free()
	_wreck_body = null
	var was_wreck := state == DEAD
	hp = max_hp
	state = ROAM
	_watch = Vector3.INF
	V2Fx.set_smoke(_smoke, false)
	_settle()
	_go_home()
	if was_wreck:
		V2Sfx.play("power_up", hit_point())                # back in service
	_target = position
	_pause = -1.0
	_cool = 1.5
	_aim_valid = false
	_play("Idle", 1.0, true)


func hit_point() -> Vector3:
	return _hit_joint.global_position


func flash_on() -> bool:
	for f in _flashes:
		if f.on:
			return true
	return false


## The training dummy between and after hits (**user: "have different animations from it getting shot", "make
## the animation longer and less twitchy"**). Calm, its head follows the player round the room. Struck, it plays
## one of five reactions, never the same twice running, each about three and a half seconds, slow and heavy:
##   cower    it leans back and away, steps uneasily (Walk, slow), turns its head aside
##   stagger  it is thrown to one side and sways there and back, stepping to keep its feet (Turn, slow)
##   buckle   its legs give (the start of the Death clip), it sinks, then gathers itself and rises
##   rear     its front comes up, it holds, comes down, and shakes its head slowly
##   turn     it steps round, away from the shot, stands turned away looking back, and steps round again
## Every pose is a target that the body follows smoothly (`_rx_tilt`, `_rx_pos`, the head at a limited rate): no
## impulses, nothing random from frame to frame. Struck again while one lasts, it does not start over: it reels
## deeper and holds longer. Every wound stays: it heaves as it breathes, lists a little, smokes from the third.
func _dummy_tick(delta: float) -> void:
	_left = 99.0                                           # (the preview's own clock does not restart clips here)
	var want_tilt := Vector3(0.0, 0.0, _list)
	var want_pos := Vector3.ZERO
	var head := Vector2.INF                                # yaw, pitch it holds its head at; INF = on the player
	if _react != "":
		_rt += delta
		var e := smoothstep(0.0, 0.4, _rt) * (1.0 - smoothstep(_rhold, _rdur, _rt)) * _ramp
		match _react:
			"cower":
				want_tilt += Vector3(0.2, 0.0, _rside * 0.05) * e
				want_pos += Vector3(0.0, 0.0, 0.1) * e
				head = Vector2(_rside * 0.9, 0.3) * minf(e, 1.0)
				if _rt < _rhold - 0.5:
					_play("Walk", 0.55)
				else:
					_ease_to("Idle", 0.7)
			"stagger":
				var sway := _rside * exp(-_rt * 0.55) * cos(_rt * 2.4) * smoothstep(0.0, 0.3, _rt) * _ramp
				want_tilt += Vector3(0.04, 0.0, 0.26 * sway)
				want_pos += Vector3(0.13 * sway, 0.0, 0.03)
				head = Vector2(-_rside * 0.5 * sway, 0.15)
				if _rt < _rhold - 0.3:
					_play("Turn", 0.7)
				else:
					_ease_to("Idle", 0.7)
			"buckle":
				want_tilt += Vector3(-0.1, 0.0, _rside * 0.04) * e
				head = Vector2(_rside * 0.25, 0.45) * minf(e, 1.0)
				if _rt >= 0.75 and clip == "Death":
					_ease_to("Idle", 1.2)
			"rear":
				var up := smoothstep(0.0, 0.35, _rt) * (1.0 - smoothstep(_rhold - 0.9, _rhold - 0.4, _rt)) * _ramp
				want_tilt += Vector3(0.3 * up, 0.0, 0.0)
				want_pos += Vector3(0.0, 0.05 * up, 0.06 * up)
				var after := _rt - (_rhold - 0.4)
				head = Vector2(0.55 * sin(after * TAU * 0.9) * exp(-after * 0.8), 0.1) if after > 0.0 else Vector2(0.0, -0.3 * up)
				_ease_to("Idle", 0.5)
			"turn":
				var to := _rhome + (_rside * 0.75 if _rt < _rhold else 0.0)
				var left := _step_round(Vector3(-sin(to), 0.0, -cos(to)), delta * 0.55)        # (slowly: it is hurt)
				if left < deg_to_rad(2.0):
					_ease_to("Idle", 0.4)
				want_tilt += Vector3(0.06, 0.0, _rside * 0.05) * e
		if _rt >= _rdur:
			_react = ""
			_ramp = 1.0
			_ease_to("Idle", 0.5)
	elif _rhome != INF and absf(angle_difference(rotation.y, _rhome)) > deg_to_rad(2.0):      # (still turned away: round again)
		if _step_round(Vector3(-sin(_rhome), 0.0, -cos(_rhome)), delta * 0.55) < deg_to_rad(2.0):
			_ease_to("Idle", 0.4)
	if _wounds > 0:                                        # hurt, it heaves
		_breath += delta * minf(1.3 + 0.2 * _wounds, 2.6)
		want_pos.y += sin(_breath) * 0.005 * minf(_wounds, 6)
		want_tilt.x += sin(_breath) * 0.006 * minf(_wounds, 6)
		_twitch -= delta
		if _twitch <= 0.0 and _wounds >= 4 and not _parts.is_empty():      # and something in it shorts now and then
			_twitch = randf_range(3.0, 6.0)
			var j := (_parts[randi() % _parts.size()] as Array)[0] as Node3D
			if is_instance_valid(j):
				V2Fx.sparkle(j.global_position, 5, -6.0)
	var follow := 1.0 - exp(-delta * 6.0)
	_rx_tilt = _rx_tilt.lerp(want_tilt, follow)
	_rx_pos = _rx_pos.lerp(want_pos, follow)
	if head != Vector2.INF:
		_ayaw = move_toward(_ayaw, clampf(head.x, -1.2, 1.2), 2.0 * delta)
		_apitch = move_toward(_apitch, clampf(head.y, -0.6, 0.6), 1.5 * delta)
	elif player != null and not _aims.is_empty():          # it looks at the player
		_aim_point = player.global_position + Vector3(0, 1.3, 0)
		_aim_valid = true
		_servo(delta * (0.35 if _wounds == 0 else 0.5), true)


## Go over to a clip with a long blend (a change of pose that takes its time).
func _ease_to(clip_name: String, blend: float) -> void:
	if clip == clip_name or ap == null or not ap.has_animation(clip_name):
		return
	ap.speed_scale = 1.0
	clip = clip_name
	ap.play(clip_name, blend)


## The training dummy: the round that has just struck it was the last one wanted. It falls apart as a robot does.
func finish_off(dir: Vector3) -> void:
	_dummy_last = true
	_react = ""
	_rx_tilt = Vector3.ZERO
	_rx_pos = Vector3.ZERO
	hit(1.0, dir)
	_shove = Vector3.ZERO


## A round from the player, flying along `dir`, that struck at `point` the part on `joint`.
func hit(damage: float = 34.0, dir: Vector3 = Vector3.ZERO, point: Vector3 = Vector3.INF, joint: Node3D = null) -> void:
	if dummy and _dummy_last:                              # the training's last round: it is destroyed like any robot
		dummy = false
		state = ROAM
		hp = 0.01
	if dummy:
		if dir == Vector3.ZERO:
			dir = Vector3.FORWARD
		if point == Vector3.INF:
			point = hit_point()
		# (**user: "make the dummy robot more reactive to the shots he's taking, like he's alive. make him
		# 'suffer' after a shot"**, then "different animations", "longer and less twitchy": `_dummy_tick`)
		_wounds += 1
		_flinch = 0.5
		if _rhome == INF:
			_rhome = rotation.y
		_knock_joint(joint if joint != null else _hit_joint, point, dir, 0.8)
		_push(dir, 1.1)
		_shove = Vector3.ZERO                          # (it keeps its place on its pad)
		var side := signf((global_basis.inverse() * dir).x + (point - global_position).dot(global_basis.x) * 0.5)
		if side == 0.0:
			side = 1.0 if randf() < 0.5 else -1.0
		_list = clampf(_list + side * 0.012, -0.07, 0.07)
		if _react == "" or _rt > _rhold:               # calm, or coming out of the last one: another, not the same again
			var others: Array = REACTIONS.filter(func(r: String) -> bool: return r != _last_react)
			_react = others[randi() % others.size()] if force_react == "" else force_react
			_last_react = _react
			_rt = 0.0
			_ramp = 1.0
			_rside = side
			_rhold = {"cower": 2.2, "stagger": 2.6, "buckle": 2.2, "rear": 2.6, "turn": 2.3}[_react]
			_rdur = _rhold + 1.3
			if _react == "buckle":
				_play("Death", 0.8, true)
			V2Sfx.play("servo", point, 3.0, {"cower": 1.6, "stagger": 1.25, "buckle": 0.8, "rear": 1.85, "turn": 1.4}[_react])
		else:                                          # struck while it reels: deeper, and longer
			_ramp = minf(_ramp + 0.15, 1.5)
			_rhold = maxf(_rhold, _rt + 0.9)
			_rdur = _rhold + 1.3
		V2Fx.sparkle(point, 6 + mini(_wounds, 6), -4.0)
		V2Sfx.play("robot_hit", point, 2.0)
		if _wounds >= 3:
			V2Fx.set_smoke(_smoke, true)
		struck.emit()
		return
	if state == PREVIEW:
		if clip != "Death":
			play("Death")
		return
	if dir == Vector3.ZERO:
		dir = (global_position - player.global_position).normalized() if player != null else Vector3.FORWARD
	if point == Vector3.INF:
		point = hit_point()
	if state == DEAD:
		# the wreck is still a thing in the room: the part that is struck swings, the whole of it is jarred
		_knock_joint(joint if joint != null else _hit_joint, point, dir, WRECK_PUSH[kind][0])
		_push(dir, WRECK_PUSH[kind][1])
		if randf() < 0.4:
			V2Fx.sparkle(point, 7, -3.0)               # (something inside still has power)
		return
	_knock_joint(joint if joint != null else _hit_joint, point, dir, 0.5)
	_push(dir, 1.6 if hp - damage <= 0.0 else 1.0)
	V2Sfx.play("robot_hit", point)
	hp -= damage
	if hp <= 0.0:
		hp = 0.0
		kills += 1
		state = DEAD
		# (its part boxes stop rounds only from here on; a spider or a drone gets one box on the floor when it has
		# come to rest, `_wreck_solid`. The turret's wreck hangs from the ceiling with its head at the height of the
		# player's: solid, it shut the middle of its cell to everything, and nobody jumps over that.)
		_solid(false)
		_spin_up = 0.0
		destroyed.emit(self)
		_dead_for = 0.0
		_short_t = randf_range(0.25, 0.6)
		V2Fx.set_smoke(_smoke, true)
		V2Fx.burst(hit_point())
		if kind == "drone":
			# shot down, it goes down like an aircraft: on along the line it was flying (the way it faces, if it
			# was hovering), nose dropping, faster and faster, into the floor or whatever is in its way, and blows
			# up there. No spinning about: the first version careered round the room like a top.
			_exploded = false
			var going := _own_vel                          # (its own flight: not the shove of the rounds that hit it)
			going.y = 0.0
			if going.length() < 0.8:
				going = -global_basis.z
				going.y = 0.0
			_vel = going.normalized() * maxf(_own_vel.length(), 2.6)
			_spin_total = ap.get_animation("Death").length
			_spin = 1.0                                    # > 0 while it is still in the air
			_shove = Vector3.ZERO
			_play("Death", DIVE, true)
			_t = 1.02 / DIVE + ap.get_animation("Death").length + RESPAWN
		else:
			_play("Death", 1.0, true)
			_t = ap.get_animation("Death").length + RESPAWN
			_crashed = kind != "spider"                    # (the spider's body hits the floor later in the clip)
			V2Sfx.play("power_down", hit_point())
	else:
		_flinch = 1.0
		alerted = true
		_cool = maxf(_cool, 0.3)                       # it loses its aim for a moment
		if state == ROAM and kind != "turret":
			_engage()                                  # it knows where that came from


## The wreck becomes a thing in the way: once it lies still (the spider's body is down, the drone has come down
## and blown up) and the player does not stand in it, one box over the footprint of its parts, as high as they
## reach but WRECK_TOP at most, so that it can always be jumped (its parts above that are not solid).
func _wreck_solid() -> void:
	if _wreck_body != null or kind == "turret" or not _crashed or not _exploded or _spin > 0.0:
		return
	if clip == "Death" and ap.is_playing() and ap.current_animation_position < ap.current_animation_length - 0.05:
		return
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for b in _solids:
		var shape := b.get_child(0) as CollisionShape3D
		var half: Vector3 = (shape.shape as BoxShape3D).size / 2.0
		var xf := shape.global_transform
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p := xf * (half * Vector3(sx, sy, sz))
					lo = lo.min(p)
					hi = hi.max(p)
	if lo.x > hi.x:                                        # (no parts: headless without mesh data)
		lo = global_position - Vector3(0.8, 0.0, 0.8)
		hi = global_position + Vector3(0.8, 0.5, 0.8)
	# (a little inside the outermost leg tips and duct edges: what is jumped is the bulk of it)
	var size := Vector3(maxf((hi.x - lo.x) * 0.8, 0.5), clampf(hi.y - global_position.y, 0.25, WRECK_TOP), maxf((hi.z - lo.z) * 0.8, 0.5))
	var mid := Vector3((lo.x + hi.x) / 2.0, global_position.y + size.y / 2.0, (lo.z + hi.z) / 2.0)
	if player != null:
		var d := player.global_position - mid
		if absf(d.x) < size.x / 2.0 + 0.45 and absf(d.z) < size.z / 2.0 + 0.45 and player.global_position.y < mid.y + size.y:
			return                                         # (the player stands in it: when they have stepped out)
	_wreck_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	_wreck_body.add_child(cs)
	_wreck_body.top_level = true
	_wreck_body.set_meta("wreck", self)
	add_child(_wreck_body)
	_wreck_body.global_transform = Transform3D(Basis.IDENTITY, mid)
	_bodies.append(_wreck_body.get_rid())


## A wreck's short circuits: sparks and a crackle from one of its parts, often just after it dies, then now and
## then. (The drone in its last flight sheds its own sparks: `_spin_out`.)
func _shorts(delta: float) -> void:
	_dead_for += delta
	if _spin > 0.0 or not _exploded or _parts.is_empty():
		return
	_short_t -= delta
	if _short_t > 0.0:
		return
	var calm := smoothstep(0.5, 5.0, _dead_for)
	_short_t = randf_range(lerpf(0.25, 1.2, calm), lerpf(0.9, 3.2, calm))
	if not respawns:
		_short_t *= 1.0 + smoothstep(8.0, 40.0, _dead_for) * 5.0      # (and its short circuits become rare)
	var part: Array = _parts[randi() % _parts.size()]
	var at: Vector3 = (part[0] as Node3D).global_transform * (part[1] as Vector3)
	V2Fx.sparkle(at, randi_range(10, 20), -2.0 - 4.0 * calm)
	if randf() < 0.35:
		_short_t = randf_range(0.08, 0.2)              # (they come in twos and threes)


## The joint that was struck, and the joints it hangs from (less and less), are set swinging about their own
## pivots by the round's push on them: torque = (where it struck - the pivot) x (the way it flew).
func _knock_joint(joint: Node3D, point: Vector3, dir: Vector3, k: float) -> void:
	var n: Node = joint
	var i := 0
	while n != null and n != _root and n != self and i < 4:
		var j := n as Node3D
		if j != null and not (String(j.name) in ["AimYaw", "AimPitch"]):
			var torque := (point - j.global_position).cross(dir)
			var local := j.global_basis.orthonormalized().inverse() * torque
			if not _flop.has(j):
				_flop[j] = {"off": Vector3.ZERO, "vel": Vector3.ZERO, "base": j.transform, "mine": j.transform}
			_flop[j].vel += (local * 16.0 + local.normalized() * 1.5) * k / (1.0 + i * 1.5)
			i += 1
		n = n.get_parent()


## Knocked by a round: the body jumps back on its seat and tips away from the shot (both on springs), and the
## spider is shoved a little over the floor, the drone a good way through the air; the turret's arm is swung aside.
func _push(dir: Vector3, k: float) -> void:
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
	# (the speed first: the spider's right turn runs its clip backwards, and a clip started while the speed is
	# still negative ends on the spot. A spider killed in mid-turn stood frozen instead of falling.)
	ap.speed_scale = speed
	if clip != clip_name or restart or not ap.is_playing():
		clip = clip_name
		ap.play(clip_name, 0.0 if restart else 0.12)
		if restart:
			ap.seek(0.0, true)


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
	# It sees the player if it can see their chest or their head; it aims at the part it sees. (With the chest
	# alone, a player behind the stairs' railings could see and shoot a spider that could not see them: measured
	# with the bot, the two spiders of the game's sector B never fired a round at it.)
	var seen := Vector3.INF
	_sees = false
	if active and not player.down:
		for point in [player.chest(), player.cam.global_position - Vector3(0.0, 0.08, 0.0)]:
			var q := PhysicsRayQueryParameters3D.create(_eye(), point)
			q.collision_mask = V2World.SHOTS
			q.exclude = _bodies
			var res := get_world_3d().direct_space_state.intersect_ray(q)
			if not res.is_empty() and res.collider == player:
				_sees = true
				seen = point
				break
	if _sees:
		alerted = true
		_unseen = 0.0
		_aim_point = _aim_point.lerp(seen, 1.0 - exp(-delta / aim_lag)) if _aim_valid else seen
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
	V2Sfx.play(kind + "_shot", from)
	var to := from + dir * 40.0
	var q := PhysicsRayQueryParameters3D.create(from + dir * 0.15, to)
	q.collision_mask = V2World.SHOTS
	q.exclude = _bodies
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if not res.is_empty():
		to = res.position
		if res.collider == player:
			player.hurt(_spec.damage * damage_scale, from)
			to -= dir * minf(1.3, from.distance_to(to) * 0.5)      # (a streak that ends at the eye fills the screen)
		else:
			V2Fx.impact(to, res.normal)
			# a miss that passes the player's head is heard going by
			var head := player.cam.global_position
			var along := clampf((head - from).dot(dir), 0.0, from.distance_to(to))
			if (from + dir * along).distance_to(head) < 1.3:
				V2Sfx.play("flyby")
	V2Fx.tracer(from, to, V2Fx.RED)
	V2Fx.puff(from, dir, V2Fx.GUNSMOKE, 0.22, 2, 0.7, 0.22, 0.5)


# ---------------------------------------------------------------- spider and drone
## From here toward what it aims at (the player's place a moment ago; the player if it has not seen them yet).
func _aim_dir() -> Vector3:
	return (_aim_point if _aim_valid else player.global_position) - global_position


func _local(p: Vector3) -> Vector3:
	return p - (get_parent() as Node3D).global_position


## A place to go to: inside its arena, and (with `grid`) the middle of the cell it falls in.
func _spot(p: Vector3) -> Vector3:
	if grid > 0.0:
		p = Vector3((floorf(p.x / grid) + 0.5) * grid, 0.0, (floorf(p.z / grid) + 0.5) * grid)
	return _clamp_arena(p)


func _clamp_arena(p: Vector3) -> Vector3:
	var a: Rect2 = arena
	return Vector3(clampf(p.x, a.position.x, a.end.x), 0.0, clampf(p.z, a.position.y, a.end.y))


func in_arena(margin: float = 0.05) -> bool:
	if kind == "turret":
		return absf(position.x - _home.x) < 0.01 and position.z >= minf(rail.x, _home.z) - 0.01 and position.z <= maxf(rail.y, _home.z) + 0.01
	return arena.grow(margin).has_point(Vector2(position.x, position.z))


func _pick_roam() -> void:
	var a: Rect2 = arena
	var pl := _local(player.global_position)
	for k in 10:
		var c := _spot(Vector3(randf_range(a.position.x, a.end.x), 0.0, randf_range(a.position.y, a.end.y)))
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
		var c := _spot(pl + Vector3(cos(ang), 0.0, sin(ang)) * randf_range(_spec.keep[0], _spec.keep[1]))
		var d := c.distance_to(pl)
		var score := maxf(_spec.keep[0] - d, 0.0) * 4.0 + absf(c.distance_to(position) - 2.5) * 0.5
		for o in others:
			if o != self and is_instance_valid(o) and (o as V2Robot).state != DEAD and (o as V2Robot).kind == kind \
					and c.distance_to((o as V2Robot)._target) < 2.6:
				score += 4.0
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


## A place out of every `no_go` square: p itself, or the nearest point of the square's edge.
func _clear_of(p: Vector3) -> Vector3:
	for n in no_go:
		var c: Vector3 = n[0]
		var h: float = n[1]
		var d := p - c
		if absf(d.x) < h and absf(d.z) < h:
			if h - absf(d.x) < h - absf(d.z):
				p.x = c.x + (h + 0.06) * (1.0 if d.x >= 0.0 else -1.0)
			else:
				p.z = c.z + (h + 0.06) * (1.0 if d.z >= 0.0 else -1.0)
	return p


## Does the straight way from a to b cross the square of middle c and half side h? (on the floor's plane)
static func _crosses(a: Vector3, b: Vector3, c: Vector3, h: float) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	for axis in [0, 2]:
		var p: float = a[axis] - c[axis]
		var v: float = b[axis] - a[axis]
		if absf(v) < 1e-6:
			if absf(p) >= h:
				return false
		else:
			var ta := (-h - p) / v
			var tb := (h - p) / v
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 >= t1:
				return false
	return true


## Where to head for to get from where it is to `to` without crossing a `no_go` square: `to`, or a corner of the
## square to go round first. The corner is kept until it is reached (`_via`): choosing afresh every frame, it
## turned back and forth between two of them. Then the next one: the one that makes the shorter way, of those in
## plain view.
func _round(to: Vector3) -> Vector3:
	for n in no_go:
		var c: Vector3 = n[0]
		var h: float = n[1]
		if not _crosses(position, to, c, h + 0.03):
			continue
		if _via != Vector3.INF and position.distance_to(_via) > 0.12:
			return _via
		var best := to
		var best_len := 1e9
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var k := Vector3(c.x + sx * (h + 0.25), position.y, c.z + sz * (h + 0.25))
				if (_via != Vector3.INF and k.distance_to(_via) < 0.01) or _crosses(position, k, c, h - 0.15):
					continue
				var length := position.distance_to(k) + k.distance_to(to)
				if length < best_len:
					best_len = length
					best = k
		_via = best if best != to else Vector3.INF
		return best
	_via = Vector3.INF
	return to


## One step toward _target; true when it is there. face_player: keep the nose on the player while moving.
func _move(delta: float, fast: bool, face_player: bool) -> bool:
	if not no_go.is_empty() and kind != "turret":
		_target = _clear_of(_target)
		var via := _round(_target)
		if via != _target:
			return _move_to(via, delta, fast, face_player, true)
	return _move_to(_target, delta, fast, face_player, false)


func _move_to(goal: Vector3, delta: float, fast: bool, face_player: bool, around: bool) -> bool:
	var to := goal - position
	to.y = 0.0
	if grid > 0.0 and state != WATCH and not around and absf(to.x) > 0.35 and absf(to.z) > 0.35:
		to = Vector3(to.x, 0.0, 0.0) if absf(fposmod(position.z, grid) - grid / 2.0) < absf(fposmod(position.x, grid) - grid / 2.0) \
			else Vector3(0.0, 0.0, to.z)                   # (first along the row or the column it is on the middle of)
		for n in no_go:                                    # (unless that leg leads into what it goes round: then straight)
			if _crosses(position, position + to, n[0], float(n[1]) + 0.03):
				to = goal - position
				to.y = 0.0
	var dist := to.length()
	var clips: Array = _spec.clips
	_own_vel = Vector3.ZERO
	if dist < 0.3 and (_target - position).length() < 0.45 and not around:
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
	if pl.length() < 3.0 and pl.dot(to) > 0.0 and state != WATCH:      # never into the player
		k = 0.0
	var speed: float = (_spec.run if fast else _spec.walk) * k
	_own_vel = to / maxf(dist, 0.001) * speed
	var step := minf(speed * delta, dist)
	var moved := position + to / maxf(dist, 0.001) * step
	position = Vector3(clampf(moved.x, arena.position.x, arena.end.x), 0.0, clampf(moved.z, arena.position.y, arena.end.y))
	if not no_go.is_empty():
		position = _clear_of(position)
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
	_own_vel = Vector3.ZERO                            # (_move sets it when it moves)
	if state == TRAVEL:
		_servo(delta, false)
		_travel(delta)
		return
	if state == WATCH:
		_watching(delta)
		return
	if kind == "drone":
		_seat.y = move_toward(_seat.y, _seat_y, 1.5 * delta)
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
				_cool = randf_range(_spec.cooldown[0], _spec.cooldown[1]) / haste
				_engage()


## The player is down: come and look. `spot` = where to stand (its parent's frame), `at` = what to look at
## (world: the player's head on the floor), `way` = the way there if it is in another room (as for `follow`).
## It does not fire. The turret turns its head (and runs along its rail) to look.
func watch(at: Vector3, spot: Vector3, way: Array = []) -> void:
	if state == DEAD or state == PREVIEW:
		return
	_watch = at
	_watch_spot = Vector3(spot.x, 0.0, spot.z)
	_aim_point = at
	_aim_valid = true
	_cool = 1e6                                            # (no more rounds)
	if kind == "turret":
		return
	arena = Rect2(-1e6, -1e6, 2e6, 2e6)
	_route = way
	state = TRAVEL if not way.is_empty() else WATCH
	_target = _watch_spot


func _watching(delta: float) -> void:
	_aim_point = _watch
	_aim_valid = true
	_target = _watch_spot
	var far := Vector2(position.x - _watch_spot.x, position.z - _watch_spot.z).length()
	if kind == "drone":
		_seat.y = move_toward(_seat.y, 1.25 if far < 3.0 else _seat_y, 1.2 * delta)      # it comes down to look
	_servo(delta, true)
	if not _move(delta, far > 3.5, kind == "drone" and far < 2.0):
		return
	# there: turned to the player, still, its guns on them
	var dir := _local(_watch) - position
	if kind == "spider":
		var off := absf(angle_difference(rotation.y, atan2(-dir.x, -dir.z)))
		if off > deg_to_rad(10.0) or (clip == "Turn" and off > deg_to_rad(3.0)):
			_step_round(dir, delta)
		else:
			_rest_pose()
	else:
		_face(dir, _spec.turn, delta)
		_play(_spec.clips[4])


## Go somewhere along a way of points (its parent's frame; `low` = a corridor or a doorway: a drone comes down for
## it): after the player, through the dungeon's doorways (v2_game.gd finds the way). The turret stays where it hangs.
func follow(points: Array) -> void:
	if kind == "turret" or state == DEAD or state == PREVIEW or points.is_empty():
		return
	_route = points
	arena = Rect2(-1e6, -1e6, 2e6, 2e6)                    # (no floor of its own on the way)
	state = TRAVEL


func _travel(delta: float) -> void:
	# the end of the way; or the player in sight close by: it stops and fights where it stands
	var near := _sees and global_position.distance_to(player.global_position) < 11.0
	if _watch != Vector3.INF and _route.is_empty():        # (come to look at the player who is down: the last stretch)
		state = WATCH
		return
	if _route.is_empty() or near:
		_route.clear()
		state = ROAM
		arrived.emit(self)
		_target = position
		if near:
			_engage()
		return
	var wp: Array = _route[0]
	_target = Vector3((wp[0] as Vector3).x, 0.0, (wp[0] as Vector3).z)
	if kind == "drone":
		_seat.y = move_toward(_seat.y, LOW if bool(wp[1]) else _seat_y, 1.4 * delta)
	if _move(delta, true, false):
		_route.pop_front()


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
	if _watch != Vector3.INF:                              # (the player is down: it looks at them)
		_aim_point = _watch
		_aim_valid = true
	var tracking := _aim_valid and (_unseen < 2.5 or _watch != Vector3.INF)
	if rail.y > rail.x:
		# its carriage runs along the rail: to where the player is abreast of it, or slowly up and down on patrol
		var want := position.z
		if tracking:
			want = clampf(_local(_aim_point).z, rail.x, rail.y)
		else:
			want = rail.y if _rail_dir > 0.0 else rail.x
			if absf(position.z - want) < 0.05:
				_rail_dir = -_rail_dir
		var z := move_toward(position.z, want, (0.9 if tracking else 0.35) * delta)
		travelled += absf(z - position.z)
		position.z = z
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
		if state == AIM and _cool <= 0.0 and _sees and (_aim_err < deg_to_rad(3.0) or _spin_up > 0.0):
			# the barrels run up first: heard, and time to get out of its line
			if _spin_up <= 0.0:
				V2Sfx.play("turret_spin_up", hit_point())
			_spin_up += delta
			if _spin_up >= SPIN_UP / haste and _aim_err < deg_to_rad(4.0):
				state = SHOOT
				_passes = 3 + randi() % 2                  # the firing part 4 or 5 times: 16 or 20 rounds
				_play("Shoot", GATLING[0], true)
		elif state == AIM and _spin_up > 0.0:              # (lost sight of them while running up)
			_spin_up = 0.0
			V2Sfx.play("turret_spin_down", hit_point())
		elif state == SHOOT:
			var at := ap.current_animation_position
			if at >= GATLING[2] and _passes > 0:
				_passes -= 1
				ap.seek(at - (GATLING[2] - GATLING[1]), true)
			elif (at >= GATLING[2] + 0.04 and _passes <= 0) or not ap.is_playing():
				state = AIM
				_spin_up = 0.0
				V2Sfx.play("turret_spin_down", hit_point())
				V2Sfx.play("turret_tail", hit_point())
				_cool = randf_range(_spec.cooldown[0], _spec.cooldown[1]) / haste
				_rest_pose()
	else:
		if state != ROAM:
			state = ROAM
			if _spin_up > 0.0:
				V2Sfx.play("turret_spin_down", hit_point())
		_spin_up = 0.0
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
		for j in _flop:
			var f: Dictionary = _flop[j]
			var spec: Array = FLOP_DEAD[kind] if state == DEAD else FLOP_LIVE
			f.vel += (-f.off * spec[0] * spec[0] - f.vel * 2.0 * spec[1]) * h
			f.off = (f.off + f.vel * h).limit_length(1.0)
	for j in _flop.keys():
		var f2: Dictionary = _flop[j]
		var node := j as Node3D
		if node.transform != f2.mine:
			f2.base = node.transform                   # (the clip has moved the joint since: that is its pose now)
		if (f2.off as Vector3).length() < 0.003 and (f2.vel as Vector3).length() < 0.03:
			node.transform = f2.base
			_flop.erase(j)
		else:
			f2.mine = (f2.base as Transform3D) * Transform3D(Basis((f2.off as Vector3).normalized(), (f2.off as Vector3).length()), Vector3.ZERO)
			node.transform = f2.mine
	if kind != "turret" and _shove.length() > 0.01:
		var p := position + _shove * delta
		position = _clamp_arena(p) if state != DEAD else Vector3(clampf(p.x, bounds.position.x, bounds.end.x), floor_y, clampf(p.z, bounds.position.y, bounds.end.y))
		if is_instance_valid(_wreck_body) and state == DEAD:                # (a wreck that is shoved takes its box along)
			_wreck_body.global_position += Vector3(_shove.x, 0.0, _shove.z) * delta
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
	_root.position = _seat + _knock + _rx_pos + shake - Vector3(0.0, _sink, 0.0)
	var tv := _tilt + _rx_tilt
	var tilt := Basis(tv.normalized(), tv.length()) if tv.length() > 0.0001 else Basis.IDENTITY
	if kind == "drone":
		_root.basis = tilt * Basis(Vector3.RIGHT, _apitch) * _base
	else:
		_root.basis = tilt * _base
		for i in _aims.size():
			var a: Dictionary = _aims[i]
			var r := Basis(a.axis as Vector3, _ayaw if i == 0 else _apitch)
			(a.node as Node3D).transform = Transform3D(r, (a.pivot as Vector3) - r * (a.pivot as Vector3))


# ---------------------------------------------------------------- every frame
## The drone, shot down and still in the air: it flies on in a straight line, facing as it faced (it does not turn),
## gathering speed as it loses height (the Death clip is the fall and the attitude: nose down, banked), shedding
## sparks. It ends on the floor (the clip's moment of impact) or against the first thing in its way.
func _spin_out(delta: float) -> void:
	_wob += delta
	var k := clampf(ap.current_animation_position / 1.02, 0.0, 1.0)      # 0 -> 1 over the fall
	_vel = _vel.normalized() * minf(_vel.length() + 3.2 * delta, 7.0)
	_apitch = move_toward(_apitch, 0.0, 3.0 * delta)
	var p := position + _vel * delta
	var struck := false
	if p.x < bounds.position.x or p.x > bounds.end.x or p.z < bounds.position.y or p.z > bounds.end.y:
		struck = true                                      # a wall
		p = Vector3(clampf(p.x, bounds.position.x, bounds.end.x), 0.0, clampf(p.z, bounds.position.y, bounds.end.y))
	else:
		var from := hit_point()                            # or anything that stands in the room
		var q := PhysicsRayQueryParameters3D.create(from, from + _vel.normalized() * 0.75)
		var skip: Array[RID] = _bodies.duplicate()
		if player != null:
			skip.append(player.get_rid())
		q.exclude = skip
		struck = not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	if not struck:
		position = p
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = randf_range(0.12, 0.3)
		V2Fx.sparks(hit_point(), -_vel.normalized() + Vector3(0, 0.4, 0), 10)
	V2Sfx.drive(_rotor, true, 1.2 + 0.7 * k + 0.12 * sin(_wob * 23.0))      # the rotors scream
	if struck:                                             # into a wall, a tank, a column: it blows up there and drops
		_spin = 0.0
		_blow_up()
		_vel = Vector3.ZERO
		ap.speed_scale = 1.0
	elif ap.current_animation_position >= 1.02:           # into the floor
		_spin = 0.0
		_shove = _vel * 0.3                                # (what is left of it skids on)
		ap.speed_scale = 1.0


func _blow_up() -> void:
	if _exploded:
		return
	_exploded = true
	V2Sfx.drive(_rotor, false)
	V2Fx.explosion(hit_point())
	if player != null:
		var d := player.global_position.distance_to(hit_point())
		if d < BLAST[0]:
			player.hurt(BLAST[1] * (1.0 - d / BLAST[0]), hit_point())


## What is heard of a live robot: the spider's feet coming down (twice per cycle of its gait), a servo when a robot
## swings onto its target or steps round, the drone's rotors rising and falling with its speed.
func _sounds(delta: float) -> void:
	_servo_t -= delta
	if kind == "spider" and clip in ["Walk", "Run", "Turn"] and ap.is_playing():
		var i := int(floor(ap.current_animation_position / (ap.current_animation_length / 2.0)))
		if i != _step_i:
			_step_i = i
			V2Sfx.play("spider_step", global_position, 3.0 if clip == "Run" else 0.0)
	if kind == "drone":
		V2Sfx.drive(_rotor, true, 1.0 + 0.12 * clampf(_shove.length() + (2.0 if state == ENGAGE else 0.0), 0.0, 4.0))
	var turning := clip == "Turn" or (state == AIM and _aim_err < 8.0 and _aim_err > deg_to_rad(6.0))
	if turning and _servo_t <= 0.0:
		_servo_t = 0.7
		V2Sfx.play("servo", hit_point())


func _process(delta: float) -> void:
	if ap.is_playing():
		ap.advance(delta)
	var fired := V2Fx.fired(ap, _events, _ev, _flashes)
	if state == PREVIEW:
		_label.text = "%s  ·  %s" % [kind.to_upper(), clip]
		for node in fired:                             # along the barrel
			var n := node as Node3D
			var from := n.global_position
			var dir := -n.global_basis.z.normalized()
			var to := from + dir * 30.0
			var q := PhysicsRayQueryParameters3D.create(from + dir * 0.3, to)
			q.exclude = _bodies
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
		if dummy:
			_label.visible = false
			_dummy_tick(delta)
			_springs(delta)
		return
	_label.text = kind.to_upper()
	_label.visible = show_label
	_t -= delta
	_cool -= delta
	if state == DEAD:
		# the wreck: what the aim added to the clip's pose goes (the turret's head must hang, not hold its last
		# pitch), and it comes down the last of the way to the floor as the clip's fall ends
		_ayaw = move_toward(_ayaw, 0.0, 4.0 * delta)
		_apitch = move_toward(_apitch, 0.0, 3.0 * delta)
		_tpitch = move_toward(_tpitch, 0.0, 2.5 * delta)
		if _spin > 0.0:
			_spin_out(delta)
		_sink = _gap * smoothstep(0.25, 1.05, ap.current_animation_position) if clip == "Death" else _sink
		if not _crashed and clip == "Death" and ap.current_animation_position >= 1.4:
			_crashed = true                            # the spider's body slams down
			V2Sfx.play("crash", hit_point())
		if not _exploded and clip == "Death" and ap.current_animation_position >= 1.02:
			_blow_up()                                 # the drone hits the floor
		_shorts(delta)
		_springs(delta)
		_wreck_solid()
		if _t <= 0.0 and respawns:
			respawn()
		elif not respawns and _dead_for > 40.0 and _smoke.emitting:
			V2Fx.set_smoke(_smoke, false)                  # (the game: a wreck that stays smokes itself out)
		return
	if player == null:
		return
	_sounds(delta)
	_look(delta)
	if state == SHOOT:
		for node in fired:
			_fire(node as Node3D)
	if kind == "turret":
		_turret(delta)
	else:
		_mobile(delta)
	_springs(delta)
