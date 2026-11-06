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
## A landed hit (amount after status scaling), the same shape as Monster.damaged. FxFeedback flashes it.
signal damaged(amount: float, info: Dictionary)
## Not helped up in time: stays on the spot, leaves the party.
signal isolated()
## Heard the player while waiting to be found (tuning callout_far_m, through walls). Lane D shows
## `text` in a speech bubble at this person. near = the player is close, they beg for help.
signal called_out(text: String, near: bool)

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
## HUD hold bar text while being helped up.
const REVIVE_HOLD_LABEL := "일으키는 중"
const WAYPOINT_REACHED := 0.3
const MOVING_SPEED := 0.1
## _face_open_side(): rays, their length (m), and how much more open a side must be to turn.
const OPEN_PROBE_DIRS := 8
const OPEN_PROBE_M := 6.0
const OPEN_PROBE_MARGIN := 0.5
## A supported person turns to the player's walking direction only above this speed (m/s).
const SUPPORT_TURN_SPEED := 0.5
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
## Who is helping this downed person up (3 s hold), or null.
var _reviver: Node3D
var _revive_left := 0.0
var _revive_from := Vector3.ZERO
var _round := 0
var _strikes := 0
var _rescued := false
var _supporting := false
var _support_dir := Vector3.FORWARD  # the player's last walking direction (flat, unit)
var _startle_left := 0.0
var _low_health_said := false
var _hide_point := Vector3.ZERO
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF
var _repath_left := 0.0
var _noisy := false
var _callout_left := 0.0
## How close the player was last step: 0 out of range, 1 far, 2 near.
var _callout_tier := 0
## near (bool) -> how many lines of that kind were said.
var _callout_said := {false: 0, true: 0}
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _noise: NoiseEmitter = $Noise
## Status effects (B-14). Lane D listens to its signals.
@onready var status: StatusHolder = StatusHolder.attach(self)


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
		_face_open_side.call_deferred()
	_apply_layers()
	# Pack character model (Lane D, ResidentModel). Missing assets: the greybox stays.
	($Model as ResidentModel).show_resident(profile, spawn.move_type)


func _exit_tree() -> void:
	_set_supporting(false)


func _physics_process(delta: float) -> void:
	tick(delta)
	if state == State.FOLLOW and _supporting:
		return
	# Slow / bind scale the walking velocity; knockback replaces it (B-14).
	velocity = status.steer(velocity)
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
			return begin_revive(interactor)
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


## 일으키기 (03: F 3초, same as companions): starts the hold. The 30 s wait pauses meanwhile;
## the helper moving away (channel_cancel_distance) or going down cancels it.
func begin_revive(interactor: Node3D) -> bool:
	if state != State.DOWNED or _reviver != null or interactor == null:
		return false
	_reviver = interactor
	_revive_from = interactor.global_position
	_revive_left = tuning.revive_sec
	return true


## HUD hold bar while being helped up (Player.hud_state "hold"), {} otherwise.
func hold_state() -> Dictionary:
	if _reviver == null or tuning.revive_sec <= 0.0:
		return {}
	return {"label": REVIVE_HOLD_LABEL, "progress": clampf(1.0 - _revive_left / tuning.revive_sec, 0.0, 1.0)}


## Help up a downed person at once (the end of the 3 s hold). Returns false when not downed.
func revive(interactor: Node3D) -> bool:
	if state != State.DOWNED:
		return false
	_reviver = null
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
## Status effects ride in info (StatusHolder header).
func take_damage(amount: float, info: Dictionary = {}) -> void:
	if not EXPOSED.has(state) or amount <= 0.0:
		return
	amount = status.scale_damage(amount, info)
	status.apply_hit(info)
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, info)
	if not _low_health_said and health > 0.0 and health <= tuning.max_health * tuning.low_health_ratio:
		_low_health_said = true
		Radio.say(&"rescuee_low_health", {"name": display_name})
	if health == 0.0:
		_go_down()


## Started following at least once (rescued, still to be brought out).
func is_rescued() -> bool:
	return _rescued


## Where a rescue quest objective (Quests.active_field_objectives entry) points once its person is
## following: the open extraction point nearest the player. null while nobody is following yet (the
## objective's own marker is used then) or when no point is open. Used by the HUD, minimap and map.
static func escort_goal(tree: SceneTree, objective: Dictionary) -> Node3D:
	if StringName(objective.get("kind", &"")) != &"rescue":
		return null
	var target_id := StringName(objective.get("target_id", &""))
	var following := false
	for n: Node in tree.get_nodes_in_group(GROUP):
		var t := n as RescueTarget
		if t != null and t.is_rescued() and (target_id == &"" or StringName(t.profile.get("id", &"")) == target_id):
			following = true
			break
	var em := tree.get_first_node_in_group(ExtractionManager.GROUP) as ExtractionManager
	if not following or em == null:
		return null
	var player := tree.get_first_node_in_group(&"player") as Node3D
	var best: Node3D = null
	var best_d := INF
	for e: ExtractPoint in em.active_points():
		var d := e.global_position.distance_squared_to(player.global_position) if player != null else 0.0
		if d < best_d:
			best = e
			best_d = d
	return best


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
	status.step(delta)
	_tick_callout(delta)
	match state:
		State.LOCKPICKING:
			_tick_lockpick(delta)
		State.DEFEND:
			_defend_left -= delta
			if _defend_left <= 0.0:
				_rescue(_find_player())
		State.DOWNED:
			if _reviver != null:
				_tick_revive(delta)
			else:
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


## Hold F to fill the gauge; letting go (or walking off) empties it (user playtest 2026-11-06).
## Interactors without `interact_held` (not the player) count as holding.
func _tick_lockpick(delta: float) -> void:
	var held: Variant = _player.get(&"interact_held") if _player != null else false
	if _player == null or held == false \
			or _player.global_position.distance_to(_channel_from) > tuning.lockpick_leave_m:
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


## Turns toward the most open side (8 rays on the world layer), so the door (TRAPPED) sits in the
## opening, not against a wall. Keeps the spot's facing
## unless another side is clearly more open (the elevator car: the doorway, user playtest 2026-11-06).
func _face_open_side() -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP
	var front := -global_basis.z
	front.y = 0.0
	front = front.normalized() if front.length() > 0.01 else Vector3.FORWARD
	var best_dir := front
	var best := _free_distance(space, from, front)
	for i in OPEN_PROBE_DIRS:
		var dir := front.rotated(Vector3.UP, TAU * i / OPEN_PROBE_DIRS)
		var free := _free_distance(space, from, dir)
		if free > best + OPEN_PROBE_MARGIN:
			best = free
			best_dir = dir
	if best_dir != front:
		look_at(global_position + best_dir, Vector3.UP)


func _free_distance(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * OPEN_PROBE_M,
		1 << (Enums.LAYER_WORLD - 1), [get_rid()])
	var hit := space.intersect_ray(query)
	return OPEN_PROBE_M if hit.is_empty() else from.distance_to(hit["position"])


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


# --- Call out ------------------------------------------------------------------

## While waiting to be found: call out when the player comes within callout_far_m, again every
## callout_interval_sec, and at once when the player first comes within callout_near_m.
func _tick_callout(delta: float) -> void:
	_callout_left = maxf(_callout_left - delta, 0.0)
	if state != State.WAITING:
		_callout_tier = 0
		return
	var player := _player if _player else _find_player()
	if player == null:
		return
	var d := global_position.distance_to(player.global_position)
	var tier := 2 if d <= tuning.callout_near_m else (1 if d <= tuning.callout_far_m else 0)
	if tier > 0 and (_callout_left <= 0.0 or (tier == 2 and _callout_tier < 2)):
		_call_out(tier == 2)
	_callout_tier = tier


func _call_out(near: bool) -> void:
	var table := tuning.callout_near_lines if near else tuning.callout_far_lines
	var lines: PackedStringArray = table.get(spawn.rescue_type, PackedStringArray())
	if lines.is_empty():
		return
	var said: int = _callout_said[near]
	_callout_said[near] = said + 1
	_callout_left = tuning.callout_interval_sec
	called_out.emit(lines[said % lines.size()], near)


# --- Escort --------------------------------------------------------------------

func _tick_follow(delta: float) -> void:
	if _player == null:
		_player = _find_player()
		if _player == null:
			return
	var moved := _player_flat_velocity()
	if _supporting:
		# Side and facing follow where the player walks, not where they aim: aiming backward while
		# walking forward must not swing the supported person around.
		if moved.length() > SUPPORT_TURN_SPEED:
			_support_dir = moved.normalized()
		var right := Vector3(-_support_dir.z, 0.0, _support_dir.x)
		global_position = _player.global_position + right * tuning.support_offset
		rotation.y = atan2(-_support_dir.x, -_support_dir.z)
		velocity = Vector3.ZERO
		return
	if _startle_left > 0.0:
		_startle_left = maxf(_startle_left - delta, 0.0)
		_stop()
		return
	var gap := _flat_distance(_player.global_position) - tuning.follow_distance
	_walk_toward(_player.global_position, tuning.follow_distance, delta,
		moved.length() + maxf(gap, 0.0) * tuning.follow_catch_up)


func _player_flat_velocity() -> Vector3:
	var v: Variant = _player.get(&"velocity") if _player != null else null
	return Vector3(v.x, 0.0, v.z) if v is Vector3 else Vector3.ZERO


## Walks the nav path (layers from the spawn) toward goal until stop_distance (flat) is reached.
## No path (e.g. a wheelchair facing stairs only) = stays put. `max_speed` < 0: own walking speed.
func _walk_toward(goal: Vector3, stop_distance: float, delta: float, max_speed := -1.0) -> void:
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
	var speed := move_speed() if max_speed < 0.0 else minf(move_speed(), max_speed)
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
	if on:
		var ahead := -_player.global_basis.z
		ahead.y = 0.0
		_support_dir = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
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
	status.clear()
	_down_left = tuning.downed_sec
	_set_state(State.DOWNED)
	downed.emit()


func _tick_revive(delta: float) -> void:
	if not is_instance_valid(_reviver) or _reviver.get(&"is_downed") == true \
			or _reviver.global_position.distance_to(_revive_from) > tuning.channel_cancel_distance:
		_reviver = null
		return
	_revive_left -= delta
	if _revive_left <= 0.0:
		revive(_reviver)


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


## [F] prompt words (Player HUD "prompt"; empty = nothing to do with F right now). QA 플레이 준비.
func interact_label() -> String:
	match state:
		State.WAITING:
			match spawn.rescue_type:
				RescueSpawn.Type.INJURED:
					var item := spawn.required_item
					if item != &"":
						var def: Variant = Economy.get_def(item)
						var item_name := String(def.name) if def != null else String(item)
						if Bag.count_of(item) < 1:
							return "치료하기 / %s 필요" % item_name
						return "치료하기"
					return "일으켜 세우기"
				RescueSpawn.Type.COMMUNICATION:
					return "말 걸기"
				RescueSpawn.Type.TRAPPED:
					return ""  # the door in front takes F
		State.DOWNED:
			return "일으키기"
		State.HIDE:
			return "따라오게 하기"
	return ""
