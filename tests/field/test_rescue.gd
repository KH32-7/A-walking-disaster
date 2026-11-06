extends Node
## B-10: rescue types (trapped / injured / communication: success and failure), follow and hide,
## the five walking styles (speed, noise), wheelchair vs stairs (nav layers), downed 30 s,
## spawning on RescueSpots and rescue_completed on extraction.
## Targets are driven with tick(); their own physics process is off.

const DT := 1.0 / 60.0
const EPS := 0.05
const TARGET_SCENE := preload("res://field/rescue/rescue_target.tscn")
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const SPOT_SCENE := preload("res://field/markers/rescue_spot.tscn")
const TUNING := preload("res://data/classes/rescue_tuning.tres")
const NOISE_TABLE := preload("res://field/noise/noise_table.tres")
const SPAWN_FILES := [
	"res://data/regions/flooded_mall/rescues/injured_elder.tres",
	"res://data/regions/flooded_mall/rescues/trapped_wheelchair.tres",
	"res://data/regions/flooded_mall/rescues/lost_child.tres",
]
const Move := RescueSpawn.Move
const Type := RescueSpawn.Type
const State := RescueTarget.State

var _ok := true
var _player: Player
var _regions: Array[RID] = []
var _noises: Array = []


func run() -> bool:
	_ok = true
	var bag_before := Bag.save_data()
	var colony_before := Colony.save_data()
	var router_before := SceneRouter.save_data()
	_player = PLAYER_SCENE.instantiate()
	_player.set_physics_process(false)
	add_child(_player)
	EventBus.noise_emitted.connect(_on_noise)

	_test_data_files()
	_test_trapped()
	_test_injured()
	_test_communication()
	_test_callout()
	await _bake_test_navmesh(false)
	_test_speeds()
	_test_noise()
	_test_child_startle()
	_test_follow_and_hide()
	_test_escort_goal()
	_test_downed()
	_test_wheelchair_stairs()
	await _bake_test_navmesh(true)
	_test_wheelchair_ramp()
	_test_spawn_and_complete()

	EventBus.noise_emitted.disconnect(_on_noise)
	_clear_navmesh()
	_player.free()
	Bag.load_data(bag_before)
	Colony.load_data(colony_before)
	SceneRouter.load_data(router_before)
	return _ok


func _test_data_files() -> void:
	var spawns := _load_spawns()
	_check(spawns.size() == 3, "three demo rescue spawns load")
	for s in spawns:
		_check(not RescueManager.profile_for(s).is_empty(), "profile for %s" % s.template_id)
	_check(spawns[1].navigation_layers() == 0b10, "wheelchair uses nav layer 2 only")
	_check(spawns[0].navigation_layers() == 0b01, "walkers use nav layer 1")
	for action: StringName in TUNING.move_noise.values():
		_check(NOISE_TABLE.has_action(action), "noise table has %s" % action)


# --- Rescue types --------------------------------------------------------------

func _test_trapped() -> void:
	# Lock picking: hold F (Player.interact_held) for lockpick_sec (4 s since 2026-11-06).
	_player.interact_held = true
	var t := _target(_spawn(Type.TRAPPED, Move.WHEELCHAIR))
	var door := t.get_node("Door") as RescueDoor
	_check(door.get_collision_layer_value(Enums.LAYER_ALLY) and door.get_collision_layer_value(Enums.LAYER_INTERACTABLE),
			"door is on layers 3 and 7")
	_check(not t.get_collision_layer_value(Enums.LAYER_INTERACTABLE), "trapped person is reached through the door")
	_check(door.interact_label() == "문 따기 (꾹 누르기)", "door prompt says hold")
	_check(door.begin_open(_player), "door starts lock picking")
	_ticks(t, TUNING.lockpick_sec - 0.2)
	_check(t.state == State.LOCKPICKING and t.lockpick_progress() > 0.9, "still picking before the time")
	_check(door.hold_state().get("progress", 0.0) > 0.9, "door shows the hold gauge")
	_ticks(t, 0.3)
	_check(t.state == State.FOLLOW and t.is_in_group(RescueTarget.PARTY_GROUP), "lock picked: follows, joins the party")
	_check(t.get_collision_layer_value(Enums.LAYER_ALLY), "follower is on layer 3")
	t.free()

	# Letting go of F empties the gauge; small steps while holding do not.
	t = _target(_spawn(Type.TRAPPED, Move.WHEELCHAIR))
	(t.get_node("Door") as RescueDoor).begin_open(_player)
	_ticks(t, 1.0)
	_player.position.x += 1.0
	_ticks(t, DT)
	_check(t.state == State.LOCKPICKING, "moving a little while holding keeps picking")
	_player.position.x -= 1.0
	_player.interact_held = false
	_ticks(t, DT)
	_check(t.state == State.WAITING and t.lockpick_progress() == 0.0, "letting go resets lock picking")
	_player.interact_held = true
	(t.get_node("Door") as RescueDoor).begin_open(_player)
	_player.position.x += TUNING.lockpick_leave_m + 0.5
	_ticks(t, DT)
	_check(t.state == State.WAITING, "walking away resets lock picking")
	_player.position.x -= TUNING.lockpick_leave_m + 0.5
	t.free()

	# Power restored: out at once (through the switch).
	t = _target(_spawn(Type.TRAPPED, Move.WHEELCHAIR), [&"elevator"])
	var power := RescuePowerSwitch.new()
	add_child(power)
	_check(power.begin_open(_player) and t.state == State.FOLLOW, "power switch frees the trapped person")
	_check(not power.begin_open(_player), "switch works once")
	power.free()
	t.free()

	# Monsters break the door first: defend event, then they follow.
	t = _target(_spawn(Type.TRAPPED, Move.WHEELCHAIR))
	(t.get_node("Door") as RescueDoor).take_damage(TUNING.door_health + 1.0, {})
	_check(t.state == State.DEFEND and t.get_collision_layer_value(Enums.LAYER_ALLY), "broken door: defend event, exposed")
	_ticks(t, TUNING.defend_sec - 0.5)
	_check(t.state == State.DEFEND, "defend lasts 60 s")
	_ticks(t, 1.0)
	_check(t.state == State.FOLLOW, "defended: follows")
	t.free()


func _test_injured() -> void:
	Bag.load_data({})
	var t := _target(_spawn(Type.INJURED, Move.SUPPORTED, &"first_aid_kit"))
	var needed: Array = []
	t.item_needed.connect(func(id: StringName) -> void: needed.append(id))
	_check(t.get_collision_layer_value(Enums.LAYER_INTERACTABLE), "injured person is interactable")
	_check(not t.begin_open(_player) and needed == [&"first_aid_kit"], "no first aid kit: refused, item_needed")
	Bag.try_add(&"first_aid_kit", 1)
	_check(t.begin_open(_player), "first aid kit used")
	_check(Bag.count_of(&"first_aid_kit") == 0, "kit removed from the bag")
	_check(t.state == State.FOLLOW and _player.one_hand_only, "supported: follows, player one-hand only")
	_check(is_equal_approx(_player.move_speed_mult, 0.7), "supported: player speed x0.7")
	_check(not t.get_collision_layer_value(Enums.LAYER_INTERACTABLE), "follower does not block other interactions")
	t.free()
	_check(is_equal_approx(_player.move_speed_mult, 1.0) and not _player.one_hand_only, "player hooks reset when the person is gone")


func _test_communication() -> void:
	var t := _target(_card_spawn())
	var rounds: Array = []
	t.card_round_started.connect(func(i: int, prompt: StringName, _o: Array[StringName]) -> void: rounds.append([i, prompt]))
	_check(t.begin_open(_player) and t.state == State.CARDS, "cards start")
	_check(rounds == [[0, &"come_with_us"]], "round 1 shown")
	_check(t.answer_card(0), "round 1 right")
	_check(not t.answer_card(2), "round 2 wrong once")
	_check(rounds.size() == 3 and rounds[2][0] == 1, "round 2 asked again")
	_check(t.answer_card(1) and t.state == State.FOLLOW, "two right answers: follows")
	t.free()

	t = _target(_card_spawn())
	t.begin_open(_player)
	t.answer_card(1)
	t.answer_card(2)
	_check(t.state == State.WARY, "two wrong answers: wary")
	_check(not t.begin_open(_player) and not t.is_rescued(), "wary person does not come this sortie")
	t.free()

	var colony_before := Colony.save_data()
	Colony.complete_building(Colony.place_building(TUNING.interpreter_building, Vector2i.ZERO, 0, &"", false))
	t = _target(_card_spawn())
	_check(t.begin_open(_player) and t.state == State.FOLLOW, "interpreter radio: instant success")
	t.free()
	Colony.load_data(colony_before)


# --- Escort --------------------------------------------------------------------

func _test_speeds() -> void:
	var walk := _player.stats.walk_speed
	var expected := {Move.WALK: walk, Move.SLOW: walk * 0.7, Move.WHEELCHAIR: walk, Move.CHILD: walk * 1.1}
	for move: int in expected:
		var t := _follower(move, Vector3(1, 0, 1), Vector3(9, 0, 9))
		_check(absf(t.move_speed() - expected[move]) < EPS, "speed of move %d" % move)
		_check(absf(_flat(t.velocity) - expected[move]) < EPS, "follow velocity of move %d (%.2f)" % [move, _flat(t.velocity)])
		t.free()
	# Supported: the player is slowed instead.
	var s := _follower(Move.SUPPORTED, Vector3(1, 0, 1), Vector3(1.5, 0, 1))
	for i in 30:
		_player.step(DT, {"move": Vector2.UP})
	_check(absf(_flat(_player.velocity) - walk * 0.7) < EPS, "supporting player walks at -30%")
	_player.velocity = Vector3.ZERO
	s.free()


func _test_noise() -> void:
	var expected := {Move.WALK: 4.0, Move.SLOW: 3.0, Move.WHEELCHAIR: 3.0, Move.CHILD: 2.0}
	for move: int in expected:
		_noises.clear()
		var t := _follower(move, Vector3(1, 0, 1), Vector3(9, 0, 9))
		_check(_noise_from(t) == expected[move], "footstep noise of move %d (%s)" % [move, _noise_from(t)])
		t.free()
	_noises.clear()
	var s := _follower(Move.SUPPORTED, Vector3(1, 0, 1), Vector3(1.5, 0, 1))
	_player.velocity = Vector3(3, 0, 0)
	s.tick(DT)
	_check(_noise_from(s) == 5.0, "supported noise 5m while the player moves")
	_player.velocity = Vector3.ZERO
	s.free()


func _test_child_startle() -> void:
	var t := _follower(Move.CHILD, Vector3(1, 0, 1), Vector3(9, 0, 9))
	EventBus.noise_emitted.emit(Vector3(2, 0, 2), 4.0, null)
	_check(not t.is_startled(), "small noise does not startle")
	EventBus.noise_emitted.emit(Vector3(2, 0, 2), 15.0, null)
	t.tick(DT)
	_check(t.is_startled() and _flat(t.velocity) == 0.0, "gunshot: child stops")
	_ticks(t, TUNING.startle_sec - 0.2)
	_check(t.is_startled(), "still frozen before 2 s")
	_ticks(t, 0.3)
	_check(not t.is_startled() and _flat(t.velocity) > 0.0, "walks again after 2 s")
	t.free()


func _test_follow_and_hide() -> void:
	var cover := Node3D.new()
	cover.add_to_group(RescueTarget.COVER_GROUP)
	add_child(cover)
	cover.global_position = Vector3(5, 0, 1)
	var t := _follower(Move.WALK, Vector3(1, 0, 1), Vector3(9, 0, 9))
	var manager := RescueManager.new()
	manager.spawn_on_ready = false
	add_child(manager)
	manager.targets.append(t)
	_check(manager.toggle_command() and t.state == State.HIDE, "companion_command: hide")
	_check(t._hide_point.distance_to(Vector3(4, 0, 1)) < 0.3, "hides behind the nearest low cover")
	_check(t.is_in_group(RescueTarget.PARTY_GROUP), "hidden person stays in the party")
	_check(manager.toggle_command() and t.state == State.FOLLOW, "companion_command again: follow")
	manager.free()
	t.free()
	cover.free()

	var s := _follower(Move.SUPPORTED, Vector3(1, 0, 1), Vector3(1.5, 0, 1))
	_check(s.command_hide() and not _player.one_hand_only, "supported person set down, player free")
	_player.global_position = Vector3(8, 0, 8)
	_check(not s.command_follow(_player), "too far to pick them up")
	_player.global_position = Vector3(2, 0, 1)
	_check(s.begin_open(_player) and s.state == State.FOLLOW and _player.one_hand_only, "picked up again")
	s.free()


## The rescue objective's marker moves to the nearest open extraction point once the person follows.
func _test_escort_goal() -> void:
	var o := {"kind": &"rescue", "target_id": &""}
	var em := ExtractionManager.new()
	em.auto_activate = false
	add_child(em)
	var near := ExtractPoint.new()
	var far := ExtractPoint.new()
	add_child(near)
	add_child(far)
	near.global_position = Vector3(10, 0, 0)
	far.global_position = Vector3(40, 0, 0)
	em._active = [far, near]
	var t := _target(_spawn(Type.INJURED, Move.WALK))
	_check(RescueTarget.escort_goal(get_tree(), o) == null, "escort goal: none before the rescue")
	t.begin_open(_player)
	t.tick(DT)
	_check(t.is_rescued(), "escort goal: rescued")
	_check(RescueTarget.escort_goal(get_tree(), o) == near, "escort goal: nearest open extraction point")
	_check(RescueTarget.escort_goal(get_tree(), {"kind": &"visit"}) == null, "escort goal: rescue objectives only")
	_check(RescueTarget.escort_goal(get_tree(), {"kind": &"rescue", "target_id": &"someone_else"}) == null,
			"escort goal: only for its own person")
	t.free()
	near.free()
	far.free()
	em.free()


func _test_downed() -> void:
	var t := _follower(Move.WALK, Vector3(1, 0, 1), Vector3(2, 0, 2))
	t.take_damage(TUNING.max_health, {})
	_check(t.state == State.DOWNED, "health 0: downed")
	_check(not t.get_collision_layer_value(Enums.LAYER_ALLY) and t.get_collision_layer_value(Enums.LAYER_INTERACTABLE),
			"downed: off layer 3, on layer 7")
	_ticks(t, TUNING.downed_sec - 0.5)
	_check(t.state == State.DOWNED, "still downed before 30 s")
	_check(t.begin_open(_player) and t.state == State.DOWNED, "F: helping up starts")
	_ticks(t, TUNING.revive_sec - 0.2)
	_check(t.state == State.DOWNED and t.hold_state()["progress"] > 0.9,
			"still downed before 3 s (the 30 s wait paused)")
	_ticks(t, 0.3)
	_check(t.state == State.FOLLOW and t.hold_state().is_empty(), "helped up after 3 s")
	_check(is_equal_approx(t.health, TUNING.max_health * TUNING.revive_health_ratio), "half health after help")
	t.take_damage(TUNING.max_health, {})
	var isolated := [false]
	t.isolated.connect(func() -> void: isolated[0] = true)
	_ticks(t, TUNING.downed_sec + 0.1)
	_check(t.state == State.ISOLATED and isolated[0], "not helped in 30 s: stranded")
	_check(not t.is_in_group(RescueTarget.PARTY_GROUP), "stranded person leaves the party")
	t.free()


func _test_wheelchair_stairs() -> void:
	var walker := _follower(Move.WALK, Vector3(2, 0, 2), Vector3(25, 2, 2))
	var chair := _follower(Move.WHEELCHAIR, Vector3(2, 0, 2), Vector3(25, 2, 2))
	_check(_path_end(walker).x > 20.0, "walker path climbs the stairs")
	_check(_path_end(chair).x < 10.5, "wheelchair path stops before the stairs (%s)" % _path_end(chair))
	walker.free()
	chair.free()


func _test_wheelchair_ramp() -> void:
	var chair := _follower(Move.WHEELCHAIR, Vector3(2, 0, 2), Vector3(25, 2, 2))
	var used_ramp := false
	for p in chair._path:
		if p.x > 9.0 and p.x < 21.0 and p.z > 6.0:
			used_ramp = true
	_check(_path_end(chair).x > 20.0 and used_ramp, "wheelchair goes up by the ramp")
	chair.free()


# --- Spawning and rescue_completed ---------------------------------------------

func _test_spawn_and_complete() -> void:
	var spots: Array[RescueSpot] = []
	for tag: StringName in [&"flooded_edge", &"elevator", &"shop_interior"]:
		var spot: RescueSpot = SPOT_SCENE.instantiate()
		spot.spawn_tags.append(tag)
		add_child(spot)
		spots.append(spot)
	var manager := _manager(2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var placed := manager.spawn(rng)
	_check(placed.size() == 2, "max 2 rescue targets per sortie")
	for t in placed:
		_check(t.spot_tags.has(t.spawn.spawn_tags[0]), "%s on a spot with its tag" % t.party_id)
		t.set_physics_process(false)
	manager.free()

	manager = _manager(3)
	placed = manager.spawn(rng)
	for t in placed:
		t.set_physics_process(false)
	var completed: Array = []
	var listener := func(p: Dictionary) -> void: completed.append(p.get("id"))
	EventBus.rescue_completed.connect(listener)
	var elder := placed[0]
	var child := placed[2]
	elder._rescue(_player)
	child._rescue(_player)
	# B-09 ExtractionManager stand-in.
	var extraction := Node.new()
	extraction.add_user_signal(&"sortie_result_ready", [{"name": "result", "type": TYPE_DICTIONARY}])
	extraction.add_to_group(RescueManager.EXTRACTION_GROUP)
	add_child(extraction)
	manager._connect_extraction()
	extraction.emit_signal(&"sortie_result_ready",
			{"extracted": true, "rescued": [elder.party_id, child.party_id, placed[1].party_id]})
	_check(completed == [&"demo_carpenter", &"demo_child"], "rescue_completed for the rescued only (%s)" % [completed])
	_check(not Colony.get_resident(&"demo_carpenter").is_empty(), "Colony took the rescued person in")
	_check(Colony.get_resident(&"demo_carpenter")["gender"] == elder.profile["gender"],
			"gender fixed in the field is kept at the base")
	_check(ResidentModel.pick(Colony.get_resident(&"demo_carpenter")) == ResidentModel.pick(elder.profile, elder.spawn.move_type),
			"same character model in the field and at the base")
	manager.complete_rescues([elder.party_id])
	_check(completed.size() == 2, "rescue_completed once per person")
	EventBus.rescue_completed.disconnect(listener)
	extraction.free()
	manager.free()

	manager = _manager(3)
	placed = manager.spawn(rng)
	_check(placed.size() == 1 and placed[0].party_id == &"demo_mechanic", "people already in the base do not spawn again")
	manager.free()
	for spot in spots:
		spot.free()


# --- Call out ------------------------------------------------------------------

func _test_callout() -> void:
	for table: Dictionary in [TUNING.callout_far_lines, TUNING.callout_near_lines]:
		for type in [Type.TRAPPED, Type.INJURED, Type.COMMUNICATION]:
			var lines: PackedStringArray = table.get(type, PackedStringArray())
			_check(lines.size() >= 2, "call out lines for type %d" % type)
			for line in lines:
				_check(not ("—" in line or "·" in line or "…" in line), "no banned glyph in '%s'" % line)
	Bag.load_data({})
	var t := _target(_spawn(Type.INJURED, Move.SUPPORTED, &"first_aid_kit"))
	# Another test may leave a Player in the tree: hear this one.
	t._player = _player
	var said: Array = []
	t.called_out.connect(func(text: String, near: bool) -> void: said.append([text, near]))
	t.global_position = Vector3(TUNING.callout_far_m + 2.0, 0.0, 0.0)
	_ticks(t, 1.0)
	_check(said.is_empty(), "player out of range: silent")
	t.global_position.x = TUNING.callout_far_m - 1.0
	t.tick(DT)
	_check(said.size() == 1 and not said[0][1] and said[0][0] == TUNING.callout_far_lines[Type.INJURED][0],
			"player heard: first far line (%s)" % [said])
	_ticks(t, TUNING.callout_interval_sec - 0.5)
	_check(said.size() == 1, "quiet between call outs")
	t.global_position.x = TUNING.callout_near_m - 1.0
	t.tick(DT)
	_check(said.size() == 2 and said[1][1] and said[1][0] == TUNING.callout_near_lines[Type.INJURED][0],
			"player comes near: begs at once")
	_ticks(t, TUNING.callout_interval_sec + 0.1)
	_check(said.size() == 3 and said[2][1] and said[2][0] != said[1][0], "again after the interval, the next line")
	Bag.try_add(&"first_aid_kit", 1)
	t.begin_open(_player)
	var count := said.size()
	_ticks(t, TUNING.callout_interval_sec * 2.0)
	_check(t.state != State.WAITING and said.size() == count, "rescued: no more call outs")
	t.free()


# --- Helpers -------------------------------------------------------------------

func _spawn(type: int, move: int, item: StringName = &"") -> RescueSpawn:
	var s := RescueSpawn.new()
	s.template_id = &"test_person"
	s.rescue_type = type as RescueSpawn.Type
	s.move_type = move as RescueSpawn.Move
	s.required_item = item
	return s


func _card_spawn() -> RescueSpawn:
	return load("res://data/regions/flooded_mall/rescues/lost_child.tres")


func _load_spawns() -> Array[RescueSpawn]:
	var out: Array[RescueSpawn] = []
	for path: String in SPAWN_FILES:
		out.append(load(path))
	return out


func _manager(max_count: int) -> RescueManager:
	var m := RescueManager.new()
	m.spawn_on_ready = false
	m.max_per_sortie = max_count
	m.pool_count = 0  # fixed spawns only; pool survivors are checked by the playthrough bot
	m.spawns = _load_spawns()
	add_child(m)
	return m


func _target(s: RescueSpawn, tags: Array[StringName] = []) -> RescueTarget:
	var t: RescueTarget = TARGET_SCENE.instantiate()
	t.setup(s, {"name": "테스트"}, tags)
	t.set_physics_process(false)
	add_child(t)
	_player.global_position = Vector3.ZERO
	return t


## A rescued person following the player (no item needed), after one tick.
func _follower(move: int, at: Vector3, player_at: Vector3) -> RescueTarget:
	var t := _target(_spawn(Type.INJURED, move))
	t.global_position = at
	_player.global_position = player_at
	t.begin_open(_player)
	t.tick(DT)
	return t


func _ticks(t: RescueTarget, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		t.tick(minf(DT, left))
		left -= DT


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _path_end(t: RescueTarget) -> Vector3:
	return t._path[t._path.size() - 1] if not t._path.is_empty() else t.global_position


func _on_noise(_position: Vector3, radius: float, source: Node) -> void:
	_noises.append([radius, source])


func _noise_from(t: Node) -> float:
	for n in _noises:
		if n[1] == t:
			return n[0]
	return -1.0


## Floor (x 0..10, y 0) and an upper level (x 20..30, y 2) joined by a slope at z 0..4.
## Nav layer 1 (walkers) has the slope as stairs. Nav layer 2 (wheelchair) skips it and, with
## `ramp`, gets a second slope at z 6..10 instead (the B-12 baking convention).
func _bake_test_navmesh(ramp: bool) -> void:
	_clear_navmesh()
	var map := get_viewport().world_3d.navigation_map
	# Headless --script runs start with the navigation server off.
	NavigationServer3D.set_active(true)
	NavigationServer3D.map_set_active(map, true)
	var floor_box := [Vector3(10, 0.2, 10), Transform3D(Basis(), Vector3(5, -0.1, 5))]
	var upper_box := [Vector3(10, 0.2, 10), Transform3D(Basis(), Vector3(25, 1.9, 5))]
	var slope := Basis(Vector3.BACK, atan2(2.0, 10.0))
	var stairs_box := [Vector3(10.6, 0.2, 4), Transform3D(slope, Vector3(15, 0.9, 2))]
	var ramp_box := [Vector3(10.6, 0.2, 4), Transform3D(slope, Vector3(15, 0.9, 8))]
	_add_region(map, 0b01, [floor_box, upper_box, stairs_box])
	_add_region(map, 0b10, [floor_box, upper_box, ramp_box] if ramp else [floor_box, upper_box])
	# Wait until the map has synced the new regions: a new iteration and a probe path on the floor.
	var start := NavigationServer3D.map_get_iteration_id(map)
	for i in 60:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > start 				and not NavigationServer3D.map_get_path(map, Vector3(1, 0, 1), Vector3(9, 0, 9), true, 0b11).is_empty():
			break


func _add_region(map: RID, layers: int, boxes: Array) -> void:
	var source := NavigationMeshSourceGeometryData3D.new()
	for b: Array in boxes:
		var mesh := BoxMesh.new()
		mesh.size = b[0]
		source.add_faces(mesh.get_faces(), b[1])
	var navmesh := NavigationMesh.new()
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_navigation_mesh(region, navmesh)
	NavigationServer3D.region_set_navigation_layers(region, layers)
	NavigationServer3D.region_set_map(region, map)
	_regions.append(region)


func _clear_navmesh() -> void:
	for r in _regions:
		NavigationServer3D.free_rid(r)
	_regions.clear()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_ok = false
		printerr("  FAIL rescue: %s" % msg)
