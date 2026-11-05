extends Node
## D-12: the craft screen opens from the base menu id, shows every mode, and its action button
## follows the Armory previews (upgrade, engrave, blocked without a worker).
## Called by tests/run_tests.gd. Restores Economy, Colony, Armory and GameState afterwards.


func run() -> bool:
	var snap := {"economy": JSON.from_native(Economy.save_data()), "colony": JSON.from_native(Colony.save_data()),
		"armory": JSON.from_native(Armory.save_data()), "game": JSON.from_native(GameState.save_data())}
	var tier := Colony.tier
	var ok := true
	ok = _test_compare_rows() and ok
	_setup()
	ok = await _test_upgrade() and ok
	ok = await _test_modes() and ok
	ok = await _test_engrave() and ok
	ok = await _test_no_worker() and ok
	UI.close(&"craft")
	await get_tree().process_frame
	ok = _expect(not get_tree().paused, "closing the craft screen unpauses") and ok
	Economy.load_data(JSON.to_native(snap.economy))
	Colony.load_data(JSON.to_native(snap.colony))
	Colony.tier = tier
	Armory.load_data(JSON.to_native(snap.armory))
	GameState.load_data(JSON.to_native(snap.game))
	return ok


var _machete: StringName
var _spear: StringName


func _setup() -> void:
	Economy.load_data({})
	Colony.load_data({})
	Economy.set_cap_bonus(5000)
	Economy.apply({&"scrap": 200, &"parts": 20, &"water_moss": 10, &"essence_water_low": 2})
	Colony.tier = Enums.BaseTier.SETTLEMENT
	var smith := Colony.add_resident({"id": &"test_smith", "name": "테스트 정비공", "age_stage": Enums.AgeStage.ADULT,
		"stats": {&"dex": 8}, "access_needs": []})
	var keeper := Colony.add_resident({"id": &"test_keeper", "name": "테스트 공방지기", "age_stage": Enums.AgeStage.ADULT,
		"stats": {&"dex": 5}, "access_needs": []})
	var ws := Colony.place_building(&"workshop", Vector2i(2, 2), 0, &"", false)
	Colony.complete_building(ws)
	Colony.assign_job(smith, &"maintenance", ws)
	GameState.set_flag(&"blueprint_essence_workshop")
	var ew := Colony.place_building(&"essence_workshop", Vector2i(8, 8), 0, &"", false)
	Colony.complete_building(ew)
	Colony.assign_job(keeper, &"essence_research", ew)
	var sr := Colony.place_building(&"sewing_room", Vector2i(2, 8), 0, &"", false)
	Colony.complete_building(sr)
	_machete = Armory.create_item(&"machete", Enums.Rarity.COMMON)
	_spear = Armory.create_item(&"spear", Enums.Rarity.EPIC)
	Armory.create_item(&"hoodie", Enums.Rarity.COMMON)  # sewing room gear, nobody works there


func _test_compare_rows() -> bool:
	var rows := ItemInfo.compare_rows({"damage": 10.0, "attack_interval": 0.5, "durability": 50.0},
		{"damage": 12.0, "attack_interval": 0.6, "durability": 50.0})
	var by := {}
	for r: Array in rows:
		by[r[0]] = r
	return _expect(by.has("공격력") and by["공격력"][3] == "up", "higher damage is marked up") \
		and _expect(by.has("공격 간격") and by["공격 간격"][3] == "dn", "slower attack is marked down") \
		and _expect(by.has("내구도") and by["내구도"][3] == "", "unchanged durability has no mark")


func _test_upgrade() -> bool:
	var ok := _expect(UI.has_screen(&"craft"), "craft screen registered for the base menu")
	UI.open(&"craft", {"facility": &"workshop", "mode": &"upgrade", "uid": _machete})
	await get_tree().process_frame
	var s := UI.get_screen(&"craft")
	ok = _expect(UI.top() == &"craft" and s is MenuScreen, "craft screen opens") and ok
	var btn: Button = s.get(&"_do_button")
	ok = _expect(btn != null and not btn.disabled, "upgrade is possible with workshop + worker + scrap") and ok
	var scrap := Economy.get_amount(&"scrap")
	if btn != null:
		btn.pressed.emit()
	ok = _expect(Armory.get_item(_machete).upgrade_level == 1, "pressing the action upgrades through Armory") and ok
	ok = _expect(Economy.get_amount(&"scrap") < scrap, "the upgrade paid scrap") and ok
	return ok


func _test_modes() -> bool:
	var ok := true
	var s := UI.get_screen(&"craft")
	for f: StringName in [&"workshop", &"essence_workshop"]:
		s.call(&"_set_facility", f)
		for m: Array in s.call(&"_modes"):
			s.call(&"_set_mode", m[0])
			await get_tree().process_frame
			var title: Label = s.get(&"_title")
			ok = _expect(title != null and not title.text.is_empty(), "mode %s/%s draws a title" % [f, m[0]]) and ok
	return ok


func _test_engrave() -> bool:
	var s := UI.get_screen(&"craft")
	s.call(&"_set_facility", &"essence_workshop")
	s.call(&"_set_mode", &"engrave")
	s.set(&"_sel", _spear)
	s.set(&"_slot", 0)
	s.set(&"_essence", &"essence_water_low")
	s.call(&"_refresh")
	await get_tree().process_frame
	var btn: Button = s.get(&"_do_button")
	var ok := _expect(btn != null and not btn.disabled, "engraving is possible with a worker and the essence")
	if btn != null:
		btn.pressed.emit()
	ok = _expect(Armory.get_engravings(_spear)[0] == &"essence_water_low", "pressing the action engraves") and ok
	return ok


func _test_no_worker() -> bool:
	var s := UI.get_screen(&"craft")
	s.call(&"_set_facility", &"sewing_room")
	s.call(&"_set_mode", &"craft")
	s.call(&"_set_mode", &"upgrade")
	await get_tree().process_frame
	var btn: Button = s.get(&"_do_button")
	return _expect(btn == null or btn.disabled, "no worker in the sewing room: the action is blocked")


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
