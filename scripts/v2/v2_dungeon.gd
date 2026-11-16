class_name V2Dungeon
extends Node3D
## The generated dungeon in the V2 look: a layout of `DungeonGen` (rooms joined by corridors, a tree from the spawn
## room; 4 m cells) built from the environment set (v2/scripts/export_set.py -> assets/models/v2/set.glb).
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
# A room's theme: how its wall panels are dealt (plain / with a display / with services), how often a ceiling cell
# carries services, what stands at the inner corners of its cells (cover: the robots keep to the cells' middles and
# pass between) and what stands along its walls. All pieces of assets/models/v2/set.glb (v2/scripts/set_*.py).
const THEMES := {
	"lab": {"walls": ["wall_plain", "wall_plain", "wall_plain", "wall_plain", "wall_screen", "wall_screen", "wall_service"], "services": 0.15,
		"stand": ["tank", "tank", "column_tall", "barrier"], "along": ["console", "console", "locker", "charging_dock", "shelving", "shelving"],
		"small": ["drum", "crate"], "accent": Vector3(0.05, 0.4, 0.46), "light": Color(0.93, 0.98, 1.0)},
	"storage": {"walls": ["wall_plain", "wall_plain", "wall_plain", "wall_plain", "wall_plain", "wall_service"], "services": 0.1,
		"stand": ["crate_stack", "crate_stack", "drum_stack", "barrier", "column_tall"], "along": ["shelving", "shelving", "crate_stack", "drum_stack", "locker", "crate", "drum"],
		"small": ["crate", "crate", "drum"], "accent": Vector3(0.62, 0.36, 0.03), "light": Color(1.0, 0.975, 0.93)},
	"server": {"walls": ["wall_plain", "wall_plain", "wall_plain", "wall_plain", "wall_screen", "wall_screen", "wall_screen", "wall_service"], "services": 0.35,
		"stand": ["server_rack", "server_rack", "column_tall"], "along": ["server_rack", "server_rack", "server_rack", "console", "locker", "charging_dock"],
		"small": ["crate"], "accent": Vector3(0.06, 0.16, 0.6), "light": Color(0.9, 0.95, 1.0)},
	"power": {"walls": ["wall_plain", "wall_plain", "wall_plain", "wall_plain", "wall_plain", "wall_service", "wall_service"], "services": 0.35,
		"stand": ["power_core", "power_core", "drum_stack", "column_tall"], "along": ["pipe_riser", "pipe_riser", "charging_dock", "locker", "drum", "drum_stack"],
		"small": ["drum", "drum", "crate"], "accent": Vector3(0.6, 0.1, 0.03), "light": Color(1.0, 0.96, 0.9)},
	"workshop": {"walls": ["wall_plain", "wall_plain", "wall_plain", "wall_plain", "wall_plain", "wall_service", "wall_screen"], "services": 0.2,
		"stand": ["barrier", "crate_stack", "barrier", "column_tall", "drum"], "along": ["workbench", "workbench", "shelving", "charging_dock", "locker", "crate"],
		"small": ["crate", "drum"], "accent": Vector3(0.2, 0.42, 0.1), "light": Color(1.0, 0.985, 0.95)},
}
const CORRIDORS := ["corridor", "corridor_b", "corridor_c"]
# What stands in rooms: the box that stops the player and rounds [width, height, depth], where its middle is from
# the piece's origin (the piece's frame: +z toward the room), and how far the piece reaches behind its origin
# (toward the wall it stands against).
const DECO_BOX := {
	"crate": [Vector3(1.08, 0.62, 0.66), Vector3.ZERO, 0.34], "crate_stack": [Vector3(2.14, 1.26, 0.7), Vector3.ZERO, 0.36],
	"drum": [Vector3(0.66, 0.92, 0.66), Vector3.ZERO, 0.36], "drum_stack": [Vector3(1.84, 1.86, 1.3), Vector3(0.21, 0, 0.065), 0.6],
	"barrier": [Vector3(1.94, 1.25, 0.5), Vector3.ZERO, 0.46], "tank": [Vector3(1.3, 2.3, 1.5), Vector3(0, 0, -0.1), 0.96],
	"server_rack": [Vector3(1.06, 2.15, 1.16), Vector3(0, 0, -0.02), 0.62], "power_core": [Vector3(1.4, 2.2, 1.4), Vector3.ZERO, 0.75],
	"console": [Vector3(1.34, 1.5, 0.94), Vector3(0, 0, 0.06), 0.48], "locker": [Vector3(1.2, 2.15, 0.98), Vector3(0, 0, -0.02), 0.62],
	"shelving": [Vector3(2.16, 2.1, 0.72), Vector3.ZERO, 0.36], "workbench": [Vector3(2.32, 1.0, 1.0), Vector3(0, 0, -0.02), 0.68],
	"charging_dock": [Vector3(1.4, 1.95, 1.1), Vector3(0, 0, -0.1), 0.72], "pipe_riser": [Vector3(0.5, 2.74, 0.6), Vector3(0, 0, -0.1), 0.42],
	"column_tall": [Vector3(0.92, 5.2, 0.92), Vector3.ZERO, 0.76],
}
const FILL := 0.7                     # of a room's free wall cells, this share gets something standing there
const FACE := 0.045                   # a wall panel's fields stand this far in front of its origin: the panels are set back by it,
                                      # so that the fields' face is the wall's plane (where rounds strike and leave their marks)
const SEEN := 28.0                    # areas further than this from the player are not drawn
const FLOOR_TOP := 0.068              # a floor tile's fields above its origin; the corridor section's floor plates: 0.012
const CEIL_FACE := 0.052              # a ceiling panel's plates below its origin
const LEAF_SLIDE := {"door_leaf_l": -1.66, "door_leaf_r": 0.8}       # how far each leaf goes into the wall
const TANKS := [Color(0.2, 0.62, 0.68), Color(0.25, 0.68, 0.4), Color(0.75, 0.55, 0.16), Color(0.5, 0.36, 0.85), Color(0.7, 0.3, 0.3)]

var gen: DungeonGen
var areas: Array = []                 # {room: bool, id, rect: Rect2 (world x z), node, layer, lights: Array}
var area_of: Dictionary = {}          # cell -> index into areas
var locked_room := -1                 # set before `build`: every doorway of this room gets a door, shut and locked (the training)
var keep_clear: Array = []            # set before `build`: [place, radius, its whole cell too?]: nothing is stood there
var doors: Array = []                 # {a: cell (room), b: cell (corridor), at: Vector3, dir: Vector2i, door: bool, open: bool, leaves, lamps}
var _door_at: Dictionary = {}         # [cell, cell] -> index into doors (both orders)
var _kit: Dictionary = {}             # piece name -> [[Mesh, Transform3D, material name], ...]
var _kit_scene: Node3D
var _headless := false
var _lamps: Dictionary = {}
var _gun_area := -1
var _taken: Dictionary = {}           # room cells that hold something against a wall already
var themes: Dictionary = {}           # room id -> its theme (a key of THEMES)
var _plain: Dictionary = {}           # cells whose ceiling stays clear (a turret's rail may run under it)


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)


func build(layout: DungeonGen) -> void:
	gen = layout
	_headless = DisplayServer.get_name() == "headless"
	_kit_scene = (load(V2Assets.DIR + "set.glb") as PackedScene).instantiate()
	for piece in _kit_scene.get_children():
		var parts: Array = []
		for n in piece.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var mat := mi.mesh.surface_get_material(0) if not _headless else null
			parts.append([mi.mesh, mi.transform, mat.resource_name if mat != null else ""])
		_kit[String(piece.name)] = parts
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(gen.seed_value) + 77
	var names: Array = THEMES.keys()                       # every theme comes up before one comes again
	var deck: Array = []
	for r in gen.rooms:
		if deck.is_empty():
			deck = names.duplicate()
			for k in range(deck.size() - 1, 0, -1):
				var o := rng.randi() % (k + 1)
				var t: String = deck[k]
				deck[k] = deck[o]
				deck[o] = t
		themes[r.id] = deck.pop_back()
	for e in gen.enemy_spawns:
		if e.type == "turret":
			for dz in [-1, 0, 1]:
				_plain[cell_of(e.pos) + Vector2i(0, dz)] = true
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
	for k in keep_clear:
		if k[2]:
			_taken[cell_of(k[0])] = true
	for d in gen.deco_spawns:
		_deco(d, rng)
	_furnish(rng)
	for i in areas.size():
		_meshes(i)
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
	var placed: Array = []                                 # the shell: [piece name, Transform3D]
	areas.append({"room": is_room, "id": id, "rect": rect, "node": node, "layer": 2, "lights": [], "cells": cells, "placed": placed, "props": []})
	var height := H if is_room else HC
	var along_x := not is_room and cells.size() > 1 and (cells[0] as Vector2i).y == (cells[1] as Vector2i).y
	var theme: Dictionary = THEMES[themes[id]] if is_room else {}
	for c: Vector2i in cells:
		area_of[c] = index
		var at := center(c)
		if not is_room:
			_corridor_cell(placed, node, c, along_x)
			continue
		# --- the floor: eight tiles of 1 x 2 m; in front of a doorway they lie along the way through it and the four
		# nearest are striped; under the exit all are; here and there two are gratings
		var door_dir := Vector2i.ZERO
		for d in DungeonGen.DIRS:
			if gen.is_floor(c + d) and gen.cells[c + d].t == DungeonGen.T_CORRIDOR:
				door_dir = d
		var turn := Basis(Vector3.UP, PI / 2.0) if door_dir.x != 0 else Basis.IDENTITY       # (a tile's length is along its z)
		var exit_here := id == gen.exit_room and at.distance_to(gen.exit_pos) < 1.0
		var grates := rng.randf() < 0.14 and door_dir == Vector2i.ZERO and not exit_here
		var g0 := rng.randi() % 4
		for ix in 4:
			for iz in 2:
				var local := Vector3(-1.5 + ix, -FLOOR_TOP, -1.0 + iz * 2.0)
				var piece := "floor_plain"
				if exit_here:
					piece = "floor_hazard"
				elif door_dir != Vector2i.ZERO:
					var toward := (turn * local).dot(Vector3(door_dir.x, 0, door_dir.y))
					if toward > 0.0:
						piece = "floor_hazard"
				elif grates and ix == g0 and iz == 0:
					piece = "floor_grating"
				placed.append([piece, Transform3D(turn, at + turn * local)])
		# --- the ceiling: four panels of 2 x 2 m; lamps on every other cell (two of the four), between them plain
		# panels, now and then one carrying services (not where a turret's rail may run)
		var lit := posmod(c.x + c.y, 2) == 0
		var serv := -1 if (lit or _plain.has(c) or rng.randf() > float(theme.services)) else rng.randi() % 4
		for k in 4:
			var cx := -1.0 if k % 2 == 0 else 1.0
			var cz := -1.0 if k < 2 else 1.0
			var piece := "ceiling_plain"
			if lit and k == (posmod(c.x, 4)):                  # (one lamp to a lit cell, not always in the same quarter)
				piece = "ceiling_light"
			elif k == serv:
				piece = "ceiling_services"
			placed.append([piece, Transform3D(Basis(Vector3.UP, (rng.randi() % 4) * PI / 2.0), at + Vector3(cx, H + CEIL_FACE, cz))])
		# --- the walls
		for d in DungeonGen.DIRS:
			var n: Vector2i = c + d
			var edge := at + Vector3(d.x, 0, d.y) * (CELL / 2.0)
			var out := Vector3(d.x, 0, d.y)
			var basis := Basis(Vector3.UP, _yaw(-d))
			if not gen.is_floor(n):
				# a plinth, a row of two panels (the theme deals them), a second row of plain ones up to the ceiling
				for side in [-1.0, 1.0]:
					var o: Vector3 = edge + out * FACE + basis.x * float(side)
					placed.append(["wall_plinth", Transform3D(basis, o)])
					placed.append([theme.walls[rng.randi() % theme.walls.size()], Transform3D(basis, o + Vector3(0, 0.4, 0))])
					placed.append(["wall_upper", Transform3D(basis, o + Vector3(0, 3.4, 0))])
				_wall_box(node, edge, d, -2.3, 2.3, 0.0, height)
			elif gen.cells[n].t == DungeonGen.T_CORRIDOR:
				# a doorway: a door frame facing the room and one facing the corridor, back to back in the wall's
				# thickness, each with its surround; over it the second row of panels
				var back := Basis(Vector3.UP, _yaw(d))
				for piece in ["door_frame", "door_surround"]:
					placed.append([piece, Transform3D(basis, edge)])
					placed.append([piece, Transform3D(back, edge + out * T)])
				for side in [-1.0, 1.0]:
					placed.append(["wall_upper", Transform3D(basis, edge + out * FACE + basis.x * float(side) + Vector3(0, 3.4, 0))])
				_wall_box(node, edge, d, -2.3, -DOOR_HALF, 0.0, H)
				_wall_box(node, edge, d, DOOR_HALF, 2.3, 0.0, H)
				_wall_box(node, edge, d, -DOOR_HALF, DOOR_HALF, DOOR_H, H)
	# floor and ceiling: one box each
	_solid(node, Vector3(rect.size.x, 1.0, rect.size.y), Vector3(rect.get_center().x, -0.5, rect.get_center().y))
	_solid(node, Vector3(rect.size.x, 0.4, rect.size.y), Vector3(rect.get_center().x, height + 0.2, rect.get_center().y))


## A corridor's cell: one section of corridor (floor, walls with their ribs, ceiling), turned along the corridor.
## Where the corridor runs into a room the section is shortened by the room wall's thickness: run to the end of its
## cell, its faces would lie in the planes of the door frame's (two meshes lit by different areas' lights, fighting
## for the pixels: the flicker beside the doorways of the first kit).
func _corridor_cell(placed: Array, node: Node3D, c: Vector2i, along_x: bool) -> void:
	var at := center(c)
	var basis := Basis(Vector3.UP, PI / 2.0) if along_x else Basis.IDENTITY          # (the section's length is along its z)
	var lz := basis.z
	var cut := 0.0
	var shift := 0.0
	for sgn in [-1.0, 1.0]:
		var nb: Vector2i = c + Vector2i(roundi(lz.x * sgn), roundi(lz.z * sgn))
		if gen.is_floor(nb) and gen.cells[nb].t != DungeonGen.T_CORRIDOR:
			cut += T
			shift -= sgn * T / 2.0
	# (a corridor has one kind of section, and now and then a cell of another)
	var kind: String = CORRIDORS[posmod(hash(area_of.get(c, 0)) + gen.seed_value, 3)] if hash(c) % 5 != 0 else CORRIDORS[posmod(hash(c) / 5, 3)]
	placed.append([kind, Transform3D(basis * Basis.from_scale(Vector3(1.0, 1.0, (CELL - cut) / CELL)), at + lz * shift + Vector3(0, -0.012, 0))])
	for d in DungeonGen.DIRS:
		if not gen.is_floor(c + d):
			_wall_box(node, at + Vector3(d.x, 0, d.y) * (CELL / 2.0), d, -2.3, 2.3, 0.0, HC)


## An area's meshes: its shell (floor, walls, ceiling) merged into one mesh per material, and what stands in it
## into a second one (that one casts shadows). Two meshes an area, whatever is in it: a room with thirty things
## in it costs the draw calls of an empty one.
func _meshes(i: int) -> void:
	if _headless:
		return
	var a: Dictionary = areas[i]
	for group in [[a.placed, false], [a.props, true]]:
		var list: Array = group[0]
		if list.is_empty():
			continue
		var tools: Dictionary = {}
		for p in list:
			for part in _kit[p[0]]:
				var key: String = part[2]
				if key == "ELiquid":                       # (each room's tanks hold a liquid of its own colour)
					key = "ELiquid#%d" % (int(a.id) % TANKS.size())
				elif key == "EAccent" and a.room:          # (and the line round its walls has its theme's)
					key = "EAccent#" + themes[a.id]
				if not tools.has(key):
					tools[key] = SurfaceTool.new()
				(tools[key] as SurfaceTool).append_from(part[0], 0, (p[1] as Transform3D) * (part[1] as Transform3D))
		var mesh := ArrayMesh.new()
		var mi := MeshInstance3D.new()
		for key in tools:
			(tools[key] as SurfaceTool).commit(mesh)
		mi.mesh = mesh
		if OS.has_environment("V2_TRIS"):
			var tr := 0
			for k in mesh.get_surface_count():
				tr += mesh.surface_get_array_index_len(k) / 3
			var per := {}
			for p in list:
				per[p[0]] = per.get(p[0], 0) + 1
			print("[tris] area %d (%s %s) %s: %dk  %s" % [i, "room" if a.room else "corridor", str(a.rect.size), "props" if group[1] else "shell", tr / 1000, str(per)])
		var s := 0
		for key: String in tools:
			var mat: Material = V2Assets.material(key) if not key.contains("#") else null
			if key.begins_with("ELiquid#"):
				mat = _liquid(int(key.get_slice("#", 1)))
			elif key.begins_with("EAccent#"):
				mat = V2Assets.accent(THEMES[key.get_slice("#", 1)].accent)
			mi.set_surface_override_material(s, mat)
			s += 1
		# (the shell casts no shadow: what stands in it does)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if group[1] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = a.layer
		(a.node as Node3D).add_child(mi)


func _liquid(k: int) -> StandardMaterial3D:
	var key := "liquid%d" % k
	if not _lamps.has(key):
		var color: Color = TANKS[k]
		var liquid := (V2Assets.material("ELiquid") as StandardMaterial3D).duplicate() as StandardMaterial3D
		# (dark and deep, a faint glow of its own: at the full colour it was a flat bright slab behind the glass)
		liquid.albedo_color = Color(color.r * 0.22, color.g * 0.22, color.b * 0.22)
		liquid.emission = color
		liquid.emission_energy_multiplier = 0.16
		liquid.roughness = 0.08
		liquid.rim_enabled = true                          # lighter toward its outline: it reads as a round column
		liquid.rim = 0.55
		liquid.rim_tint = 0.6
		_lamps[key] = liquid
	return _lamps[key]


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
		l.light_color = THEMES[themes[a.id]].light if a.room else Color(0.97, 0.98, 1.0)
		l.light_energy = (0.25 * clampf(rect.get_area() / (spots.size() * 40.0), 0.8, 1.7)) if a.room else 0.24
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
	# (no shadow: the light comes straight down, and an open leaf, inside the wall, threw a soft-edged band of
	# shadow onto the wall's face beside the doorway, which shimmered as the player moved)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A doorway between a room cell and a corridor cell; with leaves and lamps if the generator put a door there.
func _doorway(dw: Dictionary) -> void:
	var a: Vector2i = dw.room_cell
	var b: Vector2i = dw.corr_cell
	var d: Vector2i = b - a
	var edge := center(a) + Vector3(d.x, 0, d.y) * (CELL / 2.0)
	var locked := locked_room >= 0 and gen.room_at(a) == locked_room
	var has_door := bool(dw.door) or locked
	var rec := {"a": a, "b": b, "at": edge, "dir": d, "door": has_door, "open": not has_door, "locked": locked, "leaves": [], "lamps": []}
	_door_at[[a, b]] = doors.size()
	_door_at[[b, a]] = doors.size()
	doors.append(rec)
	if not rec.door:
		return
	# The leaves: the wide one and the narrow one of the set's door, standing in the middle of the wall between
	# the two door frames; each slides into the wall on its own side. (No shadow: the light comes straight down,
	# and a leaf inside the wall would throw a band of it onto the panels beside the doorway.)
	var layer: int = areas[area_of[a]].layer | areas[area_of[b]].layer
	var frame := Node3D.new()                              # the room-side door frame's place: +Z toward the room, +X along the wall
	frame.transform = Transform3D(Basis(Vector3.UP, _yaw(-d)), edge)
	add_child(frame)
	for piece in ["door_leaf_l", "door_leaf_r"]:
		var leaf := Node3D.new()
		leaf.name = piece
		frame.add_child(leaf)
		if not _headless:
			for part in _kit[piece]:
				var mi := MeshInstance3D.new()
				mi.mesh = part[0]
				mi.transform = part[1]
				mi.material_override = V2Assets.material(part[2])
				mi.layers = layer
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				leaf.add_child(mi)
		var x0 := -DOOR_HALF if piece == "door_leaf_l" else 0.42
		var x1 := 0.42 if piece == "door_leaf_l" else DOOR_HALF
		_solid(leaf, Vector3(x1 - x0, DOOR_H, 0.2), Vector3((x0 + x1) / 2.0, DOOR_H / 2.0, -T / 2.0))
		rec.leaves.append(leaf)


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


func unlock() -> void:
	for d in doors:
		d.locked = false


func open_door(i: int) -> void:
	var d: Dictionary = doors[i]
	if d.open or d.locked:
		return
	d.open = true
	V2Sfx.play("door", (d.at as Vector3) + Vector3(0, 1.3, 0))
	# (each leaf goes all the way into the wall on its side, behind the door frame and the panels beyond it)
	for leaf: Node3D in d.leaves:
		var tw := create_tween()
		tw.tween_interval(0.12)
		tw.tween_property(leaf, "position:x", float(LEAF_SLIDE[String(leaf.name)]), 0.6 if leaf.name == &"door_leaf_r" else 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## What the generator stands against a room's wall: something of the room's theme there.
func _deco(d: Dictionary, rng: RandomNumberGenerator) -> void:
	var out := Vector3(sin(float(d.yaw)), 0, cos(float(d.yaw)))          # toward the wall (the generator's yaw faces the room)
	var c := cell_of(d.pos)
	if _taken.has(c):
		return
	var side := Vector2i.ZERO                              # the wall of its cell that lies that way
	for dir in DungeonGen.DIRS:
		if not gen.is_floor(c + dir) and (side == Vector2i.ZERO or Vector2(dir).dot(Vector2(out.x, out.z)) > Vector2(side).dot(Vector2(out.x, out.z))):
			side = dir
	if side == Vector2i.ZERO:
		return
	_taken[c] = true
	var along: Array = THEMES[themes[int(d.room)]].along
	_against(along[rng.randi() % along.size()], c, side, int(d.room), rng)


## `what` against the wall of cell `c` on its side `d`, somewhere along it, its back 0.24 m off the wall (clear of
## the pipes of a service panel); a pipe riser stands on the wall itself.
func _against(what: String, c: Vector2i, d: Vector2i, room_id: int, rng: RandomNumberGenerator) -> void:
	var out := Vector3(d.x, 0, d.y)
	var side := Vector3(-d.y, 0, d.x)
	var spec: Array = DECO_BOX[what]
	var yaw := atan2(-out.x, -out.z)
	# (What stands against a wall must leave the middle of its cell free: the robots and the bot walk there. A
	# specimen tank, 1.5 m deep, reached to 15 cm from it and closed the cell: tanks stand free now, and nothing
	# deeper than 1.3 m goes against a wall.)
	assert((spec[0] as Vector3).z <= 1.3, what + " is too deep to stand against a wall")
	var reach := CELL / 2.0 - (0.0 if what == "pipe_riser" else 0.24) - float(spec[2])
	var room_for := maxf((CELL - (spec[0] as Vector3).x) / 2.0 - 0.3, 0.0)
	var slide := rng.randf_range(-room_for, room_for)
	_stand(what, center(c) + out * reach + side * slide, yaw, room_id)
	# now and then something small in what is left of the cell's wall beside it
	var small: Array = THEMES[themes[room_id]].small
	var item: String = small[rng.randi() % small.size()]
	var isz: Vector3 = (DECO_BOX[item] as Array)[0]
	var free := CELL / 2.0 - 0.15 + absf(slide) - (spec[0] as Vector3).x / 2.0         # on the side the piece moved away from
	if what != item and rng.randf() < 0.4 and free > isz.x + 0.25:
		var sgn := -1.0 if slide > 0.0 else 1.0
		var at := center(c) + side * sgn * (CELL / 2.0 - 0.15 - free / 2.0) + out * (CELL / 2.0 - 0.3 - isz.z / 2.0 - rng.randf_range(0.0, 0.25))
		_stand(item, at, yaw + rng.randf_range(-0.3, 0.3), room_id)


## The rooms furnished: cover at the corners of the cells inside them (the robots keep to the cells' middles, so
## they pass between), and the theme's equipment along the walls, on cells that hold nothing yet and are not at a
## doorway or by the exit.
func _furnish(rng: RandomNumberGenerator) -> void:
	for l in gen.loot_spawns:
		_taken[cell_of(l.pos)] = true
	for r in gen.rooms:
		var rc := r.rect
		var theme: Dictionary = THEMES[themes[r.id]]
		# --- cover: a pattern over the inner corners
		var pattern := rng.randi() % 3                         # 0 the four outer ones, 1 every second, 2 scattered
		for x in range(rc.position.x + 1, rc.end.x):
			for y in range(rc.position.y + 1, rc.end.y):
				var ix := x - rc.position.x
				var iy := y - rc.position.y
				var outer := (ix == 1 or ix == rc.size.x - 1) and (iy == 1 or iy == rc.size.y - 1)
				if rc.size.x >= 5 and rc.size.y >= 5:      # (a big room's middle is not left bare)
					outer = outer or ((ix == rc.size.x / 2 or ix == (rc.size.x + 1) / 2) and (iy == rc.size.y / 2 or iy == (rc.size.y + 1) / 2))
				var want := outer if pattern == 0 else ((ix % 2 == 1 and iy % 2 == 1) if pattern == 1 else rng.randf() < 0.5)
				if rc.size.x >= 5 and rc.size.y >= 5 and not want:
					want = rng.randf() < 0.18                      # (and a few more, off the pattern)
				if rc.size.x < 4 or rc.size.y < 4:
					want = rng.randf() < 0.4                       # (a small room: one or two)
				if not want:
					continue
				var at := Vector3(x * CELL, 0, y * CELL)
				if r.id == gen.exit_room and at.distance_to(gen.exit_pos) < 3.6:
					continue
				if keep_clear.any(func(k: Array) -> bool: return at.distance_to(k[0]) < float(k[1])):
					continue
				var by_door := false                           # (the cells round a doorway stay open)
				for dc in r.doorway_cells:
					if absi(dc.x * 2 + 1 - x * 2) <= 1 and absi(dc.y * 2 + 1 - y * 2) <= 1:
						by_door = true
				if by_door:
					continue
				var what: String = theme.stand[rng.randi() % theme.stand.size()]
				var yaw := (rng.randi() % 4) * PI / 2.0
				_stand(what, at, yaw, r.id)
				_beside(what, at, yaw, theme.small, r.id, rng)
		# --- along the walls
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
			var sides: Array = []
			for d in DungeonGen.DIRS:
				if not gen.is_floor(c + d):
					sides.append(d)
			if not sides.is_empty():
				spots.append([c, sides[rng.randi() % sides.size()]])
		for k in int(round(spots.size() * FILL)):
			var at_i := rng.randi() % spots.size()
			var pick: Array = spots[at_i]
			spots.remove_at(at_i)
			_taken[pick[0]] = true
			_against(theme.along[rng.randi() % theme.along.size()], pick[0], pick[1], r.id, rng)


## Something small next to a piece of cover (a crate left by a stack, a drum by a column): in front of it or behind,
## a little askew. Only by pieces shallow enough that the pair stays within 1.2 m of the cell corner they stand on:
## the robots pass along the cells' middles, 2 m from it.
func _beside(what: String, at: Vector3, yaw: float, small: Array, room_id: int, rng: RandomNumberGenerator) -> void:
	var spec: Array = DECO_BOX[what]
	var size: Vector3 = spec[0]
	if size.z > 1.0 or rng.randf() > 0.65:
		return
	var b := Basis(Vector3.UP, yaw)
	var n := 1 if rng.randf() < 0.7 else 2
	var sides: Array = [1.0, -1.0] if rng.randf() < 0.5 else [-1.0, 1.0]
	for k in n:
		var item: String = small[rng.randi() % small.size()]
		var isz: Vector3 = (DECO_BOX[item] as Array)[0]
		var off := size.z / 2.0 + isz.z / 2.0 + rng.randf_range(0.06, 0.14)
		if off + isz.z / 2.0 > 1.2:
			continue
		var slide := maxf((size.x - isz.x) / 2.0, 0.0)
		var p := at + b * ((spec[1] as Vector3) + Vector3(rng.randf_range(-slide, slide), 0, float(sides[k]) * off))
		_stand(item, p, yaw + rng.randf_range(-0.22, 0.22) + (PI if rng.randf() < 0.5 else 0.0), room_id)


## One of the set's pieces standing at `at`, turned by `yaw`: into the room's merged mesh, and a box that stops
## the player and rounds.
func _stand(what: String, at: Vector3, yaw: float, room_id: int) -> void:
	var area: Dictionary = areas[area_of[gen.rooms[room_id].rect.position]]
	var spec: Array = DECO_BOX[what]
	var basis := Basis(Vector3.UP, yaw)
	var size: Vector3 = spec[0]
	_solid(area.node, size, at + basis * (spec[1] as Vector3) + Vector3(0, size.y / 2.0, 0), yaw)
	(area.props as Array).append([what, Transform3D(basis, at)])
	if OS.has_environment("V2_STAND"):
		printerr("[stand] %s at %.2f %.2f yaw %.0f room %d" % [what, at.x, at.z, rad_to_deg(yaw), room_id])


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
		(a.node as Node3D).visible = i == here or r.grow(SEEN).has_point(Vector2(player_at.x, player_at.z))
	if here != _gun_area and here >= 0:
		_gun_area = here
		for i in areas.size():
			for l in areas[i].lights:
				(l as Light3D).light_cull_mask = int(areas[i].layer) | (gun_layer if i == here else 0)
