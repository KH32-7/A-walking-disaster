extends Node
## 2026-11-07 패치 (연애·결혼·육아에 사건 더하기): 모닥불 가중치, 전우애, 짝사랑, 질투, 기념일, 사랑싸움, 화해,
## 첫걸음, 성장 잔치, 어른 흉내, 가족 식사. Called by tests/run_tests.gd. Restores Colony, Economy and GameState.

var _stages: Array = []


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	var flow := GameState.flow_state
	EventBus.relationship_changed.connect(_on_stage)
	var ok := true
	ok = _test_bonfire_bias() and ok
	ok = _test_comrades() and ok
	ok = _test_crush_and_jealousy() and ok
	ok = _test_couple_events() and ok
	ok = _test_reconcile() and ok
	ok = _test_children() and ok
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
	Colony._rng.seed = 7
	_stages.clear()


func _add(extra: Dictionary = {}) -> StringName:
	var profile := {"traits": []}  # no random traits (혼자가 편함 halves gains)
	profile.merge(extra, true)
	return Colony.add_resident(profile)


func _apply(event_id: StringName, who: Array, choice: StringName = &"watch") -> Dictionary:
	var def := BaseDB.get_night_event(event_id)
	return Colony._apply_night_event({"event_id": event_id, "participants": who, "choices": def.choices.duplicate(),
		"night_day": GameState.day}, choice)


## 모닥불: 첫 사람과 가까운 사람이 더 자주 같이 앉는다.
func _test_bonfire_bias() -> bool:
	_fresh()
	var ids: Array[StringName] = []
	for i in 6:
		ids.append(_add())
	Colony.add_relation(ids[0], ids[1], 60)
	var close := 0
	var other := 0
	for i in 2000:
		var g: Array = Colony._night_candidates(&"bonfire")[0]
		if g[0] == ids[0] and g.size() >= 2:
			if g[1] == ids[1]:
				close += 1
			elif g[1] == ids[2]:
				other += 1
	return _check(close > other * 3, "모닥불: 관계 60인 사람이 남보다 훨씬 자주 (%d vs %d)" % [close, other])


func _test_comrades() -> bool:
	_fresh({&"food": 10})
	var a := _add()
	var b := _add()
	var ok := true
	for i in RelationRules.COMRADE_SORTIES:
		ok = _check(Colony._night_candidates(&"comrade_oath").is_empty(), "출격 %d번으로는 아직 전우 아님" % i) and ok
		Colony._on_sortie_ended({"extracted": true, "companions": [a, b], "stranded": []})
	Colony.add_relation(a, b, RelationRules.COMRADE_MIN_RELATION)
	var groups := Colony._night_candidates(&"comrade_oath")
	ok = _check(groups.size() == 1 and a in groups[0] and b in groups[0], "함께 %d번 살아 돌아오고 관계 20 이상 → 전우의 약속" % RelationRules.COMRADE_SORTIES) and ok
	var morale := int(Colony.residents[a]["morale"])
	var res := _apply(&"comrade_oath", [a, b], &"toast")
	ok = _check(Colony.relation_stage(a, b) == &"comrade" and Enums.RelationFlag.COMRADES in Colony.relation_flags(a, b), "전우가 됨") and ok
	ok = _check(_stages.any(func(s): return s[2] == &"comrade"), "relationship_changed(comrade): 일지가 읽음") and ok
	ok = _check(Economy.get_amount(&"food") == 8 and int(Colony.residents[a]["morale"]) == mini(morale + RelationRules.COMRADE_TOAST_MORALE, 100),
		"건배: 식량 2, 사기 +5 (%s)" % res["text"]) and ok
	ok = _check(not "(가)" in String(res["text"]), "조사 정리: %s" % res["text"]) and ok
	var v := Colony.relation(a, b)
	Colony._on_sortie_ended({"extracted": true, "companions": [a, b], "stranded": []})
	ok = _check(Colony.relation(a, b) == v + RelationRules.SORTIE_TOGETHER * RelationRules.COMRADE_SORTIE_MULT, "전우끼리 출격하면 관계 두 배") and ok
	# 연인이 되고 결혼해도 전우 표시는 남는다.
	Colony._set_lovers(a, b, 20)
	ok = _check(Enums.RelationFlag.COMRADES in Colony.relation_flags(a, b) and Colony.relation_stage(a, b) == &"lover", "연인이 되어도 전우 유지") and ok
	Colony.load_data(JSON.parse_string(JSON.stringify(Colony.save_data())))
	var m: Dictionary = Colony.relation_meta[RelationRules.pair_key(a, b)]
	ok = _check(int(m["sorties"]) == RelationRules.COMRADE_SORTIES + 1 and Enums.RelationFlag.COMRADES in m["flags"], "저장 후 출격 횟수·전우 유지") and ok
	return ok


func _test_crush_and_jealousy() -> bool:
	_fresh()
	var a := _add()
	var b := _add()
	var c := _add()
	Colony.add_relation(a, b, 25)
	var ok := _check(Colony._night_candidates(&"crush").size() == 1, "짝사랑: 관계 20~39 미혼 성인 둘")
	var before := Colony.relation(a, b)
	var res := _apply(&"crush", [a, b], &"nudge")
	var d := Colony.relation(a, b) - before
	ok = _check(d == RelationRules.CRUSH_NUDGE or d == RelationRules.CRUSH_NUDGE_FAIL, "등을 떠밀면 +8 또는 -4 (%d, %s)" % [d, res["text"]]) and ok
	Colony.add_relation(a, b, 40)
	Colony._set_lovers(a, b, 20)
	ok = _check(Colony._night_candidates(&"crush").is_empty(), "연인이 되면 짝사랑 끝") and ok
	Colony.add_relation(b, c, RelationRules.JEALOUSY_AT)
	var groups := Colony._night_candidates(&"jealousy")
	ok = _check(groups.any(func(g): return g == [a, b, c]), "질투: 연인의 상대와 가까운 제3자 %s" % [groups]) and ok
	var lovers := Colony.relation(a, b)
	var ac := Colony.relation(a, c)
	_apply(&"jealousy", [a, b, c], &"watch")
	ok = _check(Colony.relation(a, b) == lovers + RelationRules.JEALOUSY_LOVERS and Colony.relation(a, c) == ac + RelationRules.JEALOUSY_RIVAL,
		"지켜보면 연인 -6, 제3자와 -8") and ok
	return ok


func _test_couple_events() -> bool:
	_fresh({&"cloth": 1})
	var a := _add()
	var b := _add()
	Colony.add_relation(a, b, 60)
	Colony._set_lovers(a, b, 10)
	ok_day(20)
	var ok := _check(Colony._night_candidates(&"anniversary").size() == 1, "기념일: 연인이 된 지 10일")
	ok_day(21)
	ok = _check(Colony._night_candidates(&"anniversary").is_empty(), "기념일은 10일마다만") and ok
	var v := Colony.relation(a, b)
	_apply(&"anniversary", [a, b], &"gift")
	ok = _check(Colony.relation(a, b) == v + RelationRules.ANNIVERSARY_RELATION and Economy.get_amount(&"cloth") == 0, "기념일 관계 +6, 선물에 천 1") and ok
	ok = _check(Colony._night_candidates(&"couple_spat").is_empty(), "둘 다 괜찮으면 사랑싸움 없음") and ok
	Colony.residents[a]["fatigue"] = RelationRules.SPAT_FATIGUE_AT
	ok = _check(Colony._night_candidates(&"couple_spat").size() == 1, "한 명이 지치면 사랑싸움") and ok
	v = Colony.relation(a, b)
	_apply(&"couple_spat", [a, b], &"watch")
	ok = _check(Colony.relation(a, b) == v + RelationRules.SPAT_LOSS, "지켜보면 관계 -6") and ok
	return ok


func ok_day(day: int) -> void:
	GameState.load_data({"day": day})


func _test_reconcile() -> bool:
	_fresh()
	var a := _add()
	var b := _add()
	Colony.add_relation(a, b, -20)
	var ok := _check(Colony._night_candidates(&"reconcile").is_empty(), "같이 나간 적 없으면 화해 없음")
	Colony._on_sortie_ended({"extracted": true, "companions": [a, b], "stranded": []})
	ok = _check(Colony._night_candidates(&"reconcile").size() == 1, "사이 나쁜 둘이 오늘 같이 살아 돌아오면 화해") and ok
	var v := Colony.relation(a, b)
	_apply(&"reconcile", [a, b])
	ok = _check(Colony.relation(a, b) == v + RelationRules.RECONCILE_RELATION, "화해 관계 +12") and ok
	ok_day(21)
	ok = _check(Colony._night_candidates(&"reconcile").is_empty(), "다음 날은 화해 대상 아님") and ok
	return ok


func _test_children() -> bool:
	_fresh({&"food": 10})
	var a := _add()
	var b := _add()
	var m: Dictionary = Colony._relation_meta(a, b)
	m["flags"] = [Enums.RelationFlag.MARRIED]
	Colony.add_relation(a, b, 70)
	var baby := _add({"age_stage": Enums.AgeStage.BABY, "age_days": 0})
	Colony._adopt(m, baby)
	var ok := _check(not _has_group(&"first_steps", baby), "갓난아기는 아직 첫걸음 없음")
	Colony.residents[baby]["age_days"] = ChildRules.FIRST_STEPS_DAY
	ok = _check(_has_group(&"first_steps", baby) and BaseDB.get_night_event(&"first_steps").priority, "4일이 되면 첫걸음 (우선)") and ok
	var morale := int(Colony.residents[a]["morale"])
	_apply(&"first_steps", [baby, a, b], &"cheer")
	ok = _check(int(Colony.residents[a]["morale"]) == mini(morale + ChildRules.FIRST_STEPS_MORALE + RelationRules.CHEER_MORALE, 100), "첫걸음 응원: 보호자 사기 +13") and ok
	ok = _check(not _has_group(&"first_steps", baby), "첫걸음은 한 번만") and ok
	ok = _check(_has_group(&"family_dinner", a), "부부와 아이 → 가족 식사") and ok
	# 아이가 되면 성장 잔치, 선물이면 가장 낮은 능력치 +1.
	Colony.residents[baby]["age_days"] = ChildRules.STAGE_START[Enums.AgeStage.CHILD] - 1
	Colony._age_one_day(baby, [])
	ok = _check(int(Colony.residents[baby]["age_stage"]) == Enums.AgeStage.CHILD and _has_group(&"growth_party", baby), "아이가 되면 성장 잔치") and ok
	var stat := Colony._lowest_stat(baby)
	var low := int(Colony.residents[baby]["stats"][stat])
	var res := _apply(&"growth_party", [baby, a, b], &"gift")
	ok = _check(int(Colony.residents[baby]["stats"][stat]) == mini(low + 1, ResidentData.STAT_MAX) and Economy.get_amount(&"food") == 7,
		"잔치 선물: 식량 3, 능력치 +1 (%s)" % res["text"]) and ok
	ok = _check(not _has_group(&"growth_party", baby), "잔치는 단계마다 한 번") and ok
	# 어른 흉내: 보호자가 익힌 작업을 아이가 따라 한다.
	ok = _check(not _has_group(&"copycat", baby), "보호자 숙련이 없으면 흉내 없음") and ok
	Colony.residents[a]["job_skill"][&"cooking"] = 2
	ok = _check(_has_group(&"copycat", baby), "보호자 숙련이 있으면 어른 흉내") and ok
	res = _apply(&"copycat", [baby, a, b], &"praise")
	ok = _check(int(Colony.residents[baby]["job_skill"].get(&"cooking", 0)) == ChildRules.COPYCAT_SKILL and res.get("job") == &"cooking",
		"흉내로 요리 숙련 1 (%s)" % res["text"]) and ok
	Colony.load_data(JSON.parse_string(JSON.stringify(Colony.save_data())))
	ok = _check(&"copycat" in Colony.residents[baby]["milestones"] and Colony.residents[baby]["milestones"][0] is StringName, "저장 후 milestones 유지") and ok
	return ok


func _has_group(event_id: StringName, member: StringName) -> bool:
	return Colony._night_candidates(event_id).any(func(g): return member in g)


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_bonds] 실패: " + what)
	return cond
