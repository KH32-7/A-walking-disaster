extends Node
## D-07: sortie prep / result / evening open with their data and follow the flow state.


func run() -> bool:
	var ok := true
	UI.close_all()
	UI.open(&"result", {"result": {"extracted": true, "xp": 100, "kills": 2,
		"loot": {"resources": {&"scrap": 3}, "items": [], "discarded": {}}}})
	await get_tree().process_frame
	var r = UI.get_screen(&"result")
	ok = _expect(r != null and r.result.get("kills", 0) == 2, "result screen receives args before building") and ok
	UI.close_all()
	UI.open(&"evening", {"report": {"produced": {&"wood": 5}, "consumed": {}, "morale": {}, "events": []}})
	await get_tree().process_frame
	ok = _expect(UI.get_screen(&"evening") != null and UI.get_screen(&"evening").report.produced.wood == 5,
		"evening screen gets the report") and ok
	UI.close_all()
	UI.open(&"sortie_prep")
	await get_tree().process_frame
	var s = UI.get_screen(&"sortie_prep")
	ok = _expect(s != null and s.loadout().region_id == &"flooded_mall", "prep picks the first open region") and ok
	UI.close_all()
	# flow-driven open/close
	UI._on_flow_state_changed(Enums.FlowState.EVENING)
	ok = _expect(UI.is_open(&"evening"), "EVENING opens the evening screen") and ok
	UI._on_flow_state_changed(Enums.FlowState.NIGHT)
	ok = _expect(not UI.is_open(&"evening"), "leaving EVENING closes it") and ok
	UI._on_flow_state_changed(GameState.flow_state)
	UI.close_all()
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
