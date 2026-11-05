extends Node
## D-06 재설계 ②놓기 / ③짓기: BuildPlaceHud follows BuildMode's signals (cursor card words, placed →
## site card, cancelled → back to the list with the same building), and the site card puts residents
## on the construction job. Called by tests/run_tests.gd. Restores Economy, Colony and GameState.


func run() -> bool:
	var snap := {"economy": JSON.from_native(Economy.save_data()), "colony": JSON.from_native(Colony.save_data()),
		"game": JSON.from_native(GameState.save_data())}
	Economy.load_data({})
	Colony.load_data({})
	Economy.set_cap_bonus(5000)
	Economy.apply({&"wood": 100})
	var worker := Colony.add_resident({"id": &"flow_builder", "name": "흐름 일꾼", "age_stage": Enums.AgeStage.ADULT,
		"stats": {&"str": 6}, "access_needs": []})
	var ok := true
	var mode := BuildMode.new()
	add_child(mode)
	mode.def_id = &"lumber_yard"
	UI.show_build_place(mode)
	var hud: BuildPlaceHud = UI.build_place_hud
	ok = _expect(hud != null and hud.get_parent() == UI.hud, "placement overlay goes on the HUD layer") and ok
	mode.preview_info.emit({"ok": true, "reasons": [], "on_grid": true, "node_kind": "나무", "nodes": 6, "radius": 10.0,
		"center": Vector3.ZERO})
	ok = _expect(_label_with(hud, "놓을 수 있어요") != null and _label_with(hud, "나무 6곳") != null,
		"ok spot: words + node count") and ok
	mode.preview_info.emit({"ok": false, "reasons": ["다른 건물과 겹침"], "on_grid": true, "center": Vector3.ZERO})
	await get_tree().process_frame
	ok = _expect(_label_with(hud, "놓을 수 없어요") != null and _label_with(hud, "다른 건물과 겹침") != null,
		"blocked spot: the reason in words") and ok
	# cancel → back to the list with the same building picked
	mode.cancelled.emit()
	await get_tree().process_frame
	ok = _expect(UI.top() == &"build" and UI.get_screen(&"build").get(&"_sel") == &"lumber_yard"
		and UI.get_screen(&"build").get(&"_mode") == &"build", "cancel reopens the build list on the same building") and ok
	UI.close(&"build")
	await get_tree().process_frame
	# placed → site card
	var uid := Colony.place_building(&"lumber_yard", Vector2i(2, 2), 0, &"front_yard", false)
	UI.show_build_place(mode)
	mode.placed.emit(uid)
	await get_tree().process_frame
	var screen := UI.get_screen(&"build")
	ok = _expect(UI.top() == &"build" and screen.get(&"_mode") == &"site" and screen.get(&"_sel_uid") == uid,
		"placing opens the site card for the new site") and ok
	var put := _button(screen.get(&"_detail"), "배정")
	ok = _expect(put != null, "site card lists residents to send") and ok
	if put != null:
		put.pressed.emit()
		ok = _expect(Colony.job_of(worker) == WorkRules.CONSTRUCTION_JOB
			and worker in Colony.get_building(uid)["workers"], "배정 sends the resident to build the site") and ok
	ok = _expect(_button(screen.get(&"_detail"), "이대로 짓기") != null and _button(screen.get(&"_detail"), "현장 옮기기") != null,
		"site card has 이대로 짓기 and 현장 옮기기") and ok
	UI.close(&"build")
	await get_tree().process_frame
	mode.queue_free()
	Economy.load_data(JSON.to_native(snap.economy))
	Colony.load_data(JSON.to_native(snap.colony))
	GameState.load_data(JSON.to_native(snap.game))
	return ok


func _find(root: Node, pred: Callable) -> Node:
	for c in root.get_children():
		if c.is_queued_for_deletion():
			continue
		if pred.call(c):
			return c
		var f := _find(c, pred)
		if f != null:
			return f
	return null


func _button(root: Node, prefix: String) -> Button:
	return _find(root, func(n: Node) -> bool: return n is Button and (n as Button).text.begins_with(prefix)) as Button


func _label_with(root: Node, part: String) -> Label:
	return _find(root, func(n: Node) -> bool: return n is Label and part in (n as Label).text) as Label


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
