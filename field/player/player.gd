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
## Helped back up by a resident (RescueCall, 살려주는 주민).
signal revived()

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
## Seconds between footstep sounds per move state. Only states that make noise (AIM_WALK is 0 m), and
## silent while the noise comes out 0 (shadow step), so a sound always means monsters can hear it.
const FOOTSTEP_SEC := {MoveState.WALK: 0.45, MoveState.SPRINT: 0.3}
## Interaction query: sphere centered at body height, at most this many candidates.
const INTERACT_HEIGHT := 0.9
const INTERACT_MAX_HITS := 8

@export var stats: PlayerStats = preload("res://data/classes/player_base.tres")
## False on maps that are not a field sortie (B-23 base defense). Going down then only emits
## `downed`, not EventBus.player_downed: no bag loss, lost gear, stranded companions or sortie end.
@export var field_rules := true

## F (interact) is held down this frame. Hold actions (lock picking) read it; tests set it.
var interact_held := false
var health: float
var stamina: float
var is_aiming := false
var move_state := MoveState.IDLE
## Non-empty = a cutscene drives the player with this step() input instead of the keyboard
## (see step(); "world_move" gives a world direction). Cleared by the cutscene when it ends.
var script_input: Dictionary = {}
var is_downed := false
## Set by WeaponHolder (B-06): (amount, info) -> damage left after blocking.
var incoming_damage_filter: Callable
## B-10 부축: walk / sprint / aim speed x this while supporting a rescued person. 1 = normal.
var move_speed_mult := 1.0
## B-10 부축: only one-hand weapons (pistol, dagger) while true. TODO(B-06): WeaponHolder reads it.
var one_hand_only := false
## Set by RescueCall (field maps). Called when health reaches 0; returning true means someone is
## coming, so EventBus.player_downed waits for give_up(). revive() stands the player back up.
var down_interceptor: Callable
## Vehicle being driven (02 "탈것"), or null. FieldVehicle sets it through start_riding / stop_riding.
var riding: FieldVehicle

var _aim_toggled := false
var _sprint_toggled := false
var _since_stamina_use := 0.0
var _dodge_left := 0.0
var _dodge_elapsed := 0.0
var _dodge_dir := Vector3.ZERO
var _footstep_left := 0.0
var _facing := Vector3.FORWARD
var _aim_point: Variant = null
## Interactable the player last started using (HUD hold bar).
var _interacting: Node3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _noise: NoiseEmitter = $Noise
## Status effects (B-14): bleed, stagger, bind, slow ... Lane D listens to its signals.
@onready var status: StatusHolder = StatusHolder.attach(self)
## Class skills, passives and mastery (B-13). It hooks the Weapons node and incoming_damage_filter.
@onready var skills: ClassSkills = ClassSkills.attach(self)
## Quick-slot consumables (B-16): keys 3 to 6, use time, throwing. Logic in field/consumables/.
@onready var consumables: ConsumableUser = ConsumableUser.attach(self)
## Magic weapons (B-15): essence effects, combos, mana, release (X). After `skills`: it wraps the hit filter.
@onready var magic: MagicWeapon = MagicWeapon.attach(self)


func _ready() -> void:
	add_to_group(GROUP)
	_set_body_layers(true)
	# TODO(A-11): add stats.health_per_level per player level once progression exists.
	health = stats.max_health
	stamina = stats.max_stamina
	_since_stamina_use = stats.stamina_regen_delay_sec


func _physics_process(delta: float) -> void:
	if is_downed:
		return
	if riding != null:
		_step_riding()
		return
	if not script_input.is_empty():
		interact_held = false
		step(delta, script_input)  # a cutscene drives the player (IntroCutscene); no interact
		move_and_slide()
		return
	step(delta, {} if input_blocked() else _read_input())
	move_and_slide()
	interact_held = Input.is_action_pressed(&"interact") and not input_blocked()
	if Input.is_action_just_pressed(&"interact") and not input_blocked():
		interact()


## A menu is open over the field (pause, settings, journal ...). The field keeps running, but the
## player stands still and does not act (user decision 2026-11-06: the field never pauses).
static func input_blocked() -> bool:
	return UI.blocks_play()


## Starts using the nearest interactable in reach (loot containers for now).
## Returns false when nothing is in reach or it refused.
## Uses a shape query, not an Area3D: Jolt areas do not report static bodies by default.
func interact() -> bool:
	var target := interact_target()
	if target == null or not target.begin_open(self):
		return false
	_interacting = target
	return true


## Interactable last started with interact(), or null once it is gone.
func interacting() -> Node3D:
	return _interacting if is_instance_valid(_interacting) else null


## Everything the field HUD (D-04) draws, rebuilt every call. Keys: issue #28.
func hud_state() -> Dictionary:
	return PlayerHudState.build(self)


## Nearest interactable (something with begin_open) in reach, or null.
func interact_target() -> Node3D:
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
	return best


## Cannot move: bound, staggered or knocked back (B-14 status effects).
func is_bound() -> bool:
	return not status.can_move()


## Stagger for `sec` seconds (B-06 guard break). Same as the &"stagger" status.
func stun(sec: float) -> void:
	status.apply(&"stagger", {"duration": sec})


## Weapons (B-06) pay melee and block stamina through this, so regen delay restarts.
func spend_stamina(amount: float) -> void:
	_spend_stamina(amount)


## World point to face while aiming (B-04 camera sets it from the cursor or stick).
func set_aim_point(point: Vector3) -> void:
	_aim_point = point


## True when the body turns to the cursor: while aiming, and always while holding a gun
## (user decision: guns face the cursor, melee faces the move direction unless aiming/blocking).
func faces_cursor() -> bool:
	if is_aiming:
		return true
	var weapons := get_node_or_null(^"Weapons") as WeaponHolder
	return weapons != null and WeaponHolder.is_gun(weapons.current_stats())


## Last aim point from the camera (Vector3), or null before the first one.
func aim_point() -> Variant:
	return _aim_point


func facing() -> Vector3:
	return _facing


func is_invulnerable() -> bool:
	return move_state == MoveState.DODGE and _dodge_elapsed < stats.dodge_invuln_sec


## Damage entry point for monsters and hazards. Status effects ride in info (StatusHolder header:
## info["status"], legacy info["bind_sec"]); a blocked hit applies none.
## Status tick damage (bleed, shock) skips blocking and dodge invulnerability.
## DebugConsole `godmode` blocks everything.
func take_damage(amount: float, info: Dictionary = {}) -> void:
	if riding != null:
		riding.take_damage(amount, info)
		return
	var tick := StatusHolder.is_tick(info)
	if is_downed or (is_invulnerable() and not tick) or amount <= 0.0 or DebugConsole.godmode:
		return
	if incoming_damage_filter.is_valid() and not tick:
		amount = incoming_damage_filter.call(amount, info)
		if amount <= 0.0:
			return
	amount = status.scale_damage(amount, info)
	status.apply_hit(info)
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, stats.max_health)
	var ratio := amount / maxf(stats.max_health, 1.0)
	if not tick and ratio >= CombatFeel.SHAKE_HURT_MIN_RATIO:
		CombatFeel.shake(self, CombatFeel.SHAKE_PLAYER_HURT * ratio)
	if health == 0.0:
		is_downed = true
		status.clear()
		velocity = Vector3.ZERO
		downed.emit()
		if field_rules and not (down_interceptor.is_valid() and down_interceptor.call()):
			EventBus.player_downed.emit()


## Helped up by a resident (RescueCall). Health = max x health_ratio.
func revive(health_ratio: float) -> void:
	if not is_downed:
		return
	is_downed = false
	health = stats.max_health * health_ratio
	health_changed.emit(health, stats.max_health)
	revived.emit()


## Nobody came in time: the normal field down (bag loss, stranded companions, sortie end).
func give_up() -> void:
	if is_downed and field_rules:
		EventBus.player_downed.emit()


func is_riding() -> bool:
	return riding != null


## FieldVehicle.mount(): stop walking and footsteps, leave every physics layer (hits go to the vehicle).
func start_riding(vehicle: FieldVehicle) -> void:
	riding = vehicle
	is_aiming = false
	velocity = Vector3.ZERO
	_set_move_state(MoveState.IDLE)
	_set_body_layers(false)


## FieldVehicle.dismount(): stand at `at`.
func stop_riding(at: Vector3) -> void:
	riding = null
	_set_body_layers(true)
	global_position = at


## One simulation step. Split from input reading so tests can drive it.
## input: {"move": Vector2, "aim": bool, "sprint": bool, "dodge": bool}
## A cutscene may give "world_move": Vector3 (ground direction, length <= 1) instead of "move".
func step(delta: float, input: Dictionary) -> void:
	var dir: Vector3 = input["world_move"] if input.has("world_move") else _to_world(input.get("move", Vector2.ZERO))
	status.step(delta)
	if is_downed:
		return
	if not status.can_move():
		# Bound, staggered or knocked back (B-14): no moving or dodging, aiming still works.
		dir = Vector3.ZERO
		input = input.merged({"dodge": false, "sprint": false}, true)
	input = consumables.filter_input(input)
	if move_state == MoveState.DODGE:
		_step_dodge(delta)
	elif input.get("dodge", false) and stamina >= stats.dodge_stamina:
		_start_dodge(dir)
	else:
		_step_move(delta, dir, input.get("aim", false), input.get("sprint", false))
	var push := status.knockback_velocity()
	if push != Vector3.ZERO:
		velocity.x = push.x
		velocity.z = push.z
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_step_stamina_regen(delta)
	_update_facing(dir)


func _read_input() -> Dictionary:
	# The field map is open (real time): right click there sets a ping, not the aim.
	var map_open := UI.is_open(&"map")
	var aim := Input.is_action_pressed(&"aim") and not map_open
	if Settings.get_value(&"toggle_aim") and not map_open:
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


## Driving: the move keys steer the vehicle, F gets off. Weapons, skills and items are locked
## (their nodes check is_riding()).
func _step_riding() -> void:
	interact_held = false
	if input_blocked():
		riding.set_input(Vector3.ZERO)
		return
	if Input.is_action_just_pressed(&"interact"):
		riding.dismount()
		return
	riding.set_input(_to_world(Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")))
	_facing = riding.forward()
	rotation.y = atan2(-_facing.x, -_facing.z)


func _set_body_layers(on: bool) -> void:
	collision_layer = (1 << (Enums.LAYER_PLAYER - 1)) if on else 0
	collision_mask = ((1 << (Enums.LAYER_WORLD - 1)) | (1 << (Enums.LAYER_MONSTER - 1))) if on else 0


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
	speed *= _backpedal_mult(dir)
	var target := dir * speed * move_speed_mult * status.move_mult()
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
	_step_footstep(delta)


func _step_footstep(delta: float) -> void:
	var sec: float = FOOTSTEP_SEC.get(move_state, 0.0)
	if sec <= 0.0:
		_footstep_left = 0.0
		return
	_footstep_left -= delta
	if _footstep_left > 0.0:
		return
	_footstep_left = sec
	if _noise == null or _noise.radius_for(MOVE_NOISE[move_state]) > 0.0:
		Audio.play(&"footstep_run" if move_state == MoveState.SPRINT else &"footstep", global_position)


## Slower when walking away from where the body faces (only while it faces the cursor).
func _backpedal_mult(dir: Vector3) -> float:
	if not faces_cursor() or dir.length_squared() < 0.0001:
		return 1.0
	var back := maxf(-dir.normalized().dot(_facing), 0.0)
	return lerpf(1.0, stats.backpedal_speed_mult, back)


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
	Audio.play(&"dodge_roll", global_position)


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
	if faces_cursor() and _aim_point != null and move_state != MoveState.DODGE:
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
