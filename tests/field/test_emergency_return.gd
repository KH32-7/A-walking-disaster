extends Node
## B-22 emergency return. A day raid warning (or a day raid without warning) asks once,
## night raids do not. "Go back" picks the nearest usable active point (navmesh path length,
## straight line without one), sets wait to 0 s, emits emergency_return_requested, keeps a route
## and marks the compass. The sortie result says emergency_return.
## (docs/design/10-raids-defense.md "출격 중 습격과 긴급 귀환", 02-field.md "탈출")

const PLAYER_SCENE := preload("res://field/player/player.tscn")
const DT := 1.0 / 60.0

var _ok := true
var _root: Node3D
var _player: Node3D
var _manager: ExtractionManager
var _emergency: EmergencyReturn
var _points := {}
var _offers: Array = []
var _requested := 0
var _regions: Array[RID] = []


func run() -> bool:
	_ok = true
	var bag_before := Bag.save_data()
	var economy_before := Economy.save_data()
	EventBus.emergency_return_requested.connect(_on_requested)

	_test_offer_rules()
	_test_decline()
	_test_go_back_straight_line()
	_test_item_points()
	_test_zero_wait_result()
	_test_offer_after_done()
	await _test_navmesh_path()
	await _test_compass_marker()

	_teardown()
	_clear_navmesh()
	FieldState.set_sortie_result({})
	EventBus.emergency_return_requested.disconnect(_on_requested)
	Bag.load_data(bag_before)
	Economy.load_data(economy_before)
	return _ok


# --- Setup ---

## Points by id: [position, type]. The player is a plain Node3D unless `player` is given.
func _setup(spots: Dictionary, player: Node3D = null) -> void:
	_teardown()
	_offers.clear()
	_requested = 0
	Bag.load_data({})
	_root = Node3D.new()
	_root.name = "EmergencyTestRoot"
	add_child(_root)
	_points.clear()
	for id: StringName in spots:
		var p := ExtractPoint.new()
		p.id = id
		p.position = spots[id][0]
		p.type = spots[id][1]
		p.wait_sec = 20.0 if p.type == ExtractPoint.Type.GENERATOR else 5.0
		_root.add_child(p)
		_points[id] = p
	_player = player if player != null else Node3D.new()
	if not _player.is_in_group(Player.GROUP):
		_player.add_to_group(Player.GROUP)
	_root.add_child(_player)
	_manager = ExtractionManager.new()
	_manager.auto_activate = false
	_manager.region_id = &"test_region"
	_root.add_child(_manager)
	_manager.set_physics_process(false)
	_emergency = _manager.get_node(^"EmergencyReturn") as EmergencyReturn
	_emergency.set_physics_process(false)
	_emergency.return_offered.connect(func(raid: Dictionary): _offers.append(raid))
	# All candidates active (ACTIVE_COUNT is 2, the tests use at most 2).
	_manager.activate(0)


func _teardown() -> void:
	if _root != null:
		_root.free()
		_root = null


func _two_normal() -> Dictionary:
	return {
		&"ex_near": [Vector3(8, 0, 0), ExtractPoint.Type.NORMAL],
		&"ex_far": [Vector3(-20, 0, 0), ExtractPoint.Type.NORMAL],
	}


func _raid(time: Enums.RaidTime) -> Dictionary:
	return {"occurs": true, "raid_id": &"test_raid", "time": time, "type": &"swarm",
		"directions": [&"west"], "strength": 30.0, "target": &"base", "warning_sec": 60.0}


func _on_requested() -> void:
	_requested += 1


# --- Tests ---

func _test_offer_rules() -> void:
	_setup(_two_normal())
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.NIGHT))
	_check(_offers.is_empty(), "night raid warning does not ask")
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	_check(_offers.size() == 1 and _emergency.state == EmergencyReturn.State.OFFERED, "day raid warning asks")
	_check(not _offers.is_empty() and _offers[0].get("raid_id") == &"test_raid", "offer carries the raid info")
	EventBus.raid_started.emit(_raid(Enums.RaidTime.DAY))
	_check(_offers.size() == 1, "raid_started after the warning does not ask again")

	_setup(_two_normal())
	EventBus.raid_started.emit(_raid(Enums.RaidTime.DAY))
	_check(_offers.size() == 1, "day raid without warning asks on raid_started")


func _test_decline() -> void:
	_setup(_two_normal())
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	_emergency.answer(false)
	_check(_emergency.state == EmergencyReturn.State.DECLINED, "keep exploring")
	_check(_requested == 0 and is_equal_approx(_manager.wait_multiplier, 1.0), "declining changes nothing")
	_check(_emergency.target_point_id() == &"" and _emergency.route().is_empty(), "no target, no route")
	_emergency.answer(true)
	_check(_requested == 0, "answering twice does nothing")


func _test_go_back_straight_line() -> void:
	_setup(_two_normal())
	_emergency.answer(true)
	_check(_requested == 0, "answer without an offer does nothing")
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	var routes: Array = []
	_emergency.route_changed.connect(func(points: PackedVector3Array): routes.append(points))
	_emergency.answer(true)
	_check(_requested == 1, "emergency_return_requested sent once")
	_check(_manager.wait_multiplier == 0.0, "wait is 0 s")
	_check(_emergency.target_point_id() == &"ex_near", "nearest point without a navmesh: straight line")
	var route := _emergency.route()
	_check(route.size() == 2 and route[1].is_equal_approx(_points[&"ex_near"].global_position),
		"route without a navmesh is player to point")
	_check(routes.size() == 1, "route_changed on start")
	_emergency.tick(DT)
	_check(routes.size() == 1, "no repath before REPATH_SEC")
	_player.position = Vector3(2, 0, 0)
	_emergency.tick(EmergencyReturn.REPATH_SEC)
	_check(routes.size() == 2 and _emergency.route()[0].is_equal_approx(Vector3(2, 0, 0)), "route follows the player")


func _test_item_points() -> void:
	var spots := {
		&"ex_key": [Vector3(5, 0, 0), ExtractPoint.Type.KEY],
		&"ex_gen": [Vector3(-15, 0, 0), ExtractPoint.Type.GENERATOR],
	}
	_setup(spots)
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	_emergency.answer(true)
	_check(_emergency.target_point_id() == &"ex_gen", "key point without a key is skipped")

	_setup(spots)
	Bag.try_add(&"key", 1)
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	_emergency.answer(true)
	_check(_emergency.target_point_id() == &"ex_key", "key point with a key is used")

	_setup({
		&"ex_key": [Vector3(5, 0, 0), ExtractPoint.Type.KEY],
		&"ex_bat": [Vector3(-15, 0, 0), ExtractPoint.Type.BATTERY],
	})
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	_emergency.answer(true)
	_check(_emergency.target_point_id() == &"ex_key", "nothing usable: nearest anyway")


func _test_zero_wait_result() -> void:
	_setup(_two_normal())
	var completed: Array = []
	var on_completed := func(point_id: StringName): completed.append(point_id)
	EventBus.extraction_completed.connect(on_completed)
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	_emergency.answer(true)
	_player.position = _points[&"ex_near"].position
	_manager.tick(DT)
	EventBus.extraction_completed.disconnect(on_completed)
	_check(completed == [&"ex_near"], "extracts on the first tick at the point")
	var result := FieldState.last_sortie_result()
	_check(result.get("extracted") == true and result.get("emergency_return") == true, "result says emergency_return")

	# A generator point extracts at once too.
	_setup({&"ex_gen": [Vector3(4, 0, 0), ExtractPoint.Type.GENERATOR]})
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	_emergency.answer(true)
	_player.position = _points[&"ex_gen"].position
	_manager.tick(DT)
	_check(_manager.state == ExtractionManager.State.DONE, "generator point: 0 s too")

	_setup(_two_normal())
	_player.position = _points[&"ex_near"].position
	for i in 400:
		_manager.tick(DT)
	_check(FieldState.last_sortie_result().get("emergency_return") == false, "normal extraction: emergency_return false")


func _test_offer_after_done() -> void:
	_setup(_two_normal())
	_manager._on_player_downed()
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	_check(_offers.is_empty(), "no offer after the sortie ended")

	_setup(_two_normal())
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	_manager._on_player_downed()
	_emergency.answer(true)
	_check(_requested == 0 and _emergency.state == EmergencyReturn.State.DECLINED, "answer after going down does nothing")


## Two floor strips joined at the far end. ex_across is closer in a straight line but the walk
## goes round; ex_ahead is the shorter walk.
func _test_navmesh_path() -> void:
	await _bake_u_floor()
	_setup({
		&"ex_across": [Vector3(0, 0, 6), ExtractPoint.Type.NORMAL],
		&"ex_ahead": [Vector3(10, 0, 0), ExtractPoint.Type.NORMAL],
	})
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	_emergency.answer(true)
	_check(_emergency.target_point_id() == &"ex_ahead", "navmesh: shorter walk wins over straight line")
	var route := _emergency.route()
	_check(route.size() >= 2 and route[route.size() - 1].distance_to(Vector3(10, 0, 0)) < 1.0,
		"route ends at the point (%s)" % [route])
	var across := _emergency._path_cost(Vector3.ZERO, Vector3(0, 0, 6))
	_check(across > 30.0, "walk to ex_across goes round (%.1f m)" % across)
	_clear_navmesh()


func _test_compass_marker() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.set_physics_process(false)
	_setup(_two_normal(), player)
	var markers: Array = player.hud_state().get("compass_markers", [])
	_check(markers.size() == 2 and markers.all(func(m): return not m.has("emergency")), "no emergency mark before")
	EventBus.raid_warning.emit(_raid(Enums.RaidTime.DAY))
	_emergency.answer(true)
	markers = player.hud_state().get("compass_markers", [])
	var marked := markers.filter(func(m): return m.get("emergency", false))
	_check(marked.size() == 1, "one compass marker is the emergency target")
	_check(markers.all(func(m): return m.get("kind") == &"extract"), "kind stays extract")
	await get_tree().process_frame


# --- Navmesh helpers (same approach as test_rescue) ---

func _bake_u_floor() -> void:
	_clear_navmesh()
	var map := get_viewport().world_3d.navigation_map
	# Headless --script runs start with the navigation server off.
	NavigationServer3D.set_active(true)
	NavigationServer3D.map_set_active(map, true)
	var source := NavigationMeshSourceGeometryData3D.new()
	for b: Array in [
		[Vector3(24, 0.2, 4), Vector3(10, -0.1, 0)],   # strip z -2..2
		[Vector3(24, 0.2, 4), Vector3(10, -0.1, 6)],   # strip z 4..8
		[Vector3(4, 0.2, 4), Vector3(20, -0.1, 3)],    # joint at x 18..22
	]:
		var mesh := BoxMesh.new()
		mesh.size = b[0]
		source.add_faces(mesh.get_faces(), Transform3D(Basis(), b[1]))
	var navmesh := NavigationMesh.new()
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_navigation_mesh(region, navmesh)
	NavigationServer3D.region_set_navigation_layers(region, EmergencyReturn.NAV_LAYERS)
	NavigationServer3D.region_set_map(region, map)
	_regions.append(region)
	var start := NavigationServer3D.map_get_iteration_id(map)
	for i in 60:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > start \
				and not NavigationServer3D.map_get_path(map, Vector3.ZERO, Vector3(10, 0, 0), true, 1).is_empty():
			break


func _clear_navmesh() -> void:
	for r in _regions:
		NavigationServer3D.free_rid(r)
	_regions.clear()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_ok = false
		printerr("  FAIL emergency_return: %s" % msg)
