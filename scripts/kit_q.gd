class_name KitQuaternius
extends RefCounted
## Quaternius Modular Sci-Fi MegaKit + Sci-Fi Essentials (CC0), normalized by
## blender/scripts/normalize_quaternius.py into assets/models/q_kit.glb and q_door.glb.
## Same interface as KitGreybox: get_mesh(piece, variant), get_collision(piece), door_scene().
## Piece frames match CLAUDE.md "Kit piece frames"; walls are 5 m tall here.

const KIT := "res://assets/models/q_kit.glb"
const DOOR := "res://assets/models/q_door.glb"

## piece -> {variant: node name in q_kit.glb}; "" is the default variant.
const NODES := {
	"floor": {"": "Floor_A", "A": "Floor_A", "B": "Floor_B", "C": "Floor_C"},
	"ceiling": {"": "Ceiling"},
	"ceiling_light": {"": "CeilingLight"},
	"wall": {"": "Wall_Band", "astra": "Wall_Astra", "band": "Wall_Band", "window": "Wall_Window"},
	"doorframe": {"": "Doorframe"},
	"pillar": {"": "Pillar"},
	"deco_crate3": {"": "Deco_Crate3"}, "deco_barrel_large": {"": "Deco_BarrelLarge"},
	"deco_computer": {"": "Deco_Computer"}, "deco_barrel": {"": "Deco_Barrel"},
	"deco_locker": {"": "Deco_Locker"}, "deco_shelves": {"": "Deco_Shelves"},
}
const WALL_STYLES := ["astra", "band", "window"]
const FLOOR_STYLES := ["A", "B", "C"]

var _meshes: Dictionary = {}  # node name -> Mesh
var _door: PackedScene


func _init() -> void:
	var scene: Node = (load(KIT) as PackedScene).instantiate()
	for piece in NODES:
		for v in NODES[piece]:
			var n: String = NODES[piece][v]
			if _meshes.has(n):
				continue
			var mi := scene.find_child(n, true, false) as MeshInstance3D
			assert(mi != null, "q_kit.glb has no node " + n)
			_meshes[n] = MaterialLib.rebind(mi.mesh)
	scene.free()
	_door = load(DOOR)


func get_mesh(piece: String, variant: String = "") -> Mesh:
	var table: Dictionary = NODES[piece]
	return _meshes[table.get(variant, table[""])]


func door_scene() -> Node3D:
	var d := _door.instantiate() as Node3D
	MaterialLib.rebind_tree(d)
	return d


## Collision boxes in the piece frame (Godot space: -Z faces into the room).
func get_collision(piece: String) -> Array[AABB]:
	match piece:
		"wall":
			# Panel face reaches 0.45 m into the cell; backing extends outward.
			return [AABB(Vector3(-2, 0, -DungeonGen.WALL_DEPTH), Vector3(4, DungeonGen.WALL_H, DungeonGen.WALL_DEPTH + 0.6))]
		"doorframe":
			# Door_Frame_Square: 4.86 m wide, opening 2.46 x 3.5 m, 0.5 m deep.
			return [AABB(Vector3(-2.43, 0, -0.25), Vector3(1.2, 5, 0.5)),
				AABB(Vector3(1.23, 0, -0.25), Vector3(1.2, 5, 0.5)),
				AABB(Vector3(-1.23, 3.5, -0.25), Vector3(2.46, 1.5, 0.5))]
		"pillar":
			return [AABB(Vector3(-0.6, 0, -0.6), Vector3(1.2, 5, 1.2))]
		"door_panel":
			return [AABB(Vector3(-2.1, 0, -0.1), Vector3(4.2, 4.05, 0.2))]
	if piece.begins_with("deco_"):
		return [get_mesh(piece).get_aabb().grow(-0.02)]
	return []
