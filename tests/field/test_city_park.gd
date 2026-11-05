extends RefCounted
## B-24: city park layout. Markers match the confirmed map file plus the generator's extras, the
## boss arena keeps its real radius, the navmesh reaches every marker and extract point, the old
## underpass is a real tunnel (both mouths and the gate point on nav layers 1 and 2), and the
## first sortie route fits its time budget. The assembly spawns the player, monsters, loot and
## roaming packs, activates 2 extract points, closes the underpass gate and has an IndoorZone per
## building plus the underpass.

const LAYOUT := "res://levels/field/city_park/layout.tscn"
const ASSEMBLY := "res://levels/field/city_park/city_park.tscn"
const MAP_FILE := "res://levels/field/city_park/build/city_park_map.json"
const BUILDER := preload("res://levels/field/city_park/build/build_layout.gd")
const MAP_SCALE: float = BUILDER.MAP_SCALE
const NAV_WALK := 1
const NAV_WHEELCHAIR := 2
const REACH := 1.5 ## path end within this distance (xz) of the target
## Map file markers plus the generator's extras (build_layout.gd EXTRA_NESTS, extra LootSpots):
## loot 12 + 18 (3 nests, greenhouse and landmarks; B-26 halved the m2 per indoor spot)
## + 11 (B-26 filler scenes in dead space), nests 3 + 3.
const MARKER_COUNTS := {
	PlayerSpawn.GROUP: 2, ExtractPoint.GROUP: 3, LootSpot.GROUP: 41, MonsterNest.GROUP: 6,
	RescueSpot.GROUP: 3, HiddenRoute.GROUP: 1, Recording.GROUP: 2, BossArena.GROUP: 1,
}
const EXTRACT_IDS := [&"park_south_gate", &"park_east_bus", &"park_north_gate"]
const NAV_SYNC_MAX_FRAMES := 300
const NEST_INTERVAL := 120.0
## 5 buildings and the underpass.
const INDOOR_ZONES := 6
const WALK_SPEED := 4.5

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
	if region:
		_expect(region.navigation_layers == NAV_WALK | NAV_WHEELCHAIR, "region is on nav layers 1 and 2")
		var map := region.get_navigation_map()
		var main := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"main")
		for i in NAV_SYNC_MAX_FRAMES:
			if NavigationServer3D.map_get_iteration_id(map) > 0 \
					and NavigationServer3D.map_get_closest_point(map, main) != Vector3.ZERO:
				break
			await _tree.physics_frame
		_check_paths(map)
		_check_underpass(map)
		_check_sortie_time(map)
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
		if node.id == &"park_north_gate":
			_expect(node.type == ExtractPoint.Type.KEY, "north gate extract needs a key")
	_expect(ids.size() == EXTRACT_IDS.size() and ids.all(func(i: StringName) -> bool: return i in EXTRACT_IDS),
		"extract ids %s" % [ids])
	for node in _tree.get_nodes_in_group(MonsterNest.GROUP):
		_expect(is_equal_approx(node.spawn_interval_sec, NEST_INTERVAL), "nest %s spawns every %ds (%.1f)" % [
			node.name, NEST_INTERVAL, node.spawn_interval_sec])
		_expect(node.family == Enums.Element.GREEN, "nest %s is GREEN (danger 1 park)" % node.name)
	var arenas := _tree.get_nodes_in_group(BossArena.GROUP)
	if arenas.size() == 1:
		var arena := arenas[0] as BossArena
		_expect(arena.boss_id == &"ancient_tree_giant", "boss arena boss_id %s" % arena.boss_id)
		# Radius is a design value and does not scale; the center moves with the plan.
		_expect(is_equal_approx(arena.radius, 18.0), "boss arena radius 18m (%.1f)" % arena.radius)
		_expect(arena.global_position.distance_to(Vector3(-3.0, 0.0, -35.0) * MAP_SCALE) < 0.01,
			"boss arena at the plaza center")


func _check_paths(map: RID) -> void:
	var main := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"main")
	var east := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"east")
	for node in _tree.get_nodes_in_group(ExtractPoint.GROUP):
		var target: Vector3 = node.global_position
		_expect(_reaches(map, main, target, NAV_WALK), "main spawn reaches extract %s" % node.id)
		_expect(_reaches(map, east, target, NAV_WALK), "east spawn reaches extract %s" % node.id)
		_expect(_reaches(map, main, target, NAV_WHEELCHAIR), "wheelchair reaches extract %s" % node.id)
	# Whole map walkable: every other marker from the main gate.
	for group: StringName in [LootSpot.GROUP, MonsterNest.GROUP, RescueSpot.GROUP, Recording.GROUP]:
		for node in _tree.get_nodes_in_group(group):
			_expect(_reaches(map, main, node.global_position, NAV_WALK), "main spawn reaches %s" % node.name)
	var arena := _tree.get_nodes_in_group(BossArena.GROUP)
	if arena.size() == 1:
		_expect(_reaches(map, main, (arena[0] as Node3D).global_position, NAV_WALK), "main spawn reaches the boss arena")


## Both mouths from the surface, and the gate point on the tunnel floor from each mouth.
func _check_underpass(map: RID) -> void:
	var routes := _tree.get_nodes_in_group(HiddenRoute.GROUP)
	if routes.size() != 1:
		return
	var route := routes[0] as HiddenRoute
	_expect(route.id == &"park_old_underpass" and route.required_trait == &"ELDER", "underpass route data")
	var main := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"main")
	var gate := route.get_node_or_null(^"Gate") as Node3D
	_expect(gate != null, "underpass marker has a Gate point for B-20")
	if gate == null:
		return
	var floor_point := Vector3(gate.global_position.x, BUILDER.UNDERPASS_FLOOR_Y, gate.global_position.z)
	for layers: int in [NAV_WALK, NAV_WHEELCHAIR]:
		_expect(_reaches(map, main, route.from_point(), layers), "reach the south mouth (layers %d)" % layers)
		_expect(_reaches(map, main, route.to_point(), layers), "reach the north mouth (layers %d)" % layers)
		_expect(_reaches(map, route.from_point(), floor_point, layers), "south mouth leads into the tunnel (layers %d)" % layers)
		_expect(_reaches(map, route.to_point(), floor_point, layers), "north mouth leads into the tunnel (layers %d)" % layers)


## Map file sortie 1: walk the demo route on the navmesh, add the activities, stay in budget.
func _check_sortie_time(map: RID) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_FILE))
	var sortie: Dictionary = data.sorties[0]
	var route: Dictionary = data.demo_routes[0]
	var length := 0.0
	var pts: Array = route.points
	for i in range(1, pts.size()):
		var a := Vector3(pts[i - 1][0], pts[i - 1][1], pts[i - 1][2]) * Vector3(MAP_SCALE, 1.0, MAP_SCALE)
		var b := Vector3(pts[i][0], pts[i][1], pts[i][2]) * Vector3(MAP_SCALE, 1.0, MAP_SCALE)
		length += _path_length(NavigationServer3D.map_get_path(map, a, b, true, NAV_WALK))
	var total := length / WALK_SPEED + float(sortie.activity_sec)
	_expect(total <= float(sortie.budget_sec), "sortie 1 takes %.0fs (%.0fm), budget %ds" % [
		total, length, sortie.budget_sec])


func _check_assembly() -> void:
	var park := (load(ASSEMBLY) as PackedScene).instantiate() as Node3D
	_tree.root.add_child(park)
	for i in 5:
		await _tree.process_frame
		await _tree.physics_frame
	var players := _tree.get_nodes_in_group(Player.GROUP)
	_expect(players.size() == 1, "assembly spawns one player")
	if players.size() == 1:
		var spawn := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"main")
		_expect((players[0] as Node3D).global_position.distance_to(spawn) < 1.0, "player starts at the main spawn")
	_expect(_tree.get_nodes_in_group(Monster.GROUP).size() > 0, "monsters spawn at the nests")
	var roaming := park.get_node_or_null(^"RoamingSpawner") as RoamingSpawner
	_expect(roaming != null, "roaming spawner in the assembly")
	if roaming:
		for i in NAV_SYNC_MAX_FRAMES:
			if roaming.alive_count() > 0:
				break
			await _tree.physics_frame
		var packs := {}
		for m in roaming.alive():
			packs[m.pack] = m.home
		_expect(packs.size() == MonsterRules.ROAM_START_GROUPS, "%d roaming packs on the map (%d)" % [
			MonsterRules.ROAM_START_GROUPS, packs.size()])
		_expect(packs.values().all(func(h: Vector3) -> bool: return h != Vector3.ZERO and h.y < MonsterRules.ROAM_MAX_Y),
			"roaming packs start on real navmesh points %s" % [packs.values()])
	var loot := park.get_node(^"LootSpawner") as LootSpawner
	_expect(loot.spawned.size() > 0, "loot containers spawn")
	for c in loot.spawned:
		_expect(c.loot_table != null and c.loot_table.region_id == &"city_park",
			"container %s uses a park loot table" % c.name)
	var extraction := park.get_node(^"ExtractionManager") as ExtractionManager
	_expect(extraction.active_point_ids().size() == ExtractionManager.ACTIVE_COUNT, "2 of 3 extract points are active")
	_expect(park.get_node_or_null(^"CompanionManager") is CompanionManager, "companion manager (B-17) in the assembly")
	var gates := park.get_node(^"HiddenRouteManager") as HiddenRouteManager
	_expect(gates.gate_of(&"park_old_underpass") != null, "underpass starts closed")
	_expect(gates.gate_width > BUILDER.UNDERPASS_W, "gate spans the tunnel (%.1fm)" % gates.gate_width)
	var zones := park.find_children("IndoorZone_*", "Area3D", true, false)
	_expect(zones.size() == INDOOR_ZONES and zones.all(func(z: Node) -> bool: return z is IndoorZone and z.building_id != &""),
		"%d indoor zones with building ids (%d)" % [INDOOR_ZONES, zones.size()])
	park.queue_free()
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
		push_error("test_city_park: " + what)
		_ok = false
