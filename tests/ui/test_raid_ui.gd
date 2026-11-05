extends Node
## D-14: raid warning / result / emergency return screens open from the raid signals, the warning
## asks Colony for the prediction and its auto choice goes through Colony.resolve_raid(PLAYED),
## the emergency card answers B-22's EmergencyReturn, a field result waits for the sortie result,
## and the defense HUD moves guards only into free spots during the prep phase.
## Called by tests/run_tests.gd. Restores Economy, Colony and GameState afterwards.

const FAKE_RETURN_SRC := """extends Node
var state := 1
var answered := -1
func _ready() -> void:
	add_to_group(&"field_emergency_return")
func answer(go_back: bool) -> void:
	answered = 1 if go_back else 0
"""


func run() -> bool:
	var snap := {"economy": JSON.from_native(Economy.save_data()), "colony": JSON.from_native(Colony.save_data()),
		"game": JSON.from_native(GameState.save_data())}
	var flow := GameState.flow_state
	UI.close_all()
	UI.raid_flow.auto_open = true  # the runner has no current scene
	var ok := true
	ok = _expect(UI.has_screen(&"raid_warning") and UI.has_screen(&"raid_result") and UI.has_screen(&"emergency_return"),
		"raid screens registered") and ok
	ok = _expect(UI.raid_flow != null and UI.raid_flow.is_inside_tree(), "RaidFlow lives under UI") and ok
	ok = await _test_warning() and ok
	ok = await _test_same_frame() and ok
	ok = await _test_auto_choice() and ok
	ok = await _test_emergency() and ok
	ok = await _test_field_result() and ok
	ok = await _test_result_screen() and ok
	ok = _test_defense_hud() and ok
	ok = _test_hud_flow() and ok
	UI.close_all()
	UI.raid_flow.auto_open = null
	await get_tree().process_frame
	ok = _expect(not get_tree().paused, "closing the raid screens unpauses") and ok
	GameState.flow_state = flow
	UI._on_flow_state_changed(GameState.flow_state)
	Economy.load_data(JSON.to_native(snap.economy))
	Colony.load_data(JSON.to_native(snap.colony))
	GameState.load_data(JSON.to_native(snap.game))
	GameState.flow_state = flow
	return ok


func _raid(id: StringName, time := Enums.RaidTime.NIGHT) -> Dictionary:
	return {"occurs": true, "raid_id": id, "time": time, "type": &"wave", "directions": [&"north", &"east"],
		"strength": 40.0, "target": &"base", "warning_sec": 60.0 if time == Enums.RaidTime.DAY else 0.0,
		"family": Enums.Element.NONE, "notice": &"none", "small": false}


func _test_warning() -> bool:
	GameState.flow_state = Enums.FlowState.NIGHT
	EventBus.raid_warning.emit(_raid(&"test_raid_warn"))
	await get_tree().process_frame
	var s = UI.get_screen(&"raid_warning")
	var ok := _expect(s != null and UI.top() == &"raid_warning", "an unresolved raid opens the warning card")
	if s == null:
		return false
	ok = _expect(s.raid.get("raid_id") == &"test_raid_warn", "warning gets the raid info") and ok
	ok = _expect(s.prediction.has("likely") and s.prediction.has("ratio_min"), "warning shows Colony.predict_raid()") and ok
	var direct: Button = s.get(&"_direct_btn")
	ok = _expect(direct != null and direct.disabled == not RaidFlow.can_direct(),
		"direct defense is only offered when Colony has the C-17 API") and ok
	ok = _expect(get_tree().paused, "the warning pauses the game") and ok
	UI.close(&"raid_warning")
	return ok


## Today Colony / the router resolve the raid in the same frame: only the result opens.
func _test_same_frame() -> bool:
	GameState.flow_state = Enums.FlowState.NIGHT
	EventBus.raid_warning.emit(_raid(&"test_raid_sync"))
	EventBus.raid_resolved.emit({"raid_id": &"test_raid_sync", "day": 6, "time": Enums.RaidTime.NIGHT,
		"mode": Enums.RaidMode.AUTO, "ratio": 1.2, "outcome": Enums.RaidOutcome.WIN, "damage": {},
		"casualties": [], "loot": {}, "summary": ["a", "b", "c"]})
	await get_tree().process_frame
	await get_tree().process_frame
	var ok := _expect(not UI.is_open(&"raid_warning"), "a raid resolved in the same frame skips the warning")
	ok = _expect(UI.is_open(&"raid_result"), "raid_resolved opens the result") and ok
	var r = UI.get_screen(&"raid_result")
	ok = _expect(r != null and r.result.get("raid_id") == &"test_raid_sync", "result screen gets the result") and ok
	UI.close_all()
	return ok


func _test_auto_choice() -> bool:
	Economy.load_data({})
	Colony.load_data({})
	GameState.flow_state = Enums.FlowState.BASE_STAY
	var got := []
	var cb := func(res: Dictionary) -> void: got.append(res)
	EventBus.raid_resolved.connect(cb)
	UI.open(&"raid_warning", {"raid": _raid(&"test_raid_auto", Enums.RaidTime.DAY)})
	await get_tree().process_frame
	var s = UI.get_screen(&"raid_warning")
	var btn: Button = s.get(&"_auto_btn") if s != null else null
	if btn != null:
		btn.pressed.emit()
	EventBus.raid_resolved.disconnect(cb)
	var ok := _expect(not got.is_empty() and int(got[0].get("mode", -1)) == Enums.RaidMode.PLAYED,
		"자동 판정으로 넘기기 resolves through Colony with RaidMode.PLAYED")
	ok = _expect(not UI.is_open(&"raid_warning"), "choosing closes the warning") and ok
	await get_tree().process_frame
	ok = _expect(UI.is_open(&"raid_result"), "and the result follows") and ok
	UI.close_all()
	return ok


func _test_emergency() -> bool:
	GameState.flow_state = Enums.FlowState.FIELD
	var script := GDScript.new()
	script.source_code = FAKE_RETURN_SRC
	script.reload()
	var fake: Node = script.new()
	add_child(fake)
	EventBus.raid_warning.emit(_raid(&"test_raid_field", Enums.RaidTime.DAY))
	await get_tree().process_frame
	var s = UI.get_screen(&"emergency_return")
	var ok := _expect(s != null, "a day raid in the field opens the emergency return card")
	ok = _expect(not UI.is_open(&"raid_warning"), "no base warning card in the field") and ok
	if s != null:
		# The field never pauses (user decision 2026-11-06); the player just stops acting under it.
		ok = _expect(not get_tree().paused and UI.blocks_play(),
				"the emergency choice keeps the field running but blocks play input") and ok
		(s.get(&"_back_btn") as Button).pressed.emit()
	ok = _expect(int(fake.get(&"answered")) == 1, "긴급 귀환 calls EmergencyReturn.answer(true)") and ok
	ok = _expect(not UI.is_open(&"emergency_return"), "answering closes the card") and ok
	fake.set(&"state", 2)  # DECLINED: no second offer
	EventBus.raid_warning.emit(_raid(&"test_raid_field2", Enums.RaidTime.DAY))
	await get_tree().process_frame
	ok = _expect(not UI.is_open(&"emergency_return"), "no card when EmergencyReturn is not offering") and ok
	fake.queue_free()
	UI.close_all()
	return ok


## "계속 탐색": the auto result arrives in the field and shows with the sortie result.
func _test_field_result() -> bool:
	GameState.flow_state = Enums.FlowState.FIELD
	EventBus.raid_resolved.emit({"raid_id": &"test_raid_held", "day": 6, "time": Enums.RaidTime.DAY,
		"mode": Enums.RaidMode.AUTO, "ratio": 0.8, "outcome": Enums.RaidOutcome.NARROW, "damage": {},
		"casualties": [], "loot": {}, "summary": ["x"]})
	await get_tree().process_frame
	var ok := _expect(not UI.is_open(&"raid_result"), "a raid result in the field waits")
	GameState.flow_state = Enums.FlowState.RESULT
	UI.raid_flow._on_flow_state_changed(Enums.FlowState.RESULT)
	await get_tree().process_frame
	var r = UI.get_screen(&"raid_result")
	ok = _expect(r != null and r.result.get("raid_id") == &"test_raid_held", "it opens with the sortie result") and ok
	UI.close_all()
	return ok


func _test_result_screen() -> bool:
	Colony.load_data({})
	var rid := Colony.add_resident({"id": &"test_raid_guard", "name": "테스트 경비", "age_stage": Enums.AgeStage.ADULT,
		"stats": {}, "access_needs": []})
	UI.open(&"raid_result", {"result": {"raid_id": &"r", "day": 7, "time": Enums.RaidTime.NIGHT,
		"mode": Enums.RaidMode.AUTO, "ratio": 0.5, "outcome": Enums.RaidOutcome.LOSS,
		"damage": {"damaged": [], "durability_loss": {}, "resources_lost": {&"wood": 12}},
		"casualties": [{"resident_id": rid, "kind": &"serious"}], "loot": {}, "summary": ["1", "2", "3", "4"]}})
	await get_tree().process_frame
	var r = UI.get_screen(&"raid_result")
	var ok := _expect(r != null, "raid result opens from args")
	if r != null:
		var texts := _texts(r)
		ok = _expect("패배" in " ".join(texts), "outcome word is written (not colour only)") and ok
		ok = _expect("테스트 경비" in " ".join(texts) and "크게 다침" in texts, "casualties list name and kind") and ok
		ok = _expect("−12" in texts, "lost storage shows as given") and ok
	UI.close(&"raid_result")
	return ok


func _test_defense_hud() -> bool:
	var hud := RaidDefenseHud.new()
	hud.auto_bind = false
	add_child(hud)
	var moved := []
	hud.guard_moved.connect(func(id: StringName, spot: StringName) -> void: moved.append([id, spot]))
	hud.set_state({"wave": 1, "waves": 3, "phase": &"prep", "time_left": 12.0,
		"guards": [{"id": &"g1", "name": "가", "spot": &"post"}, {"id": &"g2", "name": "나", "spot": &""}],
		"spots": [{"id": &"post", "name": "초소", "kind": &"post", "cap": 1}, {"id": &"gate", "name": "문", "kind": &"gate", "cap": 2}]})
	var ok := _expect(not hud.move_guard(&"g2", &"post"), "a full spot refuses another guard")
	ok = _expect(hud.move_guard(&"g2", &"gate") and hud.guards_at(&"gate") == [&"g2"], "a guard moves into a free spot") and ok
	ok = _expect(moved.size() == 1 and moved[0] == [&"g2", &"gate"], "guard_moved reports the move") and ok
	hud.select_guard(&"g1")
	hud.spot_clicked(&"gate")
	ok = _expect(hud.guards_at(&"gate").size() == 2, "select + click moves a guard without dragging") and ok
	var st := hud.state.duplicate(true)
	st["phase"] = &"fight"
	hud.set_state(st)
	ok = _expect(not hud.move_guard(&"g1", &""), "guards stay put during a wave") and ok
	ok = _expect(not hud.get(&"_place_panel").visible, "placement panel only shows in the prep phase") and ok
	hud.set_state({})
	ok = _expect(hud.modulate.a == 0.0, "no state = nothing drawn") and ok
	hud.queue_free()
	return ok


func _test_hud_flow() -> bool:
	UI._on_flow_state_changed(Enums.FlowState.BASE_DAY_RAID)
	var ok := _expect(UI.raid_hud != null and UI.raid_hud.visible, "BASE_DAY_RAID shows the defense HUD")
	UI._on_flow_state_changed(Enums.FlowState.BASE_MORNING)
	ok = _expect(not UI.raid_hud.visible, "leaving the raid hides it") and ok
	return ok


func _texts(n: Node) -> Array[String]:
	var out: Array[String] = []
	for c in n.find_children("*", "Label", true, false):
		out.append((c as Label).text)
	return out


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
