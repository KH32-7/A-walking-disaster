extends Node
## C-02: resident data model, rescue -> resident, beds, Colony save/load round trip.
## Called by tests/run_tests.gd: run() -> bool. Restores Colony afterwards.

var _joined: Array[StringName] = []


func run() -> bool:
	var snapshot := JSON.stringify(Colony.save_data())
	EventBus.resident_joined.connect(_on_joined)
	var ok := true
	ok = _test_defs_loaded() and ok
	ok = _test_create_rolls_valid_resident() and ok
	ok = _test_profile_overrides() and ok
	ok = _test_rescue_and_beds() and ok
	ok = _test_save_round_trip() and ok
	EventBus.resident_joined.disconnect(_on_joined)
	Colony.load_data(JSON.parse_string(snapshot))
	return ok


func _on_joined(id: StringName) -> void:
	_joined.append(id)


func _test_defs_loaded() -> bool:
	var ok := true
	ok = _check(BaseDB.traits().size() == 16, "특성 16개 (07 탭 표)") and ok
	ok = _check(BaseDB.jobs().size() == 18, "직업 17개 (07 탭 표) + 전초기지 주둔 (C-19)") and ok
	var wood := BaseDB.get_job(&"woodcutting")
	ok = _check(wood != null and wood.base_output.get(&"wood") == 8.0 and wood.main_stat_key() == &"str", "벌목: 힘, 나무 8") and ok
	var diligent := BaseDB.get_trait(&"diligent")
	ok = _check(diligent != null and is_equal_approx(diligent.effect(&"work_efficiency"), 0.1), "부지런함 +10%") and ok
	ok = _check(not BaseDB.get_trait(&"monster_mark").randomizable, "마물 흔적은 무작위로 안 나옴") and ok
	for id: StringName in BaseDB.traits():
		for other in BaseDB.get_trait(id).exclusive_with:
			ok = _check(BaseDB.get_trait(other) != null, "배타 특성 id 존재: %s→%s" % [id, other]) and ok
	return ok


func _test_create_rolls_valid_resident() -> bool:
	var rng := RandomNumberGenerator.new()
	var ok := true
	for seed in 50:
		rng.seed = seed
		var r := ResidentData.create({"former_job": &"mechanic"}, rng)
		ok = _check(r["stats"][&"dex"] >= 5 and r["stats"][&"dex"] <= 7, "정비공 주 능력치(손재주) 5~7") and ok
		for key in [&"str", &"sense", &"heart"]:
			ok = _check(r["stats"][key] >= 2 and r["stats"][key] <= 5, "나머지 능력치 2~5") and ok
		ok = _check(r["traits"].size() == 2, "특성 2개") and ok
		ok = _check(not ResidentData.traits_conflict(r["traits"][0], r["traits"][1]), "배타 특성이 함께 안 나옴") and ok
		for t in r["traits"]:
			ok = _check(BaseDB.get_trait(t).randomizable, "이야기 특성은 굴리지 않음") and ok
		if not ok:
			return false
	return ok


func _test_profile_overrides() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var r := ResidentData.create(DemoProfiles.PROFILES[1], rng)  # stats: only dex given
	var ok := true
	ok = _check(r["stats"][&"dex"] == 7, "프로필 능력치가 우선") and ok
	ok = _check(r["stats"].size() == 4 and r["stats"][&"str"] >= 2, "빠진 능력치는 굴림") and ok
	ok = _check(r["access_needs"] == [Enums.AccessNeed.MOBILITY], "참여 조건 유지") and ok
	ok = _check(r["traits"] == [&"quick_hands", &"brave"], "프로필 특성 유지") and ok
	var child := ResidentData.create(DemoProfiles.PROFILES[2], rng)
	ok = _check(&"monster_mark" in child["traits"] and child["age_stage"] == Enums.AgeStage.CHILD, "데모 아이: 마물 흔적, 아이") and ok
	return ok


func _test_rescue_and_beds() -> bool:
	Colony.load_data({})
	_joined.clear()
	var ok := true
	ok = _check(Colony.bed_count() == Colony.START_BED_COUNT and Colony.population() == 0, "시작: 침상 6, 주민 0") and ok
	EventBus.rescue_completed.emit(DemoProfiles.PROFILES[0])
	ok = _check(_joined == [&"demo_carpenter"], "rescue_completed → resident_joined") and ok
	ok = _check(Colony.get_resident(&"demo_carpenter")["bed_id"] == &"main_hall_bed_1", "첫 침상 배정") and ok
	for i in Colony.START_BED_COUNT:
		Colony.add_resident({})
	ok = _check(Colony.population() == 7 and _joined.size() == 7, "주민 7명, 신호 7번") and ok
	var last := Colony.get_resident(_joined[-1])
	ok = _check(last["bed_id"] == &"" and Colony.free_beds().is_empty(), "7번째는 임시 거처") and ok
	ok = _check(Colony.add_resident(DemoProfiles.PROFILES[0]) != &"demo_carpenter", "같은 id면 새 id") and ok
	ok = _check(Colony.assign_bed(&"demo_carpenter", &"main_hall_bed_2") == false, "다른 사람 침상에는 못 감") and ok
	Colony.add_beds([&"family_house_1_bed_1"])
	ok = _check(Colony.assign_bed(last["id"], &"family_house_1_bed_1"), "새 침상에 배정") and ok
	Colony.release_bed(&"demo_carpenter")
	ok = _check(Colony.free_beds() == [&"main_hall_bed_1"], "침상 비우기") and ok
	if OS.is_debug_build():
		var out := DebugConsole.execute("resident add demo 3")
		ok = _check(out.begins_with("주민 추가") and Colony.population() == 9, "콘솔 resident add demo 3: " + out) and ok
	return ok


func _test_save_round_trip() -> bool:
	Colony.load_data({})
	for p in DemoProfiles.PROFILES:
		Colony.add_resident(p)
	Colony.add_resident({})
	Colony.threat = 4
	Colony.residents[&"demo_mechanic"]["relations"][&"demo_carpenter"] = 35
	Colony.residents[&"demo_mechanic"]["job_skill"][&"maintenance"] = 2
	var before := JSON.stringify(Colony.save_data(), "", true)
	Colony.load_data(JSON.parse_string(before))  # same path as a real save file
	var after := JSON.stringify(Colony.save_data(), "", true)
	var ok := _check(before == after, "저장 → JSON → 불러오기 → 저장 이 같음")
	var mech := Colony.get_resident(&"demo_mechanic")
	ok = _check(mech["relations"].get(&"demo_carpenter") == 35 and typeof(mech["stats"][&"dex"]) == TYPE_INT, "불러온 뒤 키·타입 복원") and ok
	var id: StringName = Colony.add_resident({})
	ok = _check(not id in [&"resident_001"], "불러온 뒤 id 번호가 이어짐") and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_residents] 실패: " + what)
	return cond
