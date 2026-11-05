extends RefCounted
## SaveSystem (A-04): every provider round-trips, wrong versions and corrupt files are refused,
## the suspend save deletes itself on load. Uses a throwaway save dir, never the real saves.

const TEST_DIR := "user://test_saves"
const PROVIDERS := [&"game", &"economy", &"armory", &"bag", &"field", &"colony"]

var _backup: Dictionary = {}
var _old_dir: String
var _old_slot: int
var _old_autosave: bool


func run() -> bool:
	_old_dir = SaveSystem.save_dir
	_old_slot = SaveSystem.current_slot
	_old_autosave = SaveSystem.autosave_enabled
	SaveSystem.save_dir = TEST_DIR
	SaveSystem.autosave_enabled = false
	_wipe_dir()
	for key in PROVIDERS:
		_backup[key] = _provider(key).save_data().duplicate(true)

	var ok := _check_providers_registered() and _check_round_trip() and _check_version_refused() \
		and _check_corrupt_refused() and _check_suspend() and _check_slot_info() \
		and _check_bad_slot()

	for key in PROVIDERS:
		_provider(key).load_data(_backup[key])
	_wipe_dir()
	SaveSystem.save_dir = _old_dir
	SaveSystem.current_slot = _old_slot
	SaveSystem.autosave_enabled = _old_autosave
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _provider(key: StringName) -> Object:
	return SaveSystem._providers.get(key)


func _snapshot_all() -> Dictionary:
	var out := {}
	for key in PROVIDERS:
		out[key] = _provider(key).save_data().duplicate(true)
	return out


func _fill_sample_state() -> void:
	GameState.load_data({"day": 7, "phase": Enums.Phase.EVENING,
		"flags": {&"met_broadcaster": true, &"bridge_level": 2}})
	Economy.load_data({"amounts": {&"wood": 40, &"scrap": 12}, "cap_bonus": 300})
	FieldState.load_data({
		"lost_gear": [{"item_uid": &"gun_0001", "region_id": &"flooded_mall",
			"position": Vector3(1.5, 0.0, -3.25)}],
		"boss_respawn_day": {&"flooded_mall": 12},
	})
	Colony.load_data({
		"residents": {&"res_kim": {"name": "김순자", "age_stage": Enums.AgeStage.ELDER,
			"status": Enums.ResidentStatus.ACTIVE, "skills": [1, 2.5]}},
		"threat": 35, "tier": Enums.BaseTier.SETTLEMENT,
	})


func _reset_state() -> void:
	for key in PROVIDERS:
		_provider(key).load_data({})


func _check_providers_registered() -> bool:
	for key in PROVIDERS:
		if not _expect(_provider(key) != null, "provider %s not registered" % key):
			return false
	return true


func _check_round_trip() -> bool:
	_fill_sample_state()
	var before := _snapshot_all()
	if not _expect(SaveSystem.save_slot(1), "save_slot(1) failed"):
		return false
	_reset_state()
	var loaded := SaveSystem.load_slot(1)
	var after := _snapshot_all()
	var ok := _expect(loaded, "load_slot(1) failed") and _expect(SaveSystem.current_slot == 1, "current_slot")
	for key in PROVIDERS:
		ok = _expect(var_to_str(after[key]) == var_to_str(before[key]),
			"%s differs after round trip:\n  before %s\n  after  %s" % [key, before[key], after[key]]) and ok
	return ok


func _check_version_refused() -> bool:
	_fill_sample_state()
	SaveSystem.save_slot(2)
	var path := TEST_DIR.path_join("slot_2.json")
	var text := FileAccess.get_file_as_string(path)
	var data: Dictionary = JSON.to_native(JSON.parse_string(text))
	data["version"] = SaveSystem.SAVE_VERSION + 1
	_write_raw(path, JSON.stringify(JSON.from_native(data)))

	_reset_state()
	var before := _snapshot_all()
	var loaded := SaveSystem.load_slot(2)
	return _expect(not loaded, "newer version was loaded") \
		and _expect(var_to_str(_snapshot_all()) == var_to_str(before), "refused load changed state")


func _check_corrupt_refused() -> bool:
	_write_raw(TEST_DIR.path_join("slot_0.json"), "{ not json")
	_reset_state()
	var before := _snapshot_all()
	return _expect(not SaveSystem.load_slot(0), "corrupt file was loaded") \
		and _expect(var_to_str(_snapshot_all()) == var_to_str(before), "corrupt load changed state")


func _check_suspend() -> bool:
	_fill_sample_state()
	SaveSystem.current_slot = 2
	var before := _snapshot_all()
	var saved := SaveSystem.save_suspend()
	_reset_state()
	SaveSystem.current_slot = 0
	var loaded := SaveSystem.load_suspend()
	return _expect(saved and loaded, "suspend save/load failed") \
		and _expect(var_to_str(_snapshot_all()) == var_to_str(before), "suspend round trip differs") \
		and _expect(not SaveSystem.has_suspend(), "suspend file still exists after load") \
		and _expect(SaveSystem.current_slot == 2, "suspend did not restore its slot") \
		and _expect(not SaveSystem.load_suspend(), "suspend loaded twice")


func _check_slot_info() -> bool:
	SaveSystem.delete_slot(0)
	var empty := SaveSystem.slot_info(0)
	var good := SaveSystem.slot_info(1)  # round-trip save, day 7
	var old := SaveSystem.slot_info(2)  # version bumped above
	return _expect(not empty["exists"], "deleted slot still exists") \
		and _expect(good["exists"] and good["compatible"] and good["day"] == 7, "slot_info(1) %s" % good) \
		and _expect(old["exists"] and not old["compatible"], "slot_info(2) %s" % old)


func _check_bad_slot() -> bool:
	return _expect(not SaveSystem.save_slot(SaveSystem.SLOT_COUNT), "saved to out-of-range slot") \
		and _expect(not SaveSystem.has_slot(-1), "negative slot exists")


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _wipe_dir() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(TEST_DIR)
