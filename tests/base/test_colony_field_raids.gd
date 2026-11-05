extends Node
## C-21: 출격 중 낮 습격 — 발생 판정, 경보(초소 60초 / 없으면 즉시), 계속 탐색 시 자동 판정,
## 긴급 귀환(B-22) 시 기다렸다가 플레이어가 있는 판정(+20%), 쓰러지면 자동 판정.
## Called by tests/run_tests.gd. Restores Colony, Economy, GameState and SceneRouter.

var _warnings: Array = []
var _resolved: Array = []


## Raids and the played defence are switched off in the game for now (RaidRules.RAIDS /
## DIRECT_DEFENSE); these rules are still tested with them on.
func run() -> bool:
	var was := [RaidRules.RAIDS, RaidRules.DIRECT_DEFENSE]
	RaidRules.RAIDS = true
	RaidRules.DIRECT_DEFENSE = true
	var ok: bool = _run_switched_on()
	RaidRules.RAIDS = was[0]
	RaidRules.DIRECT_DEFENSE = was[1]
	return ok


func _run_switched_on() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	var router_snapshot: Dictionary = SceneRouter.save_data().duplicate(true)
	EventBus.raid_warning.connect(_on_warning)
	EventBus.raid_resolved.connect(_on_resolved)
	var ok := true
	ok = _test_roll() and ok
	ok = _test_keep_exploring() and ok
	ok = _test_emergency_return() and ok
	ok = _test_sortie_end() and ok
	EventBus.raid_warning.disconnect(_on_warning)
	EventBus.raid_resolved.disconnect(_on_resolved)
	SceneRouter.load_data(router_snapshot)
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _on_warning(info: Dictionary) -> void:
	_warnings.append(info)


func _on_resolved(result: Dictionary) -> void:
	_resolved.append(result)


func _fresh(post: bool = false) -> void:
	GameState.load_data({"day": 10})
	Economy.load_data({})
	Colony.load_data({})
	Colony._rng.seed = 21
	Colony.threat = 80
	_warnings.clear()
	_resolved.clear()
	Colony.add_resident({"traits": []})
	if post:
		var uid := Colony.place_building(&"guard_post", Vector2i.ZERO, 0, &"front_yard", false)
		Colony.complete_building(uid)


## A day raid that comes `after` seconds into the sortie.
func _pending(after: float) -> void:
	Colony._field_raid = {"phase": &"waiting", "due_in": after, "hit_in": 0.0, "raid": {}, "result": {}}
	Colony._emergency_requested = false


func _test_roll() -> bool:
	_fresh()
	var hits := 0
	for i in 200:
		Colony._roll_field_day_raid()
		if not Colony.field_day_raid().is_empty():
			hits += 1
	var ok := _check(hits > 15 and hits < 70, "위협도 70 이상이면 출격마다 약 20%% (%d/200)" % hits)
	var due: float = Colony.field_day_raid().get("due_in", 120.0)
	ok = _check(due >= RaidRules.FIELD_RAID_AFTER_SEC.x and due <= RaidRules.FIELD_RAID_AFTER_SEC.y, "출격 90~300초 뒤 경보") and ok
	Colony.threat = 60
	hits = 0
	for i in 100:
		Colony._roll_field_day_raid()
		hits += 0 if Colony.field_day_raid().is_empty() else 1
	ok = _check(hits == 0, "위협도 70 미만이면 낮 습격 없음") and ok
	Colony.threat = 80
	GameState.load_data({"day": 3})
	Colony._roll_field_day_raid()
	ok = _check(Colony.field_day_raid().is_empty(), "5일차 전에는 없음") and ok
	GameState.load_data({"day": 10})
	Colony.last_raid_day = 10
	Colony._roll_field_day_raid()
	ok = _check(Colony.field_day_raid().is_empty(), "하루 한 번") and ok
	return ok


func _test_keep_exploring() -> bool:
	_fresh(true)
	_pending(100.0)
	Colony._advance_field_raid(60.0)
	var ok := _check(Colony.field_day_raid()["phase"] == &"waiting" and _warnings.is_empty(), "때가 되기 전에는 조용함")
	Colony._advance_field_raid(50.0)
	var raid := Colony.field_day_raid()
	ok = _check(raid["phase"] == &"warned" and _warnings.size() == 1 and _warnings[0]["time"] == Enums.RaidTime.DAY
		and _warnings[0]["warning_sec"] == RaidRules.DAY_WARNING_SEC, "경비 초소가 있으면 60초 전 경보") and ok
	Colony._advance_field_raid(59.0)
	ok = _check(_resolved.is_empty(), "경보 뒤 60초 동안은 아직") and ok
	Colony._advance_field_raid(2.0)
	ok = _check(Colony.field_day_raid()["phase"] == &"done" and _resolved.size() == 1 and _resolved[0]["mode"] == Enums.RaidMode.AUTO,
		"계속 탐색하면 습격 때 자동 판정") and ok

	_fresh(false)
	_pending(10.0)
	Colony._advance_field_raid(11.0)
	ok = _check(_warnings[0]["warning_sec"] == 0.0 and Colony.field_day_raid()["phase"] == &"done", "초소가 없으면 경보와 동시에 습격") and ok
	return ok


func _test_emergency_return() -> bool:
	_fresh(true)
	_pending(5.0)
	Colony._advance_field_raid(6.0)
	Colony._on_emergency_return()
	Colony._advance_field_raid(61.0)
	var ok := _check(Colony.field_day_raid()["phase"] == &"hold" and _resolved.is_empty(), "긴급 귀환 중이면 습격이 와도 플레이어를 기다림")
	Colony._finish_field_raid({"extracted": true})
	ok = _check(Colony.field_day_raid()["phase"] == &"hold", "탈출하면 기지 방어전으로 (아직 판정 안 함)") and ok
	var res := Colony._resolve_returned_field_raid()
	ok = _check(res["mode"] == Enums.RaidMode.PLAYED and Colony.field_day_raid()["phase"] == &"done", "돌아온 뒤 플레이어가 있는 판정 (+20%%)") and ok
	return ok


func _test_sortie_end() -> bool:
	_fresh(true)
	_pending(5.0)
	Colony._advance_field_raid(6.0)
	Colony._on_emergency_return()
	Colony._finish_field_raid({"extracted": false})
	var ok := _check(Colony.field_day_raid()["phase"] == &"done" and _resolved.size() == 1 and _resolved[0]["mode"] == Enums.RaidMode.AUTO,
		"돌아오다 쓰러지면 자동 판정")
	_fresh(true)
	_pending(500.0)
	Colony._finish_field_raid({"extracted": true})
	ok = _check(Colony.field_day_raid().is_empty() and _warnings.is_empty(), "습격 전에 돌아오면 그날 낮 습격은 없음") and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_field_raids] 실패: " + what)
	return cond
