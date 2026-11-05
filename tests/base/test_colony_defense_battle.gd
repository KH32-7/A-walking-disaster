extends Node
## C-17: 직접 방어전 — 파 구성, 결과 표, Colony 결과 반영(직접·넘기기·기지 씬 없음), 시설 피해
## (RaidStructure, 뿌리 파쇄자 ×3), 함정 재설치, DefenseBattle 진행(3파·20초 준비·5분·긴급 귀환 2파부터·
## 대피소 패배). Raiders are stand-ins here; the real B-23 parts run in the base scene.
## Called by tests/run_tests.gd. Restores Colony, Economy and GameState.

var _requests: Array = []
var _done := 0


class FakeRaider extends Node3D:
	signal died(monster: Node3D)

	func kill() -> void:
		died.emit(self)
		queue_free()


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	var ok := true
	ok = _test_rules() and ok
	ok = _test_fallback() and ok
	Colony.defense_requested.connect(_on_request)
	ok = _test_results() and ok
	ok = _test_structures() and ok
	ok = _test_battle() and ok
	Colony.defense_requested.disconnect(_on_request)
	Colony._defense = {}
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _on_request(raid: Dictionary, first_wave: int) -> void:
	_requests.append([raid, first_wave])


func _fresh(resources: Dictionary = {}) -> void:
	GameState.load_data({"day": 12})
	Economy.load_data({})
	if not resources.is_empty():
		Economy.apply(resources)
	Colony.load_data({})
	Colony._rng.seed = 17
	Colony._defense = {}
	_requests.clear()
	_done = 0


func _raid(strength: float = 30.0, type: StringName = &"swarm", family: int = Enums.Element.NONE) -> Dictionary:
	return {"raid_id": &"d_test", "strength": strength, "type": type, "family": family, "directions": [&"south"], "time": Enums.RaidTime.DAY}


func _build(def_id: StringName) -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, &"front_yard", false)
	Colony.complete_building(uid)
	return uid


func _test_rules() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var waves := DefenseRules.compose_waves(_raid(30.0), rng)
	var points := 0
	for w: Array in waves:
		for def: MonsterDef in w:
			points += int(DefenseRules.TIER_POINTS[def.tier])
	var ok := _check(waves.size() == 3 and points >= 15 and waves.all(func(w): return not w.is_empty()), "3파, 강도 30 → 15포인트: %d" % points)
	var green := DefenseRules.compose_waves(_raid(30.0, &"swarm", Enums.Element.GREEN), rng)
	ok = _check(green.all(func(w): return w.all(func(d): return d.family == Enums.Element.GREEN)), "계열 습격은 그 계열 마물만") and ok
	var siege := DefenseRules.compose_waves(_raid(40.0, &"siege"), rng)
	ok = _check(siege[2].any(func(d): return d.tier == Enums.MonsterTier.SIEGE) and siege[0].all(func(d): return d.tier != Enums.MonsterTier.SIEGE),
		"공성 습격은 마지막 파에 공성 마물") and ok
	ok = _check(DefenseRules.outcome(true, 0) == Enums.RaidOutcome.FLAWLESS and DefenseRules.outcome(true, 2) == Enums.RaidOutcome.WIN
		and DefenseRules.outcome(true, 3) == Enums.RaidOutcome.NARROW and DefenseRules.outcome(false, 0) == Enums.RaidOutcome.LOSS, "결과 표") and ok
	return ok


func _test_fallback() -> bool:
	_fresh()
	var done := [false]
	Colony.begin_direct_defense(_raid(), 1, func() -> void: done[0] = true)
	return _check(done[0] and Colony.direct_defense().is_empty(), "기지 씬이 없으면 바로 플레이어 판정(+20%)으로")


func _test_results() -> bool:
	_fresh()
	var calls := [0]
	Colony.begin_direct_defense(_raid(30.0, &"swarm", Enums.Element.GREEN), 1, func() -> void: calls[0] += 1)
	var ok := _check(_requests.size() == 1 and Colony.direct_defense()["first_wave"] == 1, "기지 씬에 방어전을 요청")
	var res := Colony.finish_direct_defense({"won": true})
	ok = _check(res["outcome"] == Enums.RaidOutcome.FLAWLESS and res["direct"] and calls[0] == 1 and Economy.get_amount(&"vine_fiber") > 0,
		"잃은 것 없이 이기면 완승, 계열 재료 보상") and ok
	ok = _check(Colony.threat == RaidRules.THREAT_AFTER_WIN and Colony.direct_defense().is_empty(), "위협도 20으로, 방어전 끝") and ok

	_fresh({&"wood": 100})
	var guard := Colony.add_resident({"traits": []})
	var civ := Colony.add_resident({"traits": []})
	Colony.begin_direct_defense(_raid(), 1, func() -> void: pass)
	res = Colony.finish_direct_defense({"won": true, "guards_down": [guard], "hurt": [civ]})
	ok = _check(res["outcome"] == Enums.RaidOutcome.WIN and Colony.get_resident(guard)["health"] == Enums.HealthState.INJURED
		and Colony.get_resident(civ)["health"] == Enums.HealthState.INJURED, "쓰러진 경비·맞은 주민은 다침, 결과 승리") and ok
	Colony.begin_direct_defense(_raid(), 1, func() -> void: pass)
	var morale := int(Colony.get_resident(civ)["morale"])
	res = Colony.finish_direct_defense({"won": false})
	ok = _check(res["outcome"] == Enums.RaidOutcome.LOSS and Economy.get_amount(&"wood") == 80
		and int(Colony.get_resident(civ)["morale"]) == maxi(morale + RaidRules.LOSS_MORALE, 0), "지면 창고 20%% 손실, 사기 −10") and ok
	Colony.begin_direct_defense(_raid(), 2, func() -> void: calls[0] += 10)
	res = Colony.skip_direct_defense()
	ok = _check(res["mode"] == Enums.RaidMode.PLAYED and not res.has("direct") and calls[0] == 11, "자동 판정으로 넘기기 (+20%%)") and ok
	return ok


func _test_structures() -> bool:
	_fresh({&"scrap": 50, &"wood": 50})
	var wall := _build(&"stone_wall")
	var gate := _build(&"wooden_gate")
	var trap := _build(&"spike_trap")
	var ws := RaidStructure.create(wall, &"stone_wall", Vector2(2, 2), 2.6)
	var gs := RaidStructure.create(gate, &"wooden_gate", Vector2(2, 2), 2.6)
	add_child(ws)
	add_child(gs)
	var gone: Array = []
	ws.broken.connect(func(uid: StringName) -> void: gone.append(uid))
	var ok := _check(ws.is_in_group(RaidMarch.STRUCTURE_GROUP) and gs.is_in_group(RaidMarch.GATE_GROUP) and not ws.is_in_group(RaidMarch.GATE_GROUP), "구조물·문 그룹")
	ok = _check(ws.collision_layer == 1 << (Enums.LAYER_WORLD - 1), "레이어 1 몸체") and ok
	ws.take_damage(50.0, {"structure_damage_mult": 3.0})
	ok = _check(Colony.get_building(wall)["durability"] == 150, "벽은 뿌리 파쇄자 ×3 (50 → 150 피해)") and ok
	gs.take_damage(50.0, {"structure_damage_mult": 3.0})
	ok = _check(Colony.get_building(gate)["durability"] == 100, "문은 배율 없음") and ok
	ws.take_damage(60.0, {"structure_damage_mult": 3.0})
	ok = _check(gone == [wall] and Colony.get_building(wall)["damaged"] and not ws.is_in_group(RaidMarch.STRUCTURE_GROUP), "0이 되면 부서짐 (파손, 그룹에서 빠짐)") and ok
	gs.queue_free()
	Colony.buildings[trap]["durability"] = 0
	Colony.buildings[trap]["damaged"] = true
	ok = _check(Colony.reinstall_trap(trap) and Colony.get_building(trap)["durability"] == 3 and not Colony.get_building(trap)["damaged"], "함정 재설치 (수리 비용)") and ok
	ok = _check(not Colony.reinstall_trap(trap), "다 찬 함정은 재설치할 것 없음") and ok
	return ok


func _battle(first_wave: int = 1) -> DefenseBattle:
	var b := DefenseBattle.new()
	b.raider_factory = func(_def: MonsterDef, pos: Vector3, _goal: Vector3) -> Node3D:
		var m := FakeRaider.new()
		m.position = pos
		return m
	add_child(b)
	b.setup(_raid(30.0), first_wave)
	b.finished.connect(func(_r: Dictionary) -> void: _done += 1)
	return b


func _kill_all(b: DefenseBattle) -> void:
	for m in b.alive.duplicate():
		(m as FakeRaider).kill()


func _test_battle() -> bool:
	_fresh()
	Colony.begin_direct_defense(_raid(30.0), 1, func() -> void: pass)
	var b := _battle()
	b.start()
	var ok := _check(b.state == DefenseBattle.State.PREP and b.wave == 0, "시작: 20초 준비")
	b.tick(19.0)
	ok = _check(b.alive.is_empty(), "준비 중에는 마물 없음") and ok
	b.tick(1.5)
	ok = _check(b.state == DefenseBattle.State.WAVE and b.wave == 1 and b.alive.size() == b.waves[0].size(), "1파 등장 (%d마리)" % b.alive.size()) and ok
	_kill_all(b)
	b.tick(0.1)
	ok = _check(b.state == DefenseBattle.State.PREP, "다 잡으면 다음 준비") and ok
	for w in 2:
		b.tick(DefenseRules.PREP_SEC + 0.1)
		_kill_all(b)
		b.tick(0.1)
	ok = _check(_done == 1 and b.state == DefenseBattle.State.DONE, "3파를 모두 잡으면 승리") and ok

	_fresh()
	Colony.begin_direct_defense(_raid(30.0), 2, func() -> void: pass)
	b = _battle(DefenseRules.EMERGENCY_FIRST_WAVE)
	b.start()
	b.tick(DefenseRules.PREP_SEC + 0.1)
	ok = _check(b.wave == 2, "긴급 귀환이면 2파부터") and ok

	_fresh()
	Colony.begin_direct_defense(_raid(30.0), 1, func() -> void: pass)
	b = _battle()
	b.start()
	b.tick(DefenseRules.PREP_SEC + 0.1)
	b.tick(DefenseRules.SURVIVE_SEC)
	ok = _check(_done == 1, "5분 버티면 승리 (남은 마물은 물러남)") and ok

	_fresh()
	var shelter := _build(&"shelter")
	Colony.begin_direct_defense(_raid(30.0), 1, func() -> void: pass)
	b = _battle()
	b.start()
	b.broken.append(shelter)
	var lost := [{}]
	b.finished.connect(func(r: Dictionary) -> void: lost[0] = r)
	b.tick(0.1)
	ok = _check(lost[0].get("outcome") == Enums.RaidOutcome.LOSS, "대피소 문이 부서지면 패배") and ok
	ok = _test_base_scene() and ok
	return ok


## The real base scene answers defense_requested with a DefenseBattle that spawns B-23 monsters,
## guards as FieldCompanion, walls as RaidStructure; 넘기기 ends it and removes everything.
func _test_base_scene() -> bool:
	_fresh()
	var guard := Colony.add_resident({"traits": [], "stats": {&"sense": 6}})
	_build(&"guard_post")
	Colony.assign_job(guard, &"guard")
	_build(&"stone_wall")
	var scene := (load("res://levels/base/base_school/base_school.tscn") as PackedScene).instantiate()
	add_child(scene)
	Colony.begin_direct_defense(_raid(20.0), 1, func() -> void: pass)
	var b: DefenseBattle = scene.call(&"get_battle")
	var ok := _check(b != null and b.state == DefenseBattle.State.PREP, "기지 씬이 방어전을 시작")
	if b == null:
		remove_child(scene)
		scene.free()
		return ok
	ok = _check(b.guard_ids() == [guard] and b.post_names().size() >= 2, "경비는 초소에 (FieldCompanion), 자리: %s" % [b.post_names()]) and ok
	ok = _check(get_tree().get_nodes_in_group(RaidMarch.STRUCTURE_GROUP).size() >= 1, "벽이 습격 구조물로") and ok
	b.tick(DefenseRules.PREP_SEC + 0.1)
	ok = _check(not b.alive.is_empty() and b.alive.all(func(m): return m is Monster and (m as Monster).is_raider()), "1파는 B-23 습격 마물") and ok
	var raiders := b.alive.duplicate()
	var res := b.skip_to_auto()
	ok = _check(res.get("mode") == Enums.RaidMode.PLAYED and raiders.all(func(m): return not is_instance_valid(m) or m.is_queued_for_deletion()),
		"넘기기: 자동 판정 +20%%, 마물 정리") and ok
	remove_child(scene)
	scene.free()  # now: the next test must not see this scene answering defense_requested
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_defense_battle] 실패: " + what)
	return cond
