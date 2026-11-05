class_name FieldCompanion
extends CharacterBody3D
## A resident who came out with the player (B-17). CompanionManager spawns one per loadout companion.
##
## - Stats from Colony.get_resident(id) (stats, class_aptitude, traits, access_needs), gear from
##   Armory with the resident id as owner (MAIN, else SUB weapon; armor for health and footsteps).
## - Health = 80 + 힘 x 5 + 방어구 (armor defense sum + max_hp affixes, the player's armor bonus too).
## - Damage = weapon stats damage x 적성 x 능력치 (둔기 힘, 칼 손재주) x crit. No class mastery.
##   Gun spread -3% per 감각. Shots go through low cover and never hit the player or allies.
## - Modes (hold V, CompanionManager): 공격적 = nearest visible monster, 신중 = only monsters the
##   player hit (or that hit this companion: it fights back, never starts), quieter footsteps, 엄호 = stays by the nearest rescued
##   person and fights what comes close to them (no rescued person: guards the player).
## - Q skill only with 적성 상, cooldown x1.5. The skill itself waits for B-13 (skill_used hook).
## - 겁이 많음 (flee_hp_ratio) stops fighting and keeps to the player at low health, 용감함 never does.
## - Downed at 0 health: 30 s to help up (Player.interact() -> begin_open, 3 s hold), else stranded.
##
## Contracts (same as B-10 RescueTarget, so B-07 monsters and B-09 extraction see it):
## - Physics layer 3 (ally) while up, layer 7 (interactable) while downed.
## - Group ExtractionManager.PARTY_GROUP with party_id (resident id) / display_name / party_kind
##   "companion" until stranded.
## - MOBILITY access need: nav layer 2 only (no stairs, like a wheelchair rescue). Else nav layer 1.
## Design reference: docs/design/03-combat-classes.md "동행 주민 전투", 07-residents.md,
## 02-field.md "함께 나오기 (호위)".

signal mode_changed(mode: Mode)
signal downed()
signal revived()
## Not helped up in time, or left behind (player down, "두고 갈까요?").
signal stranded()
## Q skill used. TODO(B-13): the class skill effect itself (정조준 / 돌진 베기 / 내려찍기).
signal skill_used(combat_class: int)
signal attacked(target: Node3D)

enum Mode { AGGRESSIVE, CAUTIOUS, COVER }
enum State { ACTIVE, DOWNED, STRANDED }

const GROUP := &"field_companions"
const PARTY_GROUP := ExtractionManager.PARTY_GROUP
const PARTY_KIND := ExtractionManager.KIND_COMPANION
const DEFAULT_TUNING := preload("res://data/classes/companion_tuning.tres")
const DEFAULT_COMBAT := preload("res://data/classes/combat_tuning.tres")
## HUD `companions[].command` text per mode / state (issue #28).
const MODE_LABELS := {Mode.AGGRESSIVE: "공격적", Mode.CAUTIOUS: "신중", Mode.COVER: "엄호"}
const DOWNED_LABEL := "쓰러짐"
const RETREAT_LABEL := "물러남"
const REVIVE_PROMPT := "%s 일으키기"
const REVIVE_HOLD_LABEL := "일으키는 중"
const WORLD_MASK := 1 << (Enums.LAYER_WORLD - 1)
## Same as the player's shots: world + monsters, never the player (2) or allies (3).
const SHOT_MASK := WeaponHolder.SHOT_MASK
const MAX_COVER_PASSES := WeaponHolder.MAX_COVER_PASSES
## Shots aim at this height on the target (low enough for short monsters).
const AIM_HEIGHT := 0.5
## Nav layers (B-10 / B-12 convention): 1 everyone, 2 no stairs.
const NAV_ALL := 0b01
const NAV_NO_STAIRS := 0b10
## Used when no player is known (player_base walk / sprint, m/s).
const FALLBACK_WALK_SPEED := 4.5
const FALLBACK_SPRINT_SPEED := 7.0
const WAYPOINT_REACHED := 0.3
const MOVING_SPEED := 0.1

@export var tuning: CompanionTuning = DEFAULT_TUNING
@export var combat: CombatTuning = DEFAULT_COMBAT

## Read by ExtractionManager (B-09). party_id = resident id.
var party_id: StringName = &""
var display_name := ""
var party_kind := PARTY_KIND
## Colony.get_resident() copy taken at setup.
var resident: Dictionary = {}
var mode := Mode.AGGRESSIVE
var state := State.ACTIVE
var health := 0.0
var max_health := 0.0
## Monster being fought, or null.
var target: Node3D
var rng := RandomNumberGenerator.new()

var _player: Node3D
## Monster instance id -> true. 신중 only fights these.
var _marked := {}
var _attack_left := 0.0
var _reload_left := 0.0
## Rounds left in the magazine, -1 = full (filled on the first shot).
var _magazine := -1
var _skill_left := 0.0
var _retarget_left := 0.0
var _down_left := 0.0
var _reviver: Node3D
var _revive_left := 0.0
var _revive_from := Vector3.ZERO
var _armor_speed_mult := 1.0
var _footstep: StringName = &""
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF
var _repath_left := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _noise: NoiseEmitter = $Noise
## B-14 status effects (bleed, slow, bind, stagger, knockback ...) from monster hits.
@onready var status: StatusHolder = StatusHolder.attach(self)


## Call before adding to the tree. `data` = Colony.get_resident(resident_id).
func setup(resident_id: StringName, data: Dictionary) -> void:
	party_id = resident_id
	resident = data.duplicate(true)
	display_name = str(resident.get("name", resident_id))


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(PARTY_GROUP)
	collision_mask = WORLD_MASK
	var summary := Armory.get_owner_summary(party_id)
	_armor_speed_mult = float(summary.get("move_speed_mult", 1.0))
	max_health = max_health_for(resident, summary, tuning)
	health = max_health
	_noise.armory_owner_id = party_id
	# 07 조용한 발걸음: 동행 시 이동 소음 -2m (TraitDef companion_noise_m).
	_noise.footstep_bonus_m = trait_effect(&"companion_noise_m")
	rng.randomize()
	EventBus.companion_stranded.connect(_on_companion_stranded)
	_apply_layers()


func _physics_process(delta: float) -> void:
	tick(delta)
	# Slow / bind scale the walking velocity; knockback replaces it (B-14).
	velocity = status.steer(velocity)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


# --- Public API ----------------------------------------------------------------

## 03: 체력 = 80 + 힘 x 5 + 방어구. summary = Armory.get_owner_summary(resident id).
static func max_health_for(data: Dictionary, summary: Dictionary, t: CompanionTuning) -> float:
	var stats: Dictionary = data.get("stats", {})
	return t.base_health + t.health_per_str * float(stats.get(&"str", 0)) \
			+ float(summary.get("defense", 0.0)) + float(summary.get("max_hp", 0))


## Every companion's HUD line (Player.hud_state() "companions", issue #28).
static func hud_list(tree: SceneTree) -> Array:
	var list: Array = []
	for node in tree.get_nodes_in_group(GROUP):
		var c := node as FieldCompanion
		if c != null and c.state != State.STRANDED:
			list.append(c.hud_entry())
	return list


## {name, hp: 0..1, command} for the field HUD.
func hud_entry() -> Dictionary:
	var command: String = MODE_LABELS[mode]
	if state == State.DOWNED:
		command = DOWNED_LABEL
	elif is_retreating():
		command = RETREAT_LABEL
	return {"name": display_name, "hp": health / max_health if max_health > 0.0 else 0.0, "command": command}


func set_mode(next: Mode) -> void:
	if next == mode:
		return
	mode = next
	target = null
	_retarget_left = 0.0
	mode_changed.emit(mode)


## Player.interact() entry (layer 7, only while downed): starts the 3 s help-up.
func begin_open(interactor: Node3D) -> bool:
	if state != State.DOWNED or _reviver != null or interactor == null:
		return false
	_reviver = interactor
	_revive_from = interactor.global_position
	_revive_left = tuning.revive_sec
	return true


## HUD prompt while downed.
func interact_label() -> String:
	return REVIVE_PROMPT % display_name


## HUD hold bar while being helped up, {} otherwise.
func hold_state() -> Dictionary:
	if _reviver == null or tuning.revive_sec <= 0.0:
		return {}
	return {"label": REVIVE_HOLD_LABEL, "progress": clampf(1.0 - _revive_left / tuning.revive_sec, 0.0, 1.0)}


## Damage from monsters (B-07 calls take_damage(amount, info) on layer 3 bodies).
## Status effects ride in info (StatusHolder header). Tick damage comes back here too.
func take_damage(amount: float, info: Dictionary = {}) -> void:
	if state != State.ACTIVE or amount <= 0.0:
		return
	amount = status.scale_damage(amount, info)
	status.apply_hit(info)
	var source: Variant = info.get("source")
	if source is Monster:
		# 신중 does not start fights, but fights back against whatever attacks it (decided 2026-11-05).
		_marked[source.get_instance_id()] = true
	health = maxf(health - amount, 0.0)
	if health == 0.0:
		_go_down()


## Left behind in this region (help-up time ran out). FieldState sends companion_stranded.
func strand() -> void:
	if state == State.STRANDED:
		return
	_become_stranded()
	FieldState.strand_companion(party_id)


func down_time_left() -> float:
	return _down_left if state == State.DOWNED else 0.0


## Sum of `key` over the resident's traits (data/traits, Lane C TraitDef.effects).
func trait_effect(key: StringName) -> float:
	var total := 0.0
	for id in resident.get("traits", []):
		var def := BaseDB.get_trait(StringName(id))
		if def != null:
			total += def.effect(key)
	return total


## 겁이 많음: at or under flee_hp_ratio it stops fighting and stays by the player. 용감함 never.
func is_retreating() -> bool:
	if state != State.ACTIVE or trait_effect(&"no_flee") > 0.0:
		return false
	var ratio := trait_effect(&"flee_hp_ratio")
	return ratio > 0.0 and health <= max_health * ratio


## Enums.Aptitude for an Enums.CombatClass (MID when unknown).
func aptitude(combat_class: int) -> int:
	if combat_class < 0 or combat_class >= ResidentData.CLASS_KEYS.size():
		return Enums.Aptitude.MID
	var apt: Dictionary = resident.get("class_aptitude", {})
	return int(apt.get(ResidentData.CLASS_KEYS[combat_class], Enums.Aptitude.MID))


func weapon_uid() -> StringName:
	var uid := Armory.get_equipped(party_id, Enums.EquipSlot.MAIN)
	return uid if uid != &"" else Armory.get_equipped(party_id, Enums.EquipSlot.SUB)


func weapon_stats() -> Dictionary:
	var uid := weapon_uid()
	return Armory.get_item_stats(uid) if uid != &"" else {}


## Attacker-side damage of one hit (before the monster's part, element, defense):
## stats damage x 적성 x 능력치 x crit. 07: "피해는 무기 x 적성 x 능력치 보정" (no class mastery).
func hit_damage(stats: Dictionary, crit_mult: float) -> float:
	var combat_class := int(stats.get("combat_class", -1))
	var extra := float(tuning.aptitude_damage_mult.get(aptitude(combat_class), 1.0)) * stat_damage_mult(combat_class)
	return DamageFormula.attacker_damage(float(stats.get("damage", 0.0)), 0, combat.mastery_per_level,
			crit_mult, extra)


## 07: 둔기 +3%/힘, 칼 +3%/손재주, 총 1.0.
func stat_damage_mult(combat_class: int) -> float:
	var stat := &""
	match combat_class:
		Enums.CombatClass.BLUNT:
			stat = &"str"
		Enums.CombatClass.BLADE:
			stat = &"dex"
	if stat == &"":
		return 1.0
	return 1.0 + tuning.stat_damage_per_point * _stat(stat)


## Gun spread (full cone, degrees): weapon spread, x1.5 while moving, -3% per 감각.
func spread_deg(stats: Dictionary) -> float:
	var base: float = combat.weapon_value(StringName(stats.get("def_id", &"")),
			int(stats.get("combat_class", -1)), "spread_deg", 0.0)
	var moving := Vector2(velocity.x, velocity.z).length() > combat.moving_speed_threshold
	var spread := DamageFormula.spread_deg(base, 0.0, moving, false, combat.moving_spread_mult, 1.0)
	return maxf(spread * (1.0 - tuning.spread_per_sense * _stat(&"sense")), 0.0)


func skill_cooldown(combat_class: int) -> float:
	if combat_class < 0 or combat_class >= tuning.skill_q_cooldown_sec.size():
		return 0.0
	return tuning.skill_q_cooldown_sec[combat_class] * tuning.skill_cooldown_mult


func can_use_skill(combat_class: int) -> bool:
	return combat_class >= 0 and aptitude(combat_class) >= tuning.skill_min_aptitude and _skill_left <= 0.0


## Q skill if 적성 상 and off cooldown. Returns true when used.
func try_skill(stats: Dictionary) -> bool:
	var combat_class := int(stats.get("combat_class", -1))
	if not can_use_skill(combat_class):
		return false
	_skill_left = skill_cooldown(combat_class)
	skill_used.emit(combat_class)
	# TODO(B-13): run the class Q skill with this companion as the user (needs B-13's skill runner).
	return true


func skill_time_left() -> float:
	return _skill_left


## One shot (all pellets) or one swing at `target` if the weapon is ready. Returns true if it attacked.
## Ammo: the magazine and reload are real, the reserve is endless (decided 2026-11-05).
func attack(stats: Dictionary) -> bool:
	if not _target_valid() or stats.is_empty() or _attack_left > 0.0 or _reload_left > 0.0:
		return false
	var uid := weapon_uid()
	_attack_left = float(stats.get("attack_interval", 1.0))
	var chance := DamageFormula.crit_chance(float(stats.get("crit_rate", combat.crit_rate)),
			float(stats.get("crit_pctp", 0)))
	var crit := DamageFormula.crit_multiplier(rng.randf(), chance, combat.crit_mult)
	var info := {
		"source": self,
		"element": stats.get("element", Enums.Element.NONE),
		"weapon": stats.get("def_id", &""),
		"crit": crit > 1.0,
	}
	var amount := hit_damage(stats, crit)
	if WeaponHolder.is_gun(stats):
		var magazine := int(stats.get("magazine", 0))
		if _magazine < 0:
			_magazine = magazine
		var origin := global_position + Vector3.UP * combat.muzzle_height
		var aim := (target.global_position + Vector3.UP * AIM_HEIGHT - origin).normalized()
		for i in maxi(int(stats.get("pellets", 1)), 1):
			_shoot_ray(origin, _spread_dir(aim, spread_deg(stats)), float(stats.get("range", 0.0)), amount, info)
		Armory.wear(uid, combat.gun_wear)
		Audio.play(StringName("gunshot_%s" % stats.get("def_id", "")), origin)
		if magazine > 0:
			_magazine -= 1
			if _magazine <= 0:
				_reload_left = float(combat.weapon_value(StringName(stats.get("def_id", &"")),
						int(stats.get("combat_class", -1)), "reload_sec", 1.5))
	else:
		info["position"] = target.global_position
		_deal(target, amount, info)
		Armory.wear(uid, combat.melee_wear)
		Audio.play(&"swing_blade" if int(stats.get("combat_class", -1)) == Enums.CombatClass.BLADE
				else &"swing_blunt", global_position)
	var noise_action: StringName = combat.weapon_value(StringName(stats.get("def_id", &"")),
			int(stats.get("combat_class", -1)), "noise_action", &"")
	if noise_action != &"":
		_noise.emit(noise_action)
	attacked.emit(target)
	return true


## Who it stays near: the guarded rescued person in 엄호, else the player.
func anchor() -> Node3D:
	var guarded := guarded_person()
	return guarded if guarded != null else _player


## 엄호: the nearest rescued person in the party, or null.
func guarded_person() -> Node3D:
	if mode != Mode.COVER or not is_inside_tree():
		return null
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(PARTY_GROUP):
		if node == self or not node is Node3D or node.get(&"party_kind") != ExtractionManager.KIND_RESCUED:
			continue
		var d := _flat_distance(node.global_position)
		if d < best_dist:
			best = node
			best_dist = d
	return best


## Monster to fight in the current mode, or null.
func pick_target() -> Node3D:
	var center := global_position
	var radius := tuning.engage_radius
	if mode == Mode.COVER:
		var a := anchor()
		if a != null:
			center = a.global_position
		radius = tuning.cover_radius
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(Monster.GROUP):
		var m := node as Monster
		if m == null or m.is_dead():
			continue
		if mode == Mode.CAUTIOUS and not _marked.has(m.get_instance_id()):
			continue
		var d := m.global_position.distance_to(center)
		if d > radius or d >= best_dist or not has_line_of_sight(m):
			continue
		best = m
		best_dist = d
	return best


## No wall between this companion and `node` (low cover does not block).
func has_line_of_sight(node: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * combat.muzzle_height
	var to := node.global_position + Vector3.UP * combat.muzzle_height
	var exclude: Array[RID] = [get_rid()]
	for i in MAX_COVER_PASSES + 1:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, to, WORLD_MASK, exclude))
		if hit.is_empty():
			return true
		if not _is_low_cover(hit["collider"]):
			return false
		exclude.append(hit["rid"])
	return false


## Current walking speed (m/s): the player's walk, their sprint when far behind, x armor.
func move_speed() -> float:
	var walk := FALLBACK_WALK_SPEED
	var sprint := FALLBACK_SPRINT_SPEED
	if _player != null and _player.get(&"stats") != null:
		walk = _player.stats.walk_speed
		sprint = _player.stats.sprint_speed
	var far := _player != null and _flat_distance(_player.global_position) > tuning.catchup_distance
	return (sprint if far else walk) * _armor_speed_mult


## 07 참여 조건 이동 (휠체어, 거동이 불편한 노인): no stairs, like the wheelchair rescue.
func navigation_layers() -> int:
	return NAV_NO_STAIRS if Enums.AccessNeed.MOBILITY in resident.get("access_needs", []) else NAV_ALL


## One step (timers, AI, noise). _physics_process calls it; tests can call it directly.
func tick(delta: float) -> void:
	status.step(delta)
	match state:
		State.ACTIVE:
			_tick_active(delta)
		State.DOWNED:
			_tick_downed(delta)
	_update_noise()


# --- AI ------------------------------------------------------------------------

func _tick_active(delta: float) -> void:
	if not is_instance_valid(_player):
		_bind_player(_find_player())
	_attack_left = maxf(_attack_left - delta, 0.0)
	_skill_left = maxf(_skill_left - delta, 0.0)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_magazine = -1
	_retarget_left -= delta
	if _retarget_left <= 0.0:
		_retarget_left = tuning.retarget_sec
		target = pick_target()
	elif not _target_valid():
		target = null
	if is_retreating():
		target = null
	var a := anchor()
	if target != null:
		_fight(a, delta)
	elif a != null:
		_walk_toward(a.global_position, tuning.follow_distance, delta)
	else:
		_stop()


func _fight(a: Node3D, delta: float) -> void:
	if not status.can_act():
		# Staggered or knocked back (B-14): no moving on its own, turning or attacking.
		_stop()
		return
	var stats := weapon_stats()
	if stats.is_empty():
		# No weapon: keeps to the player / guarded person.
		target = null
		if a != null:
			_walk_toward(a.global_position, tuning.follow_distance, delta)
		return
	var reach := float(stats.get("range", 0.0))
	if not WeaponHolder.is_gun(stats):
		reach += tuning.melee_reach_bonus
	_face(target.global_position)
	if _flat_distance(target.global_position) > reach:
		var leashed := a != null and _flat(a.global_position - target.global_position) > tuning.leash_distance + reach
		if leashed:
			_walk_toward(a.global_position, tuning.follow_distance, delta)
		else:
			_walk_toward(target.global_position, reach * 0.9, delta)
		return
	_stop()
	try_skill(stats)
	attack(stats)


func _target_valid() -> bool:
	if not is_instance_valid(target):
		return false
	var m := target as Monster
	return m == null or not m.is_dead()


func _bind_player(player: Node3D) -> void:
	_player = player
	if player == null:
		return
	# 신중: remember what the player hits (B-06 WeaponHolder.hit_landed).
	var weapons := player.get_node_or_null(^"Weapons") as WeaponHolder
	if weapons != null and not weapons.hit_landed.is_connected(_on_player_hit):
		weapons.hit_landed.connect(_on_player_hit)


func _on_player_hit(hit: Node, _amount: float, _info: Dictionary) -> void:
	var node := hit
	while node != null and not node is Monster:
		node = node.get_parent()
	if node != null:
		_marked[node.get_instance_id()] = true


func _shoot_ray(origin: Vector3, direction: Vector3, max_range: float, amount: float, info: Dictionary) -> Node:
	var space := get_world_3d().direct_space_state
	var to := origin + direction * max_range
	var exclude: Array[RID] = [get_rid()]
	for i in MAX_COVER_PASSES + 1:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, to, SHOT_MASK, exclude))
		if hit.is_empty():
			break
		if _is_low_cover(hit["collider"]):
			exclude.append(hit["rid"])
			continue
		Fx.spawn(&"bullet_tracer", origin, {"to": hit["position"]})
		var victim := _damage_target(hit["collider"])
		if victim != null:
			var hit_info := info.duplicate()
			hit_info["position"] = hit["position"]
			_deal(victim, amount, hit_info)
		return victim
	Fx.spawn(&"bullet_tracer", origin, {"to": to})
	return null


func _deal(victim: Node, amount: float, info: Dictionary) -> void:
	victim.take_damage(amount, info)
	Fx.spawn(&"hit_spark", info.get("position", global_position), {
		"element": info.get("element", Enums.Element.NONE), "crit": info.get("crit", false)})


## Horizontal spread inside a cone of `spread` degrees (full angle).
func _spread_dir(forward: Vector3, spread: float) -> Vector3:
	if spread <= 0.0:
		return forward
	var half := deg_to_rad(spread * 0.5)
	return forward.rotated(Vector3.UP, rng.randf_range(-half, half)).normalized()


## The collider or its nearest ancestor with take_damage(). Never the player or an ally.
func _damage_target(node: Node) -> Node:
	while node != null and not node is Player and not node is FieldCompanion:
		if node.has_method(&"take_damage"):
			return node
		node = node.get_parent()
	return null


func _is_low_cover(node: Node) -> bool:
	return node != null and (node.is_in_group(WeaponHolder.LOW_COVER_GROUP)
			or (node.get_parent() != null and node.get_parent().is_in_group(WeaponHolder.LOW_COVER_GROUP)))


func _stat(key: StringName) -> float:
	var stats: Dictionary = resident.get("stats", {})
	return float(stats.get(key, 0))


# --- Movement ------------------------------------------------------------------

## Walks the nav path toward goal until stop_distance (flat). No path = stays put (B-10 rule).
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
	var dir := _path[_path_index] - global_position
	dir.y = 0.0
	dir = dir.normalized()
	var speed := move_speed()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if target == null:
		rotation.y = atan2(-dir.x, -dir.z)


func _repath(goal: Vector3) -> void:
	_repath_left = tuning.repath_sec
	_path_goal = goal
	_path_index = 0
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		# No nav mesh synced yet (tests, scenes without navigation): stay put.
		_path = PackedVector3Array()
		return
	_path = NavigationServer3D.map_get_path(map, global_position, goal, true, navigation_layers())


func _face(point: Vector3) -> void:
	var to := point - global_position
	if Vector2(to.x, to.z).length_squared() > 0.0001:
		rotation.y = atan2(-to.x, -to.z)


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _update_noise() -> void:
	var action: StringName = &""
	if state == State.ACTIVE and Vector2(velocity.x, velocity.z).length() > MOVING_SPEED:
		action = tuning.mode_footstep.get(mode, &"escort_walk")
	if action == _footstep:
		return
	_footstep = action
	if action == &"":
		_noise.stop_continuous()
	else:
		_noise.start_continuous(action)


# --- Downed --------------------------------------------------------------------

func _go_down() -> void:
	target = null
	_stop()
	status.clear()
	_down_left = tuning.downed_sec
	_set_state(State.DOWNED)
	downed.emit()


## The 30 s wait pauses while someone is helping. Moving away or going down cancels the help.
func _tick_downed(delta: float) -> void:
	if _reviver != null:
		if not is_instance_valid(_reviver) or _reviver.get(&"is_downed") == true \
				or _reviver.global_position.distance_to(_revive_from) > tuning.revive_cancel_distance:
			_reviver = null
		else:
			_revive_left -= delta
			if _revive_left <= 0.0:
				_finish_revive()
			return
	_down_left -= delta
	if _down_left <= 0.0:
		strand()


func _finish_revive() -> void:
	_reviver = null
	health = max_health * tuning.revive_health_ratio
	_set_state(State.ACTIVE)
	revived.emit()


func _become_stranded() -> void:
	_reviver = null
	target = null
	_stop()
	remove_from_group(PARTY_GROUP)
	_set_state(State.STRANDED)
	stranded.emit()


## The player went down (FieldState) or left this companion at extraction (B-09).
func _on_companion_stranded(resident_id: StringName, _region_id: StringName) -> void:
	if resident_id == party_id and state != State.STRANDED:
		_become_stranded()


# --- Helpers -------------------------------------------------------------------

func _set_state(next: State) -> void:
	if next == state:
		return
	state = next
	_repath_left = 0.0
	_apply_layers()


## Layer 3 (ally) while up, layer 7 (interactable) while downed.
func _apply_layers() -> void:
	set_collision_layer_value(Enums.LAYER_ALLY, state == State.ACTIVE)
	set_collision_layer_value(Enums.LAYER_INTERACTABLE, state == State.DOWNED)


func _find_player() -> Node3D:
	return get_tree().get_first_node_in_group(Player.GROUP) as Node3D if is_inside_tree() else null


func _flat_distance(point: Vector3) -> float:
	return _flat(point - global_position)


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
