class_name DungeonBuilder
extends RefCounted
## Turns a DungeonGen layout into a scene: per-area merged meshes, collision,
## doors, lights and the exit portal.
##
## Meshes are merged per area (room or corridor) rather than into one dungeon mesh:
## the Compatibility renderer lights each object with at most 8 lights, so each
## room's geometry must be its own object to receive its own lights.

const CELL := DungeonGen.CELL
const CEILING_LAYER := 2  # visual layer bit for ceiling meshes

var kit  # KitGreybox or a later kit with get_mesh()/get_collision()


func _init(p_kit = null) -> void:
	kit = p_kit if p_kit != null else KitGreybox.new()


static func edge_transform(c: Vector2i, d: Vector2i) -> Transform3D:
	## Edge piece on the side `d` of cell `c`: origin at the edge midpoint, local -Z
	## facing into `c`.
	var m := DungeonGen.cell_center(c) + Vector3(d.x, 0, d.y) * (CELL * 0.5)
	var basis := Basis(Vector3.UP, atan2(float(d.x), float(d.y)))
	return Transform3D(basis, m)


func build(g: DungeonGen) -> Node3D:
	var root := Node3D.new()
	root.name = "Dungeon"

	# Piece placements grouped by area key ("r3" / "c5").
	var pieces: Dictionary = {}  # area -> Array of [piece, Transform3D]
	var collide: Array = []  # [piece, Transform3D]

	for c in g.cells:
		var e = g.cells[c]
		var area := ("r%d" if e.t == DungeonGen.T_ROOM else "c%d") % e.id
		var xf := Transform3D(Basis(), DungeonGen.cell_center(c))
		_add(pieces, area, "floor", xf)
		_add(pieces, "ceil_" + area, "ceiling", xf)
		for d in DungeonGen.DIRS:
			var n: Vector2i = c + d
			if not g.is_floor(n):
				var wx := edge_transform(c, d)
				_add(pieces, area, "wall", wx)
				collide.append(["wall", wx])
			elif e.t == DungeonGen.T_ROOM and g.cells[n].t == DungeonGen.T_CORRIDOR:
				var fx := edge_transform(c, d)
				_add(pieces, area, "doorframe", fx)
				collide.append(["doorframe", fx])

	for v in g.pillars:
		var px := Transform3D(Basis(), Vector3(v.x * CELL, 0, v.y * CELL))
		var r := g.room_at(v)  # vertex v is the min-corner of cell v, inside the room
		_add(pieces, "r%d" % r, "pillar", px)
		collide.append(["pillar", px])

	var geo := Node3D.new()
	geo.name = "Geometry"
	root.add_child(geo)
	for area in pieces:
		var mi := MeshInstance3D.new()
		mi.name = area
		mi.mesh = _merge(pieces[area])
		if area.begins_with("ceil_"):
			mi.layers = CEILING_LAYER  # overhead views (capture overview) cull ceilings
		geo.add_child(mi)

	root.add_child(_build_collision(g, collide))
	_build_doors(g, root)
	_build_lights(g, root)

	var portal := ExitPortal.new()
	portal.name = "ExitPortal"
	portal.position = g.exit_pos
	var er := g.rooms[g.exit_room]
	if er.doorway_cells.size() > 0:
		portal.rotation.y = DungeonGen.yaw_facing(g.exit_pos - DungeonGen.cell_center(er.doorway_cells[0]))
	root.add_child(portal)
	portal.build_greybox()
	return root


func _add(pieces: Dictionary, area: String, piece: String, xf: Transform3D) -> void:
	if not pieces.has(area):
		pieces[area] = []
	pieces[area].append([piece, xf])


func _merge(list: Array) -> ArrayMesh:
	## Bake every placed piece into one mesh, one surface per material.
	var tools: Dictionary = {}  # Material -> SurfaceTool
	for p in list:
		var mesh: Mesh = kit.get_mesh(p[0])
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
			tools[mat].append_from(mesh, s, p[1])
	var out := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.set_material(mat)
		st.commit(out)
	return out


func _build_collision(g: DungeonGen, collide: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	for p in collide:
		var xf: Transform3D = p[1]
		for b: AABB in kit.get_collision(p[0]):
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = b.size
			cs.shape = box
			cs.transform = xf * Transform3D(Basis(), b.get_center())
			body.add_child(cs)
	# One slab under the whole dungeon for the floor (its own body so checks can exclude it).
	var bounds := Rect2i()
	var first := true
	for c in g.cells:
		if first:
			bounds = Rect2i(c, Vector2i.ONE)
			first = false
		else:
			bounds = bounds.expand(c).expand(c + Vector2i.ONE)
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(bounds.size.x * CELL + 8, 1.0, bounds.size.y * CELL + 8)
	fs.shape = fb
	var ctr := Vector2(bounds.position) + Vector2(bounds.size) * 0.5
	fs.position = Vector3(ctr.x * CELL, -0.5, ctr.y * CELL)
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorCollision"
	floor_body.collision_layer = Layers.WORLD
	floor_body.collision_mask = 0
	floor_body.add_child(fs)
	body.add_child(floor_body)
	return body


func _build_doors(g: DungeonGen, root: Node3D) -> void:
	var doors := Node3D.new()
	doors.name = "Doors"
	root.add_child(doors)
	for dw in g.doorways:
		if not dw.door:
			continue
		var c: Vector2i = dw.room_cell
		var d: Vector2i = dw.corr_cell - dw.room_cell
		var door := Door.new()
		door.name = "Door%d" % dw.corridor
		door.transform = edge_transform(c, d)
		var panel := MeshInstance3D.new()
		panel.name = "Panel"
		panel.mesh = kit.get_mesh("door_panel")
		door.setup(panel, kit.get_collision("door_panel"))
		door.set_meta("corridor", dw.corridor)
		door.set_meta("room", g.room_at(c))
		doors.add_child(door)


func _build_lights(g: DungeonGen, root: Node3D) -> void:
	var lights := Node3D.new()
	lights.name = "Lights"
	root.add_child(lights)
	for r in g.rooms:
		var l := OmniLight3D.new()
		l.name = "RoomLight%d" % r.id
		l.position = r.center() + Vector3.UP * 3.4
		l.omni_range = maxf(r.rect.size.x, r.rect.size.y) * CELL * 0.85
		l.omni_attenuation = 1.2
		l.light_energy = 1.6
		l.light_color = Color(0.85, 0.93, 1.0)
		lights.add_child(l)
	for co in g.corridors:
		var mid: Vector2i = co.cells[co.cells.size() / 2]
		var l := OmniLight3D.new()
		l.name = "CorridorLight%d" % co.id
		l.position = DungeonGen.cell_center(mid) + Vector3.UP * 3.4
		l.omni_range = 9.0
		l.light_energy = 0.9
		l.light_color = Color(0.6, 0.9, 1.0)
		lights.add_child(l)
