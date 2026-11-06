class_name RescueCall
extends Node
## 살려주는 주민: the first time the player goes down in a sortie, residents come to help them up.
## A companion who is still up runs over first. With none, up to tuning.rescue_call_count base
## residents (highest trust first) set out tuning.rescue_call_spawn_distance m away, toward the
## entry. They are ordinary companions after that and must be brought home too.
## Nobody helps the player up within rescue_call_wait_sec, or every rescuer goes down: the normal
## down (Player.give_up), and the rescuers are stranded with the rest (FieldState).
## Child of CompanionManager (added in its _ready on field maps). Tests drive tick() directly.
## Design reference: docs/design/02-field.md "살려주는 주민".

enum State { READY, WAITING, USED }

const RADIO_ID := &"rescue_call"

var state := State.READY
var rescuers: Array[FieldCompanion] = []
var _manager: CompanionManager
var _player: Player
var _wait_left := 0.0
var _helper: FieldCompanion
var _help_left := 0.0


func _ready() -> void:
	_manager = get_parent() as CompanionManager
	_bind_player.call_deferred()


func _physics_process(delta: float) -> void:
	tick(delta)


## Hooks the player's down. Called deferred from _ready; tests call it with their own player.
func bind(player: Player) -> void:
	_player = player
	if _player != null and _player.field_rules:
		_player.down_interceptor = _on_player_down


func wait_left() -> float:
	return _wait_left if state == State.WAITING else 0.0


## One step while someone is coming. Like a companion's help-up, the wait pauses while helping.
func tick(delta: float) -> void:
	if state != State.WAITING:
		return
	var t := _manager.tuning
	var up := rescuers.filter(func(c: FieldCompanion) -> bool:
		return is_instance_valid(c) and c.state == FieldCompanion.State.ACTIVE)
	if not up.has(_helper):
		_helper = null
	if _helper == null:
		_wait_left -= delta
		if up.is_empty() or _wait_left <= 0.0:
			_finish(false)
			return
		for c: FieldCompanion in up:
			if _flat_distance(c, _player) <= t.rescue_call_reach:
				_helper = c
				_help_left = t.revive_sec
				break
	else:
		_help_left -= delta
		if _help_left <= 0.0:
			_finish(true)


func _bind_player() -> void:
	bind(get_tree().get_first_node_in_group(Player.GROUP) as Player)


## Player.down_interceptor. True = someone is coming.
func _on_player_down() -> bool:
	if state != State.READY or _manager == null:
		return false
	rescuers = _pick_rescuers()
	if rescuers.is_empty():
		return false
	state = State.WAITING
	_wait_left = _manager.tuning.rescue_call_wait_sec
	_helper = null
	for c in rescuers:
		c.rush_to = _player
	Radio.say(RADIO_ID, {"name": rescuers[0].display_name})
	return true


func _finish(saved: bool) -> void:
	state = State.USED
	for c in rescuers:
		if is_instance_valid(c):
			c.rush_to = null
	if not saved:
		_player.give_up()
		return
	_player.revive(_manager.tuning.rescue_call_health_ratio)
	CombatFeel.hit_stop(_player, CombatFeel.STOP_SIGNATURE)
	var lines := _manager.tuning.rescue_call_lines
	if not lines.is_empty():
		_helper.called_out.emit(lines[randi() % lines.size()], true)


## Companions still up; else base residents who can come, highest trust first.
func _pick_rescuers() -> Array[FieldCompanion]:
	var out: Array[FieldCompanion] = []
	for c in _manager.companions:
		if is_instance_valid(c) and c.state == FieldCompanion.State.ACTIVE:
			out.append(c)
	if not out.is_empty():
		return out
	var t := _manager.tuning
	var room := mini(t.rescue_call_count, t.max_companions - _manager.companions.size())
	if room <= 0:
		return out
	var ids: Array[StringName] = []
	for id in Colony.active_resident_ids():
		if not FieldState.companions.has(id) and CompanionManager.can_come(Colony.get_resident(id)):
			ids.append(id)
	if ids.is_empty():
		return out
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return int(Colony.get_resident(a).get("trust", 0)) > int(Colony.get_resident(b).get("trust", 0)))
	ids.resize(mini(ids.size(), room))
	out = _manager.spawn_ids(ids, _start_point())
	for c in out:
		# Stranded with the player (FieldState._on_player_downed) if nobody makes it in time.
		FieldState.companions.append(c.party_id)
	return out


## On the nav mesh, rescue_call_spawn_distance m from the player toward the entry (PlayerSpawn).
func _start_point() -> Vector3:
	var from := _player.global_position
	var spawn := get_tree().get_first_node_in_group(PlayerSpawn.GROUP) as Node3D
	var dir := (spawn.global_position - from) if spawn != null else _player.global_basis.z
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.BACK
	var goal := from + dir * _manager.tuning.rescue_call_spawn_distance
	var map := _player.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0 or NavigationServer3D.map_get_regions(map).is_empty():
		return goal  # no nav mesh (tests, scenes without navigation)
	return NavigationServer3D.map_get_closest_point(map, goal)


static func _flat_distance(a: Node3D, b: Node3D) -> float:
	var d := a.global_position - b.global_position
	return Vector2(d.x, d.z).length()
