class_name V2Fx
## V2 effects rebuilt for Godot (the Blender ones are Cycles-only): tracers, impact sparks, dust puffs, and the
## point lights that go with the muzzle-flash meshes of the glbs.

static var root: Node3D            # where spawned effects are parented (the lab)
static var _cache: Dictionary = {}
static var hold := 1.0             # > 1 keeps tracers and impact lights longer (screenshots)

const YELLOW := Color(1.0, 0.82, 0.45)
const RED := Color(1.0, 0.3, 0.12)


static func _unshaded(key: String, color: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, alpha)
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache[key] = m
	return _cache[key]


static func _later(seconds: float, node: Node) -> void:
	root.get_tree().create_timer(seconds).timeout.connect(node.queue_free)


## A bright streak along a bullet's path, gone after two frames.
static func tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var d := to - from
	var ln := d.length()
	if ln < 0.4 or root == null:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.012, 0.012, 1.0)
	mi.mesh = box
	mi.material_override = _unshaded("tracer" + color.to_html(), color, 5.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var up := Vector3.RIGHT if absf(d.normalized().y) > 0.98 else Vector3.UP
	mi.global_transform = Transform3D(Basis.looking_at(d, up) * Basis.from_scale(Vector3(1, 1, ln * 0.8)), from + d * 0.55)
	_later(0.08 * hold, mi)


## Where a round lands: a shower of sparks, a puff of dust, a short flash of light.
static func impact(pos: Vector3, normal: Vector3, metal: bool = false) -> void:
	if root == null:
		return
	var p := CPUParticles3D.new()
	var streak := BoxMesh.new()
	streak.size = Vector3(0.005, 0.07, 0.005)
	p.mesh = streak
	p.material_override = _unshaded("spark", Color(1.0, 0.62, 0.22), 6.0)
	p.particle_flag_align_y = true
	p.amount = 34 if metal else 22
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 65.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 7.5
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	root.add_child(p)
	p.global_position = pos + normal * 0.02
	p.emitting = true
	_later(1.0, p)
	var s := CPUParticles3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 10
	ball.rings = 5
	s.mesh = ball
	s.material_override = _unshaded("dust_metal" if metal else "dust", Color(0.25, 0.25, 0.26) if metal else Color(0.72, 0.71, 0.68), 1.0, 0.16)
	s.amount = 5
	s.lifetime = 0.9
	s.one_shot = true
	s.explosiveness = 0.9
	s.direction = normal
	s.spread = 50.0
	s.initial_velocity_min = 0.2
	s.initial_velocity_max = 0.8
	s.gravity = Vector3(0, 0.5, 0)
	s.scale_amount_min = 0.15
	s.scale_amount_max = 0.3
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 1.0))
	s.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	s.color_ramp = fade
	root.add_child(s)
	s.global_position = pos + normal * 0.06
	s.emitting = true
	_later(1.6, s)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.3)
	l.light_energy = 2.0
	l.omni_range = 2.5
	root.add_child(l)
	l.global_position = pos + normal * 0.1
	_later(0.07 * hold, l)


## The flash meshes under `scene` (shown by the animations through their scale), each with a point light beside it.
## Returns [{node, light, on}]; poll() switches the lights and returns the flashes that have just lit up.
static func flashes(scene: Node) -> Array:
	var out: Array = []
	for n in scene.find_children("*Flash*", "MeshInstance3D", true, false):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.4)
		l.light_energy = 2.5
		l.omni_range = 5.0
		l.visible = false
		n.get_parent().add_child(l)
		l.position = (n as Node3D).position
		out.append({"node": n, "light": l, "on": false})
	return out


static func poll(list: Array) -> Array:
	var fired: Array = []
	for f in list:
		var on: bool = (f.node as Node3D).scale.x > 0.01 and (f.node as Node3D).is_visible_in_tree()
		(f.light as OmniLight3D).visible = on
		if on and not f.on:
			fired.append(f.node)
		f.on = on
	return fired
