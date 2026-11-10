class_name Sfx
extends Node
## Sound effects. Kenney CC0 sounds in assets/audio, listed in licenses.csv.
## Static API; the first call creates one Sfx node under the scene tree root (no autoload,
## so tool scripts run with `godot -s` can use it too).
##   Sfx.play("pistol")                 2D (player's own sounds, UI)
##   Sfx.play_at("enemy_fire", pos)     3D, positioned in the world
##   Sfx.loop_3d("telegraph", parent)   looping 3D player you own (pitch/volume driven by caller)
## Each key maps to one or more files; a random one plays, with slight pitch variation.
## Browsers only start audio after a user gesture; the title button is that gesture.

const DIR := "res://assets/audio/%s.ogg"

## key: [files, volume_db, pitch_jitter]
const SOUNDS := {
	"pistol": [["laserSmall_000", "laserSmall_001"], -6.0, 0.05],
	"rifle": [["laserSmall_003", "laserSmall_004"], -10.0, 0.08],
	"reload_out": [["impactPlate_light_002"], -8.0, 0.03],
	"reload_in": [["impactMetal_medium_001"], -4.0, 0.03],
	"dry": [["click_001"], -4.0, 0.0],
	"switch": [["switch_003"], -10.0, 0.04],
	"hit_enemy": [["impactMetal_medium_002", "impactMetal_medium_004"], -6.0, 0.08],
	"hit_wall": [["impactMetal_light_001", "impactMetal_light_004"], -14.0, 0.1],
	"telegraph": [["spaceEngineSmall_000"], -8.0, 0.0],
	"enemy_fire": [["laserLarge_000", "laserLarge_003"], -2.0, 0.05],
	"melee": [["impactPunch_heavy_002"], 0.0, 0.05],
	"hurt": [["impactPlate_heavy_001"], -4.0, 0.06],
	"hurt_glitch": [["glitch_002"], -8.0, 0.1],
	"enemy_die": [["explosionCrunch_000", "explosionCrunch_002"], 0.0, 0.06],
	"brawler_motor": [["engineCircular_000"], -14.0, 0.0],
	"pursuer_hover": [["spaceEngineSmall_003"], -16.0, 0.0],
	"door": [["doorOpen_001"], -4.0, 0.03],
	"crate_open": [["impactMetal_heavy_000"], -6.0, 0.05],
	"pickup_health": [["confirmation_002"], -6.0, 0.0],
	"pickup_ammo": [["drop_004"], -4.0, 0.0],
	"pickup_kit": [["maximize_004"], -6.0, 0.0],
	"use_kit": [["forceField_002"], -4.0, 0.0],
	"ui": [["confirmation_001"], -6.0, 0.0],
	"win": [["forceField_004"], -2.0, 0.0],
	"lose": [["lowFrequency_explosion_000"], -2.0, 0.0],
	"ambience": [["spaceEngineLow_001"], -22.0, 0.0],
}
const LOOPS := ["telegraph", "brawler_motor", "pursuer_hover", "ambience"]

static var _inst: Sfx
var _streams: Dictionary = {}
var _ambience: AudioStreamPlayer
## Played keys, newest last (tests and the capture tour read this; audio itself is
## silent in the headless container).
static var log: Array[String] = []


func _ready_streams() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in SOUNDS:
		var list: Array = []
		for f in SOUNDS[key][0]:
			var s: AudioStream = load(DIR % f)
			if key in LOOPS and s is AudioStreamOggVorbis:
				s = s.duplicate()
				s.loop = true
			list.append(s)
		_streams[key] = list


func _pick(key: String) -> AudioStream:
	var l: Array = _streams[key]
	return l[randi() % l.size()]


static func _note(key: String) -> void:
	log.append(key)
	if log.size() > 2000:
		log.pop_front()


func _i_play(key: String, volume_offset: float = 0.0) -> void:
	_note(key)
	var p := AudioStreamPlayer.new()
	p.stream = _pick(key)
	p.volume_db = SOUNDS[key][1] + volume_offset
	p.pitch_scale = 1.0 + randf_range(-1.0, 1.0) * SOUNDS[key][2]
	add_child(p)
	p.finished.connect(p.queue_free)
	if is_inside_tree():
		p.play()
	else:
		p.play.call_deferred()


func _i_play_at(key: String, pos: Vector3, volume_offset: float = 0.0) -> void:
	_note(key)
	var tree := Engine.get_main_loop() as SceneTree
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	var p := AudioStreamPlayer3D.new()
	p.stream = _pick(key)
	p.volume_db = SOUNDS[key][1] + volume_offset + 6.0
	p.pitch_scale = 1.0 + randf_range(-1.0, 1.0) * SOUNDS[key][2]
	p.unit_size = 6.0
	p.max_distance = 60.0
	p.attenuation_filter_cutoff_hz = 9000.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _i_loop_3d(key: String, parent: Node3D) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _pick(key)
	p.volume_db = SOUNDS[key][1]
	p.unit_size = 5.0
	p.max_distance = 40.0
	parent.add_child(p)
	return p


func _i_start_ambience() -> void:
	if _ambience == null:
		_ambience = AudioStreamPlayer.new()
		_ambience.stream = _pick("ambience")
		_ambience.volume_db = SOUNDS.ambience[1]
		add_child(_ambience)
	if not _ambience.playing:
		if is_inside_tree():
			_ambience.play()
		else:
			_ambience.play.call_deferred()


func _i_stop_ambience() -> void:
	if _ambience:
		_ambience.stop()


static func _instance() -> Sfx:
	if _inst == null or not is_instance_valid(_inst):
		_inst = Sfx.new()
		_inst.name = "Sfx"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
		_inst._ready_streams()
	return _inst


static func play(key: String, volume_offset: float = 0.0) -> void:
	_instance()._i_play(key, volume_offset)


static func play_at(key: String, pos: Vector3, volume_offset: float = 0.0) -> void:
	_instance()._i_play_at(key, pos, volume_offset)


static func loop_3d(key: String, parent: Node3D) -> AudioStreamPlayer3D:
	return _instance()._i_loop_3d(key, parent)


static func start_ambience() -> void:
	_instance()._i_start_ambience()


static func stop_ambience() -> void:
	_instance()._i_stop_ambience()
