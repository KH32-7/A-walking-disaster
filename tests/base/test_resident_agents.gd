extends Node
## C-07: residents on the base map — one agent each, work / gather / sleep targets by phase,
## walking along the navmesh, needs above the head, agents removed when residents leave.
## Called by tests/run_tests.gd. Restores Colony, Economy and GameState.

const SCENE := "res://levels/base/base_school/base_school.tscn"
const WALK_SEC := 4.0


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	var game_snapshot := GameState.save_data().duplicate(true)
	GameState.load_data({"day": 2, "phase": Enums.Phase.MORNING})
	Economy.load_data({})
	Colony.load_data({})
	var worker := Colony.add_resident({"name": "벌목꾼", "stats": {&"str": 5}, "traits": []})
	var radio := Colony.add_resident({"name": "무전수", "stats": {&"heart": 5}, "traits": []})
	var idle := Colony.add_resident({"name": "쉬는 사람", "traits": []})
	var yard := Colony.place_building(&"lumber_yard", Vector2i(0, 0), 0, &"front_yard", false)
	Colony.complete_building(yard)
	Colony.assign_job(worker, &"woodcutting")
	Colony.assign_job(radio, &"radio")

	var base := (load(SCENE) as PackedScene).instantiate() as Node3D
	add_child(base)
	var layout: Node = base.get_node("Layout")
	var bake_deadline := Time.get_ticks_msec() + 20000
	while not layout.navigation_baked and Time.get_ticks_msec() < bake_deadline:
		await get_tree().process_frame
	await get_tree().process_frame
	var crowd: ResidentCrowd = base.residents
	var grid: BaseGrid = base.grid
	var ok := _check(crowd.agent_count() == 3, "주민 3명 → 캐릭터 3")
	if ResourceLoader.exists(ResidentAgent.CHARACTER_SCENE):
		var model := crowd.agent(worker).get_node("Model").get_child(0)
		ok = _check(model is CharacterLook, "D-09 캐릭터(CharacterLook)로 그림") and ok
		ok = _check(ResidentAgent.default_preset({"age_stage": Enums.AgeStage.CHILD}) == &"child_yellow", "아이는 아이 프리셋") and ok

	var yard_center := grid.footprint_center(&"front_yard", Vector2i(0, 0), Vector2i(2, 2))
	var a := crowd.agent(worker)
	ok = _check(a.activity == &"work" and _flat(a.target_position()).distance_to(_flat(yard_center)) < 2.0, "아침: 벌목꾼은 벌목장으로") and ok
	var radio_spot := (layout.get_node("WorkSpots/Work_Radio") as Node3D).global_position
	ok = _check(_flat(crowd.agent(radio).target_position()).distance_to(_flat(radio_spot)) < 1.0, "무전수는 방송실 작업 자리로") and ok
	ok = _check(crowd.agent(idle).activity == &"idle", "일 없는 사람은 모이는 곳 근처") and ok

	var start := a.global_position
	var before := _flat(start).distance_to(_flat(a.target_position()))
	await get_tree().create_timer(WALK_SEC).timeout
	var after := _flat(a.global_position).distance_to(_flat(a.target_position()))
	ok = _check(after < before - 3.0 or a.at_target, "내비메시를 따라 걸어감 (%.1fm → %.1fm)" % [before, after]) and ok

	GameState.set_phase(Enums.Phase.NIGHT)
	var bed: StringName = Colony.get_resident(worker)["bed_id"]
	var bed_spot := (layout.get_node("BedSpots/" + String(bed)) as Node3D).global_position
	ok = _check(a.activity == &"sleep" and _flat(a.target_position()).distance_to(_flat(bed_spot)) < 0.1, "밤: 자기 침상(%s)으로" % bed) and ok
	var path := NavigationServer3D.map_get_path(a.get_world_3d().navigation_map, a.global_position, bed_spot, true)
	ok = _check(not path.is_empty() and _flat(path[-1]).distance_to(_flat(bed_spot)) < 1.0, "침실까지 길이 있음") and ok

	GameState.set_phase(Enums.Phase.EVENING)
	var fire := Colony.place_building(&"bonfire", Vector2i(6, 1), 0, &"front_yard", false)
	Colony.complete_building(fire)
	await get_tree().process_frame
	var fire_pos := grid.footprint_center(&"front_yard", Vector2i(6, 1), Vector2i.ONE)
	ok = _check(a.activity == &"gather" and _flat(a.target_position()).distance_to(_flat(fire_pos)) < 2.0, "저녁: 모닥불로 모임") and ok

	Colony.residents[idle]["hunger"] = 5
	crowd.agent(idle).refresh_from_colony()
	ok = _check(&"hungry" in crowd.agent(idle).needs_state(), "머리 위 상태: 배고픔") and ok

	Colony._leave(idle, &"test")
	await get_tree().process_frame
	await get_tree().process_frame
	ok = _check(crowd.agent_count() == 2 and crowd.agent(idle) == null, "떠난 주민의 캐릭터는 사라짐") and ok
	var group := get_tree().get_nodes_in_group(ResidentAgent.GROUP).filter(func(n): return not n.is_queued_for_deletion())
	ok = _check(group.size() == 2 and group[0].has_meta(&"resident_id"), "그룹 base_resident + 메타 resident_id (D-09용)") and ok

	base.queue_free()
	await get_tree().process_frame
	GameState.load_data(game_snapshot)
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_resident_agents] 실패: " + what)
	return cond
