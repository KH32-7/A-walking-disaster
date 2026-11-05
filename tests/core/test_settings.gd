extends RefCounted
## Settings (A-12): ConfigFile persistence, type checks, difficulty presets, custom detection,
## hardcore lock, per-save difficulty provider. Uses a throwaway file, never the real settings.

const TEST_PATH := "user://test_settings.cfg"

var _old_path: String
var _old_values: Dictionary


func run() -> bool:
	_old_path = Settings.path
	_old_values = Settings.values.duplicate()
	Settings.path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	Settings.load_from_disk()

	var ok := _check_defaults() and _check_set_and_persist() and _check_refusals() \
		and _check_presets() and _check_custom() and _check_hardcore_lock() and _check_provider()

	DirAccess.remove_absolute(TEST_PATH)
	Settings.path = _old_path
	Settings.values = _old_values
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _check_defaults() -> bool:
	return _expect(Settings.get_value(&"subtitles") == true, "subtitles default") \
		and _expect(Settings.get_value(&"difficulty") == &"normal", "difficulty default") \
		and _expect(Settings.matching_preset() == &"normal", "defaults should match normal")


func _check_set_and_persist() -> bool:
	var ok := _expect(Settings.set_value(&"game_speed", 0.75), "set game_speed") \
		and _expect(Settings.set_value(&"aim_assist", 3), "set aim_assist") \
		and _expect(Settings.set_value(&"camera_zoom", 2), "int into float key should convert")
	Settings.values = Settings.DEFAULTS.duplicate()
	Settings.load_from_disk()
	return ok and _expect(is_equal_approx(Settings.get_value(&"game_speed"), 0.75), "game_speed not saved") \
		and _expect(Settings.get_value(&"aim_assist") == 3, "aim_assist not saved") \
		and _expect(typeof(Settings.get_value(&"camera_zoom")) == TYPE_FLOAT, "camera_zoom type")


func _check_refusals() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(TEST_PATH)
	cfg.set_value(Settings.SECTION, "subtitles", "yes please")  # wrong type
	cfg.set_value(Settings.SECTION, "no_such_key", 5)
	cfg.save(TEST_PATH)
	Settings.load_from_disk()
	return _expect(not Settings.set_value(&"no_such_key", 1), "unknown key accepted") \
		and _expect(not Settings.set_value(&"subtitles", "maybe"), "wrong type accepted") \
		and _expect(Settings.get_value(&"subtitles") == true, "bad file value loaded") \
		and _expect(not Settings.set_value(&"hardcore", true), "hardcore set directly")


func _check_presets() -> bool:
	var ok := _expect(Settings.apply_preset(&"story"), "story preset")
	ok = _expect(Settings.get_value(&"keep_bag_on_down") and Settings.get_value(&"instant_loot")
		and not Settings.get_value(&"permadeath") and Settings.get_value(&"strand_days") == 0
		and is_equal_approx(Settings.get_value(&"monster_mult"), 0.7)
		and is_equal_approx(Settings.get_value(&"raid_mult"), 0.6), "story values") and ok
	ok = _expect(Settings.apply_preset(&"hard"), "hard preset") and ok
	return ok and _expect(Settings.get_value(&"strand_days") == 3
		and is_equal_approx(Settings.get_value(&"raid_mult"), 1.3), "hard values") \
		and _expect(Settings.get_value(&"difficulty") == &"hard", "difficulty name")


func _check_custom() -> bool:
	Settings.apply_preset(&"normal")
	Settings.set_value(&"keep_bag_on_down", true)  # one protect-mode item on its own
	var custom: Variant = Settings.get_value(&"difficulty")
	Settings.set_value(&"keep_bag_on_down", false)
	return _expect(custom == Settings.CUSTOM, "single toggle should be custom, got %s" % custom) \
		and _expect(Settings.get_value(&"difficulty") == &"normal", "toggling back should match normal")


func _check_hardcore_lock() -> bool:
	Settings.apply_preset(&"normal")
	var ok := _expect(not Settings.apply_preset(&"hardcore"), "entered hardcore mid-game") \
		and _expect(Settings.apply_preset(&"hardcore", true), "hardcore at new game")
	ok = _expect(Settings.get_value(&"hardcore") and is_equal_approx(Settings.get_value(&"raid_mult"), 1.5),
		"hardcore values") and ok
	ok = _expect(not Settings.apply_preset(&"story"), "left hardcore mid-game") and ok
	return ok and _expect(Settings.apply_preset(&"normal", true), "new game back to normal")


func _check_provider() -> bool:
	Settings.apply_preset(&"story", true)
	var saved := Settings.save_data()
	Settings.apply_preset(&"hard", true)
	Settings.set_value(&"subtitle_size", 2)
	Settings.load_data(saved)
	return _expect(Settings.get_value(&"difficulty") == &"story" and Settings.get_value(&"keep_bag_on_down"),
		"difficulty provider did not restore story") \
		and _expect(Settings.get_value(&"subtitle_size") == 2, "loading a save changed a preference") \
		and _expect(not saved.has(&"subtitles"), "preferences leaked into the save")
