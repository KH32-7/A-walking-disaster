extends Node
## Issue #45 (A-09 / A-05 hooks): facility getters, worker crafting in settle_day, stay day bonus,
## stay day raid through SceneRouter. Called by tests/run_tests.gd. Restores every touched autoload.


## Raids and the played defence are switched off in the game for now (RaidRules.RAIDS /
## DIRECT_DEFENSE); these rules are still tested with them on.
func run() -> bool:
	var was := [RaidRules.RAIDS, RaidRules.DIRECT_DEFENSE]
	RaidRules.RAIDS = true
	RaidRules.DIRECT_DEFENSE = true
	var ok: bool = await _run_switched_on()
	RaidRules.RAIDS = was[0]
	RaidRules.DIRECT_DEFENSE = was[1]
	return ok


func _run_switched_on() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	var router_snapshot := SceneRouter.save_data().duplicate(true)
	var flow_before := GameState.flow_state
	var stayed_before := SceneRouter.stayed_today
	var ok := true
	ok = _test_facility_getters() and ok
	ok = _test_worker_crafting() and ok
	ok = _test_stay_bonus() and ok
	ok = await _test_stay_day_raid() and ok
	SceneRouter.stayed_today = stayed_before
	SceneRouter.load_data(router_snapshot)
	GameState.load_data(game_snapshot)
	GameState.flow_state = flow_before
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _fresh(resources: Dictionary = {}) -> void:
	SceneRouter.stayed_today = false
	Economy.load_data({})
	if not resources.is_empty():
		Economy.apply(resources)
	Colony.load_data({})
	Colony._rng.seed = 7


func _build(def_id: StringName) -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, &"", false)
	Colony.complete_building(uid)
	return uid


func _person(stats: Dictionary) -> StringName:
	return Colony.add_resident({"stats": stats, "traits": [], "former_job": &"laborer"})


func _test_facility_getters() -> bool:
	_fresh()
	var ok := _check(Colony.facility_level(&"workshop") == 0 and Colony.facility_workers(&"workshop").is_empty(), "정비소 없음 → 0, []")
	var a := _build(&"workshop")
	var b := _build(&"workshop")
	Colony.buildings[b]["level"] = 2
	var m := _person({&"dex": 7})
	Colony.assign_job(m, &"maintenance", a)
	ok = _check(Colony.facility_level(&"workshop") == 2, "완성된 정비소 중 최고 레벨 2") and ok
	ok = _check(Colony.facility_workers(&"workshop") == [m], "정비소 담당 주민") and ok
	Colony.buildings[b]["damaged"] = true
	ok = _check(Colony.facility_level(&"workshop") == 1, "파손된 시설은 레벨에서 뺌") and ok
	var ctx := Armory.facility_context(&"workshop")
	ok = _check(int(ctx.get("dex", 0)) == 7, "Armory.facility_context가 담당 주민 손재주를 읽음") and ok
	return ok


func _test_worker_crafting() -> bool:
	_fresh({&"scrap": 40, &"parts": 6, &"cloth": 4, &"herbs": 4})
	_build(&"workshop")
	_build(&"infirmary")
	var mech := _person({&"dex": 5})
	var medic := _person({&"heart": 5})
	Colony.assign_job(mech, &"maintenance")
	Colony.assign_job(medic, &"medical")
	var report := Colony.settle_day()
	var p: Dictionary = report["produced"]
	var made_workshop := int(p.get(&"ammo_pistol", 0) > 0) + int(p.get(&"ammo_rifle", 0) > 0) \
		+ int(p.get(&"ammo_shell", 0) > 0) + int(p.get(&"noise_lure", 0) > 0)
	var ok := _check(made_workshop == 3, "정비공 효율 1.5 → 3회, 재고가 적은 것부터 서로 다른 3종: %s" % p)
	ok = _check(p.get(&"bandage", 0) > 0 or p.get(&"first_aid_kit", 0) > 0, "의무실 작업자가 붕대·구급상자 제작: %s" % p) and ok
	ok = _check(report["consumed"].get(&"scrap", 0) > 0 and not report["work"][mech]["output"].is_empty(), "고철 소비, 주민별 산출 기록") and ok
	ok = _check(Economy.apply_detailed(report["changes"])["ok"], "A-05처럼 Economy에 반영 가능") and ok

	_fresh({&"scrap": 2})
	_build(&"workshop")
	var poor := _person({&"dex": 5})
	Colony.assign_job(poor, &"maintenance")
	report = Colony.settle_day()
	ok = _check(report["produced"].is_empty() and report["consumed"].get(&"scrap", 0) == 0, "재료가 없으면 만들지 않음: %s / %s" % [report["produced"], report["consumed"]]) and ok
	return ok


func _test_stay_bonus() -> bool:
	_fresh({&"food": 20})
	_build(&"lumber_yard")
	var w := _person({&"str": 5})
	Colony.assign_job(w, &"woodcutting")
	var site := Colony.place_building(&"workshop", Vector2i.ZERO, 0, &"", false)
	var normal: int = Colony.settle_day()["produced"].get(&"wood", 0)
	SceneRouter.stayed_today = true
	var stay: int = Colony.settle_day()["produced"].get(&"wood", 0)
	var ok := _check(normal == 12 and stay == roundi(12 * 1.2), "머무르기 날 생산 +20%% (%d → %d)" % [normal, stay])
	ok = _check(Colony.get_building(site)["progress"] == 20, "머무르기 날 가장 오래된 건설 현장 +20") and ok
	return ok


func _test_stay_day_raid() -> bool:
	_fresh({&"food": 50})
	GameState.load_data({"day": 10})
	Colony.threat = 100
	_build(&"guard_post")
	var ok := true
	var came := false
	for i in 60:
		GameState.flow_state = Enums.FlowState.BASE_STAY  # as if SceneRouter.stay_at_base() ran
		Colony.last_raid_day = 0
		Colony._roll_stay_day_raid()
		if GameState.flow_state != Enums.FlowState.BASE_STAY:
			came = true
			break
	ok = _check(came, "위협도 100, 머무르기 → 낮 습격(20%)이 결국 옴") and ok
	ok = _check(GameState.flow_state == Enums.FlowState.EVENING, "start_day_raid → 판정 → end_day_raid → 저녁 정산 (%s)" % Enums.FlowState.keys()[GameState.flow_state]) and ok
	# 습격 뒤 20/30, 이어진 저녁 정산이 하루 상승분(+3 이상)을 더함.
	ok = _check(Colony.threat >= 23 and Colony.threat < 40, "습격 뒤 위협도 20/30 + 저녁 정산 (%d)" % Colony.threat) and ok
	GameState.flow_state = Enums.FlowState.BASE_MORNING
	Colony.last_raid_day = 0
	Colony._roll_stay_day_raid()
	ok = _check(GameState.flow_state == Enums.FlowState.BASE_MORNING, "머무르기가 아니면 낮 습격 판정 안 함") and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_issue45] 실패: " + what)
	return cond
