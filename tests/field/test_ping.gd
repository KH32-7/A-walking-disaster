extends Node
## Map ping in FieldState: set, replace, clear, cleared on arrival (PING_REACH_M) and when the
## sortie starts or ends. The map, minimap and world arrow (ui/) only read these.

var _ok := true
var _autosave_before := true


func run() -> bool:
	_ok = true
	_autosave_before = SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	FieldState.set_process(false)

	_test_set_and_clear()
	_test_sortie_clears()
	await _test_arrival_clears()

	FieldState.clear_ping()
	FieldState.set_process(true)
	SaveSystem.autosave_enabled = _autosave_before
	return _ok


func _test_set_and_clear() -> void:
	FieldState.clear_ping()
	_expect(not FieldState.has_ping, "no ping at first")
	FieldState.set_ping(Vector3(10, 0, 5))
	_expect(FieldState.has_ping and FieldState.ping == Vector3(10, 0, 5), "set_ping stores the spot")
	FieldState.set_ping(Vector3(-4, 0, 2))
	_expect(FieldState.ping == Vector3(-4, 0, 2), "a new ping replaces the old one")
	FieldState.clear_ping()
	_expect(not FieldState.has_ping, "clear_ping removes it")


func _test_sortie_clears() -> void:
	FieldState.set_ping(Vector3(10, 0, 5))
	EventBus.sortie_started.emit({"region_id": &"flooded_mall", "companions": []})
	_expect(not FieldState.has_ping, "sortie_started clears the ping")
	FieldState.set_ping(Vector3(10, 0, 5))
	EventBus.sortie_ended.emit({})
	_expect(not FieldState.has_ping, "sortie_ended clears the ping")


func _test_arrival_clears() -> void:
	var p := Node3D.new()
	p.add_to_group(Player.GROUP)
	add_child(p)
	FieldState.set_process(true)
	FieldState.set_ping(Vector3(10, 0, 0))
	p.global_position = Vector3(10 - FieldState.PING_REACH_M - 1.0, 0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(FieldState.has_ping, "still there while farther than PING_REACH_M")
	p.global_position = Vector3(10 - FieldState.PING_REACH_M + 0.5, 3, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not FieldState.has_ping, "cleared once the player is within PING_REACH_M (height ignored)")
	FieldState.set_process(false)
	p.queue_free()


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_ok = false
		push_error("test_ping: " + label)
