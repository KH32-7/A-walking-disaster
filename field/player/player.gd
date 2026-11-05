class_name Player
extends CharacterBody3D
## Player controller (B-03): walk, sprint, aim-walk, dodge, stamina, health.
## Numbers come from `stats` (data/classes/player_base.tres). Input uses only
## InputSetup action names; toggle aim / toggle sprint follow Settings.
## Other lanes read state through the signals and getters below.
## Design reference: docs/design/03-combat-classes.md "플레이어 기본 수치"

signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal move_state_changed(state: MoveState)
signal downed()

## B-05 maps these to noise radii (aim-walk 0m, walk 4m, sprint 8m, dodge 5m).
enum MoveState { IDLE, WALK, SPRINT, AIM_WALK, DODGE }

const GROUP := &"player"
## NoiseTable action per move state. Footsteps repeat every table.continuous_interval_sec;
## the dodge is one "roll" noise. States not listed make no noise (AIM_WALK is 0m anyway).
const MOVE_NOISE := {
	MoveState.WALK: &"walk",
	MoveState.SPRINT: &"sprint",
}
const DODGE_NOISE := &"roll"
## Interaction query: sphere centered at body height, at most this many candidates.
const INTERACT_HEIGHT := 0.9
const INTERACT_MAX_HITS := 8

@export var stats: PlayerStats = preload("res://data/classes/player_base.tres")

var health: float
var stamina: float
var is_aiming := false
var move_state := MoveState.IDLE
var is_downed := false
## Set by WeaponHolder (B-06): (amount, info) -> damage left after blocking.
var incoming_damage_filter: Callable

var _aim_toggled := false
var _sprint_toggled := false
var _since_stamina_use := 0.0
var _dodge_left := 0.0
var _dodge_elapsed := 0.0
var _dodge_dir := Vector3.ZERO
var _facing := Vector3.FORWARD
var _aim_point: Variant = null
var _bound_left := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _noise: NoiseEmitter = $Noise


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 1 << (Enums.LAYER_PLAYER - 1)
	collision_mask = (1 << (Enums.LAYER_WORLD - 1)) | (1 << (Enums.LAYER_MONSTER - 1))
	# TODO(A-11): add stats.health_per_level per player level once progression exists.
	health = stats.max_health
	stamina = stats.max_stamina
	_since_stamina_use = stats.stamina_regen_delay_sec


func _physics_process(delta: float) -> void:
	if is_downed:
		return
	step(delta, _read_input())
	move_and_slide()
	if Input.is_action_just_pressed(&"interact"):
		interact()


## Starts using the nearest interactable in reach (loot containers for now).
## Returns false when nothing is in reach or it refused.
## Uses a shape query, not an Area3D: Jolt areas do not report static bodies by default.
func interact() -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = stats.interact_range
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position + Vector3.UP * INTERACT_HEIGHT)
	query.collision_mask = 1 << (Enums.LAYER_INTERACTABLE - 1)
	var best: Node3D = null
	var best_dist := INF
	for hit in get_world_3d().direct_space_state.intersect_shape(query, INTERACT_MAX_HITS):
		var body := hit.collider as Node3D
		if body == null or not body.has_method("begin_open"):
			continue
		var dist := global_position.distance_squared_to(body.global_position)
		if dist < best_dist:
			best = body
			best_dist = dist
	return best != null and best.begin_open(self)


func is_bound() -> bool:
	return _bound_left > 0.0


## Stagger (B-06 guard break): same movement lock as a bind until B-14 owns status effects.
func stun(sec: float) -> void:
	_bound_left = maxf(_bound_left, sec)


## Weapons (B-06) pay melee and block stamina through this, so regen delay restarts.
func spend_stamina(amount: float) -> void:
	_spend_stamina(amount)


## World point to face while aiming (B-04 camera sets it from the cursor or stick).
func set_aim_point(point: Vector3) -> void:
	_aim_point = point


func facing() -> Vector3:
	return _facing


func is_invulnerable() -> bool:
	return move_state == MoveState.DODGE and _dodge_elapsed < stats.dodge_invuln_sec


## Damage entry point for monsters and hazards. Reads info["bind_sec"] (vine tendril);
## other keys (element, knockback, status effects) are for B-06/B-14.
## DebugConsole `godmode` blocks everything.
func take_damage(amount: float, info: Dictionary = {}) -> void:
	if is_downed or is_invulnerable() or amount <= 0.0 or DebugConsole.godmode:
		return
	if incoming_damage_filter.is_valid():
		amount = incoming_damage_filter.call(amount, info)
		if amount <= 0.0:
			return
	_bound_left = maxf(_bound_left, info.get("bind_sec", 0.0))
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, stats.max_health)
	if health == 0.0:
		is_downed = true
		velocity = Vector3.ZERO
		downed.emit()
		EventBus.player_downed.emit()


## One simulation step. Split from input reading so tests can drive it.
## input: {"move": Vector2, "aim": bool, "sprint": bool, "dodge": bool}
func step(delta: float, input: Dictionary) -> void:
	var dir := _to_world(input.get("move", Vector2.ZERO))
	if _bound_left > 0.0:
		# Bound (B-14 will own status effects): no moving or dodging, aiming still works.
		_bound_left = maxf(_bound_left - delta, 0.0)
		dir = Vector3.ZERO
		input = input.merged({"dodge": false, "sprint": false}, true)
	if move_state == MoveState.DODGE:
		_step_dodge(delta)
	elif input.get("dodge", false) and stamina >= stats.dodge_stamina:
		_start_dodge(dir)
	else:
		_step_move(delta, dir, input.get("aim", false), input.get("sprint", false))
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_step_stamina_regen(delta)
	_update_facing(dir)


func _read_input() -> Dictionary:
	var aim := Input.is_action_pressed(&"aim")
	if Settings.get_value(&"toggle_aim"):
		if Input.is_action_just_pressed(&"aim"):
			_aim_toggled = not _aim_toggled
		aim = _aim_toggled
	var sprint := Input.is_action_pressed(&"sprint")
	if Settings.get_value(&"toggle_sprint"):
		if Input.is_action_just_pressed(&"sprint"):
			_sprint_toggled = not _sprint_toggled
		sprint = _sprint_toggled
	return {
		"move": Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down"),
		"aim": aim,
		"sprint": sprint,
		"dodge": Input.is_action_just_pressed(&"dodge"),
	}


## Screen-relative stick/WASD to a world direction on the ground plane.
func _to_world(move: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return Vector3(move.x, 0.0, move.y)
	var right := camera.global_basis.x
	var forward := -camera.global_basis.z
	right.y = 0.0
	forward.y = 0.0
	return right.normalized() * move.x + forward.normalized() * -move.y


func _step_move(delta: float, dir: Vector3, aim: bool, sprint: bool) -> void:
	is_aiming = aim
	var moving := dir.length_squared() > 0.0001
	var sprinting := sprint and moving and not aim and stamina > 0.0
	var speed := stats.walk_speed
	if aim:
		speed = stats.aim_move_speed
	elif sprinting:
		speed = stats.sprint_speed
		_spend_stamina(stats.sprint_stamina_per_sec * delta)
		if stamina <= 0.0:
			_sprint_toggled = false
	var target := dir * speed
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, stats.acceleration * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if not moving:
		_set_move_state(MoveState.IDLE)
	elif aim:
		_set_move_state(MoveState.AIM_WALK)
	elif sprinting:
		_set_move_state(MoveState.SPRINT)
	else:
		_set_move_state(MoveState.WALK)


func _start_dodge(dir: Vector3) -> void:
	_dodge_dir = dir.normalized() if dir.length_squared() > 0.0001 else _facing
	_dodge_left = stats.dodge_duration_sec
	_dodge_elapsed = 0.0
	is_aiming = false
	_spend_stamina(stats.dodge_stamina)
	var dodge_velocity := _dodge_dir * (stats.dodge_distance / stats.dodge_duration_sec)
	velocity.x = dodge_velocity.x
	velocity.z = dodge_velocity.z
	_set_move_state(MoveState.DODGE)


func _step_dodge(delta: float) -> void:
	_dodge_elapsed += delta
	_dodge_left -= delta
	if _dodge_left <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_set_move_state(MoveState.IDLE)


func _spend_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_since_stamina_use = 0.0
	stamina_changed.emit(stamina, stats.max_stamina)


func _step_stamina_regen(delta: float) -> void:
	_since_stamina_use += delta
	if _since_stamina_use < stats.stamina_regen_delay_sec or stamina >= stats.max_stamina:
		return
	stamina = minf(stamina + stats.stamina_regen * delta, stats.max_stamina)
	stamina_changed.emit(stamina, stats.max_stamina)


func _update_facing(dir: Vector3) -> void:
	if is_aiming and _aim_point != null:
		var to_aim: Vector3 = _aim_point - global_position
		to_aim.y = 0.0
		if to_aim.length_squared() > 0.0001:
			_facing = to_aim.normalized()
	elif move_state != MoveState.DODGE and dir.length_squared() > 0.0001:
		_facing = dir.normalized()
	rotation.y = atan2(-_facing.x, -_facing.z)


func _set_move_state(state: MoveState) -> void:
	if state == move_state:
		return
	move_state = state
	move_state_changed.emit(state)
	_update_noise(state)


func _update_noise(state: MoveState) -> void:
	if _noise == null:
		return
	if MOVE_NOISE.has(state):
		_noise.start_continuous(MOVE_NOISE[state])
		return
	_noise.stop_continuous()
	if state == MoveState.DODGE:
		_noise.emit(DODGE_NOISE)
