extends Node
## C-15: 아이 맞이 conditions, the 5% wish, birth (10 days, pregnancy limits), adoption (orphan in
## the base, or waiting for a rescued child), child data, growth stages, classroom 전수, save.
## Called by tests/run_tests.gd. Restores Colony, Economy and GameState.

var _wishes: Array = []
var _arrived: Array = []


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	Colony.child_wish.connect(_on_wish)
	Colony.child_arrived.connect(_on_arrived)
	var ok := true
	ok = _test_gender() and ok
	ok = _test_conditions() and ok
	ok = _test_wish_roll() and ok
	ok = _test_birth() and ok
	ok = _test_adoption() and ok
	ok = _test_growth() and ok
	ok = _test_study() and ok
	Colony.child_wish.disconnect(_on_wish)
	Colony.child_arrived.disconnect(_on_arrived)
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _on_wish(a: StringName, b: StringName, methods: Array) -> void:
	_wishes.append([a, b, methods])


func _on_arrived(child: StringName, method: int, parents: Array) -> void:
	_arrived.append([child, method, parents])


func _fresh() -> void:
	GameState.load_data({"day": 30})
	Economy.load_data({})
	Economy.apply({&"food": 100})
	Colony.load_data({})
	Colony._rng.seed = 15
	_wishes.clear()
	_arrived.clear()


## A married couple in their own family house, with an infirmary. Returns [a, b, house_uid].
## `birth` = a is a woman (출산 가능); otherwise both are men (입양만).
func _family(birth: bool = false) -> Array:
	var a := Colony.add_resident({"name": "가", "traits": [&"brave"], "gender": "female" if birth else "male"})
	var b := Colony.add_resident({"name": "나", "traits": [&"optimist"], "gender": "male"})
	var house := _build(&"family_house")
	_build(&"infirmary")
	Colony.add_relation(a, b, 85)
	var m := Colony._relation_meta(a, b)
	m["flags"] = [Enums.RelationFlag.MARRIED]
	m["house_uid"] = house
	Colony._move_into_house([a, b], house)
	for id in [a, b]:
		Colony.residents[id]["morale"] = 70
	return [a, b, house]


func _build(def_id: StringName) -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, &"front_yard", false)
	Colony.complete_building(uid)
	return uid


func _test_gender() -> bool:
	_fresh()
	var ok := _check(Colony.get_resident(Colony.add_resident({"traits": [], "gender": "여성"}))["gender"] == ResidentData.GENDER_FEMALE
		and Colony.get_resident(Colony.add_resident({"traits": [], "gender": &"male"}))["gender"] == ResidentData.GENDER_MALE,
		"프로필의 성별을 그대로 (여성·male)")
	var seen := {}
	for i in 40:
		var g: StringName = Colony.get_resident(Colony.add_resident({"traits": []}))["gender"]
		seen[g] = true
	ok = _check(seen.size() == 2 and seen.has(ResidentData.GENDER_FEMALE), "프로필에 없으면 반반으로 정함: %s" % [seen.keys()]) and ok
	var old := ResidentData.normalize({"id": &"old_save"})
	ok = _check(old["gender"] in ResidentData.GENDERS and ResidentData.normalize({"id": &"old_save"})["gender"] == old["gender"],
		"성별 없는 옛 저장은 id로 늘 같은 값") and ok
	var id := Colony.add_resident({"traits": [], "gender": "female"})
	Colony.load_data(JSON.parse_string(JSON.stringify(Colony.save_data())))
	ok = _check(Colony.get_resident(id)["gender"] == ResidentData.GENDER_FEMALE and Colony.get_resident(id)["gender"] is StringName, "저장 후 유지") and ok
	return ok


func _test_conditions() -> bool:
	_fresh()
	var f := _family()
	var a: StringName = f[0]
	var b: StringName = f[1]
	var ok := _check(Colony.child_arrival_status(a, b)["ok"], "조건 충족: %s" % [Colony.child_arrival_status(a, b)["missing"]])
	ok = _check(Colony.child_methods(a, b) == [Enums.ArrivalMethod.ADOPTION], "남성 둘이면 입양만") and ok
	Colony.residents[b]["gender"] = ResidentData.GENDER_FEMALE
	ok = _check(Colony.child_methods(a, b) == [Enums.ArrivalMethod.BIRTH, Enums.ArrivalMethod.ADOPTION], "여성이 있으면 출산도") and ok
	Colony.residents[a]["gender"] = ResidentData.GENDER_FEMALE
	ok = _check(Colony.child_methods(a, b)[0] == Enums.ArrivalMethod.BIRTH, "여성 둘도 출산 가능") and ok
	ok = _check(not ChildRules.can_give_birth({"gender": ResidentData.GENDER_FEMALE, "age_stage": Enums.AgeStage.TEEN}), "미성년은 출산 대상 아님") and ok
	Colony.residents[a]["gender"] = ResidentData.GENDER_MALE
	Colony.residents[b]["gender"] = ResidentData.GENDER_MALE
	Colony.residents[a]["morale"] = 50
	Economy.load_data({})
	var missing: Array = Colony.child_arrival_status(a, b)["missing"]
	ok = _check(missing.size() == 2, "사기 60 미만·식량 부족: %s" % [missing]) and ok
	var c := Colony.add_resident({"traits": []})
	ok = _check(not Colony.child_arrival_status(a, c)["ok"], "결혼하지 않은 둘은 안 됨") and ok
	return ok


func _test_wish_roll() -> bool:
	_fresh()
	var f := _family()
	var events: Array = []
	var days := 0
	while Colony.child_wishes().is_empty() and days < 400:
		Colony._settle_children(events)
		days += 1
	var ok := _check(Colony.child_wishes().size() == 1 and _wishes.size() == 1, "매일 5%%면 언젠가 대화가 뜸 (%d일)" % days)
	ok = _check(days > 1 and events.any(func(e): return e["type"] == &"child_wish"), "첫날에 바로는 드묾, 이벤트 기록") and ok
	ok = _check(Colony.answer_child_wish(f[0], f[1], &"later")["ok"] and Colony.child_wishes().is_empty() and _arrived.is_empty(), "나중에 → 대화만 닫힘") and ok
	return ok


func _test_birth() -> bool:
	_fresh()
	var f := _family(true)
	var a: StringName = f[0]
	var b: StringName = f[1]
	Colony.relation_meta[RelationRules.pair_key(a, b)]["wish_day"] = 30
	var res := Colony.answer_child_wish(a, b, &"now", Enums.ArrivalMethod.BIRTH)
	var ok := _check(res["ok"] and res["due_day"] == 40 and Colony.is_pregnant(a) and not Colony.is_pregnant(b), "출산: 10일 뒤, 출산할 수 있는 쪽")
	ok = _check(Colony.sortie_block_reason(a) != "" and Colony.sortie_block_reason(b) == "", "출격 불가") and ok
	ok = _check(Colony.job_block_reason(a, &"guard") != "", "경비 배정 불가") and ok
	var str_job := BaseDB.get_job(&"woodcutting")
	if str_job.main_stat_key() == &"str":
		ok = _check(is_equal_approx(Colony._pregnancy_mult(a, str_job), 0.7), "힘 작업 효율 ×0.7") and ok
	GameState.load_data({"day": 40})
	var events: Array = []
	Colony._settle_children(events)
	ok = _check(_arrived.size() == 1 and _arrived[0][1] == Enums.ArrivalMethod.BIRTH, "10일째 태어남") and ok
	var child: StringName = _arrived[0][0]
	var r := Colony.get_resident(child)
	ok = _check(r["age_stage"] == Enums.AgeStage.BABY and r["arrival_pending"] and not Colony.is_pregnant(a), "아기, 이름 짓기 대기") and ok
	ok = _check(r["traits"].size() == 1 and r["traits"][0] in [&"brave", &"optimist"], "특성 1개를 부모에게서: %s" % [r["traits"]]) and ok
	ok = _check(r["stats"].values().all(func(v): return v >= 1 and v <= 3), "초기 능력치 1~3") and ok
	ok = _check(r["gender"] in ResidentData.GENDERS, "태어난 아이도 성별이 있음") and ok
	var guardians := Colony.guardians_of(child)
	ok = _check(guardians.size() == 2 and a in guardians and b in guardians and Colony.children_of(a, b) == [child], "부모가 보호자") and ok
	ok = _check(String(r["bed_id"]).begins_with(String(f[2])), "가족 숙소 침상") and ok
	ok = _check(Colony._needs_care(a) and is_equal_approx(Colony.access_multiplier(a), NeedsRules.CARE_UNMET_MULT), "아기 보호자: 돌봄방 없으면 효율 0.5") and ok
	ok = _check(not Colony.name_child(child, "")["ok"] and Colony.name_child(child, "하늘")["ok"] and Colony.get_resident(child)["name"] == "하늘", "이름 짓기") and ok
	ok = _check(not Colony.child_arrival_status(a, b)["ok"], "다음 아이 맞이까지 20일") and ok
	Colony.load_data(JSON.parse_string(JSON.stringify(Colony.save_data())))
	ok = _check(Colony.children_of(a, b) == [child] and Colony.guardians_of(child).size() == 2, "저장 후 가족 유지") and ok
	return ok


func _test_adoption() -> bool:
	_fresh()
	var f := _family()
	var a: StringName = f[0]
	var b: StringName = f[1]
	var orphan := Colony.add_resident({"traits": [], "age_stage": Enums.AgeStage.CHILD})
	var m: Dictionary = Colony.relation_meta[RelationRules.pair_key(a, b)]
	m["wish_day"] = 30
	var res := Colony.answer_child_wish(a, b, &"now", Enums.ArrivalMethod.BIRTH)
	var ok := _check(not res["ok"], "출산할 수 없는 가족은 출산 거절")
	m["wish_day"] = 30
	res = Colony.answer_child_wish(a, b, &"now", Enums.ArrivalMethod.ADOPTION)
	ok = _check(res["ok"] and res["child_id"] == orphan and Colony.orphans().is_empty(), "기지의 보호자 없는 아이를 바로 입양") and ok

	_fresh()
	f = _family()
	a = f[0]
	b = f[1]
	Colony.relation_meta[RelationRules.pair_key(a, b)]["wish_day"] = 30
	res = Colony.answer_child_wish(a, b, &"now", Enums.ArrivalMethod.ADOPTION)
	ok = _check(res["ok"] and res["waiting"] and not Colony.child_arrival_status(a, b)["ok"], "아이가 없으면 소문을 기다림") and ok
	Colony._on_rescue_completed({"id": &"lost_kid", "name": "다온", "traits": [], "age_stage": Enums.AgeStage.CHILD})
	ok = _check(Colony.guardians_of(&"lost_kid").size() == 2 and _arrived.back()[1] == Enums.ArrivalMethod.ADOPTION, "구조된 아이를 그 가족이 입양") and ok
	ok = _check(Colony.get_resident(&"lost_kid")["arrival_pending"], "입양된 아이도 입주 의식") and ok
	return ok


func _test_growth() -> bool:
	_fresh()
	var baby := Colony.add_resident({"traits": [], "age_stage": Enums.AgeStage.BABY, "age_days": 9})
	var teen := Colony.add_resident({"traits": [], "age_stage": Enums.AgeStage.TEEN})
	var almost := Colony.add_resident({"traits": [], "age_stage": Enums.AgeStage.TEEN, "age_days": 49})
	var adult := Colony.add_resident({"traits": []})
	var events: Array = []
	for id in [baby, teen, almost, adult]:
		Colony._age_one_day(id, events)
	var ok := _check(Colony.get_resident(baby)["age_stage"] == Enums.AgeStage.CHILD, "아기 10일 → 아이")
	ok = _check(Colony.get_resident(teen)["age_days"] == 31 and Colony.get_resident(teen)["age_stage"] == Enums.AgeStage.TEEN, "구조된 청소년은 30일부터") and ok
	ok = _check(Colony.get_resident(almost)["age_stage"] == Enums.AgeStage.ADULT, "50일 → 성인") and ok
	ok = _check(Colony.get_resident(adult)["age_days"] == 0 and events.size() == 2, "성인은 나이 들지 않음, 성장 이벤트 2개") and ok
	# 아이 놀이: with a child (the baby grew into one) everyone gets +2 morale.
	var ids: Array[StringName] = [adult, baby]
	Colony.residents[adult]["morale"] = 50
	var with_kid := int(Colony._settle_morale(ids, {}, [])[adult])
	Colony.residents[baby]["age_stage"] = Enums.AgeStage.TEEN
	Colony.residents[adult]["morale"] = 50
	var without := int(Colony._settle_morale(ids, {}, [])[adult])
	ok = _check(with_kid - without == ChildRules.PLAY_MORALE, "아이 놀이: 주변 사기 +2 (%d vs %d)" % [with_kid, without]) and ok
	return ok


func _test_study() -> bool:
	_fresh()
	var teacher := Colony.add_resident({"traits": [], "former_job": &"carpenter", "stats": {&"heart": 5}})
	var kid := Colony.add_resident({"traits": [], "age_stage": Enums.AgeStage.CHILD, "stats": {&"dex": 1}})
	var room := _build(&"classroom")
	var ok := _check(Colony.assign_job(teacher, &"teaching", room), "교사 배정: %s" % Colony.job_block_reason(teacher, &"teaching", room))
	var events: Array = []
	for i in ChildRules.STUDY_DAYS:
		Colony._study(events)
	var r := Colony.get_resident(kid)
	ok = _check(int(r["job_skill"].get(&"carpentry", 0)) == 1 and events.any(func(e): return e["type"] == &"taught"), "교실 20일 → 교사 전직(목수) 숙련 1단계") and ok
	ok = _check(int(r["stats"][&"dex"]) == 1 + ChildRules.STUDY_DAYS * 2 / WorkRules.DAYS_PER_STAT, "교실 능력치 성장 ×2: 손재주 %d" % r["stats"][&"dex"]) and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_children] 실패: " + what)
	return cond
