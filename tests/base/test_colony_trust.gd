extends Node
## C-12: trust stages, daily talk, gifts, stay-day deep talk, sortie return and rescue from strand,
## and the add_trust() that A-13 calls. Called by tests/run_tests.gd. Restores what it changes.

var _changes: Array = []


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	var stayed := SceneRouter.stayed_today
	Colony.trust_changed.connect(_on_trust_changed)
	var ok := true
	ok = _test_stages() and ok
	ok = _test_talk() and ok
	ok = _test_gifts() and ok
	ok = _test_deep_talk() and ok
	ok = _test_sortie_and_rescue() and ok
	ok = _test_save() and ok
	Colony.trust_changed.disconnect(_on_trust_changed)
	SceneRouter.stayed_today = stayed
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _on_trust_changed(id: StringName, trust: int, stage: int, reason: StringName) -> void:
	_changes.append([id, trust, stage, reason])


func _fresh(resources: Dictionary = {}) -> StringName:
	GameState.load_data({"day": 3})
	Economy.load_data({})
	if not resources.is_empty():
		Economy.apply(resources)
	Colony.load_data({})
	SceneRouter.stayed_today = false
	_changes.clear()
	return Colony.add_resident({"traits": [], "likes": [&"woodwork", &"tea"], "dislikes": [&"canned_fish"],
		"story": {"background": "목수", "fragments": ["첫 조각", "둘째 조각"], "requests": []}})


func _test_stages() -> bool:
	var ok := _check(TrustRules.stage_of(0) == 0 and TrustRules.stage_of(19) == 0 and TrustRules.stage_of(20) == 1
		and TrustRules.stage_of(59) == 2 and TrustRules.stage_of(80) == 4 and TrustRules.stage_of(100) == 4, "단계 경계 0·20·40·60·80")
	var id := _fresh()
	ok = _check(Colony.unlocked_story(id).is_empty(), "낯섬: 사연 없음") and ok
	ok = _check(Colony.add_trust(id, 20) == 20 and Colony.trust_stage(id) == 1, "+20 → 경계 풀림") and ok
	ok = _check(Colony.unlocked_story(id) == ["첫 조각"], "경계 풀림: 사연 1") and ok
	Colony.add_trust(id, 40, &"quest")
	ok = _check(Colony.unlocked_story(id) == ["첫 조각", "둘째 조각"], "가까움: 사연 2") and ok
	ok = _check(Colony.add_trust(id, 500) == 100 and Colony.add_trust(id, -500) == 0, "0~100으로 묶임") and ok
	ok = _check(Colony.add_trust(&"nobody", 5) == -1, "없는 주민은 -1") and ok
	ok = _check(_changes.size() == 4 and _changes[1] == [id, 60, 3, &"quest"], "trust_changed(id, trust, stage, reason): %s" % [_changes]) and ok
	return ok


func _test_talk() -> bool:
	var id := _fresh()
	var first := Colony.talk(id)
	var ok := _check(first["ok"] and first["trust"] == TrustRules.TALK, "대화 +3")
	ok = _check(not Colony.talk(id)["ok"] and Colony.get_resident(id)["trust"] == TrustRules.TALK, "대화는 하루 1번") and ok
	GameState.load_data({"day": 4})
	ok = _check(Colony.talk(id)["ok"] and Colony.get_resident(id)["trust"] == TrustRules.TALK * 2, "다음 날 다시 대화") and ok
	Colony.residents[id]["status"] = Enums.ResidentStatus.STRANDED
	ok = _check(not Colony.trust_actions(id)["talk"], "고립된 주민과는 대화 불가") and ok
	return ok


func _test_gifts() -> bool:
	var id := _fresh({&"plank": 2, &"food": 1, &"stone": 1})
	var liked := Colony.give_gift(id, &"plank")
	var ok := _check(liked["ok"] and liked["reaction"] == &"liked" and liked["trust"] == 8, "좋아하는 것(목공 → 판자) +8: %s" % liked)
	ok = _check(Economy.get_amount(&"plank") == 1, "선물은 1개 씀") and ok
	ok = _check(not Colony.give_gift(id, &"plank")["ok"], "선물은 하루 1번") and ok
	GameState.load_data({"day": 4})
	ok = _check(Colony.give_gift(id, &"stone")["trust"] == 11, "보통 +3") and ok
	GameState.load_data({"day": 5})
	var bad := Colony.give_gift(id, &"food")
	ok = _check(bad["reaction"] == &"disliked" and bad["trust"] == 6, "싫어하는 것(통조림 생선 → 식량) −5") and ok
	GameState.load_data({"day": 6})
	ok = _check(not Colony.give_gift(id, &"food")["ok"] and Colony.trust_actions(id)["gift"], "없는 자원은 못 주고, 기회는 남음") and ok
	return ok


func _test_deep_talk() -> bool:
	var id := _fresh()
	var other := Colony.add_resident({"traits": []})
	var ok := _check(not Colony.deep_talk(id)["ok"], "출격하는 날은 깊은 대화 없음")
	SceneRouter.stayed_today = true
	var deep := Colony.deep_talk(id)
	ok = _check(deep["ok"] and deep["trust"] == TrustRules.DEEP_TALK, "머무르기 날 깊은 대화") and ok
	ok = _check(not Colony.trust_actions(id)["talk"], "깊은 대화는 그날 대화를 씀") and ok
	ok = _check(not Colony.deep_talk(other)["ok"] and Colony.talk(other)["ok"], "깊은 대화는 하루에 주민 1명, 다른 주민과 대화는 됨") and ok
	return ok


func _test_sortie_and_rescue() -> bool:
	var a := _fresh()
	var b := Colony.add_resident({"traits": []})
	Colony._on_sortie_ended({"extracted": true, "companions": [a, b], "stranded": [b]})
	var ok := _check(Colony.get_resident(a)["trust"] == TrustRules.SORTIE_RETURN and Colony.get_resident(b)["trust"] == 0,
		"살아 돌아온 동행만 +5, 고립된 동행은 없음")
	Colony.residents[b]["status"] = Enums.ResidentStatus.STRANDED
	Colony._on_rescue_completed(Colony.get_resident(b))
	ok = _check(Colony.get_resident(b)["status"] == Enums.ResidentStatus.ACTIVE
		and Colony.get_resident(b)["trust"] == TrustRules.RESCUED_FROM_STRAND, "고립에서 구출 +15") and ok
	return ok


func _test_save() -> bool:
	var id := _fresh()
	SceneRouter.stayed_today = true
	Colony.deep_talk(id)
	Colony.give_gift(id, &"stone")  # fails: no stone, keeps the gift chance
	Colony.load_data(JSON.parse_string(JSON.stringify(Colony.save_data())))
	var ok := _check(not Colony.trust_actions(id)["talk"] and not Colony.trust_actions(id)["deep_talk"]
		and Colony.trust_actions(id)["gift"], "저장 후에도 오늘 한 대화·깊은 대화가 남음")
	return _check(Colony.get_resident(id)["trust"] == TrustRules.DEEP_TALK, "신뢰도 저장") and ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_trust] 실패: " + what)
	return cond
