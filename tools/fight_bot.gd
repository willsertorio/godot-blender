extends SceneTree
## Balance bot: plays full runs with enemies on and the player mortal, using the real
## input actions. Walks the cell path to the exit, detours to open crates in rooms it
## passes, fights any hostile it can see (reaction delay + aim error, rifle when it has
## ammo, pistol otherwise, reloads in lulls), spends a kit below 45 health.
## It never uses cover, so it is a pessimistic stand-in for a careful player.
##
## Usage: godot --headless -s tools/fight_bot.gd -- [--count=10] [--start=1] [--difficulty=0]

const MAX_SECONDS := 420.0
const REACTION := 0.45
const AIM_ERROR := 0.035

var main
var p: Player
var stats := []


func _initialize() -> void:
	_run()


func _run() -> void:
	var count := 10
	var start := 1
	var diff := 0
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			match kv[0]:
				"count": count = int(kv[1])
				"start": start = int(kv[1])
				"difficulty": diff = int(kv[1])
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var wins := 0
	for s in range(start, start + count):
		main.base_seed = s
		main.run_index = 0
		main.difficulty = diff
		main.enemies_enabled = OS.get_environment("FB_NOENEMY") == ""
		main.start_run()
		p = main.player
		var r: Dictionary = await _play()
		r.seed = s
		stats.append(r)
		if r.win:
			wins += 1
		print("seed %d d%d: %s  hp=%d kills=%d/%d crates=%d kits_used=%d dmg_taken=%d time=%ds" % [
			s, diff, "WIN " if r.win else "LOSS", r.hp, r.kills, r.enemies, r.crates, r.kits_used, r.taken, r.time])
	print("fight_bot d%d: %d/%d wins" % [diff, wins, count])
	quit()


func _press(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _path(g: DungeonGen) -> Array[Vector2i]:
	var start := DungeonGen.world_to_cell(p.global_position)
	var goal := DungeonGen.world_to_cell(g.exit_pos)
	var prev := {start: start}
	var q: Array[Vector2i] = [start]
	while q.size() > 0:
		var c: Vector2i = q.pop_front()
		if c == goal:
			break
		for d in DungeonGen.DIRS:
			var n: Vector2i = c + d
			if g.is_floor(n) and not prev.has(n):
				prev[n] = c
				q.append(n)
	var path: Array[Vector2i] = []
	var c := goal
	while c != start:
		path.push_front(c)
		c = prev[c]
	return path


func _play() -> Dictionary:
	var g: DungeonGen = main.layout
	await physics_frame
	var enemies_total: int = get_nodes_in_group("hostiles").size()
	var path := _path(g)
	var i := 0
	var t := 0.0
	var seen_t := 0.0
	var target: Enemy = null
	var crate_goal: LootCrate = null
	var crate_t := 0.0
	var skipped := {}
	var crates_opened := 0
	var kits_used := 0
	var taken := 0.0
	var fire_toggle := false
	var hp_prev := p.health
	# Lambdas capture locals by value, so count through a shared dictionary.
	var n := {"kits": 0, "crates": 0}
	p.kit_used.connect(func(): n.kits += 1)
	for c in get_nodes_in_group("crates"):
		c.opened.connect(func(_pay): n.crates += 1)
	while main.state == "playing" and t < MAX_SECONDS:
		await physics_frame
		t += 1.0 / 60.0
		if p.health < hp_prev:
			taken += hp_prev - p.health
		hp_prev = p.health
		var w: WeaponHolder = p.weapons

		if p.health < 45.0 and p.kits > 0:
			_tap("use_kit")

		# Pick the nearest visible hostile.
		var best: Enemy = null
		var best_d := 30.0
		for e in get_nodes_in_group("hostiles"):
			if e.dead:
				continue
			var d: float = e.global_position.distance_to(p.global_position)
			if d < best_d and e.has_los():
				best = e
				best_d = d
		# Never compare against a possibly freed reference: freed objects can equal null.
		if target == null or not is_instance_valid(target) or best == null or best != target:
			seen_t = 0.0 if best != null and (target == null or not is_instance_valid(target) or best != target) else seen_t
			target = best
		if target != null and is_instance_valid(target):
			seen_t += 1.0 / 60.0
			_press("move_forward", false)
			if seen_t < REACTION:
				continue
			var want := "rifle" if (w.mag > 0 or w.reserve > 0) else "pistol"
			if w.current != want:
				_tap("weapon_2" if want == "rifle" else "weapon_1")
			if w.current == "rifle" and w.mag == 0 and w.reserve > 0 and w.reloading <= 0.0:
				_tap("reload")
			var aim := target.eye_position() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * AIM_ERROR * best_d
			p.look_at_point(aim)
			if w.current == "rifle":
				_press("fire", true)
			else:
				fire_toggle = not fire_toggle
				_press("fire", fire_toggle)
			continue
		_press("fire", false)
		if w.current == "rifle" and w.mag < 20 and w.reserve > 0 and w.reloading <= 0.0:
			_tap("reload")

		# Detour to a closed crate in the current room.
		var room := g.room_at(DungeonGen.world_to_cell(p.global_position))
		if crate_goal == null and room >= 0:
			for c: LootCrate in get_nodes_in_group("crates"):
				if not c.is_open and not skipped.has(c) and g.room_at(DungeonGen.world_to_cell(c.global_position)) == room:
					crate_goal = c
					skipped[c] = true
					break
		if crate_goal and (not is_instance_valid(crate_goal) or crate_goal.is_open or crate_t > 6.0):
			crate_goal = null  # opened, or unreachable: give up and carry on
			crate_t = 0.0
			path = _path(g)
			i = 0
		if crate_goal:
			crate_t += 1.0 / 60.0
			var front := crate_goal.global_position - crate_goal.global_transform.basis.z * 1.2
			if Vector2(front.x - p.global_position.x, front.z - p.global_position.z).length() < 0.5:
				_tap("interact")
				continue
			_steer(front)
			continue

		if i >= path.size():
			_steer(g.exit_pos)
			continue
		var wp := DungeonGen.cell_center(path[i])
		if Vector2(wp.x - p.global_position.x, wp.z - p.global_position.z).length() < 0.6:
			i += 1
			continue
		for door: Door in main.world.get_node("Doors").get_children():
			if not door.is_open and door.global_position.distance_to(p.global_position) < 2.3:
				_tap("interact")
		_steer(wp)
	_press("move_forward", false)
	_press("fire", false)
	return {"win": main.state == "ended" and p.alive, "hp": p.health, "kills": main.kills, "enemies": enemies_total,
		"crates": n.crates, "kits_used": n.kits, "taken": taken, "time": t}


func _steer(target: Vector3) -> void:
	var d := target - p.global_position
	d.y = 0
	p.rotation.y = DungeonGen.yaw_facing(d)
	p.head.rotation.x = 0.0
	_press("move_forward", true)
