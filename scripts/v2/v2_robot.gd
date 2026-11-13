class_name V2Robot
extends Node3D
## One V2 robot standing where it stands in the Blender scene, cycling through its clips so they can be previewed.
## Shooting it plays its Death clip; it comes back afterwards.

const ORDER := {
	"spider": ["Idle", "Shoot", "Walk", "Run", "Death"],
	"drone": ["Idle", "Shoot", "Fly", "Death"],
	"turret": ["Idle", "Shoot", "Aim", "Death"],
}
const HIT := {  # joint the hit box rides on, box size, box centre (in the joint's frame)
	"spider": ["Spider_Body", Vector3(1.0, 0.6, 1.2), Vector3.ZERO],
	"drone": ["Drone_Body", Vector3(1.7, 0.45, 0.6), Vector3.ZERO],
	"turret": ["Turret_Head", Vector3(0.7, 0.4, 0.4), Vector3(0.15, -0.14, 0.0)],
}

var kind := ""
var ap: AnimationPlayer
var clip := ""
var auto := true
var dead := false
var _idx := 0
var _left := 0.0
var _flashes: Array = []
var _label: Label3D


func setup(robot: String) -> void:
	kind = robot
	var scene: Node3D = (load(V2Assets.DIR + kind + ".glb") as PackedScene).instantiate()
	add_child(scene)
	V2Assets.apply(scene)
	ap = V2Assets.clips(scene, kind)
	_flashes = V2Fx.flashes(scene)
	var joint := scene.find_child(HIT[kind][0], true, false) as Node3D
	if joint != null:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = HIT[kind][1]
		shape.shape = box
		shape.position = HIT[kind][2]
		body.add_child(shape)
		body.set_meta("robot", self)
		joint.add_child(body)
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.pixel_size = 0.0035
		_label.modulate = Color(0.55, 0.95, 1.0)
		_label.outline_size = 6
		add_child(_label)
		_label.global_position = joint.global_position + Vector3(0, 0.75, 0)
	play(ORDER[kind][0])


func play(clip_name: String) -> void:
	if ap == null or not ap.has_animation(clip_name):
		return
	clip = clip_name
	dead = clip == "Death"
	_idx = ORDER[kind].find(clip)
	ap.play(clip)
	ap.seek(0.0, true)
	var a := ap.get_animation(clip)
	_left = maxf(a.length, 3.0) if a.loop_mode != Animation.LOOP_NONE else a.length + (2.5 if dead else 0.4)
	if _label != null:
		_label.text = "%s  ·  %s" % [kind.to_upper(), clip]


func next() -> void:
	play(ORDER[kind][(_idx + 1) % ORDER[kind].size()])


func hit() -> void:
	if not dead:
		play("Death")


func flash_on() -> bool:
	for f in _flashes:
		if f.on:
			return true
	return false


func _process(delta: float) -> void:
	for node in V2Fx.poll(_flashes):       # a shot: a red streak along the barrel, sparks where it lands
		var n := node as Node3D
		var from := n.global_position
		var dir := -n.global_basis.z.normalized()
		var to := from + dir * 30.0
		var q := PhysicsRayQueryParameters3D.create(from + dir * 0.3, to)
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty():
			to = res.position
			V2Fx.impact(to, res.normal)
		V2Fx.tracer(from, to, V2Fx.RED)
	_left -= delta
	if _left <= 0.0:
		if auto or dead:
			next()
		else:
			play(clip)
