extends RefCounted
## Upgrade / repair / crafting (A-09): design 05 cost table, facility caps, dexterity discount,
## upgrade transfer, repair and auto repair, recipe data, crafted rarity distribution.
## Economy, Armory and GameState flags are restored afterwards; nothing is written to disk.

const RESIDENT := &"res_test_upgrade"
## Facility Lv3 with a dex 5 worker: no cap, no discount.
const FULL := {"facility_level": 3, "dex": 5}

var _saved_armory: Dictionary
var _saved_economy: Dictionary
var _saved_flags: Dictionary


func run() -> bool:
	_saved_armory = Armory.save_data().duplicate(true)
	_saved_economy = Economy.save_data().duplicate(true)
	_saved_flags = GameState.flags.duplicate(true)
	Armory.load_data({})
	var ok := _check_cost_table() and _check_discount() and _check_caps() and _check_reasons() \
		and _check_upgrade() and _check_family() and _check_transfer() and _check_repair() \
		and _check_auto_repair() and _check_recipes() and _check_craft() and _check_worker_craft() \
		and _check_rarity_distribution() and _check_save()
	Armory.load_data(_saved_armory)
	Economy.load_data(_saved_economy)
	GameState.flags = _saved_flags
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


## Exact storage contents (bypasses the storage cap so big numbers are possible).
func _stock(amounts: Dictionary) -> void:
	Economy.load_data({"amounts": amounts.duplicate()})


func _plain(def_id: StringName, upgrade := 0) -> StringName:
	var uid := Armory.create_item(def_id, Enums.Rarity.COMMON)
	var item := Armory.get_item(uid)
	item.affixes = []
	item.upgrade_level = upgrade
	return uid


func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or int(a[key]) != int(b[key]):
			return false
	return true


func _check_cost_table() -> bool:
	# Design 05 "강화" 비용: scrap 10n + parts n, rare parts (n-5) from +6, family x2 from +9.
	var table := {
		1: {&"scrap": 10, &"parts": 1},
		3: {&"scrap": 30, &"parts": 3},
		5: {&"scrap": 50, &"parts": 5},
		6: {&"scrap": 60, &"parts": 6, &"rare_parts": 1},
		8: {&"scrap": 80, &"parts": 8, &"rare_parts": 3},
		9: {&"scrap": 90, &"parts": 9, &"rare_parts": 4, &"vine_fiber": 2},
		10: {&"scrap": 100, &"parts": 10, &"rare_parts": 5, &"vine_fiber": 2},
	}
	for n: int in table:
		var cost := UpgradeRules.upgrade_cost(n)
		if not _expect(_same(cost, table[n]), "+%d cost %s, expected %s" % [n, cost, table[n]]):
			return false
	return _expect(_same(UpgradeRules.upgrade_cost(9, 0, &"neon_dust"),
		{&"scrap": 90, &"parts": 9, &"rare_parts": 4, &"neon_dust": 2}), "family material choice")


func _check_discount() -> bool:
	# Worker dex >= 8: -20%, each amount rounded up.
	return _expect(_same(UpgradeRules.upgrade_cost(1, 8), {&"scrap": 8, &"parts": 1}), "dex 8 +1") \
		and _expect(_same(UpgradeRules.upgrade_cost(6, 10), {&"scrap": 48, &"parts": 5, &"rare_parts": 1}), "dex 10 +6") \
		and _expect(_same(UpgradeRules.upgrade_cost(10, 9),
			{&"scrap": 80, &"parts": 8, &"rare_parts": 4, &"vine_fiber": 2}), "dex 9 +10") \
		and _expect(_same(UpgradeRules.upgrade_cost(5, 7), {&"scrap": 50, &"parts": 5}), "dex 7 has no discount")


func _check_caps() -> bool:
	var caps := [0, 3, 6, 10]
	for level in caps.size():
		if not _expect(UpgradeRules.facility_cap(level) == caps[level], "facility Lv%d cap" % level):
			return false
	_stock({&"scrap": 500, &"parts": 50})
	var at3 := _plain(&"pistol", 3)
	var lv1 := Armory.preview_upgrade(at3, {"facility_level": 1, "dex": 5})
	var lv2 := Armory.preview_upgrade(at3, {"facility_level": 2, "dex": 5})
	var at6 := Armory.preview_upgrade(_plain(&"pistol", 6), {"facility_level": 2, "dex": 5})
	return _expect(lv1["reason"] == &"facility_level" and lv1["max_level"] == 3, "Lv1 stops at +3: %s" % lv1["reason"]) \
		and _expect(lv2["ok"] and lv2["max_level"] == 6, "Lv2 allows +4: %s" % lv2["reason"]) \
		and _expect(at6["reason"] == &"facility_level", "Lv2 stops at +6") \
		and _expect(UpgradeRules.facility_for_slot(Enums.EquipSlot.MAIN) == &"workshop"
			and UpgradeRules.facility_for_slot(Enums.EquipSlot.BODY) == &"sewing_room"
			and UpgradeRules.facility_for_slot(Enums.EquipSlot.BAG) == &"sewing_room", "facility per slot")


func _check_reasons() -> bool:
	_stock({})
	var uid := _plain(&"rifle")
	var no_fac := Armory.preview_upgrade(uid, {"facility_level": 0, "dex": 5})
	var no_worker := Armory.preview_upgrade(uid, {"facility_level": 1, "dex": 0})
	var poor := Armory.preview_upgrade(uid, FULL)
	var maxed := Armory.preview_upgrade(_plain(&"rifle", 10), FULL)
	var lost_uid := _plain(&"rifle")
	Armory.set_lost(lost_uid, true)
	var lost := Armory.preview_upgrade(lost_uid, FULL)
	return _expect(no_fac["reason"] == &"no_facility", "no facility: %s" % no_fac["reason"]) \
		and _expect(no_worker["reason"] == &"no_worker", "no worker: %s" % no_worker["reason"]) \
		and _expect(poor["reason"] == &"cost" and _same(poor["missing"], {&"scrap": 10, &"parts": 1}),
			"cost missing %s" % poor["missing"]) \
		and _expect(maxed["reason"] == &"max_level" and maxed["cost"].is_empty(), "+10 is max") \
		and _expect(lost["reason"] == &"lost", "lost item") \
		and _expect(Armory.preview_upgrade(&"nope")["reason"] == &"no_item", "unknown uid") \
		and _expect(not Armory.upgrade(uid, FULL) and Armory.get_item(uid).upgrade_level == 0, "upgrade without cost")


func _check_upgrade() -> bool:
	_stock({&"scrap": 10, &"parts": 1})
	var uid := _plain(&"pistol")
	var preview := Armory.preview_upgrade(uid, FULL)
	var ok := Armory.upgrade(uid, FULL)
	var stats := Armory.get_item_stats(uid)
	var vest := _plain(&"flak_vest", 2)
	_stock({&"scrap": 30, &"parts": 3})
	var vest_ok := Armory.upgrade(vest, {"facility_level": 1, "dex": 3})
	return _expect(ok and Armory.get_item(uid).upgrade_level == 1, "pistol +1") \
		and _expect(Economy.get_amount(&"scrap") == 0 and Economy.get_amount(&"parts") == 0, "cost paid") \
		and _expect(is_equal_approx(preview["stats_after"]["damage"], 18 * 1.06)
			and is_equal_approx(stats["damage"], preview["stats_after"]["damage"]), "stats_after %s" % preview["stats_after"]) \
		and _expect(is_equal_approx(preview["stats"]["damage"], 18.0), "stats before") \
		and _expect(vest_ok and is_equal_approx(Armory.get_item_stats(vest)["defense"], 22 * 1.24), "vest +3 at sewing room Lv1")


func _check_family() -> bool:
	_stock({&"stone_shard": 5, &"scrap": 90, &"parts": 9, &"rare_parts": 4})
	var uid := _plain(&"rifle", 8)
	var auto := Armory.preview_upgrade(uid, FULL)
	var chosen := Armory.preview_upgrade(uid, {"facility_level": 3, "dex": 5, "family_mat": &"water_moss"})
	var low := Armory.preview_upgrade(_plain(&"rifle", 7), FULL)
	var ok := Armory.upgrade(uid, FULL)
	return _expect(auto["family_mat"] == &"stone_shard" and auto["family_options"].size() == 4,
			"family default = most in stock: %s" % auto["family_mat"]) \
		and _expect(chosen["cost"].get(&"water_moss", 0) == 2 and chosen["reason"] == &"cost", "family choice") \
		and _expect(low["family_options"].is_empty() and low["family_mat"] == &"", "+8 has no family material") \
		and _expect(ok and Economy.get_amount(&"stone_shard") == 3 and Economy.get_amount(&"rare_parts") == 0, "+9 paid")


func _check_transfer() -> bool:
	_stock({&"scrap": 40})
	var rifle := _plain(&"rifle", 6)
	var smg := _plain(&"smg")
	var vest := _plain(&"flak_vest")
	var high := _plain(&"shotgun", 5)
	var mismatch := Armory.preview_transfer(rifle, vest, FULL)
	var no_gain := Armory.preview_transfer(rifle, high, FULL)
	var preview := Armory.preview_transfer(rifle, smg, FULL)
	var ok := Armory.transfer_upgrade(rifle, smg, FULL)
	return _expect(mismatch["reason"] == &"slot_mismatch", "transfer to armor: %s" % mismatch["reason"]) \
		and _expect(no_gain["reason"] == &"no_gain", "+6 -> +5 target gains nothing") \
		and _expect(preview["ok"] and preview["result_level"] == 4, "preview %s" % preview) \
		and _expect(ok and Armory.get_item(smg).upgrade_level == 4 and Armory.get_item(rifle).upgrade_level == 0,
			"transfer levels") \
		and _expect(Economy.get_amount(&"scrap") == 20, "transfer costs 20 scrap") \
		and _expect(Armory.preview_transfer(rifle, rifle, FULL)["reason"] == &"same_item", "same item")


func _check_repair() -> bool:
	_stock({&"scrap": 10})
	var uid := _plain(&"machete")
	var full := Armory.preview_repair(uid, FULL)
	Armory.wear(uid, 35.0)
	var preview := Armory.preview_repair(uid, FULL)
	var no_fac := Armory.preview_repair(uid, {"facility_level": 0, "dex": 0})
	var ok := Armory.repair(uid, FULL)
	var hat := _plain(&"cloth_hat")
	Armory.wear(hat, 0.5)
	var tiny := Armory.preview_repair(hat, FULL)
	return _expect(full["reason"] == &"full", "undamaged: %s" % full["reason"]) \
		and _expect(preview["ok"] and preview["cost"][&"scrap"] == 4, "35 lost -> 4 scrap: %s" % preview["cost"]) \
		and _expect(no_fac["reason"] == &"no_facility", "repair needs facility") \
		and _expect(ok and is_equal_approx(Armory.get_item(uid).durability, 100.0) and Economy.get_amount(&"scrap") == 6,
			"repaired") \
		and _expect(tiny["cost"][&"scrap"] == 1 and tiny["facility"] == &"sewing_room", "any damage costs 1") \
		and _expect(UpgradeRules.repair_cost(40.0) == 4 and UpgradeRules.repair_cost(41.0) == 5, "repair cost rounding")


func _check_auto_repair() -> bool:
	_stock({&"scrap": 6})
	Armory.set_auto_repair(false)
	var off := Armory.run_auto_repair(&"workshop", -1, FULL)
	Armory.set_auto_repair(true)
	var no_worker := Armory.run_auto_repair(&"workshop", -1, {"facility_level": 1, "dex": 0})
	Armory.load_data({"auto_repair": true})
	var worn := _plain(&"pipe_wrench")
	Armory.equip(RESIDENT, Enums.EquipSlot.MAIN, worn)
	Armory.wear(worn, 20.0)  # equipped: repaired first, 2 scrap
	var stored := _plain(&"hammer")
	Armory.wear(stored, 50.0)  # 5 scrap wanted, 4 left -> +40
	var armor := _plain(&"hoodie")
	Armory.wear(armor, 30.0)  # sewing room, not touched by the workshop
	var result := Armory.run_auto_repair(&"workshop", -1, FULL)
	var capped := Armory.run_auto_repair(&"sewing_room", 0, FULL)
	return _expect(off["reason"] == &"disabled" and off["scrap"] == 0, "auto repair off") \
		and _expect(no_worker["reason"] == &"no_worker", "auto repair needs a worker") \
		and _expect(result["scrap"] == 6 and Economy.get_amount(&"scrap") == 0, "spent %d" % result["scrap"]) \
		and _expect(is_equal_approx(Armory.get_item(worn).durability, 100.0), "worn gear repaired first") \
		and _expect(is_equal_approx(Armory.get_item(stored).durability, 90.0), "partial repair %f" % Armory.get_item(stored).durability) \
		and _expect(is_equal_approx(Armory.get_item(armor).durability, 70.0), "armor not repaired at workshop") \
		and _expect(capped["scrap"] == 0 and capped["repaired"].is_empty(), "budget 0 repairs nothing")


func _check_recipes() -> bool:
	# Design 05 table: 34, plus 5 vehicles (02 "탈것").
	if not _expect(Armory.recipes.size() == 39, "recipes %d (design 05 table: 34 + vehicles 5)" % Armory.recipes.size()):
		return false
	for id: StringName in Armory.recipes:
		var recipe: Recipe = Armory.get_recipe(id)
		for input: StringName in recipe.inputs:
			if not _expect(Economy.get_def(input) != null, "%s: unknown input %s" % [id, input]):
				return false
		# Vehicles are crafted by the player, like equipment.
		var equipment := Armory.get_def(recipe.output_id) != null or Garage.is_vehicle(recipe.output_id)
		if not _expect(equipment or Economy.get_def(recipe.output_id) != null, "%s: unknown output" % id) \
				or not _expect(BaseDB.get_building(recipe.facility) != null, "%s: unknown facility %s" % [id, recipe.facility]) \
				or not _expect(equipment != recipe.by_worker, "%s: equipment is crafted by the player" % id):
			return false
	var pistol_ammo := Armory.get_recipe(&"ammo_pistol")
	var shells := Armory.get_recipe(&"ammo_shell")
	var kit := Armory.get_recipe(&"first_aid_kit")
	return _expect(pistol_ammo.facility == &"workshop" and pistol_ammo.output_qty == 20
			and _same(pistol_ammo.inputs, {&"scrap": 3}), "ammo_pistol") \
		and _expect(shells.output_qty == 12 and _same(shells.inputs, {&"scrap": 4, &"parts": 1}), "ammo_shell") \
		and _expect(kit.facility == &"infirmary" and _same(kit.inputs, {&"cloth": 1, &"herbs": 2}), "first_aid_kit") \
		and _expect(_same(Armory.get_recipe(&"hiking_pack").inputs, {&"cloth": 10, &"vine_fiber": 5})
			and _same(Armory.get_recipe(&"military_pack").inputs, {&"cloth": 20, &"vine_fiber": 10})
			and _same(Armory.get_recipe(&"large_pack").inputs, {&"cloth": 40, &"vine_fiber": 20}), "bag steps x2") \
		and _expect(Armory.get_recipe(&"sniper_rifle").blueprint_required
			and not Armory.get_recipe(&"hiking_pack").blueprint_required, "blueprints") \
		and _expect(Armory.list_recipes(&"workshop", 1).size() == 4 and Armory.list_recipes(&"infirmary").size() == 2,
			"list_recipes")


func _check_craft() -> bool:
	GameState.flags.erase(&"blueprint_hammer")
	_stock({&"wood": 5, &"scrap": 8})
	var locked := Armory.preview_craft(&"hammer", FULL)
	GameState.set_flag(&"blueprint_hammer")
	var no_worker := Armory.preview_craft(&"hammer", {"facility_level": 1, "dex": 0})
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var made := Armory.craft(&"hammer", FULL, rng)
	var worker_only := Armory.preview_craft(&"ammo_pistol", FULL)
	var again := Armory.craft(&"hammer", FULL)
	return _expect(locked["reason"] == &"blueprint" and locked["blueprint_flag"] == &"blueprint_hammer",
			"blueprint lock: %s" % locked["reason"]) \
		and _expect(no_worker["reason"] == &"no_worker", "craft needs a worker") \
		and _expect(made["ok"] and Armory.has_item(made["uid"]) and Armory.get_item(made["uid"]).def_id == &"hammer"
			and Armory.get_item(made["uid"]).owner == Armory.STORAGE_ID, "crafted %s" % made) \
		and _expect(Economy.get_amount(&"wood") == 0 and Economy.get_amount(&"scrap") == 0, "craft paid") \
		and _expect(worker_only["reason"] == &"worker_only", "ammo is a worker job") \
		and _expect(not again["ok"] and again["reason"] == &"cost", "second craft has no materials")


func _check_worker_craft() -> bool:
	_stock({&"scrap": 50, &"parts": 50})
	var limited := Armory.craft_by_worker(&"ammo_rifle", 3, {&"scrap": 10, &"parts": 5})
	var from_economy := Armory.craft_by_worker(&"ammo_shell", 2)
	var wrong := Armory.craft_by_worker(&"hammer", 1)
	return _expect(limited["ok"] and limited["count"] == 2, "limited by stock: %s" % limited) \
		and _expect(_same(limited["changes"], {&"scrap": -8, &"parts": -2, &"ammo_rifle": 40}), "changes %s" % limited["changes"]) \
		and _expect(_same(from_economy["produced"], {&"ammo_shell": 24}) and _same(from_economy["consumed"], {&"scrap": 8, &"parts": 2}),
			"from economy %s" % from_economy) \
		and _expect(Economy.get_amount(&"scrap") == 50 and Economy.get_amount(&"ammo_shell") == 0, "Economy untouched") \
		and _expect(wrong["reason"] == &"not_worker_recipe", "hammer is not a worker recipe")


func _check_rarity_distribution() -> bool:
	if not _expect(is_equal_approx(UpgradeRules.craft_higher_chance(0), 0.05)
			and is_equal_approx(UpgradeRules.craft_higher_chance(10), 0.40), "5% + dex x 3.5%"):
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	var trials := 4000
	for dex in [0, 4, 10]:
		var higher := 0
		for i in trials:
			if UpgradeRules.roll_craft_rarity(dex, rng) >= Enums.Rarity.UNCOMMON:
				higher += 1
		var rate := float(higher) / trials
		var want := UpgradeRules.craft_higher_chance(dex)
		if not _expect(absf(rate - want) < 0.03, "dex %d: %.3f uncommon+ (want %.3f)" % [dex, rate, want]):
			return false
	# Same seed -> same crafted rarity.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 3
	b.seed = 3
	var same := true
	for i in 50:
		same = same and UpgradeRules.roll_craft_rarity(7, a) == UpgradeRules.roll_craft_rarity(7, b)
	return _expect(same, "rarity roll not repeatable")


func _check_save() -> bool:
	Armory.set_auto_repair(true)
	var data: Dictionary = JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(Armory.save_data()))))
	Armory.load_data({})
	var cleared := Armory.auto_repair_enabled
	Armory.load_data(data)
	return _expect(not cleared and Armory.auto_repair_enabled, "auto repair toggle saved")
