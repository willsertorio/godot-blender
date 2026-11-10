extends SceneTree
## Generator check. Builds many seeds headless and verifies:
##  - room count is 8..12
##  - every room is reachable from spawn by walking floor cells (doors count as
##    passable since they can be opened), so the exit is reachable
##  - the exit portal is in the final room (the deepest room from spawn) and inside it
##  - floor areas only touch through doorways (no accidental wall gaps)
##  - nothing spawns inside walls: player, portal, enemies and loot are tested
##    against the built collision with physics overlap queries
##  - no two seeds produce the same layout
##
## Usage: godot --headless -s tools/gen_check.gd -- [--count=300] [--start=1]

var failures := 0
var floor_rid: RID


func _initialize() -> void:
	_run()


func _run() -> void:
	var count := 300
	var start := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--count="):
			count = int(a.split("=")[1])
		elif a.begins_with("--start="):
			start = int(a.split("=")[1])
	var hashes := {}
	var room_hist := {}
	var t0 := Time.get_ticks_msec()
	for s in range(start, start + count):
		var difficulty := s % 4
		var g := DungeonGen.new().generate(s, difficulty)
		_check_data(s, g)
		var h := g.layout_hash()
		if hashes.has(h):
			_fail(s, "layout identical to seed %d" % hashes[h])
		hashes[h] = s
		room_hist[g.rooms.size()] = room_hist.get(g.rooms.size(), 0) + 1
		await _check_physics(s, g)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("gen_check: %d seeds in %.1fs, room counts %s, %d unique layouts" % [count, secs, room_hist, hashes.size()])
	if failures == 0:
		print("gen_check: PASS")
		quit(0)
	else:
		print("gen_check: FAIL (%d problems)" % failures)
		quit(1)


func _fail(s: int, msg: String) -> void:
	failures += 1
	if failures <= 40:
		printerr("seed %d: %s" % [s, msg])


func _check_data(s: int, g: DungeonGen) -> void:
	var n := g.rooms.size()
	if n < 8 or n > 12:
		_fail(s, "room count %d" % n)

	# Reachability: flood fill over floor cells from the spawn cell.
	var start := DungeonGen.world_to_cell(g.player_spawn)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while queue.size() > 0:
		var c: Vector2i = queue.pop_back()
		for d in DungeonGen.DIRS:
			var nb: Vector2i = c + d
			if g.is_floor(nb) and not seen.has(nb):
				seen[nb] = true
				queue.append(nb)
	for r in g.rooms:
		if not seen.has(r.rect.position):
			_fail(s, "room %d unreachable" % r.id)
	if seen.size() != g.cells.size():
		_fail(s, "%d floor cells unreachable" % (g.cells.size() - seen.size()))

	# Exit in the final room.
	var deepest := 0
	for r in g.rooms:
		deepest = maxi(deepest, r.depth)
	if g.exit_room < 0 or g.exit_room == g.spawn_room:
		_fail(s, "no exit room")
	elif g.rooms[g.exit_room].depth != deepest:
		_fail(s, "exit room depth %d, deepest is %d" % [g.rooms[g.exit_room].depth, deepest])
	if g.room_at(DungeonGen.world_to_cell(g.exit_pos)) != g.exit_room:
		_fail(s, "exit portal not inside the exit room")

	# Areas touch only through doorways.
	var doorway_pairs := {}
	for dw in g.doorways:
		doorway_pairs[[dw.room_cell, dw.corr_cell]] = true
		doorway_pairs[[dw.corr_cell, dw.room_cell]] = true
	for c in g.cells:
		for d in DungeonGen.DIRS:
			var nb: Vector2i = c + d
			if not g.is_floor(nb):
				continue
			var a = g.cells[c]
			var b = g.cells[nb]
			if a.t == b.t and a.id == b.id:
				continue
			if not doorway_pairs.has([c, nb]):
				_fail(s, "areas touch without a doorway at %s|%s" % [c, nb])

	# Everything spawns on a floor cell of the room it claims.
	for e in g.enemy_spawns:
		if g.room_at(DungeonGen.world_to_cell(e.pos)) != e.room:
			_fail(s, "enemy outside its room at %s" % e.pos)
	for l in g.loot_spawns:
		if g.room_at(DungeonGen.world_to_cell(l.pos)) != l.room:
			_fail(s, "loot outside its room at %s" % l.pos)


func _check_physics(s: int, g: DungeonGen) -> void:
	var world := DungeonBuilder.new().build(g)
	root.add_child(world)
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	floor_rid = (world.get_node("WorldCollision/FloorCollision") as StaticBody3D).get_rid()

	# Self-test: a probe on a known wall edge must register, or the overlap test is blind.
	var probe_ok := false
	for c in g.cells:
		for d in DungeonGen.DIRS:
			if not g.is_floor(c + d) and not probe_ok:
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = _sphere(0.2)
				q.transform = DungeonBuilder.edge_transform(c, d) * Transform3D(Basis(), Vector3(0, 2, 0.15))
				q.collision_mask = Layers.WORLD
				q.exclude = [floor_rid]
				probe_ok = space.intersect_shape(q, 1).size() > 0
				if not probe_ok:
					_fail(s, "self-test: wall probe found nothing; overlap checks are not working")
				probe_ok = true
		if probe_ok:
			break

	_overlap(s, space, "player",g.player_spawn + Vector3.UP * 0.9, _capsule(0.4, 1.8))
	_overlap(s, space, "portal", g.exit_pos + Vector3.UP * 1.25, _sphere(1.0))
	for e in g.enemy_spawns:
		_overlap(s, space, "enemy " + e.type, e.pos + Vector3.UP * 1.0, _sphere(0.7))
	for l in g.loot_spawns:
		_overlap(s, space, "container", l.pos + Vector3.UP * 0.5, _sphere(0.75))
	world.queue_free()
	await process_frame


func _overlap(s: int, space: PhysicsDirectSpaceState3D, what: String, pos: Vector3, shape: Shape3D) -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = Layers.WORLD
	q.exclude = [floor_rid]
	var hits := space.intersect_shape(q, 4)
	for h in hits:
		_fail(s, "%s spawns inside geometry (%s) at %s" % [what, h.collider.name, pos])
		return


func _sphere(r: float) -> SphereShape3D:
	var sh := SphereShape3D.new()
	sh.radius = r
	return sh


func _capsule(r: float, h: float) -> CapsuleShape3D:
	var sh := CapsuleShape3D.new()
	sh.radius = r
	sh.height = h
	return sh
