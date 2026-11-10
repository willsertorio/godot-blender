class_name AnimUtil
## Helpers for the Quaternius rigs: clips are named "<Name>_Rig" (or "<Name>_<Armature>").
## find() matches by prefix; cyclic clips are set to loop on first use.

const LOOPING := ["Idle", "Look", "Run", "Walk", "Hanging", "Charging", "Charge", "Idle_Open", "Idle_Closed"]


static func find(ap: AnimationPlayer, prefix: String) -> String:
	if ap == null:
		return ""
	for n in ap.get_animation_list():
		if n == prefix or n.begins_with(prefix + "_"):
			return n
	return ""


## Play the clip whose name starts with `prefix` (no-op if it is already playing).
static func play(ap: AnimationPlayer, prefix: String, blend: float = 0.15, speed: float = 1.0) -> bool:
	var n := find(ap, prefix)
	if n == "":
		return false
	var a := ap.get_animation(n)
	if prefix in LOOPING and a.loop_mode == Animation.LOOP_NONE:
		a.loop_mode = Animation.LOOP_LINEAR
	if ap.current_animation != n or not ap.is_playing():
		ap.play(n, blend, speed)
	return true
