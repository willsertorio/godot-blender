extends Node
## What plays the V2 game by code: its checks (`--game-test`), the balance bot (`--bot=N`) and the capture tour
## (`--game-capture=DIR`). All three need the rooms' collision, i.e. a display (xvfb-run -a godot --rendering-driver
## opengl3 ...): headless, the room meshes have no faces, nothing blocks a walk or a line of sight, and the walk
## and the fights are skipped.
##
## The bot (reaction 0.4 s, aim error about 1 degree, strafes while it fires, no use of cover) walks the level's
## waypoints (`NODES`, the same in every sector, found by sweeping a box through the room's collision), opens the
## crates and doors on its way, fights whatever it can see, uses a med kit under 45 health.

# waypoints of a sector (room frame, x z) and which are joined
const NODES := {
	"start": Vector2(0.2, 0.0), "h2": Vector2(0.5, -1.0), "h1": Vector2(2.2, -6.2), "gate": Vector2(3.8, -7.4),
	"rp": Vector2(4.6, -9.3), "dr": Vector2(5.75, -10.2), "u3": Vector2(4.5, -12.0), "um": Vector2(1.0, -12.0),
	"u2": Vector2(-2.5, -12.0), "u1": Vector2(-2.5, -10.5), "dl": Vector2(-3.8, -10.35),
	"dn": Vector2(-1.3, -10.45), "hn": Vector2(-1.3, -9.0),                   # the gap between the stairs and a post: the way into the hall
	"c_right": Vector2(5.0, -8.45), "c_frontleft": Vector2(-3.15, 1.0), "c_front": Vector2(-1.5, 1.7), "c_back": Vector2(1.0, -12.85),
	"exit0": Vector2(1.0, 1.2), "exit": Vector2(1.0, 2.5),
}
const EDGES := [["start", "h2"], ["h2", "h1"], ["h1", "gate"], ["gate", "rp"], ["rp", "dr"], ["rp", "u3"], ["u3", "um"], ["um", "u2"],
	["u2", "u1"], ["u1", "dl"], ["dl", "dn"], ["dn", "hn"], ["hn", "h1"], ["hn", "h2"], ["rp", "c_right"], ["h2", "c_frontleft"],
	["h2", "c_front"], ["um", "c_back"], ["h2", "exit0"], ["exit0", "exit"]]
const CRATE_NODE := {Vector2(5.85, -8.4): "c_right", Vector2(-4.02, 1.0): "c_frontleft", Vector2(-1.5, 2.65): "c_front", Vector2(1.0, -13.62): "c_back"}

var game: Node
var player: V2Player
var solid := true                    # the rooms have collision (not headless)
var _at := "start"                   # the waypoint the bot stands at (in its sector)
var _strafe := 1.0
var _strafe_t := 0.0
var _react := 0.0
var _err := Vector2.ZERO
var _err_t := 0.0
var _burst_t := 0.0
var log_lines: Array[String] = []


func _ready() -> void:
	player = game.player
	player.mouse_look = false
	solid = DisplayServer.get_name() != "headless"


func note(text: String) -> void:
	log_lines.append("%4.0f s  %s" % [game.elapsed, text])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _frame() -> float:
	await get_tree().process_frame
	return get_process_delta_time()


func _world(sector: int, node: String) -> Vector3:
	var p: Vector2 = NODES[node]
	return game.rooms[sector].position + Vector3(p.x, 0.0, p.y)


func _path(from: String, to: String) -> Array:
	var prev := {from: ""}
	var queue := [from]
	while not queue.is_empty():
		var n: String = queue.pop_front()
		if n == to:
			break
		for e in EDGES:
			var other := ""
			if e[0] == n:
				other = e[1]
			elif e[1] == n:
				other = e[0]
			if other != "" and not prev.has(other):
				prev[other] = n
				queue.append(other)
	var out: Array = []
	var k := to
	while k != "" and prev.has(k):
		out.push_front(k)
		k = prev[k]
	return out


func teleport(sector: int, node: String, yaw_deg: float = 0.0) -> void:
	player.global_position = _world(sector, node) + Vector3(0, 0.02, 0)
	player.velocity = Vector3.ZERO
	player._yaw = deg_to_rad(yaw_deg)
	_at = node


# ---------------------------------------------------------------------------------------------- walking and fighting
## The live robot the bot can see best (nearest), or null.
func _target() -> V2Robot:
	var best: V2Robot = null
	var best_d := 30.0
	var eye := player.cam.global_position
	for r in game.robots:
		if r.state == V2Robot.DEAD or not r.active:
			continue
		var d := eye.distance_to(r.hit_point())
		if d >= best_d:
			continue
		if solid:
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
	# the machine gun in bursts of half a second (held longer, its barrel climbs off the target)
	_burst_t -= delta
	if _burst_t <= -0.3:
		_burst_t = 0.5
	player.bot_fire = fire and player.weapon == "rifle" and _burst_t > 0.0
	if fire and player.weapon == "pistol":
		player.act("Fire")
	if player.hp < 45.0:
		player.use_kit()


func _calm() -> void:
	player.bot_fire = false
	player.auto_move = Vector3.ZERO


## Walk to waypoint `node` of the sector the bot is in, fighting on the way if `fight`. False if it did not get there.
func walk(node: String, fight: bool = true, limit: float = 40.0) -> bool:
	var sector: int = game._room_at(player.global_position.x)
	for step in _path(_at, node):
		var goal := _world(sector, step)
		var t := 0.0
		var stuck := 0.0
		var strayed := false
		var last := player.global_position
		while true:
			var delta := await _frame()
			if game.state != game.PLAYING:
				_calm()
				return false
			var r := _target() if fight else null
			if r != null:
				_fight(r, delta)
				var line := goal - _world(sector, _at)
				var rel := player.global_position - _world(sector, _at)
				var along := clampf(rel.dot(line.normalized()), 0.0, line.length()) if line.length() > 0.01 else 0.0
				strayed = (rel - line.normalized() * along).length() > 0.9
				continue
			if player.bot_fire:
				_react = 0.4
			_calm()
			# (a fight's strafing takes it off its line: back to the waypoint it came from first)
			var aim_for := _world(sector, _at) if strayed else goal
			var to := aim_for - player.global_position
			to.y = 0.0
			if to.length() < 0.25:
				if strayed:
					strayed = false
					continue
				break
			player._yaw = rotate_toward(player._yaw, atan2(-to.x, -to.z), deg_to_rad(400.0) * delta)
			player._pitch = move_toward(player._pitch, deg_to_rad(-4.0), delta * 2.0)
			player.auto_move = Vector3(0, 0, -1)
			t += delta
			stuck = stuck + delta if player.global_position.distance_to(last) < 0.4 * delta else 0.0
			last = player.global_position
			if t > limit or stuck > 3.0:
				_calm()
				log_lines.append("could not reach %s in sector %d (at %s after %.0f s)" % [step, sector, player.global_position, t])
				return false
		_at = step
	_calm()
	return true


## Stay and fight until nothing in sight is alive (or `limit` seconds).
func clear(limit: float = 60.0) -> void:
	var t := 0.0
	var quiet := 0.0
	while t < limit and quiet < 1.5 and game.state == game.PLAYING:
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


## Through the door on the right into the next sector.
func next_sector() -> bool:
	var sector: int = game._room_at(player.global_position.x)
	if not await walk("dr"):
		return false
	game.interact()
	await _wait(0.9)
	player.auto_move = Vector3.ZERO
	var goal := _world(sector + 1, "dl")
	var t := 0.0
	while player.global_position.distance_to(goal) > 0.3 and t < 12.0 and game.state == game.PLAYING:
		var delta := await _frame()
		t += delta
		var to := goal - player.global_position
		player._yaw = rotate_toward(player._yaw, atan2(-to.x, -to.z), deg_to_rad(400.0) * delta)
		player.auto_move = Vector3(0, 0, -1)
	_calm()
	_at = "dl"
	return game._room_at(player.global_position.x) == sector + 1


## The whole level: every crate on the way, every sector cleared from its gate, the exit. Returns the result line.
func play_level() -> Dictionary:
	_at = "start"
	var hp_low := 100.0
	for sector in game.LEVEL.size():
		if game.state != game.PLAYING:
			break
		note("sector %s entered: health %d, kits %d, rounds %d + %d" % [game.LEVEL[sector].name, player.hp, player.kits, player.mag.rifle, player.reserve])
		if sector > 0:
			await walk("hn")                               # from the door through the gap by the stairs into the hall
			await clear()
		for c in game.LEVEL[sector].crates:
			if game.state != game.PLAYING:
				break
			if await walk(CRATE_NODE[Vector2(c[0], c[1])]):
				game.interact()
				await _wait(1.2)
		await clear(20.0)
		# the door onward is locked while a robot of this sector works: look for what is left
		for node in ["h1", "h2", "h1", "gate", "hn", "h2"]:
			if game.alive_in(sector) == 0 or game.state != game.PLAYING:
				break
			await walk(node)
			await clear(30.0)
		hp_low = minf(hp_low, player.hp)
		note("sector %s done: %d robots left in it, health %d" % [game.LEVEL[sector].name, game.alive_in(sector), player.hp])
		if game.LEVEL[sector].has("exit"):
			var reached := await walk("exit")
			await _wait(0.5)                               # (the gate takes the player in on the game's next frame)
			note("exit: walk %s, state %d, at %s" % [reached, game.state, player.global_position])
		elif game.state == game.PLAYING:
			if not await next_sector():
				break
	return {"won": game.state == game.WON, "hp": player.hp, "low": hp_low, "time": game.elapsed, "kills": game.kills, "sector": game.current,
		"kits": player.kits, "reserve": player.reserve}


func play_runs(n: int) -> void:
	# (one run per process: the scene is reloaded for the next by the caller's loop, see tools/v2_bot.sh)
	await _wait(0.5)
	var r := await play_level()
	print("[bot] %s  time %.0f s  health %d (lowest between sectors %d)  kills %d/%d  sector %s  kits left %d  rounds left %d" % [
		"WON" if r.won else ("LOST" if game.state == game.LOST else "STUCK"), r.time, r.hp, r.low, r.kills, game.robots.size(),
		game.LEVEL[r.sector].name, r.kits, r.reserve])
	for l in log_lines:
		print("[bot]   ", l)
	get_tree().quit()


# ---------------------------------------------------------------------------------------------- checks
func _check(what: String, ok: bool, detail: String = "") -> bool:
	print("[game] %s: %s%s" % [what, "PASS" if ok else "FAIL", ("  (" + detail + ")") if detail != "" else ""])
	return ok


func _until(cond: Callable, limit: float) -> float:
	var t := 0.0
	while not cond.call() and t < limit:
		t += await _frame()
	return t


## `--game-test`; with `--walk` only the walk (the slow part under software GL).
func test() -> void:
	var ok := true
	await _wait(0.5)
	player.invulnerable = true
	if not ("--walk" in OS.get_cmdline_user_args()):
		ok = await _test_rules() and ok
	ok = await _test_walk() and ok
	ok = await _test_end() and ok
	print("[game] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()


func _test_rules() -> bool:
	var ok := true
	ok = _check("the level", game.rooms.size() == 4 and game.robots.size() == 8 and game.crates.size() == 6 and game.doors.size() == 3,
		"%d sectors, %d robots, %d crates, %d doors" % [game.rooms.size(), game.robots.size(), game.crates.size(), game.doors.size()]) and ok
	# --- the pistol's magazine: 15 rounds, then it reloads by itself
	var fired := 0
	var t := 0.0
	while player.mag.pistol > 0 and t < 30.0:
		player.act("Fire")
		t += await _frame()
	fired = V2Player.MAG.pistol - player.mag.pistol
	var t_reload := await _until(func() -> bool: return player.mag.pistol == V2Player.MAG.pistol, 6.0)
	ok = _check("pistol: magazine runs out and is reloaded", fired == 15 and player.mag.pistol == 15, "%d rounds in %.1f s, full again %.1f s later" % [fired, t, t_reload]) and ok
	# --- the machine gun: 30 rounds held, reload takes 30 from the 60 carried
	player.switch_weapon()
	await _until(func() -> bool: return player.busy == "", 3.0)
	player.bot_fire = true
	t = await _until(func() -> bool: return player.mag.rifle == 0, 8.0)
	player.bot_fire = false
	await _until(func() -> bool: return player.mag.rifle == 30, 6.0)
	ok = _check("machine gun: 30 rounds, then a reload out of the reserve", player.mag.rifle == 30 and player.reserve == 30, "empty after %.1f s, now %d + %d" % [t, player.mag.rifle, player.reserve]) and ok
	player.switch_weapon()
	# --- a crate: E opens it, what is in it is taken
	teleport(0, "c_right", -90.0)
	await _wait(0.2)
	game.interact()
	await _until(func() -> bool: return player.reserve == 90, 4.0)
	ok = _check("crate: opened with E, the ammunition taken", bool(game.crates[0].open) and player.reserve == 90, "reserve %d" % player.reserve) and ok
	# --- a med kit
	player.kits = 1
	player.hp = 50.0
	var used := player.use_kit()
	ok = _check("med kit (H)", used and is_equal_approx(player.hp, 90.0) and player.kits == 0, "health %d" % player.hp) and ok
	player.hp = 100.0
	# --- no regeneration in the game
	player.hp = 60.0
	player._since_hurt = 99.0
	await _wait(1.0)
	ok = _check("health does not come back by itself", is_equal_approx(player.hp, 60.0)) and ok
	player.hp = 100.0
	# --- robots: a wreck stays a wreck; the score
	var sp: V2Robot = game.robots[0]
	sp.hit(9999.0)
	await _wait(V2Robot.RESPAWN + 4.0)
	ok = _check("a destroyed robot stays destroyed", sp.state == V2Robot.DEAD and game.kills == 1 and game.score == 200, "kills %d, score %d" % [game.kills, game.score]) and ok
	# --- a door: locked while a robot of its sector works, then E opens it; and a drone that follows through it
	teleport(1, "dr", -90.0)
	await _wait(0.3)
	game.interact()
	await _wait(0.3)
	var was_locked: bool = not game.doors[1].open and game.alive_in(1) == 1
	game.robots[1].hit(9999.0)
	await _wait(0.8)
	game.interact()
	await _wait(1.0)
	var leaf: Node3D = game.doors[1].leaves[0]
	ok = _check("door: locked while a robot of the sector works, then E opens it", was_locked and bool(game.doors[1].open)
		and absf(leaf.position.z - (V2World.DOOR_Z - V2World.DOOR_W / 4.0)) > 0.5 and game.rooms[2].visible) and ok
	var drone: V2Robot = null
	for r in game.robots:
		if r.kind == "drone" and r.room == 2 and drone == null:
			drone = r
	teleport(1, "h1", 90.0)
	drone.alerted = true
	var top := 0.0
	var low := 9.0
	t = 0.0
	while (drone.room != 1 or drone.state == V2Robot.TRAVEL) and t < 60.0 and drone.state != V2Robot.DEAD:
		t += await _frame()
		if drone.state == V2Robot.TRAVEL and absf(drone.position.z - V2World.DOOR_Z) < 0.5 and (drone.position.x > 5.6 or drone.position.x < -3.8):
			top = maxf(top, drone._seat.y + 0.87 * sin(drone._roll))
			low = minf(low, absf(drone._roll))
	ok = _check("drone follows the player through the open door, on edge", drone.room == 1 and drone.state != V2Robot.TRAVEL and low > 1.2 and top < V2World.DOOR_H,
		"in sector %s after %.1f s; in the doorway rolled %.0f degrees, its top at %.2f m (the lintel: %.2f)" % [game.LEVEL[drone.room].name, t, rad_to_deg(low), top, V2World.DOOR_H]) and ok
	# --- the turret runs along its rail to where the player is
	var turret: V2Robot = null
	for r in game.robots:
		if r.kind == "turret" and r.room == 2:
			turret = r
	teleport(2, "h2", 0.0)
	var z0 := turret.position.z
	await _wait(6.0)
	ok = _check("turret runs along its rail", absf(turret.position.z - z0) > 0.5 and turret.in_arena(), "%.1f m" % absf(turret.position.z - z0)) and ok
	return ok


func _test_walk() -> bool:
	var ok := true
	# --- the walk: every waypoint of the level on foot, through the three doors, to the exit (needs collision)
	if solid:
		for r in game.robots:
			if r.state != V2Robot.DEAD:
				r.hit(9999.0)                              # (the walk is about the floor plan, not the fight)
		await _wait(0.5)
		teleport(0, "start")
		var walked := true
		for sector in 4:
			for node in (["h1", "c_frontleft", "c_front", "hn", "c_back", "c_right"] if sector < 3 else ["h1", "c_frontleft", "exit0"]):
				walked = walked and await walk(node, false)
			if sector < 3:
				walked = walked and await next_sector()
		ok = _check("the whole level can be walked", walked, "; ".join(log_lines)) and ok
		walked = await walk("exit", false)
		await _wait(0.3)
		ok = _check("the exit gate ends the level", game.state == game.WON and game._end != null, "score %d" % game.score) and ok
	else:
		print("[game] (headless: no collision, the walk and the exit are not checked)")
		game.finish(true)
		ok = _check("the level is won", game.state == game.WON and game._end != null) and ok
	return ok


func _test_end() -> bool:
	var ok := true
	# --- going down ends it too
	game.state = game.PLAYING
	if game._end != null:
		game._end.queue_free()
	player.invulnerable = false
	player.down = false
	player.hp = 100.0
	player.hurt(999.0, Vector3.ZERO)
	await _wait(0.2)
	ok = _check("going down loses the level", game.state == game.LOST and player.down) and ok
	if "--walk" in OS.get_cmdline_user_args():
		return ok
	var want := ["door", "crate", "pickup", "heal", "exit", "pistol_shot", "rifle_shot", "pistol_mag_in", "rifle_mag_in"]
	var unheard: Array = []
	for key in want:
		if not V2Sfx.heard.has(key):
			unheard.append(key)
	ok = _check("sounds of the game", unheard.is_empty(), "never played: %s" % ", ".join(unheard) if not unheard.is_empty() else "%d keys" % want.size()) and ok
	return ok


# ---------------------------------------------------------------------------------------------- pictures
func _shot(dir: String, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(shot_name + ".png"))
	print("[capture] ", shot_name)


func _stand(sector: int, x: float, z: float, yaw_deg: float, pitch_deg: float = -4.0) -> void:
	player.global_position = game.rooms[sector].position + Vector3(x, 0.02, z)
	player.velocity = Vector3.ZERO
	player._yaw = deg_to_rad(yaw_deg)
	player._pitch = deg_to_rad(pitch_deg)


func capture(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.invulnerable = true
	await _wait(1.0)
	await _shot(dir, "a1_start")
	_stand(0, 3.7, -8.9, -76.0, -14.0)                    # the crate by the door
	await _wait(0.4)
	await _shot(dir, "a2_crate")
	game.open_crate(game.crates[0])
	await _wait(1.3)
	await _shot(dir, "a3_crate_open")
	_stand(0, 3.6, -9.6, -78.0)                            # the door to B
	await _wait(1.0)
	await _shot(dir, "a4_door")
	game.open_door(0, true)
	await _wait(1.0)
	await _shot(dir, "a5_door_open")
	_stand(1, 3.9, -8.2, 147.0, -6.0)                       # B: the hall from its gate
	await _wait(2.5)
	await _shot(dir, "b1_hall")
	_stand(1, 0.4, 2.0, 0.0, -8.0)
	await _wait(1.0)
	await _shot(dir, "b2_spiders")
	game.robots[0].hit(9999.0)
	await _wait(3.5)
	await _shot(dir, "b3_wreck")
	game.open_door(1, true)
	_stand(2, 3.9, -8.2, 147.0, 8.0)                        # C: drones and the turret on its rail
	await _wait(3.0)
	await _shot(dir, "c1_drones_turret")
	_stand(2, 1.5, 1.6, 40.0, 24.0)
	await _wait(1.5)
	await _shot(dir, "c2_rail")
	# a drone of C comes after the player into B: through the doorway on edge
	var drone: V2Robot = null
	for r in game.robots:
		if r.kind == "drone" and r.room == 2 and drone == null:
			drone = r
	_stand(1, 3.4, -8.6, -70.0, -2.0)
	drone.alerted = true
	var t := 0.0
	while t < 40.0 and not (drone.state == V2Robot.TRAVEL and drone.room == 2 and drone.position.x < -3.2):
		t += await _frame()
	for k in 5:
		await _shot(dir, "t%d_drone_through_door" % (k + 1))
		await _wait(0.45)
	game.open_door(2, true)
	_stand(3, 3.9, -8.2, 160.0, -2.0)                       # D: the exit at the far end
	await _wait(2.0)
	await _shot(dir, "d1_exit_far")
	_stand(3, 1.0, -1.6, 180.0, 0.0)
	await _wait(1.0)
	await _shot(dir, "d2_exit_gate")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._bot = null
	await _wait(0.3)
	await _shot(dir, "e1_menu")
	game._bot = self
	teleport(3, "exit", 180.0)
	await _wait(0.6)
	await _shot(dir, "e2_won")
	get_tree().quit()
