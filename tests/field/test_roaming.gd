extends Node
## Roaming packs (RoamingSpawner): start packs away from the player, nests and indoor ground,
## each pack homed on its own spawn point, one more pack every ROAM_INTERVAL_SEC off camera
## (faster at night, night rules applied), the roaming cap and the region cap shared with nests.
## World: flat 300x300 navmesh, the east half is an IndoorZone, the player in the north-west.

const VINE := preload("res://data/monsters/vine_tendril.tres")
const POD := preload("res://data/monsters/spore_pod.tres")
const BLOB := preload("res://data/monsters/swamp_blob.tres")
const HALF := 150.0
const PLAYER_AT := Vector3(-120.0, 0.0, -120.0)
const NEST_AT := Vector3(-60.0, 0.0, 60.0)
const NIGHT := GameState.SORTIE_NIGHT_SEC

var _ok := true
var _world: Node3D
var _night_before: NightTuning
var _autosave_before := true


func run() -> bool:
	# Past the onboarding days (MonsterRules.EARLY_DENSITY, EarlyZone, FieldState.early_bag_kept).
	var day_before := GameState.day
	GameState.day = 9
	_night_before = FieldState.night
	_autosave_before = SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	FieldState.set_process(false)
	_world = _make_world()
	add_child(_world)
	var map := _world.get_world_3d().navigation_map
	for i in 300:
		await get_tree().physics_frame
		var probe := NavigationServer3D.map_get_closest_point(map, Vector3(-100.0, 0.0, 0.0))
		if NavigationServer3D.map_get_iteration_id(map) > 0 and probe.distance_to(Vector3(-100.0, 0.0, 0.0)) < 1.0:
			break

	_test_start_packs()
	_test_interval_off_camera()
	_test_caps()
	_test_night()

	EventBus.sortie_ended.emit({})
	FieldState.night = _night_before
	SaveSystem.autosave_enabled = _autosave_before
	_world.free()
	GameState.day = day_before
	return _ok


func _test_start_packs() -> void:
	var spawner := _spawner(true)
	spawner.tick(0.0)
	var monsters := spawner.alive()
	var homes := {}
	for m in monsters:
		_expect(m.def != POD, "spore pods never roam")
		_expect(_flat(m.home, PLAYER_AT) >= MonsterRules.ROAM_START_MIN_PLAYER_DIST, "start pack away from the player")
		_expect(_flat(m.home, NEST_AT) >= MonsterRules.ROAM_CLEAR_NEST, "start pack away from the nest")
		_expect(m.home.x < 0.0, "no pack on indoor ground (%s)" % m.home)
		_expect(_flat(m.global_position, m.home) <= MonsterRules.SPAWN_SCATTER_RADIUS + 0.01, "spawned at its home")
		_expect(is_equal_approx(m.wander_radius, MonsterRules.ROAM_WANDER_RADIUS), "roaming wander radius")
		if homes.has(m.pack):
			_expect(homes[m.pack] == m.home, "a pack shares one home")
		homes[m.pack] = m.home
	_expect(homes.size() == MonsterRules.ROAM_START_GROUPS, "%d start packs (%d)" % [
		MonsterRules.ROAM_START_GROUPS, homes.size()])
	var list := homes.values()
	for i in list.size():
		for j in range(i + 1, list.size()):
			_expect(_flat(list[i], list[j]) >= MonsterRules.ROAM_SPREAD, "packs spread out")
	spawner.free()


func _test_interval_off_camera() -> void:
	var camera := Camera3D.new()
	_world.add_child(camera)
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), Vector3(-75.0, 60.0, 0.0))
	camera.make_current()
	var spawner := _spawner(false)
	spawner.tick(0.0)
	spawner.tick(MonsterRules.ROAM_INTERVAL_SEC - 1.0)
	_expect(spawner.alive_count() == 0, "nothing before the interval")
	for k in 4:
		spawner.tick(MonsterRules.ROAM_INTERVAL_SEC if k > 0 else 1.0)
	var count := spawner.alive_count()
	_expect(count >= 4 * MonsterRules.ROAM_GROUP_MIN and count <= 4 * MonsterRules.ROAM_GROUP_MAX,
		"one pack per interval (%d after 4)" % count)
	for m in spawner.alive():
		_expect(_flat(m.home, PLAYER_AT) >= MonsterRules.ROAM_MIN_PLAYER_DIST, "new pack away from the player")
		_expect(not camera.is_position_in_frustum(m.home + Vector3.UP), "new pack off camera (%s)" % m.home)
	spawner.free()
	camera.free()


func _test_caps() -> void:
	var spawner := _spawner(false)
	spawner.tick(0.0)
	spawner.tick(MonsterRules.ROAM_INTERVAL_SEC * 30)
	_expect(spawner.alive_count() <= MonsterRules.ROAM_MAX_ALIVE, "roaming cap (%d)" % spawner.alive_count())
	for m in spawner.alive():
		m.free()
	# Nest monsters count toward the region cap too.
	var others: Array[Monster] = []
	for i in MonsterRules.REGION_MAX_ALIVE - 1:
		var m := VINE.scene.instantiate() as Monster
		m.def = VINE
		m.position = Vector3(100.0, 0.0, -100.0 + i)
		_world.add_child(m)
		others.append(m)
	var got := spawner.spawn_group(Vector3(-100.0, 0.0, 0.0), 3, VINE)
	_expect(got.size() == 1, "region cap counts nest and roaming monsters (%d)" % got.size())
	_expect(get_tree().get_nodes_in_group(Monster.GROUP).size() == MonsterRules.REGION_MAX_ALIVE, "region cap in all")
	for m in others:
		m.free()
	spawner.free()


func _test_night() -> void:
	var always := NightTuning.new()
	always.elite_chance = 1.0
	FieldState.night = always
	EventBus.sortie_started.emit({"region_id": &"flooded_mall", "companions": []})
	FieldState.advance_sortie_time(NIGHT)
	var spawner := _spawner(false)
	spawner.tick(0.0)
	var step := MonsterRules.ROAM_INTERVAL_SEC / always.spawn_mult
	spawner.tick(step - 1.0)
	_expect(spawner.alive_count() == 0, "night: nothing just before interval / spawn_mult")
	spawner.tick(1.0)
	_expect(spawner.alive_count() >= 1, "night: packs come spawn_mult times as often")
	for m in spawner.alive():
		if "sight_mult" in m:
			_expect(is_equal_approx(m.get(&"sight_mult"), always.sight_mult), "night sight_mult on roamers")
		if "drop_mult" in m:
			_expect(is_equal_approx(m.get(&"drop_mult"), always.drop_mult), "night drop_mult on roamers")
	spawner.free()
	EventBus.sortie_ended.emit({})
	FieldState.night = _night_before


# --- Helpers --------------------------------------------------------------

func _make_world() -> Node3D:
	var world := Node3D.new()
	world.name = "RoamingWorld"
	var region := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.vertices = PackedVector3Array([Vector3(-HALF, 0, -HALF), Vector3(HALF, 0, -HALF),
		Vector3(HALF, 0, HALF), Vector3(-HALF, 0, HALF)])
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = nm
	world.add_child(region)
	var zone := IndoorZone.new()
	zone.building_id = &"test_hall"
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for c: Vector2 in [Vector2(0, -HALF), Vector2(HALF, -HALF), Vector2(HALF, HALF), Vector2(0, HALF)]:
		points.append(Vector3(c.x, 0.0, c.y))
		points.append(Vector3(c.x, 3.0, c.y))
	hull.points = points
	shape.shape = hull
	zone.add_child(shape)
	world.add_child(zone)
	var player := Node3D.new()
	player.add_to_group(Player.GROUP)
	player.position = PLAYER_AT
	world.add_child(player)
	var nest := MonsterNest.new()
	nest.position = NEST_AT
	world.add_child(nest)
	return world


func _spawner(start_groups: bool) -> RoamingSpawner:
	var spawner := RoamingSpawner.new()
	spawner.monster_defs = [VINE, POD, BLOB]
	spawner.region_id = &"flooded_mall"
	spawner.spawn_start_groups = start_groups
	_world.add_child(spawner)
	return spawner


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_ok = false
		push_error("test_roaming: " + label)
