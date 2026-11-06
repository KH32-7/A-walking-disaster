extends Node
## B-04: 45 deg diagonal start, 90 deg turns (4 views), 3 zoom distances, mouse and stick aim
## reach the player's facing, WASD stays screen relative after turning, aim assist, roof hook.

const CAMERA_SCENE := preload("res://field/camera/field_camera.tscn")
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const DT := 1.0 / 60.0
const EPS := 0.02

var _ok := true
var _camera: FieldCamera
var _player: Player


func run() -> bool:
	_ok = true
	var reduce_shake: Variant = Settings.get_value(&"reduce_shake")
	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_camera = CAMERA_SCENE.instantiate()
	_camera.target = _player
	add_child(_camera)

	_test_start_view()
	_test_turns_and_wasd()
	await _test_turn_tween()
	_test_zoom()
	_test_stick_aim()
	_test_mouse_aim()
	await _test_mouse_on_monster()
	await _test_mouse_under_roof()
	_test_aim_assist()
	_test_indoor_zone()

	Settings.values[&"reduce_shake"] = reduce_shake
	_camera.free()
	_player.free()
	return _ok


func _test_start_view() -> void:
	_camera.snap()
	_expect(_camera.yaw_index() == 0, "starts on view 0")
	var offset := _offset()
	_expect_near(_flat(offset).angle_to(Vector3(1, 0, 1).normalized()), 0.0, "starts on 45 deg diagonal")
	_expect_near(rad_to_deg(asin(offset.y / offset.length())), FieldCamera.PITCH_DEG, "looks down 55 deg", 0.1)
	_expect_near(offset.length(), FieldCamera.ZOOM_DISTANCES[FieldCamera.START_ZOOM], "start distance")
	_expect(get_viewport().get_camera_3d() == _camera, "becomes the current camera")
	var ear := _camera.listener()
	_expect(ear != null and ear.is_current(), "player-side listener is current")
	_expect(ear != null and ear.global_position.distance_to(_player.global_position + Vector3.UP * FieldCamera.FOCUS_HEIGHT) < EPS,
		"listener sits at the player's chest, not at the camera")
	_expect(ear != null and ear.global_basis.z.distance_to(_camera.global_basis.z) < EPS, "listener faces like the camera")


func _test_turns_and_wasd() -> void:
	Settings.values[&"reduce_shake"] = true # instant turns
	var expected := [135.0, 225.0, 315.0, 45.0]
	for i in 4:
		_camera.rotate_step(1)
		_camera.snap()
		_expect(_camera.yaw_index() == (i + 1) % 4, "turn %d index" % (i + 1))
		var want := Vector3(sin(deg_to_rad(expected[i])), 0.0, cos(deg_to_rad(expected[i])))
		_expect_near(_flat(_offset()).angle_to(want), 0.0, "turn %d is 90 deg more" % (i + 1))
		var forward := _flat(-_camera.global_basis.z)
		var right := _flat(_camera.global_basis.x)
		_expect_near(_move_dir(Vector2.UP).angle_to(forward), 0.0, "turn %d: W goes screen up" % (i + 1))
		_expect_near(_move_dir(Vector2.RIGHT).angle_to(right), 0.0, "turn %d: D goes screen right" % (i + 1))


func _test_turn_tween() -> void:
	Settings.values[&"reduce_shake"] = false
	var before := _flat(_offset())
	_camera.rotate_step(-1)
	# physics_frame fires before nodes and tweens step, so wait a few frames.
	for i in 4:
		await get_tree().physics_frame
	var mid := _flat(_offset()).angle_to(before)
	_expect(mid > 0.001 and mid < deg_to_rad(80.0), "turn eases in over time")
	await get_tree().create_timer(FieldCamera.ROTATE_SEC + 0.1).timeout
	await get_tree().physics_frame
	_expect(_camera.yaw_index() == 3, "left turn goes to view 3")
	_expect_near(_flat(_offset()).angle_to(before), deg_to_rad(90.0), "tween ends 90 deg away")


func _test_zoom() -> void:
	var levels: Array[int] = []
	_camera.zoom_changed.connect(func(level: int) -> void: levels.append(level))
	_camera.zoom_step(-1)
	_camera.zoom_step(-1)
	_expect(_camera.zoom_level() == 0 and levels.size() == 1 and levels[0] == 0, "zoom in stops at near")
	_camera.snap()
	_expect_near(_offset().length(), FieldCamera.ZOOM_DISTANCES[0], "near distance")
	_camera.zoom_step(5)
	_camera.snap()
	_expect(_camera.zoom_level() == 2, "zoom out stops at far")
	_expect_near(_offset().length(), FieldCamera.ZOOM_DISTANCES[2], "far distance")
	_camera.zoom_step(-1)
	_camera.snap()


func _test_stick_aim() -> void:
	var right := _flat(_camera.global_basis.x)
	var point := _camera.aim_point_from_stick(Vector2.RIGHT, _player.global_position, _player.facing())
	_expect_near((point - _player.global_position).length(), FieldCamera.STICK_AIM_DISTANCE, "stick aim distance")
	_aim_at(point)
	_expect_near(_player.facing().angle_to(right), 0.0, "stick right faces screen right")
	var idle := _camera.aim_point_from_stick(Vector2(0.1, 0.0), _player.global_position, _player.facing())
	_expect_near(_flat(idle - _player.global_position).angle_to(_player.facing()), 0.0, "deadzone keeps facing")


func _test_mouse_aim() -> void:
	var ground := _player.global_position + Vector3(3.0, 0.0, -2.0)
	var screen := _camera.unproject_position(ground)
	var point: Variant = _camera.aim_point_from_screen(screen)
	_expect(point != null, "cursor ray hits the ground")
	if point == null:
		return
	_expect_near((point as Vector3).distance_to(ground), 0.0, "cursor point is under the cursor", 0.05)
	_aim_at(point)
	_expect_near(_player.facing().angle_to(_flat(ground - _player.global_position)), 0.0, "player faces cursor")


## User playtest 2026-11-06: on the mall's 2F the cursor ray hit the roof above (faded out, still
## solid) and the player aimed somewhere else. Hits above the head are skipped.
func _test_mouse_under_roof() -> void:
	var roof := StaticBody3D.new()
	roof.collision_layer = 1 << (Enums.LAYER_WORLD - 1)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.3, 40.0)
	shape.shape = box
	roof.add_child(shape)
	add_child(roof)
	roof.global_position = _player.global_position + Vector3.UP * 4.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ground := _player.global_position + Vector3(3.0, 0.0, -2.0)
	var point: Variant = _camera.aim_point_from_screen(_camera.unproject_position(ground))
	_expect(point is Vector3 and (point as Vector3).distance_to(ground) < 0.05,
			"a roof above the player does not catch the cursor ray (%s)" % [point])
	roof.free()


## User feedback 2026-11-06: the cursor on a tall monster's head aimed at the ground behind it.
## With aim assist on, a monster under the cursor is aimed at directly.
func _test_mouse_on_monster() -> void:
	var assist: Variant = Settings.get_value(&"aim_assist")
	var def := preload("res://data/monsters/root_crusher.tres") as MonsterDef
	var monster := def.scene.instantiate() as Monster
	monster.def = def
	add_child(monster)
	monster.set_physics_process(false)
	monster.global_position = _player.global_position + Vector3(3.0, 0.0, -2.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var head := _camera.unproject_position(monster.global_position + Vector3.UP * 2.0)
	Settings.values[&"aim_assist"] = 1
	var point: Variant = _camera.aim_point_from_screen(head)
	_expect(point is Vector3 and (point as Vector3).distance_to(monster.global_position) < EPS,
			"cursor on a monster's head aims at the monster")
	Settings.values[&"aim_assist"] = 0
	point = _camera.aim_point_from_screen(head)
	_expect(point is Vector3 and (point as Vector3).distance_to(monster.global_position) > 0.5,
			"assist off: the cursor ray ignores monsters")
	Settings.values[&"aim_assist"] = assist
	monster.free()


func _test_aim_assist() -> void:
	var dir := Vector3.RIGHT
	var near_target: Array[Vector3] = [Vector3(10.0, 0.0, 1.5)] # about 8.5 deg off
	_expect(FieldCamera.assist_direction(Vector3.ZERO, dir, near_target, 0) == dir, "assist off")
	_expect(FieldCamera.assist_direction(Vector3.ZERO, dir, near_target, 1) == dir, "weak cone too narrow")
	var bent := FieldCamera.assist_direction(Vector3.ZERO, dir, near_target, 2)
	_expect_near(bent.angle_to(near_target[0]), 0.0, "medium assist bends to target")
	var far_target: Array[Vector3] = [Vector3(FieldCamera.ASSIST_RANGE + 5.0, 0.0, 0.5)]
	_expect(FieldCamera.assist_direction(Vector3.ZERO, dir, far_target, 3) == dir, "out of range ignored")


func _test_indoor_zone() -> void:
	var zone := IndoorZone.new()
	zone.building_id = &"shop"
	add_child(zone)
	var roof := _roof(&"shop")
	var other := _roof(&"other")
	var fade_script := GDScript.new()
	fade_script.source_code = "extends Node3D\nvar calls := []\nfunc set_roof_hidden(h: bool) -> void:\n\tcalls.append(h)\n"
	fade_script.reload()
	var fading := _roof(&"shop")
	fading.set_script(fade_script)
	var entered: Array[StringName] = []
	zone.player_entered.connect(func(id: StringName) -> void: entered.append(id))

	zone._on_body_entered(_player)
	_expect(not roof.visible and other.visible, "entering hides only this building's roof")
	_expect(fading.visible and fading.get(&"calls") == [true], "roof with set_roof_hidden fades itself")
	_expect(entered.size() == 1 and entered[0] == &"shop", "player_entered fires")
	zone._on_body_exited(_player)
	_expect(roof.visible and fading.get(&"calls") == [true, false], "leaving shows the roof again")
	for node: Node in [zone, roof, other, fading]:
		node.free()


func _roof(id: StringName) -> Node3D:
	var roof := Node3D.new()
	roof.add_to_group(IndoorZone.ROOF_GROUP)
	roof.set_meta(IndoorZone.ROOF_META, id)
	add_child(roof)
	return roof


func _aim_at(point: Vector3) -> void:
	_player.set_aim_point(point)
	_player.step(DT, {"aim": true})


func _move_dir(input: Vector2) -> Vector3:
	_player.velocity = Vector3.ZERO
	_player.step(DT, {"move": input})
	var dir := _flat(_player.velocity)
	_player.velocity = Vector3.ZERO
	return dir


func _offset() -> Vector3:
	return _camera.global_position - (_player.global_position + Vector3.UP * FieldCamera.FOCUS_HEIGHT)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_ok = false
		push_error("test_camera: %s" % label)


func _expect_near(actual: float, expected: float, label: String, eps := EPS) -> void:
	if absf(actual - expected) > eps:
		_ok = false
		push_error("test_camera: %s (got %.3f, want %.3f)" % [label, actual, expected])
