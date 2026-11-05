class_name RescueTarget
extends CharacterBody3D
## One person to rescue and escort (B-10). RescueManager spawns these on RescueSpots.
##
## Rescue: TRAPPED (pick the door lock 10 s or restore_power(); monsters breaking the door first
## turns it into a defend event), INJURED (use required_item, then the player supports them),
## COMMUNICATION (picture cards: card_round_started -> Lane D shows them -> answer_card()).
## Escort: follow (default) / hide (companion_command), 5 walking styles, footstep noise via
## NoiseEmitter (EventBus.noise_emitted), downed at 0 health, 30 s to help up or stranded.
##
## Contracts (shared with B-07 / B-09 / B-12):
## - Physics layer 3 (ally) while exposed (following, hiding, defending): monsters target it after the player.
## - Group ExtractionManager.PARTY_GROUP (&"escorts") with party_id / display_name / party_kind
##   from the moment it starts following, until it is stranded.
## - Wheelchair: nav layer 2 only (no stairs). Everyone else: nav layer 1.
## - Player.interact() reaches it on layer 7 (begin_open), only while there is something to do.
## Design reference: docs/design/02-field.md "구조 이벤트", "함께 나오기 (호위)".

signal state_changed(state: State)
## Rescue needs a bag item the player does not have (Lane D: notification).
signal item_needed(item_id: StringName)
## COMMUNICATION: show this round (Lane D). options = card ids, answer with answer_card(index).
signal card_round_started(round_index: int, prompt_id: StringName, options: Array[StringName])
signal card_answered(correct: bool, strikes: int)
signal downed()
signal revived()
## Not helped up in time: stays on the spot, leaves the party.
signal isolated()

enum State { WAITING, LOCKPICKING, CARDS, DEFEND, WARY, FOLLOW, HIDE, DOWNED, ISOLATED }

const GROUP := &"field_rescue_targets"
## B-09 extraction checks this group (6m, "두고 갈까요?").
const PARTY_GROUP := ExtractionManager.PARTY_GROUP
const PARTY_KIND := ExtractionManager.KIND_RESCUED
## 숨기 goes behind low cover (B-06).
const COVER_GROUP := WeaponHolder.LOW_COVER_GROUP
const DEFAULT_TUNING := preload("res://data/classes/rescue_tuning.tres")
## Used when no player is known yet (m/s, player_base walk_speed).
const FALLBACK_WALK_SPEED := 4.5
const WAYPOINT_REACHED := 0.3
const MOVING_SPEED := 0.1
const EXPOSED: Array[State] = [State.FOLLOW, State.HIDE, State.DEFEND]

@export var spawn: RescueSpawn
@export var tuning: RescueTuning = DEFAULT_TUNING

## Read by ExtractionManager (B-09).
var party_id: StringName = &""
var display_name := ""
var party_kind := PARTY_KIND
## Rescue profile (DemoProfiles entry or Colony resident). Sent with rescue_completed.
var profile: Dictionary = {}
## Tags of the RescueSpot it stands on (RescuePowerSwitch matches these).
var spot_tags: Array[StringName] = []
var state := State.WAITING
var health := 0.0

var _player: Node3D
var _door: RescueDoor
var _channel_left := 0.0
var _channel_from := Vector3.ZERO
var _defend_left := 0.0
var _down_left := 0.0
var _before_down := State.FOLLOW
var _round := 0
var _strikes := 0
var _rescued := false
var _supporting := false
var _startle_left := 0.0
var _low_health_said := false
var _hide_point := Vector3.ZERO
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF
var _repath_left := 0.0
var _noisy := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _noise: NoiseEmitter = $Noise


## Call before adding to the tree.
func setup(p_spawn: RescueSpawn, p_profile: Dictionary, p_spot_tags: Array[StringName] = []) -> void:
	spawn = p_spawn
	profile = p_profile
	spot_tags = p_spot_tags
	party_id = spawn.party_id()
	display_name = str(profile.get("name", party_id))


func _ready() -> void:
	add_to_group(GROUP)
	health = tuning.max_health
	collision_mask = 1 << (Enums.LAYER_WORLD - 1)
	EventBus.noise_emitted.connect(_on_noise)
	if spawn.rescue_type == RescueSpawn.Type.TRAPPED:
		_make_door()
	_apply_layers()


func _exit_tree() -> void:
	_set_supporting(false)


func _physics_process(delta: float) -> void:
	tick(delta)
	if state == State.FOLLOW and _supporting:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


# --- Public API ----------------------------------------------------------------

## Player.interact() entry (layer 7). Starts or advances whatever this person needs.
func begin_open(interactor: Node3D) -> bool:
	match state:
		State.WAITING:
			match spawn.rescue_type:
				RescueSpawn.Type.INJURED:
					return _treat(interactor)
				RescueSpawn.Type.COMMUNICATION:
					return _start_cards(interactor)
		State.DOWNED:
			return revive(interactor)
		State.HIDE:
			return command_follow(interactor)
	return false


## 갇힘: start picking the door lock. The door forwards Player.interact() here.
func begin_lockpick(interactor: Node3D) -> bool:
	if state != State.WAITING or spawn.rescue_type != RescueSpawn.Type.TRAPPED:
		return false
	_player = interactor
	_channel_from = interactor.global_position
	_channel_left = tuning.lockpick_sec
	_set_state(State.LOCKPICKING)
	return true


## 0..1 lock picking progress (Lane D ring).
func lockpick_progress() -> float:
	if state != State.LOCKPICKING or tuning.lockpick_sec <= 0.0:
		return 0.0
	return clampf(1.0 - _channel_left / tuning.lockpick_sec, 0.0, 1.0)


## 갇힘: power is back (elevator). Opens at once.
func restore_power() -> bool:
	if state != State.WAITING and state != State.LOCKPICKING:
		return false
	if spawn.rescue_type != RescueSpawn.Type.TRAPPED:
		return false
	_remove_door()
	_rescue(_player if _player else _find_player())
	return true


## COMMUNICATION: pick card `index` of the current round. Returns true when it was right.
func answer_card(index: int) -> bool:
	if state != State.CARDS:
		return false
	var current := spawn.card_rounds[_round]
	var correct := index == current.answer
	if correct:
		_round += 1
	else:
		_strikes += 1
	card_answered.emit(correct, _strikes)
	if not correct and _strikes >= tuning.card_strikes:
		_set_state(State.WARY)
	elif _round >= spawn.card_rounds.size():
		_rescue(_player)
	else:
		_present_round()
	return correct


## Current round for Lane D: {round_index, prompt_id, options} or {} outside the card event.
func current_card_round() -> Dictionary:
	if state != State.CARDS:
		return {}
	var r := spawn.card_rounds[_round]
	return {"round_index": _round, "prompt_id": r.prompt_id, "options": r.options}


## 숨기: go to the nearest low cover and wait. A supported person is set down where they are.
func command_hide() -> bool:
	if state != State.FOLLOW:
		return false
	if _supporting:
		_set_supporting(false)
		_hide_point = global_position
	else:
		_hide_point = _find_cover_point()
	_set_state(State.HIDE)
	return true


## 따라오기. A supported person needs the player within support_pickup_range.
func command_follow(player: Node3D = null) -> bool:
	if state != State.HIDE:
		return false
	if player != null:
		_player = player
	if _player == null:
		_player = _find_player()
	if spawn.move_type == RescueSpawn.Move.SUPPORTED:
		if _player == null or _flat_distance(_player.global_position) > tuning.support_pickup_range:
			return false
		if _support_busy():
			return false
	_set_state(State.FOLLOW)
	return true


## Help up a downed person. Returns false when not downed.
func revive(interactor: Node3D) -> bool:
	if state != State.DOWNED:
		return false
	_player = interactor
	health = tuning.max_health * tuning.revive_health_ratio
	_low_health_said = false
	if _before_down == State.DEFEND:
		_set_state(State.DEFEND)
	elif spawn.move_type == RescueSpawn.Move.SUPPORTED and _support_busy():
		_hide_point = global_position
		_set_state(State.HIDE)
	else:
		_set_state(State.FOLLOW)
	revived.emit()
	return true


## Damage from monsters (B-07 calls take_damage(amount, info) on layer 3 bodies).
func take_damage(amount: float, _info: Dictionary = {}) -> void:
	if not EXPOSED.has(state) or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if not _low_health_said and health > 0.0 and health <= tuning.max_health * tuning.low_health_ratio:
		_low_health_said = true
		Radio.say(&"rescuee_low_health", {"name": display_name})
	if health == 0.0:
		_go_down()


## Started following at least once (rescued, still to be brought out).
func is_rescued() -> bool:
	return _rescued


## Current walking speed (m/s). SUPPORTED moves with the player (player speed x speed_mult).
func move_speed() -> float:
	var walk := FALLBACK_WALK_SPEED
	var player := _player if _player else _find_player()
	if player != null and player.get("stats") != null:
		walk = player.stats.walk_speed
	if spawn.move_type == RescueSpawn.Move.SUPPORTED:
		walk *= tuning.speed_mult.get(RescueSpawn.Move.SUPPORTED, 1.0)
		return walk
	return walk * tuning.speed_mult.get(spawn.move_type, 1.0)


func down_time_left() -> float:
	return _down_left if state == State.DOWNED else 0.0


func is_startled() -> bool:
	return _startle_left > 0.0


## One step (timers, following, noise). _physics_process calls it; tests can call it directly.
func tick(delta: float) -> void:
	match state:
		State.LOCKPICKING:
			_tick_lockpick(delta)
		State.DEFEND:
			_defend_left -= delta
			if _defend_left <= 0.0:
				_rescue(_find_player())
		State.DOWNED:
			_down_left -= delta
			if _down_left <= 0.0:
				_isolate()
		State.FOLLOW:
			_tick_follow(delta)
		State.HIDE:
			_walk_toward(_hide_point, WAYPOINT_REACHED, delta)
	_update_noise()


# --- Rescue --------------------------------------------------------------------

func _treat(interactor: Node3D) -> bool:
	var item := spawn.required_item
	if item != &"" and Bag.count_of(item) < 1:
		item_needed.emit(item)
		return false
	_player = interactor
	if spawn.move_type == RescueSpawn.Move.SUPPORTED and _support_busy():
		return false
	if item != &"":
		Bag.remove_item(item, 1)
	_rescue(interactor)
	return true


func _start_cards(interactor: Node3D) -> bool:
	_player = interactor
	if spawn.card_rounds.is_empty() or Colony.has_completed(tuning.interpreter_building):
		_rescue(interactor)
		return true
	_round = 0
	_set_state(State.CARDS)
	_present_round()
	return true


func _present_round() -> void:
	var r := spawn.card_rounds[_round]
	card_round_started.emit(_round, r.prompt_id, r.options)


func _tick_lockpick(delta: float) -> void:
	if _player == null or _player.global_position.distance_to(_channel_from) > tuning.channel_cancel_distance:
		_set_state(State.WAITING)
		return
	_channel_left -= delta
	if _channel_left <= 0.0:
		_remove_door()
		_rescue(_player)


func _on_door_broken() -> void:
	if state != State.WAITING and state != State.LOCKPICKING:
		return
	_remove_door()
	_defend_left = tuning.defend_sec
	_set_state(State.DEFEND)


func _rescue(player: Node3D) -> void:
	if player != null:
		_player = player
	if not _rescued:
		_rescued = true
		add_to_group(PARTY_GROUP)
	_set_state(State.FOLLOW)


func _make_door() -> void:
	_door = RescueDoor.new()
	_door.name = "Door"
	_door.target = self
	_door.health = tuning.door_health
	_door.broken.connect(_on_door_broken)
	add_child(_door)


func _remove_door() -> void:
	if _door == null:
		return
	_door.collision_layer = 0
	_door.queue_free()
	_door = null


# --- Escort --------------------------------------------------------------------

func _tick_follow(delta: float) -> void:
	if _player == null:
		_player = _find_player()
		if _player == null:
			return
	if _supporting:
		var right := _player.global_basis.x
		right.y = 0.0
		global_position = _player.global_position + right.normalized() * tuning.support_offset
		velocity = Vector3.ZERO
		return
	if _startle_left > 0.0:
		_startle_left = maxf(_startle_left - delta, 0.0)
		_stop()
		return
	_walk_toward(_player.global_position, tuning.follow_distance, delta)


## Walks the nav path (layers from the spawn) toward goal until stop_distance (flat) is reached.
## No path (e.g. a wheelchair facing stairs only) = stays put.
func _walk_toward(goal: Vector3, stop_distance: float, delta: float) -> void:
	if _flat_distance(goal) <= stop_distance:
		_stop()
		return
	_repath_left -= delta
	if _repath_left <= 0.0 or _path_goal.distance_to(goal) > tuning.follow_distance * 0.5:
		_repath(goal)
	while _path_index < _path.size() and _flat_distance(_path[_path_index]) < WAYPOINT_REACHED:
		_path_index += 1
	if _path_index >= _path.size():
		_stop()
		return
	var to := _path[_path_index] - global_position
	to.y = 0.0
	var dir := to.normalized()
	var speed := move_speed()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	rotation.y = atan2(-dir.x, -dir.z)


func _repath(goal: Vector3) -> void:
	_repath_left = tuning.repath_sec
	_path_goal = goal
	_path_index = 0
	_path = NavigationServer3D.map_get_path(
			get_world_3d().navigation_map, global_position, goal, true, spawn.navigation_layers())
	# An unreachable goal (wheelchair, stairs only) gives a path to the closest reachable point:
	# they wait there instead of going up.


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _find_cover_point() -> Vector3:
	var best: Node3D = null
	var best_dist := tuning.hide_search_radius
	for node in get_tree().get_nodes_in_group(COVER_GROUP):
		var cover := node as Node3D
		if cover == null:
			continue
		var d := _flat_distance(cover.global_position)
		if d < best_dist:
			best = cover
			best_dist = d
	if best == null:
		return global_position
	var away := global_position - best.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3.BACK
	var point := best.global_position + away.normalized() * 1.0
	point.y = global_position.y
	return point


func _set_supporting(on: bool) -> void:
	if on == _supporting:
		return
	_supporting = on
	if not is_instance_valid(_player):
		return
	# Player hooks (field/player/player.gd): speed x0.7 and one-hand weapons while supporting.
	_player.set(&"move_speed_mult", tuning.speed_mult.get(RescueSpawn.Move.SUPPORTED, 1.0) if on else 1.0)
	_player.set(&"one_hand_only", on)


## The player already supports someone else.
func _support_busy() -> bool:
	for node in get_tree().get_nodes_in_group(GROUP):
		if node != self and node is RescueTarget and node._supporting and node._player == _player:
			return true
	return false


func _on_noise(position: Vector3, radius: float, source: Node) -> void:
	if spawn.move_type != RescueSpawn.Move.CHILD or state != State.FOLLOW or source == self:
		return
	if radius >= tuning.loud_noise_radius and global_position.distance_to(position) <= radius:
		_startle_left = tuning.startle_sec


func _update_noise() -> void:
	var moving := false
	if state == State.FOLLOW and _supporting:
		var body := _player as CharacterBody3D
		moving = body != null and Vector2(body.velocity.x, body.velocity.z).length() > MOVING_SPEED
	elif state == State.FOLLOW or state == State.HIDE:
		moving = Vector2(velocity.x, velocity.z).length() > MOVING_SPEED
	if moving == _noisy:
		return
	_noisy = moving
	if moving:
		_noise.start_continuous(tuning.move_noise.get(spawn.move_type, &"escort_walk"))
	else:
		_noise.stop_continuous()


# --- Downed --------------------------------------------------------------------

func _go_down() -> void:
	_before_down = state
	_set_supporting(false)
	_stop()
	_down_left = tuning.downed_sec
	_set_state(State.DOWNED)
	downed.emit()


func _isolate() -> void:
	_set_supporting(false)
	remove_from_group(PARTY_GROUP)
	_set_state(State.ISOLATED)
	isolated.emit()
	if spawn.resident_id != &"":
		FieldState.strand_companion(spawn.resident_id)


# --- Helpers -------------------------------------------------------------------

func _set_state(next: State) -> void:
	if next == state:
		return
	state = next
	if state == State.FOLLOW and spawn.move_type == RescueSpawn.Move.SUPPORTED:
		_set_supporting(true)
	elif state != State.FOLLOW:
		_set_supporting(false)
	if state != State.FOLLOW and state != State.HIDE:
		_stop()
	_repath_left = 0.0
	_apply_layers()
	state_changed.emit(state)


## Layer 3 (ally) while exposed, layer 7 (interactable) only while the player can do something here.
func _apply_layers() -> void:
	var interactable := false
	match state:
		State.WAITING:
			interactable = spawn.rescue_type != RescueSpawn.Type.TRAPPED
		State.DOWNED:
			interactable = true
		State.HIDE:
			interactable = spawn.move_type == RescueSpawn.Move.SUPPORTED
	set_collision_layer_value(Enums.LAYER_ALLY, EXPOSED.has(state))
	set_collision_layer_value(Enums.LAYER_INTERACTABLE, interactable)


func _find_player() -> Node3D:
	return get_tree().get_first_node_in_group(Player.GROUP) as Node3D if is_inside_tree() else null


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()
