extends Node
## Autoload `Audio`. Owner: Lane D (D-11, D-20).
## Gameplay code calls `Audio.play(&"gunshot_pistol", global_position)` and never loads
## streams itself. Noise radius is NOT decided here - Lane B emits EventBus.noise_emitted;
## this only plays the sound.
## Events: data/ui/audio_events/*.tres (AudioEventDef). Unknown ids fall back:
## monster_<family>_<action> -> monster_<action>, then by prefix (gunshot_* -> gunshot_default).
## No file yet -> Synth placeholder.
## Buses SFX / Voice / Music / UI are created at start; volumes follow Settings volume_*.
## Music (D-20): set_music_state(&"title" | &"base" | &"festival" | &"field" | &"chase" | &"night" | &"raid"); the
## flow state drives it automatically. Each state is a set of stems (data/ui/music_layers/*.tres, MusicLayerDef)
## sharing one tempo and length, or one full_track song; all layers of a timeline start together and only their
## volumes fade:
##   - base: one more instrument per population step (Colony.population() >= unlock_population),
##     refreshed on resident_joined / resident_left / resident_died.
##   - field / chase: per region (MusicLayerDef.region, SceneRouter.current_region()); the empty-region layers
##     are the fallback. chase: tension stems over field while any field monster is in CHASE / ATTACK
##     ("!", state_changed); a full_track chase song crossfades with the field song instead.
##   - festival: festival stems over base on the wedding night event and on the festival day.
##   - night: low strings. raid: percussion.
## music_layers_changed(ids) / sound_played(ev, pos) are for captions and visual cues.
## Ambience: looping beds under the music, AudioEventDefs whose id is in AMBIENCE (amb_*). Audio starts and
## fades them itself from the music state and GameState.is_raining() (weather_changed); play() ignores them.
## They need a real file (no synth fallback). ambience_changed(ids) is for captions.
## Design reference: docs/design/16-art-sound.md

## A sound event started (2D: position is Vector3.INF). For captions / visual cues (AudioEventDef.visual_cue_id).
signal sound_played(event: AudioEventDef, position: Vector3)
## The audible music layers changed (ids in layer_order).
signal music_layers_changed(layer_ids: Array[StringName])
## The ambience loops heard changed.
signal ambience_changed(ambience_ids: Array[StringName])

const EVENTS_DIR := "res://data/ui/audio_events"
const LAYERS_DIR := "res://data/ui/music_layers"
const BUSES := ["SFX", "Voice", "Music", "UI"]
const POOL_2D := 10
const POOL_3D := 20
## Switching between timelines (base <-> field <-> night <-> raid).
const FADE_SEC := 1.2
## Music offset on top of each MusicLayerDef.volume_db.
const MUSIC_DB := -4.0
const SILENT_DB := -80.0
## A layer joining / leaving within the same timeline (population, festival).
const LAYER_FADE_SEC := 2.5
## Chase tension comes in fast, stays CHASE_HOLD_SEC after the last chaser, then fades out.
const CHASE_IN_SEC := 0.5
const CHASE_HOLD_SEC := 3.0
const CHASE_POLL_SEC := 0.25
const MONSTER_GROUP := &"field_monsters"
const CHASE_STATES := [Enums.AIState.CHASE, Enums.AIState.ATTACK]
const WEDDING_EVENT := &"wedding"
## Ambience loop id -> music states it plays in. Rain plays in every state while GameState.is_raining().
const AMB_RAIN := &"amb_rain"
const AMBIENCE := {
	&"amb_base_school": [&"base"],
	AMB_RAIN: [],
}
const AMBIENCE_FADE_SEC := 2.0
const FLOW_MUSIC := {
	Enums.FlowState.TITLE: &"title", Enums.FlowState.BASE_MORNING: &"base", Enums.FlowState.BASE_STAY: &"base", Enums.FlowState.SORTIE_PREP: &"base",
	Enums.FlowState.EVENING: &"base", Enums.FlowState.FIELD: &"field", Enums.FlowState.NIGHT: &"night",
	Enums.FlowState.NIGHT_RAID: &"raid", Enums.FlowState.BASE_DAY_RAID: &"raid", Enums.FlowState.NIGHT_EVENT: &"night",
}
## Music state -> layer states heard in it.
const STATE_LAYERS := {
	&"title": [&"title"], &"base": [&"base"], &"festival": [&"base", &"festival"],
	&"field": [&"field"], &"chase": [&"field", &"chase"],
	&"night": [&"night"], &"raid": [&"raid"],
}
## Layer state -> timeline. Stems of one timeline start together and stay in sync.
const TIMELINE := {
	&"title": &"title", &"base": &"base", &"festival": &"base", &"field": &"field", &"chase": &"field",
	&"night": &"night", &"raid": &"raid",
}

var events: Dictionary = {}
var music_state: StringName = &""
## id -> MusicLayerDef, and the ids in play order (state, unlock_population, id).
var layers: Dictionary = {}
var layer_order: Array[StringName] = []
## Overlays, refreshed automatically (chase from monsters, festival from Colony). Call refresh_music()
## after setting one by hand.
var chase_active := false
var festival_active := false
## >= 0: use this instead of Colony.population() (previews, tests). Call refresh_music() after.
var population_override := -1
## Not empty: use this field region instead of SceneRouter.current_region() (previews, tests). Call
## refresh_music() after.
var region_override: StringName = &""
var _p2: Array[AudioStreamPlayer] = []
var _p3: Array[AudioStreamPlayer3D] = []
var _timeline: StringName = &""
## Field region the current timeline was started for (&"" outside the field).
var _region: StringName = &""
## Players of the current timeline: layer id -> AudioStreamPlayer.
var _layer_players: Dictionary = {}
var _layer_tweens: Dictionary = {}
var _audible: Array[StringName] = []
## Ambience loops playing: id -> AudioStreamPlayer.
var _amb_players: Dictionary = {}
var _amb_tweens: Dictionary = {}
var _monster_states: Dictionary = {}
var _chase_left := 0.0
## -1 not started, -2 finished and waited for, else the WorkerThreadPool task id.
var _prewarm_task := -1


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
	_load_events()
	_load_layers()
	_apply_volumes()
	EventBus.settings_changed.connect(func(k: StringName) -> void:
		if String(k).begins_with("volume"):
			_apply_volumes())
	EventBus.flow_state_changed.connect(func(s: Enums.FlowState) -> void:
		_start_prewarm()
		_check_festival()
		set_music_state(FLOW_MUSIC.get(s, &"")))
	EventBus.day_started.connect(func(_d: int) -> void: _check_festival())
	EventBus.weather_changed.connect(func(_w: Enums.Weather) -> void: refresh_ambience())
	EventBus.game_loaded.connect(func(_slot: int) -> void: refresh_ambience.call_deferred())
	EventBus.game_loaded.connect(func(_slot: int) -> void: _check_festival())
	EventBus.night_event_started.connect(func(event_id: StringName, _p: Array) -> void:
		if event_id == WEDDING_EVENT:
			set_music_state(&"festival"))
	EventBus.resident_joined.connect(func(_id: StringName) -> void: refresh_music.call_deferred())
	EventBus.resident_left.connect(func(_id: StringName, _r: StringName) -> void: refresh_music.call_deferred())
	EventBus.resident_died.connect(func(_id: StringName, _c: StringName) -> void: refresh_music.call_deferred())
	var poll := Timer.new()
	poll.wait_time = CHASE_POLL_SEC
	poll.autostart = true
	poll.timeout.connect(_poll_chase)
	add_child(poll)


func _exit_tree() -> void:
	if _prewarm_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_prewarm_task)
		_prewarm_task = -2


## Placeholder stems take a few seconds to build: do it once on a worker thread, base first, as soon as the
## game flow starts (title). Not at _ready, so tools that reload scripts never race the thread.
func _start_prewarm() -> void:
	if _prewarm_task == -1:
		_prewarm_task = WorkerThreadPool.add_task(_prewarm_music, false, "Audio music stems")


## Worker thread: build every synth stem in timeline order (base, field, night, raid).
func _prewarm_music() -> void:
	var order := [&"base", &"field", &"night", &"raid"]
	var ids := layer_order.duplicate()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return order.find(TIMELINE.get(layers[a].state, &"")) < order.find(TIMELINE.get(layers[b].state, &"")))
	for id: StringName in ids:
		var l: MusicLayerDef = layers[id]
		if l.stream.is_empty():
			MusicSynth.make(l.synth)


func play(event_id: StringName, position: Vector3 = Vector3.INF) -> void:
	if AMBIENCE.has(event_id):
		return  # loops are started by refresh_ambience()
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
		sound_played.emit(ev, position)
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
		sound_played.emit(ev, Vector3.INF)


func set_music_state(state: StringName) -> void:
	if state == music_state:
		return
	music_state = state
	_start_prewarm()
	refresh_music()
	refresh_ambience()


## Ambience ids heard in a music state (pure: no playback).
static func ambience_for(state: StringName, raining: bool) -> Array[StringName]:
	var out: Array[StringName] = []
	if state == &"" or state == &"title":
		return out
	for id: StringName in AMBIENCE:
		if state in AMBIENCE[id] or (id == AMB_RAIN and raining):
			out.append(id)
	return out


## Ambience loops playing now (fading in or at full volume).
func audible_ambience() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_amb_players.keys())
	return out


## Start the ambience loops wanted now and fade out the rest. Loops without a file (no assets) stay silent.
func refresh_ambience() -> void:
	var want := ambience_for(music_state, GameState.is_raining())
	var changed := false
	for id: StringName in _amb_players.keys():
		if id in want:
			continue
		var old: AudioStreamPlayer = _amb_players[id]
		_amb_players.erase(id)
		_fade_amb(id, old, SILENT_DB).tween_callback(old.queue_free)
		changed = true
	for id in want:
		if _amb_players.has(id):
			continue
		var ev := get_event(id)
		if ev == null or ev.stream.is_empty() or not ResourceLoader.exists(ev.stream):
			continue
		var stream: AudioStream = load(ev.stream)
		if &"loop" in stream:
			stream.set(&"loop", true)
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = BUSES[ev.bus]
		p.volume_db = SILENT_DB
		add_child(p)
		p.play()
		_amb_players[id] = p
		_fade_amb(id, p, ev.volume_db)
		changed = true
	if changed:
		ambience_changed.emit(audible_ambience())


func _fade_amb(id: StringName, p: AudioStreamPlayer, target_db: float) -> Tween:
	if _amb_tweens.has(id):
		(_amb_tweens[id] as Tween).kill()
	var tw := create_tween()
	tw.tween_property(p, ^"volume_db", target_db, AMBIENCE_FADE_SEC)
	_amb_tweens[id] = tw
	return tw


## Layer ids heard for a music state, population, overlays and field region (pure: no playback).
## Per layer state: the region's own layers if it has any, else the empty-region ones. A full_track overlay
## (chase, festival) replaces the layers under it.
func layers_for(state: StringName, population: int, chase := false, festival := false,
		region: StringName = &"") -> Array[StringName]:
	var states: Array = STATE_LAYERS.get(state, []).duplicate()
	if chase and &"field" in states and not &"chase" in states:
		states.append(&"chase")
	if festival and &"base" in states and not &"festival" in states:
		states.append(&"festival")
	var picked := {}
	for s: StringName in states:
		var own: Array[StringName] = []
		var any: Array[StringName] = []
		for id in layer_order:
			var l: MusicLayerDef = layers[id]
			if l.state != s or population < l.unlock_population:
				continue
			if l.region == &"":
				any.append(id)
			elif l.region == region:
				own.append(id)
		picked[s] = own if not own.is_empty() else any
	for i in range(1, states.size()):
		if (picked[states[i]] as Array).any(func(id: StringName) -> bool: return (layers[id] as MusicLayerDef).full_track):
			picked[states[0]] = []
	var out: Array[StringName] = []
	for id in layer_order:
		for s: StringName in states:
			if id in picked[s]:
				out.append(id)
				break
	return out


## Field region the music follows (&"" outside the field timeline).
func field_region() -> StringName:
	if region_override != &"":
		return region_override
	if TIMELINE.get(STATE_LAYERS.get(music_state, [&""])[0], &"") != &"field":
		return &""
	return SceneRouter.current_region()


## Layers playing now (fading in or at full volume).
func audible_layers() -> Array[StringName]:
	return _audible.duplicate()


## Layer ids with a running player (the whole current timeline, audible or silent).
func timeline_layers() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_layer_players.keys())
	return out


func population() -> int:
	if population_override >= 0:
		return population_override
	if Colony.has_method(&"population"):
		return Colony.population()
	return 0


## Recompute the audible layers and fade towards them.
func refresh_music() -> void:
	var region := field_region()
	var want := layers_for(music_state, population(), chase_active, festival_active, region)
	var timeline: StringName = TIMELINE.get(STATE_LAYERS.get(music_state, [&""])[0], &"")
	if timeline != _timeline or region != _region:
		_start_timeline(timeline, region)
	for id: StringName in _layer_players:
		var p: AudioStreamPlayer = _layer_players[id]
		var l: MusicLayerDef = layers[id]
		var on := id in want
		var target := l.volume_db + MUSIC_DB if on else SILENT_DB
		var sec := LAYER_FADE_SEC
		if l.state == &"chase" and on:
			sec = CHASE_IN_SEC
		if p.has_meta(&"fresh"):
			sec = FADE_SEC
			p.remove_meta(&"fresh")
		if _layer_tweens.has(id):
			(_layer_tweens[id] as Tween).kill()
		var tw := create_tween()
		tw.tween_property(p, ^"volume_db", target, sec)
		_layer_tweens[id] = tw
	if want != _audible:
		_audible = want
		music_layers_changed.emit(want.duplicate())


## Fade out the old timeline and start every layer of the new one that can be heard in `region`, in the same
## frame (in sync, silent).
func _start_timeline(timeline: StringName, region: StringName) -> void:
	for id: StringName in _layer_players:
		var old: AudioStreamPlayer = _layer_players[id]
		if _layer_tweens.has(id):
			(_layer_tweens[id] as Tween).kill()
		var tw := create_tween()
		tw.tween_property(old, ^"volume_db", SILENT_DB, FADE_SEC)
		tw.tween_callback(old.queue_free)
	_layer_players.clear()
	_layer_tweens.clear()
	_timeline = timeline
	_region = region
	if timeline == &"":
		return
	var can := {}
	for s: StringName in STATE_LAYERS:
		if TIMELINE.get(STATE_LAYERS[s][0], &"") == timeline:
			for overlays in [false, true]:
				for id in layers_for(s, 1 << 20, overlays, overlays, region):
					can[id] = true
	var started: Array[AudioStreamPlayer] = []
	for id in layer_order:
		var l: MusicLayerDef = layers[id]
		if not can.has(id):
			continue
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.volume_db = SILENT_DB
		var stream: AudioStream = load(l.stream) if not l.stream.is_empty() and ResourceLoader.exists(l.stream) \
			else MusicSynth.make(l.synth)
		if &"loop" in stream:
			stream.set(&"loop", true)
		p.stream = stream
		p.set_meta(&"fresh", true)
		add_child(p)
		_layer_players[id] = p
		started.append(p)
	for p in started:
		p.play()


func _check_festival() -> void:
	# Colony.is_festival_today() (C-14) is not in contracts.md yet; read it only if it exists.
	var on := Colony.has_method(&"is_festival_today") and bool(Colony.call(&"is_festival_today"))
	if on != festival_active:
		festival_active = on
		refresh_music()


## Chase overlay: any field monster in CHASE / ATTACK. Reads each monster's state once, then follows
## its state_changed signal (same as D-05 world markers).
func _poll_chase() -> void:
	var chasing := false
	for m in get_tree().get_nodes_in_group(MONSTER_GROUP):
		if not m.has_signal(&"state_changed"):
			continue
		var key := m.get_instance_id()
		if not _monster_states.has(key):
			_monster_states[key] = int(m.get(&"state"))
			m.state_changed.connect(_on_monster_state.bind(key))
			m.tree_exiting.connect(func() -> void: _monster_states.erase(key))
		if int(_monster_states[key]) in CHASE_STATES and not (m.has_method(&"is_dead") and m.is_dead()):
			chasing = true
	if chasing:
		_chase_left = CHASE_HOLD_SEC
	else:
		_chase_left -= CHASE_POLL_SEC
	_set_chase(chasing or _chase_left > 0.0)


func _on_monster_state(_old: int, new_state: int, key: int) -> void:
	_monster_states[key] = new_state
	if new_state in CHASE_STATES:
		_chase_left = CHASE_HOLD_SEC
		_set_chase(true)


func _set_chase(on: bool) -> void:
	if on != chase_active:
		chase_active = on
		refresh_music()


func get_event(event_id: StringName) -> AudioEventDef:
	if events.has(event_id):
		return events[event_id]
	var s := String(event_id)
	var parts := s.split("_")
	if parts.size() >= 3 and events.has(StringName(parts[0] + "_" + parts[parts.size() - 1])):
		return events[StringName(parts[0] + "_" + parts[parts.size() - 1])]
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


func _load_layers() -> void:
	var dir := DirAccess.open(LAYERS_DIR)
	if dir == null:
		return
	var list: Array[MusicLayerDef] = []
	for f in dir.get_files():
		var file := f.trim_suffix(".remap")
		if file.ends_with(".tres"):
			var l := load(LAYERS_DIR.path_join(file)) as MusicLayerDef
			if l != null:
				layers[l.id] = l
				list.append(l)
	list.sort_custom(func(a: MusicLayerDef, b: MusicLayerDef) -> bool:
		if a.state != b.state:
			return String(a.state) < String(b.state)
		if a.unlock_population != b.unlock_population:
			return a.unlock_population < b.unlock_population
		return String(a.id) < String(b.id))
	layer_order.clear()
	for l in list:
		layer_order.append(l.id)


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
