extends Node
## Issue #115 (B-19): the field HUD shows a boss name + health bar only while hud_state() has
## "boss", with a tick (shape) at each phase boundary.


func run() -> bool:
	var hud := FieldHud.new()
	hud.auto_bind = false
	add_child(hud)
	await get_tree().process_frame
	var ok := true
	hud.set_state({"hp": 80.0, "hp_max": 100.0})
	ok = _expect(not hud._boss.visible, "no boss key: bar hidden") and ok
	hud.set_state({"hp": 80.0, "hp_max": 100.0,
		"boss": {"name": "고목 거인", "hp": 1500.0, "hp_max": 3000.0, "phase": 1, "phase_count": 2}})
	ok = _expect(hud._boss.visible and hud._boss_name.text == "고목 거인", "boss key: name shown") and ok
	ok = _expect(is_equal_approx(hud._boss_bar.value, 0.5), "bar follows hp / hp_max") and ok
	ok = _expect(hud._boss_bar.ticks.size() == 1 and is_equal_approx(hud._boss_bar.ticks[0], 0.5),
		"two phases: one tick at 50%") and ok
	ok = _expect(hud._boss_phase.text.contains("1 / 2"), "phase written as text") and ok
	hud.set_state({"boss": {"name": "x", "hp": 1.0, "hp_max": 4.0, "phase": 1, "phase_count": 3, "phase_at": [0.7, 0.3]}})
	ok = _expect(hud._boss_bar.ticks.size() == 2 and is_equal_approx(hud._boss_bar.ticks[0], 0.7), "phase_at overrides even ticks") and ok
	hud.set_state({"hp": 80.0, "hp_max": 100.0})
	ok = _expect(not hud._boss.visible, "boss gone: bar hidden again") and ok
	hud.queue_free()
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
