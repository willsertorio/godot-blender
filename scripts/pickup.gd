class_name Pickup
extends Area3D
## A loot payoff lying in the world: "kit" (carried health kit), "ammo" (rifle reserve)
## or "health" (immediate). Walk over it to take it. A pickup that would do nothing
## (kits full, health full, ammo reserve full) stays on the floor.
## Models: kit = Poly Haven medical_box, ammo = Poly Haven ammo_box, health = modelled
## energy cell (assets/models/*.glb), spinning above a loot-green halo on the floor.

const GREEN := Color("#39FF88")
const HEALTH_AMOUNT := 35.0
const AMMO_AMOUNT := 60

var payoff := "health"
## Radius of the walk-over trigger (crates use a larger one so it can be taken from beside the crate).
var collect_radius := 0.7
## Floor halo (off for payoffs that pop out of a crate).
var show_halo := true
var visual: Node3D
var _t := 0.0


func _ready() -> void:
	add_to_group("pickups")
	collision_layer = Layers.PICKUP
	collision_mask = Layers.PLAYER
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = collect_radius
	cs.shape = sph
	cs.position.y = 0.6
	add_child(cs)
	visual = Node3D.new()
	visual.position.y = 0.55
	add_child(visual)
	_build()
	body_entered.connect(_on_body)


const MODELS := {"kit": "res://assets/models/kit.glb", "ammo": "res://assets/models/ammo.glb",
	"health": "res://assets/models/health_cell.glb"}
static var _scenes: Dictionary = {}


func _process(delta: float) -> void:
	_t += delta
	# body_entered only fires on entry; re-offer to a player already standing in range
	# (e.g. health was full when they arrived and has dropped since).
	if fmod(_t, 0.25) < delta:
		for b in get_overlapping_bodies():
			if b is Player and try_take(b):
				return
	visual.rotation.y += delta * 1.4
	visual.position.y = 0.35 + sin(_t * 2.4) * 0.06


func _on_body(b: Node) -> void:
	if b is Player:
		try_take(b)


func try_take(p: Player) -> bool:
	if not p.alive:
		return false
	match payoff:
		"health":
			if p.health >= p.max_health:
				return false
			p.heal(HEALTH_AMOUNT)
			Sfx.play("pickup_health")
		"kit":
			if p.kits >= Player.MAX_KITS:
				return false
			p.kits += 1
			Sfx.play("pickup_kit")
		"ammo":
			if not p.weapons.add_rifle_ammo(AMMO_AMOUNT):
				return false
			Sfx.play("pickup_ammo")
	p.picked_up.emit(payoff)
	queue_free()
	return true


func _build() -> void:
	if show_halo:
		_halo()
	var path: String = MODELS[payoff]
	if ResourceLoader.exists(path):
		if not _scenes.has(path):
			_scenes[path] = load(path)
		var m := (_scenes[path] as PackedScene).instantiate() as Node3D
		MaterialLib.rebind_tree(m)
		visual.add_child(m)
		return
	_build_greybox()


func _halo() -> void:
	## Glowing ring on the floor, so loot reads against the dark deck from across a room.
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.36
	tor.outer_radius = 0.42
	tor.rings = 32
	ring.mesh = tor
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.02
	ring.material_override = MaterialLib.neon(GREEN, 2.2)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var disc := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(1.1, 1.1)
	disc.mesh = q
	disc.position.y = 0.015
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_texture = WeaponHolder._flash_texture()
	dm.albedo_color = Color(GREEN, 1.0) * 0.45
	disc.material_override = dm
	add_child(disc)


func _build_greybox() -> void:
	var neon := MaterialLib.neon(GREEN, 2.4)
	var metal := MaterialLib.get_material("PropMetal")
	match payoff:
		"health":
			# Floating cross.
			for s in [Vector3(0.5, 0.16, 0.16), Vector3(0.16, 0.5, 0.16)]:
				var b := BoxMesh.new()
				b.size = s
				_mi(b, neon)
		"kit":
			var case := BoxMesh.new()
			case.size = Vector3(0.5, 0.3, 0.34)
			_mi(case, metal)
			for s in [Vector3(0.24, 0.07, 0.02), Vector3(0.07, 0.24, 0.02)]:
				var b := BoxMesh.new()
				b.size = s
				var m := _mi(b, neon)
				m.position.z = -0.175
			var band := BoxMesh.new()
			band.size = Vector3(0.52, 0.04, 0.36)
			_mi(band, neon).position.y = 0.1
		"ammo":
			var box := BoxMesh.new()
			box.size = Vector3(0.44, 0.26, 0.26)
			_mi(box, metal)
			for i in 3:
				var cell := CylinderMesh.new()
				cell.top_radius = 0.04
				cell.bottom_radius = 0.04
				cell.height = 0.14
				_mi(cell, neon).position = Vector3(-0.12 + i * 0.12, 0.2, 0)


func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	visual.add_child(mi)
	return mi
