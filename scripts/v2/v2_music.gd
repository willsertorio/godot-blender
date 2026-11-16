class_name V2Music
## The menu's music (**user: music in the menu; "when game starts, we only hear the lab sounds, no more music"**).
## It plays on the title and fades out when a run (or the lab) starts; the game itself has the room tone only.
## Three CC0 pieces from opengameart.org stand as candidates, because none could be heard where this was written:
## M on the title steps through them (the title shows which for a moment); the one that stays is TRACKS[0] once
## the user has chosen. Files: assets/audio/v2/music (tools/build_v2_music.sh: all at -23 LUFS), each one looping.
## The player hangs from the scene tree's root, not from a scene, so that it can fade across the change of scene.

const DIR := "res://assets/audio/v2/music/"
const TRACKS := [
	{"file": "menu_exploration_theme", "title": "Exploration Theme", "by": "Cleyton Kauffman"},
	{"file": "menu_budding_of_consciousness", "title": "The Budding of Consciousness", "by": "Yoiyami"},
	{"file": "menu_solar_sail", "title": "Solar Sail", "by": "vitalezzz"},
]
const LEVEL := -5.0                 # dB: under the game's sounds

static var enabled := true
static var index := 0
static var _player: AudioStreamPlayer


## The title is up: the music starts (or goes on, if it was already playing).
static func start(tree: SceneTree) -> void:
	if not enabled or DisplayServer.get_name() == "headless":
		return
	if is_instance_valid(_player) and _player.playing and not _player.has_meta("leaving"):
		return
	_drop()
	_player = AudioStreamPlayer.new()
	_player.stream = load(DIR + TRACKS[index].file + ".ogg")
	_player.volume_db = -40.0
	tree.root.add_child.call_deferred(_player)
	_player.ready.connect(func() -> void:
		_player.play()
		_player.create_tween().tween_property(_player, "volume_db", LEVEL, 1.5))


## A run starts: the music fades and is gone.
static func stop(seconds: float = 1.4) -> void:
	if not is_instance_valid(_player) or _player.has_meta("leaving"):
		return
	var p := _player
	p.set_meta("leaving", true)
	if not p.is_inside_tree():
		p.queue_free()
		return
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -50.0, seconds)
	tw.tween_callback(p.queue_free)


## The next candidate (M on the title); returns what to show.
static func next(tree: SceneTree) -> String:
	index = (index + 1) % TRACKS.size()
	_drop()
	start(tree)
	return "MUSIC %d / %d  ·  %s  ·  %s" % [index + 1, TRACKS.size(), TRACKS[index].title, TRACKS[index].by]


static func _drop() -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null
