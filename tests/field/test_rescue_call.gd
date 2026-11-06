extends Node
## 살려주는 주민 (RescueCall): the first field down waits for a rescuer instead of ending the sortie.
## A companion who is up runs over; helped up after revive_sec in reach, health x ratio, and a
## second down ends the sortie at once. The wait running out ends it and strands the rescuers.
## With no companion, base residents set out (highest trust, no children). Nobody to send = the
## usual down. Base maps (field_rules off) never wait.
## Companions and the RescueCall are driven with tick(); their own physics process is off.

const DT := 1.0 / 60.0
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const COMPANION_SCENE := preload("res://field/companion/field_companion.tscn")
const TUNING := preload("res://data/classes/companion_tuning.tres")
const State := RescueCall.State

var _ok := true
var _root: Node3D
var _downs := 0
var _radio: Array[String] = []


func run() -> bool:
	_ok = true
	var saved := {
		"colony": Colony.save_data(), "field": FieldState.save_data(), "armory": Armory.save_data(),
		"bag": Bag.save_data(), "companions": FieldState.companions.duplicate(),
	}
	var autosave_before := SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	var keep_bag_before: Variant = Settings.get_value(&"keep_bag_on_down")
	Settings.set_value(&"keep_bag_on_down", true)
	EventBus.player_downed.connect(_on_player_downed)
	EventBus.radio_message.connect(_on_radio)

	_test_companion_helps_up()
	_test_wait_runs_out()
	_test_base_residents_come()
	_test_nobody_to_send()
	_test_base_map_never_waits()

	EventBus.player_downed.disconnect(_on_player_downed)
	EventBus.radio_message.disconnect(_on_radio)
	Settings.set_value(&"keep_bag_on_down", keep_bag_before)
	SaveSystem.autosave_enabled = autosave_before
	Colony.load_data(saved["colony"])
	FieldState.load_data(saved["field"])
	Armory.load_data(saved["armory"])
	Bag.load_data(saved["bag"])
	FieldState.companions.assign(saved["companions"])
	return _ok


func _test_companion_helps_up() -> void:
	var s := _setup()
	var c := _companion(s, _resident({"name": "한만석"}), Vector3(1, 0, 0))
	Radio._used_sortie.erase(RescueCall.RADIO_ID)
	_radio.clear()
	_down(s.player)
	_check(s.player.is_downed and _downs == 0, "first down waits: no player_downed")
	_check(s.rc.state == State.WAITING and s.rc.rescuers.size() == 1 and s.rc.rescuers[0] == c,
			"the companion who is up comes")
	c.tick(0.0)  # binds the player, so move_speed() reads the player's sprint speed
	_check(c.rush_to == s.player and is_equal_approx(c.move_speed(), s.player.stats.sprint_speed),
			"runs to the player at sprint speed")
	_check(_radio.size() == 1 and "한만석" in _radio[0], "radio names the rescuer (%s)" % [_radio])
	_ticks(s.rc, TUNING.revive_sec - 0.1)
	_check(s.player.is_downed, "still down before revive_sec")
	_ticks(s.rc, 0.2)
	_check(not s.player.is_downed and s.rc.state == State.USED, "helped up")
	_check(is_equal_approx(s.player.health, s.player.stats.max_health * TUNING.rescue_call_health_ratio),
			"health x rescue_call_health_ratio")
	_check(c.rush_to == null, "back to following")
	_down(s.player)
	_check(_downs == 1, "second down in the sortie: the usual down at once")
	s.root.free()


func _test_wait_runs_out() -> void:
	var s := _setup()
	var id := _resident({"name": "멀리"})
	FieldState.companions.assign([id])
	var c := _companion(s, id, Vector3(30, 0, 0))  # no nav mesh: stays out of reach
	_down(s.player)
	_ticks(s.rc, TUNING.rescue_call_wait_sec - 0.5)
	_check(_downs == 0 and s.rc.state == State.WAITING, "still waiting before the time is up")
	_ticks(s.rc, 1.0)
	_check(_downs == 1 and s.rc.state == State.USED, "time up: the usual down")
	_check(c.state == FieldCompanion.State.STRANDED, "the rescuer is stranded with the player")
	s.root.free()


func _test_base_residents_come() -> void:
	var s := _setup()
	var low := _resident({"name": "낮음"}, 40)
	var high := _resident({"name": "높음"}, 99)
	var mid := _resident({"name": "중간"}, 98)
	var child := _resident({"name": "아이", "age_stage": Enums.AgeStage.CHILD}, 100)
	_down(s.player)
	var ids: Array = s.rc.rescuers.map(func(c: FieldCompanion) -> StringName: return c.party_id)
	_check(ids == [high, mid], "two highest-trust adults come, no child (%s)" % [ids])
	_check(not child in ids and not low in ids, "child and lower trust stay home")
	for c: FieldCompanion in s.rc.rescuers:
		# _start_point(): rescue_call_spawn_distance m toward the entry, snapped to the nav mesh when
		# one exists (other tests may leave one in the world).
		var d: Vector3 = c.global_position - s.player.global_position
		_check(c.global_position.is_equal_approx(s.rc._start_point()), "sets out from the start point")
		_check(Vector2(d.x, d.z).length() > TUNING.rescue_call_reach,
				"starts out of reach (%.2f m)" % Vector2(d.x, d.z).length())
		_check(FieldState.companions.has(c.party_id), "counted as a companion of this sortie")
	s.root.free()


func _test_nobody_to_send() -> void:
	var s := _setup()
	# Fill the companion cap with downed companions: no room for base residents.
	for i in TUNING.max_companions:
		var c := _companion(s, _resident({}), Vector3(1, 0, i))
		c.take_damage(c.max_health * 2.0)
	_down(s.player)
	_check(_downs == 1 and s.rc.state == State.READY, "nobody to send: the usual down")
	s.root.free()


func _test_base_map_never_waits() -> void:
	var s := _setup(false)
	_companion(s, _resident({}), Vector3(1, 0, 0))
	_down(s.player)
	_check(_downs == 0 and s.rc.state == State.READY, "base map: no rescue call, no player_downed")
	s.root.free()


# --- Helpers -------------------------------------------------------------------

func _setup(field_rules := true) -> Dictionary:
	_downs = 0
	FieldState.companions.clear()
	var root := Node3D.new()
	add_child(root)
	var player: Player = PLAYER_SCENE.instantiate()
	player.field_rules = field_rules
	root.add_child(player)
	player.set_physics_process(false)
	player.get_node(^"Weapons").set_physics_process(false)
	player.global_position = Vector3.ZERO
	var manager := CompanionManager.new()
	manager.spawn_on_ready = false
	root.add_child(manager)
	var rc := RescueCall.new()
	manager.add_child(rc)
	rc.set_physics_process(false)
	rc.bind(player)
	return {"root": root, "player": player, "manager": manager, "rc": rc}


func _resident(profile: Dictionary, trust := -1) -> StringName:
	var id := Colony.add_resident(profile)
	if trust >= 0:
		Colony.residents[id]["trust"] = trust
	return id


func _companion(s: Dictionary, id: StringName, at: Vector3) -> FieldCompanion:
	var ids: Array[StringName] = [id]
	var placed: Array[FieldCompanion] = s.manager.spawn_ids(ids, at)
	var c := placed[0]
	c.set_physics_process(false)
	return c


func _down(player: Player) -> void:
	player.take_damage(player.stats.max_health * 10.0)


func _ticks(rc: RescueCall, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(DT, left)
		for c in rc.rescuers:
			if is_instance_valid(c):
				c.tick(step)
		rc.tick(step)
		left -= DT


func _on_player_downed() -> void:
	_downs += 1


func _on_radio(_speaker: StringName, text: String, _priority: int) -> void:
	_radio.append(text)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_ok = false
		printerr("  FAIL rescue_call: %s" % msg)
