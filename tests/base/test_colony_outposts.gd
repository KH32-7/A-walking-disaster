extends Node
## C-19: 전초기지 — 노드, 건설·주둔 2명, 위협도, 방향별 강도 −25%, 하루 전 예고, 전초기지 습격 20%,
## 유지비·채집, 수리, save. Called by tests/run_tests.gd. Restores Colony, Economy and GameState.


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	var ok := true
	ok = _test_nodes_and_build() and ok
	ok = _test_effects() and ok
	ok = _test_raids() and ok
	ok = _test_settle_and_save() and ok
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _fresh(resources: Dictionary = {}) -> void:
	GameState.load_data({"day": 10})
	Economy.load_data({})
	if not resources.is_empty():
		Economy.apply(resources)
	Colony.load_data({})
	Colony._rng.seed = 19


## A ready, garrisoned outpost on `node_id`. Returns the two garrison residents.
func _active(node_id: StringName) -> Array[StringName]:
	Economy.apply(OutpostRules.COST)
	Colony.build_outpost(node_id)
	GameState.load_data({"day": GameState.day + OutpostRules.BUILD_DAYS})
	var ids: Array[StringName] = []
	for i in 2:
		var id := Colony.add_resident({"traits": [], "stats": {&"sense": 5}})
		Colony.assign_garrison(node_id, id)
		ids.append(id)
	return ids


func _test_nodes_and_build() -> bool:
	_fresh()
	var nodes := Colony.outpost_nodes().map(func(n): return n["node_id"])
	# 4 directions + one entrance per field region (the region list grows with B's data, issue #123).
	var regions := _region_ids()
	var ok := _check(nodes.size() == OutpostRules.DIRECTION_NODES.size() + regions.size(), "노드: 4방향 + 지역 %d곳 입구: %s" % [regions.size(), nodes])
	ok = _check(OutpostRules.DIRECTION_NODES.keys().all(func(id): return id in nodes) and &"outpost_flooded_mall" in nodes, "4방향과 침수 상가 입구는 항상 있음") and ok
	ok = _check(regions.all(func(r): return StringName(OutpostRules.REGION_NODE_PREFIX + r) in nodes), "지역마다 입구 노드") and ok
	ok = _check(not Colony.build_outpost(&"outpost_north"), "자원이 없으면 못 지음") and ok
	Economy.apply(OutpostRules.COST)
	ok = _check(Colony.build_outpost(&"outpost_north") and Economy.get_amount(&"wood") == 0, "나무 60·돌 30·고철 20을 내고 건설 시작") and ok
	ok = _check(not Colony.build_outpost(&"outpost_north"), "같은 노드에 둘은 안 됨") and ok
	var a := Colony.add_resident({"traits": []})
	ok = _check(not Colony.assign_garrison(&"outpost_north", a), "완성 전에는 주둔 불가") and ok
	GameState.load_data({"day": 12})
	var b := Colony.add_resident({"traits": []})
	var c := Colony.add_resident({"traits": []})
	var kid := Colony.add_resident({"traits": [], "age_stage": Enums.AgeStage.CHILD})
	ok = _check(not Colony.assign_garrison(&"outpost_north", kid), "아이는 주둔 불가") and ok
	ok = _check(Colony.assign_garrison(&"outpost_north", a) and not Colony.is_outpost_active(&"outpost_north"), "1명이면 아직 멈춤") and ok
	ok = _check(Colony.assign_garrison(&"outpost_north", b) and Colony.is_outpost_active(&"outpost_north"), "2명이면 가동") and ok
	ok = _check(not Colony.assign_garrison(&"outpost_north", c) and Colony.garrison_of(&"outpost_north") == [a, b], "주둔은 2명까지") and ok
	Colony.unassign_job(a)
	ok = _check(not Colony.is_outpost_active(&"outpost_north"), "주둔이 빠지면 멈춤") and ok
	return ok


func _test_effects() -> bool:
	_fresh()
	_active(&"outpost_north")
	var with_outpost := Colony.threat_delta()
	Colony.outposts[&"outpost_north"]["damaged"] = true
	var without := Colony.threat_delta()
	Colony.outposts[&"outpost_north"]["damaged"] = false
	var ok := _check(is_equal_approx(without - with_outpost, RaidRules.THREAT_PER_OUTPOST), "가동 중 전초기지 1곳: 위협도 −2/일")
	ok = _check(is_equal_approx(Colony.raid_strength_mult({"directions": [&"north"]}), 0.75), "그 방향 습격 강도 −25%%") and ok
	ok = _check(is_equal_approx(Colony.raid_strength_mult({"directions": [&"north", &"east"]}), 0.875), "두 방향 중 한쪽만이면 절반") and ok
	ok = _check(is_equal_approx(Colony.raid_strength_mult({"directions": [&"south"]}), 1.0), "다른 방향은 그대로") and ok
	return ok


func _test_raids() -> bool:
	_fresh()
	var garrison := _active(&"outpost_north")
	var on_outpost := 0
	var warned_ok := true
	for i in 200:
		var raid := Colony.roll_raid(Enums.RaidTime.NIGHT, true)
		if raid["target"] == &"outpost_north":
			on_outpost += 1
		var faces: bool = &"north" in raid["directions"]
		if faces != raid["outpost_warned"] or (faces and raid["notice"] != &"day_before"):
			warned_ok = false
	var ok := _check(on_outpost > 15 and on_outpost < 70, "습격의 약 20%%가 전초기지를 노림 (%d/200)" % on_outpost)
	ok = _check(warned_ok, "전초기지가 보는 방향이면 하루 전 예고 + 규모 정보") and ok
	var day := Colony.roll_raid(Enums.RaidTime.DAY, true)
	if &"north" in day["directions"]:
		ok = _check(day["warning_sec"] == RaidRules.DAY_WARNING_SEC, "낮 습격도 60초 전 무전") and ok

	var wall := Colony.place_building(&"stone_wall", Vector2i.ZERO, 0, &"front_yard", false)
	Colony.complete_building(wall)
	var res := Colony.resolve_raid({"raid_id": &"op", "strength": 500.0, "type": &"swarm", "target": &"outpost_north", "directions": [&"north"]}, Enums.RaidMode.AUTO)
	ok = _check(res["target"] == &"outpost_north" and res["outcome"] == Enums.RaidOutcome.LOSS and not Colony.is_outpost_active(&"outpost_north"), "전초기지가 무너지면 멈춤") and ok
	ok = _check(res["casualties"].size() == 2 and garrison.all(func(id): return Colony.get_resident(id)["health"] == Enums.HealthState.INJURED), "주둔 주민이 다침") and ok
	ok = _check(Colony.get_building(wall)["durability"] == BaseDB.get_building(&"stone_wall").durability, "기지는 피해 없음") and ok
	ok = _check(not Colony.repair_outpost(&"outpost_north"), "수리비가 없으면 수리 불가") and ok
	Economy.apply(Colony.outpost_repair_cost(&"outpost_north"))
	ok = _check(Colony.outpost_repair_cost(&"outpost_north") == {&"wood": 18, &"stone": 9, &"scrap": 6} and Colony.repair_outpost(&"outpost_north"),
		"수리 = 건설 비용 30%% (올림)") and ok
	return ok


func _test_settle_and_save() -> bool:
	_fresh({&"food": 50})
	_active(&"outpost_east")
	var report := Colony.settle_day()
	var ok := _check(report["produced"].get(&"wood", 0) == 5 and report["produced"].get(&"scrap", 0) == 5, "주변 채집 나무·고철 +5/일: %s" % [report["produced"]])
	ok = _check(report["consumed"].get(&"food", 0) >= 2, "유지비 식량 2/일") and ok
	var saved := Colony.outpost_nodes()
	Colony.load_data(JSON.parse_string(JSON.stringify(Colony.save_data())))
	ok = _check(Colony.outpost_nodes() == saved and Colony.is_outpost_active(&"outpost_east"), "저장 후 전초기지·주둔 유지") and ok
	return ok


## Field regions on disk: data/regions/<id>.tres and/or data/regions/<id>/ folders.
func _region_ids() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(OutpostRules.REGIONS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var file := f.trim_suffix(".remap")
		if file.ends_with(".tres") and not file.get_basename() in out:
			out.append(file.get_basename())
	for d in dir.get_directories():
		if not d in out:
			out.append(d)
	return out


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_colony_outposts] 실패: " + what)
	return cond
