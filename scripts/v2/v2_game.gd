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
const TOUGH := {"spider": [0.14, 1.0, 1.0, 100.0], "drone": [0.28, 1.0, 1.0, 60.0], "turret": [0.28, 1.0, 1.0, 110.0]}
# How many of the robots the generator scatters are kept: a share of each room's, at most two in a room next to
# the start. (Its numbers were for V1's weaker hostiles: 22 a dungeon at threat 0.) The generator always runs at
# threat 0 and the game scales with the threat level (MORE, HP_PER_THREAT, _kit_weight), so that a seed's
# dungeon is the same at every level but for that.  [share kept, the most in one room]
const CROWD := [0.6, 3]
const MORE := 1.5                   # robots added to the dungeon per mission completed
const HP_PER_THREAT := 0.08         # robots' health: + this per mission completed
const SCORE_PER_THREAT := 0.25      # a kill's worth: + this per mission completed
const DROP := 0.35                  # chance that a destroyed robot leaves something
const REACH := 2.4                  # how near a door or a crate must be for E
const CHASE := 18                   # a robot follows the player at most this many cells

enum { PLAYING, WON, LOST }

static var missions := 0            # missions completed in this sitting: the threat level
static var total_score := 0

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
var walked: Dictionary = {}         # corridor id -> true
var exit_found := false
var crates: Array = []              # {node, lid, light, what, open}
var pickups: Array = []             # {node, what, t, y}
var seed_used := 0
var _props: Node3D
var _exit_xf := Transform3D.IDENTITY   # the gate's frame (world): the player is through it when inside its opening
var _ui: CanvasLayer
var _hp_fill: ColorRect
var _hp_text: Label
var _kits_text: Label
var _gun_text: Label
var _ammo_text: Label
var _goal_text: Label
var _note_text: Label
var _note_t := 0.0
var _banner: Label
var _banner_t := 0.0
var _dot: ColorRect
var _flash: ColorRect
var _low_hp: ColorRect
var _from_bars: Array = []
var _perf: Label
var _perf_t := 0.0
var _perf_n := 0
var _menu: Control
var _end: Control
var _map: V2Map
var _tick := 0.0
var _bot: Node
var _rng := RandomNumberGenerator.new()
var _loot_rng := RandomNumberGenerator.new()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	V2Fx.root = self
	V2Fx.reset()
	V2Sfx.root = self
	V2Sfx.enabled = not ("--no-sound" in args)
	_low = "--quality=low" in args
	if _low:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var capture := ""
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
		if a.begins_with("--bot"):
			bot = maxi(int(a.trim_prefix("--bot=")), 1) if a.contains("=") else 1
	_rng.seed = hash(seed_used) + 5
	_loot_rng.seed = hash(seed_used) + 11
	_environment()
	gen = DungeonGen.new().generate(seed_used, 0)           # (the threat level is applied here, not by the generator: see below)
	dungeon = V2Dungeon.new()
	add_child(dungeon)
	dungeon.build(gen)
	_props = (load(V2Assets.DIR + "props.glb") as PackedScene).instantiate()
	V2Assets.apply(_props)
	for l in gen.loot_spawns:
		_crate(l)
		# med kits thin out with the threat level (the first number is drawn at every level, so that the robots,
		# drawn next from the same stream, are the same at every level of a seed, plus the level's extra ones)
		if l.payoff == "kit" and _rng.randf() > _kit_weight() / (_kit_weight() + 7.0) * 11.0 / 4.0:
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
	player.global_position = gen.player_spawn + Vector3(0, 0.02, 0)
	player._yaw = gen.player_yaw
	player._pitch = deg_to_rad(-3.0)
	player.died.connect(func() -> void: finish(false))
	player.interact.connect(interact)
	for r in robots:
		r.player = player
	_hud()
	V2Sfx.ambience("room_tone")
	if "--game-test" in args or bot > 0 or capture != "":
		_bot = (load("res://scripts/v2/v2_game_bot.gd") as GDScript).new()
		_bot.game = self
		add_child(_bot)
		if capture != "":
			_bot.capture(capture)
		elif bot > 0:
			_bot.play_runs(bot)
		else:
			_bot.test()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	var node := _prop("Crate")
	add_child(node)
	node.position = (l.pos as Vector3) + out * 0.5
	node.rotation.y = float(l.yaw) + PI
	_solid(node, Vector3(0.9, 0.58, 0.56), Vector3(0, 0.29, 0))
	_set_layer(node, dungeon.areas[dungeon.area_at(l.pos)].layer)
	crates.append({"node": node, "lid": node.find_child("Crate_Lid", true, false), "light": node.find_child("Crate_Light", true, false),
		"what": String(l.payoff), "open": false})


## The exit portal: the gate in the middle of the deepest room, its front toward that room's doorway.
func _exit() -> void:
	var room: DungeonGen.Room = gen.rooms[gen.exit_room]
	var to := (DungeonGen.cell_center(room.doorway_cells[0]) - gen.exit_pos) if not room.doorway_cells.is_empty() else Vector3(0, 0, 1)
	var yaw := (PI / 2.0 if to.x > 0.0 else -PI / 2.0) if absf(to.x) > absf(to.z) else (0.0 if to.z > 0.0 else PI)
	var gate := _prop("ExitGate")
	add_child(gate)
	gate.position = gen.exit_pos
	gate.rotation.y = yaw
	for sx in [-1.0, 1.0]:
		_solid(gate, Vector3(0.42, 2.8, 0.6), Vector3(sx * 1.06, 1.4, 0))
	_solid(gate, Vector3(2.5, 0.42, 0.6), Vector3(0, 2.61, 0))
	var layer: int = dungeon.areas[dungeon.area_at(gen.exit_pos)].layer
	for side in [-1.0, 1.0]:
		var sign := Label3D.new()                          # (not in the heading font: that one has no X)
		sign.text = "EXIT"
		sign.font_size = 96
		sign.pixel_size = 0.0022
		sign.modulate = Color(0.1, 0.04, 0.22)
		sign.outline_size = 0
		sign.position = Vector3(0, 2.61, side * 0.33)
		sign.rotation_degrees.y = 0.0 if side > 0.0 else 180.0
		gate.add_child(sign)
		var spot := SpotLight3D.new()                      # the field lights the floor on both sides
		spot.light_color = V2Ui.VIOLET
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
		(c.light as MeshInstance3D).set_surface_override_material(0, V2Assets.material("RFrame"))
	drop(String(c.what), node.global_position + Vector3(0, 0.62, 0), 0.5)      # what is in it rises out of it


## A pickup at `at` (world), which the player takes by walking to it, after `delay` seconds.
func drop(what: String, at: Vector3, delay: float = 0.0) -> void:
	var node := _prop({"ammo": "AmmoBox", "health": "HealthCell", "kit": "MedKit"}[what])
	add_child(node)
	node.global_position = at
	var area := dungeon.area_at(at)
	if area >= 0:
		_set_layer(node, dungeon.areas[area].layer)
	pickups.append({"node": node, "what": what, "t": -delay, "y": at.y})


func _take(p: Dictionary) -> bool:
	var ok := false
	var note := ""
	match String(p.what):
		"ammo":
			ok = player.add_ammo(60)
			note = "Ammunition +60"
		"health":
			ok = player.add_health(35.0)
			note = "Health +35"
		"kit":
			ok = player.add_kit()
			note = "Med kit (H)"
	if ok:
		V2Sfx.play("pickup")
		say(note)
	return ok


func say(text: String) -> void:
	if _note_text != null:
		_note_text.text = text
		_note_t = 2.2


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
		var at := robot.global_position
		var b := robot.bounds
		drop(roll_payoff(), Vector3(clampf(at.x + _rng.randf_range(-0.5, 0.5), b.position.x, b.end.x), 0.05,
			clampf(at.z + _rng.randf_range(-0.5, 0.5), b.position.y, b.end.y)), 2.5 if robot.kind == "drone" else 1.0)


func finish(won: bool) -> void:
	if state != PLAYING:
		return
	state = WON if won else LOST
	if won:
		V2Sfx.play("exit")
		player.invulnerable = true
		missions += 1
	total_score += score
	_end_screen()
	if _bot == null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.mouse_look = false
	_map.visible = false


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
				_banner.text = "ROOM %d OF %d" % [explored.size(), gen.rooms.size()]
				_banner_t = 2.4
			if int(a.id) == gen.exit_room:
				exit_found = true
		else:
			walked[a.id] = true
	dungeon.update(at, V2Player.GUN_LAYER)
	if state == PLAYING:
		elapsed += delta
		var local := _exit_xf.affine_inverse() * at
		if absf(local.x) < 0.8 and absf(local.z) < 0.45:
			finish(true)
		_tick -= delta
		if _tick <= 0.0:
			_tick = 0.4
			_robots_tick()
	_pickups(delta)
	_hud_update(delta)


## Twice a second: which robots are awake and drawn, and which go after the player.
func _robots_tick() -> void:
	var at := player.global_position
	var my_cell := V2Dungeon.cell_of(at)
	for r in robots:
		var d := r.global_position.distance_to(at)
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
		if r.state == V2Robot.ROAM and r.alerted and r._unseen > 2.5 and here >= 0 and area != here:
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
		elif event.keycode == KEY_TAB and state == PLAYING:
			_map.visible = not _map.visible                # (the game goes on behind it)


# ---------------------------------------------------------------------------------------------- HUD and screens
func _hud() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	_low_hp = V2Ui.full(_ui, Color(0.8, 0.05, 0.02, 0.0))
	_flash = V2Ui.full(_ui, Color(1.0, 0.1, 0.05, 0.0))
	for spec in [[-90.0, -150.0, 180.0, 6.0], [150.0, -90.0, 6.0, 180.0], [-90.0, 144.0, 180.0, 6.0], [-156.0, -90.0, 6.0, 180.0]]:
		_from_bars.append(V2Ui.rect(_ui, Color(1.0, 0.2, 0.12, 0.0), 0.5, 0.5, spec[0], spec[1], spec[2], spec[3]))      # ahead, right, behind, left
	_dot = V2Ui.rect(_ui, Color(1, 1, 1, 0.9), 0.0, 0.0, 0, 0, 4, 4)
	V2Ui.label(_ui, "HEALTH", 0.0, 1.0, 26.0, -62.0, 13, Color(0.7, 0.8, 0.86))
	V2Ui.rect(_ui, Color(0, 0, 0, 0.55), 0.0, 1.0, 24.0, -42.0, 244.0, 18.0)
	_hp_fill = V2Ui.rect(_ui, V2Ui.GREEN, 0.0, 1.0, 26.0, -40.0, 240.0, 14.0)
	_hp_text = V2Ui.label(_ui, "100", 0.0, 1.0, 278.0, -46.0, 18)
	_kits_text = V2Ui.label(_ui, "", 0.0, 1.0, 26.0, -88.0, 14, V2Ui.GREEN)
	_gun_text = V2Ui.label(_ui, "", 1.0, 1.0, -26.0, -88.0, 14, Color(0.7, 0.8, 0.86), false, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo_text = V2Ui.label(_ui, "", 1.0, 1.0, -26.0, -66.0, 34, Color(0.95, 0.98, 1.0), false, HORIZONTAL_ALIGNMENT_RIGHT)
	_goal_text = V2Ui.label(_ui, "", 0.0, 0.0, 26.0, 20.0, 15, V2Ui.CYAN)
	_perf = V2Ui.label(_ui, "", 0.0, 0.0, 26.0, 46.0, 14, Color(1.0, 0.9, 0.5))
	_perf.visible = false
	_note_text = V2Ui.label(_ui, "", 0.5, 1.0, 0.0, -150.0, 17, Color(0.95, 0.98, 1.0), false, HORIZONTAL_ALIGNMENT_CENTER)
	_banner = V2Ui.label(_ui, "", 0.5, 0.0, 0.0, 90.0, 40, Color(0.95, 0.98, 1.0), true, HORIZONTAL_ALIGNMENT_CENTER)
	_map = V2Map.new()
	_map.game = self
	_map.visible = false
	_ui.add_child(_map)
	# Esc: the mouse is free; the way back
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.visible = false
	_ui.add_child(_menu)
	V2Ui.rect(_menu, Color(0.02, 0.03, 0.045, 0.8), 0.5, 0.5, -180.0, -110.0, 360.0, 200.0)
	V2Ui.label(_menu, "The game goes on: there is no pause.", 0.5, 0.5, 0.0, -96.0, 13, Color(0.7, 0.78, 0.84), false, HORIZONTAL_ALIGNMENT_CENTER)
	V2Ui.button(_menu, "RESUME", 0.5, 0.5, 0.0, -60.0, func() -> void: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	V2Ui.button(_menu, "TITLE", 0.5, 0.5, 0.0, 4.0, to_title)


func to_title() -> void:
	missions = 0
	total_score = 0
	get_tree().change_scene_to_file(TITLE)


func _hud_update(delta: float) -> void:
	var size := get_viewport().get_visible_rect().size
	_hp_fill.offset_right = _hp_fill.offset_left + 240.0 * player.hp / V2Player.MAX_HP
	_hp_fill.color = V2Ui.GREEN if player.hp > 35.0 else V2Ui.RED
	_hp_text.text = "%d" % int(ceil(player.hp))
	_kits_text.text = ("MED KITS  %d   (H)" % player.kits) if player.kits > 0 else ""
	_gun_text.text = "MACHINE GUN" if player.weapon == "rifle" else "PISTOL"
	_ammo_text.text = ("%d / %d" % [player.mag.rifle, player.reserve]) if player.weapon == "rifle" else ("%d" % player.mag.pistol)
	_ammo_text.add_theme_color_override("font_color", V2Ui.RED if player.mag[player.weapon] <= 3 else Color(0.95, 0.98, 1.0))
	var hostiles := alive_in(here)
	_goal_text.text = "THREAT %d   ·   ROOMS %d / %d   ·   %s   ·   %s   ·   Tab: map" % [missions, explored.size(), gen.rooms.size(),
		("%d hostile%s here" % [hostiles, "" if hostiles == 1 else "s"]) if hostiles > 0 else "clear here",
		"the exit portal is in this room" if (exit_found and here >= 0 and dungeon.areas[here].room and int(dungeon.areas[here].id) == gen.exit_room)
		else ("exit found: see the map" if exit_found else "find the exit portal")]
	_note_t -= delta
	_note_text.modulate.a = clampf(_note_t, 0.0, 1.0)
	_banner_t -= delta
	_banner.modulate.a = clampf(_banner_t, 0.0, 1.0) * clampf((2.4 - _banner_t) * 4.0, 0.0, 1.0)
	_flash.color.a = player.hurt_flash * 0.3
	var to := player.hurt_from - player.global_position
	var side := wrapi(int(round(angle_difference(player._yaw, atan2(-to.x, -to.z)) / (-PI / 2.0))), 0, 4)      # 0 ahead, 1 right, 2 behind, 3 left
	for k in 4:
		(_from_bars[k] as ColorRect).color.a = player.hurt_flash * 0.75 if (k == side and state == PLAYING) else 0.0
	_low_hp.color.a = clampf((35.0 - player.hp) / 35.0, 0.0, 1.0) * (0.1 + 0.05 * sin(elapsed * 5.0)) if state == PLAYING else 0.0
	var dot := player.aim_dot if player.weapon in V2Player.AUTO else size / 2.0
	_dot.visible = state == PLAYING and dot.x >= 0.0 and not (player.busy in V2Player.NO_CURSOR) and not _map.visible
	_dot.position = dot - Vector2(2, 2)
	_dot.color = Color(1.0, 0.25, 0.15) if player.hit_confirm > 0.0 else Color(1, 1, 1, 0.9)
	_menu.visible = state == PLAYING and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _bot == null
	if _map.visible:
		_map.queue_redraw()
	if _perf.visible:
		_perf_t += delta
		_perf_n += 1
		if _perf_t >= 1.0:
			_perf.text = "%.0f fps (%.1f ms)   draw calls %d   triangles %dk   video memory %.0f MB   F3 hides this" % [_perf_n / _perf_t, 1000.0 * _perf_t / _perf_n,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]
			_perf_t = 0.0
			_perf_n = 0


func _end_screen() -> void:
	_end = Control.new()
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_end)
	var won := state == WON
	V2Ui.full(_end, Color(0.02, 0.03, 0.045, 0.8))
	V2Ui.label(_end, "MISSION COMPLETE" if won else "MISSION FAILED", 0.5, 0.5, 0.0, -190.0, 44, V2Ui.VIOLET if won else V2Ui.RED, true, HORIZONTAL_ALIGNMENT_CENTER)
	V2Ui.label(_end, "You reached the exit portal." if won else "You went down %s." % ("in a room" if here >= 0 and dungeon.areas[here].room else "in a corridor"),
		0.5, 0.5, 0.0, -128.0, 17, Color(0.8, 0.86, 0.9), false, HORIZONTAL_ALIGNMENT_CENTER)
	var lines := "Score  %d%s\nRobots destroyed  %d of %d\nRooms seen  %d of %d\nTime  %d:%02d\n%s" % [score,
		("   (all missions  %d)" % total_score) if total_score != score else "", kills, robots.size(), explored.size(), gen.rooms.size(),
		int(elapsed) / 60, int(elapsed) % 60,
		("Next dungeon: threat level %d (more robots, tougher, fewer med kits, kills worth more)" % missions) if won else ("Threat level %d" % missions)]
	V2Ui.label(_end, lines, 0.5, 0.5, 0.0, -88.0, 18, Color(0.95, 0.98, 1.0), false, HORIZONTAL_ALIGNMENT_CENTER)
	V2Ui.button(_end, "AGAIN", 0.5, 0.5, -150.0, 80.0, func() -> void: get_tree().reload_current_scene())
	V2Ui.button(_end, "TITLE", 0.5, 0.5, 150.0, 80.0, to_title)
