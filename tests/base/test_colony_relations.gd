extends Node
## C-14: relation values and stages, factors (작업장·모닥불·출격), trait multipliers, decay, the night
## event pool (모닥불·다툼·고백·데이트·청혼·결혼식·이별), the festival and save. Called by
## tests/run_tests.gd. Restores Colony, Economy and GameState.

var _stages: Array = []


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	var flow := GameState.flow_state
	EventBus.relationship_changed.connect(_on_stage)
	var ok := true
	ok = _test_defs() and ok
	ok = _test_values() and ok
	ok = _test_daily() and ok
	ok = _test_bonfire_quarrel() and ok
	ok = _test_romance() and ok
	ok = _test_wedding_and_festival() and ok
	ok = _test_breakup() and ok
	ok = _test_night_flow() and ok
	ok = _test_sortie_and_save() and ok
	EventBus.relationship_changed.disconnect(_on_stage)
	GameState.flow_state = flow
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _on_stage(a: StringName, b: StringName, stage: StringName) -> void:
	_stages.append([a, b, stage])


func _fresh(resources: Dictionary = {}) -> void:
	GameState.load_data({"day": 20})
	GameState.flow_state = Enums.FlowState.BASE_MORNING
	Economy.load_data({})
	if not resources.is_empty():
		Economy.apply(resources)
	Colony.load_data({})
	Colony._rng.seed = 14
	_stages.clear()


func _add(traits: Array = [], extra: Dictionary = {}) -> StringName:
	var profile := {"traits": traits}
	profile.merge(extra)
	return Colony.add_resident(profile)


func _test_defs() -> bool:
	var ids := BaseDB.night_events().keys()
	var ok := _check(ids.size() == 18 and &"prejudice_talk" in ids, "밤 이벤트 7종 + 편견 해소 대화 (C-16) + 2026-11-07 사건 10종: %s" % [ids])
	ok = _check(BaseDB.get_night_event(&"wedding").priority and not BaseDB.get_night_event(&"bonfire").priority, "결혼식은 우선") and ok
	ok = _check(BaseDB.get_night_event(&"quarrel").choices == [&"watch", &"mediate"], "다툼: 지켜보기·중재") and ok
	return ok


func _test_values() -> bool:
	var ok := _check(RelationRules.stage_of(-50) == &"rival" and RelationRules.stage_of(-49) == &"awkward"
		and RelationRules.stage_of(-9) == &"acquainted" and RelationRules.stage_of(30) == &"friend"
		and RelationRules.stage_of(60) == &"best_friend" and RelationRules.stage_of(0, [Enums.RelationFlag.MARRIED]) == &"married",
		"단계 경계 (08 관계 수치)")
	_fresh()
	var a := _add()
	var b := _add()
	ok = _check(Colony.add_relation(a, b, 30) == 30 and Colony.relation(b, a) == 30, "관계는 양쪽이 같음") and ok
	ok = _check(_stages == [[a, b, &"friend"]] if String(a) < String(b) else _stages.size() == 1, "단계가 바뀌면 relationship_changed: %s" % [_stages]) and ok
	ok = _check(Colony.add_relation(a, b, -500) == -100, "−100에서 멈춤") and ok
	var loner := _add([&"loner"])
	var holder := _add([&"prejudiced"])
	var marked := _add([&"monster_mark"])
	var aro := _add([&"aromantic"])
	ok = _check(Colony.add_relation(a, loner, 10) == 5, "혼자가 편함 ×0.5") and ok
	ok = _check(Colony.add_relation(holder, marked, 10) == 3, "편견 → 마물 흔적 ×0.3") and ok
	ok = _check(Colony.add_relation(holder, b, 10) == 10, "편견은 대상에게만") and ok
	ok = _check(Colony.add_relation(aro, b, 10) == 13, "연애에 관심 없음: 우정 +30%%") and ok
	ok = _check(Colony.add_relation(a, b, -5) < 0 and Colony.add_relation(a, a, 5) == 0, "감소는 배율 없음, 자기 자신은 0") and ok
	return ok


func _test_daily() -> bool:
	_fresh()
	var a := _add()
	var b := _add()
	var c := _add()
	for id in [a, b]:
		Colony.residents[id]["assignment"] = {"job": &"woodcutting", "building_id": &""}
	Colony._settle_relations({a: true, b: true, c: true})
	var ok := _check(Colony.relation(a, b) == RelationRules.SAME_WORKPLACE and Colony.relation(a, c) == 0, "같은 작업장에서 하루 +2")
	Colony.add_relation(a, c, 40)
	Colony.relation_meta[RelationRules.pair_key(a, c)]["last_day"] = 10
	Colony._settle_relations({})
	ok = _check(Colony.relation(a, c) == 39, "10일 교류 없음 → −1") and ok
	Colony.residents[a]["relations"][c] = 30
	Colony.residents[c]["relations"][a] = 30
	Colony._settle_relations({})
	ok = _check(Colony.relation(a, c) == 30, "30에서 멈춤") and ok
	Colony.add_relation(a, b, 60)
	ok = _check(is_equal_approx(Colony._best_friend_mult(a), 1.1), "절친과 같은 작업장 효율 +10%%") and ok
	Colony.residents[a]["relations"][b] = -60
	Colony.residents[b]["relations"][a] = -60
	var ctx := {"coworkers": [Colony.residents[b]]}
	var rival := NeedsRules.daily_morale(Colony.residents[a], ctx)
	Colony.residents[a]["relations"][b] = 0
	ok = _check(rival - NeedsRules.daily_morale(Colony.residents[a], ctx) == -5, "앙숙과 같은 작업장 사기 −5") and ok
	return ok


func _test_bonfire_quarrel() -> bool:
	_fresh()
	var a := _add([&"chatty"], {"likes": [&"tea"]})
	var b := _add([], {"likes": [&"tea"]})
	var ok := true
	var r := Colony._apply_night_event({"event_id": &"bonfire", "participants": [a, b], "choices": [&"watch"], "night_day": 20}, &"")
	var v := Colony.relation(a, b)
	ok = _check(v >= 2 * 2 + 2 and v <= 5 * 2 + 2, "모닥불: (2~5) × 수다쟁이 2 + 취향 같음 2 = %d" % v) and ok
	ok = _check(r["text"] != "", "모닥불 결과 문장") and ok

	_fresh()
	a = _add()
	b = _add()
	Colony.add_relation(a, b, -20)
	ok = _check(Colony._night_candidates(&"quarrel").is_empty(), "피곤하지 않으면 다툼 없음") and ok
	Colony.residents[a]["fatigue"] = 85
	ok = _check(Colony._night_candidates(&"quarrel").size() == 1, "관계 −10 이하 + 피로 80 이상 → 다툼") and ok
	for id in [a, b]:
		Colony.residents[id]["trust"] = 100
	var ev := {"event_id": &"quarrel", "participants": [a, b], "choices": [&"watch", &"mediate"], "night_day": 20}
	r = Colony._apply_night_event(ev, &"mediate")
	ok = _check(r["mediated"] and Colony.relation(a, b) == -15, "신뢰도 100이면 중재 성공 +5") and ok
	Colony._apply_night_event(ev, &"watch")
	ok = _check(Colony.relation(a, b) <= -20 and Colony.relation(a, b) >= -30, "지켜보면 −5~−15") and ok
	return ok


func _test_romance() -> bool:
	_fresh()
	var a := _add()
	var b := _add()
	var aro := _add([&"aromantic"])
	var kid := _add([], {"age_stage": Enums.AgeStage.CHILD})
	Colony.add_relation(a, b, 55)
	Colony.residents[a]["relations"][aro] = 70
	Colony.residents[aro]["relations"][a] = 70
	Colony.residents[a]["relations"][kid] = 70
	Colony.residents[kid]["relations"][a] = 70
	var groups := Colony._night_candidates(&"confession")
	var ok := _check(groups.size() == 1 and a in groups[0] and b in groups[0], "고백: 관계 40 이상 미혼 성인, 연애에 관심 없음·아이 제외 %s" % [groups])
	var morale := int(Colony.residents[a]["morale"])
	Colony._apply_night_event({"event_id": &"confession", "participants": [a, b], "choices": [&"watch", &"cheer"], "night_day": 20}, &"cheer")
	ok = _check(Colony.relation_stage(a, b) == &"lover" and Colony.partner_of(a) == b, "고백 → 연인") and ok
	ok = _check(_stages.any(func(s): return s[2] == &"lover"), "고백은 relationship_changed(lover) — 일지(A-17)가 읽음") and ok
	ok = _check(int(Colony.residents[a]["morale"]) == mini(morale + 5, 100), "응원하면 사기 +5") and ok
	ok = _check(Colony._night_candidates(&"confession").is_empty() and Colony._night_candidates(&"date").size() == 1, "연인은 고백 대상이 아니고 데이트 대상") and ok
	Colony._apply_night_event({"event_id": &"date", "participants": [a, b], "choices": [&"watch"], "night_day": 20}, &"")
	ok = _check(Colony.relation(a, b) == 60, "데이트 관계 +5") and ok
	ok = _check(Colony._night_candidates(&"proposal").is_empty(), "연인 7일·관계 70 전에는 청혼 없음") and ok
	Colony.add_relation(a, b, 25)
	GameState.load_data({"day": 30})
	for id in [a, b]:
		Colony.residents[id]["morale"] = 60
	ok = _check(Colony._night_candidates(&"proposal").size() == 1, "연인 7일, 관계 70, 사기 50 → 청혼") and ok
	return ok


func _test_wedding_and_festival() -> bool:
	_fresh()
	var a := _add()
	var b := _add()
	Colony.add_relation(a, b, 85)
	Colony._set_lovers(a, b, 1)
	Colony._apply_night_event({"event_id": &"proposal", "participants": [a, b], "choices": [&"watch"], "night_day": 20}, &"")
	var status := Colony.wedding_status(a, b)
	var ok := _check(not status["ok"] and status["missing"].size() == 3, "식량·천·가족 숙소가 없으면 준비 못 함: %s" % [status["missing"]])
	Economy.apply({&"food": 25, &"cloth": 5})
	var house := Colony.place_building(&"family_house", Vector2i.ZERO, 0, &"front_yard", false)
	Colony.complete_building(house)
	ok = _check(Colony.prepare_wedding(a, b) and Economy.get_amount(&"food") == 5 and Economy.get_amount(&"cloth") == 0, "결혼식 준비: 식량 20, 천 5") and ok
	var tonight := Colony.roll_night_events()
	ok = _check(tonight.any(func(e): return e["event_id"] == &"wedding"), "준비되면 그날 밤 결혼식 (우선)") and ok
	Colony._apply_night_event({"event_id": &"wedding", "participants": [a, b], "choices": [&"watch"], "night_day": 20}, &"")
	ok = _check(Colony.relation_stage(a, b) == &"married" and Colony.couples().size() == 1, "결혼 → 배우자") and ok
	ok = _check(String(Colony.get_resident(a)["bed_id"]).begins_with(String(house)), "가족 숙소로 옮김") and ok
	ok = _check(Colony.festival_day == 21, "다음 날 축제") and ok

	var worker := _add()
	Colony.residents[worker]["assignment"] = {"job": &"woodcutting", "building_id": &""}
	GameState.load_data({"day": 21})
	var before := int(Colony.residents[worker]["morale"])
	var report := Colony.settle_day()
	ok = _check(report["work"].is_empty() and report["events"].any(func(e): return e["type"] == &"festival"), "축제 날 생산 0") and ok
	ok = _check(int(Colony.residents[worker]["morale"]) - before >= 15 - 10, "축제 사기 +15 (%d → %d)" % [before, Colony.residents[worker]["morale"]]) and ok
	return ok


func _test_breakup() -> bool:
	_fresh()
	var a := _add()
	var b := _add()
	Colony.add_relation(a, b, 20)
	Colony._set_lovers(a, b, 1)
	for i in 6:
		Colony._settle_relations({})
	var ok := _check(Colony._night_candidates(&"breakup").is_empty(), "6일은 아직")
	Colony._settle_relations({})
	ok = _check(Colony._night_candidates(&"breakup").size() == 1, "관계 30 미만 7일 → 이별") and ok
	for id in [a, b]:
		Colony.residents[id]["morale"] = 50
	Colony._apply_night_event({"event_id": &"breakup", "participants": [a, b], "choices": [&"watch"], "night_day": 20}, &"")
	ok = _check(Colony.partner_of(a) == &"" and int(Colony.residents[a]["morale"]) == 35, "이별: 관계 해소, 사기 −15") and ok
	ok = _check(not _stages.is_empty() and _stages.back()[2] == RelationRules.SEPARATED, "이별은 relationship_changed(separated) — 일지(A-17)가 읽음") and ok
	return ok


func _test_night_flow() -> bool:
	_fresh()
	var a := _add()
	var b := _add()
	GameState.flow_state = Enums.FlowState.NIGHT
	Colony.last_night_raid_day = 20
	Colony._roll_tonight()
	var ok := _check(Colony.pending_night_events().is_empty(), "습격이 있는 밤에는 이벤트 없음")
	GameState.load_data({"day": 21})
	GameState.flow_state = Enums.FlowState.NIGHT
	Colony._roll_tonight()
	var queued := Colony.pending_night_events()
	ok = _check(queued.size() >= 1 and queued.size() <= 2 and queued[0]["event_id"] == &"bonfire", "밤마다 1~2개 (2명이면 모닥불): %s" % [queued]) and ok
	GameState.flow_state = Enums.FlowState.BASE_MORNING  # no router calls in the test
	var ev := Colony.next_night_event()
	ok = _check(ev["event_id"] == &"bonfire" and Colony.next_night_event().is_empty(), "하나씩 진행") and ok
	var res := Colony.resolve_night_event(&"no_such_choice")
	ok = _check(res["choice"] == &"watch" and Colony.relation(a, b) > 0, "모르는 선택은 첫 선택으로") and ok
	Colony.night_queue = [{"event_id": &"date", "participants": [a, b], "choices": [&"watch"], "night_day": 21}]
	Colony._set_lovers(a, b, 21)
	var v := Colony.relation(a, b)
	Colony._finish_night()
	ok = _check(Colony.night_queue.is_empty() and Colony.relation(a, b) == v + 5, "아침에 남은 이벤트는 자동 진행") and ok
	return ok


func _test_sortie_and_save() -> bool:
	_fresh()
	var a := _add()
	var b := _add()
	var c := _add()
	Colony._on_sortie_ended({"extracted": true, "companions": [a, b, c], "stranded": [c]})
	var ok := _check(Colony.relation(a, b) == 5 and Colony.relation(a, c) == 0, "함께 살아 돌아온 동행끼리 +5")
	Colony._set_lovers(a, b, 20)
	Colony.festival_day = 22
	Colony.load_data(JSON.parse_string(JSON.stringify(Colony.save_data())))
	ok = _check(Colony.relation_stage(a, b) == &"lover" and Colony.relation(b, a) == 5 and Colony.festival_day == 22, "저장 후 관계·연인·축제 날 유지") and ok
	ok = _check(Colony.relation_meta[RelationRules.pair_key(a, b)]["a"] is StringName, "불러온 뒤 id는 StringName") and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_relations] 실패: " + what)
	return cond
