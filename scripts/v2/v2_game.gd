extends V2World
## The V2 game: the generated dungeon. Every run builds a fresh layout (`DungeonGen`: eight to twelve rooms joined
## by corridors and doors, a tree from the room the player starts in) out of the V2 kit (`V2Dungeon`), scatters
## robots, supply crates and one exit portal (in the deepest room) through it, and the player works toward the exit.
##   1  the title's PLAY generates a dungeon and enters play
##   2  rooms entered count against the total (ROOMS n / N)
##   3  pistol (unlimited magazines) and machine gun (a finite reserve) against the robots; health does not come back
##   4  crates (E) and some wrecks give health, med kits (H) and machine gun rounds
##   5  E opens the doors; Tab shows the map: rooms seen, hostiles in them, doors, the exit once it is found
##   6  into the exit portal = mission complete; health gone = mission failed
##   7  the end screen: score, robots destroyed; AGAIN after a win is a harder dungeon (the threat level climbs
##      with every mission completed: more robots, tougher robots, fewer med kits; a kill is worth more)
## No pause and no prompts (the GDD's rules): Esc frees the mouse and offers the way back to the title. F3: frame rate.
##   godot --path . -- --play [--seed=N] [--threat=N]   straight into a dungeon (a seed gives the same layout again)
##   godot --headless --path . -- --game-test           checks by code, PASS / FAIL
##   godot --headless --path . -- --bot=N [--threat=N]  the balance bot plays N dungeons
##   godot --path . -- --game-capture=DIR               screenshots
const TITLE := "res://scenes/v2_title.tscn"
const KIND := {"turret": "turret", "brawler": "spider", "pursuer": "drone"}      # the generator's hostiles -> the V2 robots
const SCORE := {"turret": 100, "drone": 150, "spider": 200}
# The robots of the dungeon against the lab's. A run meets fifteen or more of them, several at a time, and health
# does not come back: tuned on bot runs (tools/v2_bot.sh; CLAUDE.md has the numbers).
#   [aim lag in seconds (the lab: 0.3), damage x, pauses between bursts /, health (the lab: 150 / 80 / 180)]
const TOUGH := {"spider": [0.14, 1.0, 1.35, 150.0], "drone": [0.2, 1.0, 1.35, 85.0], "turret": [0.2, 1.0, 1.35, 170.0]}
# How many of the robots the generator scatters are kept: a share of each room's, at most two in a room next to
# the start. (Its numbers were for V1's weaker hostiles: 22 a dungeon at threat 0.) The generator always runs at
# threat 0 and the game scales with the threat level (MORE, HP_PER_THREAT, _kit_weight), so that a seed's
# dungeon is the same at every level but for that.  [share kept, the most in one room]
const CROWD := [0.75, 4]
const MORE := 1.0                   # robots added to the dungeon per mission completed
const HP_PER_THREAT := 0.06         # robots' health: + this per mission completed
const SCORE_PER_THREAT := 0.25      # a kill's worth: + this per mission completed
const HEAR := 24.0                  # a robot this near hears the player's gun and comes
const GATHER := 9                   # a robot comes to look at the player who is down from at most this many cells away
const RING := [0.0, 50.0, -50.0, 100.0, -100.0, 150.0, -150.0]      # where they stand round the player (degrees from where the player faces)
const DEATH_WAIT := [3.4, 9.0]      # seconds from going down to the options: at the earliest, at the latest
const DROP := 0.35                  # chance that a destroyed robot leaves something
const REACH := 2.4                  # how near a door or a crate must be for E
const CHASE := 18                   # a robot follows the player at most this many cells

enum { PLAYING, WON, LOST }

static var missions := 0            # missions completed in this sitting: the threat level
static var total_score := 0
var start_at := Vector3.ZERO         # where the player appears, and facing where (the training: in front of the dummy)
var start_yaw := 0.0
static var trained := false         # the training of the first room was done in this sitting (it is not repeated)

var gen: DungeonGen
var dungeon: V2Dungeon
var player: V2Player
var robots: Array[V2Robot] = []
var state := PLAYING
var kills := 0
var score := 0
var elapsed := 0.0
var here := -1                      # the area (room or corridor) the player is in
var explored: Dictionary = {}       # room id -> true
var order: Dictionary = {}          # room id -> 1, 2, 3 ... as they were entered
var walked: Dictionary = {}         # corridor id -> true
var exit_found := false
var crates: Array = []              # {node, lid, light, what, open}
var pickups: Array = []             # {node, what, t, y}
var seed_used := 0
var _props: Node3D
var _exit_xf := Transform3D.IDENTITY   # the gate's frame (world): the player is through it when inside its opening
var _ui: CanvasLayer                 # the HUD's layer (4): over the 3D view, the gun (1) and the hit effects (2)
var _fx: CanvasLayer
var hud: V2Hud
var ending := false                  # an end screen is up
# The training of the first room (the user's five points): a dummy spider on a striped pad; aim with the pistol
# and hit it; take the rifle, aim and hit it; take the health kit out of the crate; E opens a door, and the run
# starts. Until then the room's doors are locked and the robots beyond hear nothing.
const TRAIN_HITS := [3, 6]           # hits wanted with the pistol, with the rifle (each one aimed)
var training := false
var train_step := 0                  # 0 pistol, 1 rifle, 2 the kit, 3 the door
var train_hits := 0
var dummy: V2Robot
var _train_kits := 0
var _perf: Label
var _perf_log := false             # -- --perf-log: F3's lines are printed every second (the browser's console)
var _perf_t := 0.0
var _perf_n := 0
var _menu: Control
var _top: CanvasLayer
var _end: Control
var _map: V2Map
var _tick := 0.0
var _bot: Node
var _death_t := 0.0
var _rounds_heard := 0
var _seen_t := 0.0
var _watchers: Array = []
var _rng := RandomNumberGenerator.new()
var _loot_rng := RandomNumberGenerator.new()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	V2Fx.root = self
	V2Fx.reset()
	V2Sfx.root = self
	V2Sfx.enabled = not ("--no-sound" in args)
	V2Music.stop(1.0)                                      # (the menu's music does not follow into play)
	_low = "--quality=low" in args
	if _low:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	_render_setup()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# (the one shadow falls straight down from a soft light: five samples a pixel look the same as thirteen here)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	var capture := ""
	var part := ""
	var bot := 0
	seed_used = int(Time.get_ticks_usec()) ^ (randi() << 8)
	if "--game-test" in args:
		seed_used = 7                                      # (the checks want the same dungeon every time)
	for a in args:
		if a.begins_with("--seed="):
			seed_used = int(a.trim_prefix("--seed=")) + missions * 7919      # (the next mission of a seeded run is seeded too)
		if a.begins_with("--threat=") and total_score == 0 and missions == 0:
			missions = int(a.trim_prefix("--threat="))
		if a.begins_with("--game-capture="):
			capture = a.trim_prefix("--game-capture=")
		if a.begins_with("--part="):                       # with --game-capture: flicker / death / marks (v2_game_bot.gd)
			part = a.trim_prefix("--part=")
		if a.begins_with("--bot"):
			bot = maxi(int(a.trim_prefix("--bot=")), 1) if a.contains("=") else 1
	# the training: the first run of a sitting, never for the bot, the checks or the pictures
	# (-- --no-training skips it, -- --training forces it, -- --training-test checks it)
	var automated := "--game-test" in args or bot > 0 or capture != ""
	training = ("--training" in args or "--training-test" in args) or (not trained and missions == 0 and not automated and not ("--no-training" in args))
	V2Robot.no_go = []
	_rng.seed = hash(seed_used) + 5
	_loot_rng.seed = hash(seed_used) + 11
	_environment(0.38, 0.25, 22.0)
	gen = DungeonGen.new().generate(seed_used, 0)           # (the threat level is applied here, not by the generator: see below)
	dungeon = V2Dungeon.new()
	add_child(dungeon)
	# (nothing is stood where the player appears: the middle of a room with an even number of cells is a cell corner)
	dungeon.keep_clear.append([gen.player_spawn, 2.3, false])
	var dummy_at := Vector3.ZERO
	start_at = gen.player_spawn
	start_yaw = gen.player_yaw
	if training:
		dummy_at = _training_spot()
		# (**user: "make the character be loaded in front of the enemy in the training room"**)
		start_at = _training_start(dummy_at)
		start_yaw = atan2(-(dummy_at.x - start_at.x), -(dummy_at.z - start_at.z))
		dungeon.keep_clear.append([start_at, 2.3, false])
		dungeon.locked_room = gen.spawn_room
		dungeon.keep_clear.append([dummy_at, 3.0, true])
		for l in gen.loot_spawns:                          # (the room's crate holds the health kit of the fourth step)
			if int(l.room) == gen.spawn_room:
				l.payoff = "kit"
	dungeon.build(gen)
	V2Fx.layer_at = func(p: Vector3) -> int:               # (bullet marks, the dropped gun: lit by the room they are in)
		var a := dungeon.area_at(p)
		return int(dungeon.areas[a].layer) if a >= 0 else 0xFFFFF
	_props = (load(V2Assets.DIR + "set.glb") as PackedScene).instantiate()      # (the environment set: crates, pickups, the exit)
	V2Assets.apply(_props)
	for l in gen.loot_spawns:
		_crate(l)
		# med kits thin out with the threat level (the first number is drawn at every level, so that the robots,
		# drawn next from the same stream, are the same at every level of a seed, plus the level's extra ones)
		if l.payoff == "kit" and _rng.randf() > _kit_weight() / (_kit_weight() + 7.0) * 11.0 / 4.0 and not (training and int(l.room) == gen.spawn_room):
			crates[-1].what = "ammo" if _loot_rng.randf() < 0.57 else "health"
	_exit()
	var per_room: Dictionary = {}                          # the generator's robots, room by room: a share of each room's is kept
	for e in gen.enemy_spawns:
		if not per_room.has(e.room):
			per_room[e.room] = []
		per_room[e.room].append(e)
	var keep: Dictionary = {}
	for room_id in per_room:
		var n: int = per_room[room_id].size()
		keep[room_id] = clampi(int(floor(n * CROWD[0] + _rng.randf())), 1, mini(n, 2 if gen.rooms[room_id].depth <= 1 else CROWD[1]))
	# the threat level: MORE robots in the dungeon per level, first in the rooms away from the start (the biggest
	# first, a room's limit rising as they fill), then anywhere, until the generator's places are used up
	# (the generator's own scaling, +0.5 a room per level, is not used: its extra robots also reshuffle the loot)
	var by_size: Array = per_room.keys()
	by_size.sort_custom(func(a2: int, b2: int) -> bool: return gen.rooms[a2].rect.get_area() > gen.rooms[b2].rect.get_area())
	var extra := int(round(MORE * missions))
	for turn in 6:
		for room_id in by_size:
			var most: int = CROWD[1] + turn if gen.rooms[room_id].depth >= 2 else turn
			if extra > 0 and keep[room_id] < mini(per_room[room_id].size(), most):
				keep[room_id] += 1
				extra -= 1
	for room_id in per_room:
		for k in keep[room_id]:
			_robot(per_room[room_id][k])
	for r in robots:                                       # the robots of a room keep off each other's firing positions
		r.others = robots.filter(func(o: V2Robot) -> bool: return o.room == r.room)
	player = V2Player.new()
	player.rules = true
	player.grab = false                                    # (a click does not take the mouse back: the menu's buttons must work)
	add_child(player)
	player.global_position = start_at + Vector3(0, 0.02, 0)
	player._yaw = start_yaw
	player._pitch = deg_to_rad(-3.0)
	player.died.connect(func() -> void: finish(false))
	player.interact.connect(interact)
	for r in robots:
		r.player = player
	if training:
		_training_build(dummy_at)
	_hud()
	V2Sfx.ambience("room_tone")
	if automated or "--training-test" in args:
		_bot = (load("res://scripts/v2/v2_game_bot.gd") as GDScript).new()
		_bot.game = self
		add_child(_bot)
		if "--training-test" in args:
			_bot.training_test()
		elif capture != "" and part != "":
			_bot.call(part, capture)
		elif capture != "":
			_bot.capture(capture)
		elif bot > 0:
			_bot.play_runs(bot)
		else:
			_bot.test()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_opening(training)
		for a in args:                                     # (pictures of the opening: -- --title --open-capture=DIR)
			if a.begins_with("--open-capture="):
				V2World.film(self, a.trim_prefix("--open-capture="), "game", 16.0)


## How a run opens (**user: "a fade in into the environment, then the gun appears with the inspecting motion, then
## the character is playable"**, and later **"the letters all fade into white, and the same white fades out into
## the game, more slowly"**: the title has faded into its own white, `V2World.open_from`): the veil lifts off the room, the gun
## comes up into view (Draw) and is turned over once (Inspect), and only then do the keys and the mouse answer and
## the HUD comes in. Later runs of a sitting open the same way without the turning over. Not for the bot, the
## checks or the pictures.
func _opening(full: bool) -> void:
	var top := CanvasLayer.new()
	top.layer = 8
	add_child(top)
	var from_title := V2World.open_from != UIPalette.COMPLETE_BG
	var veil: ColorRect = V2World.veil if is_instance_valid(V2World.veil) else V2Ui.full(top, V2World.open_from)
	veil.color.a = 1.0
	V2World.open_from = UIPalette.COMPLETE_BG
	player.locked = true
	player.overlay.visible = false
	hud.modulate.a = 0.0
	await get_tree().create_timer(0.5).timeout
	var tw := create_tween()
	# (out of the title's white: slowly, the room comes out of the light; out of an end screen's grey: quicker)
	tw.tween_property(veil, "color:a", 0.0, 3.0 if from_title else 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	top.queue_free()
	if is_instance_valid(V2World.veil):
		V2World.veil.get_parent().queue_free()
		V2World.veil = null
	player.overlay.visible = true
	for clip in (["Draw", "Inspect"] if full else ["Draw"]):
		player.act(clip)
		while player.busy != "" and state == PLAYING:
			await get_tree().process_frame
	player.locked = false
	create_tween().tween_property(hud, "modulate:a", 1.0, 0.45)


# ---------------------------------------------------------------------------------------------- what the dungeon holds
func _prop(prop_name: String) -> Node3D:
	var n := (_props.find_child(prop_name, true, false) as Node3D).duplicate() as Node3D
	n.position = Vector3.ZERO
	return n


func _robot(e: Dictionary) -> void:
	var kind: String = KIND[e.type]
	var area := dungeon.area_at(e.pos)
	var robot := V2Robot.new()
	add_child(robot)
	robot.setup(kind)
	robot.respawns = false
	robot.show_label = false
	robot.aim_lag = TOUGH[kind][0]
	robot.damage_scale = TOUGH[kind][1]
	robot.haste = TOUGH[kind][2]
	robot.max_hp = TOUGH[kind][3] * (1.0 + HP_PER_THREAT * missions)
	robot.hp = robot.max_hp
	robot.room = area
	robot.bounds = dungeon.arena(area, 0.7)
	# (on the middle of a cell: spider and drone go between the middles of cells, and the turret's arm swings
	# clear of what stands at the cells' corners, columns and tanks)
	var floor_rect := dungeon.arena(area, 1.9)
	var at: Vector3 = V2Dungeon.center(V2Dungeon.cell_of(e.pos))
	var mid: Vector2 = (dungeon.areas[area].rect as Rect2).get_center()
	robot.place(at, rad_to_deg(atan2(-(mid.x - at.x), -(mid.y - at.z))) + _rng.randf_range(-40.0, 40.0))
	if kind == "turret":                                   # it hangs from a carriage on a short rail under the ceiling
		robot.set_rail(maxf(at.z - 2.4, floor_rect.position.y), minf(at.z + 2.4, floor_rect.end.y), dungeon.areas[area].layer)
	else:
		robot.arena = floor_rect
		robot.grid = V2Dungeon.CELL
		if kind == "spider":
			robot._spec.keep = [3.8, 6.0]                  # it closes in more than the lab's (5 to 7.5 m): its rounds scatter with its guns' recoil
	_set_layer(robot, dungeon.areas[area].layer)
	robot.destroyed.connect(_on_destroyed)
	robot.arrived.connect(_settle)
	robots.append(robot)


## A robot at the end of its way (or stopped on it): the area it stands in is its floor now.
func _settle(robot: V2Robot) -> void:
	var area := dungeon.area_at(robot.global_position)
	if area < 0:
		return
	robot.room = area
	robot.arena = dungeon.arena(area, 1.9)
	robot.bounds = dungeon.arena(area, 0.7)
	_set_layer(robot, dungeon.areas[area].layer)


func _solid(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = at
	parent.add_child(body)


## A supply crate against a wall (the generator's place and what is in it), its front to the room.
func _crate(l: Dictionary) -> void:
	var out := Vector3(sin(float(l.yaw)), 0, cos(float(l.yaw)))          # toward the wall
	# (the paint says what is in it: olive = ammunition, white = a health pack, green = a med kit)
	var node := _prop({"ammo": "loot_crate_olive", "health": "loot_crate", "kit": "loot_crate_green"}[String(l.payoff)])
	add_child(node)
	node.position = (l.pos as Vector3) + out * 0.5
	node.rotation.y = float(l.yaw) + PI
	_solid(node, Vector3(1.0, 0.59, 0.62), Vector3(0, 0.3, 0))
	_set_layer(node, dungeon.areas[dungeon.area_at(l.pos)].layer)
	var lid := node.find_child("Crate_Lid*", true, false)       # (the three crates' lids: Crate_Lid, Crate_Lid_001, ...)
	crates.append({"node": node, "lid": lid, "light": lid.find_child("*ECyan*", true, false), "what": String(l.payoff), "open": false})


## The exit portal: the gate in the middle of the deepest room, its front toward that room's doorway.
func _exit() -> void:
	var room: DungeonGen.Room = gen.rooms[gen.exit_room]
	var to := (DungeonGen.cell_center(room.doorway_cells[0]) - gen.exit_pos) if not room.doorway_cells.is_empty() else Vector3(0, 0, 1)
	var yaw := (PI / 2.0 if to.x > 0.0 else -PI / 2.0) if absf(to.x) > absf(to.z) else (0.0 if to.z > 0.0 else PI)
	var gate := _prop("exit_portal")
	add_child(gate)
	gate.position = gen.exit_pos
	gate.rotation.y = yaw
	for sx in [-1.0, 1.0]:                                  # (the arch's legs and head stop the player; the leaves by the field do not)
		_solid(gate, Vector3(0.5, 3.0, 0.7), Vector3(sx * 1.2, 1.5, 0))
	_solid(gate, Vector3(2.9, 0.6, 0.7), Vector3(0, 3.05, 0))
	var layer: int = dungeon.areas[dungeon.area_at(gen.exit_pos)].layer
	for side in [-1.0, 1.0]:
		var sign := Label3D.new()                          # (not in the heading font: that one has no X)
		sign.text = "EXIT"
		sign.font_size = 96
		sign.pixel_size = 0.0022
		sign.modulate = Color(0.1, 0.04, 0.22)
		sign.outline_size = 0
		sign.position = Vector3(0, 3.23, side * 0.34)
		sign.rotation_degrees.y = 0.0 if side > 0.0 else 180.0
		gate.add_child(sign)
		var spot := SpotLight3D.new()                      # the field lights the floor on both sides
		spot.light_color = Color(0.35, 0.9, 1.0)           # (the field's colour)
		spot.light_energy = 2.0
		spot.spot_range = 5.0
		spot.spot_angle = 70.0
		spot.position = Vector3(0, 2.2, side * 0.3)
		spot.rotation_degrees = Vector3(-60.0, 0.0 if side < 0.0 else 180.0, 0)
		spot.light_cull_mask = layer
		gate.add_child(spot)
	_set_layer(gate, layer)
	_exit_xf = gate.global_transform
	V2Sfx.drive(V2Sfx.loop("exit_hum", gate), true)


# ---------------------------------------------------------------------------------------------- the training
## Where the dummy stands in its cage: **the middle of the first room** (user: "in the center of the training
## room, not in the corner"). (It was a cell near a wall. In a room with an even number of cells the middle is a
## cell corner; `keep_clear` keeps cover off it.)
func _training_spot() -> Vector3:
	return (gen.rooms[gen.spawn_room] as DungeonGen.Room).center()


## Where the player appears in the training room: in front of the cage's door, 6 m from the dummy (less in a
## small room: 1.3 m short of the wall), along a row or a column of the room. Of the four ways, the one with the
## player's back to where the generator would have had them look from (the way out lies beyond the cage), unless
## the room is too short that way. `keep_clear` round that spot and round the dummy opens the line between them.
func _training_start(at: Vector3) -> Vector3:
	var room: DungeonGen.Room = gen.rooms[gen.spawn_room]
	var lo := Vector2(room.rect.position) * V2Dungeon.CELL
	var hi := Vector2(room.rect.end) * V2Dungeon.CELL
	var back := Vector3(sin(gen.player_yaw), 0, cos(gen.player_yaw))
	var best := gen.player_spawn
	var best_score := -1e9
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var reach := (hi.x - at.x if d.x > 0 else (at.x - lo.x if d.x < 0 else (hi.y - at.z if d.y > 0 else at.z - lo.y))) - 1.3
		if reach < 4.0:
			continue
		var dir := Vector3(d.x, 0, d.y)
		var score := minf(6.0, reach) + dir.dot(back) * 2.0
		if score > best_score:
			best_score = score
			best = at + dir * minf(6.0, reach)
	return best


## The dummy and its pad: a low dark plinth with two of the set's striped floor tiles on it, the spider on top,
## facing where the player appears. It is no enemy: not among `robots`, it only takes hits.
func _training_build(at: Vector3) -> void:
	var layer: int = dungeon.areas[dungeon.area_of[gen.rooms[gen.spawn_room].rect.position]].layer
	var pad := Node3D.new()
	add_child(pad)
	var to := start_at - at
	pad.position = at
	pad.rotation.y = atan2(to.x, to.z)
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.16, 0.24, 2.16)
	base.mesh = box
	base.position.y = 0.12
	base.material_override = V2Assets.material("EDarkSteel")
	pad.add_child(base)
	for x in [-0.5, 0.5]:
		var tile := _prop("floor_hazard")
		pad.add_child(tile)
		tile.position = Vector3(x, 0.24, 0)
	# the cage round it (**user: "let's give the impression that the dummy robot is 'caged'"**, after their
	# reference; `training_cage` of the set, its door toward the player): its posts stop everything, its bars
	# stop the player and let rounds and looks through (`V2World.CAGE`)
	var cage := _prop("training_cage")
	pad.add_child(cage)
	_set_layer(pad, layer)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.16, 0.31, 2.16)
	shape.shape = bs
	shape.position.y = 0.155
	body.add_child(shape)
	pad.add_child(body)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := CollisionShape3D.new()
			var pb := BoxShape3D.new()
			pb.size = Vector3(0.24, 2.5, 0.24)
			post.shape = pb
			post.position = Vector3(sx * 1.4, 1.25, sz * 1.4)
			body.add_child(post)
	var bars := StaticBody3D.new()
	bars.collision_layer = V2World.CAGE
	bars.collision_mask = 0
	for k in 4:
		var side := CollisionShape3D.new()
		var sb := BoxShape3D.new()
		sb.size = Vector3(2.6, 2.5, 0.16) if k < 2 else Vector3(0.16, 2.5, 2.6)
		side.shape = sb
		side.position = Vector3(0, 1.25, -1.45 if k == 0 else 1.45) if k < 2 else Vector3(-1.45 if k == 2 else 1.45, 1.25, 0)
		bars.add_child(side)
	pad.add_child(bars)
	player.collision_mask |= V2World.CAGE
	# robots go round it (**user: "make the robots avoid the cage"**): spiders and drones steer round the square
	# (`V2Robot.no_go`: the cage and 0.85 m for the robot), and no path leads through a cell it stands in the middle of
	V2Robot.no_go.append([Vector3(at.x, 0.0, at.z), 1.61 + 0.85])
	var cell := V2Dungeon.cell_of(at)
	if V2Dungeon.center(cell).distance_to(Vector3(at.x, 0.0, at.z)) < 1.0:
		dungeon.blocked[cell] = true
	dummy = V2Robot.new()
	add_child(dummy)
	dummy.setup("spider")
	dummy.dummy = true
	dummy.respawns = false
	dummy.show_label = false
	dummy.player = player
	dummy.place(at, rad_to_deg(atan2(-to.x, -to.z)))
	dummy.set_ai(false)
	dummy.auto = false
	dummy.play("Idle")
	dummy._home.y = 0.31
	dummy.position.y = 0.31
	dummy.floor_y = 0.31
	dummy.bounds = dungeon.arena(dungeon.area_of[gen.rooms[gen.spawn_room].rect.position], 0.7)
	_set_layer(dummy, layer)
	dummy.struck.connect(_on_dummy_struck)
	_train_kits = player.kits


func _aimed() -> bool:
	return player._aimed > 0.6 or player.busy == "ADSFire"


func _on_dummy_struck() -> void:
	if not training or train_step > 1:
		return
	var want := "pistol" if train_step == 0 else "rifle"
	if player.weapon != want:
		if train_step == 0:
			say("The pistol first · press 1", "weapon_pistol", true)
		return
	if not _aimed():
		say("Aim first · hold C or right mouse", "", true)
		return
	train_hits += 1
	if train_hits >= TRAIN_HITS[train_step]:
		if train_step == 1:                                # every shot asked for has been fired at it: it is destroyed
			dummy.finish_off(player.last_aim)
		_training_next()


func _training_next() -> void:
	train_step += 1
	train_hits = 0
	V2Sfx.play("ui")
	hud.train_done()
	if train_step == 3:
		dungeon.unlock()


func _training_tick() -> void:
	if train_step == 2 and player.kits > _train_kits:
		_training_next()
	elif train_step == 3:
		for d in dungeon.doors:
			if d.door and d.open and gen.room_at(d.a) == gen.spawn_room:
				_training_end()
				return


## The door is open: the run starts. What was fired at the dummy is given back.
func _training_end() -> void:
	training = false
	trained = true
	player.mag.rifle = V2Player.MAG.rifle
	player.reserve = maxi(player.reserve, 60)
	elapsed = 0.0
	hud.train_done()


# ---------------------------------------------------------------------------------------------- what the player does
## E: the shut door or the crate within reach that the player is nearest to.
func interact() -> void:
	if state != PLAYING:
		return
	var at := player.global_position
	var door := dungeon.door_near(at, REACH)
	var best := REACH
	if door >= 0:
		var d: Vector3 = dungeon.doors[door].at
		best = Vector2(at.x - d.x, at.z - d.z).length()
	var crate: Dictionary = {}
	for c in crates:
		var dist := at.distance_to((c.node as Node3D).global_position)
		if not c.open and dist < best:
			best = dist
			crate = c
	if not crate.is_empty():
		open_crate(crate)
	elif door >= 0 and dungeon.doors[door].locked:
		say("Locked · finish the training", "door", true)
	elif door >= 0:
		open_door(door)


func open_door(i: int) -> void:
	if dungeon.doors[i].open:
		return
	dungeon.open_door(i)
	var at: Vector3 = dungeon.doors[i].at
	for r in robots:                                       # the robots near it hear it open
		if r.state != V2Robot.DEAD and r.global_position.distance_to(at) < 16.0:
			r.alerted = true


func open_crate(c: Dictionary) -> void:
	if c.open:
		return
	c.open = true
	var node := c.node as Node3D
	V2Sfx.play("crate", node.global_position + Vector3(0, 0.4, 0))
	var tw := create_tween()
	tw.tween_property(c.lid as Node3D, "rotation_degrees:x", -105.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if c.light != null:
		(c.light as MeshInstance3D).set_surface_override_material(0, V2Assets.material("EDarkSteel"))      # (its lamp goes out)
	drop(String(c.what), node.global_position + Vector3(0, 0.62, 0), 0.5)      # what is in it rises out of it


## A pickup at `at` (world), which the player takes by walking to it, after `delay` seconds.
func drop(what: String, at: Vector3, delay: float = 0.0) -> void:
	var node := _prop({"ammo": "ammo_box", "health": "medkit_white", "kit": "medkit"}[what])
	add_child(node)
	node.global_position = at
	if what == "ammo":
		node.scale = Vector3.ONE * 1.7                     # (a box of rounds is 20 cm long: bigger, to be seen on the floor)
	var area := dungeon.area_at(at)
	if area >= 0:
		_set_layer(node, dungeon.areas[area].layer)
	pickups.append({"node": node, "what": what, "t": -delay, "y": at.y})


func _take(p: Dictionary) -> bool:
	var ok := false
	var note := ""
	var icon := ""
	match String(p.what):
		"ammo":
			ok = player.add_ammo(60)
			note = "+60 rifle ammo"
			icon = "ammo_rifle"
		"health":
			ok = player.add_health(35.0)
			note = "+35 health"
			icon = "health_cross"
		"kit":
			ok = player.add_kit()
			note = "Health kit stored · H uses it" if training else "Health kit stored"
			icon = "health_kit"
	if ok:
		V2Sfx.play("pickup")
		say(note, icon)
	return ok


func say(text: String, icon_name: String = "", warn: bool = false) -> void:
	if hud != null:
		hud.say(text, icon_name, warn)


## What E would open from where the player stands: "door", "crate" or "" (the HUD's prompt).
func in_reach() -> String:
	var at := player.global_position
	var door := dungeon.door_near(at, REACH)
	var best := REACH
	var what := ""
	if door >= 0 and not dungeon.doors[door].locked:
		var d: Vector3 = dungeon.doors[door].at
		best = Vector2(at.x - d.x, at.z - d.z).length()
		what = "door"
	for c in crates:
		if not c.open and at.distance_to((c.node as Node3D).global_position) < best:
			best = at.distance_to((c.node as Node3D).global_position)
			what = "crate"
	return what


func map_open() -> bool:
	return _map != null and _map.visible


## What a wreck leaves: med kits thin out as the threat level climbs (weight 4 falling to 1).
func roll_payoff() -> String:
	var pick := _rng.randf() * (_kit_weight() + 7.0)
	return "kit" if pick < _kit_weight() else ("ammo" if pick < _kit_weight() + 4.0 else "health")


## The med kit's weight among what crates and wrecks give (ammunition 4, health 3): 4 at threat 0, down to 1 at 4.
func _kit_weight() -> float:
	return maxf(1.0, 4.0 - 0.75 * missions)


func _on_destroyed(robot: V2Robot) -> void:
	kills += 1
	score += int(round(SCORE[robot.kind] * (1.0 + SCORE_PER_THREAT * missions)))
	if _rng.randf() < DROP:
		# (beside the wreck, on the player's side of it: the wreck is solid, and what lay under it could not be reached)
		var at := robot.global_position
		var to := player.global_position - at
		to.y = 0.0
		at += (to.normalized() if to.length() > 0.1 else Vector3.FORWARD).rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6)) * minf(1.6, maxf(to.length() - 0.6, 0.0))
		var b := robot.bounds
		drop(roll_payoff(), Vector3(clampf(at.x, b.position.x, b.end.x), 0.05, clampf(at.z, b.position.y, b.end.y)), 2.5 if robot.kind == "drone" else 1.0)


func finish(won: bool) -> void:
	if state != PLAYING:
		return
	state = WON if won else LOST
	if won:
		V2Sfx.play("exit")
		player.invulnerable = true
		missions += 1
	total_score += score
	player.mouse_look = false
	_map.visible = false
	if won:
		_show_end()
	else:
		_death_t = 0.0                                     # the player falls; the robots come to look; then the options
		_gather()


func _show_end() -> void:
	_end_screen()
	if _bot == null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The player is down: the robots that can get there come and stand round them, looking (they do not fire any
## more); the turrets turn their heads. Places in a ring round the player, in front of their eyes first.
func _gather() -> void:
	var at := player.global_position
	var head := at + Vector3(0, V2Player.LIE, 0)
	var my_cell := V2Dungeon.cell_of(at)
	var fwd := -player.global_basis.z
	var alive: Array = robots.filter(func(r: V2Robot) -> bool: return r.state != V2Robot.DEAD)
	alive.sort_custom(func(a2: V2Robot, b2: V2Robot) -> bool: return a2.global_position.distance_to(at) < b2.global_position.distance_to(at))
	var k := 0
	for r: V2Robot in alive:
		if r.kind == "turret":
			if r.global_position.distance_to(at) < 30.0:
				r.watch(head, r.position)
			continue
		var cells := dungeon.path(V2Dungeon.cell_of(r.global_position), my_cell)
		if cells.is_empty() or cells.size() > GATHER:
			continue
		var spot := Vector3.INF
		while k < RING.size() and spot == Vector3.INF:
			var p := at + fwd.rotated(Vector3.UP, deg_to_rad(RING[k])) * (2.0 if r.kind == "spider" else 1.5)
			k += 1
			var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.5, 0), p + Vector3(0, 0.5, 0))
			q.exclude = [player.get_rid()]
			var res := get_world_3d().direct_space_state.intersect_ray(q)
			if res.is_empty() or res.collider.has_meta("robot"):
				spot = p
		if spot == Vector3.INF:
			continue
		var way: Array = []                                # cell middle to cell middle, up to the cell next to the player's
		for i in range(1, cells.size() - 1):
			way.append([V2Dungeon.center(cells[i]), dungeon.low_cell(cells[i])])
		r.active = true
		r.set_process(true)
		r.watch(head, spot, way)
		_watchers.append(r)


## After going down: the robots on their way are kept lit by the areas they cross; the options appear once the
## first of them has stood over the player for a moment (or after a while, if none comes).
func _death(delta: float) -> void:
	_death_t += delta
	if _end != null:
		return
	var there := false
	for r: V2Robot in _watchers:
		var area := dungeon.area_at(r.global_position)
		if area >= 0 and area != r.room:
			r.room = area
			_set_layer(r, dungeon.areas[area].layer)
		if r.state == V2Robot.WATCH and Vector2(r.position.x - r._watch_spot.x, r.position.z - r._watch_spot.z).length() < 0.6:
			there = true
	_seen_t = _seen_t + delta if there else 0.0
	var quick := _bot != null and DisplayServer.get_name() == "headless"
	if quick or _death_t > DEATH_WAIT[1] or (_death_t > DEATH_WAIT[0] and (_seen_t > 1.6 or _watchers.is_empty())):
		_show_end()


func alive_in(area: int) -> int:
	var n := 0
	for r in robots:
		if r.state != V2Robot.DEAD and r.room == area:
			n += 1
	return n


# ---------------------------------------------------------------------------------------------- every frame
func _process(delta: float) -> void:
	if player == null:
		return
	var at := player.global_position
	var area := dungeon.area_at(at)
	if area >= 0 and area != here:
		here = area
		var a: Dictionary = dungeon.areas[area]
		if a.room:
			if not explored.has(a.id):                     # a room entered for the first time counts
				explored[a.id] = true
				order[a.id] = explored.size()              # (the map numbers the rooms as they were found)
			if int(a.id) == gen.exit_room:
				exit_found = true
		else:
			walked[a.id] = true
	var t := Time.get_ticks_usec()
	dungeon.update(at, V2Player.GUN_LAYER)
	V2World.took("dungeon", t)
	t = Time.get_ticks_usec()
	if training and state == PLAYING:
		_training_tick()
	if state == PLAYING:
		if not training:
			elapsed += delta
		var local := _exit_xf.affine_inverse() * at
		if absf(local.x) < 0.8 and absf(local.z) < 0.45:
			finish(true)
		_tick -= delta
		if _tick <= 0.0:
			_tick = 0.4
			_robots_tick()
	if state == LOST:
		_death(delta)
	_pickups(delta)
	V2World.took("game", t)
	t = Time.get_ticks_usec()
	_hud_update(delta)
	V2World.took("hud", t)


## Twice a second: which robots are awake and drawn, and which go after the player.
func _robots_tick() -> void:
	var at := player.global_position
	var my_cell := V2Dungeon.cell_of(at)
	var gunfire := player._rounds != _rounds_heard and not training      # the player has fired since the last tick (practice is not heard)
	_rounds_heard = player._rounds
	if dummy != null:                                      # (drawn with its room)
		dummy.visible = (dungeon.areas[dungeon.area_of[gen.rooms[gen.spawn_room].rect.position]].node as Node3D).visible
	for r in robots:
		var d := r.global_position.distance_to(at)
		if gunfire and d < HEAR and r.state != V2Robot.DEAD:
			r.alerted = true
		var area := dungeon.area_at(r.global_position)
		r.active = d < 34.0
		r.visible = area < 0 or (dungeon.areas[area].node as Node3D).visible
		r.set_process(d < 48.0 or r.state == V2Robot.TRAVEL or r.state == V2Robot.DEAD)
		if r.state == V2Robot.DEAD or r.kind == "turret":
			continue
		if r.state == V2Robot.TRAVEL:
			if area >= 0 and area != r.room:               # (on its way through another area: lit by that one)
				r.room = area
				_set_layer(r, dungeon.areas[area].layer)
			continue
		# it has seen the player (or heard a door) and they are somewhere else now: after them, through open doorways
		if r.state == V2Robot.ROAM and r.alerted and r._unseen > 1.2 and here >= 0 and area != here:
			var cells := dungeon.path(V2Dungeon.cell_of(r.global_position), my_cell)
			if cells.size() >= 2 and cells.size() <= CHASE:
				var way: Array = []
				for k in range(1, cells.size()):
					way.append([V2Dungeon.center(cells[k]), dungeon.low_cell(cells[k])])
				r.follow(way)


func _pickups(delta: float) -> void:
	for p in pickups.duplicate():
		var node := p.node as Node3D
		p.t += delta
		if p.t < 0.0:
			node.visible = false
			continue
		node.visible = true
		node.rotation.y += delta * 1.4
		node.position.y = float(p.y) + 0.08 + 0.05 * sin(float(p.t) * 3.0)
		var flat := Vector2(player.global_position.x - node.global_position.x, player.global_position.z - node.global_position.z)
		if state == PLAYING and flat.length() < 1.3 and float(p.t) > 0.25 and _take(p):
			pickups.erase(p)
			node.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_perf.visible = not _perf.visible
			_perf.text = "measuring ..."
			_perf_t = 0.0
			_perf_n = 0
		elif event.keycode == KEY_F4:                      # the 3D picture's size: 1080 / 900 / 720 rows / the window's
			_render_next()
			_perf.visible = true
			_perf.text = _render_text() + " ..."
			_perf_t = 0.0
			_perf_n = 0
		elif event.keycode == KEY_TAB and state == PLAYING:
			_map.visible = not _map.visible                # (the game goes on behind it)


# ---------------------------------------------------------------------------------------------- HUD and screens
## The screens of the UI concept (v2/reference/ui/README.md), on their layers: the gun is drawn on layer 1
## (V2Player), then the hit's blur and glow (2), the HUD (4), the map (5), the end screens and the Esc menu (6).
func _hud() -> void:
	_fx = CanvasLayer.new()
	_fx.layer = 2
	add_child(_fx)
	_ui = CanvasLayer.new()
	_ui.layer = 4
	add_child(_ui)
	hud = V2Hud.new()
	_ui.add_child(hud)
	hud.setup(self, _fx)
	_perf = hud.perf
	_perf_log = "--perf-log" in OS.get_cmdline_user_args()
	_perf.visible = _perf_log
	var map_layer := CanvasLayer.new()
	map_layer.layer = 5
	add_child(map_layer)
	_map = V2Map.new()
	_map.game = self
	_map.visible = false
	map_layer.add_child(_map)
	_top = CanvasLayer.new()
	_top.layer = 6
	add_child(_top)
	# Esc: the mouse is free; the way back (the run keeps going: there is no pause)
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.visible = false
	_top.add_child(_menu)
	V2Ui.full(_menu, Color(0, 0, 0, 0.45))
	var card := V2Ui.panel(_menu, UIPalette.hud_panel(true), [28, 22, 28, 26])
	V2Ui.at(card, 0.5, 0.5, 0.0, 0.0)
	var col := V2Ui.column(card, 16)
	V2Ui.text(col, "THE RUN KEEPS GOING", "bold", 12, UIPalette.LABEL, 0.24)
	var buttons := V2Ui.row(col, 12)
	V2Ui.button(buttons, "RESUME", func() -> void: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED, UIPalette.CYAN, "chevron_right")
	V2Ui.button(buttons, "STOP HERE", to_title)


func to_title() -> void:
	missions = 0
	total_score = 0
	get_tree().change_scene_to_file(TITLE)


func again() -> void:
	V2World.cover(get_tree(), UIPalette.COMPLETE_BG, 0.0)  # (no frame of the engine's clear colour between the two runs)
	get_tree().reload_current_scene()


func _hud_update(delta: float) -> void:
	hud.update(delta)
	hud.visible = not _map.visible                         # (the map has the screen to itself)
	_menu.visible = state == PLAYING and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _bot == null
	if _map.visible:
		_map.queue_redraw()
	if _perf.visible:
		_perf_t += delta
		_perf_n += 1
		if _perf_t >= 1.0:
			var vp := get_viewport().get_viewport_rid()
			var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
			var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
			_perf.text = "%.0f fps (%.1f ms)   %s (F4 changes it)   draw calls %d   triangles %dk   video memory %.0f MB%s   F3 hides this" % [
				_perf_n / _perf_t, 1000.0 * _perf_t / _perf_n, _render_text(),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				"\ndrawing: cpu %.1f ms, gpu %.1f ms" % [cpu, gpu] if gpu > 0.0 or cpu > 0.0 else ""]
			# where the rest goes, by system (**user, of the browser build: "game code ~33 ms": which code?**)
			_perf.text += "\n" + V2World.prof_text(_perf_n) + "   robots awake %d of %d" % [
				robots.filter(func(r: V2Robot) -> bool: return r.is_processing()).size(), robots.size()]
			if _perf_log:
				print("[perf] ", _perf.text.replace("\n", " | "))
			_perf_t = 0.0
			_perf_n = 0


func _end_screen() -> void:
	ending = true
	_ui.visible = false
	_end = V2End.new()
	_top.add_child(_end)
	(_end as V2End).setup(self, state == WON, hud.blur)
