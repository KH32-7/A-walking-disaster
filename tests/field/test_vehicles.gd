extends Node
## 02 "탈것": ride and get off, hits on riders go to the vehicle, wreck throws everyone out,
## mechanic repair (hold F, 50%), seats and wheelchair seats, ramming monsters.

const DT := 1.0 / 60.0
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const COMPANION_SCENE := preload("res://field/companion/field_companion.tscn")
const VINE_DEF := preload("res://data/monsters/vine_tendril.tres")
const TUNING := FieldVehicle.TUNING
const TEST_HP := 10000.0

var _ok := true
var _root: Node3D
var _player: Player


func run() -> bool:
	_ok = true
	var colony_before := Colony.save_data()
	var garage_before := Garage.save_data().duplicate(true)
	_root = Node3D.new()
	add_child(_root)
	_floor()
	_player = PLAYER_SCENE.instantiate()
	_root.add_child(_player)
	_player.set_physics_process(false)
	_player.get_node(^"Weapons").set_physics_process(false)
	await _physics()

	await _test_ride()
	await _test_wreck_and_repair()
	await _test_seats()
	await _test_ram()
	await _test_spawner()
	await _test_boat_bounds()
	await _test_helicopter()

	_root.free()
	Colony.load_data(colony_before)
	Garage.load_data(garage_before)
	FieldState.set_sortie_result({})
	return _ok


func _test_ride() -> void:
	var car := _vehicle(&"car", Vector3(0, 0, -3))
	await _physics()
	_check(car.interact_label() == FieldVehicle.RIDE_LABEL, "working car says ride")
	_check(car.begin_open(_player) and _player.is_riding() and car.driver == _player, "mount")
	_check(_player.collision_layer == 0, "rider leaves the physics layers")
	_player.take_damage(10.0)
	_check(is_equal_approx(car.durability, 110.0) and is_equal_approx(_player.health, _player.stats.max_health),
			"hit on the driver goes to the car")
	_check(car.dismount() and not _player.is_riding() and car.driver == null, "dismount")
	_check(_player.collision_layer != 0, "layers back after dismount")
	_check(_player.global_position.distance_to(car.global_position) > car.def.body_size.x * 0.5, "steps off beside it")
	car.free()


func _test_wreck_and_repair() -> void:
	var car := _vehicle(&"car", Vector3(0, 0, -3))
	await _physics()
	car.begin_open(_player)
	car.take_damage(1000.0)
	_check(car.is_broken() and not _player.is_riding(), "wreck throws the driver out")
	_check(car.interact_label() == FieldVehicle.NEED_MECHANIC_LABEL, "broken without mechanic")
	_check(not car.begin_open(_player), "cannot repair without mechanic")

	var helper := _companion({"name": "정비공", "former_job": &"mechanic"}, car.global_position + Vector3(2, 0, 0))
	_check(car.interact_label() == FieldVehicle.REPAIR_LABEL, "mechanic nearby offers repair")
	_check(car.begin_open(_player), "repair starts")
	_player.interact_held = false
	car._tick_repair(DT)
	_check(car.hold_state().is_empty() and car.is_broken(), "letting go cancels the repair")
	car.begin_open(_player)
	_player.interact_held = true
	car._tick_repair(TUNING.repair_sec + DT)
	_check(not car.is_broken() and is_equal_approx(car.durability, car.def.max_durability * TUNING.repaired_ratio),
			"repair restores %d%%" % int(TUNING.repaired_ratio * 100.0))
	_player.interact_held = false
	helper.free()
	car.free()


func _test_seats() -> void:
	var bike := _vehicle(&"motorbike", Vector3(0, 0, -3))
	var a := _companion({"name": "가"}, Vector3(1, 0, 0))
	var b := _companion({"name": "나"}, Vector3(-1, 0, 0))
	await _physics()
	bike.begin_open(_player)
	_check(bike.passengers.size() == 1, "motorbike takes one passenger, got %d" % bike.passengers.size())
	var seated: FieldCompanion = bike.passengers[0]
	_check(seated.riding == bike and not seated.visible and seated.collision_layer == 0, "passenger hidden")
	seated.take_damage(5.0)
	_check(is_equal_approx(bike.durability, bike.def.max_durability - 5.0), "hit on a passenger goes to the bike")
	bike.dismount()
	_check(seated.riding == null and seated.visible and seated.collision_layer != 0, "passenger gets off")
	bike.free()
	a.free()
	b.free()

	var wheel := _companion({"name": "휠체어", "access_needs": [Enums.AccessNeed.MOBILITY]}, Vector3(1, 0, 0))
	var moto := _vehicle(&"motorbike", Vector3(0, 0, -3))
	await _physics()
	moto.begin_open(_player)
	_check(moto.passengers.is_empty(), "wheelchair user does not board a motorbike")
	moto.dismount()
	moto.free()
	var car := _vehicle(&"car", Vector3(0, 0, -3))
	await _physics()
	car.begin_open(_player)
	_check(car.passengers.has(wheel), "wheelchair user boards a car")
	car.dismount()
	car.free()
	wheel.free()


func _test_ram() -> void:
	var car := _vehicle(&"car", Vector3.ZERO)
	var monster: Monster = VINE_DEF.scene.instantiate()
	monster.def = VINE_DEF
	_root.add_child(monster)
	monster.set_physics_process(false)
	monster.global_position = Vector3(0, 0, -8)
	monster.max_hp = TEST_HP
	monster.hp = TEST_HP
	await _physics()
	car.begin_open(_player)
	for i in 120:
		car.set_input(Vector3.FORWARD)
		await get_tree().physics_frame
		if monster.hp < TEST_HP:
			break
	_check(monster.hp < TEST_HP, "fast car hurts the monster it hits")
	_check(car.durability < car.def.max_durability, "ramming costs the car durability")
	car.dismount()
	car.free()
	monster.free()


func _test_spawner() -> void:
	var holder := Node3D.new()
	_root.add_child(holder)
	for i in 5:
		var s := VehicleSpot.new()
		s.name = "L%d" % i
		s.vehicle_ids = [&"bicycle"]
		s.position = Vector3(40 + i * 5, 0, 20)
		holder.add_child(s)
	for i in 2:
		var w := VehicleSpot.new()
		w.name = "W%d" % i
		w.surface = VehicleDef.Surface.WATER
		w.position = Vector3(40 + i * 6, 0, 40)
		holder.add_child(w)
	var spawn_point := PlayerSpawn.new()
	spawn_point.position = Vector3(60, 0, 60)
	holder.add_child(spawn_point)
	var spawner := VehicleSpawner.new()
	spawner.spawn_on_ready = false
	holder.add_child(spawner)
	await _physics()

	var first := _layout(spawner.spawn(_rng(7)))
	_check(first.size() == roundi(7 * TUNING.spawn_ratio), "spawn ratio: %d of 7" % first.size())
	_check(_layout(spawner.spawn(_rng(7))) == first, "same seed, same vehicles")
	for v in spawner.spawned:
		_check(v.def.field_broken_chance > 0.0 or not v.is_broken(), "%s never spawns broken" % v.def.id)
	await _physics()

	var boat_uid := Garage.add(&"motorboat")
	var with_boat := spawner.spawn(_rng(7), boat_uid)
	var brought: FieldVehicle = with_boat.back()
	_check(brought.garage_uid == boat_uid and brought.global_position.is_equal_approx(Vector3(40, 0, 40)),
			"brought boat waits at the first water spot")
	for v in with_boat:
		_check(v == brought or not v.global_position.is_equal_approx(Vector3(40, 0, 40)), "dock spot kept free")
	await _physics()
	var car_uid := Garage.add(&"car", 50.0)
	var with_car := spawner.spawn(_rng(7), car_uid)
	var car: FieldVehicle = with_car.back()
	_check(car.garage_uid == car_uid and is_equal_approx(car.durability, 50.0), "brought car keeps its durability")
	_check(car.global_position.distance_to(spawn_point.global_position) > 1.0
			and car.global_position.distance_to(spawn_point.global_position) < TUNING.brought_offset_m + 0.5,
			"brought car stands beside the player spawn")
	holder.free()


func _test_boat_bounds() -> void:
	for layer in [Enums.LAYER_BOAT_BOUNDS, Enums.LAYER_WORLD]:
		var wall := StaticBody3D.new()
		wall.collision_layer = 1 << (layer - 1)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(10, 3, 1)
		shape.shape = box
		wall.add_child(shape)
		wall.position = Vector3(-40, 0, -6)
		_root.add_child(wall)
		var boat := _vehicle(&"motorboat", Vector3(-40, 0, 0))
		await _physics()
		boat.begin_open(_player)
		for i in 150:
			boat.set_input(Vector3.FORWARD)
			await get_tree().physics_frame
		var stopped := boat.global_position.z > -6.0
		if layer == Enums.LAYER_BOAT_BOUNDS:
			_check(stopped, "boat stops at the land (layer 9)")
		else:
			_check(not stopped, "boat ignores walls that are only world (lip, buildings)")
		boat.dismount(true)
		boat.free()
		wall.free()


func _test_helicopter() -> void:
	var holder := Node3D.new()
	_root.add_child(holder)
	var ids := {&"ex_a": Vector3(10, 0, 30), &"ex_b": Vector3(-10, 0, 30), &"ex_heli": Vector3(0, 0, 50)}
	var heli: ExtractPoint
	for id: StringName in ids:
		var p := ExtractPoint.new()
		p.id = id
		p.position = ids[id]
		p.zone_radius = 6.0
		if id == &"ex_heli":
			p.type = ExtractPoint.Type.HELICOPTER
			p.wait_sec = 1.0
			heli = p
		holder.add_child(p)
	var manager := ExtractionManager.new()
	manager.auto_activate = false
	holder.add_child(manager)
	manager.set_physics_process(false)
	await _physics()

	# TUNING values are folded in at parse time, so draw many seeds instead of changing the chance.
	var with_heli := -1
	var hits := 0
	for s in 200:
		manager.activate(s)
		var active := manager.active_points()
		_check(active.size() == 2 or (active.size() == 3 and heli in active), "seed %d: 2 points, helicopter on top" % s)
		if heli in active:
			hits += 1
			with_heli = s
	_check(absf(hits / 200.0 - TUNING.helicopter_chance) < 0.1,
			"helicopter in %d of 200 sorties (chance %.2f)" % [hits, TUNING.helicopter_chance])
	manager.activate(with_heli)
	await _physics()
	var wreck := heli.get_node_or_null(^"HelicopterWreck") as HelicopterWreck
	_check(wreck != null, "active helicopter point has a wreck")
	if wreck == null:
		holder.free()
		return

	_player.global_position = heli.global_position + Vector3(2.5, 0, 0)
	manager.tick(DT)
	_check(manager.state == ExtractionManager.State.IDLE, "broken helicopter does not extract")
	_check(wreck.interact_label() == FieldVehicle.NEED_MECHANIC_LABEL and not wreck.begin_open(_player),
			"helicopter needs a mechanic")
	var helper := _companion({"name": "정비공", "former_job": &"mechanic"}, heli.global_position + Vector3(3, 0, 1))
	_check(wreck.begin_open(_player), "mechanic nearby: repair starts")
	_player.interact_held = true
	wreck._physics_process(TUNING.helicopter_repair_sec + DT)
	_player.interact_held = false
	_check(wreck.fixed, "helicopter fixed after %d s" % int(TUNING.helicopter_repair_sec))
	manager.tick(DT)
	_check(manager.state == ExtractionManager.State.COUNTING, "fixed helicopter starts the extraction")
	helper.free()
	holder.free()
	_player.global_position = Vector3.ZERO


## Def id and position of every spawned vehicle, for comparing two draws.
func _layout(list: Array[FieldVehicle]) -> Array:
	var out := []
	for v in list:
		out.append([v.def.id, v.global_position.snapped(Vector3.ONE * 0.01), v.is_broken()])
	return out


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _vehicle(def_id: StringName, at: Vector3) -> FieldVehicle:
	var v := FieldVehicle.new()
	var def := Garage.get_def(def_id)
	v.setup(def, def.max_durability)
	_root.add_child(v)
	v.global_position = at
	return v


func _companion(profile: Dictionary, at: Vector3) -> FieldCompanion:
	var id := Colony.add_resident(profile)
	var c: FieldCompanion = COMPANION_SCENE.instantiate()
	c.setup(id, Colony.get_resident(id))
	_root.add_child(c)
	c.set_physics_process(false)
	c.global_position = at
	return c


func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	body.add_child(shape)
	body.position.y = -0.5
	_root.add_child(body)


func _physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_ok = false
		printerr("  FAIL vehicles: %s" % msg)
