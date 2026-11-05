extends RefCounted
## Essences (A-10): design 06 table numbers, slots per rarity, slot opening, engraving cost and
## reasons, overwrite / removal, same-element x1.5, combos and their proc rate, accessory resist,
## refining (3 -> 1, 2 with the 마물 흔적 worker), disassembly 50%, +9 family material, save round trip.
## Economy and Armory are restored afterwards; nothing is written to disk.

## Essence workshop Lv2 with a worker, no 마물 흔적.
const WS := {"facility_level": 2, "worker": true, "mark": false}
const G := Enums.Element.GREEN
const S := Enums.Element.STONE
const W := Enums.Element.WATER
const L := Enums.Element.LIGHT

## Design 06 "정수" table, every grade: essence id -> effect_params.
const TABLE := {
	&"essence_green_low": {"root_chance": 0.10, "root_sec": 1.0, "lifesteal_ratio": 0.02},
	&"essence_green_mid": {"root_chance": 0.15, "root_sec": 1.5, "lifesteal_ratio": 0.04},
	&"essence_green_high": {"root_chance": 0.20, "root_sec": 2.0, "lifesteal_ratio": 0.06},
	&"essence_stone_low": {"stagger_bonus": 0.20, "guard_break_chance": 0.10},
	&"essence_stone_mid": {"stagger_bonus": 0.35, "guard_break_chance": 0.15},
	&"essence_stone_high": {"stagger_bonus": 0.50, "guard_break_chance": 0.25},
	&"essence_water_low": {"slow_chance": 0.20, "slow_sec": 2.0, "wet_light_bonus": 0.25},
	&"essence_water_mid": {"slow_chance": 0.30, "slow_sec": 2.0, "wet_light_bonus": 0.25},
	&"essence_water_high": {"slow_chance": 0.40, "slow_sec": 2.0, "wet_light_bonus": 0.25},
	&"essence_light_low": {"chain_chance": 0.15, "chain_damage_ratio": 0.30, "chain_targets": 2},
	&"essence_light_mid": {"chain_chance": 0.25, "chain_damage_ratio": 0.45, "chain_targets": 2},
	&"essence_light_high": {"chain_chance": 0.35, "chain_damage_ratio": 0.60, "chain_targets": 2},
}

var _saved_armory: Dictionary
var _saved_economy: Dictionary


func run() -> bool:
	_saved_armory = Armory.save_data().duplicate(true)
	_saved_economy = Economy.save_data().duplicate(true)
	Armory.load_data({})
	var ok := _check_defs() and _check_table() and _check_slots() and _check_open_slot() \
		and _check_engrave_cost() and _check_engrave() and _check_overwrite_remove() \
		and _check_same_element() and _check_combos() and _check_accessory() and _check_refine() \
		and _check_disassemble() and _check_family() and _check_save() and _check_debug()
	Armory.load_data(_saved_armory)
	Economy.load_data(_saved_economy)
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _stock(amounts: Dictionary) -> void:
	Economy.load_data({"amounts": amounts.duplicate()})


## A plain item (no affixes) in storage.
func _plain(def_id: StringName, rarity: int = Enums.Rarity.COMMON) -> StringName:
	var uid := Armory.create_item(def_id, rarity)
	Armory.get_item(uid).affixes = []
	return uid


## Item with these engravings set directly (bypasses cost; for effect checks).
func _engraved(def_id: StringName, rarity: int, ids: Array) -> StringName:
	var uid := _plain(def_id, rarity)
	var item := Armory.get_item(uid)
	for i in ids.size():
		item.engravings.append({"slot_index": i, "essence_def_id": ids[i]})
	return uid


func _params_match(params: Dictionary, expected: Dictionary) -> bool:
	for key in expected:
		if not params.has(key) or not is_equal_approx(float(params[key]), float(expected[key])):
			return false
	return true


func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or int(a[key]) != int(b[key]):
			return false
	return true


func _check_defs() -> bool:
	var ids := EssenceRules.list_essences()
	if not _expect(ids.size() == 12, "12 essences, got %d" % ids.size()):
		return false
	for element in [G, S, W, L]:
		for grade in [Enums.EssenceGrade.LOW, Enums.EssenceGrade.MID, Enums.EssenceGrade.HIGH]:
			var id := EssenceRules.make_id(element, grade)
			var def := EssenceRules.get_essence(id)
			if not _expect(def != null and def.id == id and def.element == element and def.grade == grade
					and def.size == Vector2i(1, 1), "essence def %s" % id):
				return false
			# Accessory resist +20 / 30 / 40%.
			if not _expect(is_equal_approx(def.resist_ratio, [0.2, 0.3, 0.4][grade]), "%s resist" % id):
				return false
	if not _expect(EssenceRules.make_id(Enums.Element.NONE, 0) == &"" and ids[0] == &"essence_green_high",
			"id rule"):
		return false
	# Every pair of different elements has exactly one combo, order does not matter.
	if not _expect(EssenceRules.combos().size() == 6, "6 combos"):
		return false
	var names := {[G, S]: "가시 덤불", [G, W]: "늪", [G, L]: "광합성", [S, W]: "진흙", [S, L]: "파편 폭발",
		[W, L]: "감전 웅덩이"}
	for pair: Array in names:
		var combo := EssenceRules.get_combo(pair[0], pair[1])
		var reverse := EssenceRules.get_combo(pair[1], pair[0])
		if not _expect(combo != null and combo == reverse and combo.name == names[pair]
				and is_equal_approx(combo.proc_rate, 0.2) and is_equal_approx(combo.proc_rate_high, 0.3),
				"combo %s" % [pair]):
			return false
	return _expect(EssenceRules.get_combo(G, G) == null, "no combo for one element") \
		and _expect(EssenceRules.get_combo(G, L).trigger == &"kill" and EssenceRules.get_combo(S, L).trigger == &"kill",
			"kill-triggered combos") \
		and _expect(_params_match(EssenceRules.get_combo(G, S).effect_params, {"zone_sec": 3, "dps": 5, "slow_ratio": 0.3}),
			"thorn bush params") \
		and _expect(_params_match(EssenceRules.get_combo(G, W).effect_params, {"zone_radius": 2, "zone_sec": 3, "slow_ratio": 0.5}),
			"swamp params") \
		and _expect(_params_match(EssenceRules.get_combo(G, L).effect_params, {"radius": 5, "heal": 10}), "photosynthesis") \
		and _expect(_params_match(EssenceRules.get_combo(S, W).effect_params, {"duration_sec": 3}), "mud") \
		and _expect(_params_match(EssenceRules.get_combo(S, L).effect_params, {"radius": 2, "damage_ratio": 0.5}), "shard") \
		and _expect(_params_match(EssenceRules.get_combo(W, L).effect_params,
			{"wet_chain_range_mult": 2, "wet_chain_damage_mult": 1.5}), "shock puddle")


## Completion condition: one engraving of each essence gives the design 06 numbers in get_item_stats().
func _check_table() -> bool:
	for id: StringName in TABLE:
		var stats := Armory.get_item_stats(_engraved(&"machete", Enums.Rarity.RARE, [id]))
		var def := EssenceRules.get_essence(id)
		var effects: Array = stats["essence_effects"]
		if not _expect(stats["element"] == def.element and stats["magic"] and stats["combo"] == null
				and effects.size() == 1, "%s stats %s" % [id, stats]):
			return false
		var effect: Dictionary = effects[0]
		if not _expect(_params_match(effect["params"], TABLE[id]) and is_equal_approx(effect["mult"], 1.0)
				and effect["essence_ids"] == [id] and effect["grade"] == def.grade, "%s effect %s" % [id, effect]):
			return false
	var green := Armory.get_item_stats(_engraved(&"machete", Enums.Rarity.RARE, [&"essence_green_low"]))
	var light := Armory.get_item_stats(_engraved(&"rifle", Enums.Rarity.RARE, [&"essence_light_mid"]))
	return _expect(green["display_name"] == "덩굴 감긴 마체테", "name %s" % green["display_name"]) \
		and _expect(light["display_name"] == "번개 서린 소총", "name %s" % light["display_name"])


func _check_slots() -> bool:
	# Design 05 "등급": 0 / 1 / 1 / 2 / 2 for weapons and accessories; armor and bags take none.
	for rarity in 5:
		var weapon := _plain(&"pistol", rarity)
		var ring := _plain(&"ring", rarity)
		var expected: int = [0, 1, 1, 2, 2][rarity]
		if not _expect(Armory.essence_slot_count(weapon) == expected and Armory.essence_slot_count(ring) == expected
				and Armory.get_engravings(weapon).size() == expected, "slots at rarity %d" % rarity):
			return false
	var vest := _plain(&"flak_vest", Enums.Rarity.EPIC)
	var plain_stats := Armory.get_item_stats(_plain(&"rifle"))
	return _expect(Armory.essence_slot_count(vest) == 0 and not Armory.is_engravable(vest), "armor not engravable") \
		and _expect(plain_stats["element"] == Enums.Element.NONE and plain_stats["essence_effects"].is_empty()
			and plain_stats["combo"] == null and not plain_stats["magic"] and plain_stats["display_name"] == "소총",
			"plain weapon stats")


func _check_open_slot() -> bool:
	var uid := _plain(&"pipe_wrench")
	_stock({&"parts": 3, &"scrap": 10})
	var p := Armory.preview_open_slot(uid, WS)
	if not _expect(p["ok"] and _same(p["cost"], {&"parts": 3, &"scrap": 10}) and p["stats_after"]["essence_slots"] == 1
			and Armory.essence_slot_count(uid) == 0, "open slot preview %s" % p):
		return false
	if not _expect(Armory.open_slot(uid, WS) and Armory.essence_slot_count(uid) == 1
			and Economy.get_amount(&"parts") == 0 and Economy.get_amount(&"scrap") == 0, "open slot pays"):
		return false
	_stock({&"parts": 30, &"scrap": 100})
	var uncommon := _plain(&"pipe_wrench", Enums.Rarity.UNCOMMON)
	var fresh := _plain(&"club")
	return _expect(Armory.preview_open_slot(uid, WS)["reason"] == &"already_open", "already open") \
		and _expect(Armory.preview_open_slot(uncommon, WS)["reason"] == &"has_slots", "has slots") \
		and _expect(Armory.preview_open_slot(_plain(&"ring"), WS)["reason"] == &"not_weapon", "ring") \
		and _expect(Armory.preview_open_slot(fresh, {"facility_level": 0, "worker": true})["reason"] == &"no_facility", "no ws") \
		and _expect(Armory.preview_open_slot(fresh, {"facility_level": 1, "worker": false})["reason"] == &"no_worker", "no worker") \
		and _expect(Armory.get_item_stats(uid)["opened_slot"], "opened flag in stats")


func _check_engrave_cost() -> bool:
	# Design 06: 1 essence + family material of the element (2 / 4 / 6) + scrap 5.
	return _expect(_same(EssenceRules.engrave_cost(&"essence_green_low"),
			{&"essence_green_low": 1, &"vine_fiber": 2, &"scrap": 5}), "green low cost") \
		and _expect(_same(EssenceRules.engrave_cost(&"essence_stone_mid"),
			{&"essence_stone_mid": 1, &"stone_shard": 4, &"scrap": 5}), "stone mid cost") \
		and _expect(_same(EssenceRules.engrave_cost(&"essence_water_high"),
			{&"essence_water_high": 1, &"water_moss": 6, &"scrap": 5}), "water high cost") \
		and _expect(_same(EssenceRules.engrave_cost(&"essence_light_low"),
			{&"essence_light_low": 1, &"neon_dust": 2, &"scrap": 5}), "light low cost") \
		and _expect(EssenceRules.engrave_cost(&"nope").is_empty(), "unknown cost")


func _check_engrave() -> bool:
	var rifle := _plain(&"rifle", Enums.Rarity.UNCOMMON)
	_stock({})
	var reasons := {
		"cost": Armory.preview_engrave(rifle, &"essence_water_low", 0, WS),
		"no_facility": Armory.preview_engrave(rifle, &"essence_water_low", 0, {"facility_level": 0, "worker": true}),
		"no_worker": Armory.preview_engrave(rifle, &"essence_water_low", 0, {"facility_level": 1, "worker": false}),
		"bad_slot": Armory.preview_engrave(rifle, &"essence_water_low", 1, WS),
		"unknown_essence": Armory.preview_engrave(rifle, &"essence_fire_low", 0, WS),
		"no_slots": Armory.preview_engrave(_plain(&"rifle"), &"essence_water_low", 0, WS),
		"not_engravable": Armory.preview_engrave(_plain(&"scrap_armor", Enums.Rarity.EPIC), &"essence_water_low", 0, WS),
		"no_item": Armory.preview_engrave(&"it_nope", &"essence_water_low", 0, WS),
	}
	for reason: String in reasons:
		var p: Dictionary = reasons[reason]
		if not _expect(not p["ok"] and p["reason"] == StringName(reason), "reason %s: %s" % [reason, p["reason"]]):
			return false
	if not _expect(_same(reasons["cost"]["missing"], {&"essence_water_low": 1, &"water_moss": 2, &"scrap": 5}),
			"missing %s" % reasons["cost"]["missing"]):
		return false

	_stock({&"essence_water_low": 1, &"water_moss": 2, &"scrap": 5})
	var p := Armory.preview_engrave(rifle, &"essence_water_low", 0, WS)
	if not _expect(p["ok"] and p["replaces"] == &"" and p["stats_after"]["element"] == W
			and p["stats"]["element"] == Enums.Element.NONE, "engrave preview %s" % p):
		return false
	if not _expect(Armory.engrave(rifle, &"essence_water_low", 0, WS), "engrave"):
		return false
	var stats := Armory.get_item_stats(rifle)
	var item := Armory.get_item(rifle)
	Armory.set_lost(rifle, true)
	var lost := Armory.preview_engrave(rifle, &"essence_water_low", 0, WS)
	Armory.set_lost(rifle, false)
	return _expect(Economy.get_amount(&"essence_water_low") == 0 and Economy.get_amount(&"water_moss") == 0
			and Economy.get_amount(&"scrap") == 0, "engrave paid") \
		and _expect(stats["element"] == W and stats["engravings"] == [&"essence_water_low"], "engraved %s" % stats) \
		and _expect(item.engravings == [{"slot_index": 0, "essence_def_id": &"essence_water_low"}], "engravings record") \
		and _expect(lost["reason"] == &"lost", "lost item")


func _check_overwrite_remove() -> bool:
	var blade := _engraved(&"longsword", Enums.Rarity.RARE, [&"essence_green_low"])
	_stock({&"essence_stone_high": 1, &"stone_shard": 6, &"scrap": 5, &"essence_green_low": 0})
	var p := Armory.preview_engrave(blade, &"essence_stone_high", 0, WS)
	if not _expect(p["ok"] and p["replaces"] == &"essence_green_low", "overwrite preview %s" % p):
		return false
	if not _expect(Armory.engrave(blade, &"essence_stone_high", 0, WS)
			and Armory.get_engravings(blade) == [&"essence_stone_high"]
			and Economy.get_amount(&"essence_green_low") == 0, "overwrite: old essence is gone"):
		return false
	_stock({&"essence_stone_high": 5, &"stone_shard": 50, &"scrap": 50})
	if not _expect(Armory.preview_engrave(blade, &"essence_stone_high", 0, WS)["reason"] == &"same_essence",
			"same essence again"):
		return false
	var r := Armory.preview_remove_engraving(blade, 0, WS)
	if not _expect(r["ok"] and r["removed"] == &"essence_stone_high" and r["cost"].is_empty()
			and r["stats_after"]["element"] == Enums.Element.NONE, "remove preview %s" % r):
		return false
	var before := Economy.get_amount(&"essence_stone_high")
	return _expect(Armory.remove_engraving(blade, 0, WS) and Armory.get_engravings(blade) == [&""]
			and Armory.get_item(blade).engravings.is_empty(), "removed") \
		and _expect(Economy.get_amount(&"essence_stone_high") == before, "removal gives nothing back") \
		and _expect(Armory.preview_remove_engraving(blade, 0, WS)["reason"] == &"empty_slot", "empty slot") \
		and _expect(Armory.preview_remove_engraving(blade, 3, WS)["reason"] == &"bad_slot", "bad slot") \
		and _expect(Armory.preview_remove_engraving(blade, 0, {"facility_level": 0, "worker": false})["reason"]
			== &"empty_slot", "remove empty before facility")


func _check_same_element() -> bool:
	# Same essence twice: no combo, effect x1.5 on the grade-scaled numbers.
	var double := Armory.get_item_stats(_engraved(&"dagger", Enums.Rarity.EPIC, [&"essence_green_low", &"essence_green_low"]))
	var effects: Array = double["essence_effects"]
	if not _expect(double["combo"] == null and effects.size() == 1 and is_equal_approx(effects[0]["mult"], 1.5)
			and _params_match(effects[0]["params"], {"root_chance": 0.15, "root_sec": 1.5, "lifesteal_ratio": 0.03}),
			"green low x2 %s" % [effects]):
		return false
	var light := Armory.get_item_stats(_engraved(&"smg", Enums.Rarity.EPIC, [&"essence_light_high", &"essence_light_high"]))
	var water := Armory.get_item_stats(_engraved(&"smg", Enums.Rarity.EPIC, [&"essence_water_mid", &"essence_water_mid"]))
	# Mixed grades of one element: average, then x1.5 (가안).
	var mixed := Armory.get_item_stats(_engraved(&"smg", Enums.Rarity.EPIC, [&"essence_green_low", &"essence_green_high"]))
	return _expect(_params_match(light["essence_effects"][0]["params"],
			{"chain_chance": 0.525, "chain_damage_ratio": 0.9, "chain_targets": 2}), "light high x2 %s" % [light["essence_effects"]]) \
		and _expect(_params_match(water["essence_effects"][0]["params"], {"slow_chance": 0.45, "slow_sec": 2.0,
			"wet_light_bonus": 0.25}), "water mid x2 %s" % [water["essence_effects"]]) \
		and _expect(_params_match(mixed["essence_effects"][0]["params"], {"root_chance": 0.225, "root_sec": 2.25})
			and mixed["essence_effects"][0]["grade"] == Enums.EssenceGrade.HIGH, "mixed grades %s" % [mixed["essence_effects"]])


func _check_combos() -> bool:
	# Different elements: both effects + combo. 20%, or 30% when the average grade is Mid or higher.
	var thorn := Armory.get_item_stats(_engraved(&"spear", Enums.Rarity.EPIC, [&"essence_green_low", &"essence_stone_low"]))
	var low_mid := Armory.get_item_stats(_engraved(&"spear", Enums.Rarity.EPIC, [&"essence_stone_low", &"essence_water_mid"]))
	var mid_mid := Armory.get_item_stats(_engraved(&"spear", Enums.Rarity.LEGENDARY, [&"essence_stone_mid", &"essence_water_mid"]))
	var swamp := Armory.get_item_stats(_engraved(&"spear", Enums.Rarity.EPIC, [&"essence_water_high", &"essence_green_low"]))
	var one_slot := Armory.get_item_stats(_engraved(&"spear", Enums.Rarity.EPIC, [&"", &"essence_light_low"]))
	return _expect(thorn["combo"] != null and thorn["combo"]["id"] == &"thorn_bush"
			and is_equal_approx(thorn["combo"]["proc_rate"], 0.2) and thorn["essence_effects"].size() == 2
			and thorn["element"] == G and thorn["combo"]["elements"] == [G, S], "thorn bush %s" % [thorn["combo"]]) \
		and _expect(low_mid["combo"]["id"] == &"mud" and is_equal_approx(low_mid["combo"]["proc_rate"], 0.2), "low+mid 20%") \
		and _expect(is_equal_approx(mid_mid["combo"]["proc_rate"], 0.3), "mid+mid 30%") \
		and _expect(swamp["combo"]["id"] == &"swamp" and swamp["element"] == W
			and is_equal_approx(swamp["combo"]["proc_rate"], 0.3), "first slot is the attack element") \
		and _expect(one_slot["combo"] == null and one_slot["element"] == L, "only slot 2 filled")


func _check_accessory() -> bool:
	var ring := _engraved(&"ring", Enums.Rarity.EPIC, [&"essence_water_low", &"essence_water_high"])
	var badge := _engraved(&"badge", Enums.Rarity.RARE, [&"essence_light_mid"])
	var stats := Armory.get_item_stats(ring)
	if not _expect(stats["element"] == Enums.Element.NONE and stats["combo"] == null
			and is_equal_approx(stats["element_resist"][W], 0.6) and stats["essence_effects"].size() == 2, "ring %s" % stats):
		return false
	Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.ACCESSORY, badge)
	var summary := Armory.get_owner_summary(Armory.PLAYER_ID)
	Armory.unequip(Armory.PLAYER_ID, Enums.EquipSlot.ACCESSORY)
	return _expect(is_equal_approx(summary["element_resist"].get(L, 0.0), 0.3) and summary["element_resist"].size() == 1,
		"owner resist %s" % summary["element_resist"])


func _check_refine() -> bool:
	_stock({&"essence_green_low": 7})
	var p := Armory.preview_refine(&"essence_green_low", 2, WS)
	if not _expect(p["ok"] and p["input_qty"] == 3 and _same(p["cost"], {&"essence_green_low": 6})
			and _same(p["gain"], {&"essence_green_mid": 2}), "refine preview %s" % p):
		return false
	if not _expect(Armory.refine(&"essence_green_low", 2, WS) and Economy.get_amount(&"essence_green_low") == 1
			and Economy.get_amount(&"essence_green_mid") == 2, "refine 6 -> 2"):
		return false
	# 마물 흔적 worker: 2 per refine.
	_stock({&"essence_stone_mid": 2})
	var mark := {"facility_level": 2, "worker": true, "mark": true}
	if not _expect(Armory.preview_refine(&"essence_stone_mid", 1, WS)["reason"] == &"cost"
			and Armory.refine(&"essence_stone_mid", 1, mark) and Economy.get_amount(&"essence_stone_high") == 1
			and Economy.get_amount(&"essence_stone_mid") == 0, "mark refine 2 -> 1"):
		return false
	_stock({&"essence_light_low": 30, &"essence_light_high": 30})
	return _expect(Armory.preview_refine(&"essence_light_high", 1, WS)["reason"] == &"max_grade", "max grade") \
		and _expect(Armory.preview_refine(&"essence_light_low", 1, {"facility_level": 1, "worker": true})["reason"]
			== &"facility_level", "needs Lv2") \
		and _expect(Armory.preview_refine(&"essence_light_low", 1, {"facility_level": 0, "worker": true})["reason"]
			== &"no_facility", "no workshop") \
		and _expect(Armory.preview_refine(&"essence_light_low", 1, {"facility_level": 2, "worker": false})["reason"]
			== &"no_worker", "no worker") \
		and _expect(Armory.preview_refine(&"essence_light_low", 0, WS)["reason"] == &"bad_times", "times 0") \
		and _expect(Armory.preview_refine(&"wood", 1, WS)["reason"] == &"unknown_essence", "not an essence") \
		and _expect(EssenceRules.refine_output(&"essence_water_mid") == &"essence_water_high", "refine output")


func _check_disassemble() -> bool:
	# Roll distribution: 50% each.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1010
	var ids: Array = []
	for i in 1000:
		ids.append(&"essence_green_low")
	var back: int = EssenceRules.roll_disassemble(ids, rng).get(&"essence_green_low", 0)
	if not _expect(back > 450 and back < 550, "disassemble return rate %d / 1000" % back):
		return false
	var plain := _plain(&"rifle", Enums.Rarity.RARE)
	var worn := _engraved(&"pistol", Enums.Rarity.EPIC, [&"essence_light_low"])
	Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.SUB, worn)
	var worn_reason: StringName = Armory.preview_disassemble(worn, WS)["reason"]
	Armory.unequip(Armory.PLAYER_ID, Enums.EquipSlot.SUB)
	if not _expect(worn_reason == &"not_in_storage", "worn: %s" % worn_reason) \
			or not _expect(Armory.preview_disassemble(plain, WS)["reason"] == &"no_engraving", "plain weapon") \
			or not _expect(Armory.preview_disassemble(worn, {"facility_level": 0, "worker": false})["reason"]
				== &"no_facility", "no workshop"):
		return false
	_stock({})
	var magic := _engraved(&"hammer", Enums.Rarity.EPIC, [&"essence_stone_mid", &"essence_water_low"])
	var p := Armory.preview_disassemble(magic, WS)
	if not _expect(p["ok"] and p["essences"] == [&"essence_stone_mid", &"essence_water_low"]
			and is_equal_approx(p["return_chance"], 0.5), "disassemble preview %s" % p):
		return false
	rng.seed = 7
	var result := Armory.disassemble(magic, WS, rng)
	var total := 0
	for id: StringName in [&"essence_stone_mid", &"essence_water_low"]:
		var n: int = result["returned"].get(id, 0) + result["lost"].get(id, 0)
		total += n
		if not _expect(n == 1 and Economy.get_amount(id) == result["returned"].get(id, 0), "disassemble %s %s" % [id, result]):
			return false
	return _expect(result["ok"] and total == 2 and not Armory.has_item(magic), "item destroyed")


## A-09: from +9 the family material follows the weapon's element once it has one.
func _check_family() -> bool:
	var rifle := _engraved(&"rifle", Enums.Rarity.RARE, [&"essence_light_low"])
	Armory.get_item(rifle).upgrade_level = 8
	var p := Armory.preview_upgrade(rifle, {"facility_level": 3, "dex": 5})
	var plain := _plain(&"rifle", Enums.Rarity.RARE)
	Armory.get_item(plain).upgrade_level = 8
	var q := Armory.preview_upgrade(plain, {"facility_level": 3, "dex": 5})
	return _expect(p["family_options"] == [&"neon_dust"] and p["cost"].get(&"neon_dust", 0) == 2, "family %s" % p["family_options"]) \
		and _expect(q["family_options"].size() == 4, "no element: any family")


func _check_save() -> bool:
	var epic := _engraved(&"sledgehammer", Enums.Rarity.EPIC, [&"essence_stone_low", &"essence_light_mid"])
	var common := _plain(&"club")
	Armory.get_item(common).opened_slot = true
	Armory.get_item(common).engravings = [{"slot_index": 0, "essence_def_id": &"essence_green_mid"}]
	var before := Armory.get_item_stats(epic)
	var data: Dictionary = JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(Armory.save_data()))))
	# Old saves / plain JSON: ints come back as floats, StringNames as Strings.
	var plain: Dictionary = JSON.parse_string(JSON.stringify(Armory.save_data()))
	Armory.load_data({})
	Armory.load_data(plain)
	var plain_ok := Armory.get_engravings(epic) == [&"essence_stone_low", &"essence_light_mid"] \
		and Armory.get_engravings(common) == [&"essence_green_mid"]
	Armory.load_data({})
	Armory.load_data(data)
	var after := Armory.get_item_stats(epic)
	return _expect(plain_ok, "plain JSON engravings") \
		and _expect(Armory.get_engravings(epic) == [&"essence_stone_low", &"essence_light_mid"], "epic engravings saved") \
		and _expect(Armory.get_item(common).opened_slot and Armory.get_engravings(common) == [&"essence_green_mid"],
			"opened slot saved") \
		and _expect(after["element"] == before["element"] and after["combo"]["id"] == &"shard_burst"
			and after["essence_effects"] == before["essence_effects"], "stats after load")


func _check_debug() -> bool:
	if not OS.is_debug_build():
		return true
	var club := _plain(&"club")
	Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, club)
	var line := DebugConsole.execute("engrave essence_water_low")
	var stats := Armory.get_item_stats(club)
	Armory.unequip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN)
	return _expect(stats["element"] == W and stats["opened_slot"], "debug engrave: %s" % line)
