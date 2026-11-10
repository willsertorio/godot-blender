class_name DungeonGen
extends RefCounted
## Pure-data dungeon generator. Same seed + difficulty -> identical layout.
##
## Space is a grid of CELL x CELL metre cells on the XZ plane. Cell (x, y) covers
## world X in [x*CELL, x*CELL+CELL] and world Z in [y*CELL, y*CELL+CELL].
## Rooms are rectangles of cells; corridors are straight 1-cell-wide runs joining a
## parent room to a child room, so the room graph is a tree rooted at the spawn room.
## Walls exist on every edge between a floor cell and an empty cell; a doorframe sits
## on every edge between a room cell and a corridor cell.

const CELL := 4.0
const WALL_H := 4.0
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const T_ROOM := 1
const T_CORRIDOR := 2

## Enemy type ids (match scripts/enemies/*). Weights/score live in combat code.
const ENEMY_TYPES := ["turret", "brawler", "pursuer"]
const LOOT_PAYOFFS := ["kit", "ammo", "health"]


class Room:
	var id: int
	var rect: Rect2i
	var parent: int = -1
	var depth: int = 0
	var doorway_cells: Array[Vector2i] = []  # room cells that touch a corridor

	func center() -> Vector3:
		var c := Vector2(rect.position) + Vector2(rect.size) * 0.5
		return Vector3(c.x * CELL, 0.0, c.y * CELL)

	func has_cell(c: Vector2i) -> bool:
		return rect.has_point(c)


class Corridor:
	var id: int
	var a: int  # parent room id
	var b: int  # child room id
	var dir: Vector2i  # from a towards b
	var cells: Array[Vector2i] = []


var seed_value: int
var difficulty: int
var rng := RandomNumberGenerator.new()

var rooms: Array[Room] = []
var corridors: Array[Corridor] = []
## Vector2i -> {"t": T_ROOM|T_CORRIDOR, "id": room or corridor id}
var cells: Dictionary = {}
## Each: {"room_cell": Vector2i, "corr_cell": Vector2i, "corridor": int, "door": bool}
var doorways: Array = []
## Grid vertices (world = vertex * CELL) holding a pillar.
var pillars: Array[Vector2i] = []
var spawn_room := 0
var exit_room := -1
var player_spawn := Vector3.ZERO
var player_yaw := 0.0
var exit_pos := Vector3.ZERO
## Each: {"type": String, "pos": Vector3, "room": int}
var enemy_spawns: Array = []
## Each: {"pos": Vector3, "yaw": float, "room": int, "payoff": String}
var loot_spawns: Array = []


static func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)


static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func yaw_facing(d: Vector3) -> float:
	## Godot cameras look down -Z; this returns rotation.y that looks along d.
	return atan2(-d.x, -d.z)


func is_floor(c: Vector2i) -> bool:
	return cells.has(c)


func room_at(c: Vector2i) -> int:
	var e = cells.get(c)
	if e != null and e.t == T_ROOM:
		return e.id
	return -1


func generate(p_seed: int, p_difficulty: int = 0) -> DungeonGen:
	seed_value = p_seed
	difficulty = p_difficulty
	rng.seed = hash(p_seed)
	var target := rng.randi_range(8, 12)

	_add_room(Rect2i(0, 0, 4, 4), -1)
	var attempts := 0
	while rooms.size() < target and attempts < 4000:
		attempts += 1
		_try_grow()
	# Extremely unlikely, but never return an invalid layout: reseed deterministically.
	if rooms.size() < 8:
		var again := DungeonGen.new()
		return again.generate(p_seed * 7919 + 1, p_difficulty)

	_compute_depths()
	_place_pillars()
	_place_doors()
	_place_player()
	_place_exit()
	_place_enemies()
	_place_loot()
	return self


# --- layout ---------------------------------------------------------------

func _add_room(r: Rect2i, parent: int) -> Room:
	var room := Room.new()
	room.id = rooms.size()
	room.rect = r
	room.parent = parent
	rooms.append(room)
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			cells[Vector2i(x, y)] = {"t": T_ROOM, "id": room.id}
	return room


func _try_grow() -> void:
	var parent: Room = rooms[rng.randi() % rooms.size()]
	var dir: Vector2i = DIRS[rng.randi() % 4]
	var w := rng.randi_range(3, 6)
	var h := rng.randi_range(3, 6)
	var length := rng.randi_range(2, 4)
	var pr := parent.rect

	var corr: Array[Vector2i] = []
	var new_rect: Rect2i
	var parent_cell: Vector2i
	if dir.x != 0:
		var lat := rng.randi_range(pr.position.y + 1, pr.end.y - 2)
		var sx := pr.end.x if dir.x > 0 else pr.position.x - 1
		parent_cell = Vector2i(sx - dir.x, lat)
		for i in length:
			corr.append(Vector2i(sx + i * dir.x, lat))
		var ex := sx + (length - 1) * dir.x
		var nx := ex + 1 if dir.x > 0 else ex - w
		var ny := rng.randi_range(lat - h + 2, lat - 1)
		new_rect = Rect2i(nx, ny, w, h)
	else:
		var lat := rng.randi_range(pr.position.x + 1, pr.end.x - 2)
		var sy := pr.end.y if dir.y > 0 else pr.position.y - 1
		parent_cell = Vector2i(lat, sy - dir.y)
		for i in length:
			corr.append(Vector2i(lat, sy + i * dir.y))
		var ey := sy + (length - 1) * dir.y
		var ny := ey + 1 if dir.y > 0 else ey - h
		var nx := rng.randi_range(lat - w + 2, lat - 1)
		new_rect = Rect2i(nx, ny, w, h)

	# New room plus a one-cell margin must be empty, so rooms never touch.
	var grown := new_rect.grow(1)
	for x in range(grown.position.x, grown.end.x):
		for y in range(grown.position.y, grown.end.y):
			if cells.has(Vector2i(x, y)):
				return
	# Corridor cells must be empty and touch nothing except their own run,
	# the parent room (first cell only) and the new room (last cell only).
	for i in corr.size():
		var c := corr[i]
		if cells.has(c):
			return
		for d in DIRS:
			var n := c + d
			if i == 0 and n == parent_cell:
				continue
			if corr.has(n) or new_rect.has_point(n):
				continue
			if cells.has(n):
				return

	var room := _add_room(new_rect, parent.id)
	var co := Corridor.new()
	co.id = corridors.size()
	co.a = parent.id
	co.b = room.id
	co.dir = dir
	co.cells = corr
	corridors.append(co)
	for c in corr:
		cells[c] = {"t": T_CORRIDOR, "id": co.id}
	var child_cell := corr[corr.size() - 1] + dir
	doorways.append({"room_cell": parent_cell, "corr_cell": corr[0], "corridor": co.id, "door": false})
	doorways.append({"room_cell": child_cell, "corr_cell": corr[corr.size() - 1], "corridor": co.id, "door": false})
	parent.doorway_cells.append(parent_cell)
	room.doorway_cells.append(child_cell)


func _compute_depths() -> void:
	# The room graph is a tree; depth = corridors walked from spawn.
	for r in rooms:
		var d := 0
		var p := r.parent
		while p != -1:
			d += 1
			p = rooms[p].parent
		r.depth = d


func _place_pillars() -> void:
	for r in rooms:
		if r.id == spawn_room or r.rect.size.x < 5 or r.rect.size.y < 5:
			continue
		var p := r.rect.position
		var e := r.rect.end
		for v in [Vector2i(p.x + 1, p.y + 1), Vector2i(e.x - 1, p.y + 1),
				Vector2i(p.x + 1, e.y - 1), Vector2i(e.x - 1, e.y - 1)]:
			pillars.append(v)


func _place_doors() -> void:
	# A door sits at one end of roughly half the corridors (the end that enters
	# the child room, i.e. deeper into the dungeon). The first corridor out of
	# spawn always gets one so every run shows a door early.
	for co in corridors:
		var chance := 1.0 if co.a == spawn_room and co.id == _first_spawn_corridor() else 0.5
		if rng.randf() < chance:
			doorways[co.id * 2 + 1].door = true


func _first_spawn_corridor() -> int:
	for co in corridors:
		if co.a == spawn_room:
			return co.id
	return -1


func _place_player() -> void:
	var r := rooms[spawn_room]
	player_spawn = r.center()
	var target := player_spawn + Vector3(0, 0, -1)
	if r.doorway_cells.size() > 0:
		target = cell_center(r.doorway_cells[0])
	player_yaw = yaw_facing(target - player_spawn)


func _place_exit() -> void:
	var best := -1
	for r in rooms:
		if r.id == spawn_room:
			continue
		if best == -1 or r.depth > rooms[best].depth or (r.depth == rooms[best].depth and r.id > best):
			best = r.id
	exit_room = best
	exit_pos = rooms[best].center()


## Free cell centres in a room for spawning things: not a doorway cell, not the
## exit/spawn centre, not already used.
func _free_cells(r: Room, used: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(r.rect.position.x, r.rect.end.x):
		for y in range(r.rect.position.y, r.rect.end.y):
			var c := Vector2i(x, y)
			if used.has(c) or r.doorway_cells.has(c):
				continue
			var cc := cell_center(c)
			if r.id == exit_room and cc.distance_to(exit_pos) < CELL * 1.2:
				continue
			out.append(c)
	return out


var _used: Dictionary = {}


func _place_enemies() -> void:
	for r in rooms:
		if r.id == spawn_room:
			continue
		var area := r.rect.size.x * r.rect.size.y
		var n := 1 + int(area >= 16) + int(area >= 25) + rng.randi_range(0, 1)
		n += difficulty  # more hostiles per completed mission
		n = mini(n, 8)
		var free := _free_cells(r, _used)
		for i in mini(n, free.size()):
			var c: Vector2i = free.pop_at(rng.randi() % free.size())
			_used[c] = true
			var t: String = ENEMY_TYPES[_weighted([3, 4, 3])]
			var j := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
			enemy_spawns.append({"type": t, "pos": cell_center(c) + j, "room": r.id})


func _place_loot() -> void:
	# Kits thin out with difficulty: weight 4 at d0, falling to 1.
	var kit_w := maxi(1, 4 - difficulty)
	for r in rooms:
		var n := rng.randi_range(0, 2) if r.id != spawn_room else 1
		var free := _free_cells(r, _used)
		for i in mini(n, free.size()):
			var c: Vector2i = free.pop_at(rng.randi() % free.size())
			_used[c] = true
			var payoff: String = LOOT_PAYOFFS[_weighted([kit_w, 4, 3])]
			var j := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
			loot_spawns.append({"pos": cell_center(c) + j, "yaw": rng.randf() * TAU, "room": r.id, "payoff": payoff})


func _weighted(weights: Array) -> int:
	var total := 0
	for w in weights:
		total += w
	var roll := rng.randi_range(1, total)
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0:
			return i
	return weights.size() - 1


## Stable fingerprint of the layout (cell set), used to verify runs don't repeat.
func layout_hash() -> int:
	var keys := cells.keys()
	keys.sort()
	return hash(str(keys))
