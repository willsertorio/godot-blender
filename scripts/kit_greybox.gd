class_name KitGreybox
extends RefCounted
## Greybox stand-ins for the environment kit. Every piece uses the same local frame
## the Blender kit will use (see CLAUDE.md "Kit piece frames"), so the art pass only
## swaps meshes.
##
## floor / ceiling : origin at cell centre, floor top at y=0, ceiling underside at y=4.
## wall            : origin at edge midpoint on the floor, spans x in [-2, 2], local -Z
##                   faces into the cell it bounds, thickness extends towards +Z.
## doorframe       : same frame as wall, 2.4 m x 3 m opening.
## pillar          : origin at grid vertex on the floor.
## door_panel      : 2.4 x 3 m slab, origin at the bottom centre of the opening.

const NEON_CYAN := Color("#22E5FF")

var _meshes: Dictionary = {}
var mat_wall: StandardMaterial3D
var mat_floor: StandardMaterial3D
var mat_trim: StandardMaterial3D
var mat_neon: StandardMaterial3D


func _init() -> void:
	mat_wall = _mat(Color(0.16, 0.17, 0.19), 0.8)
	mat_floor = _mat(Color(0.11, 0.115, 0.125), 0.9)
	mat_trim = _mat(Color(0.25, 0.26, 0.28), 0.6)
	mat_neon = StandardMaterial3D.new()
	mat_neon.resource_name = "NeonCyan"
	mat_neon.albedo_color = Color.BLACK
	mat_neon.emission_enabled = true
	mat_neon.emission = NEON_CYAN
	mat_neon.emission_energy_multiplier = 3.0
	mat_neon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_neon.albedo_color = NEON_CYAN

	_meshes["floor"] = _build([[mat_floor, AABB(Vector3(-2, -0.2, -2), Vector3(4, 0.2, 4))]])
	_meshes["ceiling"] = _build([[mat_wall, AABB(Vector3(-2, 4, -2), Vector3(4, 0.2, 4))]])
	_meshes["ceiling_light"] = _meshes["ceiling"]
	_meshes["wall"] = _build([
		[mat_wall, AABB(Vector3(-2, 0, 0), Vector3(4, 4, 0.3))],
		[mat_neon, AABB(Vector3(-2, 2.95, -0.03), Vector3(4, 0.06, 0.03))],
		[mat_trim, AABB(Vector3(-2, 0, -0.06), Vector3(4, 0.25, 0.06))],
	])
	_meshes["doorframe"] = _build([
		[mat_trim, AABB(Vector3(-2, 0, 0), Vector3(0.8, 4, 0.3))],
		[mat_trim, AABB(Vector3(1.2, 0, 0), Vector3(0.8, 4, 0.3))],
		[mat_trim, AABB(Vector3(-1.2, 3, 0), Vector3(2.4, 1, 0.3))],
		[mat_neon, AABB(Vector3(-1.25, 3.0, -0.04), Vector3(2.5, 0.05, 0.04))],
	])
	_meshes["pillar"] = _build([
		[mat_trim, AABB(Vector3(-0.4, 0, -0.4), Vector3(0.8, 4, 0.8))],
	])
	_meshes["door_panel"] = _build([
		[mat_trim, AABB(Vector3(-1.2, 0, 0.08), Vector3(2.4, 3, 0.14))],
		[mat_neon, AABB(Vector3(-0.05, 0.4, 0.05), Vector3(0.1, 2.2, 0.03))],
	])


func get_mesh(piece: String) -> Mesh:
	return _meshes[piece]


## Collision boxes per piece in the piece frame (only solid parts).
func get_collision(piece: String) -> Array[AABB]:
	match piece:
		"wall":
			return [AABB(Vector3(-2, 0, 0), Vector3(4, 4, 0.3))]
		"doorframe":
			return [AABB(Vector3(-2, 0, 0), Vector3(0.8, 4, 0.3)),
				AABB(Vector3(1.2, 0, 0), Vector3(0.8, 4, 0.3)),
				AABB(Vector3(-1.2, 3, 0), Vector3(2.4, 1, 0.3))]
		"pillar":
			return [AABB(Vector3(-0.4, 0, -0.4), Vector3(0.8, 4, 0.8))]
		"door_panel":
			return [AABB(Vector3(-1.2, 0, 0.08), Vector3(2.4, 3, 0.14))]
	return []


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _build(parts: Array) -> ArrayMesh:
	var by_mat: Dictionary = {}
	for p in parts:
		var m: Material = p[0]
		if not by_mat.has(m):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(m)
			by_mat[m] = st
		_box(by_mat[m], p[1])
	var mesh := ArrayMesh.new()
	for m in by_mat:
		var st: SurfaceTool = by_mat[m]
		st.generate_tangents()
		st.commit(mesh)
	return mesh


static func _box(st: SurfaceTool, b: AABB) -> void:
	var p := b.position
	var s := b.size
	# 6 faces: normal, then 4 corners counter-clockwise seen from outside.
	var faces := [
		[Vector3(1, 0, 0), [Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)]],
		[Vector3(-1, 0, 0), [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)]],
		[Vector3(0, 1, 0), [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)]],
		[Vector3(0, -1, 0), [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]],
		[Vector3(0, 0, 1), [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)]],
		[Vector3(0, 0, -1), [Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)]],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var q: Array = f[1]
		var v: Array[Vector3] = []
		for k in q:
			v.append(p + k * s)
		# UVs at world scale (1 UV = 1 m) on the face's two tangent axes.
		var uv: Array[Vector2] = []
		for k in v:
			if absf(n.x) > 0.5:
				uv.append(Vector2(k.z, -k.y))
			elif absf(n.y) > 0.5:
				uv.append(Vector2(k.x, k.z))
			else:
				uv.append(Vector2(k.x, -k.y))
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
