extends Node
## C-11: 참여 조건 (이동·언어·청각·돌봄), zone access, assignment blocking, F_access, care slots,
## hearing alarm in raids, access_map(). Called by tests/run_tests.gd. Restores Colony and Economy.


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	var ok := true
	ok = _test_mobility() and ok
	ok = _test_language() and ok
	ok = _test_care() and ok
	ok = _test_hearing_raid() and ok
	ok = _test_access_map() and ok
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
	Colony._rng.seed = 5


func _person(needs: Array = [], stats: Dictionary = {&"str": 5, &"dex": 5, &"heart": 5}) -> StringName:
	return Colony.add_resident({"stats": stats, "traits": [], "former_job": &"laborer", "access_needs": needs})


func _build(def_id: StringName, zone: StringName = &"front_yard") -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, zone, false)
	Colony.complete_building(uid)
	return uid


func _test_mobility() -> bool:
	_fresh({&"food": 50})
	var wheel := _person([Enums.AccessNeed.MOBILITY])
	var walker := _person()
	var ok := _check(not Colony.zone_access(&"main_hall")["mobility"] and Colony.zone_access(&"front_yard")["mobility"], "방송실(데크 위)은 경사로가 필요, 공터는 평지")
	var reason := Colony.job_block_reason(wheel, &"radio")
	ok = _check(reason.begins_with("갈 수 있는 방송실 자리가 없음") or reason.contains("경사로"), "휠체어 사용자: 경사로 없으면 방송실 배정 불가 (%s)" % reason) and ok
	ok = _check(Colony.assign_job(walker, &"radio"), "걷는 사람은 방송실 가능") and ok
	Colony.unassign_job(walker)
	var shop := _build(&"workshop")
	ok = _check(Colony.assign_job(wheel, &"maintenance", shop), "공터(평지) 정비소는 처음부터 가능") and ok
	_build(&"ramp")
	ok = _check(Colony.zone_access(&"main_hall")["mobility"] and Colony.assign_job(wheel, &"radio"), "공터에 경사로 → 방송실 가능") and ok
	var slope_shop := _build(&"workshop", &"park_b")
	ok = _check(Colony.access_block_reason(wheel, &"park_b") != "", "북쪽 숲(비탈)은 그 안에 경사로가 필요") and ok
	ok = _check(not Colony.assign_job(wheel, &"maintenance", slope_shop), "북쪽 숲 정비소 배정 불가") and ok
	_build(&"ramp", &"park_b")
	ok = _check(Colony.zone_access(&"park_b")["mobility"], "북쪽 숲에 경사로 → 오를 수 있음") and ok
	# Ramp removed later: the resident can no longer reach work and produces nothing that day.
	Colony.assign_job(wheel, &"radio")
	for uid in Colony.building_ids(&"ramp"):
		Colony.demolish_building(uid)
	var report := Colony.settle_day()
	ok = _check(not report["work"].has(wheel), "경사로가 없어지면 방송실에 못 가서 일 못 함") and ok
	return ok


func _test_language() -> bool:
	_fresh({&"food": 50})
	_build(&"lumber_yard")
	var migrant := _person([Enums.AccessNeed.LANGUAGE])
	Colony.assign_job(migrant, &"woodcutting")
	var ok := _check(is_equal_approx(Colony.access_multiplier(migrant), 0.7), "그림 표지판 없으면 효율 ×0.7")
	var before: float = Colony.preview_output(migrant).get(&"wood", 0.0)
	_build(&"picture_sign")
	ok = _check(is_equal_approx(Colony.access_multiplier(migrant), 1.0) and Colony.preview_output(migrant)[&"wood"] > before, "같은 구역에 표지판 → 효율 회복") and ok
	var reason := Colony.job_block_reason(migrant, &"radio")
	ok = _check(reason.begins_with("통역 무전기"), "무전은 통역 무전기가 있어야 (%s)" % reason) and ok
	var radio_add := Colony.place_building(&"interpreter_radio", Vector2i.ZERO, 0, &"", false)
	Colony.complete_building(radio_add)
	ok = _check(Colony.job_block_reason(migrant, &"radio") == "", "통역 무전기 → 무전 가능") and ok
	return ok


func _test_care() -> bool:
	_fresh({&"food": 50})
	_build(&"lumber_yard")
	var parent := _person([Enums.AccessNeed.CARE])
	Colony.assign_job(parent, &"woodcutting")
	var ok := _check(is_equal_approx(Colony.access_multiplier(parent), 0.5), "돌봄방이 없으면 효율 ×0.5")
	var daycare := _build(&"daycare")
	ok = _check(Colony.care_slots() == 0, "돌봄 담당이 없는 돌봄방은 0자리") and ok
	var carer := _person()
	Colony.assign_job(carer, &"care", daycare)
	ok = _check(Colony.care_slots() == 4 and is_equal_approx(Colony.access_multiplier(parent), 1.0), "돌봄 담당 → 4자리, 보호자 효율 회복") and ok
	var others: Array[StringName] = []
	for i in 4:
		others.append(_person([Enums.AccessNeed.CARE]))
	ok = _check(Colony.care_covered().size() == 4, "보호자 5명 중 4명만 돌봄") and ok
	return ok


func _test_hearing_raid() -> bool:
	_fresh()
	var deaf := _person([Enums.AccessNeed.HEARING])
	Colony.residents[deaf]["health"] = Enums.HealthState.OK
	# Shelter + alarm normally keep civilians safe; without a 경광등 the deaf resident is not counted.
	var ok := _check(not Colony.hearing_alarm(), "경광등 없음")
	_build(&"warning_light")
	ok = _check(not Colony.hearing_alarm(), "전력 없는 경광등은 안 됨") and ok
	_build(&"solar_panel")
	ok = _check(Colony.hearing_alarm(), "전력 들어온 경광등 → 시각 경보") and ok
	return ok


func _test_access_map() -> bool:
	_fresh()
	_build(&"ramp")
	var m := Colony.access_map()
	var ok := _check(m["zones"].size() == BaseDB.zones().size(), "구역마다 항목")
	ok = _check(m["zones"][&"main_hall"]["mobility"] and not m["zones"][&"park_b"]["mobility"], "방송실 가능, 북쪽 숲 불가") and ok
	ok = _check("경사로 (북쪽 숲)" in m["zones"][&"park_b"]["missing"], "북쪽 숲에 무엇이 필요한지 글로: %s" % [m["zones"][&"park_b"]["missing"]]) and ok
	ok = _check(m.has("hearing_alarm") and m["care"].has("slots") and m.has("interpreter_radio"), "기지 전체 항목") and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_access] 실패: " + what)
	return cond
