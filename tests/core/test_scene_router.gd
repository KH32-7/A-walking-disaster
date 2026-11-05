extends RefCounted
## SceneRouter (A-05): three full days with debug steps only (empty world), phase_changed exactly once
## per phase change, sortie / evening signals, stay-at-base branch, refused transitions, autosave
## points, load returns to prep. Uses throwaway save and settings locations.

const TEST_SAVES := "user://test_router_saves"
const TEST_SETTINGS := "user://test_router_settings.cfg"

var _phases: Array = []
var _flows: Array = []
var _counts := {}
var _backup := {}
var _old := {}


func run() -> bool:
	_old = {"save_dir": SaveSystem.save_dir, "settings_path": Settings.path, "settings": Settings.values.duplicate(),
		"autosave": SaveSystem.autosave_enabled, "slot": SaveSystem.current_slot}
	for key: StringName in SaveSystem._providers:
		_backup[key] = SaveSystem._providers[key].save_data().duplicate(true)
	var flow_before := GameState.flow_state
	SaveSystem.save_dir = TEST_SAVES
	Settings.path = TEST_SETTINGS
	SaveSystem.autosave_enabled = true
	_wipe()

	var on_phase := func(p): _phases.append(p)
	var on_flow := func(s): _flows.append(s)
	var counters := {}
	for sig in [&"sortie_started", &"sortie_ended", &"evening_settled", &"day_started", &"game_saved"]:
		counters[sig] = func(_a = null): _counts[sig] = _counts.get(sig, 0) + 1
		EventBus.connect(sig, counters[sig])
	EventBus.phase_changed.connect(on_phase)
	EventBus.flow_state_changed.connect(on_flow)

	var ok := _check_three_days() and _check_refused() and _check_stay_branch()
	ok = ok and await _check_load_to_prep()
	ok = ok and _check_merge_loot()

	EventBus.phase_changed.disconnect(on_phase)
	EventBus.flow_state_changed.disconnect(on_flow)
	for sig: StringName in counters:
		EventBus.disconnect(sig, counters[sig])
	for key: StringName in _backup:
		SaveSystem._providers[key].load_data(_backup[key])
	GameState.flow_state = flow_before
	_wipe()
	SaveSystem.save_dir = _old["save_dir"]
	SaveSystem.autosave_enabled = _old["autosave"]
	SaveSystem.current_slot = _old["slot"]
	Settings.path = _old["settings_path"]
	Settings.values = _old["settings"]
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _to_title() -> void:
	SaveSystem.reset_all()
	GameState.flow_state = Enums.FlowState.TITLE
	_phases.clear()
	_flows.clear()
	_counts.clear()


func _check_three_days() -> bool:
	_to_title()
	var steps := 0
	while GameState.day < 4 and steps < 100:
		var phase_before := GameState.phase
		var phases_before := _phases.size()
		if not SceneRouter.advance():
			return _expect(false, "advance failed at %s" % Enums.FlowState.keys()[GameState.flow_state])
		var emitted := _phases.size() - phases_before
		# Exactly one phase_changed when the phase moved, none otherwise.
		var expected := 0 if GameState.phase == phase_before else 1
		if emitted != expected:
			return _expect(false, "step %d (%s): %d phase_changed, expected %d" % [steps,
				Enums.FlowState.keys()[GameState.flow_state], emitted, expected])
		steps += 1
	return _expect(GameState.day == 4 and GameState.flow_state == Enums.FlowState.BASE_MORNING,
			"ended on day %d in %s" % [GameState.day, Enums.FlowState.keys()[GameState.flow_state]]) \
		and _expect(_counts.get(&"sortie_started", 0) == 3 and _counts.get(&"sortie_ended", 0) == 3, "sorties %s" % _counts) \
		and _expect(_counts.get(&"evening_settled", 0) == 3, "evenings %s" % _counts) \
		and _expect(_counts.get(&"day_started", 0) == 4, "day_started %s (days 1-4)" % _counts) \
		and _expect(_counts.get(&"game_saved", 0) == 4 * 1 + 3 * 2, "autosaves %s" % _counts) \
		and _expect(SceneRouter.last_sortie_result.get("extracted", false), "last sortie not extracted") \
		and _expect(SceneRouter.last_evening_report.has("discarded"), "evening report without discarded")


func _check_refused() -> bool:
	# Now in BASE_MORNING.
	return _expect(not SceneRouter.finish_night(), "finish_night from morning") \
		and _expect(not SceneRouter.go_to_field({}), "go_to_field without prep") \
		and _expect(GameState.flow_state == Enums.FlowState.BASE_MORNING, "refusal changed the state")


func _check_stay_branch() -> bool:
	var day := GameState.day
	var ok := _expect(SceneRouter.stay_at_base() and SceneRouter.stayed_today, "stay_at_base") \
		and _expect(GameState.phase == Enums.Phase.STAY, "stay phase") \
		and _expect(SceneRouter.start_day_raid({"raid_id": &"r1"}) \
			and GameState.flow_state == Enums.FlowState.BASE_DAY_RAID, "day raid while staying") \
		and _expect(SceneRouter.end_day_raid() and GameState.flow_state == Enums.FlowState.EVENING, "day raid -> evening")
	ok = _expect(SceneRouter.confirm_evening() and SceneRouter.finish_night(), "night") and ok
	return ok and _expect(GameState.day == day + 1 and not SceneRouter.stayed_today, "stay flag not reset")


func _check_load_to_prep() -> bool:
	# Morning autosave -> prep -> field autosaves as SORTIE_PREP; loading returns to prep.
	var ok := SceneRouter.open_sortie_prep() and SceneRouter.go_to_field({"region_id": &"debug_region"})
	var slot := SaveSystem.current_slot
	EventBus.player_downed.emit()  # the router finishes at the end of the frame (after Lane B's handlers)
	ok = _expect(GameState.flow_state == Enums.FlowState.FIELD, "downed finished before Lane B's handlers ran") and ok
	await Engine.get_main_loop().process_frame
	ok = _expect(ok and GameState.flow_state == Enums.FlowState.RESULT
		and not SceneRouter.last_sortie_result["extracted"], "downed -> result") and ok
	var loaded := SceneRouter.load_game(slot)
	return ok and _expect(loaded and GameState.flow_state == Enums.FlowState.RESULT, "load after result: %s"
		% Enums.FlowState.keys()[GameState.flow_state])


func _check_merge_loot() -> bool:
	var merged := SceneRouter._merge_loot(
		{"resources": {&"wood": 5}, "discarded": {&"wood": 2}, "items": [&"it_1"]},
		{"resources": {&"wood": 1, &"parts": 3}, "discarded": {}, "items": [&"it_1", &"it_2"]})
	var r := SceneRouter.last_sortie_result
	return _expect(merged["resources"] == {&"wood": 6, &"parts": 3} and merged["discarded"] == {&"wood": 2}
			and merged["items"] == [&"it_1", &"it_2"], "merge_loot %s" % merged) 		and _expect(r.has("downed") and r.has("kills") and r.has("rescued_profiles") and r.has("down")
			and r["loot"].has("resources"), "result keys %s" % [r.keys()])


func _wipe() -> void:
	DirAccess.remove_absolute(TEST_SETTINGS)
	var dir := DirAccess.open(TEST_SAVES)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(TEST_SAVES)
