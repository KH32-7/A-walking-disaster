extends Node
## C-05: job assignment, production formula, daily settlement (settle_day).
## Called by tests/run_tests.gd: run() -> bool. Restores Colony and Economy afterwards.


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var ok := true
	ok = _test_formula() and ok
	ok = _test_assignment_rules() and ok
	ok = _test_early_game_baseline() and ok
	ok = _test_inputs_and_food() and ok
	ok = _test_construction_and_skill() and ok
	ok = _test_fuel() and ok
	ok = _test_never_negative() and ok
	ok = _test_save_with_jobs() and ok
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _fresh(resources: Dictionary = {}) -> void:
	Economy.load_data({})
	if not resources.is_empty():
		Economy.apply(resources)
	Colony.load_data({})


func _person(stats: Dictionary, extra: Dictionary = {}) -> StringName:
	var p := {"stats": stats, "traits": [], "former_job": &"laborer"}
	p.merge(extra, true)
	return Colony.add_resident(p)


func _build(def_id: StringName) -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, &"", false)
	Colony.complete_building(uid)
	return uid


func _test_formula() -> bool:
	_fresh()
	var job := BaseDB.get_job(&"woodcutting")
	var r := Colony.get_resident(_person({&"str": 5}))
	var ok := _check(is_equal_approx(WorkRules.efficiency(r, job), 1.5), "힘 5, 숙련 0, 사기 50 → ×1.5")
	r["job_skill"][&"woodcutting"] = 2
	ok = _check(is_equal_approx(WorkRules.efficiency(r, job), 1.5 * 1.3), "숙련 2 → ×1.3") and ok
	r["morale"] = 75
	ok = _check(is_equal_approx(WorkRules.efficiency(r, job), 1.5 * 1.3 * 1.2), "사기 70 이상 → ×1.2") and ok
	r["morale"] = 25
	r["hunger"] = 10
	ok = _check(is_equal_approx(WorkRules.efficiency(r, job), 1.5 * 1.3 * 0.8 * 0.7), "사기 20~39 ×0.8, 배고픔 20 미만 ×0.7") and ok
	r["hunger"] = 70
	r["morale"] = 50
	r["traits"] = [&"diligent"]
	ok = _check(is_equal_approx(WorkRules.efficiency(r, job), 1.5 * 1.3 * 1.1), "부지런함 +10%") and ok
	r["age_stage"] = Enums.AgeStage.TEEN
	ok = _check(is_equal_approx(WorkRules.efficiency(r, job), 1.5 * 1.3 * 1.1 * 0.7), "청소년 ×0.7") and ok
	r["age_stage"] = Enums.AgeStage.ELDER
	ok = _check(is_equal_approx(WorkRules.efficiency(r, BaseDB.get_job(&"teaching")), (1.0 + 0.1 * r["stats"][&"heart"]) * 1.1 * 1.2), "노인 교육 ×1.2") and ok
	ok = _check(WorkRules.food_need({"age_stage": Enums.AgeStage.ADULT, "traits": [&"big_eater"]}) == 3, "대식가 식량 3") and ok
	ok = _check(WorkRules.food_need({"age_stage": Enums.AgeStage.CHILD, "traits": []}) == 1, "아이 식량 1") and ok
	return ok


func _test_assignment_rules() -> bool:
	_fresh()
	var a := _person({&"str": 5})
	var b := _person({&"str": 5})
	var c := _person({&"str": 5})
	var kid := _person({}, {"age_stage": Enums.AgeStage.CHILD})
	var teen := _person({&"heart": 5}, {"age_stage": Enums.AgeStage.TEEN})
	var ok := _check(not Colony.assign_job(a, &"woodcutting"), "벌목장이 없으면 벌목 불가")
	var yard := _build(&"lumber_yard")
	ok = _check(Colony.assign_job(a, &"woodcutting") and Colony.assign_job(b, &"woodcutting"), "벌목장 정원 2") and ok
	ok = _check(Colony.job_block_reason(c, &"woodcutting") != "" and not Colony.assign_job(c, &"woodcutting"), "3번째는 자리 없음") and ok
	Colony.buildings[yard]["level"] = 2
	ok = _check(Colony.building_capacity(yard) == 3 and Colony.assign_job(c, &"woodcutting"), "Lv2 → 정원 +1") and ok
	ok = _check(not Colony.assign_job(kid, &"rest") or Colony.job_of(kid) == &"rest", "아이도 휴식은 가능") and ok
	ok = _check(not Colony.assign_job(kid, &"woodcutting"), "아이는 일하지 않음") and ok
	_build(&"vegetable_garden")
	ok = _check(not Colony.assign_job(teen, &"woodcutting") and Colony.assign_job(teen, &"farming"), "청소년은 텃밭 가능, 벌목 불가") and ok
	Colony.unassign_job(a)
	ok = _check(Colony.job_of(a) == &"" and not a in Colony.get_building(yard)["workers"], "배정 해제") and ok
	Colony.residents[b]["health"] = Enums.HealthState.INJURED
	ok = _check(Colony.job_block_reason(b, &"quarrying") != "", "부상 중에는 배정 불가") and ok
	return ok


## docs/design/11-economy.md "기지 생산 기준": 주민 4명 → 나무 +25/일, 돌 +12/일, 식량은 수지가 맞게.
func _test_early_game_baseline() -> bool:
	_fresh({&"food": 20})
	_build(&"lumber_yard")
	_build(&"quarry")
	_build(&"vegetable_garden")
	var w1 := _person({&"str": 5})
	var w2 := _person({&"str": 6})
	var q := _person({&"str": 5})
	var f := _person({&"heart": 5})
	Colony.residents[q]["job_skill"][&"quarrying"] = 2  # two weeks on the job
	Colony.assign_job(w1, &"woodcutting")
	Colony.assign_job(w2, &"woodcutting")
	Colony.assign_job(q, &"quarrying")
	Colony.assign_job(f, &"farming")
	var report := Colony.settle_day()
	var ch: Dictionary = report["changes"]
	var ok := _check(absi(ch.get(&"wood", 0) - 25) <= 1, "나무 +25/일 (실제 %s)" % ch.get(&"wood"))
	ok = _check(absi(ch.get(&"stone", 0) - 12) <= 1, "돌 +12/일 (실제 %s)" % ch.get(&"stone")) and ok
	ok = _check(absi(ch.get(&"food", 0)) <= 2, "식량 수지 ±2 (실제 %s)" % ch.get(&"food", 0)) and ok
	ok = _check(report["work"].size() == 4 and report["consumed"].get(&"food") == 8, "4명 일함, 식량 8 소비") and ok
	ok = _check(Economy.apply_detailed(ch)["ok"], "A-05처럼 Economy에 반영 가능") and ok
	return ok


func _test_inputs_and_food() -> bool:
	_fresh({&"wood": 4})
	_build(&"carpentry_shop")
	var c := _person({&"dex": 5})
	Colony.assign_job(c, &"carpentry")
	var report := Colony.settle_day()
	var ok := _check(report["consumed"].get(&"wood") == 4 and report["produced"].get(&"plank") == 2, "나무가 모자라면 목재판도 그만큼: %s / %s" % [report["consumed"], report["produced"]])
	ok = _check(report["events"].any(func(e): return e["type"] == &"food_short"), "식량이 없으면 굶음 이벤트") and ok
	ok = _check(Colony.get_resident(c)["hunger"] == 70 - 40, "굶으면 배고픔 −40") and ok

	_fresh({&"food": 30})
	_build(&"kitchen")
	var cook := _person({&"heart": 5})
	var other := _person({&"str": 5})
	Colony.assign_job(cook, &"cooking")
	report = Colony.settle_day()
	ok = _check(Colony.get_resident(other)["hunger"] == 70 - 40 + 70, "요리 식사 +70") and ok
	ok = _check(report["consumed"].get(&"food") == roundi(4 / 1.5), "요리하면 식량 효율 ×1.5 (%s)" % report["consumed"]) and ok
	ok = _check(Colony.get_resident(other)["fatigue"] == 0, "일 안 한 사람은 야영지 침낭에서 회복") and ok
	return ok


func _test_construction_and_skill() -> bool:
	_fresh()
	var builder := _person({&"str": 5})
	var site := Colony.place_building(&"workshop", Vector2i.ZERO, 0, &"", false)
	var ok := _check(Colony.assign_job(builder, &"construction", site), "건설 현장에 배정")
	Colony.settle_day()
	ok = _check(Colony.get_building(site)["progress"] == 15, "하루 10 × (1 + 0.1×힘5) = 15") and ok
	var report := Colony.settle_day()  # 15 + 15 = 30 → done on day 2
	ok = _check(Colony.has_completed(&"workshop") and Colony.job_of(builder) == &"", "30 채우면 완성되고 배정 해제") and ok
	ok = _check(report["events"].any(func(e): return e["type"] == &"building_completed"), "완성 이벤트") and ok

	_fresh({&"food": 100})
	_build(&"lumber_yard")
	var w := _person({&"str": 5})
	Colony.assign_job(w, &"woodcutting")
	var ups := 0
	for day in 10:
		for e in Colony.settle_day()["events"]:
			if e["type"] == &"skill_up" or e["type"] == &"stat_up":
				ups += 1
	var r := Colony.get_resident(w)
	ok = _check(r["job_skill"][&"woodcutting"] == 1 and r["stats"][&"str"] == 6 and ups == 2, "7일 → 숙련 1, 10일 → 힘 +1") and ok
	return ok


func _test_fuel() -> bool:
	_fresh()
	var gen := _build(&"generator")
	var lift := _build(&"elevator")
	var ok := _check(Colony.is_powered(lift), "새 발전기는 첫날 돌아감")
	var report := Colony.settle_day()
	ok = _check(report["events"].any(func(e): return e["type"] == &"no_fuel"), "연료 없음 이벤트") and ok
	ok = _check(not Colony.is_powered(lift) and Colony.power_supply() == 0.0, "연료가 없으면 다음 날 전력 0") and ok
	Economy.apply({&"fuel": 10})
	report = Colony.settle_day()
	ok = _check(report["consumed"].get(&"fuel") == 2 and Colony.is_powered(lift), "연료 2 쓰고 다시 켜짐") and ok
	ok = _check(Colony.get_building(gen)["fueled"], "fueled 플래그") and ok
	return ok


func _test_never_negative() -> bool:
	_fresh({&"food": 7, &"wood": 3})
	_build(&"carpentry_shop")
	_build(&"kitchen")
	_build(&"vegetable_garden")
	for i in 5:
		Colony.add_resident({})
	var ids := Colony.active_resident_ids()
	Colony.assign_job(ids[0], &"carpentry")
	Colony.assign_job(ids[1], &"cooking")
	Colony.assign_job(ids[2], &"farming")
	var ok := true
	for day in 8:
		var ch: Dictionary = Colony.settle_day()["changes"]
		ok = _check(Economy.apply_detailed(ch)["ok"], "정산이 Economy를 음수로 만들지 않음 (%d일차 %s)" % [day, ch]) and ok
	return ok


func _test_save_with_jobs() -> bool:
	_fresh()
	var yard := _build(&"lumber_yard")
	var w := _person({&"str": 5})
	Colony.assign_job(w, &"woodcutting")
	Colony.settle_day()
	var before := JSON.stringify(Colony.save_data(), "", true)
	Colony.load_data(JSON.parse_string(before))
	var ok := _check(JSON.stringify(Colony.save_data(), "", true) == before, "배정 포함 저장 왕복")
	ok = _check(Colony.job_of(w) == &"woodcutting" and w in Colony.get_building(yard)["workers"], "불러온 뒤 배정 유지") and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_settlement] 실패: " + what)
	return cond
