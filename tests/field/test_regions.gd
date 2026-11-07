extends RefCounted
## B-24: the five regions in data/regions load with the design 02 values, point at existing data
## (resources, loot tables, extract points and hidden routes in the map), and the unlock checks
## follow design 02 / 12. Progression reads danger through the same file.

## id -> [danger, name] (02 "지역").
const REGIONS := {
	&"city_park": [1, "숲이 된 도심 공원"],
	&"flooded_mall": [2, "침수 상가"],
	&"hospital": [3, "병원"],
	&"office_district": [4, "고층 업무지구"],
	&"harbor": [5, "항구"],
}
const RESOURCE_FMT := "res://data/resources/%s.tres"

var _ok := true


func run() -> bool:
	var all := RegionDef.all()
	var ids: Array[StringName] = []
	for def in all:
		ids.append(def.id)
	_expect(ids == [&"city_park", &"flooded_mall", &"hospital", &"office_district", &"harbor"],
		"all() in danger order %s" % [ids])
	for id: StringName in REGIONS:
		var def := RegionDef.load_def(id)
		_expect(def != null, "data/regions/%s.tres loads" % id)
		if def != null:
			_check_def(def, REGIONS[id][0], REGIONS[id][1])
	_check_maps()
	_check_unlocks()
	_expect(Progression.region_danger(&"harbor") == 5, "Progression reads danger from RegionDef")
	return _ok


func _check_def(def: RegionDef, danger: int, name: String) -> void:
	var id := def.id
	_expect(def.danger == danger and def.name == name, "%s danger %d name %s" % [id, def.danger, def.name])
	_expect(def.map_scene == SceneRouter.REGION_SCENE_FMT % [id, id], "%s map_scene follows the router" % id)
	_expect(not def.monster_families.is_empty() and def.monster_families.size() == def.family_shares.size(),
		"%s families and shares" % id)
	var sum := 0.0
	for share in def.family_shares:
		sum += share
	_expect(is_equal_approx(sum, 1.0), "%s family shares sum to 1 (%.2f)" % [id, sum])
	_expect(not def.resources.is_empty() and def.resources.all(func(r: StringName) -> bool:
		return ResourceLoader.exists(RESOURCE_FMT % r)), "%s resources exist %s" % [id, def.resources])
	_expect(def.boss_id != &"" and def.loot_table_id == id and def.unlock_text != "", "%s boss, loot, unlock text" % id)


## Regions with a map: the def lists exactly the map's extract points and hidden routes, and
## every container kind has a region loot table.
func _check_maps() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for def in RegionDef.all():
		if not def.has_map():
			continue
		var layout := (load("res://levels/field/%s/layout.tscn" % def.id) as PackedScene).instantiate() as Node3D
		tree.root.add_child(layout)
		var extracts: Array[StringName] = []
		var normal := 0
		for node in layout.find_children("*", "ExtractPoint", true, false):
			extracts.append(node.id)
			# 02 "헬기 탈출": helicopter points come on top of the 3 candidates.
			if (node as ExtractPoint).type != ExtractPoint.Type.HELICOPTER:
				normal += 1
		_expect(normal == 3, "%s has 3 extract candidates besides helicopters (02), got %d" % [def.id, normal])
		var routes: Array[StringName] = []
		for node in layout.find_children("*", "HiddenRoute", true, false):
			routes.append(node.id)
		extracts.sort()
		routes.sort()
		var want_extracts := def.extract_candidates.duplicate()
		want_extracts.sort()
		var want_routes := def.hidden_routes.duplicate()
		want_routes.sort()
		_expect(extracts == want_extracts, "%s extract candidates %s match the map %s" % [def.id, want_extracts, extracts])
		_expect(routes == want_routes, "%s hidden routes %s match the map %s" % [def.id, want_routes, routes])
		layout.free()
		for type: int in LootSpot.ContainerType.values():
			_expect(LootData.find_table(def.loot_table_id, type) != null,
				"%s has a %s loot table" % [def.id, LootSpot.ContainerType.keys()[type]])
	_expect(RegionDef.load_def(&"city_park").has_map() and RegionDef.load_def(&"flooded_mall").has_map(),
		"park and mall have maps")


## 02 / 12: park from the start, mall after one park extraction, hospital at settlement,
## business district at settlement + the elevator key quest, harbor with radio room Lv2.
func _check_unlocks() -> void:
	var start := {"flags": {}, "tier": Enums.BaseTier.CAMP, "facility_levels": {}, "completed_quests": []}
	var open := func(id: StringName, state: Dictionary) -> bool:
		return RegionDef.load_def(id).is_unlocked(state)
	_expect(open.call(&"city_park", start), "park is open from the start")
	for id: StringName in [&"flooded_mall", &"hospital", &"office_district", &"harbor"]:
		_expect(not open.call(id, start), "%s is closed at the start" % id)
	_expect(open.call(&"flooded_mall", _with(start, "flags", {&"extracted_city_park": true})), "mall after a park extraction")
	var settled := _with(start, "tier", Enums.BaseTier.SETTLEMENT)
	_expect(open.call(&"hospital", settled), "hospital at settlement")
	_expect(not open.call(&"office_district", settled), "business district needs the quest too")
	_expect(RegionDef.load_def(&"office_district").missing_unlocks(settled) == [&"quest"], "only the quest is missing")
	_expect(open.call(&"office_district", _with(settled, "completed_quests", [&"elevator_key"])),
		"business district at settlement + elevator key")
	_expect(not open.call(&"harbor", _with(start, "facility_levels", {&"radio_room": 1})), "harbor closed at radio room Lv1")
	_expect(open.call(&"harbor", _with(start, "facility_levels", {&"radio_room": 2})), "harbor at radio room Lv2")
	# Live state: the mall flag comes from GameState.
	var had := GameState.has_flag(&"extracted_city_park")
	GameState.set_flag(&"extracted_city_park", true)
	_expect(RegionDef.load_def(&"flooded_mall").missing_unlocks().is_empty(), "mall opens on the live GameState flag")
	if not had:
		GameState.flags.erase(&"extracted_city_park")


func _with(state: Dictionary, key: String, value: Variant) -> Dictionary:
	var out := state.duplicate(true)
	out[key] = value
	return out


func _expect(cond: bool, what: String) -> void:
	if not cond:
		push_error("test_regions: " + what)
		_ok = false
