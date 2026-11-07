class_name WeaponHolder
extends Node3D
## Player weapon runtime (B-06). Child of the Player scene ("Weapons").
## Weapon stats come only from Armory.get_item_stats() of the item in the active slot.
## Rules that are not item stats (spread, reload time, stamina cost, block, combo ...) come from
## `tuning` (data/classes/combat_tuning.tres). Damage math lives in DamageFormula.
## Guns: hitscan rays from muzzle_height, pellets, spread, bloom, magazine + Bag reserve, reload.
## Melee: 3-hit combo, arc hit, backstab, block (the aim action) and perfect block.
## Low cover: any collider (or its parent) in group LOW_COVER_GROUP. Shots pass over it, and a target
## within tuning.cover_near_target_m behind it takes tuning.cover_damage_mult. Other world
## colliders stop shots.
## Design reference: docs/design/03-combat-classes.md "근접 전투", "사격", "피해 공식"

signal weapon_changed(slot: Enums.EquipSlot, item_uid: StringName)
## reserve = -1 for infinite ammo, 0 for melee weapons.
signal ammo_changed(in_magazine: int, reserve: int)
signal reload_started(duration_sec: float)
## Trigger pulled on an empty magazine with nothing to reload (aim reticle shake).
signal dry_fired()
signal reload_finished()
## kind: &"shot" or &"swing". combo_step: 1..3 for swings, 0 for shots.
signal attacked(kind: StringName, combo_step: int)
## One bullet path (per pellet), same points as Fx "bullet_tracer". hit = it stopped on something.
signal shot_traced(from: Vector3, to: Vector3, hit: bool)
signal hit_landed(target: Node, amount: float, info: Dictionary)
signal blocked(perfect: bool)
signal guard_broken()

## Group for low cover colliders. B-12 layouts and D dressing put their low cover bodies here.
const LOW_COVER_GROUP := &"low_cover"
const DEFAULT_TUNING := preload("res://data/classes/combat_tuning.tres")
const MELEE_MASK := 1 << (Enums.LAYER_MONSTER - 1)
const WORLD_MASK := 1 << (Enums.LAYER_WORLD - 1)
const MONSTER_MASK := 1 << (Enums.LAYER_MONSTER - 1)
## Shot box half width with aim assist off: a thin line.
const MIN_SHOT_HALF_WIDTH := 0.01
## Most monster bodies one shot line can report.
const MAX_LINE_HITS := 32
## Melee hit sphere center height above the player's feet.
const MELEE_HEIGHT := 1.0
const MELEE_MAX_HITS := 16
## A shot passes at most this many low cover colliders before it stops looking.
const MAX_COVER_PASSES := 4
## Used when a weak point has no sphere collision shape.
const DEFAULT_WEAK_POINT_RADIUS := 0.2

@export var tuning: CombatTuning = DEFAULT_TUNING
## Armory owner (Armory.PLAYER_ID).
@export var owner_id: StringName = &"player"

var active_slot: Enums.EquipSlot = Enums.EquipSlot.MAIN
var is_blocking := false
var is_reloading := false
## Step of the last swing (1..tuning.combo_hits), 0 before any swing.
var combo_step := 0
var rng := RandomNumberGenerator.new()
## B-13 ClassSkills: (target, amount, info) -> amount, called for every hit before take_damage.
## It may add info["status"] (class on-hit effects, skills, passives).
var hit_filter: Callable
## B-13 precision shot: shots keep going through the monsters they hit.
var shot_pierces := false
## B-13 gun passive: reload time x this.
var reload_mult := 1.0

var _player: Player
## item uid -> rounds in the magazine. Unknown uid = full magazine.
var _magazines: Dictionary = {}
var _clock := 0.0
## Clock time when the next attack may start.
var _ready_at := 0.0
var _reload_done_at := 0.0
var _last_shot_at := -INF
var _bloom := 0.0
## Set during fire(): where its muzzle flash and tracers are drawn from (_visual_muzzle).
var _draw_from := Vector3.INF
var _block_started := 0.0
var _stun_until := 0.0
## Guard break: aim must be released once before blocking again.
var _block_needs_release := false
## Melee attack pressed during the recovery: swing as soon as ready.
var _attack_buffered := false


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_error("WeaponHolder must be a child of Player")
		set_physics_process(false)
		return
	_player.incoming_damage_filter = filter_incoming
	EventBus.equipment_changed.connect(_on_equipment_changed)
	if current_uid() == &"":
		_switch_to_any()


func _physics_process(delta: float) -> void:
	if _player.is_downed or _player.is_riding():
		return
	step(delta, {"aim": _player.is_aiming} if Player.input_blocked() else _read_input())


## One step. Split from input reading so tests can drive it.
## input: {"attack": just pressed, "attack_held": bool, "aim": bool, "reload": bool,
##         "weapon_1": bool, "weapon_2": bool, "weapon_swap": bool}
func step(delta: float, input: Dictionary) -> void:
	_clock += delta
	if is_reloading and _clock >= _reload_done_at:
		_finish_reload()
	if input.get("weapon_1", false):
		switch_to(Enums.EquipSlot.MAIN)
	elif input.get("weapon_2", false):
		switch_to(Enums.EquipSlot.SUB)
	elif input.get("weapon_swap", false):
		switch_to(_other_slot())
	if not usable(current_stats()):
		# Supporting someone (B-10): fall back to the light weapon in the other slot if there is one.
		switch_to(_other_slot())
	var stats := current_stats()
	if stats.is_empty() or not usable(stats):
		_set_blocking(false)
		return
	if is_gun(stats):
		_step_gun(delta, stats, input)
	else:
		_step_melee(stats, input)


# --- Public ---------------------------------------------------------------

func current_uid() -> StringName:
	return Armory.get_equipped(owner_id, active_slot)


func current_stats() -> Dictionary:
	var uid := current_uid()
	return Armory.get_item_stats(uid) if uid != &"" else {}


static func is_gun(stats: Dictionary) -> bool:
	return int(stats.get("combat_class", -1)) == Enums.CombatClass.GUN


## False for a two-hand weapon while the player supports someone (02 "함께 나오기": 부축 중엔
## 권총, 단검 같은 한 손 무기만). Light = ItemDef.light (보조무기 가능).
func usable(stats: Dictionary) -> bool:
	if stats.is_empty() or _player == null or not _player.one_hand_only:
		return true
	return bool(stats.get("light", false))


## Makes `slot` active. Fails when nothing is equipped there, or it is two-handed while supporting.
func switch_to(slot: Enums.EquipSlot) -> bool:
	var uid := Armory.get_equipped(owner_id, slot)
	if uid == &"" or not usable(Armory.get_item_stats(uid)):
		return false
	if slot == active_slot:
		return true
	active_slot = slot
	_reset_weapon_state()
	return true


func can_act() -> bool:
	return _clock >= _stun_until and _player.move_state != Player.MoveState.DODGE \
			and not _player.is_downed


func is_stunned() -> bool:
	return _clock < _stun_until


func ammo_in_magazine() -> int:
	var stats := current_stats()
	if not is_gun(stats):
		return 0
	return int(_magazines.get(current_uid(), int(stats.get("magazine", 0))))


## -1 = infinite, otherwise rounds of this gun's ammo in the Bag.
func ammo_reserve() -> int:
	var stats := current_stats()
	if not is_gun(stats):
		return 0
	if StringName(stats["def_id"]) in tuning.infinite_ammo_defs or GameState.has_flag(StartKit.FLAG_INFINITE_AMMO):
		return -1
	return Bag.count(StringName(stats.get("ammo_id", &"")))


## Current full cone angle for the next shot (degrees).
func current_spread_deg() -> float:
	var stats := current_stats()
	return DamageFormula.spread_deg(_weapon_value(stats, "spread_deg", 0.0), _bloom, _is_moving(),
			_player.is_aiming, tuning.moving_spread_mult, tuning.aim_spread_mult)


## Fires the active gun once (all pellets). Empty magazine starts a reload instead.
func fire() -> bool:
	var stats := current_stats()
	if not is_gun(stats) or not can_act() or is_reloading or _clock < _ready_at:
		return false
	var uid := current_uid()
	var rounds := ammo_in_magazine()
	if rounds <= 0:
		if not start_reload():
			Audio.play(&"dry_fire", global_position)
			dry_fired.emit()
		return false
	_magazines[uid] = rounds - 1
	_ready_at = _clock + float(stats.get("attack_interval", 0.3))
	_last_shot_at = _clock
	var base_spread: float = _weapon_value(stats, "spread_deg", 0.0)
	var spread := current_spread_deg()
	_bloom = DamageFormula.add_bloom(_bloom, tuning.bloom_per_shot_deg, base_spread,
			_weapon_value(stats, "spread_cap_deg", base_spread))
	var crit := _roll_crit(stats)
	var amount := _attacker_damage(stats, crit)
	var origin := _player.global_position + Vector3.UP * tuning.muzzle_height
	var forward := _player.facing()
	_draw_from = _visual_muzzle(origin, forward)
	for i in maxi(int(stats.get("pellets", 1)), 1):
		var angle := deg_to_rad(rng.randf_range(-spread * 0.5, spread * 0.5))
		shoot_ray(origin, forward.rotated(Vector3.UP, angle), float(stats.get("range", 10.0)),
				amount, _hit_info(stats, crit))
	Armory.wear(uid, tuning.gun_wear)
	_emit_noise(stats)
	Audio.play(StringName("gunshot_%s" % stats["def_id"]), origin)
	Fx.spawn(&"muzzle_flash", _draw_from, {"direction": forward})
	_draw_from = Vector3.INF
	CombatFeel.kick(self, forward, stats["def_id"])
	attacked.emit(&"shot", 0)
	_emit_ammo()
	return true


## Where this shot is drawn from: the model's hand (PlayerModel.muzzle_point), else the old spot.
## Only the look: the hitscan stays at tuning.muzzle_height so low cover works the same.
func _visual_muzzle(origin: Vector3, forward: Vector3) -> Vector3:
	var model := _player.get_node_or_null(^"Model")
	if model != null and model.has_method(&"muzzle_point"):
		var p: Variant = model.call(&"muzzle_point", forward)
		if p is Vector3 and (p as Vector3).is_finite():
			return p
	return origin + forward * 0.5


func _tracer_from(origin: Vector3) -> Vector3:
	return _draw_from if _draw_from.is_finite() else origin


## One hitscan shot along the flat `direction`. Walls: a ray at the shot height that passes over low
## cover and stops at other world colliders. Monsters: any body on the monster layer touching the
## line up to that wall, at any height and shot_radius() to either side (monsters_on_line), so
## short ones (split slimes, rubble bugs) are hit too. Damages the nearest one (every one while
## shot_pierces), then a world collider with take_damage() where the shot stops.
## Returns the first node it damaged, or null.
func shoot_ray(origin: Vector3, direction: Vector3, max_range: float, amount: float,
		info: Dictionary) -> Node:
	var space := get_world_3d().direct_space_state
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	var exclude: Array[RID] = [_player.get_rid()]
	var wall := wall_on_line(space, origin, dir, max_range, exclude)
	var end: Vector3 = wall.get("position", origin + dir * max_range)
	var cover_points: Array = wall["cover"]
	var first: Node = null
	for hit: Dictionary in monsters_on_line(space, origin, dir, origin.distance_to(end), shot_radius(),
			tuning.shot_hit_below, tuning.shot_hit_above, exclude):
		var target := _damage_target(hit["collider"])
		if target == null:
			continue
		if target is Monster:
			var weak := _weak_point_on_line(target as Monster, origin, dir, hit["distance"])
			if weak != null:
				target = weak
		_shot_hit(target, hit["position"], amount, info, cover_points)
		if first == null:
			first = target
		if not shot_pierces:
			Fx.spawn(&"bullet_tracer", _tracer_from(origin), {"to": hit["position"]})
			shot_traced.emit(origin, hit["position"], true)
			return first
	var stopped := wall.has("collider")
	Fx.spawn(&"bullet_tracer", _tracer_from(origin), {"to": end})
	shot_traced.emit(origin, end, stopped)
	if stopped:
		var target := _damage_target(wall["collider"])
		if target == null:
			Fx.spawn(&"bullet_impact", end, {"normal": wall["normal"]})
		else:
			_shot_hit(target, end, amount, info, cover_points)
			if first == null:
				first = target
	return first


## Half width (m) of the shot against monsters, from Settings `aim_assist`.
func shot_radius() -> float:
	var sizes := tuning.shot_radius_by_assist
	if sizes.is_empty():
		return 0.0
	return sizes[clampi(int(Settings.get_value(&"aim_assist")), 0, sizes.size() - 1)]


## Where a flat shot line stops on the world layer. Low cover is passed and remembered.
## {"cover": Array[Vector3]} plus "position", "normal", "collider" when something stopped it.
static func wall_on_line(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3,
		max_range: float, exclude: Array[RID]) -> Dictionary:
	var to := origin + dir * max_range
	var skip := exclude.duplicate()
	var cover: Array[Vector3] = []
	for pass_index in MAX_COVER_PASSES + 1:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, to, WORLD_MASK, skip))
		if hit.is_empty():
			break
		if is_low_cover(hit["collider"]) and pass_index < MAX_COVER_PASSES:
			cover.append(hit["position"])
			skip.append(hit["rid"])
			continue
		return {"cover": cover, "position": hit["position"], "normal": hit["normal"],
			"collider": hit["collider"]}
	return {"cover": cover}


## Bodies on the monster layer touching the flat line from `origin` for `length` m: anywhere from
## `below` under to `above` over it and up to `radius` to either side. Nearest first, each
## {"collider", "position" (on the line), "distance"}. FieldCompanion shoots with it too.
static func monsters_on_line(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3,
		length: float, radius: float, below: float, above: float, exclude: Array[RID]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	if length <= 0.0 or flat.is_zero_approx():
		return found
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(radius, MIN_SHOT_HALF_WIDTH) * 2.0, below + above, length)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis.looking_at(flat),
			origin + flat * length * 0.5 + Vector3.UP * (above - below) * 0.5)
	query.collision_mask = MONSTER_MASK
	query.exclude = exclude
	var seen := {}
	for hit in space.intersect_shape(query, MAX_LINE_HITS):
		var body := hit["collider"] as Node3D
		if body == null or seen.has(body):
			continue
		seen[body] = true
		var along := clampf((body.global_position - origin).dot(flat), 0.0, length)
		found.append({"collider": body, "position": origin + flat * along, "distance": along})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	return found


## Low cover collider: in LOW_COVER_GROUP itself or through its parent.
static func is_low_cover(node: Node) -> bool:
	return node != null and (node.is_in_group(LOW_COVER_GROUP)
			or (node.get_parent() != null and node.get_parent().is_in_group(LOW_COVER_GROUP)))


## Starts reloading the active gun. False when full, already reloading or out of reserve ammo.
func start_reload() -> bool:
	var stats := current_stats()
	if not is_gun(stats) or is_reloading or not can_act():
		return false
	if ammo_in_magazine() >= int(stats.get("magazine", 0)) or ammo_reserve() == 0:
		return false
	var duration: float = _weapon_value(stats, "reload_sec", 1.5) \
			* (1.0 - float(stats.get("reload_pct", 0)) / 100.0) * reload_mult
	is_reloading = true
	_reload_done_at = _clock + duration
	Audio.play(reload_event(StringName(stats.get("def_id", &""))), global_position)
	reload_started.emit(duration)
	return true


## Reload sound for a gun: `reload_<def_id>` (pump, bolt ...) when that event exists, else the shared `reload`.
static func reload_event(def_id: StringName) -> StringName:
	var id := StringName("reload_%s" % def_id)
	return id if Audio.events.has(id) else &"reload"


## One melee swing at the active weapon. Hits every monster body in reach inside the arc.
func swing() -> bool:
	var stats := current_stats()
	if stats.is_empty() or is_gun(stats) or not can_act() or is_blocking or _clock < _ready_at:
		return false
	var cost: float = _weapon_value(stats, "stamina_cost", 0.0) \
			* (1.0 - float(stats.get("stamina_pct", 0)) / 100.0)
	if _player.stamina < cost:
		return false
	var combat_class := int(stats["combat_class"])
	combo_step = DamageFormula.next_combo(combo_step, _clock - _ready_at,
			tuning.combo_window(combat_class), tuning.combo_hits)
	_ready_at = _clock + float(stats.get("attack_interval", 0.5))
	_attack_buffered = false
	_player.spend_stamina(cost)
	var finisher := tuning.combo_finisher_mult if combo_step == tuning.combo_hits else 1.0
	var crit := _roll_crit(stats)
	var base_amount := _attacker_damage(stats, crit, finisher)
	var backstab_mult := float(stats.get("backstab_mult", tuning.backstab_mult))
	for target in melee_targets(float(stats.get("range", 1.5))):
		var info := _hit_info(stats, crit)
		info["position"] = target.global_position
		info["combo_step"] = combo_step
		var amount := base_amount * _family_bonus(stats, target)
		if _is_backstab(target):
			amount *= backstab_mult
			info["backstab"] = true
		_deal(target, amount, info)
	Armory.wear(current_uid(), tuning.melee_wear)
	_emit_noise(stats)
	Audio.play(&"swing_blade" if combat_class == Enums.CombatClass.BLADE else &"swing_blunt",
			global_position)
	Fx.spawn(&"melee_swing", _player.global_position, {"direction": _player.facing(),
		"radius": float(stats.get("range", 1.5)), "element": stats.get("element", Enums.Element.NONE),
		"combat_class": combat_class, "finisher": combo_step == tuning.combo_hits})
	attacked.emit(&"swing", combo_step)
	return true


## B-13 skills: one hit on `target` with the active weapon's damage x mult (mastery and crit as
## usual), through the same path as shots and swings (hit_filter, hit_landed).
func skill_hit(target: Node3D, mult: float, extra_info: Dictionary = {}) -> void:
	var stats := current_stats()
	var crit := _roll_crit(stats)
	var info := _hit_info(stats, crit)
	info["position"] = target.global_position
	info.merge(extra_info, true)
	_deal(target, _attacker_damage(stats, crit, mult), info)


## Monsters whose body is within `reach` of the player and inside the swing arc.
func melee_targets(reach: float) -> Array[Node3D]:
	var sphere := SphereShape3D.new()
	sphere.radius = reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), _player.global_position + Vector3.UP * MELEE_HEIGHT)
	query.collision_mask = MELEE_MASK
	query.exclude = [_player.get_rid()]
	var found: Array[Node3D] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, MELEE_MAX_HITS):
		var target := _damage_target(hit["collider"]) as Node3D
		if target == null or target in found:
			continue
		if DamageFormula.in_arc(_player.facing(), target.global_position - _player.global_position,
				tuning.melee_arc_deg):
			found.append(target)
	return found


## Player.take_damage() calls this first (Player.incoming_damage_filter). Returns the damage to take.
func filter_incoming(amount: float, info: Dictionary) -> float:
	if not is_blocking:
		return amount
	var source := info.get("source") as Node3D
	if source == null or not DamageFormula.in_arc(_player.facing(),
			source.global_position - _player.global_position, tuning.block_arc_deg):
		return amount
	var result := DamageFormula.block(amount, _clock - _block_started,
			tuning.perfect_block_window_sec, tuning.block_damage_mult, tuning.block_stamina_per_damage)
	if result["perfect"]:
		if source.has_method("stun"):
			source.stun(tuning.perfect_block_stun_sec)
		Audio.play(&"perfect_block", global_position)
		Fx.spawn(&"perfect_block", global_position, {})
		blocked.emit(true)
		return 0.0
	_player.spend_stamina(result["stamina_cost"])
	Audio.play(&"block", global_position)
	blocked.emit(false)
	if _player.stamina <= 0.0:
		_break_guard()
	return result["damage"]


# --- Internals ------------------------------------------------------------

func _read_input() -> Dictionary:
	return {
		"attack": Input.is_action_just_pressed(&"attack"),
		"attack_held": Input.is_action_pressed(&"attack"),
		# Player already applies Settings toggle_aim; the dodge clears it.
		"aim": _player.is_aiming,
		"reload": Input.is_action_just_pressed(&"reload"),
		"weapon_1": Input.is_action_just_pressed(&"weapon_1"),
		"weapon_2": Input.is_action_just_pressed(&"weapon_2"),
		"weapon_swap": Input.is_action_just_pressed(&"weapon_swap"),
	}


func _step_gun(delta: float, stats: Dictionary, input: Dictionary) -> void:
	_set_blocking(false)
	if _clock - _last_shot_at > float(stats.get("attack_interval", 0.3)) * tuning.bloom_recover_delay_mult:
		_bloom = maxf(_bloom - tuning.bloom_recover_deg_per_sec * delta, 0.0)
	if input.get("reload", false):
		start_reload()
	if input.get("attack", false) or (stats.get("full_auto", false) and input.get("attack_held", false)):
		fire()


func _step_melee(stats: Dictionary, input: Dictionary) -> void:
	var aim: bool = input.get("aim", false)
	if not aim:
		_block_needs_release = false
	_set_blocking(aim and can_act() and not _block_needs_release)
	if is_blocking:
		_attack_buffered = false
		return
	if input.get("attack", false):
		_attack_buffered = true
	if _attack_buffered and _clock >= _ready_at:
		if not swing():
			_attack_buffered = false


func _set_blocking(on: bool) -> void:
	if on and not is_blocking:
		_block_started = _clock
	is_blocking = on


func _break_guard() -> void:
	_set_blocking(false)
	_block_needs_release = true
	_stun_until = _clock + tuning.guard_break_stun_sec
	_player.stun(tuning.guard_break_stun_sec)
	Audio.play(&"guard_break", global_position)
	guard_broken.emit()


func _finish_reload() -> void:
	is_reloading = false
	var stats := current_stats()
	if not is_gun(stats):
		return
	var need := int(stats.get("magazine", 0)) - ammo_in_magazine()
	var reserve := ammo_reserve()
	var take := need if reserve < 0 else mini(need, reserve)
	if reserve >= 0 and take > 0:
		Bag.consume(StringName(stats.get("ammo_id", &"")), take)
	_magazines[current_uid()] = ammo_in_magazine() + take
	reload_finished.emit()
	_emit_ammo()


func _attacker_damage(stats: Dictionary, crit_mult: float, extra: float = 1.0) -> float:
	# stats.damage already has rarity, upgrade (1 + 0.06U), affixes and durability.
	return DamageFormula.attacker_damage(float(stats.get("damage", 0.0)), _mastery(stats),
			tuning.mastery_per_level, crit_mult, extra)


## Class mastery (A-11 Progression) of the weapon's family. The holder is always the player's.
func _mastery(stats: Dictionary) -> int:
	var family := int(stats.get("combat_class", -1))
	return ClassMastery.level(family) if family >= 0 else tuning.default_mastery


func _roll_crit(stats: Dictionary) -> float:
	var chance := DamageFormula.crit_chance(
			float(stats.get("crit_rate", tuning.crit_rate)), float(stats.get("crit_pctp", 0)))
	return DamageFormula.crit_multiplier(rng.randf(), chance, tuning.crit_mult)


func _hit_info(stats: Dictionary, crit_mult: float) -> Dictionary:
	return {
		"source": _player,
		"element": stats.get("element", Enums.Element.NONE),
		"weapon": stats.get("def_id", &""),
		"crit": crit_mult > 1.0,
	}


func _deal(target: Node, amount: float, info: Dictionary) -> void:
	if hit_filter.is_valid():
		amount = hit_filter.call(target, amount, info)
	target.take_damage(amount, info)
	Fx.spawn(&"hit_spark", info.get("position", global_position), {
		"element": info.get("element", Enums.Element.NONE),
		"weak_point": target is MonsterWeakPoint,
		"crit": info.get("crit", false),
		"shot": info.get("shot", false),  # bullet hits add a burst, chips and dust (hit_spark.tres)
	})
	_hit_stop(target, info)
	hit_landed.emit(target, amount, info)


## A shot hit at `point`: low cover within tuning.cover_near_target_m of it scales the damage.
func _shot_hit(target: Node, point: Vector3, amount: float, info: Dictionary, cover_points: Array) -> void:
	var hit_info := info.duplicate()
	hit_info["position"] = point
	hit_info["shot"] = true
	for cover_point: Vector3 in cover_points:
		if cover_point.distance_to(point) <= tuning.cover_near_target_m:
			amount *= tuning.cover_damage_mult
			hit_info["cover"] = true
			break
	_deal(target, amount, hit_info)


## B-27: hit-stop for melee hits, kills and crit / weak point kills (never a single bullet).
func _hit_stop(target: Node, info: Dictionary) -> void:
	var monster := target as Monster
	if monster == null and target is MonsterWeakPoint:
		monster = target.get_parent() as Monster
	var killed := monster != null and is_instance_valid(monster) and monster.is_dead()
	var melee := info.has("combo_step")
	var finisher := melee and int(info["combo_step"]) == tuning.combo_hits
	var crit: bool = info.get("crit", false) or target is MonsterWeakPoint
	CombatFeel.hit_stop(self, CombatFeel.stop_for(killed, crit, melee, finisher))


## Machete "수풀 계열 피해 +20%": stats vs_green_bonus against GREEN monsters.
func _family_bonus(stats: Dictionary, target: Node) -> float:
	var monster := target as Monster
	if monster != null and monster.def.family == Enums.Element.GREEN:
		return 1.0 + float(stats.get("vs_green_bonus", 0.0))
	return 1.0


func _is_backstab(target: Node3D) -> bool:
	var aware := false
	if target is Monster:
		aware = (target as Monster).state in [Enums.AIState.CHASE, Enums.AIState.ATTACK]
	return DamageFormula.is_backstab(-target.global_basis.z,
			_player.global_position - target.global_position, tuning.backstab_arc_deg, aware)


## Weak point hit on the ground plane: the shot line passes through the core's circle before it
## would leave the body. Cores sit on the monster's front, so shots from behind hit the body.
func _weak_point_on_line(monster: Monster, origin: Vector3, direction: Vector3,
		body_distance: float) -> MonsterWeakPoint:
	var flat_dir := Vector3(direction.x, 0.0, direction.z).normalized()
	for child in monster.get_children():
		var weak := child as MonsterWeakPoint
		if weak == null:
			continue
		var to_core := weak.global_position - origin
		to_core.y = 0.0
		var along := to_core.dot(flat_dir)
		var radius := _weak_point_radius(weak)
		if along > 0.0 and (to_core - flat_dir * along).length() <= radius \
				and along <= body_distance + radius:
			return weak
	return null


func _weak_point_radius(weak: MonsterWeakPoint) -> float:
	for child in weak.get_children():
		if child is CollisionShape3D and child.shape is SphereShape3D:
			return child.shape.radius * weak.global_basis.get_scale().x
	return DEFAULT_WEAK_POINT_RADIUS


## The collider itself or its nearest ancestor with take_damage(), never the player.
func _damage_target(node: Node) -> Node:
	while node != null and not node is Player:
		if node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null


func _weapon_value(stats: Dictionary, key: String, fallback: Variant) -> Variant:
	return tuning.weapon_value(StringName(stats.get("def_id", &"")),
			int(stats.get("combat_class", -1)), key, fallback)


func _emit_noise(stats: Dictionary) -> void:
	var noise := _player.get_node_or_null(^"Noise") as NoiseEmitter
	var action: StringName = _weapon_value(stats, "noise_action", &"")
	if noise != null and action != &"":
		noise.emit(action)


func _emit_ammo() -> void:
	ammo_changed.emit(ammo_in_magazine(), ammo_reserve())


func _is_moving() -> bool:
	return Vector2(_player.velocity.x, _player.velocity.z).length() > tuning.moving_speed_threshold


func _other_slot() -> Enums.EquipSlot:
	return Enums.EquipSlot.SUB if active_slot == Enums.EquipSlot.MAIN else Enums.EquipSlot.MAIN


func _switch_to_any() -> void:
	if not switch_to(Enums.EquipSlot.MAIN):
		switch_to(Enums.EquipSlot.SUB)


func _reset_weapon_state() -> void:
	is_reloading = false
	combo_step = 0
	_bloom = 0.0
	_attack_buffered = false
	_set_blocking(false)
	weapon_changed.emit(active_slot, current_uid())
	_emit_ammo()


func _on_equipment_changed(changed_owner: StringName, slot: Enums.EquipSlot) -> void:
	if changed_owner != owner_id or slot != active_slot:
		return
	if current_uid() == &"" and (switch_to(_other_slot())):
		return
	_reset_weapon_state()
