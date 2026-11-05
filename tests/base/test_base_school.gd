extends Node
## C-09: base map (levels/base/base_school). Loads the assembled scene the way SceneRouter does,
## then checks markers, player placement, roof zone and that the baked navigation connects the
## front yard, the main hall rooms and the playground. Called by tests/run_tests.gd.

const SCENE := "res://levels/base/base_school/base_school.tscn"
const BAKE_TIMEOUT_SEC := 20.0


func run() -> bool:
	var ok := _check(SceneRouter.BASE_SCENE == SCENE and ResourceLoader.exists(SCENE), "SceneRouter.BASE_SCENE 이 이 씬을 가리키고 파일이 있음")
	if not ok:
		return false
	var base := (load(SCENE) as PackedScene).instantiate() as Node3D
	add_child(base)
	var layout: Node = base.get_node("Layout")
	if not layout.navigation_baked:
		var timer := get_tree().create_timer(BAKE_TIMEOUT_SEC)
		while not layout.navigation_baked and timer.time_left > 0.0:
			await get_tree().process_frame
	ok = _check(layout.navigation_baked, "내비메시 굽기 완료") and ok
	ok = _test_markers(layout) and ok
	ok = _test_player(base, layout) and ok
	ok = _test_navigation(layout) and ok
	base.queue_free()
	await get_tree().process_frame
	return ok


func _test_markers(layout: Node) -> bool:
	var counts := {}
	for node in layout.find_children("*", "Marker3D", true, false):
		var key := "other"
		if node is ZoneMarker: key = "zone"
		elif node is BuildArea: key = "build"
		elif node is ResourceNode: key = "tree" if node.kind == ResourceNode.Kind.TREE else "debris"
		elif node is RaidSpawnPoint: key = "raid"
		elif node is WorkSpot: key = "work"
		elif node is OutpostNode: key = "outpost"
		elif node is PlayerSpawn: key = "spawn"
		counts[key] = counts.get(key, 0) + 1
	var ok := _check(counts.get("zone", 0) == 8 and counts.get("build", 0) == 7, "구역 8 (본관·앞마당·운동장·체육관·옥상·공원 A·B·교문 밖 상가), 건설 부지 7: %s" % counts)
	ok = _check(counts.get("raid", 0) == 4 and counts.get("outpost", 0) == 4, "습격 4방향, 전초기지 노드 4") and ok
	ok = _check(counts.get("tree", 0) >= 4 and counts.get("debris", 0) >= 2 and counts.get("spawn", 0) == 1, "나무·잔해·플레이어 시작점") and ok
	var directions := {}
	for node in layout.find_children("*", "Marker3D", true, false):
		if node is RaidSpawnPoint:
			directions[node.direction] = true
	ok = _check(directions.size() == 4, "습격 지점 방향이 서로 다름") and ok
	# M1: a lumber yard (needs a tree within 10 m) and a bed fit on the start-cleared front yard.
	var yard: BuildArea = layout.get_node("Zones/Build_FrontYard")
	var nearest := INF
	for node in layout.find_children("*", "Marker3D", true, false):
		if node is ResourceNode and node.kind == ResourceNode.Kind.TREE:
			nearest = minf(nearest, yard.cell_to_world(Vector2i(0, 1)).distance_to(node.global_position))
	ok = _check(nearest <= 10.0, "앞마당 서쪽 칸에서 나무까지 10m 이내 (벌목장 조건, %.1fm)" % nearest) and ok
	var zone: ZoneMarker = layout.get_node("Zones/Zone_FrontYard")
	ok = _check(zone.starts_cleared and yard.zone_id == zone.zone_id, "앞마당은 처음부터 건설 가능") and ok
	var indoor := layout.get_node_or_null("IndoorZone_MainHall") as IndoorZone
	ok = _check(indoor != null and indoor.building_id == &"main_hall", "본관 지붕 숨김 구역 (building_id main_hall)") and ok
	return ok


func _test_player(base: Node3D, layout: Node) -> bool:
	var spawn: Node3D
	for node in layout.find_children("*", "Marker3D", true, false):
		if node is PlayerSpawn:
			spawn = node
	var player := base.get_node("Player") as Node3D
	var ok := _check(player is Player and player.global_position.distance_to(spawn.global_position) < 0.01, "플레이어가 시작점에 놓임")
	ok = _check(base.get_node("FieldCamera") is FieldCamera, "쿼터뷰 카메라") and ok
	# Lane D's dressing.tscn may or may not exist yet (D-10, issue #57).
	if ResourceLoader.exists("res://levels/base/base_school/dressing.tscn"):
		ok = _check(base.get_node_or_null("Dressing") != null and base.get_node_or_null("GreyboxSun") == null, "dressing이 있으면 dressing을 붙이고 임시 조명은 없음") and ok
	else:
		ok = _check(base.get_node_or_null("GreyboxSun") != null, "dressing이 없으면 임시 조명") and ok
	return ok


func _test_navigation(layout: Node) -> bool:
	var region: NavigationRegion3D = layout.get_node("Navigation")
	var ok := _check(region.navigation_mesh.get_polygon_count() > 0, "내비 폴리곤 생성")
	var map := region.get_navigation_map()
	NavigationServer3D.map_force_update(map)
	var from := Vector3(7, 0, -14)  # player spawn
	var targets := {
		"운동장": Vector3(0, 0, 6),
		"방송실(본관 서쪽 방)": Vector3(-17, 0, -26),
		"침실(본관 동쪽 방)": Vector3(17, 0, -26),
		"교문 밖": Vector3(0, 0, 32),
	}
	for label: String in targets:
		var to: Vector3 = targets[label]
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		var reached := not path.is_empty() and Vector2(path[-1].x, path[-1].z).distance_to(Vector2(to.x, to.z)) < 1.0
		ok = _check(reached, "시작점 → %s 길 있음" % label) and ok
	return ok


func _check(cond: bool, what: String) -> bool:
	if not cond:
		push_error("[test_base_school] 실패: " + what)
	return cond
