class_name ExitPortal
extends Area3D
## Stepping inside ends the run in success.

signal reached

const EXIT_VIOLET := Color("#B48CFF")


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitoring = true
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.0
	cyl.height = 2.5
	cs.shape = cyl
	cs.position.y = 1.25
	add_child(cs)
	body_entered.connect(func(b): if b.is_in_group("player"): reached.emit())


## Greybox look: a ring of violet light with a glowing disc. Replaced in the hero pass.
func build_greybox() -> void:
	var m := StandardMaterial3D.new()
	m.resource_name = "NeonViolet"
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = EXIT_VIOLET
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 1.05
	tor.outer_radius = 1.25
	tor.material = m
	ring.mesh = tor
	# Pivot stands the ring upright facing local Z; the ring spins about its own normal.
	var pivot := Node3D.new()
	pivot.rotation_degrees.x = 90
	pivot.position.y = 1.4
	add_child(pivot)
	pivot.add_child(ring)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.05
	var dm := m.duplicate() as StandardMaterial3D
	dm.albedo_color = Color(EXIT_VIOLET, 0.35)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material = dm
	disc.mesh = cyl
	disc.rotation_degrees.x = 90
	disc.position.y = 1.4
	add_child(disc)
	var light := OmniLight3D.new()
	light.light_color = EXIT_VIOLET
	light.light_energy = 2.0
	light.omni_range = 7.0
	light.position.y = 1.4
	add_child(light)
	var spin := create_tween().set_loops()
	spin.tween_property(ring, "rotation:y", TAU, 4.0).from(0.0)
