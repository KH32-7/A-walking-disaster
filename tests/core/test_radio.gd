extends RefCounted
## Radio (A-14): template data, formatting, cooldowns, frequency setting, once-per limits,
## one line per fight, morning broadcast, repeated downs, raid warnings. No LLM anywhere.

var _heard: Array = []
var _saved_freq: Variant
var _saved_game: Dictionary
var _saved_autosave: bool


func run() -> bool:
	_saved_freq = Settings.values[&"ai_radio_frequency"]
	_saved_game = GameState.save_data()
	# day_started / sortie_started below would autosave into the real slots otherwise.
	_saved_autosave = SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	var on_line := func(speaker: StringName, text: String, priority: int):
		_heard.append({"speaker": speaker, "text": text, "priority": priority})
	EventBus.radio_message.connect(on_line)

	var ok := _check_data() and _check_format() and _check_cooldown() and _check_frequency() \
		and _check_once_per() and _check_combat() and _check_morning() and _check_rotation() \
		and _check_repeated_downs() and _check_raid_sign()

	EventBus.radio_message.disconnect(on_line)
	Settings.values[&"ai_radio_frequency"] = _saved_freq
	SaveSystem.autosave_enabled = _saved_autosave
	GameState.load_data(_saved_game)
	_reset()
	Radio.load_data({})
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _reset(freq := 1) -> void:
	# Writes the value directly so the test never touches the real settings file.
	Settings.values[&"ai_radio_frequency"] = freq
	Radio._clock = 1000.0
	Radio._last_spoke.clear()
	Radio._used_sortie.clear()
	Radio._used_day.clear()
	Radio._bags.clear()
	Radio.set_combat(false)
	_heard.clear()


func _check_data() -> bool:
	var ok := _expect(Radio.triggers.size() >= 15, "only %d radio triggers" % Radio.triggers.size())
	for id: StringName in Radio.triggers:
		var trigger: RadioTrigger = Radio.triggers[id]
		ok = _expect(trigger.lines.size() >= 5, "%s has %d lines (design: 5)" % [id, trigger.lines.size()]) and ok
	for id in [&"low_ammo", &"low_health", &"noise_high", &"rescuee_low_health", &"no_progress", &"dusk",
			&"day_raid_hold", &"day_raid_return", &"morning_greeting", &"repeated_downs"]:
		ok = _expect(Radio.triggers.has(id), "missing trigger %s" % id) and ok
	return ok


func _check_format() -> bool:
	_reset()
	Radio.say(&"dusk", {"minutes": 3})
	var text: String = _heard[0]["text"] if not _heard.is_empty() else ""
	return _expect(_heard.size() == 1 and _heard[0]["speaker"] == Radio.BROADCASTER, "dusk not emitted") \
		and _expect(text.contains("3") and not text.contains("{"), "placeholder not filled: %s" % text) \
		and _expect(_heard[0]["priority"] == Radio.triggers[&"dusk"].priority, "priority")


func _check_cooldown() -> bool:
	_reset()
	var first := Radio.say(&"low_ammo")
	Radio._clock += 30.0
	var too_soon := Radio.say(&"low_ammo")
	var other := Radio.say(&"low_health")  # different type is not blocked
	Radio._clock += 31.0
	var later := Radio.say(&"low_ammo")
	return _expect(first and not too_soon and other and later, "cooldown %s %s %s %s" % [first, too_soon, other, later])


func _check_frequency() -> bool:
	_reset(Radio.FREQ_OFF)
	var muted := not Radio.say(&"low_ammo")
	var story := Radio.say(&"morning_quip")
	_reset(Radio.FREQ_OFTEN)
	Radio.say(&"noise_high")
	Radio._clock += 31.0  # half of 60 s
	var often := Radio.say(&"noise_high")
	return _expect(muted, "guidance spoke with radio off") and _expect(story, "story line muted by radio off") \
		and _expect(often, "'often' did not halve the cooldown")


func _check_once_per() -> bool:
	_reset()
	var first := Radio.say(&"dusk", {"minutes": 3})
	Radio._clock += 1000.0
	var second := Radio.say(&"dusk", {"minutes": 3})
	EventBus.sortie_started.emit({"region_id": &"test_region"})
	var next_sortie := Radio.say(&"dusk", {"minutes": 3})
	return _expect(first and not second and next_sortie, "once per sortie %s %s %s" % [first, second, next_sortie])


func _check_combat() -> bool:
	_reset()
	Radio.set_combat(true)
	var one := Radio.say(&"low_ammo")
	var two := Radio.say(&"low_health")
	Radio.set_combat(false)
	Radio.set_combat(true)
	var next_fight := Radio.say(&"noise_high")
	Radio.set_combat(false)
	return _expect(one and not two and next_fight, "one line per fight %s %s %s" % [one, two, next_fight])


func _check_morning() -> bool:
	_reset()
	GameState.weather = Enums.Weather.RAIN
	GameState.day = 4
	EventBus.day_started.emit(4)
	var texts := _heard.map(func(h): return h["text"])
	var rain_lines: Array = Radio.triggers[&"morning_weather_rain"].lines
	var has_rain := texts.any(func(t): return t in rain_lines)
	var has_day := texts.any(func(t): return t.contains("4일째"))
	var count := _heard.size()
	return _expect(count == 3, "morning broadcast lines %d" % count) and _expect(has_rain, "no rain line") \
		and _expect(has_day, "greeting without the day: %s" % [texts])


func _check_rotation() -> bool:
	_reset()
	var trigger: RadioTrigger = Radio.triggers[&"noise_high"]
	var seen := {}
	var last := ""
	for i in trigger.lines.size() * 2:
		var line := Radio._next_line(trigger)
		if line == last:
			return _expect(false, "same line twice in a row: %s" % line)
		last = line
		seen[line] = true
	return _expect(seen.size() == trigger.lines.size(), "rotation used %d of %d lines" % [seen.size(), trigger.lines.size()])


func _check_repeated_downs() -> bool:
	_reset()
	Radio.load_data({})
	for i in Radio.REPEATED_DOWNS:
		EventBus.sortie_started.emit({"region_id": &"flooded_mall"})
		EventBus.player_downed.emit()
	_heard.clear()
	EventBus.sortie_started.emit({"region_id": &"flooded_mall"})
	var advised := _heard.size() == 1 and String(_heard[0]["text"]).contains("flooded_mall")
	_heard.clear()
	EventBus.sortie_started.emit({"region_id": &"flooded_mall"})
	var once := _heard.is_empty()
	var saved := Radio.save_data()
	return _expect(advised, "no repeated-downs advice: %s" % [_heard]) and _expect(once, "advised twice") \
		and _expect(saved["downs"][&"flooded_mall"] == Radio.REPEATED_DOWNS, "downs not saved %s" % saved)


func _check_raid_sign() -> bool:
	_reset()
	GameState.phase = Enums.Phase.MORNING
	EventBus.raid_warning.emit({"time": Enums.RaidTime.NIGHT, "directions": [&"north"]})
	var morning_text: String = _heard[0]["text"] if not _heard.is_empty() else ""
	_heard.clear()
	GameState.phase = Enums.Phase.NIGHT
	EventBus.raid_warning.emit({"time": Enums.RaidTime.NIGHT, "directions": [&"west"]})
	var night_text: String = _heard[0]["text"] if not _heard.is_empty() else ""
	return _expect(morning_text in Radio.triggers[&"raid_sign"].lines.map(func(l): return l.format({"direction": "북쪽"})),
			"morning sign: %s" % morning_text) \
		and _expect(night_text.contains("서쪽"), "night warning: %s" % night_text)
