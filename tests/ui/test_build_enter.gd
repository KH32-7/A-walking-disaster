extends Node
## Build menu on the real base map: Enter on a picked card, and a second click on the picked card,
## both start ②놓기 (BuildMode active + BuildPlaceHud). Called by tests/run_tests.gd.

const BASE := "res://levels/base/base_school/base_school.tscn"


func run() -> bool:
	var snap := {"economy": JSON.from_native(Economy.save_data()), "colony": JSON.from_native(Colony.save_data())}
	Economy.load_data({})
	Colony.load_data({})
	Economy.set_cap_bonus(500)
	Economy.apply({&"wood": 50, &"stone": 20})
	var base := (load(BASE) as PackedScene).instantiate()
	add_child(base)
	await _frames(5)
	var ok := true
	# 1) Enter
	ok = await _open_pick() and ok
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.physical_keycode = KEY_ENTER
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(4)
	var up := InputEventKey.new()
	up.keycode = KEY_ENTER
	up.physical_keycode = KEY_ENTER
	Input.parse_input_event(up)
	await _frames(4)
	var mode: BuildMode = base.build_mode
	ok = _expect(mode.active and is_instance_valid(UI.build_place_hud) and not UI.is_open(&"build"),
		"Enter on the picked card starts placing (active=%s hud=%s build_open=%s flow=%s)" % [mode.active,
		is_instance_valid(UI.build_place_hud), UI.is_open(&"build"), Enums.FlowState.keys()[GameState.flow_state]]) and ok
	mode.cancel()
	await _frames(3)
	UI.close(&"build")
	await _frames(3)
	# 2) click the picked card again
	ok = await _open_pick() and ok
	var card := _card_of(UI.get_screen(&"build"), &"bonfire")
	ok = _expect(card != null, "bonfire card is on the list") and ok
	if card != null:
		card.pressed.emit()
		await _frames(4)
		ok = _expect(mode.active and is_instance_valid(UI.build_place_hud), "a second click on the picked card starts placing") and ok
	mode.cancel()
	await _frames(3)
	UI.close(&"build")
	base.queue_free()
	await _frames(3)
	Economy.load_data(JSON.to_native(snap.economy))
	Colony.load_data(JSON.to_native(snap.colony))
	return ok


func _open_pick() -> bool:
	UI.open(&"build")
	await _frames(4)
	var screen: Node = UI.get_screen(&"build")
	screen._sel = &"bonfire"
	screen._fill()
	await _frames(2)
	return _expect(UI.is_open(&"build") and Colony.can_build(&"bonfire").ok, "build menu open with 모닥불 picked")


## The card Button showing `def_id` (its tooltip is the description; match by name label).
func _card_of(screen: Node, def_id: StringName) -> Button:
	var want := BaseDB.get_building(def_id).display_name
	for b in screen._list.find_children("*", "Button", true, false):
		for l in b.find_children("*", "Label", true, false):
			if (l as Label).text == want:
				return b
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
