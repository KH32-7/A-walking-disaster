extends Node
## D-04: field HUD draws the state contract, follows the flow state, feeds rewards and hints.

const Fake := preload("res://ui/_preview/fake_field_state.gd")


func run() -> bool:
	var hud := FieldHud.new()
	hud.auto_bind = false
	add_child(hud)
	await get_tree().process_frame
	var ok := true
	hud.set_state(Fake.make(0.0))
	ok = _expect(hud._weapons.get_child_count() == 3, "2 weapons + ammo row (%d)" % hud._weapons.get_child_count()) and ok
	ok = _expect(hud._quick.get_child_count() == 4, "4 consumable slots") and ok
	ok = _expect(hud._objectives.get_child_count() == 4, "header + 3 objectives") and ok
	ok = _expect(hud._timer.text == "03:42", "dusk timer %s" % hud._timer.text) and ok
	ok = _expect(absf(hud._hp.value - 0.86) < 0.001, "hp ratio %f" % hud._hp.value) and ok
	var s := Fake.make(0.0)
	s.hp = 10.0
	s.dusk_left_sec = 90.0
	hud.set_state(s)
	ok = _expect(hud._hp.fill_color == UiTokens.DANGER, "low hp turns the bar red") and ok
	ok = _expect(hud._timer.get_theme_color(&"font_color") == UiTokens.WARN, "dusk under 3 min warns") and ok
	for i in 6:
		hud.push_reward("보상 %d" % i, 10)
	ok = _expect(hud.feed_count() <= FieldHud.FEED_MAX, "feed keeps at most %d lines" % FieldHud.FEED_MAX) and ok
	EventBus.notification_posted.emit("마물이 몰려옵니다", &"danger")
	ok = _expect(hud._hint.visible and hud._hint_body.text == "마물이 몰려옵니다", "danger notice shows a hint card") and ok
	hud.queue_free()
	# UI shows the HUD only in the field
	GameState.set_flow_state(Enums.FlowState.FIELD)
	ok = _expect(UI.field_hud != null and UI.field_hud.visible, "HUD visible in FIELD") and ok
	GameState.set_flow_state(Enums.FlowState.BASE_MORNING)
	ok = _expect(not UI.field_hud.visible, "HUD hidden in the base") and ok
	GameState.set_flow_state(Enums.FlowState.TITLE)
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
