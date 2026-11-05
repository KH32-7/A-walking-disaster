extends Node
## C-18: defense facilities (10 탭 표), their effect on the automatic judgment, consumables,
## repair and wall upkeep. Called by tests/run_tests.gd. Restores Colony, Economy and GameState.


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	var ok := true
	ok = _test_defs() and ok
	ok = _test_defense_values() and ok
	ok = _test_consumables() and ok
	ok = _test_shelter() and ok
	ok = _test_repair() and ok
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _fresh(resources: Dictionary = {}) -> void:
	GameState.load_data({"day": 10})
	Economy.load_data({})
	if not resources.is_empty():
		Economy.apply(resources)
	Colony.load_data({})
	Colony._rng.seed = 21


func _build(def_id: StringName, zone: StringName = &"front_yard") -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, zone, false)
	Colony.complete_building(uid)
	return uid


func _test_defs() -> bool:
	var ok := true
	var expect := {&"palisade": [100, 0.5], &"stone_wall": [300, 1.0], &"iron_wall": [600, 2.0], &"wooden_gate": [150, 1.0],
		&"iron_gate": [500, 3.0], &"guard_post": [200, 5.0], &"spike_trap": [3, 2.0], &"essence_lamp": [150, 6.0],
		&"light_tower": [150, 1.0], &"shelter": [800, 0.0]}
	for id: StringName in expect:
		var def := BaseDB.get_building(id)
		ok = _check(def != null and def.durability == expect[id][0] and is_equal_approx(def.defense_value, expect[id][1]), "%s 내구도·방어 기여 (10 탭 표)" % id) and ok
	ok = _check(BaseDB.get_building(&"noise_decoy") != null and BaseDB.get_building(&"warning_bell") != null, "소음 미끼·경보 종") and ok
	return ok


func _test_defense_values() -> bool:
	_fresh()
	for i in 4:
		_build(&"stone_wall")
	var lamp := _build(&"essence_lamp")
	var tower := _build(&"light_tower")
	var d := Colony.defense_breakdown()
	var ok := _check(is_equal_approx(d["total"], 4.0), "석벽 4 = 4. 정수가 없는 등불·전력 없는 조명탑은 0 (%.1f)" % d["total"])
	Economy.apply({&"essence_green_low": 2})
	_build(&"solar_panel")
	d = Colony.defense_breakdown()
	ok = _check(d["facilities"].has(lamp) and d["facilities"].has(tower) and is_equal_approx(d["total"], 4.0 + 6.0 + 1.0), "정수 2 → 등불 6, 전력 → 조명탑 1") and ok
	var wall: StringName = Colony.building_ids(&"stone_wall")[0]
	Colony.buildings[wall]["durability"] = 150
	ok = _check(is_equal_approx(Colony.defense_breakdown()["total"], 3.5 + 6.0 + 1.0), "내구도 절반인 벽은 기여 절반") and ok
	return ok


func _test_consumables() -> bool:
	_fresh({&"essence_green_low": 1, &"essence_water_low": 3})
	_build(&"noise_decoy")
	_build(&"noise_decoy")
	var trap := _build(&"spike_trap")
	_build(&"essence_lamp")
	var ok := _check(is_equal_approx(Colony.raid_strength_mult({"type": &"swarm"}), 0.8), "소음 미끼 2개 → 강도 −20%")
	ok = _check(is_equal_approx(Colony.raid_strength_mult({"type": &"fog"}), 0.8 * 1.2), "조명탑 없는 안개 습격 +20%") and ok
	var result := Colony.resolve_raid({"raid_id": &"d1", "strength": 10.0, "type": &"swarm", "directions": [&"north"]}, Enums.RaidMode.AUTO)
	ok = _check(result["used"]["decoys"] == 2 and Colony.building_ids(&"noise_decoy").is_empty(), "미끼는 한 번 쓰면 사라짐") and ok
	ok = _check(Colony.get_building(trap)["durability"] == 2, "함정 3회 → 2회 남음") and ok
	ok = _check(Economy.get_amount(&"essence_water_low") == 1 and Economy.get_amount(&"essence_green_low") == 1, "등불은 많은 정수부터 2개: %s" % result["used"]["essence"]) and ok
	Colony.buildings[trap]["durability"] = 1
	Colony.resolve_raid({"raid_id": &"d2", "strength": 10.0, "type": &"swarm"}, Enums.RaidMode.AUTO)
	ok = _check(Colony.get_building(trap)["damaged"], "다 쓴 함정은 파손(다시 설치 = 수리)") and ok
	return ok


func _test_shelter() -> bool:
	_fresh()
	var civilians: Array[StringName] = []
	for i in 6:
		civilians.append(Colony.add_resident({"traits": []}))
	_build(&"shelter")
	_build(&"warning_bell")
	var hurt := 0
	for i in 5:
		var result := Colony.resolve_raid({"raid_id": StringName("s%d" % i), "strength": 500.0, "type": &"swarm"}, Enums.RaidMode.AUTO)
		hurt += result["casualties"].size()
	return _check(hurt == 0, "대피소 + 경보 종 → 비전투 주민은 패배해도 다치지 않음")


func _test_repair() -> bool:
	# Food so the builder does not starve: hunger 0 → 5% sickness a day would make this depend on luck.
	_fresh({&"wood": 50, &"scrap": 50, &"parts": 10, &"plank": 20, &"food": 30})
	var shop := _build(&"workshop")
	Colony.buildings[shop]["damaged"] = true
	var builder := Colony.add_resident({"stats": {&"str": 5}, "traits": []})
	var ok := _check(Colony.job_block_reason(builder, &"construction", shop) != "", "수리를 시작하기 전에는 배정 불가")
	var check := Colony.can_repair(shop)
	ok = _check(check["ok"] and check["cost"] == {&"plank": 3, &"scrap": 9, &"parts": 2}, "수리 비용 = 건설 비용 30%% (올림): %s" % check["cost"]) and ok
	ok = _check(Colony.start_repair(shop) and Economy.get_amount(&"scrap") == 41, "수리 시작 + 비용 지불") and ok
	ok = _check(Colony.repair_work_needed(shop) == 15 and Colony.assign_job(builder, &"construction", shop), "수리 작업 = 진행도 30의 50%") and ok
	var report := Colony.settle_day()
	ok = _check(not Colony.get_building(shop)["damaged"] and report["events"].any(func(e): return e["type"] == &"repaired"), "하루 15 → 수리 완료") and ok

	var wall := _build(&"stone_wall")
	Colony.buildings[wall]["durability"] = 100
	ok = _check(Colony.assign_job(builder, &"construction", wall), "내구도가 준 벽은 보수 배정 가능") and ok
	Colony.settle_day()
	ok = _check(Colony.get_building(wall)["durability"] == 250, "벽 보수 하루 100 × 1.5 = 150") and ok
	Colony.settle_day()
	var b: Dictionary = Colony.get_resident(builder)
	ok = _check(Colony.get_building(wall)["durability"] == 300 and Colony.job_of(builder) == &"", "최대 내구도에서 멈추고 배정 해제 (내구도 %d, 작업 %s, 피로 %d, 배고픔 %d, 건강 %d, 사기 %d)" % [
		Colony.get_building(wall)["durability"], Colony.job_of(builder), b["fatigue"], b["hunger"], b["health"], b["morale"]]) and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_defense] 실패: " + what)
	return cond
