extends Node
## Issue #86: closing a screen with its own key must mark the input handled BEFORE close(),
## because close() removes the node and get_viewport() is null afterwards (SCRIPT ERROR, which
## tools/headless_check.sh treats as a failure). Also #101: region names for the field HUD.


func run() -> bool:
	var ok := true
	ok = await _close_with(&"bag", _key(KEY_TAB), &"_unhandled_input") and ok
	if UI.has_screen(&"map") and InputMap.has_action(&"map"):
		var ev := InputEventAction.new()
		ev.action = &"map"
		ev.pressed = true
		ok = await _close_with(&"map", ev, &"_unhandled_key_input") and ok
	ok = _expect(FieldHud.region_display_name(&"flooded_mall") == "침수 상가", "region id shows as its name") and ok
	ok = _expect(FieldHud.region_display_name(&"no_such_region") == "no_such_region", "unknown region falls back to id") and ok
	UI.close_all()
	return ok


func _close_with(id: StringName, ev: InputEvent, handler: StringName) -> bool:
	UI.close_all()
	UI.open(id)
	await get_tree().process_frame
	var s := UI.get_screen(id)
	if not _expect(s != null, "%s opens" % id):
		return false
	s.call(handler, ev)
	await get_tree().process_frame
	return _expect(not UI.is_open(id), "%s closes with its own key" % id)


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
