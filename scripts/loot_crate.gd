class_name LootCrate
extends StaticBody3D
## Loot container. Closed: E within INTERACT_RANGE opens it (no prompt, as in the GDD).
## Opening plays the glb's "Open" animation and pays out its payoff (kit / ammo /
## health). The payoff is taken at once if it does something; otherwise the pickup
## waits on top of the open crate. A crate opens once.
## Solid on WORLD: it blocks movement, sight and bullets like any furniture.

signal opened(payoff: String)

const SCENE := "res://assets/models/container.glb"
const INTERACT_RANGE := 2.0
const SIZE := Vector3(1.14, 0.9, 0.9)  # Quaternius Prop_Chest, normalized

static var _scene: PackedScene

var payoff := "health"
var is_open := false
var main
var model: Node3D
var anim: AnimationPlayer


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("crates")
	collision_layer = Layers.WORLD
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	cs.shape = box
	cs.position.y = SIZE.y * 0.5
	add_child(cs)
	if _scene == null:
		_scene = load(SCENE)
	model = _scene.instantiate()
	MaterialLib.rebind_tree(model)
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	DungeonBuilder.limit_view_range(self)
	# No light of its own: the Quaternius chest glows through its emissive map, and extra
	# lights push room meshes past Compatibility's 8-lights-per-object limit.


func interact_point() -> Vector3:
	return global_position + Vector3.UP * 0.5


func interact_range() -> float:
	return INTERACT_RANGE


func can_interact() -> bool:
	return not is_open


func interact(player: Node) -> void:
	if is_open:
		return
	is_open = true
	if not AnimUtil.play(anim, "Open", 0.1) and anim and anim.has_animation("Open"):
		anim.play("Open")
	Sfx.play_at("crate_open", global_position + Vector3.UP * 0.5)
	var p := Pickup.new()
	p.payoff = payoff
	p.collect_radius = 1.35
	p.show_halo = false
	p.position = Vector3(0, 0.7, 0)
	add_child(p)
	opened.emit(payoff)
	# Pop up out of the crate, then pay out if it helps right now.
	var tw := p.create_tween()
	tw.tween_property(p, "position:y", 1.2, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(func():
		if is_instance_valid(p) and player is Player:
			p.try_take(player))
