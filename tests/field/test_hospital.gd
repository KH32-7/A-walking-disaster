extends RefCounted
## Hospital layout and assembly (levels/field/hospital). Markers match the map file plus the generator's
## extras, the boss arena sits in the operating theatre, the navmesh reaches every marker and extract
## point on foot and by wheelchair, the tunnel floor is reached from both mouths, and the quarantine wall
## really cuts the back yard off (the way round is long). The assembly spawns the player, monsters of the
## region's families, loot from the hospital tables and roaming packs, activates 2 extract points, closes
## the wall gap (hidden route) and puts the surgical lamp wraith out, asleep, from its first day.

const LAYOUT := "res://levels/field/hospital/layout.tscn"
const ASSEMBLY := "res://levels/field/hospital/hospital.tscn"
const MAP_FILE := "res://levels/field/hospital/build/hospital_map.json"
const BUILDER := preload("res://levels/field/hospital/build/build_layout.gd")
const CityKit := preload("res://field/buildings/city_kit.gd")
const MAP_SCALE: float = BUILDER.MAP_SCALE
const NAV_WALK := 1
const NAV_WHEELCHAIR := 2
const REACH := 1.5 ## path end within this distance (xz) of the target
## Map file markers plus the generator's extras: loot 9 (crates and nest spots) + 87 furniture
## containers (build/kit_buildings.gd loot) + 7 (4 extra nests, garden) + 13 (filler scenes)
## + 6 (bay, plaza, car park by hand), nests 4 + 4.
const MARKER_COUNTS := {
	PlayerSpawn.GROUP: 2, ExtractPoint.GROUP: 3, LootSpot.GROUP: 122, MonsterNest.GROUP: 8,
	RescueSpot.GROUP: 7, HiddenRoute.GROUP: 1, Recording.GROUP: 2, BossArena.GROUP: 1,
}
const EXTRACT_IDS := [&"hospital_main_gate", &"hospital_generator", &"hospital_north_gate"]
const NAV_SYNC_MAX_FRAMES := 300
const NEST_INTERVAL := 60.0
## 7 buildings and the tunnel.
const INDOOR_ZONES := 8
const TUNNEL_FLOOR_Y := -4.0
## Either side of the quarantine wall, east of the surgery wing (world metres).
const WALL_SOUTH := Vector3(40.0, 0.0, -45.0)
const WALL_NORTH := Vector3(40.0, 0.0, -60.0)
const WALL_DETOUR_MIN := 60.0
## Families of data/regions/hospital.tres.
const FAMILIES := [Enums.Element.WATER, Enums.Element.LIGHT]
const BOSS_ID := &"surgical_lamp_wraith"
## Furniture containers (kit plans' loot): all of them spawn, each with its room table.
const FURNITURE := 87

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
		_check_tunnel(map)
		_check_wall(map)
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
		if node.id == &"hospital_generator":
			_expect(node.type == ExtractPoint.Type.GENERATOR, "boiler room extract needs the generator")
	_expect(ids.size() == EXTRACT_IDS.size() and ids.all(func(i: StringName) -> bool: return i in EXTRACT_IDS),
		"extract ids %s" % [ids])
	for node in _tree.get_nodes_in_group(MonsterNest.GROUP):
		_expect(is_equal_approx(node.spawn_interval_sec, NEST_INTERVAL), "nest %s spawns every %ds (%.1f)" % [
			node.name, NEST_INTERVAL, node.spawn_interval_sec])
		_expect(node.family in FAMILIES, "nest %s is WATER or LIGHT (%d)" % [node.name, node.family])
	var supply := 0
	for node in _tree.get_nodes_in_group(LootSpot.GROUP):
		if (node as LootSpot).container_type == LootSpot.ContainerType.SUPPLY_CRATE:
			supply += 1
			_expect(_near_danger((node as Node3D).global_position), "supply crate %s is near a nest or the boss" % node.name)
	_expect(supply >= 4, "at least 4 supply crates (%d)" % supply)
	var arenas := _tree.get_nodes_in_group(BossArena.GROUP)
	if arenas.size() == 1:
		var arena := arenas[0] as BossArena
		_expect(arena.boss_id == BOSS_ID, "boss arena boss_id %s" % arena.boss_id)
		_expect(arena.global_position.distance_to(Vector3(0.0, 0.0, -42.0)) < 0.01, "boss arena in the operating theatre")


## Within 20 m (layout_builder SUPPLY_DANGER_RADIUS) of a nest or the boss arena.
func _near_danger(p: Vector3) -> bool:
	for group: StringName in [MonsterNest.GROUP, BossArena.GROUP]:
		for node in _tree.get_nodes_in_group(group):
			if Vector2(p.x, p.z).distance_to(Vector2((node as Node3D).global_position.x, (node as Node3D).global_position.z)) \
					< BUILDER.SUPPLY_DANGER_RADIUS:
				return true
	return false


func _check_paths(map: RID) -> void:
	var main := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"main")
	var east := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"east")
	for node in _tree.get_nodes_in_group(ExtractPoint.GROUP):
		var target: Vector3 = node.global_position
		_expect(_reaches(map, main, target, NAV_WALK), "main spawn reaches extract %s" % node.id)
		_expect(_reaches(map, east, target, NAV_WALK), "east spawn reaches extract %s" % node.id)
		_expect(_reaches(map, main, target, NAV_WHEELCHAIR), "wheelchair reaches extract %s" % node.id)
	for group: StringName in [LootSpot.GROUP, MonsterNest.GROUP, RescueSpot.GROUP, Recording.GROUP, BossArena.GROUP]:
		for node in _tree.get_nodes_in_group(group):
			# Furniture stands in its own collision: reaching its side is enough.
			var reach := REACH
			if node is LootSpot and (node as LootSpot).look_piece != &"":
				var size: Vector3 = CityKit.PROPS[(node as LootSpot).look_piece][2]
				reach += maxf(size.x, size.z) * 0.5
			_expect(_reaches(map, main, node.global_position, NAV_WALK, reach), "main spawn reaches %s" % node.name)
	# The trapped wheelchair user in the isolation room gets out to the main gate.
	for node in _tree.get_nodes_in_group(RescueSpot.GROUP):
		if &"isolation" in (node as RescueSpot).spawn_tags:
			var gate := Vector3.ZERO
			for ex in _tree.get_nodes_in_group(ExtractPoint.GROUP):
				if ex.id == &"hospital_main_gate":
					gate = ex.global_position
			_expect(_reaches(map, node.global_position, gate, NAV_WHEELCHAIR), "wheelchair from the isolation room to the main gate")


## Both mouths from the surface and the floor from each mouth, on foot and by wheelchair.
func _check_tunnel(map: RID) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_FILE))
	var link: Dictionary = {}
	for l: Dictionary in data.floor_links:
		if l.kind == "tunnel":
			link = l
	_expect(not link.is_empty(), "map file has the tunnel link")
	if link.is_empty():
		return
	var a := Vector3(link.from.position[0] * MAP_SCALE, 0.0, link.from.position[2] * MAP_SCALE)
	var b := Vector3(link.to.position[0] * MAP_SCALE, 0.0, link.to.position[2] * MAP_SCALE)
	var floor_point := (a + b) * 0.5 + Vector3(0.0, TUNNEL_FLOOR_Y, 0.0)
	var main := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"main")
	for layers: int in [NAV_WALK, NAV_WHEELCHAIR]:
		_expect(_reaches(map, main, a, layers), "reach the south mouth (layers %d)" % layers)
		_expect(_reaches(map, main, b, layers), "reach the north mouth (layers %d)" % layers)
		_expect(_reaches(map, a, floor_point, layers), "south mouth leads down to the floor (layers %d)" % layers)
		_expect(_reaches(map, b, floor_point, layers), "north mouth leads down to the floor (layers %d)" % layers)


## The quarantine wall cuts the back yard off: 15 m apart across it (east of the surgery wing), the
## way round (through the surgery wing, the tunnel or the west road) is far longer.
func _check_wall(map: RID) -> void:
	var path := _path(map, WALL_SOUTH, WALL_NORTH, NAV_WALK)
	var length := _path_length(path)
	_expect(_reaches(map, WALL_SOUTH, WALL_NORTH, NAV_WALK), "back yard is reachable from the hospital side")
	_expect(length > WALL_DETOUR_MIN, "the wall makes the way round long (%.0fm, straight %.0fm)" % [
		length, WALL_SOUTH.distance_to(WALL_NORTH)])


func _check_assembly() -> void:
	var saved_respawn := FieldState.boss_respawn_day.duplicate()
	var saved_day := GameState.day
	FieldState.boss_respawn_day = {}
	GameState.day = BossDef.for_monster(BOSS_ID).first_day
	var hospital := (load(ASSEMBLY) as PackedScene).instantiate() as Node3D
	_tree.root.add_child(hospital)
	for i in 5:
		await _tree.process_frame
		await _tree.physics_frame
	var bosses: Array[StringName] = []
	for node in _tree.get_nodes_in_group(BossMonster.BOSS_GROUP):
		bosses.append((node as BossMonster).def.id)
		_expect((node as BossMonster).state == Enums.AIState.SLEEP, "%s starts asleep" % node.name)
	_expect(bosses == [BOSS_ID], "the hospital's BossSpawner puts the wraith out %s" % [bosses])
	GameState.day = saved_day
	FieldState.boss_respawn_day = saved_respawn
	var players := _tree.get_nodes_in_group(Player.GROUP)
	_expect(players.size() == 1, "assembly spawns one player")
	if players.size() == 1:
		var spawn := _marker_pos(PlayerSpawn.GROUP, &"spawn_id", &"main")
		_expect((players[0] as Node3D).global_position.distance_to(spawn) < 1.0, "player starts at the main spawn")
	var monsters := _tree.get_nodes_in_group(Monster.GROUP).filter(func(m: Node) -> bool: return not m is BossMonster)
	_expect(monsters.size() > 0, "monsters spawn at the nests")
	_expect(monsters.all(func(m: Node) -> bool: return (m as Monster).def.family in FAMILIES),
		"every spawned monster is WATER or LIGHT")
	var roaming := hospital.get_node_or_null(^"RoamingSpawner") as RoamingSpawner
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
	var loot := hospital.get_node(^"LootSpawner") as LootSpawner
	_expect(loot.spawned.size() > 0, "loot containers spawn")
	var furniture := 0
	for c in loot.spawned:
		_expect(c.loot_table != null and String(c.loot_table.id).begins_with("hospital_"),
			"container %s uses a hospital loot table" % c.name)
		if c.look_piece != &"":
			furniture += 1
			_expect(c.loot_table.region_id == &"" and LootData.table(c.loot_table.id) == c.loot_table,
				"furniture %s (%s) uses its room table %s" % [c.name, c.look_piece, c.loot_table.id])
	_expect(furniture == FURNITURE, "every furniture container spawns (%d of %d)" % [furniture, FURNITURE])
	# A pharmacy shelf opens like any container (open time from its kind, contents from its room).
	var shelves := loot.spawned.filter(func(c: LootContainer) -> bool: return c.look_piece == &"shelf_02" 			and c.loot_table.id == &"hospital_pharmacy")
	_expect(not shelves.is_empty() and players.size() == 1, "a pharmacy shelf container")
	if not shelves.is_empty() and players.size() == 1:
		var shelf := shelves[0] as LootContainer
		var who := players[0] as Node3D
		who.global_position = shelf.global_position + Vector3(1.0, 0.0, 0.0)
		_expect(shelf.begin_open(who), "the shelf starts opening")
		for i in 100:
			shelf.advance(0.1)
		_expect(shelf.state == LootContainer.State.OPEN, "the shelf is open (%d)" % shelf.state)
	var extraction := hospital.get_node(^"ExtractionManager") as ExtractionManager
	_expect(extraction.active_point_ids().size() == ExtractionManager.ACTIVE_COUNT, "2 of 3 extract points are active")
	var gates := hospital.get_node(^"HiddenRouteManager") as HiddenRouteManager
	_expect(gates.gate_of(&"hospital_quarantine_gap") != null, "the wall gap starts closed")
	var zones := hospital.find_children("IndoorZone_*", "Area3D", true, false)
	_expect(zones.size() == INDOOR_ZONES and zones.all(func(z: Node) -> bool: return z is IndoorZone and z.building_id != &""),
		"%d indoor zones with building ids (%d)" % [INDOOR_ZONES, zones.size()])
	hospital.queue_free()
	await _tree.process_frame


func _reaches(map: RID, from: Vector3, to: Vector3, layers: int, reach := REACH) -> bool:
	var path := _path(map, from, to, layers)
	if path.is_empty():
		return false
	var end := path[path.size() - 1]
	return Vector2(end.x - to.x, end.z - to.z).length() <= reach and absf(end.y - to.y) < 1.5


## Full path search: the map has more polygons than the default search budget (4096), so the long
## walks (east spawn to the north-west gate) would stop short.
func _path(map: RID, from: Vector3, to: Vector3, layers: int) -> PackedVector3Array:
	var query := NavigationPathQueryParameters3D.new()
	query.map = map
	query.start_position = from
	query.target_position = to
	query.navigation_layers = layers
	query.path_search_max_polygons = 0
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	return result.path


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
		push_error("test_hospital: " + what)
		_ok = false
