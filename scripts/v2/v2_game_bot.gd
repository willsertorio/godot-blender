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
		if stuck > 0.25:                                   # (a wreck in the way: over it)
			player.bot_jump = true
		if t > limit or stuck > 2.5:
			if OS.has_environment("V2_BOT_STUCK"):
				for h in [0.1, 0.5, 1.0, 1.5]:
					var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, h, 0), player.global_position + Vector3(0, h, 0) + to.normalized() * 1.5)
					q.exclude = [player.get_rid()]
					var res := player.get_world_3d().direct_space_state.intersect_ray(q)
					if not res.is_empty():
						var sh := (res.collider as Node).get_child(0) as CollisionShape3D
						printerr("[bot]   ray at %.1f m: %s at %s, box %s, hit %s" % [h, str((res.collider as Node).get_path()), str((res.collider as Node3D).global_position), str((sh.shape as BoxShape3D).size) if sh != null and sh.shape is BoxShape3D else "?", str(res.position)])
				printerr("[bot] did not reach %s: at %s (cell %s), %.1f m short" % [str(goal), str(player.global_position), str(V2Dungeon.cell_of(player.global_position)), to.length()])
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
	# --- no reload at a run; footsteps at the pace of the walk the view shows (two a second)
	player.select_weapon("rifle")
	await _wait(0.8)
	player.busy = ""
	player.mag.rifle = 10
	player.reserve = 60
	player._running = true
	var refused := not player.reload()
	player._running = false
	var allowed := player.reload()
	await _wait(3.0)
	var before_steps: int = player.steps
	player.auto_move = Vector3(0, 0, -1)
	var yaw_was := player._yaw
	for leg in 2:                                          # (there and back, so as to stay in the room; a turn costs a step)
		await _wait(2.0)
		player._yaw += PI
	player.auto_move = Vector3.ZERO
	player._yaw = yaw_was
	var paced: int = player.steps - before_steps
	ok = _check("no reload at a run; footsteps two a second at a walk", refused and allowed and paced >= 5 and paced <= 9,       # (by distance, as before, it was 17)
		"R at a run refused: %s, standing: %s; %d footsteps in 4 s of walking" % [str(refused), str(allowed), paced]) and ok
	# --- robots: a wreck stays a wreck; the score
	var first: V2Robot = game.robots[0]
	first.hit(9999.0)
	await _wait(V2Robot.RESPAWN + 4.0)
	ok = _check("a destroyed robot stays destroyed", first.state == V2Robot.DEAD and game.kills == 1 and game.score == game.SCORE[first.kind],
		"kills %d, score %d" % [game.kills, game.score]) and ok
	# --- a wreck is solid: it stops a walk, and a jump goes over it
	var hulk: V2Robot = null
	for r in game.robots:
		if r.kind == "spider" and hulk == null:
			hulk = r
	if hulk != null:
		var kills_was: int = game.kills
		var score_was: int = game.score
		if hulk.state != V2Robot.DEAD:
			hulk.hit(9999.0)
		teleport(hulk.global_position + Vector3(0, 0, 6.0))
		t = await _until(func() -> bool: return hulk._wreck_body != null, 8.0)
		game.kills = kills_was
		game.score = score_was
		var solid := hulk._wreck_body != null
		var box := Vector3.ZERO
		var stopped := false
		var over := false
		if solid:
			var mid: Vector3 = hulk._wreck_body.global_position
			box = ((hulk._wreck_body.get_child(0) as CollisionShape3D).shape as BoxShape3D).size
			# (walk at it along +Z from a free side: the way that is free of walls and cover is found by ray)
			var from := mid
			for a in 8:
				var dirv := Vector3(sin(a * PI / 4.0), 0.0, cos(a * PI / 4.0))
				var q := PhysicsRayQueryParameters3D.create(mid + Vector3(0, 1.0, 0) + dirv * (box.length() / 2.0 + 0.1), mid + Vector3(0, 1.0, 0) + dirv * 3.2)
				q.collision_mask = 1
				var q2 := PhysicsRayQueryParameters3D.create(mid + Vector3(0, 1.0, 0) - dirv * (box.length() / 2.0 + 0.1), mid + Vector3(0, 1.0, 0) - dirv * 3.2)
				q2.collision_mask = 1
				var dss := player.get_world_3d().direct_space_state
				if dss.intersect_ray(q).is_empty() and dss.intersect_ray(q2).is_empty():
					from = mid + dirv * 2.6
					break
			var yaw := rad_to_deg(atan2(from.x - mid.x, from.z - mid.z))
			teleport(from, yaw)
			player.auto_move = Vector3(0, 0, -1)
			await _wait(2.2)
			stopped = (player.global_position - from).length() < 2.6 and player.global_position.y < 0.2
			var short_of := Vector2(player.global_position.x - mid.x, player.global_position.z - mid.z).length()
			teleport(from, yaw)
			var tj := 0.0
			var top := 0.0
			while tj < 3.0:
				var dj := await _frame()
				tj += dj
				player.auto_move = Vector3(0, 0, -1)
				if Vector2(player.global_position.x - mid.x, player.global_position.z - mid.z).length() < maxf(box.x, box.z) / 2.0 + 0.75:
					player.bot_jump = true
				top = maxf(top, player.global_position.y)
			over = (player.global_position - from).length() > 3.4
			player.auto_move = Vector3.ZERO
			ok = _check("a wreck is solid: a walk stops at it, a jump goes over it", stopped and over,
				"box %.2f x %.2f x %.2f m after %.1f s; walking: stopped %.2f m from its middle; jumping: %.1f m travelled, feet up to %.2f m" % [box.x, box.y, box.z, t, short_of, (player.global_position - from).length(), top]) and ok
		else:
			ok = _check("a wreck is solid: a walk stops at it, a jump goes over it", false, "no box after %.1f s" % t) and ok
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
	# (in the biggest room, with a spider and a drone put back in service two cells away: the walk through the
	# dungeon has left none)
	var big: DungeonGen.Room = gen.rooms[0]
	for r in gen.rooms:
		if r.rect.get_area() > big.rect.get_area() and r.id != gen.exit_room:
			big = r
	var mid := Vector2i(big.rect.position + big.rect.size / 2)
	player.invulnerable = true
	teleport(V2Dungeon.center(mid))
	var put := {}
	var offsets := {"spider": Vector2i(-1, 0), "drone": Vector2i(0, -1)}
	for robot: V2Robot in game.robots:
		if offsets.has(robot.kind) and not put.has(robot.kind):
			put[robot.kind] = true
			robot.respawns = true
			robot.respawn()
			robot.respawns = false
			robot.set_process(true)
			robot.room = dungeon.area_of[mid]
			robot.arena = dungeon.arena(robot.room, 1.9)
			robot.place(V2Dungeon.center(mid + offsets[robot.kind]), 0.0)
	await _wait(0.6)
	player.invulnerable = false
	player.hurt(999.0, Vector3.ZERO)
	await _wait(0.2)
	ok = _check("going down fails the mission, the threat level stays", game.state == game.LOST and player.down and game.missions == level) and ok
	# --- then: the player falls onto their side, the gun lies on the floor, the robots come and look, none fires
	var could := 0                                         # robots that can walk or fly there
	for r in game.robots:
		if r.state != V2Robot.DEAD and r.kind != "turret":
			var cells := dungeon.path(V2Dungeon.cell_of(r.global_position), V2Dungeon.cell_of(player.global_position))
			if not cells.is_empty() and cells.size() <= game.GATHER:
				could += 1
	var shots := 0
	for r in game.robots:
		shots += r.shots_fired
	await _wait(11.0)
	var nearest := 99.0
	var facing := 0
	for r: V2Robot in game._watchers:
		var d := Vector2(r.global_position.x - player.global_position.x, r.global_position.z - player.global_position.z).length()
		nearest = minf(nearest, d)
		if d < 2.8 and r.aim_error() < deg_to_rad(12.0):
			facing += 1
	var shots_after := 0
	for r in game.robots:
		shots_after += r.shots_fired
	ok = _check("down: the view lies on its side at the floor, the gun is on the floor",
		absf(player.cam.global_position.y - player.global_position.y - V2Player.LIE) < 0.03 and absf(player.cam.global_basis.x.y) > 0.9
		and player.dropped != null and player.dropped.global_position.y < 0.12 and not player.overlay.visible,
		"eye %.2f m up, rolled %.0f degrees" % [player.cam.global_position.y - player.global_position.y, rad_to_deg(asin(clampf(absf(player.cam.global_basis.x.y), 0.0, 1.0)))]) and ok
	ok = _check("down: the robots come close and look, and hold their fire",
		(could == 0 or (game._watchers.size() >= mini(could, 2) and nearest < 2.6 and facing >= 1)) and shots_after == shots and game._end != null,
		"%d could come, %d came, the nearest %.1f m away, %d with their guns on the player, %d rounds fired" % [could, game._watchers.size(), nearest, facing, shots_after - shots]) and ok
	var want := ["door", "crate", "pickup", "heal", "exit", "pistol_shot", "rifle_shot", "pistol_mag_in", "rifle_mag_in"]
	var unheard: Array = []
	for key in want:
		if not V2Sfx.heard.has(key):
			unheard.append(key)
	ok = _check("sounds of the game", unheard.is_empty(), "never played: %s" % ", ".join(unheard) if not unheard.is_empty() else "%d keys" % want.size()) and ok
	print("[game] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()


## The training of the first room (-- --training-test, headless): the room's doors are locked and E does nothing
## at them; a shot from the hip does not count; three aimed pistol hits, then six aimed rifle hits on the dummy;
## the crate holds a health kit; taking it unlocks the doors; opening one starts the run. No robot hears any of it.
func training_test() -> void:
	var ok := true
	await _wait(1.0)
	var doors: Array = []
	for i in dungeon.doors.size():
		if gen.room_at(dungeon.doors[i].a) == gen.spawn_room:
			doors.append(i)
	var shut := doors.all(func(i: int) -> bool: return dungeon.doors[i].door and not dungeon.doors[i].open and dungeon.doors[i].locked)
	ok = _check("training: the first room's doors are shut and locked, the dummy stands on its pad",
		game.training and game.dummy != null and not doors.is_empty() and shut and game.dummy.position.y > 0.25, "%d doors" % doors.size()) and ok
	var d0: Dictionary = dungeon.doors[doors[0]]
	var inward := Vector3(-d0.dir.x, 0, -d0.dir.y)
	teleport((d0.at as Vector3) + inward * 1.6)
	await _wait(0.3)
	var prompt: String = game.in_reach()
	game.interact()
	await _wait(0.4)
	ok = _check("training: E does nothing at a locked door, and no prompt offers it", not d0.open and prompt == "") and ok
	# in front of the dummy, 2.8 m from it (the ground round it is kept clear)
	var target: V2Robot = game.dummy
	var to_spawn: Vector3 = (game.start_at - target.global_position)
	to_spawn.y = 0.0
	var stand := target.global_position + to_spawn.normalized() * 2.8
	stand.y = 0.0                                          # (the dummy stands on its pad; the player on the floor)
	_look_at(stand, target.hit_point())
	await _wait(0.4)
	player.act("Fire")
	await _wait(0.6)
	ok = _check("training: a shot from the hip does not count", game.train_step == 0 and game.train_hits == 0) and ok
	player.bot_aim = true
	player.act("ADS")
	await _until(func() -> bool: return player._aimed > 0.9, 2.0)
	for k in 3:
		_look_at(stand, target.hit_point())
		await _wait(0.15)
		player.act("Fire")
		await _wait(0.6)
	ok = _check("training: three aimed pistol hits pass the first step", game.train_step == 1, "step %d, hits %d" % [game.train_step, game.train_hits]) and ok
	# its feet stay where its clip has them while its body is thrown about (every reaction; a foot off that place
	# is a foot in the air or dragged)
	await _until(func() -> bool: return target._react == "", 8.0)
	await _wait(0.6)
	var worst := 0.0
	var before := 0.0
	var folded := 0.0
	var body_moved := 0.0
	for name in V2Robot.REACTIONS:
		target.force_react = name
		target.hit(1.0, -to_spawn.normalized(), target.hit_point())
		target._wounds -= 1
		var tt := 0.0
		while tt < 2.0:
			tt += await _frame()
			var rest: Transform3D = target.global_transform * Transform3D(target._base, target._seat)
			for i in target._legs.size():
				if i < target._foot_rel.size():
					worst = maxf(worst, ((target._legs[i][3] as Node3D).global_position - rest * (target._foot_rel[i] as Vector3)).length())
			body_moved = maxf(body_moved, (target._root.global_position - rest.origin).length())
		if name == "buckle":                               # (its legs fold as far as they go: the last centimetres are out of reach)
			folded = worst
			worst = before
		before = worst
		await _until(func() -> bool: return target._react == "", 8.0)
		await _wait(0.6)
	target.force_react = ""
	ok = _check("training: the dummy reels with its feet planted", worst < 0.005 and folded < 0.05 and body_moved > 0.04 and target._legs.size() == 4,
		"through all five reactions its body was up to %.0f mm off its place, a foot at most %.1f mm off where its clip has it (%.0f mm as its legs fold in the buckle)" % [
			body_moved * 1000.0, worst * 1000.0, folded * 1000.0]) and ok
	player.bot_aim = false
	await _until(func() -> bool: return player.busy == "", 3.0)
	player.switch_weapon()
	await _until(func() -> bool: return player.busy == "" and player.weapon == "rifle", 4.0)
	_look_at(stand, target.hit_point())
	player.bot_aim = true
	player.act("ADS")
	await _until(func() -> bool: return player._aimed > 0.9, 2.0)
	player.bot_fire = true
	await _until(func() -> bool: return game.train_step == 2, 4.0)
	player.bot_fire = false
	player.bot_aim = false
	ok = _check("training: six aimed rifle hits pass the second step; the doors stay locked", game.train_step == 2 and d0.locked, "step %d, hits %d" % [game.train_step, game.train_hits]) and ok
	await _wait(3.5)
	ok = _check("training: the last round destroys the dummy; its wreck stays on the pad, solid, and counts for nothing",
		target.state == V2Robot.DEAD and target._wreck_body != null and absf(target.global_position.y - 0.31) < 0.12 and game.kills == 0 and game.score == 0,
		"state %d, box %s, at %.2f m, kills %d" % [target.state, str(target._wreck_body != null), target.global_position.y, game.kills]) and ok
	await _until(func() -> bool: return player.busy == "", 3.0)
	var crate: Dictionary = {}
	for c in game.crates:
		if dungeon.room_id_at((c.node as Node3D).global_position) == gen.spawn_room:
			crate = c
	var cat: Vector3 = (crate.node as Node3D).global_position
	teleport(cat + (crate.node as Node3D).global_basis.z * 1.3)
	await _wait(0.3)
	var crate_prompt: String = game.in_reach()
	game.interact()
	await _wait(1.6)
	for p in game.pickups.duplicate():
		if is_instance_valid(p.node):
			teleport((p.node as Node3D).global_position)
	await _wait(1.0)
	ok = _check("training: the room's crate holds a health kit; taking it unlocks the doors",
		String(crate.what) == "kit" and crate_prompt == "crate" and player.kits == 1 and game.train_step == 3 and not d0.locked,
		"crate: %s, kits %d, step %d" % [crate.what, player.kits, game.train_step]) and ok
	var heard: int = (game.robots as Array).filter(func(r: V2Robot) -> bool: return r.alerted).size()
	teleport((d0.at as Vector3) + inward * 1.6)
	await _wait(0.3)
	var door_prompt: String = game.in_reach()
	game.interact()
	await _wait(0.6)
	ok = _check("training: E opens the door and the run starts; the practice rounds are given back; no robot heard the practice",
		d0.open and door_prompt == "door" and not game.training and game.trained and player.mag.rifle == V2Player.MAG.rifle and heard == 0,
		"door open %s, training %s, magazine %d, robots alerted %d" % [str(d0.open), str(game.training), player.mag.rifle, heard]) and ok
	ok = _cage_check() and ok
	print("[game] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()


## A spider and a drone sent from one side of the training cage to the other, four ways each (along the rows and
## the columns, both senses): they get there, and never come nearer the cage than their room to pass. (Stepped
## here by hand, 30 times a second of its own clock: no waiting.) And no path leads through a cell the cage is on.
func _cage_check() -> bool:
	if V2Robot.no_go.is_empty():
		return _check("robots go round the cage", false, "no cage")
	var c: Vector3 = V2Robot.no_go[0][0]
	var h: float = V2Robot.no_go[0][1]
	var area: int = dungeon.area_of[gen.rooms[gen.spawn_room].rect.position]
	var arena: Rect2 = dungeon.arena(area, 1.2)
	var nearest := 1e9
	var arrived := 0
	var longest := 0.0
	teleport(Vector3(arena.position.x, 0, arena.position.y))           # (out of the robots' way)
	for kind in ["spider", "drone"]:
		for way in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			var reach := minf(7.0, (arena.size.x if way.x != 0.0 else arena.size.y) / 2.0 - 0.2)
			var side := Vector3(way.z, 0, way.x) * 0.4
			var r := V2Robot.new()
			game.add_child(r)
			r.setup(kind)
			r.player = player
			r.arena = arena
			r.grid = 4.0
			r.place(c - way * reach + side, 0.0)
			r.set_ai(false)
			r.set_process(false)
			r._target = c + way * reach + side
			var t := 0.0
			var there := false
			while t < 60.0 and not there:
				there = r._move(1.0 / 30.0, true, false)
				t += 1.0 / 30.0
				nearest = minf(nearest, maxf(absf(r.position.x - c.x), absf(r.position.z - c.z)))
			arrived += 1 if there else 0
			if not there and OS.has_environment("V2_CAGE"):
				printerr("[cage] %s way %s: from %s to %s, ended at %s after %.0f s, heading %.0f, clip %s, state %d, arena %s, cage %s" % [kind, str(way), str(c - way * reach + side), str(r._target), str(r.position.snapped(Vector3(0.01, 0.01, 0.01))), t, rad_to_deg(r.rotation.y), r.clip, r.state, str(arena), str(c)])
			longest = maxf(longest, t)
			r.queue_free()
	var through := 0
	for cell in dungeon.blocked:
		var a: Vector2i = cell + Vector2i(-1, 0)
		var b: Vector2i = cell + Vector2i(1, 0)
		if dungeon.path(a, b).has(cell):
			through += 1
	return _check("robots go round the cage: a spider and a drone, four ways each, get past it and stay out of it; no path through its cell",
		arrived == 8 and nearest >= h - 0.05 and through == 0,
		"%d of 8 arrived, the slowest in %.0f s; never nearer than %.2f m to its middle (the cage ends at 1.61, kept clear to %.2f); %d cells shut to paths, %d crossed" % [
			arrived, longest, nearest, h, dungeon.blocked.size(), through])


# ---------------------------------------------------------------------------------------------- pictures
## The training (-- --training --game-capture=DIR --part=train): each step's card with what it asks for in view.
func train(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(1.0)
	var target: V2Robot = game.dummy
	var to_spawn: Vector3 = game.start_at - target.global_position
	to_spawn.y = 0.0
	var feet := target.global_position
	feet.y = 0.0
	var start_room: DungeonGen.Room = gen.rooms[gen.spawn_room]      # the room from a corner: where the cage stands in it
	var corner := Vector3(start_room.rect.position.x * 4.0 + 1.2, 0, start_room.rect.position.y * 4.0 + 1.2)
	_look_at(corner, feet + Vector3(0, 1.0, 0))
	player.overlay.visible = false
	await _wait(0.5)
	await _shot(dir, "Train0_room")
	player.overlay.visible = true
	teleport(game.start_at, rad_to_deg(game.start_yaw), -3.0)       # as the player appears
	await _wait(0.6)
	await _shot(dir, "Train1_start")
	var stand := feet + to_spawn.normalized() * 3.4
	_look_at(stand, target.hit_point())
	player.bot_aim = true
	player.act("ADS")
	await _until(func() -> bool: return player._aimed > 0.9, 2.0)
	player.act("Fire")
	for k in 9:                                            # the dummy struck: frame after frame (0.13 s of the game apart here)
		await _shot(dir, "Train1_struck_%d" % k)
	await _wait(0.7)
	await _shot(dir, "Train1_aimed")
	player.bot_aim = false
	await _until(func() -> bool: return player.busy == "", 3.0)
	game._training_next()
	player.switch_weapon()
	await _until(func() -> bool: return player.busy == "" and player.weapon == "rifle", 4.0)
	_look_at(feet + to_spawn.normalized() * 4.2 + Vector3(to_spawn.z, 0, -to_spawn.x).normalized() * 1.6, target.hit_point())
	await _wait(0.5)
	await _shot(dir, "Train2_rifle")
	game._training_next()
	var crate: Dictionary = {}
	for c in game.crates:
		if dungeon.room_id_at((c.node as Node3D).global_position) == gen.spawn_room:
			crate = c
	var cat: Vector3 = (crate.node as Node3D).global_position
	_look_at(cat + (crate.node as Node3D).global_basis.z * 1.9 + (crate.node as Node3D).global_basis.x * 0.5, cat + Vector3(0, 0.5, 0))
	await _wait(0.6)
	await _shot(dir, "Train3_crate")
	game._training_next()
	var d0: Dictionary = {}
	for d in dungeon.doors:
		if gen.room_at(d.a) == gen.spawn_room:
			d0 = d
	var inward := Vector3(-d0.dir.x, 0, -d0.dir.y)
	_look_at((d0.at as Vector3) + inward * 2.0 + Vector3(-inward.z, 0, inward.x) * 0.7, (d0.at as Vector3) + Vector3(0, 1.35, 0))
	await _wait(0.6)
	await _shot(dir, "Train4_door")
	get_tree().quit()



func _shot(dir: String, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(shot_name + ".png"))
	print("[capture] ", shot_name)


func _look_at(from: Vector3, at: Vector3) -> void:
	var d := at - (from + Vector3(0, 1.62, 0))
	teleport(from, rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))


## Flicker hunt (-- --game-capture=DIR --part=flicker): at every doorway and in every room, three frames. `a` two frames after the
## player arrives there from another area, `b` eight frames later from the same spot, `c` with the camera 1 mm
## aside. a against b = what flashes when the player changes area; b against c = surfaces that fight for the same
## pixels (two faces in one plane) or sparkle. tools/flicker_diff.py reads them and lists the worst.
func flicker(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.invulnerable = true
	player.overlay.visible = false
	game._ui.visible = false
	for r in game.robots:
		r.process_mode = Node.PROCESS_MODE_DISABLED
		r.visible = false
	for i in dungeon.doors.size():
		game.open_door(i)
	await _wait(1.5)
	var views: Array = []                                  # [name, from (feet), look at]
	for i in dungeon.doors.size():
		var d: Dictionary = dungeon.doors[i]
		var out := Vector3(d.dir.x, 0, d.dir.y)
		var side := Vector3(-out.z, 0, out.x)
		var at: Vector3 = d.at
		views.append(["door%02d_room" % i, at - out * 3.6 + side * 0.7, at + Vector3(0, 0.9, 0)])
		views.append(["door%02d_sill" % i, at - out * 1.5, at + out * 0.3])
		views.append(["door%02d_sill2" % i, at + out * 1.9 + side * 0.4, at])
	for r in gen.rooms:
		var lo := Vector3(r.rect.position.x * 4.0, 0, r.rect.position.y * 4.0)
		var hi := Vector3(r.rect.end.x * 4.0, 0, r.rect.end.y * 4.0)
		var mid: Vector3 = (lo + hi) / 2.0
		views.append(["room%02d_from0" % r.id, lo + (mid - lo).normalized() * 1.2, mid + Vector3(0, 1.0, 0)])
		views.append(["room%02d_from2" % r.id, hi + (mid - hi).normalized() * 1.2, mid + Vector3(0, 1.0, 0)])
		views.append(["room%02d_corner" % r.id, lo + (mid - lo).normalized() * 4.0, lo + Vector3(0, 0.3, 0)])
	for co in gen.corridors:
		var cells: Array = co.cells
		views.append(["corr%02d" % co.id, V2Dungeon.center(cells[0]), V2Dungeon.center(cells[cells.size() - 1]) + Vector3(0, 1.2, 0)])
	var only := ""                                         # -- --match=TEXT: only the views whose name has TEXT in it
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--match="):
			only = arg.trim_prefix("--match=")
	if only != "":
		views = views.filter(func(v2: Array) -> bool: return String(v2[0]).contains(only))
	for v in views:
		for k in 3:
			if k != 1:
				_look_at((v[1] as Vector3) + (Vector3(0.001, 0, 0.0007) if k == 2 else Vector3.ZERO), v[2])
			player.velocity = Vector3.ZERO
			for f in (8 if k == 1 else 2):
				await _frame()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(dir.path_join("%s_%s.png" % [v[0], "abc"[k]]))
	print("[flicker] %d views" % views.size())
	get_tree().quit()


## Going down (-- --game-capture=DIR --part=death): the player is shot down in the room with most robots; frames of
## the fall, the gun on the floor, the robots coming to look, the options.
func death(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(1.0)
	var best := -1
	var most := 0
	for r in gen.rooms:
		var n: int = game.alive_in(dungeon.area_of[r.rect.position])
		if n > most:
			most = n
			best = r.id
	var room: DungeonGen.Room = gen.rooms[best]
	player.invulnerable = true
	_look_at(room.center() + Vector3(0.6, 0, 0.6), room.center() + Vector3(4, 1.2, 0))
	await _wait(2.5)
	var foe: V2Robot = null
	for r in game.robots:
		if r.state != V2Robot.DEAD and r.room == dungeon.area_of[room.rect.position] and (foe == null or r.kind == "spider"):
			foe = r
	_look_at(player.global_position, foe.hit_point())
	await _wait(0.4)
	player.invulnerable = false
	player.hurt(999.0, foe.global_position)
	var t := 0.0
	for stop in [0.2, 0.45, 0.7, 1.0, 1.6, 2.6, 3.8, 5.2, 7.0, 9.6]:
		await _wait(stop - t)
		t = stop
		await _shot(dir, "death_%04.1f" % stop)
	print("[death] watchers %d, end screen %s, gun on the floor %s" % [game._watchers.size(), str(game._end != null), str(player.dropped != null)])
	get_tree().quit()


## The rooms alone (-- --game-capture=DIR --part=rooms [--match=N,N]): every room (or the rooms numbered in --match)
## from two opposite corners at eye height, no robots, no gun, no HUD: for looking at the set and the light.
func rooms(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.invulnerable = true
	player.overlay.visible = false
	game._ui.visible = false
	for r in game.robots:
		r.process_mode = Node.PROCESS_MODE_DISABLED
		r.visible = false
	var want: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--match="):
			want = Array(a.trim_prefix("--match=").split(","))
	await _wait(1.0)
	for i in gen.rooms.size():
		if not want.is_empty() and not want.has(str(i)):
			continue
		var room: DungeonGen.Room = gen.rooms[i]
		var lo := Vector3(room.rect.position.x * 4.0, 0, room.rect.position.y * 4.0)
		var hi := Vector3(room.rect.end.x * 4.0, 0, room.rect.end.y * 4.0)
		var mid := (lo + hi) / 2.0
		var k := 0
		for corner in [lo + Vector3(1.6, 0, 1.6), hi - Vector3(1.6, 0, 1.6)]:
			_look_at(corner, mid + Vector3(0, 1.3, 0))
			await _wait(0.4)
			var info := "%d draw calls, %dk triangles" % [int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)]
			await _shot(dir, "room_%02d_%s" % [i, "ab"[k]])
			print("[rooms] room %d %s: %s" % [i, "ab"[k], info])
			k += 1
	get_tree().quit()


## Bullet marks (-- --game-capture=DIR --part=marks): rounds into a wall and the floor, seen close and from 4 m.
func marks(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.invulnerable = true
	for r in game.robots:
		r.process_mode = Node.PROCESS_MODE_DISABLED
		r.visible = false
	await _wait(1.0)
	var room: DungeonGen.Room = gen.rooms[gen.spawn_room]
	var lo := Vector3(room.rect.position.x * 4.0, 0, room.rect.position.y * 4.0)
	var wall := Vector3(lo.x, 1.5, room.center().z + 0.7)             # a point on the room's -x wall
	var from := wall + Vector3(1.4, -1.5, 0)
	for k in 9:
		var at := wall + Vector3(0, randf_range(-0.35, 0.3), randf_range(-0.45, 0.45))
		V2Fx.impact(at, Vector3(1, 0, 0))
	for k in 5:
		V2Fx.impact(Vector3(lo.x + randf_range(0.5, 1.1), 0.0, wall.z + randf_range(-0.5, 0.5)), Vector3.UP)
	await _wait(2.0)
	player.overlay.visible = false
	game._ui.visible = false
	_look_at(from, wall)
	await _wait(0.5)
	await _shot(dir, "marks_wall_close")
	_look_at(wall + Vector3(4.0, -1.5, 1.5), wall + Vector3(0, -0.5, 0))
	await _wait(0.5)
	await _shot(dir, "marks_4m")
	_look_at(wall + Vector3(1.6, -1.5, 0.0), Vector3(lo.x + 0.8, 0.0, wall.z))
	await _wait(0.5)
	await _shot(dir, "marks_floor")
	get_tree().quit()


## The screens of the UI concept (-- --game-capture=DIR --part=ui, at --resolution 1440x810: its pictures are
## v2/reference/ui/screens/*.png): the HUD at a door (the prompt), with the machine gun, hit and low, reloading,
## aiming; the map after three rooms; Signal lost. (Mission complete is the tour's last picture.)
func ui(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for r in game.robots:
		r.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait(1.0)
	var di := -1
	for i in dungeon.doors.size():
		if dungeon.doors[i].door and di < 0:
			di = i
	var door: Dictionary = dungeon.doors[di]
	var inward := Vector3(-door.dir.x, 0, -door.dir.y)
	var aside := Vector3(-inward.z, 0, inward.x)
	player.kits = 3
	_look_at((door.at as Vector3) + inward * 2.0 + aside * 0.7, (door.at as Vector3) + Vector3(0, 1.35, 0) - aside * 0.5)
	await _wait(0.8)
	await _shot(dir, "HudExplore")
	# the machine gun, a hit from ahead and to the left, low health, one kit
	player.switch_weapon()
	await _until(func() -> bool: return player.busy == "", 4.0)
	player.kits = 1
	player.mag.rifle = 24
	player.hp = 62.0
	await _wait(0.3)
	player.hurt(25.0, player.global_position + player.global_basis * Vector3(-3.0, 0, -4.0))
	await _frame()
	await _frame()
	await _shot(dir, "HudCombat")
	await _wait(1.2)
	await _shot(dir, "HudLow")
	player.mag.rifle = 6
	await _wait(0.2)
	await _shot(dir, "HudLowMagazine")
	player.act("ReloadTactical")
	await _wait(0.5)
	await _shot(dir, "HudReload")
	await _until(func() -> bool: return player.busy == "", 5.0)
	player.use_kit()
	await _frame()
	await _frame()
	await _frame()
	await _shot(dir, "HudHeal")
	game.say("+60 rifle ammo", "ammo_rifle")
	await _wait(0.4)
	await _shot(dir, "HudPickup")
	# the map after three rooms
	var order: Array = _room_order()
	for k in 3:
		var id: int = order[k]
		if not game.explored.has(id):
			game.explored[id] = true
			game.order[id] = game.explored.size()
	var r2: DungeonGen.Room = gen.rooms[order[1]]
	teleport(r2.center() + Vector3(1.0, 0, 0.6), 35.0)
	await _wait(0.6)
	game._map.visible = true
	await _wait(0.5)
	await _shot(dir, "Map")
	game._map.visible = false
	# Signal lost
	for r in game.robots:
		r.process_mode = Node.PROCESS_MODE_INHERIT
	player.hurt(999.0, player.global_position + Vector3(2, 0, -3))
	await _until(func() -> bool: return game._end != null, 12.0)
	await _wait(1.5)
	await _shot(dir, "Failure")
	get_tree().quit()


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
	_look_at(cat + (crate.node as Node3D).global_basis.z * 1.9 + (crate.node as Node3D).global_basis.x * 0.5, cat + Vector3(0, 0.5, 0))
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
		print("[capture] room %d (%s): %d draw calls, %dk triangles" % [room.id, dungeon.themes[room.id],
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0])
	var victim: V2Robot = null
	for r in game.robots:
		if r.state != V2Robot.DEAD and r.kind == "spider" and victim == null:
			victim = r
	if victim != null:
		_look_at(victim.global_position + Vector3(3.2, 0, 3.2), victim.hit_point())
		victim.hit(9999.0)
		await _wait(3.5)
		await _shot(dir, "09_wreck")
	var side: Vector3 = game._exit_xf.basis.x                       # (from in front and a little aside: nothing stands there)
	var front: Vector3 = game._exit_xf.basis.z
	_look_at(gen.exit_pos + front * 7.0 + side * 2.5, gen.exit_pos + Vector3(0, 1.5, 0))
	await _wait(1.5)
	await _shot(dir, "10_exit_room")
	_look_at(gen.exit_pos + front * 4.6 - side * 1.2, gen.exit_pos + Vector3(0, 1.5, 0))
	await _wait(0.8)
	await _shot(dir, "11_exit_portal")
	for r in gen.rooms:                                    # the map with everything found
		if not game.explored.has(r.id):
			game.explored[r.id] = true
			game.order[r.id] = game.explored.size()
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


## Pictures of the solid wrecks and the turret's long burst (-- --training --game-capture=DIR --part=wrecks):
## the training dummy destroyed on its pad; a spider's and a drone's wreck with the box that stops the player
## drawn over them (orange, only here); a turret winding up and firing, with the rounds of its burst counted.
func wrecks(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.invulnerable = true
	await _wait(1.0)
	if game.dummy != null and "--match=turret" in OS.get_cmdline_user_args():
		game._training_end()
	elif game.dummy != null:
		var target: V2Robot = game.dummy
		var to_spawn: Vector3 = game.start_at - target.global_position
		to_spawn.y = 0.0
		var feet := target.global_position
		feet.y = 0.0
		_look_at(feet + to_spawn.normalized() * 3.6, target.hit_point())
		await _wait(0.4)
		target.finish_off(player.last_aim)
		await _wait(0.5)
		await _shot(dir, "Dummy1_struck")
		await _until(func() -> bool: return target._wreck_body != null, 8.0)
		_look_at(feet + to_spawn.normalized() * 3.6, feet + Vector3(0, 0.5, 0))
		await _wait(0.5)
		await _shot(dir, "Dummy2_wreck")
		game._training_end()
	for i in dungeon.doors.size():
		game.open_door(i)
	for kind in ([] if "--match=turret" in OS.get_cmdline_user_args() else ["spider", "drone"]):
		var r: V2Robot = null
		for x in game.robots:
			if x.kind == kind and x.state != V2Robot.DEAD and r == null:
				r = x
		if r == null:
			continue
		for x in game.robots:
			if x != r and x.room == r.room and x.state != V2Robot.DEAD:
				x.set_process(false)
		teleport(r.global_position + Vector3(8.0, 0, 8.0))
		r.hit(9999.0)
		var t := await _until(func() -> bool: return r._wreck_body != null, 12.0)
		if r._wreck_body == null:
			print("[wrecks] %s: no box after %.1f s" % [kind, t])
			continue
		var mid: Vector3 = r._wreck_body.global_position
		var box: Vector3 = ((r._wreck_body.get_child(0) as CollisionShape3D).shape as BoxShape3D).size
		print("[wrecks] %s: box %.2f x %.2f x %.2f m, %.1f s after it was destroyed" % [kind, box.x, box.y, box.z, t])
		var from := mid + Vector3(2.6, 0, 1.6)
		_look_at(from, mid + Vector3(0, 0.3, 0))
		await _wait(0.6)
		await _shot(dir, "Wreck_%s" % kind)
		var show := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.45, 0.0, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.material = mat
		show.mesh = bm
		show.layers = 0xFFFFF
		game.add_child(show)
		show.global_position = mid
		await _wait(0.3)
		await _shot(dir, "Wreck_%s_box" % kind)
		show.queue_free()
	var turret: V2Robot = null
	for x in game.robots:
		if x.kind == "turret" and x.state != V2Robot.DEAD and turret == null:
			turret = x
	if turret != null:
		for x in game.robots:
			if x != turret and x.state != V2Robot.DEAD:
				x.set_process(false)
		var at := turret.global_position
		var stand := Vector3(at.x + 3.2, 0.0, at.z + 2.4)
		_look_at(stand, turret.hit_point())
		V2Sfx.heard.clear()
		var t0 := Time.get_ticks_msec()
		await _until(func() -> bool: return turret._spin_up > 0.0, 12.0)
		var wound := Time.get_ticks_msec()
		await _shot(dir, "Turret1_winding_up")
		await _until(func() -> bool: return turret.state == V2Robot.SHOOT, 6.0)
		var fired0: int = turret.shots_fired
		var start: float = game.elapsed
		await _wait(0.25)
		await _shot(dir, "Turret2_burst")
		await _wait(0.3)
		await _shot(dir, "Turret3_burst")
		await _until(func() -> bool: return turret.state != V2Robot.SHOOT, 8.0)
		print("[wrecks] turret: saw the player after %.1f s, a burst of %d rounds in %.2f s of the game's time; heard: %s" % [
			(wound - t0) / 1000.0, turret.shots_fired - fired0, game.elapsed - start,
			", ".join(["turret_spin_up", "turret_shot", "turret_spin_down", "turret_tail"].filter(func(k: String) -> bool: return V2Sfx.heard.has(k)))])
	get_tree().quit()


## Are the drones there, and can they be seen? (-- --game-capture=DIR --part=drones [--seed=N]): prints the robots
## by kind and, for each drone, where it is, how high, and whether it is drawn; pictures of the first three alive,
## from 6 m, as the player meets them (the player cannot be hurt; the other robots stand still).
func drones(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.invulnerable = true
	await _wait(1.0)
	var count := {"spider": 0, "drone": 0, "turret": 0}
	for r in game.robots:
		count[r.kind] += 1
	print("[drones] seed %d: %s" % [game.seed_used, str(count)])
	if DisplayServer.get_name() == "headless":             # (the count alone)
		get_tree().quit()
		return
	for i in dungeon.doors.size():
		game.open_door(i)
	var n := 0
	for r in game.robots:
		if r.kind != "drone":
			continue
		var cell := V2Dungeon.cell_of(r.global_position)
		var room := dungeon.room_id_at(r.global_position)
		# stand in the same room, 6 m away along the longer side
		var rect: Rect2i = gen.rooms[room].rect if room >= 0 else Rect2i(cell, Vector2i.ONE)
		var mid := Vector3((rect.position.x + rect.size.x / 2.0) * 4.0, 0, (rect.position.y + rect.size.y / 2.0) * 4.0)
		var away: Vector3 = mid - (r as V2Robot).global_position
		away.y = 0.0
		if away.length() < 1.0:
			away = Vector3(1, 0, 0)
		var from: Vector3 = (r as V2Robot).global_position + away.normalized() * 6.0
		from.x = clampf(from.x, rect.position.x * 4.0 + 1.0, rect.end.x * 4.0 - 1.0)
		from.z = clampf(from.z, rect.position.y * 4.0 + 1.0, rect.end.y * 4.0 - 1.0)
		from.y = 0.0
		_look_at(from, r.hit_point())
		await _wait(1.5)
		_look_at(from, r.hit_point())
		await _wait(0.2)
		var seen := 0
		var meshes: Array = (r as V2Robot).find_children("*", "MeshInstance3D", true, false)
		for m in meshes:
			if (m as MeshInstance3D).is_visible_in_tree():
				seen += 1
		print("[drones] drone in room %d at %s: %.2f m above the floor, state %d, processing %s, node visible %s, %d of %d meshes drawn, layers %d, %.1f m from the player" % [
			room, str(cell), r.global_position.y, r.state, str(r.is_processing()), str(r.is_visible_in_tree()), seen, meshes.size(),
			(meshes[0] as MeshInstance3D).layers if meshes.size() > 0 else -1, r.global_position.distance_to(player.global_position)])
		if n < 3:
			await _shot(dir, "Drone_%d" % n)
		if n == 0:                                         # the first one, watched for a while as it fights
			for k in 5:
				await _wait(2.5)
				_look_at(from, r.hit_point())
				await _wait(0.15)
				print("[drones]   +%.1f s: state %d, at %s, body %.2f m up, visible %s, %.1f m away, shots %d" % [(k + 1) * 2.65, r.state,
					str(r.global_position.snapped(Vector3(0.1, 0.1, 0.1))), r.hit_point().y, str(r.is_visible_in_tree()), r.global_position.distance_to(player.global_position), r.shots_fired])
				await _shot(dir, "Drone_0_later_%d" % k)
		n += 1
	get_tree().quit()


## The training dummy's five reactions to a hit (-- --training --game-capture=DIR --part=reactions): each started
## by a hit from the front, then five pictures of it, about 0.7 s of the game apart, from 4.5 m in front of the cage.
func reactions(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(1.0)
	var target: V2Robot = game.dummy
	var feet := target.global_position
	feet.y = 0.0
	var to_start: Vector3 = (game.start_at - feet).normalized()
	_look_at(feet + to_start * 4.5, feet + Vector3(0, 1.0, 0))
	player.overlay.visible = false
	game.hud.visible = false
	await _wait(0.5)
	for name in V2Robot.REACTIONS:
		target.force_react = name
		target.hit(1.0, -to_start, target.hit_point() + Vector3(0.1, 0, 0))
		for k in 5:
			await _wait(0.2 if k == 0 else 0.7)
			await _shot(dir, "React_%s_%d" % [name, k])
		await _until(func() -> bool: return target._react == "", 6.0)
		await _wait(0.8)
	get_tree().quit()

