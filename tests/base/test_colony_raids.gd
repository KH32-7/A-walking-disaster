extends Node
## C-08: raid threat, occurrence, strength, automatic judgment, prediction.
## Called by tests/run_tests.gd: run() -> bool. Restores Colony, Economy and GameState afterwards.

var _warnings: Array = []
var _resolved: Array = []
var _damaged: Array = []


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	EventBus.raid_warning.connect(_on_warning)
	EventBus.raid_resolved.connect(_on_resolved)
	EventBus.building_damaged.connect(_on_damaged)
	var ok := true
	ok = _test_rules() and ok
	ok = _test_threat() and ok
	ok = _test_roll() and ok
	ok = _test_judgment_win() and ok
	ok = _test_judgment_loss() and ok
	ok = _test_prediction() and ok
	ok = _test_save() and ok
	EventBus.raid_warning.disconnect(_on_warning)
	EventBus.raid_resolved.disconnect(_on_resolved)
	EventBus.building_damaged.disconnect(_on_damaged)
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _on_warning(info: Dictionary) -> void:
	_warnings.append(info)


func _on_resolved(result: Dictionary) -> void:
	_resolved.append(result)


func _on_damaged(uid: StringName) -> void:
	_damaged.append(uid)


func _fresh(day: int = 10, resources: Dictionary = {}) -> void:
	GameState.load_data({"day": day})
	Economy.load_data({})
	if not resources.is_empty():
		Economy.apply(resources)
	Colony.load_data({})
	Colony._rng.seed = 12345
	_warnings.clear()
	_resolved.clear()
	_damaged.clear()


func _build(def_id: StringName) -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, &"", false)
	Colony.complete_building(uid)
	return uid


func _guard(sense: int) -> StringName:
	var id := Colony.add_resident({"stats": {&"sense": sense}, "traits": []})
	Colony.assign_job(id, &"guard")
	return id


func _test_rules() -> bool:
	var ok := _check(is_equal_approx(RaidRules.strength(10, 4, Enums.BaseTier.CAMP, 1.0), 33.0), "I = 10 + 1.5×10 + 2×4 = 33")
	ok = _check(is_equal_approx(RaidRules.strength(10, 4, Enums.BaseTier.SETTLEMENT, 1.2), 63.6), "정착지 +20, r 1.2") and ok
	ok = _check(RaidRules.raid_chance(Enums.RaidTime.NIGHT, 100)["chance"] == 1.0, "위협도 100 → 확정") and ok
	ok = _check(RaidRules.raid_chance(Enums.RaidTime.NIGHT, 85)["chance"] == 0.5, "80~99 → 50%") and ok
	ok = _check(RaidRules.raid_chance(Enums.RaidTime.NIGHT, 60)["chance"] == 0.3, "60~79 → 30%") and ok
	var low := RaidRules.raid_chance(Enums.RaidTime.NIGHT, 30)
	ok = _check(low["chance"] == 0.05 and low["small"], "60 미만 → 5% 소규모") and ok
	ok = _check(RaidRules.raid_chance(Enums.RaidTime.DAY, 69)["chance"] == 0.0 and RaidRules.raid_chance(Enums.RaidTime.DAY, 70)["chance"] == 0.2, "낮: 70 이상 20%") and ok
	ok = _check(RaidRules.outcome_for(1.5) == Enums.RaidOutcome.FLAWLESS and RaidRules.outcome_for(1.0) == Enums.RaidOutcome.WIN \
		and RaidRules.outcome_for(0.7) == Enums.RaidOutcome.NARROW and RaidRules.outcome_for(0.69) == Enums.RaidOutcome.LOSS, "R 구간") and ok
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var siege := false
	for i in 300:
		if RaidRules.pick_type(Enums.BaseTier.CAMP, rng) == &"siege":
			siege = true
		var dirs := RaidRules.pick_directions(&"wave", rng)
		if dirs.size() < 2 or dirs.size() > 3 or dirs[0] == dirs[-1]:
			ok = _check(false, "파도 습격은 서로 다른 2~3 방향") and ok
			break
	ok = _check(not siege, "캠프 단계에서는 공성 습격 없음") and ok
	var r := {"stats": {&"sense": 6}, "class_aptitude": {&"gun": Enums.Aptitude.HIGH}, "traits": []}
	ok = _check(is_equal_approx(RaidRules.guard_power(r, {}, 0.0), 1.0), "무기 없음: 감각 6 × 0.5 ÷ 3 = 1") and ok
	ok = _check(is_equal_approx(RaidRules.guard_power(r, {"damage": 20.0, "combat_class": Enums.CombatClass.GUN}, 30.0), 20 * 1.15 / 10 + 3 + 3), "총 20 × 적성 상 ÷ 10 + 방어 30 ÷ 10 + 감각 3") and ok
	r["traits"] = [&"brave"]
	ok = _check(is_equal_approx(RaidRules.guard_power(r, {}, 0.0), 1.1), "용감함 경비 +10%") and ok
	return ok


func _test_threat() -> bool:
	_fresh(1)
	var ok := _check(is_equal_approx(Colony.threat_delta(), 3.0), "아무것도 없으면 하루 +3")
	_build(&"generator")
	for i in 10:
		Colony.add_resident({})
	ok = _check(is_equal_approx(Colony.threat_delta(), 3.0 + 5.0 + 3.0), "+ 소음도(발전기 5 + 인구 10 × 0.3)") and ok
	GameState.load_data({"day": 20})  # summer
	ok = _check(is_equal_approx(Colony.threat_delta(), 12.0), "여름 +1") and ok
	Colony.threat = 95
	var report := Colony.settle_day()
	ok = _check(Colony.threat == 100 and report["threat"] == {"before": 95, "after": 100}, "정산 때 위협도 반영, 100 상한") and ok
	return ok


func _test_roll() -> bool:
	_fresh(4)
	Colony.threat = 100
	var ok := _check(not Colony.roll_raid(Enums.RaidTime.NIGHT)["occurs"], "5일차 전에는 습격 없음")
	GameState.load_data({"day": 5})
	var raid := Colony.roll_raid(Enums.RaidTime.NIGHT)
	ok = _check(raid["occurs"] and _warnings.size() == 1 and _warnings[0]["raid_id"] == raid["raid_id"], "위협도 100 → 습격 + raid_warning") and ok
	for key in ["raid_id", "time", "type", "directions", "strength", "target", "warning_sec"]:
		ok = _check(raid.has(key), "계약 키 %s" % key) and ok
	ok = _check(raid["target"] == &"base" and raid["strength"] > 0.0 and raid["notice"] == &"none", "초소가 없으면 예고 없음") and ok
	ok = _check(not Colony.roll_raid(Enums.RaidTime.NIGHT)["occurs"], "하루 최대 1번") and ok
	GameState.load_data({"day": 6})
	_build(&"guard_post")
	Colony.threat = 75
	var day_raid := {}
	for i in 50:
		Colony.last_raid_day = 0
		day_raid = Colony.roll_raid(Enums.RaidTime.DAY)
		if day_raid["occurs"]:
			break
	ok = _check(day_raid["occurs"] and day_raid["warning_sec"] == 60.0, "낮 습격 + 경비 초소 → 60초 전 무전") and ok
	Colony.last_raid_day = 0
	Colony.threat = 100
	ok = _check(Colony.roll_raid(Enums.RaidTime.NIGHT)["notice"] == &"morning", "밤 습격 + 경비 초소 → 그날 아침 징후") and ok
	return ok


func _test_judgment_win() -> bool:
	_fresh(10)
	_build(&"guard_post")
	for i in 5:
		_build(&"palisade")
	_guard(8)
	_guard(6)
	var d := Colony.defense_breakdown()
	var ok := _check(d["guards"].size() == 2 and is_equal_approx(d["total"], 5.0 + 5 * 0.5 + 8 * 0.5 / 3.0 + 6 * 0.5 / 3.0), "방어 = 초소 5 + 목책 5×0.5 + 맨손 경비 2명 (%.2f)" % d["total"])
	var raid := {"raid_id": &"t1", "time": Enums.RaidTime.NIGHT, "strength": d["total"] / 2.0, "directions": [&"west"], "family": Enums.Element.GREEN}
	var result := Colony.resolve_raid(raid, Enums.RaidMode.AUTO)
	ok = _check(result["outcome"] == Enums.RaidOutcome.FLAWLESS and result["loot"].get(&"vine_fiber", 0) > 0, "R 2 → 완승, 수풀 계열 재료") and ok
	ok = _check(Economy.get_amount(&"vine_fiber") == result["loot"][&"vine_fiber"] and Colony.threat == 20, "전리품 창고에, 위협도 20") and ok
	ok = _check(_resolved.size() == 1 and result["summary"].size() >= 2 and result["summary"].size() <= 5, "raid_resolved + 요약 줄") and ok
	raid["strength"] = d["total"] / 1.2
	result = Colony.resolve_raid(raid, Enums.RaidMode.AUTO)
	ok = _check(result["outcome"] == Enums.RaidOutcome.WIN and not result["damage"]["durability_loss"].is_empty(), "R 1.2 → 승리, 내구도 감소") and ok
	var now: float = Colony.defense_breakdown()["total"]  # the WIN above wore walls down
	raid["strength"] = now / 0.9
	ok = _check(Colony.resolve_raid(raid, Enums.RaidMode.PLAYED)["outcome"] == Enums.RaidOutcome.WIN, "직접 방어에서 자동 넘기기 +20% → 0.9 × 1.2 = 1.08 승리") and ok
	return ok




func _test_judgment_loss() -> bool:
	_fresh(10, {&"wood": 100, &"stone": 50, &"parts": 10})
	var yard := _build(&"lumber_yard")
	_build(&"quarry")
	_build(&"workshop")
	_build(&"bed")
	for i in 4:
		Colony.add_resident({})
	var ids := Colony.active_resident_ids()
	Colony.assign_job(ids[0], &"woodcutting")
	Colony.residents[ids[0]]["morale"] = 50
	var raid := {"raid_id": &"t2", "time": Enums.RaidTime.NIGHT, "strength": 500.0, "directions": [&"north", &"east"]}
	var result := Colony.resolve_raid(raid, Enums.RaidMode.AUTO)
	var ok := _check(result["outcome"] == Enums.RaidOutcome.LOSS, "방어 0 → 패배")
	var damaged: Array = result["damage"]["damaged"]
	ok = _check(damaged.size() >= 2 and damaged.size() <= 3 and _damaged == damaged, "시설 2~4개 파손(파손 가능 3개) + building_damaged") and ok
	for uid in damaged:
		ok = _check(not Colony.get_building(uid)["def_id"] in [&"bed", &"radio_room"], "침상·방송실은 안 부서짐") and ok
	ok = _check(Economy.get_amount(&"wood") == 80 and Economy.get_amount(&"stone") == 40, "창고 자원 −20%") and ok
	ok = _check(Economy.get_amount(&"parts") == 10, "희귀 자원(부품)은 그대로") and ok
	ok = _check(Colony.threat == 30 and Colony.get_resident(ids[1])["morale"] == 40, "위협도 30, 사기 −10") and ok
	if yard in damaged:
		var report := Colony.settle_day()
		ok = _check(not report["work"].has(ids[0]), "파손된 벌목장은 일하지 않음") and ok
	return ok


func _test_prediction() -> bool:
	_fresh(10)
	_build(&"guard_post")
	_guard(6)
	var strength: float = Colony.defense_breakdown()["total"]
	var p := Colony.predict_raid({"strength": strength})
	var ok := _check(is_equal_approx(p["ratio_min"], 0.85) and is_equal_approx(p["ratio_max"], 1.15) and p["likely"] == Enums.RaidOutcome.WIN, "예상: R 1 → 0.85~1.15, 승리")
	ok = _check(Colony.predict_raid({})["ratio_max"] > 0.0, "강도 없이도 오늘 기준으로 예상") and ok
	return ok


func _test_save() -> bool:
	_fresh(10, {&"wood": 50})
	_build(&"lumber_yard")
	_build(&"workshop")
	Colony.threat = 100
	Colony.roll_raid(Enums.RaidTime.NIGHT)
	Colony.resolve_raid({"raid_id": &"t3", "strength": 999.0}, Enums.RaidMode.AUTO)
	var before := JSON.stringify(Colony.save_data(), "", true)
	Colony.load_data(JSON.parse_string(before))
	var ok := _check(JSON.stringify(Colony.save_data(), "", true) == before, "습격 뒤 저장 왕복 (파손·마지막 습격 날)")
	ok = _check(Colony.last_raid_day == 10 and not Colony.roll_raid(Enums.RaidTime.NIGHT)["occurs"], "불러와도 오늘은 다시 습격 없음") and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_raids] 실패: " + what)
	return cond
