extends Node
## C-04: building data + effects (beds, storage cap, power, noise), construction sites, save.
## Called by tests/run_tests.gd: run() -> bool. Restores Colony and Economy afterwards.

const DEMO := [&"bed", &"bonfire", &"lumber_yard", &"quarry", &"workshop", &"essence_workshop", &"ramp", &"palisade"]
## Workplaces of jobs that belong to defense/outposts (C-18, C-19), not to the 09 tab list.
const LATER_WORKPLACES := [&"guard_post", &"outpost"]

var _completed: Array[StringName] = []


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	EventBus.building_completed.connect(_on_completed)
	var ok := true
	ok = _test_defs() and ok
	ok = _test_start_state() and ok
	ok = _test_site_and_beds() and ok
	ok = _test_requirements() and ok
	ok = _test_storage() and ok
	ok = _test_power() and ok
	ok = _test_noise() and ok
	ok = _test_save_round_trip() and ok
	EventBus.building_completed.disconnect(_on_completed)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _on_completed(uid: StringName) -> void:
	_completed.append(uid)


func _fresh(resources: Dictionary = {}) -> void:
	Economy.load_data({})
	if not resources.is_empty():
		Economy.apply(resources)
	Colony.load_data({})
	_completed.clear()


func _test_defs() -> bool:
	var ok := _check(BaseDB.buildings().size() == 32, "건물 32종 (09 탭 31 + 목책)")
	for id in DEMO:
		ok = _check(BaseDB.get_building(id) != null, "데모 건물 %s" % id) and ok
	for job_id: StringName in BaseDB.jobs():
		var wp := BaseDB.get_job(job_id).workplace
		if wp != &"" and not wp in LATER_WORKPLACES:
			ok = _check(BaseDB.get_building(wp) != null, "직업 %s 작업장 %s 존재" % [job_id, wp]) and ok
	for id: StringName in BaseDB.buildings():
		var def := BaseDB.get_building(id)
		for req in def.requires:
			ok = _check(BaseDB.get_building(req) != null, "%s 조건 건물 %s 존재" % [id, req]) and ok
		for res: StringName in def.cost:
			if res != &"essence_low":  # A-10 정수 id 확정 전
				ok = _check(Economy.get_def(res) != null, "%s 비용 자원 %s 가 data/resources에 있음" % [id, res]) and ok
	var shop := BaseDB.get_building(&"workshop")
	ok = _check(shop.cost_for_level(2) == {&"plank": 20, &"scrap": 60, &"parts": 15}, "정비소 Lv2 = ×2 + 부품 5") and ok
	ok = _check(shop.cost_for_level(3) == {&"plank": 30, &"scrap": 90, &"parts": 15, &"rare_parts": 3}, "정비소 Lv3 = ×3 + 희귀 부품 3") and ok
	ok = _check(BaseDB.get_building(&"bed").build_work_needed() == 10, "작은 건물 진행도 10") and ok
	ok = _check(shop.build_work_needed() == 30, "중간 건물 진행도 30") and ok
	ok = _check(BaseDB.get_building(&"dining_hall").build_work_needed() == 60, "큰 건물 진행도 60") and ok
	return ok


func _test_start_state() -> bool:
	_fresh()
	var ok := _check(Colony.has_completed(&"radio_room"), "무전실은 처음부터 있음")
	ok = _check(Colony.population_cap() == 6, "시작 인구 상한 6") and ok
	ok = _check(Colony.demolish_building(&"radio_room").is_empty() and Colony.has_completed(&"radio_room"), "무전실은 철거 불가") and ok
	ok = _check(not Colony.can_build(&"radio_room")["ok"], "무전실은 새로 못 지음") and ok
	return ok


func _test_site_and_beds() -> bool:
	_fresh({&"wood": 100})
	var ok := true
	var uid := Colony.place_building(&"bed", Vector2i(3, 4), 1, &"playground")
	ok = _check(uid != &"" and Economy.get_amount(&"wood") == 90, "침상 건설 현장, 나무 10 지불") and ok
	ok = _check(Colony.population_cap() == 6 and _completed.is_empty(), "완성 전에는 효과 없음") and ok
	ok = _check(Colony.add_build_progress(uid, 6) == false, "진행도 6/10") and ok
	ok = _check(Colony.add_build_progress(uid, 6) == true and _completed == [uid], "진행도 10 넘으면 완성 + building_completed") and ok
	ok = _check(Colony.population_cap() == 7, "침상 완성 → 인구 상한 7") and ok
	for i in 7:
		Colony.add_resident({})
	ok = _check(Colony.free_beds().is_empty(), "7명 모두 침상") and ok
	var sleeper := StringName()
	for id in Colony.active_resident_ids():
		if String(Colony.get_resident(id)["bed_id"]).begins_with(String(uid)):
			sleeper = id
	ok = _check(sleeper != &"", "새 침상에 누군가 배정됨") and ok
	var refund := Colony.demolish_building(uid)
	ok = _check(refund == {&"wood": 5} and Economy.get_amount(&"wood") == 95, "철거 50% 반환") and ok
	ok = _check(Colony.get_resident(sleeper)["bed_id"] == &"" and Colony.population_cap() == 6, "철거하면 그 침상 주민은 임시 거처") and ok
	ok = _check(Colony.place_building(&"workshop") == &"", "자원이 없으면 못 지음") and ok
	return ok


func _test_requirements() -> bool:
	_fresh({&"wood": 120, &"stone": 40})  # stays under the base storage cap (200)
	var check := Colony.can_build(&"dormitory")
	var ok := _check(not check["ok"] and check["reasons"].size() == 1, "숙소는 목공소 필요: %s" % [check["reasons"]])
	Colony.complete_building(Colony.place_building(&"carpentry_shop"))
	ok = _check(Colony.can_build(&"dormitory")["ok"], "목공소 뒤에는 숙소 가능") and ok
	ok = _check(not Colony.can_build(&"family_house")["ok"], "가족 숙소는 정착지") and ok
	ok = _check(not Colony.can_build(&"essence_workshop")["ok"], "정수 공방은 설계도 필요") and ok
	ok = _check(not Colony.can_build(&"generator")["ok"], "발전기는 전기기사 필요") and ok
	return ok


func _test_storage() -> bool:
	_fresh({&"wood": 100})
	var base_cap := Economy.storage_cap()
	var uid := Colony.place_building(&"warehouse")
	Colony.complete_building(uid)
	var ok := _check(Economy.storage_cap() == base_cap + 300, "창고 → 보관 +300")
	Colony.buildings[uid]["level"] = 2
	Colony._refresh_effects()
	ok = _check(Economy.storage_cap() == base_cap + 450, "창고 Lv2 → +450 (효과 +50%)") and ok
	Colony.demolish_building(uid)
	ok = _check(Economy.storage_cap() == base_cap, "철거하면 보너스 사라짐") and ok
	return ok


func _test_power() -> bool:
	_fresh()
	var lift := _build(&"elevator")
	var light := _build(&"warning_light")
	var ok := _check(Colony.power_demand() == 2 and not Colony.is_powered(lift) and not Colony.is_powered(light), "발전 없음 → 꺼짐")
	_build(&"solar_panel")
	ok = _check(is_equal_approx(Colony.power_supply(), 3.0) and Colony.is_powered(lift) and Colony.is_powered(light), "태양광 3 → 둘 다 켜짐") and ok
	var lift2 := _build(&"elevator")
	var light2 := _build(&"warning_light")
	var off := 0
	for uid in [lift, light, lift2, light2]:
		if not Colony.is_powered(uid):
			off += 1
	ok = _check(Colony.power_demand() == 4 and off == 1, "수요 4 > 공급 3 → 1개 꺼짐") and ok
	Colony.set_power_priority(lift, 9)
	ok = _check(not Colony.is_powered(lift), "우선순위를 낮추면 그것부터 꺼짐") and ok
	ok = _check(Colony.is_powered(_build(&"bonfire")), "전력을 안 쓰는 건물은 항상 켜짐") and ok
	return ok


func _test_noise() -> bool:
	_fresh()
	_build(&"generator")
	_build(&"salvage_yard")
	for i in 10:
		Colony.add_resident({})
	return _check(is_equal_approx(Colony.base_noise(), 5.0 + 3.0 + 10 * 0.3), "소음도 = 발전기 5 + 해체장 3 + 인구 10 × 0.3")


func _test_save_round_trip() -> bool:
	_fresh({&"wood": 100})
	_build(&"bed")
	_build(&"warehouse")
	_build(&"solar_panel")
	Colony.set_power_priority(_build(&"elevator"), 2)
	var site := Colony.place_building(&"bonfire", Vector2i(5, 6), 3, &"playground")
	Colony.add_build_progress(site, 4)
	Colony.add_resident({})
	var before := JSON.stringify(Colony.save_data(), "", true)
	Colony.load_data(JSON.parse_string(before))
	var after := JSON.stringify(Colony.save_data(), "", true)
	var ok := _check(before == after, "건물 포함 저장 → JSON → 불러오기 왕복")
	var b := Colony.get_building(site)
	ok = _check(b["cell"] == [5, 6] and b["rotation"] == 3 and b["progress"] == 4 and not b["completed"], "건설 현장 상태 복원") and ok
	ok = _check(Colony.population_cap() == 7 and Economy.storage_cap() == Economy.BASE_STORAGE_CAP + 300, "불러온 뒤 효과 다시 계산") and ok
	return ok


func _build(def_id: StringName) -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, &"", false)
	Colony.complete_building(uid)
	return uid


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_buildings] 실패: " + what)
	return cond
