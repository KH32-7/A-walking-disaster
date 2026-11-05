extends Node
## D-11: audio events load (20+), unknown gunshot ids fall back, synth makes streams, music state, ambience loops.


func run() -> bool:
	var ok := true
	ok = _expect(Audio.events.size() >= 20, "at least 20 audio events (%d)" % Audio.events.size()) and ok
	ok = _expect(Audio.get_event(&"gunshot_flare_gun") == Audio.events[&"gunshot_default"],
		"unknown gunshot_* falls back to gunshot_default") and ok
	# Every gun class weapon has its own shot; pump and bolt guns have their own reload, the rest share one.
	for def in [&"pistol", &"smg", &"rifle", &"shotgun", &"sniper_rifle"]:
		ok = _expect(Audio.events.has(StringName("gunshot_%s" % def)), "gunshot_%s exists" % def) and ok
	ok = _expect(WeaponHolder.reload_event(&"shotgun") == &"reload_shotgun"
		and WeaponHolder.reload_event(&"sniper_rifle") == &"reload_sniper_rifle"
		and WeaponHolder.reload_event(&"pistol") == &"reload", "reload sound per gun, shared fallback") and ok
	for id in [&"gunshot_pistol", &"reload", &"dry_fire",&"swing_blade", &"swing_blunt", &"block", &"perfect_block", &"guard_break"]:
		ok = _expect(Audio.get_event(id) != null, "event %s used by Lane B exists" % id) and ok
	ok = _expect(Synth.make(&"shot_heavy").data.size() > 1000, "synth builds a stream") and ok
	Audio.play(&"ui_click")
	Audio.play(&"gunshot_rifle", Vector3(1, 0, 1))
	Audio.set_music_state(&"base")
	ok = _expect(Audio.music_state == &"base", "music state set") and ok
	for b in Audio.BUSES:
		ok = _expect(AudioServer.get_bus_index(b) >= 0, "bus %s exists" % b) and ok
	# Ambience loops: birds on base days, rain in any state while raining, nothing on the title.
	ok = _expect(Audio.ambience_for(&"base", false) == [&"amb_base_school"], "base ambience") and ok
	ok = _expect(Audio.ambience_for(&"field", false).is_empty(), "no field ambience on a dry day") and ok
	ok = _expect(&"amb_rain" in Audio.ambience_for(&"field", true) and &"amb_rain" in Audio.ambience_for(&"base", true),
		"rain ambience while raining") and ok
	ok = _expect(Audio.ambience_for(&"", true).is_empty(), "no ambience on the title") and ok
	for id in Audio.AMBIENCE:
		ok = _expect(Audio.get_event(id) != null and not Audio.get_event(id).stream.is_empty(), "ambience %s has a file" % id) and ok
	Audio.play(&"amb_rain")  # ignored: loops are started by refresh_ambience()
	Audio.set_music_state(&"")
	ok = _expect(Audio.audible_ambience().is_empty(), "ambience stops on the title") and ok
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
