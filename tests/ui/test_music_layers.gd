extends Node
## D-20: music layers per state, field regions with full-track songs (chase crossfades), chase / festival
## overlays, state switches, every synth stem shares one loop length, and the monster family sound events load
## with captions and visual cues.

const FAMILIES := [&"green", &"stone", &"water", &"light"]
const ACTIONS := [&"suspicious", &"chase", &"attack", &"hurt", &"death"]


func run() -> bool:
	var ok := true
	ok = _expect(Audio.layers.size() >= 12, "at least 12 music layers (%d)" % Audio.layers.size()) and ok

	# Title and base: one full song each, the same at every population.
	ok = _expect(Audio.layers_for(&"title", 0) == [&"title_theme"], "title song") and ok
	var base0 := Audio.layers_for(&"base", 0)
	ok = _expect(base0 == [&"base_theme"] and Audio.layers_for(&"base", 30) == base0, "base song %s" % [base0]) and ok
	var counts: Array[int] = [base0.size()]

	# Field regions: own song, chase song crossfades (replaces the field song); other regions fall back.
	for region in [&"city_park", &"flooded_mall"]:
		var f := Audio.layers_for(&"field", 0, false, false, region)
		var c := Audio.layers_for(&"field", 0, true, false, region)
		ok = _expect(f == [StringName("field_%s" % region)], "%s field song %s" % [region, f]) and ok
		ok = _expect(c == [StringName("chase_%s" % region)], "%s chase song replaces the field song %s" % [region, c]) and ok
		ok = _expect(Audio.layers_for(&"chase", 0, false, false, region) == c, "%s state chase" % region) and ok
	ok = _expect(Audio.layers_for(&"field", 0, false, false, &"debug_region") == Audio.layers_for(&"field", 0),
		"region without songs uses the fallback layers") and ok

	# Overlays and states.
	var field := Audio.layers_for(&"field", 0)
	var chase := Audio.layers_for(&"field", 0, true)
	ok = _expect(field.size() >= 1 and chase.size() > field.size(), "chase adds tension layers over field") and ok
	ok = _expect(Audio.layers_for(&"chase", 0) == chase, "state chase == field + chase overlay") and ok
	ok = _expect(Audio.layers_for(&"base", 0, false, true).size() > counts[0], "festival adds layers over base") and ok
	ok = _expect(Audio.layers_for(&"festival", 0) == Audio.layers_for(&"base", 0, false, true), "state festival") and ok
	ok = _expect(Audio.layers_for(&"base", 0, true).size() == counts[0], "chase overlay ignored at base") and ok
	for s in [&"night", &"raid"]:
		ok = _expect(Audio.layers_for(s, 0).size() >= 1, "state %s has layers" % s) and ok
	ok = _expect(Audio.layers_for(&"", 10).is_empty(), "no music state -> no layers") and ok

	# Every stem has the same loop length (in sync when mixed).
	var n := MusicSynth.loop_samples()
	for id: StringName in Audio.layers:
		var l: MusicLayerDef = Audio.layers[id]
		ok = _expect(not l.caption.is_empty() and l.visual_cue_id != &"", "layer %s has caption + visual cue" % id) and ok
		if l.stream.is_empty():
			var w := MusicSynth.make(l.synth)
			ok = _expect(w.data.size() == n * 2 and w.loop_mode == AudioStreamWAV.LOOP_FORWARD,
				"stem %s loops at %d samples" % [id, n]) and ok

	# Live playback: population refresh, chase overlay without restarting the timeline.
	var heard: Array = []
	var on_change := func(ids: Array[StringName]) -> void: heard.append(ids)
	Audio.music_layers_changed.connect(on_change)
	Audio.population_override = 0
	Audio.set_music_state(&"title")
	ok = _expect(Audio.audible_layers() == [&"title_theme"], "title song plays") and ok
	Audio.set_music_state(&"base")
	ok = _expect(Audio.audible_layers().size() == counts[0], "base at population 0") and ok
	Audio.population_override = 6
	EventBus.resident_joined.emit(&"test_resident")
	await get_tree().process_frame
	ok = _expect(Audio.audible_layers() == Audio.layers_for(&"base", 6), "resident_joined refreshes the base layers") and ok
	Audio.set_music_state(&"field")
	var field_players := Audio.timeline_layers()
	ok = _expect(Audio.audible_layers() == field, "field layers audible") and ok
	ok = _expect(chase.all(func(id: StringName) -> bool: return id in field_players),
		"chase stems already run (silent) with field") and ok
	Audio.chase_active = true
	Audio.refresh_music()
	ok = _expect(Audio.audible_layers() == chase, "chase overlay audible") and ok
	ok = _expect(Audio.timeline_layers() == field_players, "chase does not restart the timeline") and ok
	Audio.chase_active = false
	Audio.region_override = &"city_park"
	Audio.refresh_music()
	var park_players := Audio.timeline_layers()
	ok = _expect(Audio.audible_layers() == [&"field_city_park"], "park song in the park") and ok
	ok = _expect(&"chase_city_park" in park_players and not &"field_flooded_mall" in park_players
		and not &"field_ambient" in park_players, "park timeline runs only the park songs %s" % [park_players]) and ok
	Audio.chase_active = true
	Audio.refresh_music()
	ok = _expect(Audio.audible_layers() == [&"chase_city_park"], "park chase crossfades to the battle song") and ok
	ok = _expect(Audio.timeline_layers() == park_players, "park chase does not restart the timeline") and ok
	Audio.chase_active = false
	Audio.region_override = &""
	Audio.refresh_music()
	EventBus.night_event_started.emit(&"wedding", [])
	ok = _expect(Audio.music_state == &"festival", "wedding night event -> festival music") and ok
	ok = _expect(heard.size() >= 4, "music_layers_changed emitted on each change (%d)" % heard.size()) and ok
	Audio.music_layers_changed.disconnect(on_change)

	# Monster family events (Lane B calls Audio.play(&"monster_<family>_<action>", position)).
	for fam in FAMILIES:
		for act in ACTIONS:
			var eid := StringName("monster_%s_%s" % [fam, act])
			var ev := Audio.get_event(eid)
			ok = _expect(ev != null and ev.id == eid, "event %s exists" % eid) and ok
			if ev != null:
				ok = _expect(ev.visual_cue_id != &"" and not ev.caption.is_empty(), "%s has visual cue + caption" % eid) and ok
				ok = _expect(Synth.make(ev.synth).data.size() > 1000, "%s makes a sound" % eid) and ok
	for act in ACTIONS:
		var ev := Audio.get_event(StringName("monster_none_%s" % act))
		ok = _expect(ev != null and ev.visual_cue_id != &"", "unknown family falls back for %s" % act) and ok
	ok = _expect(Audio.get_event(&"monster_green_chase").priority == AudioEventDef.Priority.WARNING,
		"chase cue is a warning") and ok
	var played: Array = []
	var on_play := func(ev: AudioEventDef, _pos: Vector3) -> void: played.append(ev.id)
	Audio.sound_played.connect(on_play)
	Audio.play(&"monster_light_attack", Vector3(2, 0, 2))
	Audio.sound_played.disconnect(on_play)
	ok = _expect(played == [&"monster_light_attack"], "sound_played reports the event") and ok

	Audio.population_override = -1
	Audio.set_music_state(&"")
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
