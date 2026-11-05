extends RefCounted
## M2 hand-offs between Lane A systems: a finished personal request lands in the journal (A-13 -> A-17),
## the "bag_cells" perk widens the bag (A-11 -> A-08), the evening report carries auto repair (A-09 ->
## A-05). Every save provider is restored afterwards; autosave is off.

var _backup := {}
var _saved_autosave: bool


func run() -> bool:
	_saved_autosave = SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	for key: StringName in SaveSystem._providers:
		_backup[key] = SaveSystem._providers[key].save_data().duplicate(true)

	var ok := _check_request_to_journal() and _check_bag_perk() and _check_evening_repairs()

	for key: StringName in _backup:
		SaveSystem._providers[key].load_data(_backup[key])
	SaveSystem.autosave_enabled = _saved_autosave
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _check_request_to_journal() -> bool:
	SaveSystem.reset_all()
	var profile := ResidentPool.get_profile(&"demo_carpenter")
	if not _expect(not profile.is_empty(), "demo_carpenter profile missing"):
		return false
	var resident := Colony.add_resident(profile)
	var quest := &"personal_carpenter_plane"
	var started := Quests.start(quest, resident)
	var giver_ok := Quests.giver_of(quest) == resident
	var completed := Quests.complete(quest)
	var kinds: Array = Journal.entries_for_resident(resident).map(func(e): return e["kind"])
	return _expect(started and giver_ok and completed, "quest start %s giver %s complete %s" % [started, giver_ok, completed]) \
		and _expect(&"request_completed" in kinds, "no request_completed entry for %s: %s" % [resident, kinds])


func _check_bag_perk() -> bool:
	SaveSystem.reset_all()
	Bag.resize_for_player()
	var before := Bag.bonus_cells
	Progression.perks.append(&"bag_cells")
	Bag.resize_for_player()
	var after := Bag.bonus_cells
	return _expect(before == 0 and after == int(Progression.PERKS[&"bag_cells"]["value"]),
		"bag bonus cells %d -> %d" % [before, after])


func _check_evening_repairs() -> bool:
	SaveSystem.reset_all()
	SceneRouter._settle_evening()
	var repairs: Dictionary = SceneRouter.last_evening_report.get("repairs", {})
	var weapon: Dictionary = repairs.get(UpgradeRules.WEAPON_FACILITY, {})
	return _expect(repairs.has(UpgradeRules.GEAR_FACILITY) and weapon.get("reason") == &"disabled",
		"evening repairs %s" % repairs)
