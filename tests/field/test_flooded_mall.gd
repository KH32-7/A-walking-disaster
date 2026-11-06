extends RefCounted
## B-12: flooded mall layout. Markers match the confirmed map file, the navmesh reaches every
## marker from the north spawn, every extract point from both spawns, and the wheelchair layer
## leaves the mall's 2F only by the hidden ramp. The assembly spawns the player, monsters and loot,
## roaming packs, activates 2 extract points and has a B-04 IndoorZone per building. The four boss arenas
## (2026-11-06: every boss lives here) are reachable and the BossSpawner puts RegionDef.bosses_per_day
## of them out, asleep, from their first day.

const LAYOUT := "res://levels/field/flooded_mall/layout.tscn"
const ASSEMBLY := "res://levels/field/flooded_mall/flooded_mall.tscn"
const NAV_WALK := 1
const NAV_WHEELCHAIR := 2
const REACH := 1.5 ## path end within this distance (xz) of the target
## Map file markers plus the generator's extras (build_layout.gd EXTRA_NESTS, extra LootSpots):
## loot 19 + 54 (B-26: denser loot) + 9 (B-26: filler scenes in dead space; the boss arenas keep two
## fillers out since 2026-11-06), nests 3 + 3.
const MARKER_COUNTS := {
	PlayerSpawn.GROUP: 2, ExtractPoint.GROUP: 3, LootSpot.GROUP: 82, MonsterNest.GROUP: 6,
	RescueSpot.GROUP: 8, HiddenRoute.GROUP: 1, Recording.GROUP: 2, BossArena.GROUP: 4,
}
const EXTRACT_IDS := [&"mall_dock", &"mall_gas_station", &"mall_north_gate"]
const BOSS_IDS := [&"sunken_sign_serpent", &"surgical_lamp_wraith", &"neon_colossus", &"breakwater_golem"]
const NAV_SYNC_MAX_FRAMES := 300
## Nest interval after the generator's NEST_INTERVAL_MULT (map file 180s).
const NEST_INTERVAL := 60.0
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
	for node in _tree.get_nodes_in_group(MonsterNest.GROUP):
		_expect(is_equal_approx(node.spawn_interval_sec, NEST_INTERVAL), "nest %s spawns every %ds (%.1f)" % [
			node.name, NEST_INTERVAL, node.spawn_interval_sec])
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
	for group: StringName in [LootSpot.GROUP, MonsterNest.GROUP, RescueSpot.GROUP, Recording.GROUP, BossArena.GROUP]:
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
	var saved_respawn := FieldState.boss_respawn_day.duplicate()
	var saved_day := GameState.day
	FieldState.boss_respawn_day = {}
	GameState.day = BossDef.for_monster(BOSS_IDS[0]).first_day
	var mall := (load(ASSEMBLY) as PackedScene).instantiate() as Node3D
	_tree.root.add_child(mall)
	for i in 5:
		await _tree.process_frame
		await _tree.physics_frame
	var bosses: Array[StringName] = []
	for node in _tree.get_nodes_in_group(BossMonster.BOSS_GROUP):
		bosses.append((node as BossMonster).def.id)
		_expect((node as BossMonster).state == Enums.AIState.SLEEP, "%s starts asleep" % node.name)
	var per_day := RegionDef.load_def(&"flooded_mall").bosses_per_day
	_expect(per_day >= 1 and bosses.size() == per_day and bosses.all(func(id: StringName) -> bool: return id in BOSS_IDS),
			"the mall's BossSpawner puts %d of its four bosses out %s" % [per_day, bosses])
	GameState.day = saved_day
	FieldState.boss_respawn_day = saved_respawn
	var players := _tree.get_nodes_in_group(Player.GROUP)
	_expect(players.size() == 1, "assembly spawns one player")
	if players.size() == 1:
		var spawn := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"main")
		_expect((players[0] as Node3D).global_position.distance_to(spawn) < 1.0, "player starts at the main spawn")
	_expect(_tree.get_nodes_in_group(Monster.GROUP).size() > 0, "monsters spawn at the nests")
	var roaming := mall.get_node_or_null(^"RoamingSpawner") as RoamingSpawner
	_expect(roaming != null, "roaming spawner in the assembly")
	if roaming:
		# Start packs wait for the navigation map to sync.
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
	_expect((mall.get_node(^"LootSpawner") as LootSpawner).spawned.size() > 0, "loot containers spawn")
	var extraction := mall.get_node(^"ExtractionManager") as ExtractionManager
	_expect(extraction.active_point_ids().size() == ExtractionManager.ACTIVE_COUNT, "2 of 3 extract points are active")
	_expect(mall.get_node_or_null(^"CompanionManager") is CompanionManager, "companion manager (B-17) in the assembly")
	var zones := mall.find_children("IndoorZone_*", "Area3D", true, false)
	_expect(zones.size() == 12 and zones.all(func(z: Node) -> bool: return z is IndoorZone and z.building_id != &""),
		"12 indoor zones with building ids (%d)" % zones.size())
	_check_hide_above(mall.find_child("IndoorZone_shop_in", true, false) as IndoorZone)
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


## Things on the 2F (loot containers) hide with the 1F zone's roofs; things on the 1F stay
## (user report 2026-11-06: 2F cabinets floated over the 1F).
func _check_hide_above(zone: IndoorZone) -> void:
	_expect(zone != null, "mall 1F indoor zone")
	if zone == null:
		return
	var cs := zone.find_child("*", true, false) as CollisionShape3D
	var pts := (cs.shape as ConvexPolygonShape3D).points
	var c := Vector3.ZERO
	var top := -INF
	for v in pts:
		var g := cs.global_transform * v
		c += g
		top = maxf(top, g.y)
	c /= pts.size()
	var upper := Node3D.new()
	var lower := Node3D.new()
	for n in [upper, lower]:
		n.add_to_group(IndoorZone.ABOVE_GROUP)
		zone.get_tree().root.add_child(n)
	upper.global_position = Vector3(c.x, top + 0.3, c.z)
	lower.global_position = Vector3(c.x, 0.1, c.z)
	zone.set_roofs_hidden(true)
	_expect(not upper.visible and lower.visible, "2F things hide with the 1F roofs, 1F things stay")
	zone.set_roofs_hidden(false)
	_expect(upper.visible, "2F things come back with the roofs")
	upper.free()
	lower.free()
