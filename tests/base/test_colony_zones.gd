extends Node
## C-10: zones and clearing (yield, start cost, unlock tier, 묻힌 상자), base tiers, facility levels.
## Called by tests/run_tests.gd. Restores Colony, Economy and GameState.


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	var ok := true
	ok = _test_defs() and ok
	ok = _test_clearing() and ok
	ok = _test_start_cost_and_unlock() and ok
	ok = _test_buried_box() and ok
	ok = _test_tier() and ok
	ok = _test_upgrade() and ok
	ok = _test_save() and ok
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _fresh(resources: Dictionary = {}) -> void:
	GameState.load_data({"day": 2})
	Economy.load_data({})
	if not resources.is_empty():
		Economy.apply(resources)
	Colony.load_data({})
	Colony._rng.seed = 11


func _person(str_value: int = 5) -> StringName:
	return Colony.add_resident({"stats": {&"str": str_value}, "traits": [], "former_job": &"laborer"})


func _build(def_id: StringName) -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, &"", false)
	Colony.complete_building(uid)
	return uid


func _test_defs() -> bool:
	var ok := _check(BaseDB.zones().size() == 5, "구역 5곳 (09 구역과 개간)")
	ok = _check(Colony.is_zone_cleared(&"main_hall") and Colony.is_zone_cleared(&"front_yard") and not Colony.is_zone_cleared(&"park_a"), "방송실·공터만 처음부터 쓸 수 있음") and ok
	var west := BaseDB.get_zone(&"park_a")
	ok = _check(west.clear_work == 40 and west.clear_yield == {&"wood": 60}, "서쪽 숲: 진행도 40, 나무 60") and ok
	ok = _check(BaseDB.get_zone(&"gate_market").unlock_tier == Enums.BaseTier.FORTRESS, "동쪽 연못가는 요새") and ok
	return ok


func _test_clearing() -> bool:
	_fresh({&"food": 50})
	var a := _person()
	var b := _person()
	var ok := _check(Colony.assign_job(a, &"construction", &"park_a") and Colony.assign_job(b, &"construction", &"park_a"), "서쪽 숲동장 개간 배정")
	var report := Colony.settle_day()
	ok = _check(Colony.clear_progress_of(&"park_a") == 30 and not Colony.is_zone_cleared(&"park_a"), "하루 15 + 15 = 30/40") and ok
	report = Colony.settle_day()
	ok = _check(Colony.is_zone_cleared(&"park_a"), "이틀째 개간 완료") and ok
	ok = _check(report["produced"].get(&"wood", 0) >= 60, "개간하면 나무 60: %s" % report["produced"]) and ok
	ok = _check(report["events"].any(func(e): return e["type"] == &"zone_cleared"), "zone_cleared 이벤트") and ok
	ok = _check(Colony.job_of(a) == &"" and Colony.job_of(b) == &"", "끝나면 배정 해제") and ok
	ok = _check(Colony.job_block_reason(a, &"construction", &"park_a") == "이미 개간됨", "개간된 구역은 다시 배정 불가") and ok
	return ok


func _test_start_cost_and_unlock() -> bool:
	_fresh()
	var a := _person()
	var reason := Colony.job_block_reason(a, &"construction", &"park_b")
	var ok := _check(reason.begins_with("기지 단계 SETTLEMENT"), "북쪽 숲은 정착지부터 (%s)" % reason)
	Colony.tier = Enums.BaseTier.SETTLEMENT
	reason = Colony.job_block_reason(a, &"construction", &"park_b")
	ok = _check(reason.begins_with("시작 비용 부족"), "북쪽 숲: 비탈 계단 목재판 10 필요 (%s)" % reason) and ok
	Economy.apply({&"plank": 15})
	ok = _check(Colony.assign_job(a, &"construction", &"park_b") and Economy.get_amount(&"plank") == 5, "배정할 때 목재판 10 지불") and ok
	var b := _person()
	ok = _check(Colony.assign_job(b, &"construction", &"park_b") and Economy.get_amount(&"plank") == 5, "두 번째 사람은 다시 안 냄") and ok
	return ok


func _test_buried_box() -> bool:
	_fresh()
	var ok := true
	var parts := 0
	var flags := 0
	for i in 60:
		var box := Colony._buried_box()
		if box["blueprint"] != &"":
			flags += 1
			ok = _check(box["blueprint"] in TierRules.BURIED_BOX_BLUEPRINTS, "설계도는 목록 중 하나") and ok
		else:
			var n: int = box["resources"][&"parts"]
			ok = _check(n >= 2 and n <= 4, "부품 2~4") and ok
			parts += 1
	ok = _check(parts > 0 and flags > 0, "묻힌 상자: 부품과 설계도가 모두 나옴 (%d/%d)" % [parts, flags]) and ok
	return ok


func _test_tier() -> bool:
	_fresh({&"food": 100})
	for i in 5:
		_person()
	var s := Colony.next_tier_status()
	var ok := _check(s["tier"] == Enums.BaseTier.SETTLEMENT and not s["ok"] and s["missing"].size() == 3, "정착지까지 남은 것: 목공소·경사로·서쪽 숲 (%s)" % [s["missing"]])
	_build(&"carpentry_shop")
	_build(&"ramp")
	Colony.clear_zone(&"park_a")
	ok = _check(Colony.next_tier_status()["ok"], "조건 충족") and ok
	var report := Colony.settle_day()
	ok = _check(Colony.tier == Enums.BaseTier.SETTLEMENT and report["events"].any(func(e): return e["type"] == &"tier_up"), "저녁 정산 때 정착지로 성장") and ok
	ok = _check(Colony.facility_level_cap() == 2, "정착지 → 시설 Lv2까지") and ok
	s = Colony.next_tier_status()
	ok = _check(s["tier"] == Enums.BaseTier.FORTRESS and "발전기 가동" in s["missing"], "요새 조건에 발전기 가동") and ok
	return ok


func _test_upgrade() -> bool:
	_fresh({&"plank": 40, &"scrap": 80, &"parts": 20})
	var shop := _build(&"workshop")
	var check := Colony.can_upgrade(shop)
	var ok := _check(not check["ok"] and check["reasons"][0].begins_with("기지 단계"), "캐프에서는 Lv2 불가")
	Colony.tier = Enums.BaseTier.SETTLEMENT
	check = Colony.can_upgrade(shop)
	ok = _check(check["ok"] and check["cost"] == {&"plank": 20, &"scrap": 60, &"parts": 15}, "Lv2 비용 = ×2 + 부품 5") and ok
	ok = _check(Colony.upgrade_building(shop) and Colony.get_building(shop)["level"] == 2, "레벨업") and ok
	ok = _check(Economy.get_amount(&"plank") == 20 and Colony.building_capacity(shop) == 3, "비용 지불, 정원 +1") and ok
	ok = _check(not Colony.can_upgrade(shop)["ok"], "정착지에서 Lv3 불가") and ok
	ok = _check(BaseDB.get_building(&"radio_room").cost_for_level(2) == {&"scrap": 30, &"radio_parts": 5}, "방송실 Lv2: 고철 30 + 무전 부품 5") and ok
	return ok


func _test_save() -> bool:
	_fresh({&"plank": 10})
	Colony.tier = Enums.BaseTier.SETTLEMENT
	var a := _person()
	Colony.assign_job(a, &"construction", &"park_b")
	Colony.settle_day()
	var before := JSON.stringify(Colony.save_data(), "", true)
	Colony.load_data(JSON.parse_string(before))
	var ok := _check(JSON.stringify(Colony.save_data(), "", true) == before, "개간 진행도·시작 여부 저장 왕복")
	ok = _check(Colony.clear_progress_of(&"park_b") == 15 and Colony.clear_started.has(&"park_b"), "북쪽 숲 15/60, 시작 비용 냄") and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_zones] 실패: " + what)
	return cond
