extends Node
## What plays the V2 game by code: its checks (`--game-test`), the balance bot (`--bot=N`) and the capture tour
## (`--game-capture=DIR`). The dungeon's collision is boxes made from its layout, so all of it runs headless
## (the pictures need a display, of course).
##
## The bot knows the layout (a player has the map). It clears the dungeon room by room in the order of the room
## tree, the exit's room last: walks cell to cell, opens the doors and crates on its way, fights what it can see
## (reaction 0.4 s, aim error about 1 degree, strafes as it fires, bursts with the machine gun, no use of cover),
## looks for what is left in a room before it leaves, uses a med kit under 45 health, then walks into the exit.

var game: Node
var player: V2Player
var dungeon: V2Dungeon
var gen: DungeonGen
const PULL := 0.7                   # how much of the barrel's climb the bot takes out
var _strafe := 1.0
var _strafe_t := 0.0
var _react := 0.0
var _err := Vector2.ZERO
var _err_t := 0.0
var _burst_t := 0.0
var log_lines: Array[String] = []


func _ready() -> void:
	player = game.player
	dungeon = game.dungeon
	gen = game.gen
	player.mouse_look = false


func note(text: String) -> void:
	log_lines.append("%4.0f s  %s" % [game.elapsed, text])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _frame() -> float:
	await get_tree().process_frame
	return get_process_delta_time()


func _until(cond: Callable, limit: float) -> float:
	var t := 0.0
	while not cond.call() and t < limit:
		t += await _frame()
	return t


func teleport(at: Vector3, yaw_deg: float = 0.0, pitch_deg: float = -4.0) -> void:
	player.global_position = Vector3(at.x, 0.02, at.z)
	player.velocity = Vector3.ZERO
	player._yaw = deg_to_rad(yaw_deg)
	player._pitch = deg_to_rad(pitch_deg)


## Cells from a to b through every doorway, shut or not (the bot opens doors).
func cells_to(a: Vector2i, b: Vector2i) -> Array:
	var prev := {a: a}
	var queue: Array = [a]
	var at := 0
	while at < queue.size():
		var c: Vector2i = queue[at]
		at += 1
		if c == b:
			break
		for d in DungeonGen.DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not gen.is_floor(n):
				continue
			if dungeon.area_of[c] != dungeon.area_of[n] and not dungeon._door_at.has([c, n]):
				continue
			prev[n] = c
			queue.append(n)
	if not prev.has(b):
		return []
	var out: Array = [b]
	while out[0] != a:
		out.push_front(prev[out[0]])
	return out


# ---------------------------------------------------------------------------------------------- walking and fighting
## The live robot the bot can see best (nearest), or null.
func _target() -> V2Robot:
	var best: V2Robot = null
	var best_d := 32.0
	var eye := player.cam.global_position
	for r in game.robots:
		if r.state == V2Robot.DEAD:
			continue
		var d := eye.distance_to(r.hit_point())
		if d >= best_d:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, r.hit_point())
		q.exclude = [player.get_rid()]
		var res := player.get_world_3d().direct_space_state.intersect_ray(q)
		if res.is_empty() or not res.collider.has_meta("robot") or res.collider.get_meta("robot") != r:
			continue
		best = r
		best_d = d
	return best


func _aim_at(point: Vector3, delta: float, rate_deg: float = 300.0) -> float:
	var d := point - player.cam.global_position
	var yaw := atan2(-d.x, -d.z) + _err.x
	var pitch := atan2(d.y, Vector2(d.x, d.z).length()) + _err.y
	# The machine gun's rounds leave along its barrel, which climbs and wanders in a burst: the bot pulls against
	# most of that, as a player does who keeps the cursor on the target. (Without it, it emptied six magazines
	# over a robot's head at 15 m and was shot down meanwhile.)
	var a := player.aim_dir()
	var climb := (asin(clampf(a.y, -1.0, 1.0)) - player._pitch) * PULL
	var drift := angle_difference(player._yaw, atan2(-a.x, -a.z)) * PULL
	if absf(climb) > 0.3 or absf(drift) > 0.3:             # (a reload or a switch swings the gun away: nothing to follow)
		climb = 0.0
		drift = 0.0
	yaw -= drift
	pitch -= climb
	player._yaw = rotate_toward(player._yaw, yaw, deg_to_rad(rate_deg) * delta)
	player._pitch = move_toward(player._pitch, clampf(pitch, -1.4, 1.4), deg_to_rad(rate_deg) * delta)
	return absf(angle_difference(player._yaw, yaw)) + absf(player._pitch - pitch)


## One frame of a fight with `r`: aim, strafe, fire, look after itself.
func _fight(r: V2Robot, delta: float) -> void:
	_err_t -= delta
	if _err_t <= 0.0:
		_err_t = 0.35
		_err = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * deg_to_rad(1.1)
	var off := _aim_at(r.hit_point(), delta)
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(0.35, 0.6)
		_strafe = -_strafe
	player.auto_move = Vector3(_strafe, 0, 0)
	_react -= delta
	var want := "rifle" if (player.mag.rifle > 0 or player.reserve > 0) else "pistol"
	if player.weapon != want and player.busy == "":
		player.switch_weapon()
	var fire := _react <= 0.0 and off < deg_to_rad(4.0)
	_burst_t -= delta                                      # the machine gun in bursts of half a second (held longer, its barrel climbs off the target)
	if _burst_t <= -0.3:
		_burst_t = 0.5
	player.bot_fire = fire and player.weapon == "rifle" and _burst_t > 0.0
	if fire and player.weapon == "pistol":
		player.act("Fire")
	if player.hp < 45.0:
		player.use_kit()


func _calm() -> void:
	if player.bot_fire:
		_react = 0.4
	player.bot_fire = false
	player.auto_move = Vector3.ZERO


## Walk straight to a point; fight on the way if `fight`. False if it did not get there.
func step_to(goal: Vector3, fight: bool, near: float = 0.3, limit: float = 14.0) -> bool:
	var t := 0.0
	var stuck := 0.0
	var last := player.global_position
	while true:
		var delta := await _frame()
		if game.state != game.PLAYING:
			_calm()
			return false
		var r := _target() if fight else null
		if r != null:
			_fight(r, delta)
			continue
		_calm()
		var to := goal - player.global_position
		to.y = 0.0
		if to.length() < near:
			break
		player._yaw = rotate_toward(player._yaw, atan2(-to.x, -to.z), deg_to_rad(400.0) * delta)
		player._pitch = move_toward(player._pitch, deg_to_rad(-4.0), delta * 2.0)
		player.auto_move = Vector3(0, 0, -1)
		t += delta
		stuck = stuck + delta if player.global_position.distance_to(last) < 0.4 * delta else 0.0
		last = player.global_position
		if t > limit or stuck > 2.5:
			_calm()
			return false
	_calm()
	return true


## Walk to cell `goal` cell by cell, opening the doors on the way. A fight's strafing takes the bot off its line:
## each step starts again from the cell it is in. False if it did not get there.
func go(goal: Vector2i, fight: bool = true) -> bool:
	var tries := 0
	while V2Dungeon.cell_of(player.global_position) != goal and tries < 80 and game.state == game.PLAYING:
		tries += 1
		var cells := cells_to(V2Dungeon.cell_of(player.global_position), goal)
		if cells.size() < 2:
			return false
		var here: Vector2i = cells[0]
		var next: Vector2i = cells[1]
		if not dungeon.passable(here, next):               # a shut door: up to it, E, wait for the leaves
			await step_to(V2Dungeon.center(here) + Vector3(next.x - here.x, 0, next.y - here.y) * 1.0, fight, 0.4)
			game.interact()
			await _wait(0.9)
			if not dungeon.passable(here, next):
				note("the door from %s to %s did not open" % [here, next])
				return false
		if not await step_to(V2Dungeon.center(next), fight):
			await step_to(V2Dungeon.center(here), fight)   # (caught on a corner: back to the middle of its cell, and again)
	if game.state == game.PLAYING and V2Dungeon.cell_of(player.global_position) == goal:
		await step_to(V2Dungeon.center(goal), fight)
	return V2Dungeon.cell_of(player.global_position) == goal


## Stay and fight until nothing in sight is alive (or `limit` seconds).
func clear(limit: float = 60.0) -> void:
	var t := 0.0
	var quiet := 0.0
	while t < limit and quiet < 1.2 and game.state == game.PLAYING:
		var delta := await _frame()
		t += delta
		var r := _target()
		if r != null:
			quiet = 0.0
			_fight(r, delta)
		else:
			quiet += delta
			_calm()
	_calm()


func _room_order() -> Array:
	# the tree's rooms, parents before children, the exit's branch last
	var on_exit_path := {}
	var k: int = gen.exit_room
	while k >= 0:
		on_exit_path[k] = true
		k = gen.rooms[k].parent
	var order: Array = []
	var stack: Array = [gen.spawn_room]
	while not stack.is_empty():
		var id: int = stack.pop_back()
		order.append(id)
		var kids: Array = []
		for r in gen.rooms:
			if r.parent == id:
				kids.append(r.id)
		kids.sort_custom(func(a: int, b: int) -> bool: return on_exit_path.has(a) and not on_exit_path.has(b))      # (the stack pops the last: the exit's branch goes first on it)
		stack.append_array(kids)
	order.erase(gen.exit_room)
	order.append(gen.exit_room)
	return order


## The whole dungeon: every room cleared, every crate opened, then the exit. Returns the result.
func play_level() -> Dictionary:
	var hp_low := 100.0
	for id in _room_order():
		if game.state != game.PLAYING:
			break
		var room: DungeonGen.Room = gen.rooms[id]
		var area: int = dungeon.area_of[room.rect.position]
		var mid := Vector2i(room.rect.position + room.rect.size / 2)
		if id != gen.spawn_room:
			await go(room.doorway_cells[0])
			await clear()
		# look for what is left of the room's robots: its middle, then its corners
		for c in ([mid] if id != gen.exit_room else []) + [room.rect.position + Vector2i(1, 1), room.rect.end - Vector2i(2, 2), room.rect.position + Vector2i(1, 1)]:
			if game.alive_in(area) == 0 or game.state != game.PLAYING:
				break
			await go(c)
			await clear(40.0)
		for crate in game.crates:
			var at: Vector3 = (crate.node as Node3D).global_position
			if game.state != game.PLAYING or crate.open or dungeon.area_at(at) != area:
				continue
			if await go(V2Dungeon.cell_of(at)):
				await step_to(at, true, 1.3, 6.0)
				game.interact()
				await _wait(0.9)
				await step_to(at, true, 0.9, 3.0)
		for p in game.pickups.duplicate():                 # what the wrecks left
			if game.state != game.PLAYING or not is_instance_valid(p.node) or float(p.t) <= 0.0:
				continue
			var lies: Vector3 = (p.node as Node3D).global_position
			if dungeon.area_at(lies) == area and await go(V2Dungeon.cell_of(lies)):
				await step_to(lies, true, 0.7, 5.0)
		hp_low = minf(hp_low, player.hp)
		note("room %d done: %d robots left in it, health %d, kits %d, rounds %d + %d" % [id, game.alive_in(area), player.hp, player.kits, player.mag.rifle, player.reserve])
	if game.state == game.PLAYING:
		await go(V2Dungeon.cell_of(gen.exit_pos))
		for side in [1.0, -1.0, 1.0]:                      # into the gate from in front of it or from behind: from the side its posts are in the way
			if game.state != game.PLAYING:
				break
			await step_to(game._exit_xf * Vector3(0, 0, 1.5 * side), true, 0.3, 6.0)
			await step_to(gen.exit_pos, true, 0.3, 6.0)
			await _wait(0.5)
	return {"won": game.state == game.WON, "hp": player.hp, "low": hp_low, "time": game.elapsed, "kills": game.kills}


func play_runs(_n: int) -> void:
	# (one dungeon per process: tools/v2_bot.sh runs it N times. The clock runs four times as fast: the physics
	# steps stay 1/60 s, there are only more of them a second)
	Engine.time_scale = 4.0
	await _wait(0.3)
	var r := await play_level()
	print("[bot] %s  seed %d  threat %d  rooms %d  robots %d  time %.0f s  health %d (lowest after a room %d)  kills %d  kits left %d  rounds left %d  shots %d (%d %% hit)" % [
		"WON" if r.won else ("LOST" if game.state == game.LOST else "STUCK"), game.seed_used, game.missions - (1 if r.won else 0), gen.rooms.size(),
		game.robots.size(), r.time, r.hp, r.low, r.kills, player.kits, player.reserve, player._rounds, 100 * player.shots_hit / maxi(player._rounds, 1)])
	if not r.won or "--verbose" in OS.get_cmdline_user_args():
		for l in log_lines:
			print("[bot]   ", l)
	get_tree().quit()


# ---------------------------------------------------------------------------------------------- checks
func _check(what: String, ok: bool, detail: String = "") -> bool:
	print("[game] %s: %s%s" % [what, "PASS" if ok else "FAIL", ("  (" + detail + ")") if detail != "" else ""])
	return ok


func test() -> void:
	var ok := true
	await _wait(0.3)
	player.invulnerable = true
	# --- the generator: forty layouts
	var bad: Array = []
	var robots_0 := 0
	var robots_3 := 0
	for s in range(1, 41):
		var g := DungeonGen.new().generate(s, 0)
		var seen := {g.rooms[g.spawn_room].rect.position: true}
		var queue: Array = [g.rooms[g.spawn_room].rect.position]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d in DungeonGen.DIRS:
				if g.is_floor(c + d) and not seen.has(c + d):
					seen[c + d] = true
					queue.append(c + d)
		var deepest := 0
		for r in g.rooms:
			deepest = maxi(deepest, r.depth)
		if g.rooms.size() < 8 or g.rooms.size() > 12 or seen.size() != g.cells.size() or g.exit_room == g.spawn_room \
				or g.rooms[g.exit_room].depth != deepest or g.enemy_spawns.any(func(e: Dictionary) -> bool: return int(e.room) == g.spawn_room):
			bad.append(s)
		robots_0 += g.enemy_spawns.size()
		robots_3 += DungeonGen.new().generate(s, 3).enemy_spawns.size()
	ok = _check("generator: 40 layouts of 8 to 12 rooms, every cell reachable, the exit in the deepest room, none in the start room", bad.is_empty(),
		"bad seeds: %s" % str(bad) if not bad.is_empty() else "robots per dungeon: %.1f at threat 0, %.1f at threat 3" % [robots_0 / 40.0, robots_3 / 40.0]) and ok
	ok = _check("the threat level adds robots", robots_3 > robots_0 * 1.3) and ok
	# --- this dungeon
	var kinds := {}
	for r in game.robots:
		kinds[r.kind] = int(kinds.get(r.kind, 0)) + 1
	ok = _check("the dungeon is built", dungeon.areas.size() == gen.rooms.size() + gen.corridors.size() and game.robots.size() >= gen.rooms.size() - 1 and game.robots.size() <= gen.enemy_spawns.size()
		and game.crates.size() == gen.loot_spawns.size(), "seed %d: %d rooms, %d corridors, %d doors with leaves, %d crates, robots %s" % [game.seed_used, gen.rooms.size(),
		gen.corridors.size(), dungeon.doors.filter(func(d: Dictionary) -> bool: return d.door).size(), game.crates.size(), str(kinds)]) and ok
	var space := player.get_world_3d().direct_space_state
	var walls := 0
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var q := PhysicsRayQueryParameters3D.create(player.cam.global_position, player.cam.global_position + d * 40.0)
		q.exclude = [player.get_rid()]
		var res := space.intersect_ray(q)
		if not res.is_empty() and res.position.distance_to(player.cam.global_position) < 30.0:
			walls += 1
	ok = _check("walls stop a ray in every direction from the start", walls == 4, "%d of 4" % walls) and ok
	# --- the pistol's magazine: 15 rounds, then it reloads by itself
	var t := 0.0
	while player.mag.pistol > 0 and t < 30.0:
		player.act("Fire")
		t += await _frame()
	var fired: int = V2Player.MAG.pistol - player.mag.pistol
	await _until(func() -> bool: return player.mag.pistol == V2Player.MAG.pistol, 6.0)
	ok = _check("pistol: magazine runs out and is reloaded", fired == 15 and player.mag.pistol == 15, "%d rounds in %.1f s" % [fired, t]) and ok
	player.switch_weapon()
	await _until(func() -> bool: return player.busy == "", 3.0)
	player.bot_fire = true
	await _until(func() -> bool: return player.mag.rifle == 0, 8.0)
	player.bot_fire = false
	await _until(func() -> bool: return player.mag.rifle == 30, 6.0)
	ok = _check("machine gun: 30 rounds, then a reload out of the reserve", player.mag.rifle == 30 and player.reserve == 30, "now %d + %d" % [player.mag.rifle, player.reserve]) and ok
	player.switch_weapon()
	# --- a crate: E opens it, what is in it is taken
	var crate: Dictionary = game.crates[0]
	var cat: Vector3 = (crate.node as Node3D).global_position
	var front := (crate.node as Node3D).global_basis.z
	player.hp = 50.0
	var before := [player.reserve, player.hp, player.kits]
	teleport(cat + front * 0.8)
	await _wait(0.2)
	game.interact()
	await _wait(1.6)
	var gained: bool = (crate.what == "ammo" and player.reserve == before[0] + 60) or (crate.what == "health" and player.hp > before[1]) \
		or (crate.what == "kit" and player.kits == before[2] + 1)
	ok = _check("crate: opened with E, what is in it taken", bool(crate.open) and gained, "%s" % crate.what) and ok
	player.kits = 1
	player.hp = 50.0
	var used := player.use_kit()
	ok = _check("med kit (H)", used and is_equal_approx(player.hp, 90.0) and player.kits == 0) and ok
	player._since_hurt = 99.0
	await _wait(1.0)
	ok = _check("health does not come back by itself", is_equal_approx(player.hp, 90.0)) and ok
	player.hp = 100.0
	# --- a door: shut it blocks the way and the paths, E opens it
	var di := -1
	for i in dungeon.doors.size():
		if dungeon.doors[i].door and di < 0:
			di = i
	var door: Dictionary = dungeon.doors[di]
	var shut_blocks: bool = not dungeon.passable(door.a, door.b) and dungeon.path(door.a, door.b).is_empty()
	teleport(V2Dungeon.center(door.a))
	await _wait(0.2)
	var off := Vector3(-door.dir.y, 0, door.dir.x) * 0.4 + Vector3(0, 1.2, 0)      # (through one leaf, not along the seam between the two)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(V2Dungeon.center(door.a) + off, V2Dungeon.center(door.b) + off))
	game.interact()
	await _wait(1.0)
	var clear_now := space.intersect_ray(PhysicsRayQueryParameters3D.create(V2Dungeon.center(door.a) + off, V2Dungeon.center(door.b) + off))
	ok = _check("door: shut it blocks, E opens it", shut_blocks and not hit.is_empty() and bool(door.open) and clear_now.is_empty() and dungeon.passable(door.a, door.b),
		"shut: no path %s, a ray stopped %s; opened %s, the ray passes %s" % [shut_blocks, not hit.is_empty(), door.open, clear_now.is_empty()]) and ok
	# --- robots: a wreck stays a wreck; the score
	var first: V2Robot = game.robots[0]
	first.hit(9999.0)
	await _wait(V2Robot.RESPAWN + 4.0)
	ok = _check("a destroyed robot stays destroyed", first.state == V2Robot.DEAD and game.kills == 1 and game.score == game.SCORE[first.kind],
		"kills %d, score %d" % [game.kills, game.score]) and ok
	# --- a spider or a drone that has seen the player follows them out of its room, through the doorways
	for i in dungeon.doors.size():
		game.open_door(i)
	var chaser: V2Robot = null
	for r in game.robots:
		if r.state != V2Robot.DEAD and r.kind != "turret" and chaser == null:
			chaser = r
	if chaser != null:
		var from_area := chaser.room
		var room: DungeonGen.Room = gen.rooms[dungeon.areas[from_area].id]
		chaser.alerted = true
		teleport(V2Dungeon.center(gen.rooms[room.parent].doorway_cells[0] if gen.rooms[room.parent].doorway_cells.size() > 0 else gen.rooms[room.parent].rect.position))
		teleport(gen.rooms[room.parent].center())
		t = await _until(func() -> bool: return chaser.state != V2Robot.TRAVEL and dungeon.area_at(chaser.global_position) != from_area, 90.0)
		var d := chaser.global_position.distance_to(player.global_position)
		ok = _check("a %s follows the player out of its room" % chaser.kind, dungeon.area_at(chaser.global_position) != from_area and d < 16.0,
			"after %.0f s it is %.1f m from the player, %.1f m travelled" % [t, d, chaser.travelled]) and ok
	var turret: V2Robot = null
	for r in game.robots:
		if r.kind == "turret" and r.state != V2Robot.DEAD and turret == null:
			turret = r
	if turret != null:
		var z0 := turret.position.z
		teleport(turret.global_position + Vector3(2.5, 0, 2.3 if turret.rail.y - z0 > z0 - turret.rail.x else -2.3))
		await _wait(5.0)
		ok = _check("turret runs along its rail", absf(turret.position.z - z0) > 0.5 and turret.in_arena(), "%.1f m" % absf(turret.position.z - z0)) and ok
	# --- the walk: from the start, through every room, to the exit
	for r in game.robots:
		if r.state != V2Robot.DEAD:
			r.hit(9999.0)
	await _wait(0.5)
	teleport(gen.player_spawn)
	await _wait(0.2)
	var walked := true
	for id in _room_order():
		var r2: DungeonGen.Room = gen.rooms[id]              # (the exit's room by a corner: the portal stands in its middle)
		walked = await go(r2.rect.position + (Vector2i(r2.rect.size / 2) if id != gen.exit_room else Vector2i.ZERO), false) and walked
	ok = _check("every room can be walked to, and counts", walked and game.explored.size() == gen.rooms.size() and game.exit_found,
		"rooms %d / %d; %s" % [game.explored.size(), gen.rooms.size(), "; ".join(log_lines)]) and ok
	game._map.visible = true
	await _wait(0.2)
	game._map.visible = false
	var level: int = game.missions
	await go(V2Dungeon.cell_of(gen.exit_pos), false)
	await step_to(gen.exit_pos, false, 0.3, 8.0)
	await _wait(0.5)
	ok = _check("the exit portal ends the mission and raises the threat level", game.state == game.WON and game._end != null and game.missions == level + 1,
		"score %d, threat %d -> %d" % [game.score, level, game.missions]) and ok
	# --- going down ends it too
	game.state = game.PLAYING
	if game._end != null:
		game._end.queue_free()
	player.invulnerable = false
	player.down = false
	player.hp = 100.0
	level = game.missions
	player.hurt(999.0, Vector3.ZERO)
	await _wait(0.2)
	ok = _check("going down fails the mission, the threat level stays", game.state == game.LOST and player.down and game.missions == level) and ok
	var want := ["door", "crate", "pickup", "heal", "exit", "pistol_shot", "rifle_shot", "pistol_mag_in", "rifle_mag_in"]
	var unheard: Array = []
	for key in want:
		if not V2Sfx.heard.has(key):
			unheard.append(key)
	ok = _check("sounds of the game", unheard.is_empty(), "never played: %s" % ", ".join(unheard) if not unheard.is_empty() else "%d keys" % want.size()) and ok
	print("[game] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()


# ---------------------------------------------------------------------------------------------- pictures
func _shot(dir: String, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(shot_name + ".png"))
	print("[capture] ", shot_name)


func _look_at(from: Vector3, at: Vector3) -> void:
	var d := at - (from + Vector3(0, 1.62, 0))
	teleport(from, rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))


func capture(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.invulnerable = true
	await _wait(1.0)
	await _shot(dir, "01_start")
	var start: DungeonGen.Room = gen.rooms[gen.spawn_room]
	var corner := Vector3((start.rect.position.x + 0.4) * 4.0, 0, (start.rect.position.y + 0.4) * 4.0)
	_look_at(corner, start.center() + Vector3(0, 1.2, 0))
	await _wait(0.6)
	await _shot(dir, "02_start_room")
	var crate: Dictionary = game.crates[0]
	var cat: Vector3 = (crate.node as Node3D).global_position
	_look_at(cat + (crate.node as Node3D).global_basis.z * 2.4 + (crate.node as Node3D).global_basis.x * 0.8, cat + Vector3(0, 0.5, 0))
	await _wait(0.5)
	await _shot(dir, "03_crate")
	game.open_crate(crate)
	await _wait(1.2)
	await _shot(dir, "04_crate_open")
	var di := -1
	for i in dungeon.doors.size():
		if dungeon.doors[i].door and di < 0:
			di = i
	var door: Dictionary = dungeon.doors[di]
	var inward := Vector3(-door.dir.x, 0, -door.dir.y)
	_look_at((door.at as Vector3) + inward * 4.5 + Vector3(-inward.z, 0, inward.x) * 1.2, (door.at as Vector3) + Vector3(0, 1.5, 0))
	await _wait(0.6)
	await _shot(dir, "05_door")
	game.open_door(di)
	await _wait(1.0)
	await _shot(dir, "06_door_open")
	_look_at(V2Dungeon.center(door.b) + Vector3(door.dir.x, 0, door.dir.y) * 0.5, V2Dungeon.center(door.b) + Vector3(door.dir.x, 0, door.dir.y) * 8.0 + Vector3(0, 1.4, 0))
	await _wait(0.6)
	await _shot(dir, "07_corridor")
	for i in dungeon.doors.size():
		game.open_door(i)
	# the rooms with most robots, from a corner
	var by_count: Array = []
	for r in gen.rooms:
		by_count.append([game.alive_in(dungeon.area_of[r.rect.position]), r.id])
	by_count.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for k in mini(3, by_count.size()):
		var room: DungeonGen.Room = gen.rooms[by_count[k][1]]
		var c := Vector3((room.rect.position.x + 0.45) * 4.0, 0, (room.rect.position.y + 0.45) * 4.0)
		_look_at(c, room.center() + Vector3(0, 1.4, 0))
		await _wait(2.5)
		await _shot(dir, "08_room_%d_robots" % (k + 1))
	var victim: V2Robot = null
	for r in game.robots:
		if r.state != V2Robot.DEAD and r.kind == "spider" and victim == null:
			victim = r
	if victim != null:
		_look_at(victim.global_position + Vector3(3.2, 0, 3.2), victim.hit_point())
		victim.hit(9999.0)
		await _wait(3.5)
		await _shot(dir, "09_wreck")
	var exit_room: DungeonGen.Room = gen.rooms[gen.exit_room]
	var ec := Vector3((exit_room.rect.position.x + 0.5) * 4.0, 0, (exit_room.rect.position.y + 0.5) * 4.0)
	_look_at(ec, gen.exit_pos + Vector3(0, 1.4, 0))
	await _wait(1.5)
	await _shot(dir, "10_exit_room")
	_look_at(gen.exit_pos + game._exit_xf.basis.z * 3.4, gen.exit_pos + Vector3(0, 1.4, 0))
	await _wait(0.8)
	await _shot(dir, "11_exit_portal")
	for r in gen.rooms:                                    # the map with everything found
		game.explored[r.id] = true
	for co in gen.corridors:
		game.walked[co.id] = true
	game.exit_found = true
	game._map.visible = true
	await _wait(0.4)
	await _shot(dir, "12_map")
	game._map.visible = false
	teleport(gen.exit_pos, 0.0)
	await _wait(0.8)
	await _shot(dir, "13_won")
	get_tree().quit()
