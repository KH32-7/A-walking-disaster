extends Node
## C-13: 입주 의식 flow data — a rescued survivor waits for the ceremony, nickname, appearance preset,
## bed choice, first talk (story's first piece + one like), save. Called by tests/run_tests.gd.

var _ready_ids: Array[StringName] = []
var _done: Array = []


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	Colony.arrival_ready.connect(_on_ready)
	Colony.arrival_completed.connect(_on_done)
	var ok := true
	ok = _test_rescue() and ok
	ok = _test_nickname() and ok
	ok = _test_appearance() and ok
	ok = _test_bed() and ok
	ok = _test_first_talk() and ok
	Colony.arrival_ready.disconnect(_on_ready)
	Colony.arrival_completed.disconnect(_on_done)
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _on_ready(id: StringName) -> void:
	_ready_ids.append(id)


func _on_done(id: StringName, result: Dictionary) -> void:
	_done.append([id, result])


func _fresh() -> StringName:
	GameState.load_data({"day": 4})
	Economy.load_data({})
	Colony.load_data({})
	_ready_ids.clear()
	_done.clear()
	Colony._on_rescue_completed({"id": &"survivor_test", "name": "윤서", "traits": [], "likes": [&"tea", &"woodwork"],
		"first_line": "여기는 따뜻하네요.", "story": {"background": "버스 기사였다.", "fragments": ["첫 조각"], "requests": []}})
	return &"survivor_test"


func _test_rescue() -> bool:
	var id := _fresh()
	var ok := _check(Colony.pending_arrivals() == [id] and _ready_ids == [id], "구조된 생존자는 입주 의식 대기 + arrival_ready")
	var info := Colony.arrival_info(id)
	ok = _check(info["steps"] == ArrivalRules.STEPS and info["nickname_max"] == 6 and info["beds"].size() == 5,
		"의식 정보: 단계 5개, 별명 6자, 나머지 빈 침상 5개 (%d)" % info["beds"].size()) and ok
	ok = _check(info["beds"][0]["building_name"] == "방송실 야영지" and info["appearance"].has("preset"), "야영지 침낭 이름, 기본 외형 프리셋") and ok
	var home := Colony.add_resident({"traits": []})
	Colony.residents[home]["status"] = Enums.ResidentStatus.STRANDED
	Colony._on_rescue_completed(Colony.get_resident(home))
	ok = _check(not home in Colony.pending_arrivals(), "고립에서 돌아온 주민은 의식 없음") and ok
	ok = _check(not Colony.add_resident({"traits": []}) in Colony.pending_arrivals(), "디버그·시작 주민은 의식 없음") and ok
	return ok


func _test_nickname() -> bool:
	var id := _fresh()
	var ok := _check(Colony.set_nickname(id, "  콩이 ")["ok"] and Colony.get_resident(id)["nickname"] == "콩이", "별명 앞뒤 공백 정리")
	ok = _check(not Colony.set_nickname(id, "가나다라마바사")["ok"] and Colony.get_resident(id)["nickname"] == "콩이", "7자는 거절, 별명은 그대로") and ok
	ok = _check(Colony.set_nickname(id, "가나다라마바")["ok"], "6자까지 됨") and ok
	var banned := ResidentTemplate.load_banned_words()
	if not banned.is_empty() and banned[0].length() <= 6:
		ok = _check(not Colony.set_nickname(id, banned[0])["ok"], "금지어 거절") and ok
	ok = _check(Colony.set_nickname(id, "")["ok"] and Colony.get_resident(id)["nickname"] == "", "별명 없음도 됨") and ok
	return ok


func _test_appearance() -> bool:
	var id := _fresh()
	var res := Colony.set_appearance(id, {"preset": &"worker_short", "hair": "bob", "hair_color": Color(1, 0, 0), "outfit_color": "#335577"})
	var ok := _check(res["ok"], "외형 프리셋·머리·색 선택: %s" % res["reason"])
	var stored: Dictionary = Colony.get_resident(id)["appearance"]
	ok = _check(stored["hair_color"] == "#ff0000" and stored["outfit_color"] == "#335577", "색은 #rrggbb 문자열로 저장: %s" % stored) and ok
	var look := Colony.appearance_for_look(id)
	ok = _check(look["hair_color"] is Color and look["preset"] == &"worker_short", "CharacterLook용은 Color") and ok
	ok = _check(not Colony.set_appearance(id, {"preset": &"no_such_preset"})["ok"], "없는 프리셋 거절") and ok
	ok = _check(not Colony.set_appearance(id, {"hair": "mohawk"})["ok"], "없는 머리 모양 거절") and ok
	ok = _check(not Colony.set_appearance(id, {"skin": "not a colour"})["ok"], "잘못된 색 거절") and ok
	ok = _check(Colony.set_appearance(id, {"hair": "long"})["ok"] and Colony.get_resident(id)["appearance"]["preset"] == &"worker_short",
		"일부만 바꾸면 나머지는 그대로") and ok
	Colony.load_data(JSON.parse_string(JSON.stringify(Colony.save_data())))
	look = Colony.appearance_for_look(id)
	ok = _check(look["hair"] == "long" and look["hair_color"] == Color(1, 0, 0) and Colony.pending_arrivals() == [id],
		"저장 후에도 외형·대기 상태 유지") and ok
	return ok


func _test_bed() -> bool:
	var id := _fresh()
	var taken: StringName = Colony.get_resident(id)["bed_id"]
	var other := Colony.add_resident({"traits": []})
	var free: StringName = Colony.free_beds()[0]
	var ok := _check(Colony.choose_bed(id, free) and Colony.get_resident(id)["bed_id"] == free and Colony.beds[taken] == &"", "빈 침상으로 바꿈")
	ok = _check(not Colony.choose_bed(id, Colony.get_resident(other)["bed_id"]), "남의 침상은 안 됨") and ok
	ok = _check(Colony.choose_bed(id, &"") and Colony.get_resident(id)["bed_id"] == &"", "임시 거처도 고를 수 있음") and ok
	return ok


func _test_first_talk() -> bool:
	var id := _fresh()
	var res := Colony.complete_arrival(id)
	var ok := _check(res["ok"] and res["background"] == "버스 기사였다." and res["first_line"] == "여기는 따뜻하네요." and res["like"] == &"tea",
		"첫 대화: 첫마디, 사연 첫 조각, 좋아하는 것 하나: %s" % res)
	ok = _check(Colony.known_likes(id) == [&"tea"] and Colony.pending_arrivals().is_empty(), "알게 된 취향 1개, 의식 끝") and ok
	ok = _check(Colony.get_resident(id)["trust"] == ResidentData.START_TRUST + TrustRules.TALK and not Colony.trust_actions(id)["talk"],
		"첫 대화가 그날 대화 (+3)") and ok
	ok = _check(_done.size() == 1 and _done[0][0] == id and not Colony.complete_arrival(id)["ok"], "arrival_completed 한 번") and ok
	Economy.apply({&"plank": 1})
	Colony.give_gift(id, &"plank")
	ok = _check(Colony.known_likes(id) == [&"tea", &"woodwork"], "좋아하는 선물로 취향을 알게 됨") and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_arrival] 실패: " + what)
	return cond
