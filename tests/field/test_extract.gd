extends RefCounted
## B-09 extraction tests. run() -> bool is called by the A-02 runner.
## Completion: 2 active points (seeded), normal 5s, leaving cancels, generator / key / battery,
## 6m leave-behind question, EventBus.extraction_completed (docs/design/02-field.md "탈출").

const PARTY_DUMMY := preload("res://field/_sandbox/b09_party_dummy.gd")

var _ok := true
var _root: Node3D
var _player: Node3D
var _manager: ExtractionManager
var _points := {}
var _completed: Array = []
var _bag_backup: Dictionary
var _economy_backup: Dictionary


func run() -> bool:
	_ok = true
	_bag_backup = Bag.save_data()
	_economy_backup = Economy.save_data()
	EventBus.extraction_completed.connect(_on_completed)

	_test_activation()
	_test_normal()
	_test_leave_zone_cancels()
	_test_generator()
	_test_item_point(ExtractPoint.Type.KEY, &"key")
	_test_item_point(ExtractPoint.Type.BATTERY, &"battery")
	_test_leave_behind_wait()
	_test_leave_behind_leave()
	_test_wait_multiplier_zero()
	_test_downed()

	EventBus.extraction_completed.disconnect(_on_completed)
	Bag.load_data(_bag_backup)
	Economy.load_data(_economy_backup)
	return _ok


# --- Scene setup ---

## Fresh root with three candidates (types by id, default NORMAL), a fake player and an empty bag.
func _setup(types: Dictionary = {}) -> void:
	_teardown()
	_completed.clear()
	Bag.load_data({})
	_root = Node3D.new()
	_root.name = "ExtractTestRoot"
	(Engine.get_main_loop() as SceneTree).root.add_child(_root)
	_points.clear()
	var spots := {&"ex_a": Vector3(10, 0, 0), &"ex_b": Vector3(-10, 0, 0), &"ex_c": Vector3(0, 0, 20)}
	for id: StringName in spots:
		var p := ExtractPoint.new()
		p.id = id
		p.type = types.get(id, ExtractPoint.Type.NORMAL)
		p.wait_sec = 20.0 if p.type == ExtractPoint.Type.GENERATOR else 5.0
		p.position = spots[id]
		_root.add_child(p)
		_points[id] = p
	_player = Node3D.new()
	_player.add_to_group(Player.GROUP)
	_root.add_child(_player)
	_manager = ExtractionManager.new()
	_manager.auto_activate = false
	_manager.region_id = &"test_region"
	_root.add_child(_manager)
	_manager.set_physics_process(false)


func _teardown() -> void:
	if _root != null:
		_root.free()
		_root = null


## Activates exactly `ids` (test control over which points are live).
func _force_active(ids: Array) -> void:
	for seed_value in 200:
		_manager.activate(seed_value)
		var got := _manager.active_point_ids()
		var all_in := true
		for id in ids:
			all_in = all_in and got.has(id)
		if all_in:
			return
	_fail("could not activate %s" % [ids])


func _stand_at(id: StringName) -> void:
	_player.position = _points[id].position


func _add_companion(id: StringName, pos: Vector3, kind: StringName = ExtractionManager.KIND_COMPANION) -> Node3D:
	var n: Node3D = PARTY_DUMMY.new()
	n.set(&"party_id", id)
	n.set(&"display_name", "테스트 %s" % id)
	n.set(&"party_kind", kind)
	n.position = pos
	_root.add_child(n)
	return n


func _on_completed(point_id: StringName) -> void:
	_completed.append(point_id)


# --- Tests ---

func _test_activation() -> void:
	_setup()
	_manager.activate(42)
	var first := _manager.active_point_ids()
	_manager.activate(42)
	_expect_eq(_manager.active_point_ids(), first, "same seed, same active points")
	_expect_eq(first.size(), 2, "2 active points")
	var seen := {}
	for seed_value in 30:
		_manager.activate(seed_value)
		var ids := _manager.active_point_ids()
		ids.sort()
		seen[str(ids)] = true
	_expect(seen.size() > 1, "different seeds give different active points")
	_teardown()


func _test_normal() -> void:
	_setup()
	_force_active([&"ex_a"])
	var started := []
	_manager.extraction_started.connect(func(id: StringName, wait: float) -> void: started.append([id, wait]))
	_stand_at(&"ex_a")
	_manager.tick(0.0)
	_expect_eq(started, [[&"ex_a", 5.0]], "normal countdown starts at 5s")
	_manager.tick(4.9)
	_expect(_completed.is_empty(), "not out before 5s")
	_manager.tick(0.2)
	_expect_eq(_completed, [&"ex_a"], "extraction_completed after 5s")
	var result := _manager.get_result()
	_expect_eq(result.get("extracted"), true, "result.extracted")
	_expect_eq(result.get("point_id"), &"ex_a", "result.point_id")
	_teardown()


func _test_leave_zone_cancels() -> void:
	_setup()
	_force_active([&"ex_a"])
	var cancelled := []
	_manager.extraction_cancelled.connect(func(id: StringName) -> void: cancelled.append(id))
	_stand_at(&"ex_a")
	_manager.tick(0.0)
	_manager.tick(3.0)
	_player.position = Vector3(10, 0, 5)  # 5m away, zone_radius 3m
	_manager.tick(0.1)
	_expect_eq(cancelled, [&"ex_a"], "leaving the zone cancels")
	_expect_eq(_manager.state, ExtractionManager.State.IDLE, "back to idle")
	_stand_at(&"ex_a")
	_manager.tick(0.0)
	_manager.tick(3.0)
	_expect(_completed.is_empty(), "countdown restarts from 0")
	_teardown()


func _test_generator() -> void:
	_setup({&"ex_a": ExtractPoint.Type.GENERATOR, &"ex_b": ExtractPoint.Type.GENERATOR, &"ex_c": ExtractPoint.Type.GENERATOR})
	_force_active([&"ex_a"])
	var heard := []
	var listener := func(pos: Vector3, radius: float, _source: Node) -> void: heard.append([pos, radius])
	EventBus.noise_emitted.connect(listener)
	_stand_at(&"ex_a")
	_manager.tick(0.0)
	_expect(not heard.is_empty() and heard[0][1] == 25.0, "generator noise 25m")
	if not heard.is_empty():
		_expect_eq(heard[0][0], _points[&"ex_a"].position, "noise at the generator")
	_manager.tick(19.0)
	_expect(_completed.is_empty(), "generator not done before 20s")
	_manager.tick(1.1)
	_expect_eq(_completed, [&"ex_a"], "generator extraction after 20s")
	EventBus.noise_emitted.disconnect(listener)
	_teardown()


func _test_item_point(type: ExtractPoint.Type, item: StringName) -> void:
	_setup({&"ex_a": type, &"ex_b": type, &"ex_c": type})
	_force_active([&"ex_a"])
	var blocked := []
	_manager.extraction_blocked.connect(func(id: StringName, need: StringName) -> void: blocked.append([id, need]))
	_stand_at(&"ex_a")
	_manager.tick(0.0)
	_manager.tick(0.1)
	_expect_eq(blocked, [[&"ex_a", item]], "%s point blocked once without the item" % item)
	_expect_eq(_manager.state, ExtractionManager.State.IDLE, "%s: no countdown without item" % item)
	Bag.try_add(item, 1)
	_manager.tick(0.0)
	_expect_eq(_manager.state, ExtractionManager.State.COUNTING, "%s: countdown with item" % item)
	_manager.tick(5.1)
	_expect_eq(_completed, [&"ex_a"], "%s extraction" % item)
	_expect_eq(Bag.count_of(item), 0, "%s used up" % item)
	_teardown()


func _test_leave_behind_wait() -> void:
	_setup()
	_force_active([&"ex_a"])
	var companion := _add_companion(&"res_1", Vector3(20, 0, 0))  # 10m from ex_a
	var asked := []
	_manager.leave_behind_requested.connect(func(id: StringName, people: Array) -> void: asked.append([id, people]))
	_stand_at(&"ex_a")
	_manager.tick(0.0)
	_manager.tick(5.1)
	_expect_eq(asked.size(), 1, "leave-behind question sent")
	if asked.size() == 1:
		_expect_eq(asked[0][1], [{"id": &"res_1", "name": "테스트 res_1", "kind": &"companion"}], "question lists the companion")
	_expect(_completed.is_empty(), "no extraction while asking")
	_manager.answer_leave_behind(false)
	_manager.tick(0.1)
	_expect(_completed.is_empty(), "waiting for the companion")
	companion.position = Vector3(14, 0, 0)  # 4m
	_manager.tick(0.1)
	_expect_eq(_completed, [&"ex_a"], "extracts once the companion is within 6m")
	_expect_eq(_manager.get_result().get("companions"), [&"res_1"], "companion came back")
	_expect_eq(_manager.get_result().get("stranded"), [], "nobody stranded")
	_teardown()


func _test_leave_behind_leave() -> void:
	_setup()
	_force_active([&"ex_a"])
	_add_companion(&"res_1", Vector3(20, 0, 0))
	_add_companion(&"kid_1", Vector3(12, 0, 0), ExtractionManager.KIND_RESCUED)  # 2m
	var stranded := []
	var listener := func(id: StringName, region: StringName) -> void: stranded.append([id, region])
	EventBus.companion_stranded.connect(listener)
	_stand_at(&"ex_a")
	_manager.tick(0.0)
	_manager.tick(5.1)
	_manager.answer_leave_behind(true)
	EventBus.companion_stranded.disconnect(listener)
	_expect_eq(_completed, [&"ex_a"], "leave them: extract now")
	_expect_eq(stranded, [[&"res_1", &"test_region"]], "companion_stranded for the companion left behind")
	var result := _manager.get_result()
	_expect_eq(result.get("stranded"), [&"res_1"], "result.stranded")
	_expect_eq(result.get("rescued"), [&"kid_1"], "rescued person within 6m comes out")
	_teardown()


func _test_wait_multiplier_zero() -> void:
	_setup()
	_force_active([&"ex_a"])
	_manager.wait_multiplier = 0.0
	_stand_at(&"ex_a")
	_manager.tick(0.0)
	_expect_eq(_completed, [&"ex_a"], "wait_multiplier 0: instant extraction (B-22 hook)")
	_teardown()


func _test_downed() -> void:
	_setup()
	_force_active([&"ex_a"])
	EventBus.monster_killed.emit(&"vine_tendril", Enums.Element.NONE, Vector3.ZERO)
	EventBus.monster_killed.emit(&"vine_tendril", Enums.Element.NONE, Vector3.ZERO)
	_stand_at(&"ex_a")
	_manager.tick(0.0)
	EventBus.player_downed.emit()
	var result := _manager.get_result()
	_expect_eq(result.get("extracted"), false, "downed: not extracted")
	_expect_eq(result.get("downed"), true, "downed flag")
	_expect_eq(result.get("kills"), 2, "kill count")
	_expect_eq(result.get("kills_by_monster"), {&"vine_tendril": 2}, "kills by monster")
	_manager.tick(10.0)
	_expect(_completed.is_empty(), "no extraction after going down")
	_teardown()


# --- Helpers ---

func _expect(cond: bool, label: String) -> void:
	if not cond:
		_fail(label)


func _expect_eq(got: Variant, want: Variant, label: String) -> void:
	if got != want:
		_fail("%s: got %s, want %s" % [label, got, want])


func _fail(label: String) -> void:
	_ok = false
	push_error("test_extract: " + label)
