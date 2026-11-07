extends RefCounted
## Garage: vehicle defs, add and durability clamp, workshop repair cost and payment, save round trip.


func run() -> bool:
	var saved_garage := Garage.save_data().duplicate(true)
	var saved_economy := Economy.save_data().duplicate(true)
	var ok := _check_defs() and _check_add() and _check_repair() and _check_save() and _check_craft() \
		and _check_sortie() and _check_sortie_screen()
	Garage.load_data(saved_garage)
	Economy.load_data(saved_economy)
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _check_defs() -> bool:
	var ok := true
	for id in [&"bicycle", &"motorbike", &"car", &"rowboat", &"motorboat"]:
		ok = _expect(Garage.is_vehicle(id), "missing vehicle def %s" % id) and ok
	ok = _expect(Garage.get_def(&"car").seats == 4 and Garage.get_def(&"car").ram, "car def") and ok
	ok = _expect(Garage.get_def(&"rowboat").surface == VehicleDef.Surface.WATER, "rowboat surface") and ok
	return _expect(Economy.get_def(&"steel_plate") != null, "steel_plate resource missing") and ok


func _check_add() -> bool:
	Garage.load_data({})
	var uid := Garage.add(&"car")
	var ok := _expect(uid != &"" and Garage.list() == [uid], "add car")
	ok = _expect(is_equal_approx(Garage.durability(uid), 120.0), "new car not full") and ok
	Garage.set_durability(uid, 500.0)
	ok = _expect(is_equal_approx(Garage.durability(uid), 120.0), "durability above max") and ok
	Garage.set_durability(uid, -3.0)
	ok = _expect(Garage.is_broken(uid), "durability 0 should be broken") and ok
	ok = _expect(Garage.add(&"no_such_vehicle") == &"", "unknown vehicle added") and ok
	return _expect(Garage.remove(uid) and Garage.list().is_empty(), "remove") and ok


func _check_repair() -> bool:
	Garage.load_data({})
	Economy.load_data({"amounts": {&"scrap": 10}, "cap_bonus": 0})
	var uid := Garage.add(&"car", 85.0)
	var ok := _expect(Garage.repair_cost(uid) == {&"scrap": 4}, "repair cost %s" % Garage.repair_cost(uid))
	ok = _expect(Garage.repair(uid), "repair failed") and ok
	ok = _expect(Economy.get_amount(&"scrap") == 6, "scrap not spent") and ok
	ok = _expect(Garage.repair_cost(uid).is_empty() and not Garage.repair(uid), "full car repaired again") and ok
	Economy.load_data({"amounts": {&"scrap": 1}, "cap_bonus": 0})
	Garage.set_durability(uid, 0.0)
	return _expect(not Garage.repair(uid) and Garage.is_broken(uid), "repaired without scrap") and ok


func _check_craft() -> bool:
	Garage.load_data({})
	Economy.load_data({"amounts": {&"scrap": 50, &"parts": 10, &"motor": 3}, "cap_bonus": 0})
	var ctx := {"facility_level": 1, "dex": 3}
	var ok := _expect(Armory.list_recipes(&"workshop", 0).has(&"vehicle_car"), "car recipe at the workshop")
	ok = _expect(Armory.list_recipes(&"carpentry_shop", 0).has(&"vehicle_rowboat"), "rowboat at the carpentry shop") and ok
	ok = _expect(Armory.preview_craft(&"vehicle_car", ctx).get("vehicle", false), "preview says vehicle") and ok
	var out := Armory.craft(&"vehicle_car", ctx)
	ok = _expect(out.ok and Garage.list() == [StringName(out.get("vehicle_uid", &""))], "car crafted into the garage") and ok
	ok = _expect(Economy.get_amount(&"scrap") == 10 and Economy.get_amount(&"motor") == 1, "car cost paid") and ok
	return _expect(not Armory.craft(&"vehicle_car", ctx).ok and Garage.list().size() == 1, "no second car without scrap") and ok


## 02 "탈것": ridden out = kept (field-found ones are added), left behind = one more sortie there.
func _check_sortie() -> bool:
	Garage.load_data({})
	var car := Garage.add(&"car")
	Garage.apply_sortie_result({"region_id": &"flooded_mall",
		"vehicle": {"garage_uid": "", "def_id": "motorbike", "durability": 20.0},
		"vehicles_left": [{"garage_uid": String(car), "durability": 70.0, "position": [1.0, 0.0, 2.0], "yaw": 0.5}]})
	var ok := _expect(Garage.list().size() == 2, "field motorbike ridden out is kept")
	ok = _expect(Garage.is_away(car) and is_equal_approx(Garage.durability(car), 70.0), "car left in the field") and ok
	ok = _expect(not Garage.ready_list().has(car), "a car in the field cannot go out") and ok
	ok = _expect(Garage.lost_transform(car).origin.is_equal_approx(Vector3(1, 0, 2)), "left where it stood") and ok
	EventBus.sortie_started.emit({"region_id": &"flooded_mall"})
	ok = _expect(Garage.lost_in_region(&"flooded_mall") == [car], "waits in the same region") and ok
	Garage.apply_sortie_result({"region_id": &"flooded_mall", "vehicle": {"garage_uid": String(car), "def_id": "car",
		"durability": 60.0}, "vehicles_left": []})
	ok = _expect(not Garage.is_away(car) and is_equal_approx(Garage.durability(car), 60.0), "recovered by riding out") and ok

	Garage.apply_sortie_result({"region_id": &"flooded_mall", "vehicle": {},
		"vehicles_left": [{"garage_uid": String(car), "durability": 60.0, "position": [0.0, 0.0, 0.0], "yaw": 0.0}]})
	EventBus.sortie_started.emit({"region_id": &"city_park"})
	ok = _expect(not Garage.owned.has(car), "lost car gone after a sortie elsewhere") and ok

	var bike := Garage.add(&"bicycle")
	Garage.apply_sortie_result({"region_id": &"flooded_mall", "vehicle": {},
		"vehicles_left": [{"garage_uid": String(bike), "durability": 40.0, "position": [0.0, 0.0, 0.0], "yaw": 0.0}]})
	EventBus.sortie_started.emit({"region_id": &"flooded_mall"})
	Garage.apply_sortie_result({"region_id": &"flooded_mall", "vehicle": {},
		"vehicles_left": [{"garage_uid": String(bike), "durability": 40.0, "position": [0.0, 0.0, 0.0], "yaw": 0.0}]})
	return _expect(not Garage.owned.has(bike), "not recovered in its one sortie: gone") and ok


func _check_sortie_screen() -> bool:
	Garage.load_data({})
	var boat := Garage.add(&"rowboat")
	var broken := Garage.add(&"car", 0.0)
	var screen := preload("res://ui/screens/sortie_prep_screen.gd")
	var ok := _expect(screen.vehicle_block(boat, &"flooded_mall") == "", "boat can go to the flooded mall (dock)")
	ok = _expect(screen.vehicle_block(boat, &"city_park") != "", "no boat in the park (no dock)") and ok
	ok = _expect(screen.vehicle_block(broken, &"flooded_mall") != "", "broken car cannot go") and ok
	return _expect(screen.vehicle_ok(&"", &"city_park"), "walking is always fine") and ok


func _check_save() -> bool:
	Garage.load_data({})
	var a := Garage.add(&"bicycle", 12.5)
	Garage.add(&"rowboat")
	var data := JSON.parse_string(JSON.stringify(Garage.save_data())) as Dictionary
	Garage.load_data({})
	Garage.load_data(data)
	var ok := _expect(Garage.list().size() == 2, "save lost vehicles")
	ok = _expect(is_equal_approx(Garage.durability(a), 12.5), "save lost durability") and ok
	ok = _expect(Garage.def_of(a).id == &"bicycle", "save lost def") and ok
	return _expect(Garage.add(&"car") == &"veh_3", "uid counter not saved") and ok
