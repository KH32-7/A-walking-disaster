extends RefCounted
## C-01: base marker scripts and the base sandbox scene.
## Called by tests/run_tests.gd (A-02): run() -> bool.

const SANDBOX := "res://base/_sandbox/base_sandbox.tscn"


func run() -> bool:
	var ok := true
	ok = _test_build_area_cells() and ok
	ok = _test_sandbox_has_every_marker() and ok
	return ok


func _test_build_area_cells() -> bool:
	var area := BuildArea.new()
	area.size_cells = Vector2i(20, 12)
	var ok := true
	ok = _check(area.size_m() == Vector2(40, 24), "BuildArea 20×12칸 = 40×24m") and ok
	ok = _check(area.cell_to_local(Vector2i(0, 0)) == Vector3(-19, 0, -11), "0,0 칸 중심") and ok
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(7, 3), Vector2i(19, 11)]:
		ok = _check(area.local_to_cell(area.cell_to_local(cell)) == cell, "칸 왕복 %s" % cell) and ok
	ok = _check(not area.has_cell(Vector2i(20, 0)), "범위 밖 칸 거부") and ok
	ok = _check(not area.has_cell(area.local_to_cell(Vector3(-20.5, 0, 0))), "범위 밖 좌표 거부") and ok
	area.size_cells = Vector2i(0, -3)
	ok = _check(area.size_cells == Vector2i(1, 1), "크기 최소 1칸") and ok
	area.free()
	return ok


func _test_sandbox_has_every_marker() -> bool:
	var scene: PackedScene = load(SANDBOX)
	if not _check(scene != null, "샌드박스 씬 로드"):
		return false
	var root := scene.instantiate()
	var counts := {}
	for node in root.find_children("*", "Marker3D", true, false):
		var key := "other"
		if node is ZoneMarker: key = "zone"
		elif node is BuildArea: key = "build"
		elif node is ResourceNode: key = "resource"
		elif node is RaidSpawnPoint: key = "raid"
		elif node is WorkSpot: key = "work"
		elif node is OutpostNode: key = "outpost"
		counts[key] = counts.get(key, 0) + 1
	root.free()
	var ok := true
	for key in ["zone", "build", "resource", "raid", "work", "outpost"]:
		ok = _check(counts.get(key, 0) > 0, "샌드박스에 %s 마커" % key) and ok
	ok = _check(counts.get("raid", 0) == 4, "습격 지점 4방향") and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_base_markers] 실패: " + what)
	return cond
