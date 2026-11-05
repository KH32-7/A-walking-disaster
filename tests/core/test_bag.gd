extends RefCounted
## Bag (A-08): placement, rotation, overlap refusal, stacking, safe pocket, bonus row,
## extraction into storage, losing contents on down, save round trip.

var _saved_bag: Dictionary
var _saved_armory: Dictionary
var _saved_economy: Dictionary


func run() -> bool:
	_saved_bag = Bag.save_data().duplicate(true)
	_saved_armory = Armory.save_data().duplicate(true)
	_saved_economy = Economy.save_data().duplicate(true)
	var ok := _check_place_and_rotate() and _check_stacking() and _check_items() \
		and _check_bonus_row() and _check_resize_refusal() and _check_unload() and _check_lose() \
		and _check_take_and_consume() and _check_defense_load() and _check_looting_api() and _check_save()
	Bag.load_data(_saved_bag)
	Armory.load_data(_saved_armory)
	Economy.load_data(_saved_economy)
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _reset(size := Vector2i(4, 5), bonus := 0) -> void:
	Bag.load_data({})
	Bag.resize(size, bonus)
	Armory.load_data({})
	Economy.load_data({})


func _check_place_and_rotate() -> bool:
	_reset()
	var size := Vector2i(1, 3)
	var ok := _expect(Bag.can_place(size, Vector2i(0, 2), false), "1x3 at (0,2) should fit in 4x5") \
		and _expect(not Bag.can_place(size, Vector2i(0, 3), false), "1x3 at (0,3) runs off the grid") \
		and _expect(Bag.can_place(size, Vector2i(1, 4), true), "rotated 3x1 at (1,4) should fit") \
		and _expect(not Bag.can_place(size, Vector2i(2, 4), true), "rotated 3x1 at (2,4) runs off") \
		and _expect(Bag.can_place(Vector2i(2, 1), Vector2i(0, 0), false, Bag.AREA_POCKET), "2x1 fits pocket") \
		and _expect(not Bag.can_place(Vector2i(1, 2), Vector2i(0, 0), false, Bag.AREA_POCKET), "1x2 in pocket")
	# Overlap refusal: wood is 1x2.
	Bag.add_resource(&"wood", 5)
	var wood: Dictionary = Bag.entries()[0]
	ok = _expect(wood["pos"] == Vector2i(0, 0) and wood["size"] == Vector2i(1, 2), "wood at %s" % wood) and ok
	ok = _expect(not Bag.can_place(Vector2i(1, 1), Vector2i(0, 1), false), "overlap allowed") and ok
	ok = _expect(Bag.move(wood["id"], Vector2i(3, 0), true) == false, "rotated 2x1 at x=3 runs off") and ok
	ok = _expect(Bag.move(wood["id"], Vector2i(2, 0), true), "move+rotate failed") and ok
	ok = _expect(Bag.get_entry(wood["id"])["size"] == Vector2i(2, 1), "rotation not applied") and ok
	return ok


func _check_stacking() -> bool:
	_reset()
	var left := Bag.add_resource(&"stone", 45)  # stack 20 -> 20, 20, 5
	var stacks := Bag.entries()
	var ok := _expect(left == 0 and stacks.size() == 3, "stone stacks %d left %d" % [stacks.size(), left]) \
		and _expect(Bag.count(&"stone") == 45, "count %d" % Bag.count(&"stone"))
	Bag.add_resource(&"stone", 10)  # tops up the 5 stack first
	ok = _expect(Bag.entries().size() == 3 and Bag.count(&"stone") == 55, "top-up made a new stack") and ok
	# Fill the rest: 20 cells, 3 used; motors are 2x2 stack 1.
	var motors_left := Bag.add_resource(&"motor", 10)
	ok = _expect(motors_left > 0, "bag never filled up") and ok
	ok = _expect(Bag.add_resource(&"motor", 1) == 1, "added to a full bag") and ok
	return ok


func _check_items() -> bool:
	_reset()
	var rifle := Armory.create_item(&"rifle")
	var entry := Bag.add_item(rifle)
	var ok := _expect(entry > 0, "rifle did not go in") \
		and _expect(Armory.get_item(rifle).owner == Armory.BAG_ID, "rifle owner %s" % Armory.get_item(rifle).owner) \
		and _expect(not rifle in Armory.list_storage(), "carried rifle still listed in storage") \
		and _expect(not Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, rifle), "equipped from bag") \
		and _expect(Bag.add_item(rifle) == -1, "same item added twice")
	Bag.remove(entry)
	return ok and _expect(Armory.get_item(rifle).owner == Armory.STORAGE_ID, "removed item not back in storage")


func _check_bonus_row() -> bool:
	_reset(Vector2i(4, 5), 2)
	return _expect(Bag.cell_count() == 22, "cells %d" % Bag.cell_count()) \
		and _expect(Bag.is_cell(Vector2i(1, 5)) and not Bag.is_cell(Vector2i(2, 5)), "bonus row shape") \
		and _expect(Bag.can_place(Vector2i(2, 1), Vector2i(0, 5), false), "2x1 in bonus row")


func _check_resize_refusal() -> bool:
	_reset(Vector2i(6, 8))
	var e := Bag.add_item(Armory.create_item(&"sledgehammer"))  # 2x3
	Bag.move(e, Vector2i(4, 5), false)
	return _expect(not Bag.resize(Vector2i(4, 5)), "shrank over an item") \
		and _expect(Bag.grid_size == Vector2i(6, 8), "failed resize changed the grid")


func _check_unload() -> bool:
	_reset()
	Economy.load_data({"amounts": {&"wood": 195}})
	Bag.add_resource(&"wood", 10)
	Bag.add_resource(&"parts", 3)
	var pistol := Armory.create_item(&"pistol")
	Bag.add_item(pistol)
	var result := Bag.unload_to_base()
	return _expect(Bag.is_empty(), "bag not empty after unload") \
		and _expect(Economy.get_amount(&"wood") == 200 and Economy.get_amount(&"parts") == 3, "economy after unload") \
		and _expect(result["discarded"] == {&"wood": 5}, "discarded %s" % result["discarded"]) \
		and _expect(result["items"] == [pistol] and pistol in Armory.list_storage(), "pistol not in storage")


func _check_lose() -> bool:
	_reset()
	var knife := Armory.create_item(&"dagger")
	var kept := Bag.add_item(knife)
	Bag.move(kept, Vector2i(0, 0), false, Bag.AREA_POCKET)
	var gun := Armory.create_item(&"pistol")
	Bag.add_item(gun)
	Bag.add_resource(&"medicine", 2)
	var lost := Bag.lose_contents()
	return _expect(Bag.entries().size() == 1 and Bag.entries()[0]["ref"] == knife, "pocket not kept") \
		and _expect(not Armory.has_item(gun) and Armory.has_item(knife), "lost gun still exists") \
		and _expect(lost["resources"] == {&"medicine": 2} and lost["items"] == [gun], "lost report %s" % lost)


func _check_take_and_consume() -> bool:
	_reset()
	Economy.load_data({"amounts": {&"food": 15}})
	var moved := Bag.take_from_storage(&"food", 30)
	var ok := _expect(moved == 15 and Economy.get_amount(&"food") == 0 and Bag.count(&"food") == 15,
		"take_from_storage moved %d" % moved)
	ok = _expect(not Bag.consume(&"food", 16) and Bag.count(&"food") == 15, "over-consume changed bag") and ok
	ok = _expect(Bag.consume(&"food", 12) and Bag.count(&"food") == 3, "consume") and ok
	return ok


## Base defense (issues #110 #121): equipped gun's ammo (capped) and consumables come from storage,
## unload_to_base puts back what was not used.
func _check_defense_load() -> bool:
	_reset()
	Economy.load_data({"amounts": {&"ammo_pistol": 200, &"ammo_rifle": 50, &"first_aid_kit": 1}})
	var pistol := Armory.create_item(&"pistol")
	var ok := _expect(Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, pistol), "equip pistol")
	var ammo := StringName(Armory.get_item_stats(pistol).get("ammo_id", &""))
	ok = _expect(ammo == &"ammo_pistol", "pistol ammo_id %s" % ammo) and ok
	var moved := Bag.load_for_defense()
	ok = _expect(moved == {&"ammo_pistol": Bag.DEFENSE_AMMO_MAX, &"first_aid_kit": 1}, "load_for_defense %s" % moved) and ok
	ok = _expect(Economy.get_amount(&"ammo_pistol") == 200 - Bag.DEFENSE_AMMO_MAX
		and Economy.get_amount(&"ammo_rifle") == 50, "storage after defense load") and ok
	ok = _expect(Bag.consume(&"ammo_pistol", 30), "fire 30") and ok
	Bag.unload_to_base()
	return _expect(Bag.is_empty() and Economy.get_amount(&"ammo_pistol") == 170
		and Economy.get_amount(&"first_aid_kit") == 1, "defense unload put back %d" % Economy.get_amount(&"ammo_pistol")) and ok


func _check_looting_api() -> bool:
	_reset(Vector2i(1, 1))  # one cell
	var added := Bag.try_add(&"ammo_pistol", 80)  # stack 60
	var none := Bag.try_add(&"key", 1)
	return _expect(added == 60 and none == 0, "try_add %d / %d" % [added, none]) \
		and _expect(Bag.count_of(&"ammo_pistol") == 60, "count_of") \
		and _expect(not Bag.remove_item(&"ammo_pistol", 61) and Bag.count_of(&"ammo_pistol") == 60, "over-remove") \
		and _expect(Bag.remove_item(&"ammo_pistol", 60) and Bag.is_empty(), "remove_item")


func _check_save() -> bool:
	_reset(Vector2i(5, 6), 2)
	Bag.add_resource(&"scrap", 25)
	Bag.add_item(Armory.create_item(&"machete"))
	var before := Bag.save_data().duplicate(true)
	var round_trip: Dictionary = JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(before))))
	Bag.load_data(round_trip)
	return _expect(var_to_str(Bag.save_data()) == var_to_str(before), "bag differs after save round trip")
