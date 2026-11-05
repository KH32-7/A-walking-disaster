extends RefCounted
## B-12: flooded mall layout. Markers match the confirmed map file, the navmesh reaches every
## marker from the north spawn, every extract point from both spawns, and the wheelchair layer
## leaves the mall's 2F only by the hidden ramp. The assembly spawns the player, monsters and loot,
## activates 2 extract points and has a B-04 IndoorZone per building.

const LAYOUT := "res://levels/field/flooded_mall/layout.tscn"
const ASSEMBLY := "res://levels/field/flooded_mall/flooded_mall.tscn"
const NAV_WALK := 1
const NAV_WHEELCHAIR := 2
const REACH := 1.5 ## path end within this distance (xz) of the target
const MARKER_COUNTS := {
	PlayerSpawn.GROUP: 2, ExtractPoint.GROUP: 3, LootSpot.GROUP: 19, MonsterNest.GROUP: 3,
	RescueSpot.GROUP: 4, HiddenRoute.GROUP: 1, Recording.GROUP: 2, BossArena.GROUP: 0,
}
const EXTRACT_IDS := [&"mall_dock", &"mall_gas_station", &"mall_north_gate"]
const NAV_SYNC_MAX_FRAMES := 300
## Floor plan scale of the generated layout. Path length limits below are for the unscaled map.
const MAP_SCALE: float = preload("res://levels/field/flooded_mall/build/build_layout.gd").MAP_SCALE
const WALK_TO_STAIRS_MAX := 30.0
const RAMP_DETOUR_MIN := 30.0

var _tree: SceneTree
var _ok := true


func run() -> bool:
	_tree = Engine.get_main_loop() as SceneTree
	var layout := (load(LAYOUT) as PackedScene).instantiate() as Node3D
	_tree.root.add_child(layout)
	for i in 3:
		await _tree.physics_frame
	_check_markers()
	var region := layout.get_node_or_null(^"Navigation") as NavigationRegion3D
	_expect(region != null and region.navigation_mesh != null
			and region.navigation_mesh.get_polygon_count() > 0, "layout has a baked navmesh")
	var link := layout.get_node_or_null(^"Mall/StairsLink") as NavigationLink3D
	_expect(link != null and link.navigation_layers == NAV_WALK, "stairs link is on nav layer 1 only")
	if region and link:
		_expect(region.navigation_layers == NAV_WALK | NAV_WHEELCHAIR, "region is on nav layers 1 and 2")
		# 1F foot of the mall stairs.
		var stair_foot := link.get_global_start_position()
		# Regions sync asynchronously; wait until the map has the baked polygons.
		var map := region.get_navigation_map()
		for i in NAV_SYNC_MAX_FRAMES:
			if NavigationServer3D.map_get_iteration_id(map) > 0 					and NavigationServer3D.map_get_closest_point(map, stair_foot) != Vector3.ZERO:
				break
			await _tree.physics_frame
		_check_paths(map, stair_foot)
	layout.queue_free()
	await _tree.process_frame
	await _check_assembly()
	return _ok


func _check_markers() -> void:
	for group: StringName in MARKER_COUNTS:
		var count := _tree.get_nodes_in_group(group).size()
		_expect(count == MARKER_COUNTS[group], "%d markers in %s (want %d)" % [count, group, MARKER_COUNTS[group]])
	var ids: Array[StringName] = []
	for node in _tree.get_nodes_in_group(ExtractPoint.GROUP):
		ids.append((node as ExtractPoint).id)
		if node.id == &"mall_gas_station":
			_expect(node.type == ExtractPoint.Type.GENERATOR and node.wait_sec == 20.0 and node.noise_radius == 25.0,
				"gas station extract is a 20s, 25m generator")
	_expect(ids.size() == EXTRACT_IDS.size() and ids.all(func(i: StringName) -> bool: return i in EXTRACT_IDS),
		"extract ids %s" % [ids])


func _check_paths(map: RID, stair_foot: Vector3) -> void:
	var main := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"main")
	var east := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"east")
	for node in _tree.get_nodes_in_group(ExtractPoint.GROUP):
		var target: Vector3 = node.global_position
		_expect(_reaches(map, main, target, NAV_WALK), "main spawn reaches extract %s" % node.id)
		_expect(_reaches(map, east, target, NAV_WALK), "east spawn reaches extract %s" % node.id)
	# Whole map walkable: every other marker from the north gate.
	for group: StringName in [LootSpot.GROUP, MonsterNest.GROUP, RescueSpot.GROUP, Recording.GROUP]:
		for node in _tree.get_nodes_in_group(group):
			_expect(_reaches(map, main, node.global_position, NAV_WALK), "main spawn reaches %s" % node.name)
	var route := _tree.get_nodes_in_group(HiddenRoute.GROUP)[0] as HiddenRoute
	_expect(_reaches(map, main, route.from_point(), NAV_WALK), "main spawn reaches hidden route From")
	_expect(_reaches(map, main, route.to_point(), NAV_WALK), "main spawn reaches hidden route To")

	# Wheelchair: out of the stuck elevator to the dock, and only by the ramp.
	var wheel := _marker_pos(RescueSpot.GROUP, &"name", &"RescueSpot_rs_wheel")
	var dock := _marker_pos(ExtractPoint.GROUP, &"id", &"mall_dock")
	_expect(_reaches(map, wheel, dock, NAV_WHEELCHAIR), "wheelchair reaches the dock extract from the elevator")
	var walk_len := _path_length(NavigationServer3D.map_get_path(map, wheel, stair_foot, true, NAV_WALK))
	var chair_len := _path_length(NavigationServer3D.map_get_path(map, wheel, stair_foot, true, NAV_WHEELCHAIR))
	_expect(walk_len < WALK_TO_STAIRS_MAX * MAP_SCALE, "walkers take the stairs (%.1fm)" % walk_len)
	_expect(chair_len > walk_len + RAMP_DETOUR_MIN * MAP_SCALE, "wheelchair goes around by the ramp (%.1fm)" % chair_len)


func _check_assembly() -> void:
	var mall := (load(ASSEMBLY) as PackedScene).instantiate() as Node3D
	_tree.root.add_child(mall)
	for i in 5:
		await _tree.process_frame
		await _tree.physics_frame
	var players := _tree.get_nodes_in_group(Player.GROUP)
	_expect(players.size() == 1, "assembly spawns one player")
	if players.size() == 1:
		var spawn := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"main")
		_expect((players[0] as Node3D).global_position.distance_to(spawn) < 1.0, "player starts at the main spawn")
	_expect(_tree.get_nodes_in_group(Monster.GROUP).size() > 0, "monsters spawn at the nests")
	_expect((mall.get_node(^"LootSpawner") as LootSpawner).spawned.size() > 0, "loot containers spawn")
	var extraction := mall.get_node(^"ExtractionManager") as ExtractionManager
	_expect(extraction.active_point_ids().size() == ExtractionManager.ACTIVE_COUNT, "2 of 3 extract points are active")
	var zones := mall.find_children("IndoorZone_*", "Area3D", true, false)
	_expect(zones.size() == 12 and zones.all(func(z: Node) -> bool: return z is IndoorZone and z.building_id != &""),
		"12 indoor zones with building ids (%d)" % zones.size())
	mall.queue_free()
	await _tree.process_frame


func _reaches(map: RID, from: Vector3, to: Vector3, layers: int) -> bool:
	var path := NavigationServer3D.map_get_path(map, from, to, true, layers)
	if path.is_empty():
		return false
	var end := path[path.size() - 1]
	return Vector2(end.x - to.x, end.z - to.z).length() <= REACH and absf(end.y - to.y) < 1.5


func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func _marker_pos(group: StringName, key: StringName, value: Variant) -> Vector3:
	for node in _tree.get_nodes_in_group(group):
		if node.get(key) == value:
			return node.global_position
	_expect(false, "marker %s=%s in %s" % [key, value, group])
	return Vector3.ZERO


func _expect(cond: bool, what: String) -> void:
	if not cond:
		push_error("test_flooded_mall: " + what)
		_ok = false
