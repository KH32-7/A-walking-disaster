extends Node3D
## B-10 sandbox: the real player, three RescueSpots (injured elder, wheelchair user trapped in the
## deck "elevator", child who needs picture cards) on the field sandbox with stairs and a ramp.
## Nav meshes are baked here at start: layer 1 = everything, layer 2 = everything but the stairs.
##
## Run alone (F6). Headless (or P) runs a scripted demo and prints PASS / FAIL, then quits headless.
## Sandbox-only keys (raw keycodes): F interact (player), V follow / hide (companion_command),
##   1 2 3 answer a picture card, G give a first aid kit, B break the elevator door,
##   H hurt the nearest follower, X extract (stand-in for B-09 ExtractionManager), P demo.

## Same signal as ExtractionManager.sortie_result_ready (B-09), for RescueManager to hear.
signal sortie_result_ready(result: Dictionary)

const PARTY_RADIUS := 6.0
const HURT_DAMAGE := 20.0
const STEP_TIMEOUT := 25.0
## The ramp's footprint on the floor (field_sandbox.tscn Geometry/Access/Ramp).
const RAMP_X := Vector2(-19.3, -16.7)
const RAMP_Z := Vector2(2.0, 14.0)
const WHEELCHAIR_NAV_GROUP := &"b10_nav_wheelchair"

@onready var _player: Player = $Player
@onready var _camera: Camera3D = $FieldSandbox/Camera3D
@onready var _manager: RescueManager = $RescueManager
@onready var _label: Label = $DebugLayer/InfoLabel

var _camera_offset := Vector3.ZERO
var _labels := {}
var _last_event := "-"
var _completed: Array = []
var _failures := 0
var _demo_running := false
var _chair_on_ramp := false


func _ready() -> void:
	# Before RescueManager's deferred _connect_extraction / spawn.
	add_to_group(RescueManager.EXTRACTION_GROUP)
	_camera_offset = _camera.global_position - _player.global_position
	_bake_navigation()
	_manager.target_spawned.connect(_on_target_spawned)
	EventBus.rescue_completed.connect(func(p: Dictionary) -> void:
		_completed.append(p.get("id"))
		_last_event = "rescue_completed %s" % p.get("id"))
	if DisplayServer.get_name() == "headless":
		_run_demo.call_deferred()


func _process(_delta: float) -> void:
	_camera.global_position = _player.global_position + _camera_offset
	var lines := PackedStringArray([
		"Player speed x%.1f  one hand only: %s" % [_player.move_speed_mult, _player.one_hand_only],
		"First aid kits: %d" % Bag.count_of(&"first_aid_kit"),
		"Event: %s" % _last_event,
	])
	for t in _targets():
		lines.append("%s: %s%s" % [t.display_name, RescueTarget.State.keys()[t.state], _extra(t)])
		_labels[t].text = "%s\n%s" % [t.display_name, RescueTarget.State.keys()[t.state]]
	lines.append("F interact, V follow/hide, 1-3 card, G kit, B break door, H hurt, X extract, P demo")
	_label.text = "\n".join(lines)


func _physics_process(_delta: float) -> void:
	for t in _targets():
		if t.spawn.move_type == RescueSpawn.Move.WHEELCHAIR:
			var p := t.global_position
			if p.x > RAMP_X.x and p.x < RAMP_X.y and p.z > RAMP_Z.x and p.z < RAMP_Z.y and p.y > 0.2:
				_chair_on_ramp = true


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1, KEY_2, KEY_3:
			for t in _targets():
				if t.state == RescueTarget.State.CARDS:
					_last_event = "card %s" % ("right" if t.answer_card(key.keycode - KEY_1) else "wrong")
		KEY_G:
			Bag.try_add(&"first_aid_kit", 1)
		KEY_B:
			for t in _targets():
				if t.has_node("Door"):
					(t.get_node("Door") as RescueDoor).take_damage(9999.0)
		KEY_H:
			var t := _nearest_follower()
			if t:
				t.take_damage(HURT_DAMAGE)
		KEY_X:
			_extract()
		KEY_P:
			if not _demo_running:
				_run_demo()


## B-09 stand-in: everyone in the party within 6m comes out, then rescue_completed.
func _extract() -> Dictionary:
	var rescued: Array[StringName] = []
	for node in get_tree().get_nodes_in_group(RescueTarget.PARTY_GROUP):
		var t := node as RescueTarget
		if t and t.global_position.distance_to(_player.global_position) <= PARTY_RADIUS:
			rescued.append(t.party_id)
	var result := {"extracted": true, "rescued": rescued}
	_last_event = "extracted with %s" % [rescued]
	sortie_result_ready.emit(result)
	return result


# --- Scripted demo -------------------------------------------------------------

func _run_demo() -> void:
	_demo_running = true
	await get_tree().create_timer(0.3).timeout
	var by_type := {}
	for t in _targets():
		by_type[t.spawn.rescue_type] = t
	_expect(by_type.size() == 3, "three rescue targets spawned")
	var elder: RescueTarget = by_type.get(RescueSpawn.Type.INJURED)
	var chair: RescueTarget = by_type.get(RescueSpawn.Type.TRAPPED)
	var child: RescueTarget = by_type.get(RescueSpawn.Type.COMMUNICATION)
	if elder == null or chair == null or child == null:
		_finish()
		return

	print("1. Injured elder: no kit, then a kit")
	await _go_next_to(elder.global_position)
	_expect(not _player.interact(), "no first aid kit: refused")
	Bag.try_add(&"first_aid_kit", 1)
	_expect(_player.interact() and elder.state == RescueTarget.State.FOLLOW, "kit used, elder supported")
	_expect(is_equal_approx(_player.move_speed_mult, 0.7) and _player.one_hand_only, "player slowed, one hand only")
	_player.velocity = Vector3.ZERO
	_expect(elder.command_hide(), "elder set down (hide)")

	print("2. Child: picture cards")
	await _go_next_to(child.global_position)
	_expect(_player.interact() and child.state == RescueTarget.State.CARDS, "cards shown")
	child.answer_card(2)
	child.answer_card(0)
	child.answer_card(1)
	_expect(child.state == RescueTarget.State.FOLLOW, "one wrong, two right: child follows")

	print("3. Wheelchair user: pick the elevator lock on the deck, come down by the ramp")
	var door: Vector3 = chair.get_node("Door").global_position
	await _go_next_to(Vector3(door.x, chair.global_position.y, door.z - 2.0))  # outside the door
	_expect(_player.interact() and chair.state == RescueTarget.State.LOCKPICKING, "lock picking started")
	_expect(await _wait(func() -> bool: return chair.state == RescueTarget.State.FOLLOW), "door open after 10 s")
	await _go_next_to(Vector3(-9.0, 0.0, 18.0))  # bottom of the stairs
	_expect(await _wait(func() -> bool:
		return chair.global_position.distance_to(_player.global_position) < 3.0), "wheelchair reached the player")
	_expect(_chair_on_ramp, "wheelchair came down the ramp, not the stairs")

	print("4. Pick the elder up again and extract")
	await _go_next_to(elder.global_position)
	_expect(elder.begin_open(_player) and elder.state == RescueTarget.State.FOLLOW, "elder supported again")
	for t: RescueTarget in [child, chair]:
		t.global_position = _player.global_position + Vector3(1.5, 0.0, 0.0)
	await get_tree().physics_frame
	_extract()
	_expect(_completed.size() == 3, "rescue_completed x3 (%s)" % [_completed])
	_finish()


func _finish() -> void:
	print("B10 DEMO %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	_demo_running = false
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failures > 0 else 0)


func _go_next_to(point: Vector3) -> void:
	_player.global_position = point + Vector3(0.0, 0.1, 1.0)
	_player.velocity = Vector3.ZERO
	for i in 3:
		await get_tree().physics_frame


func _wait(cond: Callable) -> bool:
	var left := STEP_TIMEOUT
	while left > 0.0:
		if cond.call():
			return true
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()
	return false


func _expect(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


# --- Helpers -------------------------------------------------------------------

## CSG builds its meshes after _ready, so bake one frame later. Both regions parse from Geometry
## (same root transform); layer 2 only takes the nodes in WHEELCHAIR_NAV_GROUP (no stairs).
func _bake_navigation() -> void:
	await get_tree().process_frame
	var geo := $FieldSandbox/Geometry
	for path in ["Floor", "Walls", "Cover", "Access/Deck", "Access/Ramp"]:
		geo.get_node(path).add_to_group(WHEELCHAIR_NAV_GROUP)
	_bake_region(0b01, geo, &"")
	_bake_region(0b10, geo, WHEELCHAIR_NAV_GROUP)


func _bake_region(layers: int, root: Node3D, group: StringName) -> void:
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 0.5
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = 1 << (Enums.LAYER_WORLD - 1)
	if group != &"":
		navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
		navmesh.geometry_source_group_name = group
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, root)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	var region := NavigationRegion3D.new()
	region.name = "NavLayer%d" % layers
	region.navigation_layers = layers
	region.navigation_mesh = navmesh
	root.add_child(region)


func _on_target_spawned(t: RescueTarget) -> void:
	var label := Label3D.new()
	label.position.y = 2.1
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.outline_size = 6
	t.add_child(label)
	_labels[t] = label
	t.card_round_started.connect(func(i: int, prompt: StringName, options: Array[StringName]) -> void:
		_last_event = "card round %d: %s %s" % [i + 1, prompt, options])
	t.item_needed.connect(func(id: StringName) -> void: _last_event = "needs %s" % id)
	t.isolated.connect(func() -> void: _last_event = "%s stranded" % t.display_name)


func _targets() -> Array[RescueTarget]:
	var out: Array[RescueTarget] = []
	for t in _manager.targets:
		if is_instance_valid(t):
			out.append(t)
	return out


func _nearest_follower() -> RescueTarget:
	var best: RescueTarget = null
	for t in _targets():
		if t.state == RescueTarget.State.FOLLOW and (best == null or
				t.global_position.distance_to(_player.global_position) < best.global_position.distance_to(_player.global_position)):
			best = t
	return best


func _extra(t: RescueTarget) -> String:
	match t.state:
		RescueTarget.State.LOCKPICKING:
			return " %.0f%%" % (t.lockpick_progress() * 100.0)
		RescueTarget.State.DOWNED:
			return " %.0f s" % t.down_time_left()
		RescueTarget.State.CARDS:
			var r := t.current_card_round()
			return " round %d %s %s" % [r["round_index"] + 1, r["prompt_id"], r["options"]]
	return "  hp %.0f" % t.health
