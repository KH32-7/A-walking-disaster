class_name Monster
extends CharacterBody3D
## Common field monster AI (B-07). One script for every monster; the numbers
## come from `def` and per-monster features from def.behaviors (see BEHAVIORS).
## Hearing: listens to EventBus.noise_emitted directly and filters by
## distance <= radius * hearing_mult. Sight: cone + wall ray on the world layer.
## Design reference: docs/design/04-monsters.md "감지와 행동", 02-field.md "소음"

## Every state change. Lane D (D-05) shows "?" for SUSPICIOUS and "!" for CHASE.
signal state_changed(old_state: Enums.AIState, new_state: Enums.AIState)
## Final damage after part, element and defense multipliers.
signal damaged(amount: float, info: Dictionary)
signal attack_landed(target: Node3D, info: Dictionary)
signal died(monster: Monster)

const GROUP := &"field_monsters"
## B-03 puts the player in this group.
const PLAYER_GROUP := &"player"
## MonsterDef.behaviors id -> MonsterBehavior script.
const BEHAVIORS := {
	&"bind": preload("res://field/monsters/behaviors/bind_behavior.gd"),
	&"alarm": preload("res://field/monsters/behaviors/alarm_behavior.gd"),
	&"split": preload("res://field/monsters/behaviors/split_behavior.gd"),
	&"noise_only": preload("res://field/monsters/behaviors/noise_only_behavior.gd"),
	&"mist": preload("res://field/monsters/behaviors/mist_behavior.gd"),
	&"slow_touch": preload("res://field/monsters/behaviors/slow_touch_behavior.gd"),
	&"self_destruct": preload("res://field/monsters/behaviors/self_destruct_behavior.gd"),
	&"shock_orb": preload("res://field/monsters/behaviors/shock_orb_behavior.gd"),
	&"orb_fan": preload("res://field/monsters/behaviors/orb_fan_behavior.gd"),
	&"rally": preload("res://field/monsters/behaviors/rally_behavior.gd"),
}

@export var def: MonsterDef
## SUSPICIOUS starts looking at the spawn point. CHASE needs `target` set before
## adding to the tree, otherwise it starts in WANDER.
@export var start_state: Enums.AIState = Enums.AIState.WANDER
@export var wander_radius: float = MonsterRules.DEFAULT_WANDER_RADIUS

var state: Enums.AIState = Enums.AIState.WANDER
var hp: float = 0.0
var max_hp: float = 0.0
## Set before adding to the tree to scale max hp (split children).
var hp_scale: float = 1.0
## Nest position. Defaults to the spawn position.
var home: Vector3 = Vector3.INF
var pack: MonsterPack
## Current chase / attack target.
var target: Node3D
## How many times this monster's line has split (split behavior).
var split_generation: int = 0
## Set by make_elite() (B-18). Elites use the elite drop table.
var elite := false
## Drop chance multiplier (B-21 night x1.3). 0 = drops nothing.
var drop_mult: float = 1.0
## Sight distance multiplier (B-21 night x0.7). Applied to def.sight_range.
var sight_mult: float = 1.0
## Damage multiplier on def.attack (elite x1.5).
var attack_mult: float = 1.0
## Base defense (B-23, Lane C sets it): a finite point makes this a raider. Raiders never leash
## home, march here when idle (charges_gates: nearest gate first), follow the navmesh and hit
## raid structures in the way (RaidMarch). Vector3.INF = field monster.
var raid_goal: Vector3 = Vector3.INF

var _behaviors: Array[MonsterBehavior] = []
var _dead := false
var _clock := 0.0
var _state_time := 0.0
var _heard_times: Array[float] = []
var _sleep_noises := 0
var _noise_point := Vector3.ZERO
var _last_known := Vector3.ZERO
var _last_seen := 0.0
var _move_point := Vector3.ZERO
var _has_move_point := false
var _leg_time := 0.0
var _wait_time := 0.0
var _arrived := false
var _attack_cooldown := 0.0
var _sight_timer := 0.0
var _raid: RaidMarch
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

## Status effects (B-14). Lane D listens to its signals for icons over the head.
@onready var status: StatusHolder = StatusHolder.attach(self)


func _ready() -> void:
	if def == null:
		push_error("%s has no MonsterDef" % name)
		set_physics_process(false)
		return
	add_to_group(GROUP)
	collision_layer = 1 << (Enums.LAYER_MONSTER - 1)
	collision_mask = (1 << (Enums.LAYER_WORLD - 1)) | (1 << (Enums.LAYER_MONSTER - 1))
	max_hp = def.hp * hp_scale
	hp = max_hp
	if home == Vector3.INF:
		home = global_position
	for id in def.behaviors:
		_add_behavior(id)
	if elite:
		for id in def.elite_behaviors:
			_add_behavior(id)
	state = start_state
	_noise_point = global_position
	if state == Enums.AIState.CHASE:
		if _target_valid():
			_perceive(target)
		else:
			state = Enums.AIState.WANDER
	EventBus.noise_emitted.connect(_on_noise_emitted)


func _physics_process(delta: float) -> void:
	tick(delta)
	# Slow / bind scale the AI's velocity; knockback replaces it (B-14).
	velocity = status.steer(velocity)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()


## One AI step. Sets velocity and facing only; _physics_process moves the body.
## Tests call this directly with a fixed delta.
func tick(delta: float) -> void:
	if _dead:
		return
	_clock += delta
	_state_time += delta
	_sight_timer -= delta
	status.step(delta)
	var blocked := false
	for behavior in _behaviors:
		behavior.on_tick(delta)
		blocked = blocked or behavior.blocks_action()
	if _dead:
		return
	if blocked or not status.can_act():
		# A behavior holds it still (B-18), or staggered / knocked back (B-14).
		_stop()
		return
	if not is_raider() and _is_leash_state() and _flat_distance(home) > MonsterRules.RETURN_DISTANCE:
		_set_state(Enums.AIState.RETURN)
	match state:
		Enums.AIState.SLEEP:
			_stop()
		Enums.AIState.WANDER:
			if is_raider():
				_tick_raid(delta)
			else:
				_tick_wander(delta)
		Enums.AIState.SUSPICIOUS:
			_tick_suspicious(delta)
		Enums.AIState.INVESTIGATE:
			_tick_investigate(delta)
		Enums.AIState.CHASE:
			_tick_chase(delta)
		Enums.AIState.ATTACK:
			_tick_attack(delta)
		Enums.AIState.RETURN:
			_tick_return(delta)


# --- Public ---------------------------------------------------------------

## Damage entry point for weapons (B-06). `amount` is the attacker-side damage
## (03 formula A, U, M, C). The monster applies the part (P), element (E) and
## defense (R) factors. info keys: "element" (Enums.Element), "source" (Node),
## "weak_point" (bool, set by MonsterWeakPoint), "position" (Vector3),
## "status" (B-14, see StatusHolder). Armor break halves R, wet raises LIGHT damage.
## Status tick damage is flat and does not make the monster react.
func take_damage(amount: float, info: Dictionary = {}) -> void:
	if _dead:
		return
	var tick := StatusHolder.is_tick(info)
	var dealt := amount
	if not tick:
		var element: Enums.Element = info.get("element", Enums.Element.NONE)
		var part := MonsterRules.WEAK_POINT_MULT if info.get("weak_point", false) else 1.0
		dealt = status.scale_damage(amount * part * Enums.element_multiplier(element, def.family) \
				* MonsterRules.defense_factor(def.defense * status.defense_mult()), info)
	hp -= dealt
	damaged.emit(dealt, info)
	if hp <= 0.0:
		_die()
		return
	if tick:
		return
	status.apply_hit(info)
	_react_to_hit(info)


## Heard noise or a scream. Called by the EventBus listener after the range check.
func hear(point: Vector3, source: Node) -> void:
	if _dead or state == Enums.AIState.RETURN:
		return
	for behavior in _behaviors:
		behavior.on_heard(point, source)
	_heard_times.append(_clock)
	while _heard_times.size() > 0 and _clock - _heard_times[0] > MonsterRules.HEARING_WINDOW_SEC:
		_heard_times.pop_front()
	var heard_target := target_from_source(source)
	match state:
		Enums.AIState.SLEEP:
			_sleep_noises += 1
			if _sleep_noises >= MonsterRules.SLEEP_WAKE_NOISES:
				_suspect(point)
		Enums.AIState.WANDER:
			_suspect(point)
		Enums.AIState.SUSPICIOUS, Enums.AIState.INVESTIGATE:
			_noise_point = point
			_arrived = false
			if heard_target and _heard_times.size() >= MonsterRules.HEARING_CHASE_COUNT:
				chase(heard_target)
		Enums.AIState.CHASE, Enums.AIState.ATTACK:
			if heard_target and heard_target == target:
				_perceive(target)


## Start chasing `who`. The rest of the pack turns suspicious.
func chase(who: Node3D) -> void:
	if _dead or who == null:
		return
	target = who
	_perceive(who)
	if state == Enums.AIState.CHASE or state == Enums.AIState.ATTACK:
		return
	_set_state(Enums.AIState.CHASE)
	if pack:
		pack.alert(self, who.global_position)


## A pack member started chasing. Only idle members react.
func pack_alert(point: Vector3) -> void:
	if state == Enums.AIState.SLEEP or state == Enums.AIState.WANDER:
		_suspect(point)


## Cone + distance + wall check. use_cone = false while already chasing.
func can_see(node: Node3D, use_cone: bool = true) -> bool:
	if node == null or not node.is_inside_tree() or sight_range() <= 0.0:
		return false
	if node.is_in_group(ClassSkills.STEALTH_GROUP):
		return false  # B-13 그림자 걸음
	var to := node.global_position - global_position
	if to.length() > sight_range():
		return false
	var flat := Vector3(to.x, 0.0, to.z)
	if use_cone and flat.length() > 0.01:
		var forward := -global_basis.z
		forward.y = 0.0
		if rad_to_deg(forward.angle_to(flat)) > def.sight_angle * 0.5:
			return false
	var up := Vector3.UP * MonsterRules.SIGHT_RAY_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(
			global_position + up, node.global_position + up, 1 << (Enums.LAYER_WORLD - 1), [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Priority: player (group) > allies (layer 3: companions, rescuees, base residents).
## A downed player is skipped (base defense goes on after the player falls, B-23).
func find_visible_target() -> Node3D:
	for node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if node is Node3D and node.get(&"is_downed") != true and can_see(node):
			return node
	for ally in _allies_in_range():
		if can_see(ally):
			return ally
	return null


## Walks up from a noise source to the player or an ally it belongs to.
func target_from_source(source: Node) -> Node3D:
	var node := source
	while node != null:
		if node.is_in_group(PLAYER_GROUP) and node is Node3D:
			return node
		if node is CollisionObject3D and node.get_collision_layer_value(Enums.LAYER_ALLY):
			return node
		node = node.get_parent()
	return null


## No action for `sec` seconds (perfect block). Same as the &"stagger" status.
func stun(sec: float) -> void:
	status.apply(&"stagger", {"duration": sec})


func is_stunned() -> bool:
	return status.has(&"stagger")


func can_move() -> bool:
	return def != null and def.move_speed > 0.0


func is_dead() -> bool:
	return _dead


## Spawned for a base defense battle (raid_goal set).
func is_raider() -> bool:
	return raid_goal.is_finite()


## Sight distance after sight_mult (B-21 night) and status (B-16 flash blind = 0).
func sight_range() -> float:
	return def.sight_range * sight_mult * (status.sight_mult() if status else 1.0)


## One hit's damage: def.attack x attack_mult (elite x1.5).
func attack_damage() -> float:
	return def.attack * attack_mult


## Turns this monster into its elite variant (04 "정예", B-18): hp x3, attack x1.5,
## size x1.3, plus def.elite_behaviors. Works before or after adding to the tree.
## Calling it twice does nothing the second time.
func make_elite() -> void:
	if elite or def == null:
		return
	elite = true
	hp_scale *= MonsterRules.ELITE_HP_MULT
	attack_mult *= MonsterRules.ELITE_ATTACK_MULT
	scale *= MonsterRules.ELITE_SIZE_MULT
	if is_node_ready():
		max_hp *= MonsterRules.ELITE_HP_MULT
		hp *= MonsterRules.ELITE_HP_MULT
		for id in def.elite_behaviors:
			_add_behavior(id)


## The attached behavior for `id`, or null. Lets other B code reach one, for example a
## flash item calling the mist behavior's reveal().
func get_behavior(id: StringName) -> MonsterBehavior:
	for behavior in _behaviors:
		if behavior.get_meta(&"id", &"") == id:
			return behavior
	return null


## Removes the monster without it counting as a kill: no monster_killed, no drops
## (neon moth self-destruct). `died` still fires so packs and spawners let go of it.
func vanish() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)
	if pack:
		pack.remove(self)
	queue_free()


# --- States ---------------------------------------------------------------

func _tick_wander(delta: float) -> void:
	var seen := _look_for_target()
	if seen:
		_suspect(seen.global_position)
		return
	if _wait_time > 0.0:
		_wait_time -= delta
		_stop()
		return
	if not _has_move_point or _leg_time > MonsterRules.WANDER_LEG_MAX_SEC:
		_move_point = _pick_wander_point()
		_has_move_point = true
		_leg_time = 0.0
	_leg_time += delta
	if _move_to(_move_point, def.move_speed * MonsterRules.WANDER_SPEED_MULT, delta):
		_has_move_point = false
		_wait_time = randf_range(MonsterRules.WANDER_PAUSE_MIN_SEC, MonsterRules.WANDER_PAUSE_MAX_SEC)


## Raider idle (B-23): march to the raid goal, chasing whatever it sees on the way.
func _tick_raid(delta: float) -> void:
	var seen := _look_for_target()
	if seen:
		chase(seen)
		return
	_move_to(_march().goal(), def.move_speed, delta)


func _tick_suspicious(delta: float) -> void:
	_stop()
	_face(_noise_point, delta)
	var seen := _look_for_target()
	if seen:
		chase(seen)
	elif _state_time >= MonsterRules.SUSPICIOUS_SEC:
		_set_state(Enums.AIState.INVESTIGATE)


func _tick_investigate(delta: float) -> void:
	var seen := _look_for_target()
	if seen:
		chase(seen)
		return
	if not _arrived:
		_arrived = _move_to(_noise_point, def.move_speed, delta) \
				or _state_time > MonsterRules.INVESTIGATE_TRAVEL_MAX_SEC
		if _arrived:
			_wait_time = MonsterRules.INVESTIGATE_LOOK_SEC
		return
	_stop()
	rotate_y(deg_to_rad(MonsterRules.LOOK_AROUND_SPEED_DEG) * delta)
	_wait_time -= delta
	if _wait_time <= 0.0:
		_set_state(Enums.AIState.WANDER)


func _tick_chase(delta: float) -> void:
	if not _target_valid():
		_lose_target()
		return
	var seen_now := _senses(target)
	if seen_now:
		_perceive(target)
	elif _clock - _last_seen > MonsterRules.LOSE_TARGET_SEC:
		_lose_target()
		return
	if seen_now and _distance_to(target) <= def.attack_range:
		_set_state(Enums.AIState.ATTACK)
		return
	if can_move():
		_move_to(_last_known, def.move_speed, delta)
	else:
		_stop()
		_face(_last_known, delta)


func _tick_attack(delta: float) -> void:
	_stop()
	if not _target_valid():
		_lose_target()
		return
	_face(target.global_position, delta)
	if _distance_to(target) > def.attack_range * MonsterRules.ATTACK_EXIT_MULT or not _senses(target):
		_set_state(Enums.AIState.CHASE)
		return
	_perceive(target)
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = def.attack_interval
		_perform_attack()


func _tick_return(delta: float) -> void:
	hp = minf(max_hp, hp + max_hp * MonsterRules.RETURN_REGEN_RATIO * delta)
	if not can_move() or _move_to(home, def.move_speed, delta):
		_set_state(Enums.AIState.WANDER)


# --- Helpers --------------------------------------------------------------

func _add_behavior(id: StringName) -> void:
	if not BEHAVIORS.has(id):
		push_warning("%s: unknown behavior %s" % [def.id, id])
		return
	var behavior: MonsterBehavior = BEHAVIORS[id].new()
	behavior.monster = self
	behavior.set_meta(&"id", id)
	_behaviors.append(behavior)
	behavior.on_added()


## Sight without the cone, or touch. Blind monsters (statue) still notice a target
## right next to them, so they can attack. Ranged attackers do not sense through walls.
## Flash-blinded ones (B-16 blind status) sense nothing until it wears off.
func _senses(who: Node3D) -> bool:
	if status.sight_mult() <= 0.0:
		return false
	return can_see(who, false) 			or _distance_to(who) <= minf(def.attack_range, MonsterRules.TOUCH_SENSE_RANGE)


func _set_state(new_state: Enums.AIState) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	_state_time = 0.0
	_has_move_point = false
	_arrived = false
	_wait_time = 0.0
	match new_state:
		Enums.AIState.ATTACK:
			_attack_cooldown = MonsterRules.ATTACK_WINDUP_SEC
		Enums.AIState.RETURN, Enums.AIState.WANDER:
			target = null
			_heard_times.clear()
		Enums.AIState.INVESTIGATE:
			target = null
	state_changed.emit(old, new_state)
	for behavior in _behaviors:
		behavior.on_state_changed(old, new_state)


func _suspect(point: Vector3) -> void:
	_noise_point = point
	if state != Enums.AIState.SUSPICIOUS:
		_set_state(Enums.AIState.SUSPICIOUS)


func _lose_target() -> void:
	_noise_point = _last_known
	_set_state(Enums.AIState.INVESTIGATE)


func _perceive(who: Node3D) -> void:
	_last_known = who.global_position
	_last_seen = _clock


func _react_to_hit(info: Dictionary) -> void:
	var source: Node = info.get("source")
	var attacker := target_from_source(source)
	var point: Vector3 = info.get("position", global_position)
	if source is Node3D:
		point = source.global_position
	match state:
		Enums.AIState.RETURN:
			pass
		Enums.AIState.SLEEP:
			_suspect(point)
		_:
			if attacker:
				chase(attacker)
			else:
				_suspect(point)


func _perform_attack() -> void:
	var info := {"source": self, "element": def.family, "monster_id": def.id}
	for behavior in _behaviors:
		behavior.modify_attack(info)
	var replaced := false
	for behavior in _behaviors:
		if behavior.replace_attack(info):
			replaced = true
			break
	if not replaced and target.has_method("take_damage"):
		target.take_damage(attack_damage(), info)
	attack_landed.emit(target, info)


func _die() -> void:
	_dead = true
	for behavior in _behaviors:
		behavior.on_died()
	MonsterDrops.drop_for(self)
	EventBus.monster_killed.emit(def.id, def.family, global_position)
	died.emit(self)
	if pack:
		pack.remove(self)
	queue_free()


func _on_noise_emitted(point: Vector3, radius: float, source: Node) -> void:
	if _dead or source == self or not is_inside_tree():
		return
	var mult := def.hearing_mult
	if state == Enums.AIState.SLEEP:
		mult *= MonsterRules.SLEEP_HEARING_MULT
	if global_position.distance_to(point) <= radius * mult:
		hear(point, source)


func _look_for_target() -> Node3D:
	if _sight_timer > 0.0:
		return null
	_sight_timer = MonsterRules.SIGHT_CHECK_INTERVAL
	return find_visible_target()


func _allies_in_range() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if sight_range() <= 0.0:
		return result
	var shape := SphereShape3D.new()
	shape.radius = sight_range()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 1 << (Enums.LAYER_ALLY - 1)
	for hit in get_world_3d().direct_space_state.intersect_shape(query):
		if hit.collider is Node3D:
			result.append(hit.collider)
	return result


func _pick_wander_point() -> Vector3:
	var center := home
	var radius := wander_radius
	var leader := pack.leader() if pack else null
	if leader and leader != self:
		center = leader.global_position
		radius = MonsterRules.PACK_FOLLOW_RADIUS
	var angle := randf() * TAU
	var dist := sqrt(randf()) * radius
	return center + Vector3(cos(angle), 0.0, sin(angle)) * dist


## Steers toward `point` on the ground plane. Returns true when arrived.
## Greybox: straight-line steering. TODO(B-12): NavigationAgent3D once layouts have navmesh.
func _move_to(point: Vector3, speed: float, delta: float) -> bool:
	if speed <= 0.0:
		_stop()
		return true
	if is_raider():
		return _raid_move_to(point, speed, delta)
	var to := point - global_position
	to.y = 0.0
	if to.length() <= MonsterRules.ARRIVE_DISTANCE:
		_stop()
		return true
	var dir := to.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face(global_position + dir, delta)
	return false


## Raiders (B-23): navmesh corners instead of a straight line, and a raid structure in the way
## is hit instead of walked into.
func _raid_move_to(point: Vector3, speed: float, delta: float) -> bool:
	if _flat_distance(point) <= MonsterRules.ARRIVE_DISTANCE:
		_stop()
		return true
	var raid := _march()
	var dir := raid.next_corner(point, delta) - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	dir = dir.normalized()
	var blocker := raid.blocking_structure(dir)
	if blocker != null:
		_stop()
		_face(global_position + dir, delta)
		raid.hit(blocker, delta)
		return false
	raid.reset_hit()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face(global_position + dir, delta)
	return false


func _march() -> RaidMarch:
	if _raid == null:
		_raid = RaidMarch.new(self)
	return _raid


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _face(point: Vector3, delta: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return
	var wanted := atan2(-to.x, -to.z)
	rotation.y = rotate_toward(rotation.y, wanted, deg_to_rad(MonsterRules.TURN_SPEED_DEG) * delta)


func _is_leash_state() -> bool:
	return state in [Enums.AIState.SUSPICIOUS, Enums.AIState.INVESTIGATE,
			Enums.AIState.CHASE, Enums.AIState.ATTACK]


func _target_valid() -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and target.get(&"is_downed") != true


func _distance_to(node: Node3D) -> float:
	return _flat_distance(node.global_position)


func _flat_distance(point: Vector3) -> float:
	var to := point - global_position
	to.y = 0.0
	return to.length()
