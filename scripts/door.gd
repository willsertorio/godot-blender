class_name Door
extends StaticBody3D
## A door in a doorway. Closed: blocks movement, bullets and sight (collision layer
## WORLD). E within INTERACT_RANGE opens it; it never closes again.
##
## Expects a child Node3D named "Panel" (the moving part). If an AnimationPlayer
## with an "Open" animation exists (Blender kit door), it is played; otherwise the
## panel slides up with a tween (greybox).

const INTERACT_RANGE := 2.6

var is_open := false
var panel: Node3D
var anim: AnimationPlayer


func setup(p_panel: Node3D, shapes: Array[AABB]) -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	panel = p_panel
	add_child(panel)
	for b in shapes:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b.size
		cs.shape = box
		cs.position = b.get_center()
		add_child(cs)
	add_to_group("interactable")
	add_to_group("doors")


func interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.5


func interact_range() -> float:
	return INTERACT_RANGE


func can_interact() -> bool:
	return not is_open


func interact(_player: Node) -> void:
	if is_open:
		return
	is_open = true
	anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim and anim.has_animation("Open"):
		anim.play("Open")
	else:
		var tw := create_tween()
		tw.tween_property(panel, "position:y", 2.95, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# Stop blocking at once: the opening is passable as soon as the player triggers it.
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	opened.emit()


signal opened
