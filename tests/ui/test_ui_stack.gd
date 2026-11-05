extends Node
## D-01: UI screen stack, theme variations, badges, subtitle.


func run() -> bool:
	var ok := _check_theme()
	ok = _check_badges() and ok
	ok = await _check_stack() and ok
	ok = _check_subtitle() and ok
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _check_theme() -> bool:
	var ok := true
	for size in 3:
		for hc in [false, true]:
			var t := UiThemeBuilder.build(size, hc)
			for v in UiThemeBuilder.VARIATIONS:
				ok = _expect(t.is_type_variation(v, t.get_type_variation_base(v)),
					"variation %s missing (size %d hc %s)" % [v, size, hc]) and ok
	var small := UiThemeBuilder.build(0).get_font_size(&"font_size", &"LabelTitle")
	var large := UiThemeBuilder.build(2).get_font_size(&"font_size", &"LabelTitle")
	ok = _expect(small < large, "text size should scale titles (%d vs %d)" % [small, large]) and ok
	ok = _expect(UI.theme != null and UI.hud.theme == UI.theme, "UI layers share the theme") and ok
	return ok


func _check_badges() -> bool:
	var ok := true
	var seen := {}
	for r in 5:
		seen[UiTokens.rarity_shape(r)] = true
	ok = _expect(seen.size() == 5, "every rarity needs its own shape") and ok
	seen.clear()
	for e in range(1, 5):
		seen[UiTokens.element_shape(e)] = true
	ok = _expect(seen.size() == 4, "every element needs its own shape") and ok
	var b := ShapeBadge.new()
	b.value = 4
	b.show_label = true
	ok = _expect(b.get_label_text() == "전설" and b.get_shape() == UiTokens.Shape.STAR, "legend badge") and ok
	b.free()
	return ok


func _check_stack() -> bool:
	var ok := true
	UI.close_all()
	var packed := PackedScene.new()
	var root := Control.new()
	packed.pack(root)
	root.free()
	UI.register_screen(&"_t_a", packed)
	UI.register_screen(&"_t_b", packed, {"pauses_game": true})
	UI.register_screen(&"_t_c", packed, {"is_overlay": true, "hides_hud": false})
	UI.open(&"_t_a")
	UI.open(&"_t_b")
	ok = _expect(UI.stack_ids() == [&"_t_a", &"_t_b"], "open order %s" % [UI.stack_ids()]) and ok
	ok = _expect(get_tree().paused, "pausing screen pauses the tree") and ok
	ok = _expect(not UI.hud.visible, "HUD hidden under a screen") and ok
	ok = _expect(not UI.get_screen(&"_t_a").visible, "screen under a full screen is hidden") and ok
	UI.open(&"_t_c")
	ok = _expect(UI.get_screen(&"_t_b").visible, "overlay keeps the screen below visible") and ok
	UI.open(&"_t_a")  # re-open moves it to the top, no duplicate
	ok = _expect(UI.stack_ids() == [&"_t_b", &"_t_c", &"_t_a"], "re-open moves to top %s" % [UI.stack_ids()]) and ok
	UI.close_top()
	ok = _expect(UI.top() == &"_t_c", "close_top") and ok
	UI.close(&"_t_b")
	ok = _expect(not get_tree().paused, "unpaused after the pausing screen closed") and ok
	UI.close(&"_t_missing")  # no error
	UI.close_all()
	ok = _expect(UI.stack_ids().is_empty() and UI.hud.visible, "close_all") and ok
	UI.open(&"_t_unknown")  # pushes an error, must not crash or push
	ok = _expect(UI.stack_ids().is_empty(), "unknown screen is not opened") and ok
	await get_tree().process_frame
	return ok


func _check_subtitle() -> bool:
	var s := UI.subtitle
	s.clear()
	EventBus.radio_message.emit(&"broadcaster", "들리나? 상가 3층에서 소리가 나.", 1)
	var ok := _expect(s.current_text().begins_with("들리나"), "radio_message shows a subtitle")
	s.show_line("", "낮은 우선순위", 0)
	ok = _expect(s.current_text().begins_with("들리나"), "lower priority waits") and ok
	s.show_line("", "긴급", 5)
	ok = _expect(s.current_text() == "긴급", "higher priority interrupts") and ok
	s.clear()
	return ok
