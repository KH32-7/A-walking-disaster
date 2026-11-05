extends Node
## D-11: audio events load (20+), unknown gunshot ids fall back, synth makes streams, music state.


func run() -> bool:
	var ok := true
	ok = _expect(Audio.events.size() >= 20, "at least 20 audio events (%d)" % Audio.events.size()) and ok
	ok = _expect(Audio.get_event(&"gunshot_sniper_rifle") != null, "gunshot_* falls back to gunshot_default") and ok
	for id in [&"gunshot_pistol", &"reload", &"dry_fire", &"swing_blade", &"swing_blunt", &"block", &"perfect_block", &"guard_break"]:
		ok = _expect(Audio.get_event(id) != null, "event %s used by Lane B exists" % id) and ok
	ok = _expect(Synth.make(&"shot_heavy").data.size() > 1000, "synth builds a stream") and ok
	Audio.play(&"ui_click")
	Audio.play(&"gunshot_rifle", Vector3(1, 0, 1))
	Audio.set_music_state(&"base")
	ok = _expect(Audio.music_state == &"base", "music state set") and ok
	for b in Audio.BUSES:
		ok = _expect(AudioServer.get_bus_index(b) >= 0, "bus %s exists" % b) and ok
	Audio.set_music_state(&"")
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
