class_name V2Dungeon
extends Node3D
## The generated dungeon in the V2 look: a layout of `DungeonGen` (rooms joined by corridors, a tree from the spawn
## room; 4 m cells) built from the modular kit (v2/scripts/build_kit.py -> assets/models/v2/kit.glb).
##   areas     one per room and per corridor: its pieces merged into one mesh per material (few draw calls, and a
##             mesh takes only 8 lights in the Compatibility renderer), its lights, its render layer
##   collision boxes, made from the layout (not from the meshes): walls, doorway sides and lintels, floors,
##             ceilings, what stands in the rooms. So it exists headless too, and the checks can walk it.
##   doors     on about half the doorways (the generator says which): two leaves that slide into the wall;
##             E opens one (v2_game.gd), and it stays open. A doorway without leaves is always open.
##   paths     `path()`: cell to cell through open doorways, for robots that follow the player
## Rooms are 5.2 m high, corridors 3.4 m, doorways 2.4 x 2.6 m: wide enough for every robot.

const CELL := 4.0
const H := 5.2
const HC := 3.4
const T := 0.3                        # wall thickness, outward from the cell's edge
const DOOR_HALF := 1.2
const DOOR_H := 2.6
const WALLS := ["Wall", "Wall", "Wall", "Wall", "WallScreen", "WallPipes", "WallPipes"]      # a room wall is one of these
# what the generator calls its decor -> [the kit's piece, half its depth (m)]
const DECO := {"crate3": ["Block", 0.29], "barrel_large": ["Tank", 0.5], "barrel": ["Tank", 0.5], "computer": ["Console", 0.3],
	"locker": ["Locker", 0.27], "shelves": ["Locker", 0.27]}
const DECO_BOX := {"Block": Vector3(1.8, 1.15, 0.5), "Tank": Vector3(0.9, 2.7, 0.9), "Console": Vector3(1.4, 1.42, 0.56), "Locker": Vector3(1.1, 2.1, 0.5),
	"Column": Vector3(0.86, 5.2, 0.86)}
const MORE := ["Tank", "Console", "Locker", "Tank", "Block"]      # what else stands along a room's walls
const TANKS := [Color(0.2, 0.62, 0.68), Color(0.25, 0.68, 0.4), Color(0.75, 0.55, 0.16), Color(0.5, 0.36, 0.85), Color(0.7, 0.3, 0.3)]

var gen: DungeonGen
var areas: Array = []                 # {room: bool, id, rect: Rect2 (world x z), node, layer, lights: Array}
var area_of: Dictionary = {}          # cell -> index into areas
var doors: Array = []                 # {a: cell (room), b: cell (corridor), at: Vector3, dir: Vector2i, door: bool, open: bool, leaves, lamps}
var _door_at: Dictionary = {}         # [cell, cell] -> index into doors (both orders)
var _kit: Dictionary = {}             # piece name -> [[Mesh, Transform3D, material name], ...]
var _kit_scene: Node3D
var _headless := false
var _lamps: Dictionary = {}
var _gun_area := -1
var _taken: Dictionary = {}           # room cells that hold something against a wall already


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)


func build(layout: DungeonGen) -> void:
	gen = layout
	_headless = DisplayServer.get_name() == "headless"
	_kit_scene = (load(V2Assets.DIR + "kit.glb") as PackedScene).instantiate()
	for piece in _kit_scene.get_children():
		var parts: Array = []
		for n in piece.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var mat := mi.mesh.surface_get_material(0) if not _headless else null
			parts.append([mi.mesh, mi.transform, mat.resource_name if mat != null else ""])
		_kit[String(piece.name)] = parts
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(gen.seed_value) + 77
	for r in gen.rooms:
		var rect := Rect2(r.rect.position.x * CELL, r.rect.position.y * CELL, r.rect.size.x * CELL, r.rect.size.y * CELL)
		_area(true, r.id, rect, _cells_of(r.rect), rng)
	for co in gen.corridors:
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for c in co.cells:
			lo = lo.min(Vector2(c) * CELL)
			hi = hi.max(Vector2(c) * CELL + Vector2(CELL, CELL))
		_area(false, co.id, Rect2(lo, hi - lo), co.cells, rng)
	_layers()
	for i in areas.size():
		_lights(i)
	for dw in gen.doorways:
		_doorway(dw)
	for d in gen.deco_spawns:
		_deco(d)
	_furnish(rng)
	_kit_scene.queue_free()


func _cells_of(r: Rect2i) -> Array:
	var out: Array = []
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			out.append(Vector2i(x, y))
	return out


## The yaw that turns a piece's +Z (its room side) to face along `into`.
static func _yaw(into: Vector2i) -> float:
	return atan2(float(into.x), float(into.y))


func _area(is_room: bool, id: int, rect: Rect2, cells: Array, rng: RandomNumberGenerator) -> void:
	var node := Node3D.new()
	node.name = ("Room%d" if is_room else "Corridor%d") % id
	add_child(node)
	var index := areas.size()
	areas.append({"room": is_room, "id": id, "rect": rect, "node": node, "layer": 2, "lights": [], "cells": cells})
	var placed: Array = []                                 # [piece name, Transform3D]
	var height := H if is_room else HC
	var along_x := not is_room and cells.size() > 1 and (cells[0] as Vector2i).y == (cells[1] as Vector2i).y
	for c in cells:
		area_of[c] = index
		var at := center(c)
		if is_room:
			placed.append(["Floor", Transform3D(Basis.IDENTITY, at)])
			placed.append(["Ceiling" if posmod(c.x + c.y, 2) == 0 else "CeilingBeams", Transform3D(Basis.IDENTITY, at)])
		else:
			var turn := Basis(Vector3.UP, PI / 2.0) if along_x else Basis.IDENTITY
			placed.append(["CFloor", Transform3D(turn, at)])
			placed.append(["CCeiling", Transform3D(turn, at)])
		for d in DungeonGen.DIRS:
			var n: Vector2i = c + d
			var edge := at + Vector3(d.x, 0, d.y) * (CELL / 2.0)
			var xf := Transform3D(Basis(Vector3.UP, _yaw(-d)), edge)
			if not gen.is_floor(n):
				placed.append([WALLS[rng.randi() % WALLS.size()] if is_room else "CWall", xf])
				_wall_box(node, edge, d, -2.3, 2.3, 0.0, height)
			elif is_room and gen.cells[n].t == DungeonGen.T_CORRIDOR:
				placed.append(["WallDoor", xf])                # a doorway: built from the room's side
				_wall_box(node, edge, d, -2.3, -DOOR_HALF, 0.0, H)
				_wall_box(node, edge, d, DOOR_HALF, 2.3, 0.0, H)
				_wall_box(node, edge, d, -DOOR_HALF, DOOR_HALF, DOOR_H, H)
	# floor and ceiling: one box each
	_solid(node, Vector3(rect.size.x, 1.0, rect.size.y), Vector3(rect.get_center().x, -0.5, rect.get_center().y))
	_solid(node, Vector3(rect.size.x, 0.4, rect.size.y), Vector3(rect.get_center().x, height + 0.2, rect.get_center().y))
	if _headless:
		return
	# the pieces, merged into one mesh per material
	var tools: Dictionary = {}
	for p in placed:
		for part in _kit[p[0]]:
			if not tools.has(part[2]):
				tools[part[2]] = SurfaceTool.new()
			(tools[part[2]] as SurfaceTool).append_from(part[0], 0, (p[1] as Transform3D) * (part[1] as Transform3D))
	var mesh := ArrayMesh.new()
	var mi := MeshInstance3D.new()
	for mat_name in tools:
		(tools[mat_name] as SurfaceTool).commit(mesh)
	mi.mesh = mesh
	var s := 0
	for mat_name in tools:
		mi.set_surface_override_material(s, V2Assets.material(mat_name))
		s += 1
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # (the shell casts none: what stands in it does)
	node.add_child(mi)


func _solid(parent: Node3D, size: Vector3, at: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	parent.add_child(body)
	body.position = at
	body.rotation.y = yaw
	return body


## A box of wall on the edge `edge` of a cell whose outward side is `d`: from x0 to x1 along the edge, y0 to y1 up.
func _wall_box(parent: Node3D, edge: Vector3, d: Vector2i, x0: float, x1: float, y0: float, y1: float) -> void:
	var along := Vector3(-d.y, 0, d.x)
	var out := Vector3(d.x, 0, d.y)
	var mid := edge + along * ((x0 + x1) / 2.0) + out * (T / 2.0) + Vector3(0, (y0 + y1) / 2.0, 0)
	var size := Vector3(absf(x1 - x0), y1 - y0, T) if d.x == 0 else Vector3(T, y1 - y0, absf(x1 - x0))
	_solid(parent, size, mid)


## Render layers: an area's lights reach only its own layer. Two areas get the same layer only if they are far
## enough apart that neither's lights reach the other (9 layers, bits 1..9; bit 10 is the gun's).
func _layers() -> void:
	for i in areas.size():
		var used := {}
		for j in i:
			if (areas[i].rect as Rect2).grow(13.0).intersects(areas[j].rect):
				used[areas[j].layer] = true
		var pick := 0
		for k in 9:
			if not used.has(1 << (k + 1)):
				pick = 1 << (k + 1)
				break
		areas[i].layer = pick if pick != 0 else 1 << (1 + i % 9)
		for n in (areas[i].node as Node3D).find_children("*", "VisualInstance3D", true, false):
			(n as VisualInstance3D).layers = areas[i].layer


func _lights(i: int) -> void:
	var a: Dictionary = areas[i]
	var rect: Rect2 = a.rect
	var spots: Array = []
	if a.room:
		var nx := 2 if rect.size.x < 21.0 else 3
		var ny := 2 if rect.size.y < 21.0 else 3
		if nx * ny > 6:
			ny = 2
		for ix in nx:
			for iy in ny:
				spots.append(Vector3(rect.position.x + rect.size.x * (ix + 0.5) / nx, 4.5, rect.position.y + rect.size.y * (iy + 0.5) / ny))
	else:
		var n := maxi(int(round(maxf(rect.size.x, rect.size.y) / 8.0)), 1)
		for k in n:
			var f := (k + 0.5) / n
			spots.append(Vector3(rect.position.x + rect.size.x * (f if rect.size.x > rect.size.y else 0.5), 2.9,
				rect.position.y + rect.size.y * (f if rect.size.y >= rect.size.x else 0.5)))
	for at in spots:
		var l := OmniLight3D.new()
		l.position = at
		l.light_color = Color(0.97, 0.98, 1.0)
		l.light_energy = (0.3 * clampf(rect.get_area() / (spots.size() * 40.0), 0.8, 1.7)) if a.room else 0.24
		l.omni_range = 12.0 if a.room else 7.5
		l.omni_attenuation = 0.8
		l.light_cull_mask = a.layer
		(a.node as Node3D).add_child(l)
		a.lights.append(l)


func _lamp(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _lamps.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.02, 0.02, 0.02)
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.6
		_lamps[key] = m
	return _lamps[key]


func _box_mesh(parent: Node3D, size: Vector3, at: Vector3, mat: Material, layer: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	mi.layers = layer
	parent.add_child(mi)
	return mi


## A doorway between a room cell and a corridor cell; with leaves and lamps if the generator put a door there.
func _doorway(dw: Dictionary) -> void:
	var a: Vector2i = dw.room_cell
	var b: Vector2i = dw.corr_cell
	var d: Vector2i = b - a
	var edge := center(a) + Vector3(d.x, 0, d.y) * (CELL / 2.0)
	var rec := {"a": a, "b": b, "at": edge, "dir": d, "door": bool(dw.door), "open": not bool(dw.door), "leaves": [], "lamps": []}
	_door_at[[a, b]] = doors.size()
	_door_at[[b, a]] = doors.size()
	doors.append(rec)
	if not rec.door:
		return
	var layer: int = areas[area_of[a]].layer | areas[area_of[b]].layer
	var frame := Node3D.new()                              # +Z toward the room, +X along the wall, in the wall's middle
	frame.transform = Transform3D(Basis(Vector3.UP, _yaw(-d)), edge + Vector3(d.x, 0, d.y) * (T / 2.0))
	add_child(frame)
	for side in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.position = Vector3(side * DOOR_HALF / 2.0, 0.0, 0.0)
		frame.add_child(leaf)
		_box_mesh(leaf, Vector3(DOOR_HALF, DOOR_H - 0.03, 0.07), Vector3(0, DOOR_H / 2.0, 0), V2Assets.material("RArmor"), layer)
		_box_mesh(leaf, Vector3(DOOR_HALF - 0.3, 0.42, 0.08), Vector3(0, 1.7, 0), V2Assets.material("DarkGlass"), layer)
		_box_mesh(leaf, Vector3(DOOR_HALF - 0.1, 0.12, 0.09), Vector3(0, 0.96, 0), V2Assets.material("Hazard"), layer)
		_box_mesh(leaf, Vector3(0.06, DOOR_H - 0.03, 0.09), Vector3(-side * (DOOR_HALF / 2.0 - 0.03), DOOR_H / 2.0, 0), V2Assets.material("DarkSteel"), layer)
		_solid(leaf, Vector3(DOOR_HALF, DOOR_H, 0.2), Vector3(0, DOOR_H / 2.0, 0))
		rec.leaves.append(leaf)
	for z in [-(T / 2.0 + 0.1), T / 2.0 + 0.1]:           # a lamp over the door on each side: amber = shut, green = open
		rec.lamps.append(_box_mesh(frame, Vector3(0.9, 0.08, 0.03), Vector3(0, DOOR_H + 0.35, z), _lamp(Color(1.0, 0.6, 0.15)), layer))


func door_near(p: Vector3, reach: float) -> int:
	var best := -1
	var best_d := reach
	for i in doors.size():
		var d: Dictionary = doors[i]
		if not d.door or d.open:
			continue
		var dist := Vector2(p.x - d.at.x, p.z - d.at.z).length()
		if dist < best_d:
			best_d = dist
			best = i
	return best


func open_door(i: int) -> void:
	var d: Dictionary = doors[i]
	if d.open:
		return
	d.open = true
	V2Sfx.play("door", (d.at as Vector3) + Vector3(0, 1.3, 0))
	# (the leaves go all the way into the doorway's lining: left 4 cm proud of it, the end of a leaf showed, and
	# its two faces in one plane, the armour's and the edge strip's, flickered)
	for k in 2:
		var leaf := d.leaves[k] as Node3D
		var tw := create_tween()
		tw.tween_interval(0.12)
		tw.tween_property(leaf, "position:x", leaf.position.x + (-1.0 if k == 0 else 1.0) * (DOOR_HALF - 0.012), 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for lamp in d.lamps:
		(lamp as MeshInstance3D).material_override = _lamp(Color(0.224, 1.0, 0.533))


## What stands against a room's wall (the generator's decor in the kit's pieces): its node, a box to stop the player.
func _deco(d: Dictionary) -> void:
	var spec: Array = DECO[d.kind]
	var out := Vector3(sin(float(d.yaw)), 0, cos(float(d.yaw)))          # toward the wall (the generator's yaw faces the room)
	var wall := (d.pos as Vector3) + out * (0.5 + float(DungeonGen.DECO_KINDS[d.kind]))
	_taken[cell_of(d.pos)] = true
	_stand(spec[0], wall - out * (0.16 + float(spec[1])), float(d.yaw) + PI, int(d.room))      # (the kit's props face +Z)


## The rooms furnished beyond the generator's one to three things: columns or tanks at the corners of the cells
## inside the bigger rooms (cover; the robots keep to the cells' middles, so they pass between them), and more
## equipment along the walls, on cells that hold nothing yet and are not at a doorway.
func _furnish(rng: RandomNumberGenerator) -> void:
	for l in gen.loot_spawns:
		_taken[cell_of(l.pos)] = true
	for r in gen.rooms:
		var rc := r.rect
		if rc.size.x >= 4 and rc.size.y >= 4:
			var what := "Column" if rng.randf() < 0.55 else "Tank"
			for v in [rc.position + Vector2i(1, 1), Vector2i(rc.end.x - 1, rc.position.y + 1), Vector2i(rc.position.x + 1, rc.end.y - 1), rc.end - Vector2i(1, 1)]:
				var at := Vector3(v.x * CELL, 0, v.y * CELL)
				if r.id == gen.exit_room and at.distance_to(gen.exit_pos) < 3.0:
					continue
				_stand(what, at, 0.0, r.id)
		var spots: Array = []
		for c in _cells_of(rc):
			if _taken.has(c):
				continue
			var near_door := false
			for dc in r.doorway_cells:
				if absi(dc.x - c.x) + absi(dc.y - c.y) <= 1:
					near_door = true
			if near_door or (r.id == gen.exit_room and center(c).distance_to(gen.exit_pos) < CELL * 1.2):
				continue
			for d in DungeonGen.DIRS:
				if not gen.is_floor(c + d):
					spots.append([c, d])
		for k in 1 + (rc.size.x + rc.size.y) / 3:
			if spots.is_empty():
				break
			var pick: Array = spots[rng.randi() % spots.size()]
			spots = spots.filter(func(sp: Array) -> bool: return sp[0] != pick[0])
			var what2: String = MORE[rng.randi() % MORE.size()]
			var out := Vector3(pick[1].x, 0, pick[1].y)
			var along := Vector3(-pick[1].y, 0, pick[1].x) * rng.randf_range(-0.8, 0.8)
			var depth: float = (DECO_BOX[what2] as Vector3).z / 2.0
			_stand(what2, center(pick[0]) + out * (CELL / 2.0 - 0.16 - depth) + along, atan2(-out.x, -out.z), r.id)


## One of the kit's props at `at`, turned by `yaw`: its node, a box to stop the player and rounds.
func _stand(what: String, at: Vector3, yaw: float, room_id: int) -> void:
	var area: Dictionary = areas[area_of[gen.rooms[room_id].rect.position]]
	_solid(area.node, DECO_BOX[what], at + Vector3(0, (DECO_BOX[what] as Vector3).y / 2.0, 0), yaw)
	if _headless:
		return
	var node := (_kit_scene.find_child(what, true, false) as Node3D).duplicate() as Node3D
	(area.node as Node3D).add_child(node)
	node.position = at
	node.rotation.y = yaw
	V2Assets.apply(node)
	if what == "Tank":                                     # each room's tanks hold a liquid of its own colour
		var color: Color = TANKS[room_id % TANKS.size()]
		var liquid := (V2Assets.material("TankLiquid") as StandardMaterial3D).duplicate() as StandardMaterial3D
		liquid.albedo_color = Color(color.r, color.g, color.b, 0.45)
		liquid.emission = color * 0.8
		(node.find_child("Tank_Liquid", true, false) as MeshInstance3D).set_surface_override_material(0, liquid)
	for n in node.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = area.layer


# ---------------------------------------------------------------------------------------------- questions
func area_at(p: Vector3) -> int:
	return area_of.get(cell_of(p), -1)


func room_id_at(p: Vector3) -> int:
	var i := area_at(p)
	return int(areas[i].id) if i >= 0 and areas[i].room else -1


## May something pass from cell a to its neighbour b? (both floor, and no shut door between them)
func passable(a: Vector2i, b: Vector2i) -> bool:
	if not area_of.has(a) or not area_of.has(b):
		return false
	if area_of[a] == area_of[b]:
		return true
	if not _door_at.has([a, b]):
		return false
	return bool(doors[_door_at[[a, b]]].open)


## Cells from a to b through open doorways (both included), or [] if there is no way.
func path(a: Vector2i, b: Vector2i) -> Array:
	if not area_of.has(a) or not area_of.has(b):
		return []
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
			if not prev.has(n) and passable(c, n):
				prev[n] = c
				queue.append(n)
	if not prev.has(b):
		return []
	var out: Array = [b]
	while out[0] != a:
		out.push_front(prev[out[0]])
	return out


## Is cell `c` in a corridor, or the room cell just inside a doorway? (a drone flies low there)
func low_cell(c: Vector2i) -> bool:
	if not area_of.has(c):
		return false
	if not areas[area_of[c]].room:
		return true
	for d in DungeonGen.DIRS:
		if _door_at.has([c, c + d]):
			return true
	return false


## Where a robot may be in area i: its rectangle less a margin (what stands against the walls, its own width).
func arena(i: int, margin: float) -> Rect2:
	var r: Rect2 = areas[i].rect
	var m := Vector2(minf(margin, r.size.x / 2.0 - 0.3), minf(margin, r.size.y / 2.0 - 0.3))
	return Rect2(r.position + m, r.size - m * 2.0)


## Every frame: only what is near the player is drawn; the lights of the area they stand in reach the gun too.
func update(player_at: Vector3, gun_layer: int) -> void:
	var here := area_at(player_at)
	for i in areas.size():
		var a: Dictionary = areas[i]
		var r: Rect2 = a.rect
		(a.node as Node3D).visible = i == here or r.grow(34.0).has_point(Vector2(player_at.x, player_at.z))
	if here != _gun_area and here >= 0:
		_gun_area = here
		for i in areas.size():
			for l in areas[i].lights:
				(l as Light3D).light_cull_mask = int(areas[i].layer) | (gun_layer if i == here else 0)
