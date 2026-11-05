extends RefCounted
## Progression (A-11): XP formula, level-up boundaries, max HP, perk picks every 3 levels,
## XP from signals and finish_sortie, class mastery, save round trip.
## Never writes the real saves: autosave is off and the slot test uses a throwaway dir.

const TEST_DIR := "user://test_progression_saves"

var _levels: Array = []
var _saved: Dictionary
var _old_dir: String
var _old_slot: int
var _old_autosave: bool


func run() -> bool:
	var old_pace := Progression.xp_pace
	Progression.xp_pace = 1.0  # design numbers
	_saved = Progression.save_data().duplicate(true)
	_old_dir = SaveSystem.save_dir
	_old_slot = SaveSystem.current_slot
	_old_autosave = SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	SaveSystem.save_dir = TEST_DIR
	var on_level := func(lv: int): _levels.append(lv)
	EventBus.level_up.connect(on_level)

	var ok := _check_formula() and _check_level_boundary() and _check_multi_level() \
		and _check_max_level() and _check_hp() and _check_perks() and _check_signals() \
		and _check_finish_sortie() and _check_mastery() and _check_save_round_trip() \
		and _check_slot_round_trip() and _check_debug()

	EventBus.level_up.disconnect(on_level)
	_wipe_dir()
	SaveSystem.save_dir = _old_dir
	SaveSystem.current_slot = _old_slot
	SaveSystem.autosave_enabled = _old_autosave
	Progression.load_data(_saved)
	Progression.xp_pace = old_pace
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _reset() -> void:
	Progression.load_data({})
	_levels.clear()


func _check_formula() -> bool:
	return _expect(Progression.xp_to_next(1) == 100, "L1 need %d" % Progression.xp_to_next(1)) \
		and _expect(Progression.xp_to_next(2) == 263, "L2 need %d" % Progression.xp_to_next(2)) \
		and _expect(Progression.xp_to_next(10) == 2511, "L10 need %d" % Progression.xp_to_next(10)) \
		and _expect(Progression.xp_to_next(29) == int(floor(100.0 * pow(29, 1.4))), "L29 need")


func _check_level_boundary() -> bool:
	_reset()
	Progression.add_xp(99)
	var ok := _expect(Progression.level == 1 and Progression.xp == 99, "99 xp levelled up")
	Progression.add_xp(1)
	ok = _expect(Progression.level == 2 and Progression.xp == 0, "100 xp: level %d xp %d"
		% [Progression.level, Progression.xp]) and ok
	return _expect(_levels == [2], "level_up %s" % [_levels]) and ok


func _check_multi_level() -> bool:
	_reset()
	Progression.add_xp(100 + 263 + 10)
	return _expect(Progression.level == 3 and Progression.xp == 10, "multi: level %d xp %d"
		% [Progression.level, Progression.xp]) \
		and _expect(_levels == [2, 3], "level_up %s" % [_levels]) \
		and _expect(Progression.total_xp == 373, "total %d" % Progression.total_xp)


func _check_max_level() -> bool:
	_reset()
	Progression.add_xp(10_000_000)
	var ok := _expect(Progression.level == Progression.MAX_LEVEL, "max level %d" % Progression.level) \
		and _expect(Progression.xp == 0 and Progression.xp_needed() == 0, "xp at max %d" % Progression.xp) \
		and _expect(_levels.size() == Progression.MAX_LEVEL - 1, "level_up count %d" % _levels.size())
	return _expect(Progression.add_xp(50) == 0 and Progression.level == Progression.MAX_LEVEL,
		"xp added past max") and ok


func _check_hp() -> bool:
	_reset()
	var ok := _expect(Progression.max_hp() == 100, "L1 hp %d" % Progression.max_hp())
	Progression.load_data({"level": 5})
	ok = _expect(Progression.max_hp() == 120, "L5 hp %d" % Progression.max_hp()) and ok
	Progression.load_data({"level": 30})
	return _expect(Progression.max_hp() == 245, "L30 hp %d" % Progression.max_hp()) and ok


func _check_perks() -> bool:
	_reset()
	var ok := _expect(Progression.pending_perks() == 0 and Progression.perk_choices().is_empty(),
		"perk at level 1")
	ok = _expect(not Progression.choose_perk(&"stamina"), "chose a perk at level 1") and ok
	Progression.load_data({"level": 2})
	ok = _expect(Progression.pending_perks() == 0, "perk at level 2") and ok
	Progression.load_data({"level": 3})
	ok = _expect(Progression.pending_perks() == 1, "no perk at level 3") and ok
	ok = _expect(Progression.perk_choices().size() == Progression.PERKS.size(), "choices %s"
		% [Progression.perk_choices()]) and ok
	ok = _expect(not Progression.choose_perk(&"no_such_perk"), "unknown perk chosen") and ok
	ok = _expect(Progression.choose_perk(&"bag_cells"), "choose bag_cells") and ok
	ok = _expect(Progression.pending_perks() == 0 and Progression.perk_choices().is_empty(),
		"still pending after choosing") and ok
	ok = _expect(Progression.perk_bonus(&"bag_cells") == 2, "bag bonus %d"
		% Progression.perk_bonus(&"bag_cells")) and ok

	# Level 6: second pick, stacking the same perk to its max.
	Progression.load_data({"level": 6, "perks": [&"bag_cells"]})
	ok = _expect(Progression.choose_perk(&"bag_cells"), "second bag_cells stack") and ok
	ok = _expect(Progression.perk_bonus(&"bag_cells") == 4 and Progression.perk_stacks(&"bag_cells") == 2,
		"stacked bag bonus %d" % Progression.perk_bonus(&"bag_cells")) and ok
	Progression.load_data({"level": 9, "perks": [&"bag_cells", &"bag_cells"]})
	ok = _expect(not &"bag_cells" in Progression.perk_choices(), "maxed perk still offered") and ok
	ok = _expect(Progression.choose_perk(&"lockpick") \
		and Progression.perk_bonus(&"lockpick_time_pct") == -30, "lockpick bonus") and ok

	# Level 30 gives exactly enough picks for every stack.
	var total_stacks := 0
	for id in Progression.PERKS:
		total_stacks += int(Progression.PERKS[id]["max_stacks"])
	return _expect(Progression.MAX_LEVEL / Progression.PERK_EVERY == total_stacks,
		"%d picks vs %d stacks" % [Progression.MAX_LEVEL / Progression.PERK_EVERY, total_stacks]) and ok


func _check_signals() -> bool:
	_reset()
	EventBus.monster_killed.emit(&"no_such_monster", Enums.Element.GREEN, Vector3.ZERO)
	var ok := _expect(Progression.xp == 5, "kill without def gave %d" % Progression.xp)
	EventBus.raid_resolved.emit({"outcome": Enums.RaidOutcome.LOSS})
	ok = _expect(Progression.xp == 5, "lost raid gave xp") and ok
	EventBus.raid_resolved.emit({"outcome": Enums.RaidOutcome.NARROW})
	ok = _expect(Progression.xp == 45, "defended raid: xp %d" % Progression.xp) and ok
	ok = _expect(Progression.award(&"personal_request") == 80 and Progression.total_xp == 125
		and Progression.level == 2 and Progression.xp == 25,
		"personal request: total %d level %d" % [Progression.total_xp, Progression.level]) and ok
	return _expect(Progression.monster_tier(&"no_such_monster") == Enums.MonsterTier.NORMAL, "default tier") \
		and _expect(Progression.region_danger(&"no_such_region") == Progression.DEFAULT_DANGER, "default danger") \
		and ok


func _check_finish_sortie() -> bool:
	_reset()
	EventBus.sortie_started.emit({"region_id": &"no_such_region", "companions": [], "gear": {}})
	EventBus.monster_killed.emit(&"no_such_monster", Enums.Element.NONE, Vector3.ZERO)
	EventBus.monster_killed.emit(&"no_such_monster", Enums.Element.NONE, Vector3.ZERO)
	# 2 kills (10) + 2 rescued (100) + extraction 30 + 1 * 10
	var earned := Progression.finish_sortie(true, &"no_such_region", 2)
	var ok := _expect(earned == 150, "sortie xp %d" % earned) \
		and _expect(Progression.total_xp == 150, "total %d" % Progression.total_xp)

	# Downed: kills count, rescue and extraction do not.
	EventBus.sortie_started.emit({"region_id": &"no_such_region", "companions": [], "gear": {}})
	EventBus.monster_killed.emit(&"no_such_monster", Enums.Element.NONE, Vector3.ZERO)
	earned = Progression.finish_sortie(false, &"no_such_region", 1)
	return _expect(earned == 5, "downed sortie xp %d" % earned) and ok


func _check_mastery() -> bool:
	_reset()
	var gun := Enums.CombatClass.GUN
	var blade := Enums.CombatClass.BLADE
	var ok := _expect(Progression.mastery_level(gun) == 1 and Progression.mastery_level(blade) == 1,
		"mastery starts at 1")
	var need := Progression.mastery_xp_to_next(1)
	Progression.add_mastery(gun, need - 1)
	ok = _expect(Progression.mastery_level(gun) == 1 and Progression.mastery_xp(gun) == need - 1,
		"mastery under boundary") and ok
	ok = _expect(Progression.add_mastery(gun, 1) == 2 and Progression.mastery_xp(gun) == 0,
		"mastery boundary") and ok
	ok = _expect(Progression.mastery_level(blade) == 1, "classes not separate") and ok
	Progression.add_mastery(blade, 10_000_000)
	ok = _expect(Progression.mastery_level(blade) == Progression.MASTERY_MAX
		and Progression.mastery_xp(blade) == 0, "mastery max %d" % Progression.mastery_level(blade)) and ok
	return _expect(Progression.add_mastery(blade, 100) == Progression.MASTERY_MAX, "past mastery max") and ok


func _sample_state() -> void:
	Progression.load_data({"level": 7, "perks": [&"stamina", &"medic"]})
	Progression.add_xp(42)
	Progression.add_mastery(Enums.CombatClass.BLUNT, Progression.mastery_xp_to_next(1) + 3)


func _check_save_round_trip() -> bool:
	_reset()
	_sample_state()
	var before := Progression.save_data().duplicate(true)
	# Through JSON like a real save file.
	var json := JSON.stringify(JSON.from_native(before))
	Progression.load_data({})
	var ok := _expect(Progression.level == 1 and Progression.perks.is_empty(), "reset failed")
	Progression.load_data(JSON.to_native(JSON.parse_string(json)))
	ok = _expect(Progression.save_data() == before, "round trip %s != %s" % [Progression.save_data(), before]) and ok
	return _expect(Progression.level == 7 and Progression.xp == 42
		and Progression.mastery_level(Enums.CombatClass.BLUNT) == 2
		and Progression.mastery_xp(Enums.CombatClass.BLUNT) == 3
		and Progression.perk_stacks(&"medic") == 1, "restored values") and ok


func _check_slot_round_trip() -> bool:
	_wipe_dir()
	_reset()
	_sample_state()
	var before := Progression.save_data().duplicate(true)
	var ok := _expect(SaveSystem._providers.get(&"progression") == Progression, "provider not registered")
	ok = _expect(SaveSystem.save_slot(0), "save_slot failed") and ok
	Progression.load_data({})
	ok = _expect(SaveSystem.load_slot(0), "load_slot failed") and ok
	return _expect(Progression.save_data() == before, "slot round trip %s" % [Progression.save_data()]) and ok


func _check_debug() -> bool:
	if not OS.is_debug_build():
		return true
	_reset()
	DebugConsole.execute("xp 100")
	return _expect(Progression.level == 2, "debug xp command")


func _wipe_dir() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(TEST_DIR)
