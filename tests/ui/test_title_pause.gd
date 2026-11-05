extends Node
## D-19: title (continue / new game with protect items / load), pause (system list, suspend on
## quit in the field), loading transitions (출격·귀환·쓰러짐) and the ending card.
## Uses a throwaway save folder and settings file; restores every save provider afterwards.

const TEST_SAVES := "user://test_title_pause_saves"
const TEST_SETTINGS := "user://test_title_pause_settings.cfg"

var _backup := {}
var _flow_before: Enums.FlowState


func run() -> bool:
	for key: StringName in SaveSystem._providers:
		_backup[key] = SaveSystem._providers[key].save_data().duplicate(true)
	_flow_before = GameState.flow_state
	var old_dir := SaveSystem.save_dir
	var old_slot := SaveSystem.current_slot
	var old_settings := Settings.path
	var old_result := SceneRouter.last_sortie_result
	SaveSystem.save_dir = TEST_SAVES
	Settings.path = TEST_SETTINGS
	_wipe()
	UI.close_all()
	var ok := true
	ok = _test_registered() and ok
	ok = await _test_title_rows() and ok
	ok = _test_protect() and ok
	ok = await _test_new_game() and ok
	ok = await _test_pause() and ok
	ok = await _test_loading() and ok
	ok = await _test_ending() and ok
	UI.close_all()
	for key: StringName in _backup:
		SaveSystem._providers[key].load_data(_backup[key])
	GameState.flow_state = _flow_before
	UI._last_flow = _flow_before
	SceneRouter.last_sortie_result = old_result
	get_tree().paused = false
	_wipe()
	SaveSystem.save_dir = old_dir
	SaveSystem.current_slot = old_slot
	Settings.path = old_settings
	DirAccess.remove_absolute(TEST_SETTINGS)
	return ok


func _test_registered() -> bool:
	var ok := true
	for id: StringName in [&"title", &"pause", &"pause_menu", &"loading", &"ending"]:
		ok = _expect(UI.has_screen(id), "screen %s registered" % id) and ok
	ok = _expect(UI.FLOW_SCREENS.get(Enums.FlowState.TITLE) == &"title", "TITLE opens the title screen") and ok
	return ok


func _test_title_rows() -> bool:
	UI.open(&"title")
	await get_tree().process_frame
	var s := UI.get_screen(&"title") as TitleScreen
	var ok := _expect(s != null, "title opens")
	if s == null:
		return false
	ok = _expect(s.list.row(&"continue").disabled, "no save: continue disabled") and ok
	ok = _expect(s.list.row(&"load").disabled, "no save: load disabled") and ok
	ok = _expect(not s.list.row(&"new").disabled, "new game enabled") and ok
	ok = _expect(s.list.row(&"settings").disabled == not UI.has_screen(&"settings"),
		"settings row follows UI.has_screen") and ok
	ok = _expect(s.list.row(&"access").disabled == not UI.has_screen(&"accessibility_quick"),
		"accessibility row follows UI.has_screen") and ok
	ok = _expect(s.current == &"new", "first enabled row (new game) is focused: %s" % s.current) and ok
	# A save in slot 2 enables continue and load.
	var day := GameState.day
	GameState.day = 7
	SaveSystem.save_slot(1)
	GameState.day = day
	UI.close(&"title")
	UI.open(&"title")
	await get_tree().process_frame
	s = UI.get_screen(&"title") as TitleScreen
	var ct := TitleScreen.continue_target()
	ok = _expect(ct.kind == &"slot" and ct.slot == 1, "continue loads the latest slot %s" % ct) and ok
	ok = _expect(not s.list.row(&"continue").disabled, "save: continue enabled") and ok
	ok = _expect(not s.list.row(&"load").disabled, "save: load enabled") and ok
	# The suspend file wins over slots.
	SaveSystem.save_suspend()
	ok = _expect(TitleScreen.continue_target().kind == &"suspend", "suspend save is continued first") and ok
	SaveSystem.load_suspend()  # deletes the file again
	UI.close(&"title")
	return ok


func _test_protect() -> bool:
	var s := TitleScreen.new()
	var ok := true
	s.new_preset = &"normal"
	s._reset_new_game()
	ok = _expect(s.protect_overrides().is_empty(), "normal preset: no overrides") and ok
	s.protect[&"keep_bag_on_down"] = true
	var o := s.protect_overrides()
	ok = _expect(o.size() == 1 and o.get(&"keep_bag_on_down") == true, "one protect item -> one override %s" % o) and ok
	ok = _expect(s.protect_value(&"strand_days", true) == Settings.PRESETS[&"story"][&"strand_days"],
		"protect on = story value") and ok
	s.new_preset = &"story"
	s._reset_new_game()
	ok = _expect(s.protect.values().all(func(v): return v == true), "story preset: every protect item on") and ok
	ok = _expect(s.protect_overrides().is_empty(), "story preset: no overrides") and ok
	s.protect[&"strand_days"] = false
	ok = _expect(s.protect_overrides().get(&"strand_days") == Settings.DEFAULTS[&"strand_days"],
		"story with strand off -> default strand days") and ok
	s.free()
	return ok


func _test_new_game() -> bool:
	GameState.flow_state = Enums.FlowState.TITLE
	UI._last_flow = Enums.FlowState.TITLE
	UI.open(&"title")
	await get_tree().process_frame
	var s := UI.get_screen(&"title") as TitleScreen
	s.new_slot = 2
	s.new_preset = &"normal"
	s._reset_new_game()
	s.new_slot = 2
	s.protect[&"keep_bag_on_down"] = true
	var ok := _expect(s.start_new_game(), "start_new_game from the title")
	await get_tree().process_frame
	ok = _expect(GameState.flow_state == Enums.FlowState.BASE_MORNING, "new game reaches the morning") and ok
	ok = _expect(SaveSystem.current_slot == 2 and SaveSystem.has_slot(2), "new game saved in slot 3") and ok
	ok = _expect(Settings.get_value(&"keep_bag_on_down") == true, "protect item applied") and ok
	ok = _expect(Settings.get_value(&"monster_mult") == 1.0, "preset applied") and ok
	ok = _expect(not UI.is_open(&"title"), "leaving TITLE closes the title") and ok
	var l := UI.get_screen(&"loading") as LoadingScreen
	ok = _expect(l != null and l.kind == &"load", "title -> game shows the loading card") and ok
	UI.close_all()
	return ok


func _test_pause() -> bool:
	GameState.flow_state = Enums.FlowState.BASE_MORNING
	UI.open(&"pause")
	await get_tree().process_frame
	var p := UI.get_screen(&"pause") as PauseScreen
	var ok := _expect(p != null and get_tree().paused, "pause opens and pauses")
	if p == null:
		return false
	ok = _expect(p.list.ids() == [&"resume", &"settings", &"journal", &"title", &"quit"], "system list %s" % [p.list.ids()]) and ok
	ok = _expect(p.list.row(&"journal").disabled == not UI.has_screen(&"journal"), "journal row follows UI.has_screen") and ok
	ok = _expect(p.info_rows()[0][1] == "기지", "base location row") and ok
	p.list.row(&"resume").pressed.emit()
	await get_tree().process_frame
	ok = _expect(not UI.is_open(&"pause") and not get_tree().paused, "계속하기 closes and unpauses") and ok
	# The contract id A's FlowPrompts opens.
	UI.open(&"pause_menu")
	await get_tree().process_frame
	ok = _expect(UI.get_screen(&"pause_menu") is PauseScreen, "pause_menu opens the same screen") and ok
	UI.close(&"pause_menu")
	# Field: leaving writes the suspend save and returns to the title.
	GameState.flow_state = Enums.FlowState.FIELD
	UI._last_flow = Enums.FlowState.FIELD
	UI.open(&"pause")
	await get_tree().process_frame
	p = UI.get_screen(&"pause") as PauseScreen
	ok = _expect(p.in_field() and p.leave_note().contains("중단 저장"), "field pause explains the suspend save") and ok
	p.list.row(&"title").pressed.emit()
	await get_tree().process_frame
	ok = _expect(SaveSystem.has_suspend(), "quit to title in the field writes the suspend save") and ok
	ok = _expect(GameState.flow_state == Enums.FlowState.TITLE and UI.is_open(&"title"), "back on the title") and ok
	ok = _expect(not UI.is_open(&"pause") and not get_tree().paused, "pause closed") and ok
	DirAccess.remove_absolute(SaveSystem._suspend_path())
	UI.close_all()
	return ok


func _test_loading() -> bool:
	var S := Enums.FlowState
	var ok := true
	ok = _expect(LoadingScreen.transition_for(S.SORTIE_PREP, S.FIELD).kind == &"sortie", "prep -> field: sortie") and ok
	SceneRouter.last_sortie_result = {"downed": false}
	ok = _expect(LoadingScreen.transition_for(S.FIELD, S.RESULT).kind == &"return", "field -> result: return") and ok
	SceneRouter.last_sortie_result = {"downed": true}
	ok = _expect(LoadingScreen.transition_for(S.FIELD, S.RESULT).kind == &"down", "downed: down") and ok
	ok = _expect(LoadingScreen.transition_for(S.FIELD, S.BASE_DAY_RAID).kind == &"return", "emergency return") and ok
	ok = _expect(LoadingScreen.transition_for(S.BASE_MORNING, S.SORTIE_PREP).is_empty(), "no card inside the base") and ok
	ok = _expect(LoadingScreen.transition_for(S.FIELD, S.TITLE).is_empty(), "no card when quitting to the title") and ok
	# Flow-driven: the card opens above the result screen and learns the region from sortie_started.
	UI._last_flow = S.SORTIE_PREP
	UI._on_flow_state_changed(S.FIELD)
	UI._on_sortie_started({"region_id": &"flooded_mall"})
	var l := UI.get_screen(&"loading") as LoadingScreen
	ok = _expect(l != null and l.line.contains("침수 상가"), "sortie card names the region: %s" % (l.line if l else "")) and ok
	UI.close_all()
	UI._last_flow = S.FIELD
	UI._on_flow_state_changed(S.RESULT)
	ok = _expect(UI.top() == &"loading" and UI.is_open(&"result"), "down card on top of the result screen %s" % [UI.stack_ids()]) and ok
	ok = _expect((UI.get_screen(&"loading") as LoadingScreen).kind == &"down", "down card kind") and ok
	ok = _expect(not (UI.get_screen(&"loading") as LoadingScreen).tip.is_empty(), "loading shows a tip") and ok
	UI.close_all()
	UI._last_flow = _flow_before
	# Auto close after its duration.
	UI.open(&"loading", {"kind": &"return", "duration": 0.05})
	await get_tree().create_timer(0.6, true, false, true).timeout
	ok = _expect(not UI.is_open(&"loading"), "loading closes by itself") and ok
	UI.close_all()
	return ok


func _test_ending() -> bool:
	GameState.flow_state = Enums.FlowState.TITLE
	var cards := [
		{"resident_id": &"a", "name": "가", "status": &"active", "lines": ["가는 남았다."]},
		{"resident_id": &"b", "name": "나", "status": &"missing", "lines": ["나는 돌아오지 않았다."]},
		{"resident_id": &"c", "name": "다", "status": &"dead", "lines": ["다를 잃었다."]},
	]
	UI.open(&"ending", {"ending": Enums.EndingChoice.LEAVE, "cards": cards})
	await get_tree().process_frame
	var e := UI.get_screen(&"ending") as EndingScreen
	var ok := _expect(e != null and e.cards.size() == 3 and e.index == 0, "ending opens with the cards")
	if e == null:
		return false
	ok = _expect(e.status_counts() == {&"active": 1, &"missing": 1, &"dead": 1}, "status counts %s" % e.status_counts()) and ok
	e.step(1)
	ok = _expect(e.index == 1 and not e.is_last(), "next card") and ok
	e.step(5)
	ok = _expect(e.is_last(), "clamped to the last card") and ok
	e.step(-9)
	ok = _expect(e.index == 0, "clamped to the first card") and ok
	e.index = 2
	e.finish()
	await get_tree().process_frame
	ok = _expect(not UI.is_open(&"ending"), "finish closes the ending on the title") and ok
	# Without cards it asks the journal.
	UI.open(&"ending", {"ending": Enums.EndingChoice.STAY})
	await get_tree().process_frame
	ok = _expect(UI.get_screen(&"ending") != null, "ending opens from Journal.epilogue") and ok
	UI.close_all()
	return ok


func _wipe() -> void:
	for s in SaveSystem.SLOT_COUNT:
		SaveSystem.delete_slot(s)
	if SaveSystem.has_suspend():
		DirAccess.remove_absolute(SaveSystem._suspend_path())


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
