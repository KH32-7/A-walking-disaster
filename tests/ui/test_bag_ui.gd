extends Node
## D-08: item info, bag grid sizing, bag screen with a container, armory equip/unequip.

class FakeBox:
	extends Node
	signal opened(n: int)
	signal slot_revealed(i: int, id: StringName, n: int)
	signal reveal_finished()
	signal session_ended()
	signal slot_taken(i: int, id: StringName, n: int)
	var def = null
	var slots := [{"item_id": &"scrap", "count": 2, "identified": true}, {"item_id": &"", "count": 0, "identified": false}]

	func get_slots() -> Array:
		return slots.duplicate(true)

	func take(i: int) -> int:
		var n := Bag.try_add(slots[i].item_id, slots[i].count)
		slots[i].count -= n
		return n


func run() -> bool:
	var ok := true
	var saved_bag := Bag.save_data()
	var saved_arm := Armory.save_data()
	var info := ItemInfo.for_resource(&"scrap")
	ok = _expect(String(info.name) != "" and info.kind == &"resource", "resource info") and ok
	var uid := Armory.create_item(&"rifle", 2)
	var ii := ItemInfo.for_item(uid)
	ok = _expect(int(ii.rarity) == 2 and (ii.tooltip.stats as Array).size() >= 3, "item info has stats") and ok
	var g := BagGrid.new()
	add_child(g)
	ok = _expect(g.get_combined_minimum_size().x > 0.0, "bag grid sizes from Bag.grid_size") and ok
	g.queue_free()
	var box := FakeBox.new()
	add_child(box)
	UI.close_all()
	UI.open(&"bag", {"container": box})
	await get_tree().process_frame
	var scr = UI.get_screen(&"bag")
	ok = _expect(scr != null and scr.container == box, "bag screen bound to the container") and ok
	var before := Bag.count(&"scrap")
	scr.take_all()
	ok = _expect(Bag.count(&"scrap") == before + 2, "take all moves identified loot into the bag") and ok
	box.session_ended.emit()
	await get_tree().process_frame
	ok = _expect(not UI.is_open(&"bag"), "container session end closes the bag") and ok
	box.queue_free()
	UI.open(&"armory")
	await get_tree().process_frame
	ok = _expect(UI.top() == &"armory", "armory opens") and ok
	UI.close_all()
	Bag.load_data(saved_bag)
	Armory.load_data(saved_arm)
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
