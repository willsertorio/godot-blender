class_name KitArt
extends RefCounted
## The Blender environment kit (assets/models/kit_env.glb + door.glb). Same interface as
## KitGreybox: get_mesh(piece), get_collision(piece), plus door_scene().

const KIT := "res://assets/models/kit_env.glb"
const DOOR := "res://assets/models/door.glb"
const NODES := {"floor": "Floor", "ceiling": "Ceiling", "ceiling_light": "CeilingLight", "wall": "Wall", "doorframe": "Doorframe", "pillar": "Pillar"}

var _meshes: Dictionary = {}
var _door: PackedScene


func _init() -> void:
	var scene: Node = (load(KIT) as PackedScene).instantiate()
	for piece in NODES:
		var mi := scene.find_child(NODES[piece], true, false) as MeshInstance3D
		assert(mi != null, "kit_env.glb has no node " + NODES[piece])
		_meshes[piece] = MaterialLib.rebind(mi.mesh)
	scene.free()
	_door = load(DOOR)


func get_mesh(piece: String) -> Mesh:
	return _meshes[piece]


func door_scene() -> Node3D:
	var d := _door.instantiate() as Node3D
	MaterialLib.rebind_tree(d)
	return d


## Collision boxes in the piece frame (Godot space). Must stay in step with build_kit.py.
func get_collision(piece: String) -> Array[AABB]:
	match piece:
		"wall":
			return [AABB(Vector3(-2, 0, 0), Vector3(4, 4, 0.3))]
		"doorframe":
			return [AABB(Vector3(-2, 0, -0.06), Vector3(0.8, 4, 0.42)),
				AABB(Vector3(1.2, 0, -0.06), Vector3(0.8, 4, 0.42)),
				AABB(Vector3(-1.2, 3, -0.06), Vector3(2.4, 1, 0.42))]
		"pillar":
			return [AABB(Vector3(-0.45, 0, -0.45), Vector3(0.9, 4, 0.9))]
		"door_panel":
			return [AABB(Vector3(-1.2, 0, 0.08), Vector3(2.4, 3, 0.14))]
	return []
