extends Node
## D-15: settings + quick accessibility screens drive Settings / InputMap, the theme follows
## text size and contrast at once, the colour filter follows color_filter, menu TTS reads the
## focused row, difficulty presets / custom / hardcore lock, and key remapping with swap.
## Uses a throwaway settings file and restores Settings values and the default bindings.

const TEST_PATH := "user://test_settings_ui.cfg"

var _old_path: String
var _old_values: Dictionary


func run() -> bool:
	_old_path = Settings.path
	_old_values = Settings.values.duplicate()
	Settings.path = TEST_PATH
	Settings.values = Settings.DEFAULTS.duplicate()
	var ok := _expect(UI.has_screen(&"settings") and UI.has_screen(&"accessibility_quick"),
		"settings and accessibility_quick are registered")
	ok = _test_catalog() and ok
	ok = await _test_access() and ok
	ok = await _test_difficulty() and ok
	ok = await _test_bindings() and ok
	ok = await _test_quick() and ok
	UI.close(&"settings")
	UI.close(&"accessibility_quick")
	await get_tree().process_frame
	ok = _expect(not get_tree().paused, "closing the settings screens unpauses") and ok
	InputSetup.apply_defaults(true)
	DirAccess.remove_absolute(TEST_PATH)
	Settings.path = _old_path
	Settings.values = _old_values
	for k: StringName in [&"text_size", &"high_contrast", &"color_filter"]:
		EventBus.settings_changed.emit(k)  # theme + filter back to the real values
	return ok


func _test_catalog() -> bool:
	var ok := true
	# Every Settings key has a row somewhere (tabs, difficulty items or the preset row).
	var shown := {&"difficulty": true, &"hardcore": true}
	for tab: StringName in SettingsCatalog.ROWS:
		for r: Dictionary in SettingsCatalog.ROWS[tab]:
			shown[r.get("key", &"")] = true
	for k: StringName in SettingsCatalog.DIFFICULTY_ITEMS:
		shown[k] = true
	for k: StringName in Settings.DEFAULTS:
		ok = _expect(shown.has(k), "Settings key %s has no settings row" % k) and ok
	for a: StringName in InputSetup.DEFAULTS:
		ok = _expect(SettingsCatalog.action_name(a) != String(a), "action %s has no name" % a) and ok
	# Difficulty steps come from the presets.
	for r: Dictionary in SettingsCatalog.difficulty_rows():
		for id: StringName in Settings.PRESETS:
			var v: Variant = Settings.PRESETS[id].get(r.key)
			ok = _expect(SettingsCatalog.option_index(r.options, v) >= 0,
				"difficulty %s lacks preset value %s" % [r.key, v]) and ok
	return ok


func _row(s: SettingsScreen, key: StringName) -> SettingRow:
	for r in s.get(&"_rows"):
		if (r as SettingRow).key == key:
			return r
	return null


func _test_access() -> bool:
	UI.open(&"settings", {"tab": &"access"})
	await get_tree().process_frame
	await get_tree().process_frame
	var s := UI.get_screen(&"settings") as SettingsScreen
	var ok := _expect(s != null and UI.top() == &"settings", "settings opens")
	ok = _expect(get_tree().paused, "settings pauses the game") and ok
	var size_row := _row(s, &"subtitle_size")
	size_row.step(1)
	ok = _expect(Settings.get_value(&"subtitle_size") == 2, "stepping the row sets subtitle_size") and ok
	# Text size and contrast rebuild the theme the screen uses, right away.
	var before := UI.theme.default_font_size
	_row(s, &"text_size").step(1)
	ok = _expect(UI.theme.default_font_size > before, "text size grows the theme at once") and ok
	ok = _expect(s.get_theme_default_font_size() > before,
		"the open screen inherits the bigger text") and ok
	_row(s, &"high_contrast").step(1)
	ok = _expect(bool(Settings.get_value(&"high_contrast")), "high contrast on") and ok
	ok = _expect(UI.theme.get_color(&"font_color", &"LabelDim") == UiTokens.TEXT, "high contrast brightens dim text") and ok
	# Colour filter.
	var filter_row := _row(s, &"color_filter")
	filter_row.step(1)
	filter_row.step(1)
	ok = _expect(Settings.get_value(&"color_filter") == 2, "colour filter = deuteranopia") and ok
	ok = _expect(UI.color_filter.visible and UI.color_filter.mode() == 2, "filter layer shows mode 2") and ok
	Settings.set_value(&"color_filter", 0)
	ok = _expect(not UI.color_filter.visible, "filter off hides the layer") and ok
	# Menu TTS reads the focused row.
	Settings.set_value(&"tts_menu", true)
	MenuReader.last_text = ""
	_row(s, &"reduce_shake").grab_focus()
	ok = _expect(MenuReader.last_text.begins_with("흔들림 줄이기"), "TTS reads the focused row (%s)" % MenuReader.last_text) and ok
	_row(s, &"reduce_shake").step(1)
	ok = _expect(bool(Settings.get_value(&"reduce_shake")) and MenuReader.last_text.ends_with("켬"),
		"TTS reads the new value") and ok
	Settings.set_value(&"tts_menu", false)
	# Backspace-style reset.
	s.reset_row(size_row)
	ok = _expect(Settings.get_value(&"subtitle_size") == Settings.DEFAULTS[&"subtitle_size"], "reset_row restores the default") and ok
	return ok


func _test_difficulty() -> bool:
	var s := UI.get_screen(&"settings") as SettingsScreen
	s.call(&"_show_tab", &"difficulty")
	await get_tree().process_frame
	var preset := _row(s, &"difficulty")
	var ok := _expect(preset != null and preset.current_value() == &"normal", "difficulty row shows normal")
	preset.step(-1)
	ok = _expect(Settings.matching_preset() == &"story" and bool(Settings.get_value(&"keep_bag_on_down")),
		"stepping the preset applies story") and ok
	var hardcore_listed := false
	for o: Array in preset.options:
		hardcore_listed = hardcore_listed or o[0] == &"hardcore"
	ok = _expect(not hardcore_listed, "hardcore is not offered outside a new game") and ok
	_row(s, &"keep_bag_on_down").step(-1)
	await get_tree().process_frame
	ok = _expect(Settings.get_value(&"difficulty") == Settings.CUSTOM, "one item changed: custom") and ok
	ok = _expect(preset.tts_text().contains(SettingsCatalog.PRESET_NAMES[Settings.CUSTOM]), "preset row shows 직접 정함") and ok
	# A hardcore run cannot change difficulty from the in-game settings.
	Settings.apply_preset(&"hardcore", true)
	s.call(&"_show_tab", &"difficulty")
	await get_tree().process_frame
	var mult := _row(s, &"monster_mult")
	ok = _expect(mult.locked, "difficulty items are locked in a hardcore game") and ok
	mult.step(-1)
	ok = _expect(is_equal_approx(Settings.get_value(&"monster_mult"), 1.3), "locked row does not change") and ok
	Settings.apply_preset(&"normal", true)
	return ok


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	return k


func _has(action: StringName, code: Key) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == code:
			return true
	return false


func _test_bindings() -> bool:
	var s := UI.get_screen(&"settings") as SettingsScreen
	s.call(&"_show_tab", &"controls")
	await get_tree().process_frame
	var ok := _expect(_row(s, &"reload") != null and _row(s, &"reload").kind == "binding", "reload has a binding row")
	var other := s.apply_binding(&"reload", _key(KEY_T))
	ok = _expect(_has(&"reload", KEY_T) and not _has(&"reload", KEY_R) and other == &"",
		"reload rebinds R → T") and ok
	ok = _expect(SettingsCatalog.binding(&"reload", true) is InputEventJoypadButton, "the pad binding stays") and ok
	other = s.apply_binding(&"reload", _key(KEY_F))
	ok = _expect(other == &"interact" and _has(&"reload", KEY_F) and _has(&"interact", KEY_T),
		"taking interact's F swaps T to interact") and ok
	# Capture card → confirm dialog → apply.
	s.start_capture(&"dodge")
	ok = _expect(s.is_capturing(), "capture card opens") and ok
	await get_tree().process_frame
	var press := _key(KEY_G)
	press.pressed = true
	s.call(&"_input", press)
	ok = _expect(not s.is_capturing() and s.pending_dialog() != null, "a key press asks to confirm") and ok
	if s.pending_dialog() != null:
		s.pending_dialog().call(&"_finish", true)
	ok = _expect(_has(&"dodge", KEY_G) and not _has(&"dodge", KEY_SPACE), "confirming rebinds dodge") and ok
	s.start_capture(&"dodge")
	await get_tree().process_frame
	var esc := _key(KEY_ESCAPE)
	esc.pressed = true
	s.call(&"_input", esc)
	ok = _expect(not s.is_capturing() and s.pending_dialog() == null and _has(&"dodge", KEY_G), "Esc cancels the capture") and ok
	s.reset_all_bindings()
	ok = _expect(_has(&"reload", KEY_R) and _has(&"interact", KEY_F) and _has(&"dodge", KEY_SPACE),
		"reset puts the default keys back") and ok
	return ok


func _test_quick() -> bool:
	UI.close(&"settings")
	UI.open(&"accessibility_quick")
	await get_tree().process_frame
	var s := UI.get_screen(&"accessibility_quick") as SettingsScreen
	var ok := _expect(s != null and s.quick, "quick accessibility screen opens")
	for k: StringName in [&"text_size", &"subtitles", &"high_contrast", &"reduce_shake", &"color_filter", &"protect_mode"]:
		ok = _expect(_row(s, k) != null, "quick screen has %s" % k) and ok
	var protect := _row(s, &"protect_mode")
	protect.step(1)
	ok = _expect(Settings.matching_preset() == &"story", "protect mode on = story preset") and ok
	protect.step(1)
	ok = _expect(Settings.matching_preset() == &"normal", "protect mode off = normal") and ok
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
