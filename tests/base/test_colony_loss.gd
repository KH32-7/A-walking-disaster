extends Node
## C-20: 고립 → 실종 타이머 (Settings strand_days), 구출 귀환, 사망 뒤 사기·슬픔·추모비·장례,
## 보호자 승계, 질병 방치 사망, save. Called by tests/run_tests.gd. Restores what it changes.

var _missing: Array[StringName] = []
var _funerals: Array = []
var _guardians: Array = []


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	var strand_days = Settings.get_value(&"strand_days")
	var permadeath = Settings.get_value(&"permadeath")
	Colony.resident_missing.connect(_on_missing)
	Colony.funeral_ready.connect(_on_funeral)
	Colony.guardian_changed.connect(_on_guardian)
	var ok := true
	ok = _test_strand() and ok
	ok = _test_death() and ok
	ok = _test_memorial() and ok
	ok = _test_guardian() and ok
	ok = _test_neglect() and ok
	Colony.resident_missing.disconnect(_on_missing)
	Colony.funeral_ready.disconnect(_on_funeral)
	Colony.guardian_changed.disconnect(_on_guardian)
	Settings.set_value(&"strand_days", strand_days)
	Settings.set_value(&"permadeath", permadeath)
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _on_missing(id: StringName) -> void:
	_missing.append(id)


func _on_funeral(ids: Array) -> void:
	_funerals.append(ids)


func _on_guardian(child: StringName, guardian: StringName) -> void:
	_guardians.append([child, guardian])


func _fresh() -> void:
	GameState.load_data({"day": 12})
	Economy.load_data({})
	Colony.load_data({})
	Colony._rng.seed = 20
	_missing.clear()
	_funerals.clear()
	_guardians.clear()


func _add(extra: Dictionary = {}) -> StringName:
	var p := {"traits": []}
	p.merge(extra)
	return Colony.add_resident(p)


func _test_strand() -> bool:
	_fresh()
	Settings.set_value(&"strand_days", 3)
	var a := _add()
	Colony.residents[a]["assignment"] = {"job": &"woodcutting", "building_id": &""}
	var bed: StringName = Colony.get_resident(a)["bed_id"]
	Colony._on_companion_stranded(a, &"flooded_mall")
	var r := Colony.get_resident(a)
	var ok := _check(r["status"] == Enums.ResidentStatus.STRANDED and r["strand_days_left"] == 3 and Colony.job_of(a) == &"", "고립: 기한 3일, 작업 해제")
	ok = _check(Colony.stranded_in(&"flooded_mall") == [a] and r["bed_id"] == bed, "지역별 고립 목록, 침상은 남겨 둠") and ok
	var events: Array = []
	Colony._settle_loss(events)
	Colony._settle_loss(events)
	ok = _check(Colony.get_resident(a)["status"] == Enums.ResidentStatus.STRANDED and Colony.stranded_residents()[0]["days_left"] == 1, "이틀 뒤 하루 남음") and ok
	Colony._settle_loss(events)
	r = Colony.get_resident(a)
	ok = _check(r["status"] == Enums.ResidentStatus.MISSING and r["bed_id"] == &"" and _missing == [a], "기한이 지나면 실종, 침상 비움") and ok
	ok = _check(events.any(func(e): return e["type"] == &"missing") and Colony.stranded_residents().is_empty(), "실종 이벤트") and ok

	_fresh()
	Settings.set_value(&"strand_days", 0)
	var b := _add()
	Colony._on_companion_stranded(b, &"flooded_mall")
	for i in 20:
		Colony._settle_loss([])
	ok = _check(Colony.get_resident(b)["status"] == Enums.ResidentStatus.STRANDED and Colony.get_resident(b)["strand_days_left"] == -1, "보호 모드(0): 기한 없음") and ok
	Colony._on_rescue_completed(Colony.get_resident(b))
	r = Colony.get_resident(b)
	ok = _check(r["status"] == Enums.ResidentStatus.ACTIVE and r["stranded_region"] == &"" and Colony.stranded_residents().is_empty(), "구출하면 돌아옴") and ok
	Settings.set_value(&"strand_days", 3)
	Colony._on_companion_stranded(b, &"flooded_mall")
	Colony.load_data(JSON.parse_string(JSON.stringify(Colony.save_data())))
	ok = _check(Colony.stranded_residents() == [{"resident_id": b, "region_id": &"flooded_mall", "days_left": 3}], "저장 후 고립 유지: %s" % [Colony.stranded_residents()]) and ok
	return ok


func _test_death() -> bool:
	_fresh()
	var a := _add({"name": "가"})
	var spouse := _add()
	var friend := _add()
	var stranger := _add()
	Colony.add_relation(a, spouse, 90)
	Colony._relation_meta(a, spouse)["flags"] = [Enums.RelationFlag.MARRIED]
	Colony.add_relation(a, friend, 40)
	for id in [spouse, friend, stranger]:
		Colony.residents[id]["morale"] = 60
	Colony._kill(a, &"raid")
	var ok := _check(Colony.get_resident(spouse)["grief_days"] == LossRules.GRIEF_SPOUSE_DAYS and Colony.get_resident(friend)["grief_days"] == LossRules.GRIEF_DAYS
		and Colony.get_resident(stranger)["grief_days"] == 0, "슬픔: 배우자 10일, 친구 5일, 모르는 사이 없음")
	ok = _check(Colony.get_resident(stranger)["morale"] == 50 and Colony.get_resident(friend)["morale"] == 42 and Colony.get_resident(spouse)["morale"] == 32,
		"동료 사망 사기 −10~−30 (관계에 따라): %d %d %d" % [Colony.get_resident(stranger)["morale"], Colony.get_resident(friend)["morale"], Colony.get_resident(spouse)["morale"]]) and ok
	ok = _check(Colony.memorial_names().size() == 1 and Colony.memorial_names()[0]["name"] == "가" and GameState.has_flag(LossRules.FIRST_DEATH_FLAG), "추모비 이름, 추모비 건설 해금") and ok
	ok = _check(Colony.partner_of(spouse) == &"" and Colony.couples().is_empty(), "배우자 관계 끝") and ok
	ok = _check(is_equal_approx(Colony._grief_mult(friend), 0.8), "슬픔 중 효율 −20%%") and ok
	Colony._on_flow_state_changed(Enums.FlowState.BASE_MORNING)
	ok = _check(_funerals == [[a]] and Colony.pending_funeral() == [a], "다음 날 아침 장례") and ok
	Colony.end_funeral()
	ok = _check(Colony.pending_funeral().is_empty(), "장례 끝") and ok
	for i in 5:
		Colony._settle_loss([])
	ok = _check(Colony.get_resident(friend)["grief_days"] == 0 and Colony.get_resident(spouse)["grief_days"] == 5, "슬픔은 하루씩 줄어듦") and ok
	Colony.load_data(JSON.parse_string(JSON.stringify(Colony.save_data())))
	ok = _check(Colony.memorial_names()[0]["resident_id"] == a and Colony.memorial_names()[0]["cause"] == &"raid", "저장 후 추모비 유지") and ok
	return ok


func _test_memorial() -> bool:
	_fresh()
	var a := _add()
	Colony.residents[a]["grief_days"] = 3
	Colony.residents[a]["morale"] = 50
	var ok := _check(not Colony.visit_memorial(a)["ok"], "추모비가 없으면 못 감")
	var stone := Colony.place_building(&"memorial", Vector2i.ZERO, 0, &"front_yard", false)
	Colony.complete_building(stone)
	ok = _check(Colony.visit_memorial(a)["ok"] and Colony.get_resident(a)["grief_days"] == 2 and Colony.get_resident(a)["morale"] == 53, "추모비: 슬픔 −1일, 사기 +3") and ok
	ok = _check(not Colony.visit_memorial(a)["ok"], "하루 한 번") and ok
	return ok


func _test_guardian() -> bool:
	_fresh()
	var parent := _add()
	var close := _add()
	var other := _add()
	var child := _add({"age_stage": Enums.AgeStage.CHILD})
	Colony._relation_meta(parent, child)["flags"] = [Enums.RelationFlag.GUARDIAN]
	Colony.add_relation(child, close, 40)
	Colony.add_relation(child, other, 10)
	Colony._kill(parent, &"raid")
	var ok := _check(Colony.guardians_of(child) == [close] and _guardians == [[child, close]], "부모를 잃은 아이: 관계가 가장 높은 주민이 보호자 %s" % [Colony.guardians_of(child)])
	ok = _check(Colony.get_resident(child)["grief_days"] == LossRules.GRIEF_DAYS, "보호자를 잃은 아이도 슬픔") and ok
	return ok


func _test_neglect() -> bool:
	_fresh()
	Settings.set_value(&"permadeath", false)
	var ids: Array[StringName] = []
	for i in 100:
		ids.append(_add())
	for id in ids:
		var r: Dictionary = Colony.residents[id]
		r["health"] = Enums.HealthState.SICK
		r["recover_days"] = 1
		r["hunger"] = 0
	Colony._settle_health({}, [])
	var ok := _check(ids.all(func(id): return Colony.get_resident(id)["status"] == Enums.ResidentStatus.ACTIVE), "보호 모드에서는 질병 방치로 죽지 않음")
	_fresh()
	Settings.set_value(&"permadeath", true)
	ids.clear()
	for i in 100:
		ids.append(_add())
	for id in ids:
		var r: Dictionary = Colony.residents[id]
		r["health"] = Enums.HealthState.SICK
		r["recover_days"] = 1
		r["hunger"] = 0
	Colony._settle_health({}, [])
	var dead := ids.filter(func(id): return Colony.get_resident(id)["status"] == Enums.ResidentStatus.DEAD).size()
	ok = _check(dead > 0 and dead < 40, "치료 못 받고 굶주리면 10%% 확률로 사망 (%d/100)" % dead) and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_loss] 실패: " + what)
	return cond
