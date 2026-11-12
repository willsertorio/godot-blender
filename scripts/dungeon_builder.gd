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
## Area meshes beyond this distance (from their bounds) are not drawn.
const VIEW_RANGE := 64.0

var kit  # KitQuaternius (default) or KitGreybox: get_mesh(piece, variant), get_collision(), optional door_scene()

static var _art_kit: KitQuaternius


static func default_kit():
	if _art_kit == null:
		_art_kit = KitQuaternius.new()
	return _art_kit


func _init(p_kit = null) -> void:
	kit = p_kit if p_kit != null else default_kit()


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

	# Per-area look: each room gets one wall style and one floor; corridors use band walls.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(g.seed_value * 977 + 3)
	var wall_style := {}
	var floor_style := {}
	for r in g.rooms:
		wall_style["r%d" % r.id] = KitQuaternius.WALL_STYLES[rng.randi() % 3]
		floor_style["r%d" % r.id] = KitQuaternius.FLOOR_STYLES[rng.randi() % 3]

	for c in g.cells:
		var e = g.cells[c]
		var area := ("r%d" if e.t == DungeonGen.T_ROOM else "c%d") % e.id
		var xf := Transform3D(Basis(), DungeonGen.cell_center(c))
		_add(pieces, area, "floor", xf, floor_style.get(area, "B"))
		# Light fixtures on every other cell (checkerboard on both axes) to keep the ceiling calm.
		var lit := posmod(c.x, 2) == 0 and posmod(c.y, 2) == 0 if e.t == DungeonGen.T_ROOM else posmod(c.x + c.y, 2) == 0
		_add(pieces, "ceil_" + area, "ceiling_light" if lit else "ceiling", xf)
		for d in DungeonGen.DIRS:
			var n: Vector2i = c + d
			if not g.is_floor(n):
				var wx := edge_transform(c, d)
				_add(pieces, area, "wall", wx, wall_style.get(area, "band"))
				collide.append(["wall", wx])
			elif e.t == DungeonGen.T_ROOM and g.cells[n].t == DungeonGen.T_CORRIDOR:
				var fx := edge_transform(c, d)
				_add(pieces, area, "doorframe", fx)
				collide.append(["doorframe", fx])

	for v in g.pillars:
		var px := Transform3D(Basis(), Vector3(v.x * CELL, 0, v.y * CELL))
		var r := g.room_at(v)  # vertex v is the min-corner of cell v, inside the room
		_add(pieces, "cast_r%d" % r, "pillar", px)
		collide.append(["pillar", px])

	for dz in g.deco_spawns:
		var dxf := Transform3D(Basis(Vector3.UP, dz.yaw), dz.pos)
		_add(pieces, "cast_r%d" % dz.room, "deco_" + dz.kind, dxf)
		collide.append(["deco_" + dz.kind, dxf])

	var geo := Node3D.new()
	geo.name = "Geometry"
	root.add_child(geo)
	for area in pieces:
		var mi := MeshInstance3D.new()
		mi.name = area
		mi.mesh = _merge(pieces[area])
		if area.begins_with("ceil_"):
			mi.layers = CEILING_LAYER  # overhead views (capture overview) cull ceilings
		# Room shells (walls, floor, ceiling, frames) can't cast a useful shadow onto their
		# own interior, and every omni shadow renders 6 faces: only pillars ("cast_") cast.
		if not area.begins_with("cast_"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# No occlusion culling in Compatibility: drop far areas (fog hides the cut).
		mi.visibility_range_end = VIEW_RANGE
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


## Distance cut for props (enemies, crates, pickups): their meshes are small on screen
## beyond this and there is no occlusion culling in Compatibility.
static var high_quality := true


## Light shaft (additive cone, assets/shaders/shaft.gdshader) and drifting dust under a ceiling light.
static func _light_shaft(l: OmniLight3D) -> void:
	var h := l.position.y - 0.05
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 2.6
	cm.height = h
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/shaft.gdshader")
	sm.set_shader_parameter("color", l.light_color)
	sm.set_shader_parameter("height", h)
	cone.material_override = sm
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.position = Vector3(0, -h * 0.5 + 0.3, 0)
	cone.visibility_range_end = 40.0
	l.add_child(cone)
	var dust := CPUParticles3D.new()
	dust.amount = 70
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.8, h * 0.42, 1.8)
	dust.direction = Vector3(0.3, -1, 0.2)
	dust.spread = 70.0
	dust.gravity = Vector3(0, -0.01, 0)
	dust.initial_velocity_min = 0.02
	dust.initial_velocity_max = 0.07
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.014)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # not additive: see shaft.gdshader
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.albedo_color = Color(l.light_color.r, l.light_color.g, l.light_color.b, 0.55)
	q.material = dm
	dust.mesh = q
	dust.position = Vector3(0, -h * 0.5, 0)
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.visibility_range_end = 25.0
	l.add_child(dust)


static func limit_view_range(root: Node, distance: float = 48.0) -> void:
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = distance


func _add(pieces: Dictionary, area: String, piece: String, xf: Transform3D, variant: String = "") -> void:
	if not pieces.has(area):
		pieces[area] = []
	pieces[area].append([piece, xf, variant])


func _merge(list: Array) -> ArrayMesh:
	## Bake every placed piece into one mesh, one surface per material.
	var tools: Dictionary = {}  # Material -> SurfaceTool
	for p in list:
		var mesh: Mesh = kit.get_mesh(p[0], p[2])
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
		var panel: Node3D
		if kit.has_method("door_scene"):
			panel = kit.door_scene()  # glb root holding Panel + AnimationPlayer("Open")
		else:
			panel = MeshInstance3D.new()
			panel.name = "Panel"
			panel.mesh = kit.get_mesh("door_panel")
		door.setup(panel, kit.get_collision("door_panel"))
		door.set_meta("corridor", dw.corridor)
		door.set_meta("room", g.room_at(c))
		door.set_meta("room_cell", dw.room_cell)
		door.set_meta("corr_cell", dw.corr_cell)
		doors.add_child(door)


func _build_lights(g: DungeonGen, root: Node3D) -> void:
	## Rooms: up to 2 x 2 ceiling lights (one per quadrant of larger rooms); the light
	## nearest the centre casts shadows. Corridors: one unshadowed light at the midpoint.
	## Keeps every area mesh under the Compatibility limit of 8 lights per object.
	var lights := Node3D.new()
	lights.name = "Lights"
	root.add_child(lights)
	for r in g.rooms:
		var nx := 2 if r.rect.size.x >= 4 else 1
		var nz := 2 if r.rect.size.y >= 4 else 1
		var size := Vector2(r.rect.size) * CELL
		var origin := Vector2(r.rect.position) * CELL
		var centre := r.center()
		var placed: Array[OmniLight3D] = []
		for ix in nx:
			for iz in nz:
				var l := OmniLight3D.new()
				l.name = "RoomLight%d_%d" % [r.id, placed.size()]
				var px := origin.x + size.x * (ix + 0.5) / nx
				var pz := origin.y + size.y * (iz + 0.5) / nz
				l.position = Vector3(px, DungeonGen.WALL_H - 0.6, pz)
				var span := maxf(size.x / nx, size.y / nz)
				l.omni_range = span * 1.15 + 3.0
				l.omni_attenuation = 0.75
				l.light_energy = 2.0
				l.light_specular = 0.6
				l.light_color = Color(1.0, 0.97, 0.92)
				lights.add_child(l)
				placed.append(l)
		placed.sort_custom(func(a, b): return a.position.distance_to(centre) < b.position.distance_to(centre))
		for k in placed.size():
			# High quality: every room light casts soft shadows (props, enemies, the gun), with a shaft + dust.
			if k == 0 or high_quality:
				placed[k].shadow_enabled = true
				placed[k].shadow_bias = 0.08
				placed[k].shadow_blur = 1.6
			if high_quality:
				_light_shaft(placed[k])
	for co in g.corridors:
		var mid: Vector2i = co.cells[co.cells.size() / 2]
		var l := OmniLight3D.new()
		l.name = "CorridorLight%d" % co.id
		l.position = DungeonGen.cell_center(mid) + Vector3.UP * (DungeonGen.WALL_H - 0.6)
		l.omni_range = co.cells.size() * CELL * 0.6 + 4.0
		l.light_energy = 1.3
		l.light_specular = 0.5
		l.light_color = Color(0.92, 0.96, 1.0)
		lights.add_child(l)
