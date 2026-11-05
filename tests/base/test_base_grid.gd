extends Node
## C-03: grid placement rules, build mode, moving, building views on the real base map.
## Called by tests/run_tests.gd. Restores Colony and Economy afterwards.

const SCENE := "res://levels/base/base_school/base_school.tscn"


func run() -> bool:
	var colony_snapshot := JSON.stringify(Colony.save_data())
	var economy_snapshot := Economy.save_data().duplicate(true)
	Economy.load_data({})
	Economy.apply({&"wood": 150, &"stone": 40})
	Colony.load_data({})
	var base := (load(SCENE) as PackedScene).instantiate() as Node3D
	add_child(base)
	await get_tree().process_frame
	var grid: BaseGrid = base.grid
	var ok := true
	ok = _test_rules(grid) and ok
	ok = _test_paths(grid) and ok
	ok = _test_build_mode(base) and ok
	ok = await _test_views(base) and ok
	base.queue_free()
	await get_tree().process_frame
	Economy.load_data(economy_snapshot)
	Colony.load_data(JSON.parse_string(colony_snapshot))
	return ok


func _place(def_id: StringName, zone: StringName, cell: Vector2i, rot: int = 0) -> StringName:
	return Colony.place_building(def_id, cell, rot, zone, false)


func _test_rules(grid: BaseGrid) -> bool:
	var ok := _check(grid.areas.has(&"front_yard") and grid.areas.has(&"playground") and grid.areas.size() == 7, "건설 부지 7곳")
	ok = _check(grid.check(&"bed", &"front_yard", Vector2i(0, 0))["ok"], "앞마당 0,0에 침상") and ok
	var r := grid.check(&"bed", &"front_yard", Vector2i(0, 2))
	ok = _check(not r["ok"] and "부지 밖으로 나감" in r["reasons"], "침상(1×2)이 3칸 높이 부지 아래로 넘침") and ok
	ok = _check(grid.check(&"bed", &"front_yard", Vector2i(0, 2), 1)["ok"], "90° 돌리면 2×1로 들어감") and ok
	var bed := _place(&"bed", &"front_yard", Vector2i(0, 0))
	r = grid.check(&"bonfire", &"front_yard", Vector2i(0, 1))
	ok = _check(not r["ok"] and "다른 건물과 겹침" in r["reasons"], "겹치기 금지") and ok
	ok = _check(grid.check(&"bed", &"front_yard", Vector2i(0, 1), 0, bed)["ok"], "옮길 때는 자기 자리 무시") and ok
	r = grid.check(&"bed", &"playground", Vector2i(3, 3))
	ok = _check(not r["ok"] and "개간되지 않은 구역" in r["reasons"], "운동장은 개간 전") and ok
	Colony.clear_zone(&"playground")
	ok = _check(grid.check(&"bed", &"playground", Vector2i(3, 3))["ok"], "개간하면 운동장에 지을 수 있음") and ok
	ok = _check(grid.check(&"lumber_yard", &"front_yard", Vector2i(1, 0))["ok"], "앞마당 서쪽: 나무 10m 안 → 벌목장") and ok
	r = grid.check(&"lumber_yard", &"front_yard", Vector2i(8, 0))
	ok = _check(not r["ok"] and r["reasons"][0].begins_with("나무"), "앞마당 동쪽 끝은 나무가 멀어 벌목장 불가") and ok
	ok = _check(grid.check(&"quarry", &"front_yard", Vector2i(8, 0))["ok"], "앞마당 동쪽: 잔해 더미 → 채석장") and ok
	ok = _check(not grid.check(&"interpreter_radio", &"front_yard", Vector2i(4, 0))["ok"], "부착형 건물은 격자에 못 놓음") and ok
	ok = _check(not grid.check(&"radio_tower", &"front_yard", Vector2i(4, 0))["ok"], "무전탑은 옥상 전용") and ok
	ok = _check(BaseGrid.footprint(BaseDB.get_building(&"kitchen"), 1) == Vector2i(3, 2), "부엌 2×3 → 회전 3×2") and ok
	Colony.load_data({})
	return ok


## 통로 연결: front yard is 10×3. A bonfire in the middle row gets walled in by the last building.
func _test_paths(grid: BaseGrid) -> bool:
	_place(&"bonfire", &"front_yard", Vector2i(5, 1))
	_place(&"bed", &"front_yard", Vector2i(4, 0))   # (4,0)(4,1)
	_place(&"bed", &"front_yard", Vector2i(6, 0))   # (6,0)(6,1)
	_place(&"bonfire", &"front_yard", Vector2i(5, 0))
	var r := grid.check(&"bed", &"front_yard", Vector2i(5, 2), 1)  # (5,2)(6,2): closes the last side
	var ok := _check(not r["ok"] and r["reasons"][0].begins_with("통로"), "모닥불을 완전히 가두는 배치는 거부: %s" % [r["reasons"]])
	ok = _check(grid.check(&"bed", &"front_yard", Vector2i(7, 1))["ok"], "다른 자리는 괜찮음") and ok
	Colony.load_data({})
	return ok


func _test_build_mode(base: Node3D) -> bool:
	var mode: BuildMode = base.build_mode
	var grid: BaseGrid = base.grid
	var wood := Economy.get_amount(&"wood")
	var ok := _check(mode.start(&"bed") and mode.active, "건설 모드 시작")
	var area: BuildArea = grid.areas[&"front_yard"]
	var result := mode.preview_at(area.cell_to_world(Vector2i(2, 1)))
	ok = _check(result["ok"] and mode.last["cell"] == Vector2i(2, 1), "마우스 칸 기준 발자국 (침상 1×2 → 2,1): %s" % [mode.last]) and ok
	var uid := mode.confirm()
	ok = _check(uid != &"" and not mode.active and Economy.get_amount(&"wood") == wood - 10, "놓으면 건설 현장 + 비용 지불") and ok
	ok = _check(mode.start(&"bed") and not mode.preview_at(area.cell_to_world(Vector2i(2, 2)))["ok"], "같은 자리 다시는 불가") and ok
	mode.cancel()
	ok = _check(mode.start_move(uid), "이동 모드") and ok
	mode.rotate_footprint()
	mode.preview_cell(&"front_yard", Vector2i(7, 2))
	ok = _check(mode.confirm() == uid and Colony.get_building(uid)["cell"] == [7, 2] and Colony.get_building(uid)["rotation"] == 1, "이동 + 회전, 비용 없음") and ok
	ok = _check(Economy.get_amount(&"wood") == wood - 10, "이동은 무료") and ok
	ok = _check(not mode.preview_at(Vector3(200, 0, 200))["ok"], "부지 밖은 불가") and ok
	mode.cancel()
	# D-06 건설 패널 "배치하기" (UI.build_requested) starts the same build mode.
	UI.build_requested.emit(&"bonfire")
	ok = _check(mode.active and mode.def_id == &"bonfire", "건설 패널 배치하기 → 건설 모드") and ok
	mode.cancel()
	if OS.is_debug_build():
		var out := DebugConsole.execute("place at lumber_yard front_yard 1 0")
		ok = _check(out.begins_with("건설 현장"), "콘솔 place at: " + out) and ok
	return ok


func _test_views(base: Node3D) -> bool:
	var views: BuildingViews = base.building_views
	await get_tree().process_frame
	var ok := _check(views.view_count() == Colony.buildings.size() - 1, "무전실 빼고 건물마다 그레이박스 (%d)" % views.view_count())
	var uid := Colony.building_ids(&"", false)[1]
	Colony.complete_building(uid)
	await get_tree().process_frame
	var found := false
	for v in get_tree().get_nodes_in_group(BuildingViews.VIEW_GROUP):
		if v.get_meta(&"building_uid") == uid and not v.is_queued_for_deletion():
			found = true
	ok = _check(found, "완성하면 다시 그림 (그룹 base_building_view, 메타 building_uid)") and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_base_grid] 실패: " + what)
	return cond
