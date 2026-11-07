extends RefCounted
## EarlyZone on the city park (02 "맵 구조" 초반 구역, 사용자 요청 2026-11-07): on day 1 the
## assembly stands a wall on the line, no nest, boss arena, extract point or loot spot north of it
## stays in its group, both south extract points are the active ones, and roaming packs keep south.
## From early_open_day the whole map is back. Restores GameState.day and FieldState.open_min_z.

const ASSEMBLY := "res://levels/field/city_park/city_park.tscn"
const GROUPS: Array[StringName] = [MonsterNest.GROUP, BossArena.GROUP, ExtractPoint.GROUP, LootSpot.GROUP, RescueSpot.GROUP]

var _tree: SceneTree
var _ok := true


func run() -> bool:
	_tree = Engine.get_main_loop() as SceneTree
	var day := GameState.day
	var park := RegionDef.load_def(&"city_park")
	GameState.day = 1
	var scene := await _load()
	var line := park.early_min_z
	_expect(_tree.get_nodes_in_group(EarlyZone.WALL_GROUP).size() == 1, "1일차 덩굴 벽 하나")
	_expect(is_equal_approx(FieldState.open_min_z, line), "FieldState.open_min_z = 공원 선")
	for g in GROUPS:
		for n in _tree.get_nodes_in_group(g):
			_expect((n as Node3D).global_position.z >= line, "%s %s가 선 북쪽인데 그룹에 남음" % [g, n.name])
	_expect(_tree.get_nodes_in_group(BossArena.GROUP).is_empty(), "1일차 보스 구역 없음")
	var em := _tree.get_first_node_in_group(ExtractionManager.GROUP) as ExtractionManager
	_expect(em != null and em.active_points().size() == 2, "남쪽 탈출 2곳이 활성")
	var roam := scene.get_node_or_null(^"RoamingSpawner") as RoamingSpawner
	if roam != null:
		for m in roam.alive():
			_expect(m.global_position.z >= line - 3.0, "배회 마물 %s가 선 북쪽" % m.name)
	_free(scene)
	await _tree.process_frame
	GameState.day = park.early_open_day
	scene = await _load()
	_expect(_tree.get_nodes_in_group(EarlyZone.WALL_GROUP).is_empty(), "열리는 날부터 벽 없음")
	_expect(FieldState.open_min_z == -INF, "열린 날은 선 없음")
	_expect(_tree.get_nodes_in_group(MonsterNest.GROUP).size() == 6, "열린 날 둥지 6곳")
	_free(scene)
	# Let the navigation map sync without the park's region: the next test (emergency return) checks
	# a route with no navmesh on the same default map.
	for i in 5:
		await _tree.physics_frame
	GameState.day = day
	FieldState.open_min_z = -INF
	return _ok


func _load() -> Node3D:
	var scene := (load(ASSEMBLY) as PackedScene).instantiate() as Node3D
	_tree.root.add_child(scene)
	for i in 30:
		await _tree.physics_frame
	return scene


func _free(scene: Node) -> void:
	_tree.root.remove_child(scene)
	scene.free()


func _expect(cond: bool, message: String) -> void:
	if not cond:
		printerr(message)
		_ok = false
