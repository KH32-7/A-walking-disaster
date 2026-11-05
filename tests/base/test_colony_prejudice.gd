extends Node
## C-16: 편견 이벤트 체인 — 소문 → 선택 3가지 → 사건 → 해소, 같은 작업장 사기 −3, save.
## The marked resident never turns into a monster. Called by tests/run_tests.gd.

var _rumors: Array = []
var _resolved: Array = []


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	Colony.prejudice_rumor.connect(_on_rumor)
	Colony.prejudice_resolved.connect(_on_resolved)
	var ok := true
	ok = _test_rumor() and ok
	ok = _test_choices() and ok
	ok = _test_incidents() and ok
	ok = _test_resolution() and ok
	ok = _test_workplace_and_save() and ok
	Colony.prejudice_rumor.disconnect(_on_rumor)
	Colony.prejudice_resolved.disconnect(_on_resolved)
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _on_rumor(target: StringName, holders: Array) -> void:
	_rumors.append([target, holders])


func _on_resolved(holder: StringName, target: StringName) -> void:
	_resolved.append([holder, target])


## Returns [target (마물 흔적), holder (편견)]. Both joined on day 1; today is day 10.
func _fresh() -> Array:
	GameState.load_data({"day": 1})
	Economy.load_data({})
	Colony.load_data({})
	Colony._rng.seed = 16
	_rumors.clear()
	_resolved.clear()
	var target := Colony.add_resident({"name": "흔적", "traits": [&"monster_mark"],
		"story": {"background": "", "fragments": ["첫 조각", "둘째 조각"], "requests": []}})
	var holder := Colony.add_resident({"name": "편견", "traits": [&"prejudiced"]})
	GameState.load_data({"day": 10})
	return [target, holder]


## Puts a chain straight into the rumor step.
func _rumor(target: StringName) -> void:
	Colony._start_rumor(target, Colony._prejudice_holders(), [])


func _test_rumor() -> bool:
	var p := _fresh()
	var target: StringName = p[0]
	var holder: StringName = p[1]
	Colony.residents[holder]["traits"] = []
	for i in 50:
		Colony._settle_prejudice([])
	var ok := _check(Colony.prejudice_chains().is_empty(), "편견을 가진 주민이 없으면 소문 없음")
	Colony.residents[holder]["traits"] = [&"prejudiced"]
	GameState.load_data({"day": 3})
	for i in 50:
		Colony._settle_prejudice([])
	ok = _check(Colony.prejudice_chains().is_empty(), "들어온 지 3일 전에는 소문 없음") and ok
	GameState.load_data({"day": 10})
	for id in [target, holder]:
		Colony.residents[id]["morale"] = 60
	var events: Array = []
	var days := 0
	while Colony.prejudice_chain(target).is_empty() and days < 100:
		Colony._settle_prejudice(events)
		days += 1
	var c := Colony.prejudice_chain(target)
	ok = _check(c.get("step") == PrejudiceRules.STEP_RUMOR and c["holders"] == [holder], "매일 20%%로 소문 (%d일): %s" % [days, c]) and ok
	ok = _check(int(Colony.get_resident(holder)["morale"]) == 55 and _rumors.size() == 1, "기지 전체 사기 −5, prejudice_rumor") and ok
	ok = _check(events.any(func(e): return e["type"] == &"prejudice_rumor"), "정산 이벤트에 소문") and ok
	return ok


func _test_choices() -> bool:
	var p := _fresh()
	var target: StringName = p[0]
	_rumor(target)
	var ok := _check(not Colony.choose_prejudice_response(target, &"shout")["ok"], "없는 선택 거절")
	Colony.residents[target]["morale"] = 50
	var res := Colony.choose_prejudice_response(target, PrejudiceRules.CHOICE_DEFEND)
	ok = _check(res["ok"] and res["incident_day"] >= 15 and res["incident_day"] <= 20, "감싸기: 사건은 5~10일 뒤 (%d)" % res["incident_day"]) and ok
	ok = _check(Colony.get_resident(target)["trust"] == PrejudiceRules.DEFEND_TRUST and Colony.get_resident(target)["morale"] == 55, "감싸면 신뢰 +10, 사기 +5") and ok
	ok = _check(not Colony.choose_prejudice_response(target, PrejudiceRules.CHOICE_WATCH)["ok"], "선택은 한 번") and ok

	p = _fresh()
	target = p[0]
	_rumor(target)
	Colony.residents[target]["morale"] = 50
	res = Colony.choose_prejudice_response(target, PrejudiceRules.CHOICE_SEPARATE)
	ok = _check(res["incident_day"] >= 20 and res["incident_day"] <= 25, "따로 지내게 하면 이야기가 더 늦게 (%d)" % res["incident_day"]) and ok
	ok = _check(Colony.get_resident(target)["morale"] == 30 and Colony.get_resident(target)["bed_id"] == &"", "따로: 사기 −20, 임시 거처") and ok
	return ok


func _test_incidents() -> bool:
	var p := _fresh()
	var target: StringName = p[0]
	var holder: StringName = p[1]
	_rumor(target)
	var day: int = Colony.choose_prejudice_response(target, PrejudiceRules.CHOICE_WATCH)["incident_day"]
	GameState.load_data({"day": day - 1})
	Colony._settle_prejudice([])
	var ok := _check(Colony.prejudice_chain(target)["step"] == PrejudiceRules.STEP_WAITING, "예정일 전에는 기다림")
	GameState.load_data({"day": day})
	var events: Array = []
	Colony._settle_prejudice(events)
	var c := Colony.prejudice_chain(target)
	ok = _check(c["step"] == PrejudiceRules.STEP_INCIDENT and c["incident"] == PrejudiceRules.INCIDENT_RESCUE, "사건: 누군가를 구함") and ok
	ok = _check(Colony.relation(target, holder) > 0 and events.size() == 1, "구해 준 사람과 관계가 오름 (편견 ×0.3이라도): %d" % Colony.relation(target, holder)) and ok

	p = _fresh()
	target = p[0]
	var shop := Colony.place_building(&"essence_workshop", Vector2i.ZERO, 0, &"front_yard", false)
	Colony.complete_building(shop)
	if not Colony.assign_job(target, &"essence_research", shop):
		Colony.buildings[shop]["workers"].append(target)
	ok = _check(target in Colony.facility_workers(&"essence_workshop"), "흔적 주민이 정수 공방에서 일함") and ok
	_rumor(target)
	day = Colony.choose_prejudice_response(target, PrejudiceRules.CHOICE_WATCH)["incident_day"]
	GameState.load_data({"day": day})
	Colony.residents[p[1]]["morale"] = 50
	Colony._settle_prejudice([])
	ok = _check(Colony.prejudice_chain(target)["incident"] == PrejudiceRules.INCIDENT_WORKSHOP and Colony.get_resident(p[1])["morale"] == 55,
		"정수 공방에서 위기를 해결, 전체 사기 +5") and ok
	return ok


func _test_resolution() -> bool:
	var p := _fresh()
	var target: StringName = p[0]
	var holder: StringName = p[1]
	_rumor(target)
	Colony.choose_prejudice_response(target, PrejudiceRules.CHOICE_DEFEND)
	var c: Dictionary = Colony.prejudice_chains_data[target]
	Colony._prejudice_incident(c, [])
	var ok := _check(Colony._night_candidates(PrejudiceRules.RESOLVE_EVENT) == [[holder, target]], "사건 뒤 밤에 해소 대화")
	ok = _check(Colony.roll_night_events().any(func(e): return e["event_id"] == PrejudiceRules.RESOLVE_EVENT), "해소 대화는 우선 이벤트") and ok
	var before := Colony.relation(holder, target)
	var res := Colony._apply_night_event({"event_id": PrejudiceRules.RESOLVE_EVENT, "participants": [holder, target], "choices": [&"watch"], "night_day": 10}, &"")
	ok = _check(not &"prejudiced" in Colony.get_resident(holder)["traits"], "편견 특성이 사라짐") and ok
	ok = _check(Colony.relation(holder, target) == before + PrejudiceRules.RESOLVE_RELATION, "관계 +20 (편견이 사라진 뒤라 그대로)") and ok
	ok = _check(res["fragments"] == ["첫 조각", "둘째 조각"] and Colony.unlocked_story(target) == ["첫 조각", "둘째 조각"], "사연 공개") and ok
	ok = _check(Colony.prejudice_chain(target)["step"] == PrejudiceRules.STEP_RESOLVED and _resolved == [[holder, target]], "체인 끝, prejudice_resolved") and ok
	ok = _check(&"monster_mark" in Colony.get_resident(target)["traits"] and Colony.get_resident(target)["status"] == Enums.ResidentStatus.ACTIVE,
		"흔적이 있는 사람은 마물이 되지 않음 (그대로 주민)") and ok
	ok = _check(Colony._night_candidates(PrejudiceRules.RESOLVE_EVENT).is_empty(), "해소 뒤 다시 일어나지 않음") and ok
	return ok


func _test_workplace_and_save() -> bool:
	var p := _fresh()
	var target: Dictionary = Colony.residents[p[0]]
	var holder: Dictionary = Colony.residents[p[1]]
	var with_target := NeedsRules.daily_morale(holder, {"coworkers": [target]})
	var alone := NeedsRules.daily_morale(holder, {"coworkers": []})
	var ok := _check(with_target - alone == PrejudiceRules.SAME_WORKPLACE_MORALE, "편견 대상과 같은 작업장 사기 −3")
	ok = _check(NeedsRules.daily_morale(target, {"coworkers": [holder]}) == NeedsRules.daily_morale(target, {"coworkers": []}), "흔적 주민 쪽은 그대로") and ok
	_rumor(p[0])
	Colony.choose_prejudice_response(p[0], PrejudiceRules.CHOICE_WATCH)
	var saved := Colony.prejudice_chain(p[0])
	Colony.load_data(JSON.parse_string(JSON.stringify(Colony.save_data())))
	var loaded := Colony.prejudice_chain(p[0])
	ok = _check(loaded == saved and loaded["step"] is StringName and loaded["holders"][0] is StringName, "저장 후 체인 유지: %s" % loaded) and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_prejudice] 실패: " + what)
	return cond
