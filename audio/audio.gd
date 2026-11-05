extends Node
## Autoload `Audio`. Owner: Lane D (D-11).
## Gameplay code calls `Audio.play(&"gunshot_pistol", global_position)` and never loads
## streams itself. Noise radius is NOT decided here - Lane B emits EventBus.noise_emitted;
## this only plays the sound.
## Events: data/ui/audio_events/*.tres (AudioEventDef). Unknown ids fall back by prefix
## (gunshot_* -> gunshot_default). No file yet -> Synth placeholder.
## Buses SFX / Voice / Music / UI are created at start; volumes follow Settings volume_*.
## Music: set_music_state(&"base" | &"field" | &"chase" | &"night" | &"raid"), crossfaded; the flow
## state drives it automatically. Design reference: docs/design/16-art-sound.md

const EVENTS_DIR := "res://data/ui/audio_events"
const BUSES := ["SFX", "Voice", "Music", "UI"]
const POOL_2D := 10
const POOL_3D := 20
const FADE_SEC := 1.2
const FLOW_MUSIC := {
	Enums.FlowState.BASE_MORNING: &"base", Enums.FlowState.BASE_STAY: &"base", Enums.FlowState.SORTIE_PREP: &"base",
	Enums.FlowState.EVENING: &"base", Enums.FlowState.FIELD: &"field", Enums.FlowState.NIGHT: &"night",
	Enums.FlowState.NIGHT_RAID: &"raid", Enums.FlowState.BASE_DAY_RAID: &"raid",
}

var events: Dictionary = {}
var music_state: StringName = &""
var _p2: Array[AudioStreamPlayer] = []
var _p3: Array[AudioStreamPlayer3D] = []
var _music: Array[AudioStreamPlayer] = []
var _music_on := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, &"Master")
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_p2.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		add_child(p)
		_p3.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = &"Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	_load_events()
	_apply_volumes()
	EventBus.settings_changed.connect(func(k: StringName) -> void:
		if String(k).begins_with("volume"):
			_apply_volumes())
	EventBus.flow_state_changed.connect(func(s: Enums.FlowState) -> void:
		set_music_state(FLOW_MUSIC.get(s, &"")))


func play(event_id: StringName, position: Vector3 = Vector3.INF) -> void:
	var ev := get_event(event_id)
	if ev == null:
		return
	var stream: AudioStream = load(ev.stream) if not ev.stream.is_empty() and ResourceLoader.exists(ev.stream) \
		else Synth.make(ev.synth)
	var pitch := 1.0 + randf_range(-ev.pitch_random, ev.pitch_random)
	var bus: String = BUSES[ev.bus]
	if ev.positional and position != Vector3.INF:
		var p := _free_3d(ev.priority)
		if p == null:
			return
		p.stream = stream
		p.global_position = position
		p.bus = bus
		p.volume_db = ev.volume_db
		p.pitch_scale = pitch
		p.max_distance = ev.max_distance
		p.set_meta(&"prio", int(ev.priority))
		p.play()
	else:
		var p := _free_2d(ev.priority)
		if p == null:
			return
		p.stream = stream
		p.bus = bus
		p.volume_db = ev.volume_db
		p.pitch_scale = pitch
		p.set_meta(&"prio", int(ev.priority))
		p.play()


func set_music_state(state: StringName) -> void:
	if state == music_state:
		return
	music_state = state
	var from := _music[_music_on]
	_music_on = 1 - _music_on
	var to := _music[_music_on]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(from, ^"volume_db", -80.0, FADE_SEC)
	if state != &"":
		to.stream = Synth.make(StringName("music_" + String(state)))
		to.volume_db = -80.0
		to.play()
		tw.tween_property(to, ^"volume_db", -8.0, FADE_SEC)
	tw.chain().tween_callback(from.stop)


func get_event(event_id: StringName) -> AudioEventDef:
	if events.has(event_id):
		return events[event_id]
	var s := String(event_id)
	var cut := s.find("_")
	if cut > 0 and events.has(StringName(s.substr(0, cut) + "_default")):
		return events[StringName(s.substr(0, cut) + "_default")]
	return null


func _load_events() -> void:
	var dir := DirAccess.open(EVENTS_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		var file := f.trim_suffix(".remap")
		if file.ends_with(".tres"):
			var e := load(EVENTS_DIR.path_join(file)) as AudioEventDef
			if e != null:
				events[e.id] = e


func _apply_volumes() -> void:
	var master := float(Settings.get_value(&"volume_master"))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master, 0.0001)))
	for pair in [["Music", &"volume_music"], ["SFX", &"volume_sfx"], ["UI", &"volume_sfx"], ["Voice", &"volume_voice"]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(Settings.get_value(pair[1])), 0.0001)))


## Free player, or steal the lowest-priority one at or below `prio`.
func _free_2d(prio: int) -> AudioStreamPlayer:
	var best: AudioStreamPlayer = null
	for p in _p2:
		if not p.playing:
			return p
		if int(p.get_meta(&"prio", 0)) <= prio and (best == null or int(p.get_meta(&"prio", 0)) < int(best.get_meta(&"prio", 0))):
			best = p
	return best


func _free_3d(prio: int) -> AudioStreamPlayer3D:
	var best: AudioStreamPlayer3D = null
	for p in _p3:
		if not p.playing:
			return p
		if int(p.get_meta(&"prio", 0)) <= prio and (best == null or int(p.get_meta(&"prio", 0)) < int(best.get_meta(&"prio", 0))):
			best = p
	return best
