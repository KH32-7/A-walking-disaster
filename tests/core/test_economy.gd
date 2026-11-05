extends RefCounted
## Economy (A-06): resource defs, storage cap, overflow discard, negative guard, rare goods uncapped.


func run() -> bool:
	var saved := Economy.save_data().duplicate(true)
	var ok := _check_defs() and _check_negative() and _check_cap() and _check_rare_uncapped() \
		and _check_spend_first() and _check_bonus()
	Economy.load_data(saved)
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _reset(amounts: Dictionary = {}) -> void:
	Economy.load_data({"amounts": amounts, "cap_bonus": 0})


func _check_defs() -> bool:
	var ok := _expect(Economy.defs.size() >= 26, "only %d resource defs" % Economy.defs.size())
	for id in [&"wood", &"stone", &"scrap", &"food", &"plank", &"meal", &"debris"]:
		ok = _expect(Economy.uses_cap(id), "%s should use the storage cap" % id) and ok
	for id in [&"parts", &"rare_parts", &"medicine", &"fuel", &"vine_fiber", &"key"]:
		ok = _expect(Economy.get_def(id) != null and not Economy.uses_cap(id),
			"%s should be defined and uncapped" % id) and ok
	return ok and _expect(Economy.get_def(&"wood").category == Enums.ResourceCategory.BASIC, "wood category")


func _check_negative() -> bool:
	_reset({&"wood": 5, &"scrap": 3})
	var ok := Economy.apply({&"wood": -2, &"scrap": -4})
	return _expect(not ok, "spending more than owned succeeded") \
		and _expect(Economy.get_amount(&"wood") == 5 and Economy.get_amount(&"scrap") == 3,
			"failed apply changed amounts") \
		and _expect(not Economy.can_afford({&"scrap": 4}) and Economy.can_afford({&"scrap": 3}), "can_afford")


func _check_cap() -> bool:
	_reset({&"wood": 150})
	var result := Economy.apply_detailed({&"stone": 30, &"food": 40})
	return _expect(result["ok"], "capped gain failed") \
		and _expect(Economy.get_amount(&"stone") == 30, "stone %d" % Economy.get_amount(&"stone")) \
		and _expect(Economy.get_amount(&"food") == 20, "food %d (cap 200)" % Economy.get_amount(&"food")) \
		and _expect(result["discarded"] == {&"food": 20}, "discarded %s" % result["discarded"]) \
		and _expect(Economy.capped_total() == Economy.BASE_STORAGE_CAP, "total %d" % Economy.capped_total()) \
		and _expect(Economy.free_space() == 0, "free space")


func _check_rare_uncapped() -> bool:
	_reset({&"wood": 200})
	var result := Economy.apply_detailed({&"parts": 500, &"essence_green_low": 7, &"wood": 1})
	return _expect(Economy.get_amount(&"parts") == 500, "parts capped") \
		and _expect(Economy.get_amount(&"essence_green_low") == 7, "undefined id capped") \
		and _expect(result["discarded"] == {&"wood": 1}, "discarded %s" % result["discarded"])


func _check_spend_first() -> bool:
	_reset({&"wood": 200})
	var result := Economy.apply_detailed({&"plank": 10, &"wood": -20})
	return _expect(Economy.get_amount(&"plank") == 10 and Economy.get_amount(&"wood") == 180,
		"spend-first ordering: plank %d wood %d" % [Economy.get_amount(&"plank"), Economy.get_amount(&"wood")]) \
		and _expect(result["discarded"].is_empty(), "nothing should be discarded")


func _check_bonus() -> bool:
	_reset({&"wood": 200})
	Economy.set_cap_bonus(300)
	Economy.apply({&"stone": 350})
	var ok := _expect(Economy.storage_cap() == 500, "cap with bonus") \
		and _expect(Economy.get_amount(&"stone") == 300, "stone %d (cap 500)" % Economy.get_amount(&"stone"))
	Economy.set_cap_bonus(-5)
	return ok and _expect(Economy.cap_bonus == 0, "negative bonus not clamped")
