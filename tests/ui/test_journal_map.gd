extends Node
## D-16: survival journal (days / people / recordings / quests), field map, notice toast, radio voice.
## Called by tests/run_tests.gd. Restores Journal, Quests, GameState and FieldState afterwards.


func run() -> bool:
	var snap := {"journal": JSON.from_native(Journal.save_data()), "quests": JSON.from_native(Quests.save_data()),
		"game": JSON.from_native(GameState.save_data())}
	var lost: Array = FieldState.lost_gear.duplicate(true)
	var region := FieldState.region_id
	var ok := true
	ok = await _test_journal_days() and ok
	ok = await _test_journal_people() and ok
	ok = await _test_journal_recordings() and ok
	ok = await _test_quest_log() and ok
	ok = _test_explore() and ok
	ok = await _test_map() and ok
	ok = await _test_notice_toast() and ok
	ok = _test_radio_voice() and ok
	UI.close_all()
	await get_tree().process_frame
	ok = _expect(not get_tree().paused, "closing the journal unpauses") and ok
	Journal.load_data(JSON.to_native(snap.journal))
	Quests.load_data(JSON.to_native(snap.quests))
	GameState.load_data(JSON.to_native(snap.game))
	FieldState.lost_gear = lost
	FieldState.region_id = region
	return ok


func _setup_journal() -> void:
	Journal.load_data({})
	GameState.day = 5
	Journal.record(&"rescued", {"resident_id": &"t_elder", "name": "테스트 할머니", "day": 2})
	Journal.record(&"friend", {"resident_id": &"t_elder", "name": "테스트 할머니", "other_id": &"t_kid",
		"other": "테스트 아이", "day": 4})
	Journal.record(&"raid_win", {"day": 4})


func _test_journal_days() -> bool:
	_setup_journal()
	var ok := _expect(UI.has_screen(&"journal"), "journal screen registered (base menu J)")
	UI.open(&"journal")
	await get_tree().process_frame
	var s := UI.get_screen(&"journal") as JournalScreen
	ok = _expect(s != null and UI.top() == &"journal", "journal opens") and ok
	ok = _expect(get_tree().paused, "the journal pauses the game") and ok
	if s == null:
		return false
	ok = _expect(Array(s.day_list()) == [5, 4, 2], "days newest first, today included: %s" % [s.day_list()]) and ok
	ok = _expect(s._rows.size() == 3 and s._day == 5, "one row per day, today selected") and ok
	s.move_selection(1)
	ok = _expect(s._day == 4, "↓ picks the day below") and ok
	ok = _expect(_page_text(s).contains("테스트 할머니"), "the page shows the day's journal lines") and ok
	Journal.record(&"building_completed", {"building": "침상", "day": 4})
	await get_tree().process_frame
	ok = _expect(_page_text(s).contains("침상"), "journal_entry_added redraws the open page") and ok
	return ok


func _test_journal_people() -> bool:
	var s := UI.get_screen(&"journal") as JournalScreen
	s.open_with({"tab": &"people"})
	await get_tree().process_frame
	var ok := _expect(s._rows.size() == Journal.people().size() and s._rows.size() >= 2, "one row per person")
	s.open_with({"resident_id": &"t_kid"})
	ok = _expect(_page_text(s).contains("테스트 아이"), "a person's page lists their lines") and ok
	ok = _expect(_list_text(s).contains("함께 지내요"), "status is written out, not colour only") and ok
	return ok


func _test_journal_recordings() -> bool:
	var s := UI.get_screen(&"journal") as JournalScreen
	s.open_with({"tab": &"recordings", "recordings": []})
	await get_tree().process_frame
	var ok := _expect(_page_text(s).contains("녹음기"), "empty recordings tab explains where they come from")
	s.open_with({"recordings": [{"id": &"r1", "speaker": "경비원", "text": "남쪽으로 가.", "place": "차고지", "day": 3}]})
	ok = _expect(s._rows.size() == 1 and _page_text(s).contains("남쪽으로 가."), "a recording's subtitle is readable") and ok
	return ok


func _test_quest_log() -> bool:
	Quests.load_data({})
	GameState.day = 5
	Quests.start(&"main_01_left_behind")
	Quests.advance(&"main_01_left_behind", &"visit_mall", 1)
	var s := UI.get_screen(&"journal") as JournalScreen
	s.open_with({"tab": &"quests"})
	await get_tree().process_frame
	var checks := s.find_children("*", "CheckMark", true, false)
	var ok := _expect(checks.size() == 2, "one checkbox per goal (%d)" % checks.size())
	var done := checks.filter(func(c: CheckMark) -> bool: return c.done)
	ok = _expect(done.size() == 1, "the visited goal is ticked") and ok
	var rewards := JournalScreen.reward_rows(&"main_01_left_behind")
	ok = _expect(rewards.size() == 1 and String(rewards[0][1]) == "×10", "rewards come from QuestDef (wood ×10, flags hidden)") and ok
	ok = _expect(_page_text(s).contains("남겨진 사람들") and _page_text(s).contains("방송실 지기"),
		"quest card shows title and giver") and ok
	ok = _expect(JournalScreen._days_left_text(0).begins_with("▲"), "last day gets a ▲, not colour only") and ok
	UI.close(&"journal")
	return ok


func _test_explore() -> bool:
	var e := FieldExplore.new()
	e.reveal(Vector3(10, 0, 10), 8.0)
	var ok := _expect(e.is_seen(Vector3(12, 0, 9)) and not e.is_seen(Vector3(40, 0, 40)), "explore remembers the area around a point")
	e.clear()
	ok = _expect(not e.is_seen(Vector3(10, 0, 10)), "clear() forgets the area") and ok
	e.free()
	return ok


func _test_map() -> bool:
	Quests.load_data({})
	Quests.start(&"rumor_bus_stop_supplies")
	FieldState.region_id = &"flooded_mall"
	FieldState.lost_gear = []
	var world := Node3D.new()
	add_child(world)
	for i in 2:
		var ex := (load("res://field/markers/extract_point.tscn") as PackedScene).instantiate() as ExtractPoint
		ex.id = StringName("test_exit_%d" % i)
		world.add_child(ex)
		ex.position = Vector3(-40 + 80 * i, 0, 30)
	var rec := (load("res://field/markers/recording.tscn") as PackedScene).instantiate() as Recording
	rec.recording_id = &"rec_test"
	world.add_child(rec)
	rec.position = Vector3(0, 0, -30)
	var spot := Marker3D.new()
	spot.name = "bus_stop"
	spot.add_to_group(FieldMarker.GROUP_ALL)
	world.add_child(spot)
	spot.position = Vector3(20, 0, 0)
	var explore := FieldExplore.new()
	add_child(explore)
	var ok := _expect(UI.has_screen(&"map"), "map screen registered (M)")
	UI.open(&"map", {"region_id": &"flooded_mall", "explore": explore})
	await get_tree().process_frame
	var s := UI.get_screen(&"map") as MapScreen
	ok = _expect(s != null and not get_tree().paused, "map opens without pausing the field") and ok
	if s != null:
		var kinds: Array = s.data.marks.map(func(m: Dictionary) -> StringName: return m.kind)
		ok = _expect(kinds.count(&"extract") == 2, "both exits drawn (no ExtractionManager = every candidate)") and ok
		ok = _expect(kinds.count(&"objective") == 1, "a quest goal with a marker node is drawn") and ok
		ok = _expect(not &"recording" in kinds, "recorders stay hidden until their spot is explored") and ok
		explore.reveal(rec.global_position)
		s.open_with({})
		kinds = s.data.marks.map(func(m: Dictionary) -> StringName: return m.kind)
		ok = _expect(&"recording" in kinds, "an explored recorder shows up") and ok
		var to := s.map.to_map(Vector3(s.map.bounds.position.x, 0, s.map.bounds.position.y))
		ok = _expect(to.is_equal_approx(Vector2.ZERO), "bounds corner maps to the map corner") and ok
		ok = _expect(s.map.bounds.size.x == s.map.bounds.size.y, "map area is square") and ok
		ok = _expect(s.map.art_mode and s.map.bounds == MapScreen.OVERVIEWS[&"flooded_mall"][1],
			"flooded mall uses its painted overview over the whole layout") and ok
		var landmarks: Array = s.map.place_labels.filter(func(l: Dictionary) -> bool: return l.kind == &"landmark")
		ok = _expect(landmarks.size() == 6, "flooded mall map shows its 6 landmark names") and ok
		ok = _expect(MapScreen.exit_label(ExtractPoint.Type.GENERATOR, "주유소") == "주유소 탈출 · 발전기",
			"exit label names the place and the exit type") and ok
		ok = _expect(MapScreen.place_near(s.map.place_labels, Vector3(55.5, 0, 97.5)) == "하역장",
			"the dock exit is named after the 하역장 landmark") and ok
		ok = _expect(MapScreen.place_near(s.map.place_labels, Vector3(500, 0, 500)) == "",
			"no name far from every place") and ok
	UI.close(&"map")
	world.queue_free()
	explore.queue_free()
	await get_tree().process_frame
	return ok


func _test_notice_toast() -> bool:
	MenuScreen.clear(UI.notice_toast)
	UI.open(&"journal")
	await get_tree().process_frame
	EventBus.notification_posted.emit("테스트 알림", &"warn")
	var ok := _expect(UI.notice_toast.count() == 1, "with the HUD hidden by a screen, the toast shows the notification")
	var text := ""
	for l: Label in UI.notice_toast.find_children("*", "Label", true, false):
		text += l.text
	ok = _expect(text.contains("주의") and text.contains("테스트 알림"), "severity is a word on the toast") and ok
	UI.close(&"journal")
	MenuScreen.clear(UI.notice_toast)
	return ok


func _test_radio_voice() -> bool:
	if not bool(Settings.get_value(&"radio_voice")):
		return true  # the player turned the voice off in their own settings
	EventBus.radio_message.emit(&"broadcaster", "테스트 무전입니다.", 0)
	UI.subtitle.clear()
	var ok := _expect(UI.radio_voice.last_spoken == "테스트 무전입니다.", "radio lines go to the TTS voice when radio_voice is on")
	var a := RadioVoice.clip_path(&"broadcaster", "탄약 부족입니다.")
	ok = _expect(a == RadioVoice.clip_path(&"broadcaster", "탄약 부족입니다."), "same line, same clip path") and ok
	ok = _expect(a != RadioVoice.clip_path(&"broadcaster", "탄약 부족입니다!"), "edited line, different clip path") and ok
	return _expect(a.begins_with("res://assets/audio/voice/broadcaster/") and a.ends_with(".mp3"), "clip path layout") and ok


func _page_text(s: JournalScreen) -> String:
	var out := ""
	for l: Label in s._page.find_children("*", "Label", true, false):
		out += l.text + "\n"
	return out


func _list_text(s: JournalScreen) -> String:
	var out := ""
	for l: Label in s._list.find_children("*", "Label", true, false):
		out += l.text + "\n"
	return out


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
