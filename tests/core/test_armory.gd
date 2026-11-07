extends RefCounted
## Armory (A-07): design 05 numbers reproduced by get_item_stats, rarity / affix rolls,
## equip rules shared by player and residents, armor noise cap, save round trip.

const RESIDENT := &"res_test_kim"

var _saved: Dictionary


func run() -> bool:
	_saved = Armory.save_data().duplicate(true)
	Armory.load_data({})
	var ok := _check_defs() and _check_base_stats() and _check_rarity_upgrade() \
		and _check_broken() and _check_affix_rolls() and _check_equip_rules() \
		and _check_noise_cap() and _check_bag() and _check_lost() and _check_save()
	Armory.load_data(_saved)
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _plain(def_id: StringName, rarity := 0, upgrade := 0) -> StringName:
	var uid := Armory.create_item(def_id, rarity)
	var item := Armory.get_item(uid)
	item.affixes = []  # exact numbers without random affixes
	item.upgrade_level = upgrade
	return uid


func _check_defs() -> bool:
	var weapons := 0
	for id: StringName in Armory.defs:
		if Armory.get_def(id).is_weapon():
			weapons += 1
	return _expect(weapons == 15, "weapons %d (design: 15)" % weapons) \
		and _expect(Armory.get_def(&"scrap_armor") != null and Armory.get_def(&"school_bag") != null, "armor/bag defs") \
		and _expect(Armory.affixes.size() == 9, "affixes %d" % Armory.affixes.size())


func _check_base_stats() -> bool:
	var pistol := Armory.get_item_stats(_plain(&"pistol"))
	var shotgun := Armory.get_item_stats(_plain(&"shotgun"))
	var vest := Armory.get_item_stats(_plain(&"flak_vest"))
	return _expect(_near(pistol["damage"], 18) and _near(pistol["attack_interval"], 0.35)
			and _near(pistol["range"], 18) and _near(pistol["noise"], 15) and pistol["magazine"] == 12,
			"pistol %s" % pistol) \
		and _expect(_near(shotgun["damage"], 9) and shotgun["pellets"] == 8, "shotgun %s" % shotgun) \
		and _expect(pistol["combat_class"] == Enums.CombatClass.GUN and pistol["light"], "pistol class/light") \
		and _expect(pistol["ammo_id"] == &"ammo_pistol" and shotgun["ammo_id"] == &"ammo_shell", "ammo ids") \
		and _expect(Economy.get_def(pistol["ammo_id"]) != null, "ammo has no ResourceDef") \
		and _expect(_near(vest["defense"], 22) and _near(vest["noise_mod"], 1.5), "flak vest %s" % vest)


func _check_rarity_upgrade() -> bool:
	var rifle := Armory.get_item_stats(_plain(&"rifle", Enums.Rarity.RARE, 3))
	var armor := Armory.get_item_stats(_plain(&"scrap_armor", Enums.Rarity.EPIC, 5))
	return _expect(_near(rifle["damage"], 18 * 1.3 * 1.18), "rare rifle +3 damage %f" % rifle["damage"]) \
		and _expect(_near(armor["defense"], 32 * 1.5 * 1.4), "epic scrap armor +5 defense %f" % armor["defense"]) \
		and _expect(rifle["essence_slots"] == 1 and armor["essence_slots"] == 2, "essence slots")


func _check_broken() -> bool:
	var uid := _plain(&"hammer")
	Armory.wear(uid, 1000.0)
	var stats := Armory.get_item_stats(uid)
	return _expect(stats["broken"] and _near(stats["damage"], 18), "broken hammer %s" % stats)


func _check_affix_rolls() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ok := true
	for rarity in Enums.Rarity.values():
		var uid := Armory.create_item(&"rifle", rarity, rng)
		var item := Armory.get_item(uid)
		ok = _expect(item.affixes.size() == Armory.RARITY_AFFIXES[rarity],
			"rarity %d rolled %d affixes" % [rarity, item.affixes.size()]) and ok
		var seen := {}
		for entry: Dictionary in item.affixes:
			var affix: Affix = Armory.affixes[entry["id"]]
			ok = _expect(Enums.EquipSlot.MAIN in affix.allowed_slots, "%s not allowed on weapons" % affix.id) and ok
			ok = _expect(entry["value"] >= affix.min_value and entry["value"] <= affix.max_value,
				"%s value %d out of range" % [affix.id, entry["value"]]) and ok
			ok = _expect(not seen.has(affix.id), "duplicate affix %s" % affix.id) and ok
			seen[affix.id] = true
	# Affix math: attack +10% on a common pistol.
	var uid := _plain(&"pistol")
	Armory.get_item(uid).affixes = [{"id": &"attack", "value": 10}, {"id": &"quiet", "value": -2}]
	var stats := Armory.get_item_stats(uid)
	return ok and _expect(_near(stats["damage"], 19.8) and _near(stats["noise"], 13), "affix math %s" % stats)


func _check_equip_rules() -> bool:
	var rifle := _plain(&"rifle")
	var dagger := _plain(&"dagger")
	var hoodie := _plain(&"hoodie")
	var ok := _expect(not Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.SUB, rifle), "rifle went in SUB") \
		and _expect(Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.SUB, dagger), "dagger in SUB failed") \
		and _expect(not Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.HEAD, hoodie), "hoodie went on HEAD") \
		and _expect(Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, rifle), "rifle in MAIN failed") \
		and _expect(Armory.get_combat_class(Armory.PLAYER_ID) == Enums.CombatClass.GUN, "player class") \
		and _expect(not Armory.equip(RESIDENT, Enums.EquipSlot.MAIN, rifle), "took gear another owner wears") \
		and _expect(Armory.equip(RESIDENT, Enums.EquipSlot.BODY, hoodie), "resident equip failed") \
		and _expect(Armory.get_equipped(RESIDENT, Enums.EquipSlot.BODY) == hoodie, "resident get_equipped")
	# Replacing a slot sends the old item back to storage.
	var smg := _plain(&"smg")
	ok = _expect(Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, smg), "swap main") and ok
	ok = _expect(rifle in Armory.list_storage(), "replaced rifle not in storage") and ok
	ok = _expect(Armory.unequip(RESIDENT, Enums.EquipSlot.BODY) and hoodie in Armory.list_storage(), "unequip") and ok
	for slot in [Enums.EquipSlot.MAIN, Enums.EquipSlot.SUB]:
		Armory.unequip(Armory.PLAYER_ID, slot)
	return ok


func _check_noise_cap() -> bool:
	for id: StringName in [&"riot_helmet", &"scrap_armor", &"knee_guards"]:
		var uid := _plain(id)
		Armory.equip(RESIDENT, Armory.get_def(id).slot, uid)
	var heavy := Armory.get_owner_summary(RESIDENT)
	for slot in [Enums.EquipSlot.HEAD, Enums.EquipSlot.BODY, Enums.EquipSlot.LEGS]:
		Armory.unequip(RESIDENT, slot)
	Armory.equip(RESIDENT, Enums.EquipSlot.LEGS, _plain(&"sneakers"))
	var light := Armory.get_owner_summary(RESIDENT)
	Armory.unequip(RESIDENT, Enums.EquipSlot.LEGS)
	return _expect(_near(heavy["armor_noise"], 3.0), "noise not capped: %f" % heavy["armor_noise"]) \
		and _expect(_near(heavy["defense"], 14 + 32 + 14), "summary defense %f" % heavy["defense"]) \
		and _expect(_near(heavy["move_speed_mult"], 0.9), "scrap armor speed") \
		and _expect(_near(light["armor_noise"], -1.0), "sneakers noise %f" % light["armor_noise"])


func _check_bag() -> bool:
	var before: Vector2i = Armory.get_owner_summary(Armory.PLAYER_ID)["bag_grid"]
	Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.BAG, _plain(&"military_pack"))
	var after: Vector2i = Armory.get_owner_summary(Armory.PLAYER_ID)["bag_grid"]
	Armory.unequip(Armory.PLAYER_ID, Enums.EquipSlot.BAG)
	return _expect(before == Armory.DEFAULT_BAG_GRID and after == Vector2i(6, 7), "bag grid %s -> %s" % [before, after])


func _check_lost() -> bool:
	var uid := _plain(&"machete")
	Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, uid)
	Armory.set_lost(uid, true)
	var lost_ok := Armory.get_item(uid).owner == Armory.LOST_ID \
		and Armory.get_equipped(Armory.PLAYER_ID, Enums.EquipSlot.MAIN) == &"" \
		and not Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, uid)
	Armory.set_lost(uid, false)
	return _expect(lost_ok, "lost gear still usable") and _expect(uid in Armory.list_storage(), "recovered gear not in storage")


func _check_save() -> bool:
	var uid := Armory.create_item(&"longsword", Enums.Rarity.EPIC)
	Armory.equip(RESIDENT, Enums.EquipSlot.MAIN, uid)
	var before := Armory.get_item_stats(uid)
	var data := Armory.save_data()
	var round_trip: Dictionary = JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(data))))
	Armory.load_data(round_trip)
	var after := Armory.get_item_stats(uid)
	var next := Armory.create_item(&"club")
	return _expect(var_to_str(before) == var_to_str(after), "stats differ after save:\n%s\n%s" % [before, after]) \
		and _expect(Armory.get_equipped(RESIDENT, Enums.EquipSlot.MAIN) == uid, "equip lost after save") \
		and _expect(next != uid and not next in [&""], "uid counter reset")
