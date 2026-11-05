extends Node
## C-06: morale factors, traits, 떠날 위기 + 붙잡기, health (injury, sickness, medicine), and a
## stranded resident coming home through rescue_completed. Called by tests/run_tests.gd.

var _left: Array[StringName] = []


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	EventBus.resident_left.connect(_on_left)
	var ok := true
	ok = _test_factors() and ok
	ok = _test_settle_morale() and ok
	ok = _test_crisis() and ok
	ok = _test_health() and ok
	ok = _test_rescue_return() and ok
	EventBus.resident_left.disconnect(_on_left)
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _on_left(id: StringName, _reason: StringName) -> void:
	_left.append(id)


func _fresh(resources: Dictionary = {}) -> void:
	GameState.load_data({"day": 2})
	Economy.load_data({})
	if not resources.is_empty():
		Economy.apply(resources)
	Colony.load_data({})
	Colony._rng.seed = 3
	_left.clear()


func _person(extra: Dictionary = {}) -> StringName:
	var p := {"stats": {&"str": 5, &"heart": 3}, "traits": [], "former_job": &"laborer"}
	p.merge(extra, true)
	return Colony.add_resident(p)


func _build(def_id: StringName) -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, &"", false)
	Colony.complete_building(uid)
	return uid


func _test_factors() -> bool:
	var base := {"id": &"a", "likes": [&"woodcutting"], "dislikes": [&"quarrying"], "hunger": 70, "morale": 50,
		"traits": [], "relations": {&"b": 50}, "stats": {&"heart": 3}}
	var ok := _check(NeedsRules.daily_morale(base, {"job_id": &"woodcutting"}) == 3, "좋아하는 일 +3")
	ok = _check(NeedsRules.daily_morale(base, {"job_id": &"quarrying"}) == -3, "싫어하는 일 −3") and ok
	ok = _check(NeedsRules.daily_morale(base, {"has_bed": false}) == -10, "침상 없음 −10") and ok
	ok = _check(NeedsRules.daily_morale(base, {"ate_cooked": true, "living_bonus": 3}) == 5, "요리 +2, 모닥불·식당 +3") and ok
	ok = _check(NeedsRules.daily_morale(base, {"stranded_count": 2}) == -10, "고립된 동료 2명 −10") and ok
	var friend := {"id": &"b", "stats": {&"heart": 8}}
	ok = _check(NeedsRules.daily_morale(base, {"coworkers": [friend]}) == 3, "친구와 같은 작업장 +2, 마음 8 동료 +1") and ok
	var hungry := base.duplicate(true)
	hungry["hunger"] = 10
	ok = _check(NeedsRules.daily_morale(hungry, {}) == -10, "배고픔 20 미만 −10") and ok
	var pess := base.duplicate(true)
	pess["traits"] = [&"pessimist"]
	ok = _check(NeedsRules.apply_morale(pess, 10) == 57, "비관적: 사기 상승 ×0.7") and ok
	var opt := base.duplicate(true)
	opt["traits"] = [&"optimist"]
	opt["morale"] = 32
	ok = _check(NeedsRules.apply_morale(opt, -10) == 30, "낙천적: 사기 하한 30") and ok
	return ok


func _test_settle_morale() -> bool:
	_fresh({&"food": 60})
	for i in 7:
		_person()
	var ids := Colony.active_resident_ids()
	var homeless := ids[6]
	var report := Colony.settle_day()
	var ok := _check(Colony.get_resident(homeless)["bed_id"] == &"" and report["morale"][homeless] == -10, "7번째(임시 거처) 사기 −10: %s" % [report["morale"]])
	ok = _check(report["morale"][ids[0]] == 0, "침상 있고 아무 일 없으면 0") and ok
	_build(&"bonfire")
	report = Colony.settle_day()
	ok = _check(report["morale"][ids[0]] == 1, "모닥불 +1 (전원)") and ok
	return ok


func _test_crisis() -> bool:
	_fresh({&"food": 100})
	for i in 6:
		_person()
	var low := _person({"morale": 15})      # 7th: no bed → keeps falling
	var trusted := _person({"morale": 15, "trust": 50})
	var crisis_seen := false
	for day in 3:
		for e in Colony.settle_day()["events"]:
			if e["type"] == &"leave_crisis":
				crisis_seen = true
	var ok := _check(crisis_seen and Colony.residents_in_crisis().has(low) and Colony.residents_in_crisis().has(trusted), "사기 20 미만 3일 → 떠나려 한다")
	var fail := Colony.persuade_to_stay(low)
	ok = _check(not fail["ok"] and fail["reason"].begins_with("신뢰도 40"), "신뢰 40 미만은 붙잡기 실패") and ok
	ok = _check(Colony.persuade_to_stay(trusted)["ok"] and Colony.get_resident(trusted)["morale"] >= 25, "신뢰 50 → 붙잡기 성공, 사기 25") and ok
	Colony.settle_day()
	ok = _check(_left == [low] and Colony.get_resident(low).is_empty(), "다음 저녁에 떠남 + resident_left") and ok
	ok = _check(not Colony.get_resident(trusted).is_empty() and not Colony.get_resident(trusted)["leave_crisis"], "붙잡은 사람은 남음") and ok
	return ok


func _test_health() -> bool:
	_fresh({&"food": 100, &"medicine": 2})
	var hurt := _person()
	Colony.residents[hurt]["health"] = Enums.HealthState.INJURED
	Colony.residents[hurt]["recover_days"] = 3
	Colony.settle_day()
	Colony.settle_day()
	var ok := _check(Colony.get_resident(hurt)["health"] == Enums.HealthState.INJURED, "부상 3일: 2일째엔 아직 부상")
	Colony.settle_day()
	ok = _check(Colony.get_resident(hurt)["health"] == Enums.HealthState.OK, "3일 지나면 회복") and ok

	_build(&"infirmary")
	var medic := _person({"stats": {&"heart": 6}})
	Colony.assign_job(medic, &"medical")
	Colony.residents[hurt]["health"] = Enums.HealthState.INJURED
	Colony.residents[hurt]["recover_days"] = 3
	var sick := _person()
	Colony.residents[sick]["health"] = Enums.HealthState.SICK
	Colony.residents[sick]["recover_days"] = 4
	var report := Colony.settle_day()
	ok = _check(Colony.get_resident(hurt)["health"] == Enums.HealthState.OK, "의무실 + 의료 담당 → 부상 1일") and ok
	ok = _check(Colony.get_resident(sick)["health"] == Enums.HealthState.OK and report["consumed"].get(&"medicine") == 1, "의약품 1로 질병 치료") and ok

	_fresh({&"food": 500})
	GameState.load_data({"day": 46})  # winter
	for i in 6:
		_person()
	var fell := false
	for day in 15:
		for e in Colony.settle_day()["events"]:
			if e["type"] == &"fell_sick":
				fell = true
	ok = _check(fell, "겨울에는 병에 걸리는 사람이 생김") and ok
	return ok


func _test_rescue_return() -> bool:
	_fresh()
	var id := _person()
	Colony.residents[id]["status"] = Enums.ResidentStatus.STRANDED
	var before := Colony.residents.size()
	EventBus.rescue_completed.emit(Colony.get_resident(id).duplicate(true))
	return _check(Colony.residents.size() == before and Colony.get_resident(id)["status"] == Enums.ResidentStatus.ACTIVE, "고립된 주민을 구하면 같은 사람이 돌아옴 (복제 안 됨)")


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_needs] 실패: " + what)
	return cond
