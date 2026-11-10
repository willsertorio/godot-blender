extends SceneTree
## Headless playthrough bot. For each seed it starts a real run and drives the
## Player with the same input actions a person uses (move_forward + yaw, E to
## interact) along the cell path from spawn to the exit portal. Passes when the
## run ends in success. Before opening the first door it also walks into it and
## verifies the closed door stops the player.
##
## Usage: godot --headless -s tools/playthrough.gd -- [--count=10] [--start=1]

const MAX_SECONDS := 240.0

var failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var count := 10
	var start := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--count="):
			count = int(a.split("=")[1])
		elif a.begins_with("--start="):
			start = int(a.split("=")[1])
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for s in range(start, start + count):
		main.base_seed = s
		main.run_index = 0
		main.difficulty = 0
		main.start_run()
		var ok: bool = await _drive(main, s)
		print("seed %d: %s (%d rooms, visited %d)" % [s, "PASS" if ok else "FAIL", main.layout.rooms.size(), main.visited.size()])
		if not ok:
			failures += 1
	print("playthrough: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)


func _path(g: DungeonGen) -> Array[Vector2i]:
	var start := DungeonGen.world_to_cell(g.player_spawn)
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


func _drive(main, s: int) -> bool:
	var g: DungeonGen = main.layout
	var p: Player = main.player
	await physics_frame
	var path := _path(g)
	var t := 0.0
	var tested_block := false
	var i := 0
	while main.state == "playing" and t < MAX_SECONDS:
		if i >= path.size():
			# Last cell reached; step onto the portal itself.
			_steer(p, g.exit_pos)
		else:
			var wp := DungeonGen.cell_center(path[i])
			if Vector2(wp.x - p.global_position.x, wp.z - p.global_position.z).length() < 0.6:
				i += 1
				continue
			var door := _closed_door_near(main, p)
			if door:
				if not tested_block:
					tested_block = true
					if not await _check_blocks(p, door):
						printerr("seed %d: closed door did not block the player" % s)
						_release()
						return false
				_press_interact()
			_steer(p, wp)
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	_release()
	if main.state != "ended":
		printerr("seed %d: did not reach the exit (stuck near %s, waypoint %d/%d)" % [s, p.global_position, i, path.size()])
		return false
	return true


func _steer(p: Player, target: Vector3) -> void:
	var d := target - p.global_position
	d.y = 0
	p.rotation.y = DungeonGen.yaw_facing(d)
	Input.action_press("move_forward")


func _release() -> void:
	Input.action_release("move_forward")


func _closed_door_near(main, p: Player) -> Door:
	for door: Door in main.world.get_node("Doors").get_children():
		if door.is_open:
			continue
		var dp := door.global_position
		if Vector2(dp.x - p.global_position.x, dp.z - p.global_position.z).length() < 2.2:
			return door
	return null


func _check_blocks(p: Player, door: Door) -> bool:
	## Push straight into the closed door for a second; the player must not pass
	## through its plane.
	var n := door.global_transform.basis.z  # points from the room side to the corridor side
	var side := signf((p.global_position - door.global_position).dot(n))
	for k in 60:
		_steer(p, door.global_position)
		await physics_frame
	var after := signf((p.global_position - door.global_position).dot(n))
	return after == side


func _press_interact() -> void:
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = "interact"
	up.pressed = false
	Input.parse_input_event(up)
