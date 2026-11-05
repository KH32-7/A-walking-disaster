class_name MagicWeapon
extends Node
## Magic weapon runtime (B-15): essence effects, combos, mana gauge and essence release (X).
## Created by Player (`MagicWeapon.attach(self)`, child "Magic") AFTER ClassSkills, because it wraps
## the hit filter ClassSkills set. Everything comes from Armory.get_item_stats() of the weapon in hand.
##
## Hooks on the player's WeaponHolder ("Weapons"), no changes to it:
## - hit_filter (wraps ClassSkills.filter_hit): adds the essence and "hit" combo statuses to
##   info["status"] (the monster applies them in take_damage) and stretches stagger (STONE).
## - hit_landed: lifesteal (GREEN, of the damage the monster really took), chain (LIGHT),
##   combo zones and shock puddle, "kill" combos, mana.
## - attacked: mana for the attack that hit, gun release shots counted down.
## Extra damage from chains and shard burst goes straight to Monster.take_damage with
## info["magic"] = id, so it never procs effects or mana again.
## Element factor: Monster.take_damage multiplies Enums.element_multiplier once (see MagicRules).
## Lane D: Fx ids essence_chain {to}, essence_combo {id, radius[, duration]},
## essence_release {element, combat_class, radius}; Audio essence_release. Statuses show through
## StatusHolder signals. HUD `mana` = PlayerHudState via hud_mana().
## Design reference: docs/design/06-magic-essence.md

## Essence release used (Lane D: cast effect). combat_class = the weapon's family.
signal released(combat_class: int, element: Enums.Element)

const NODE_NAME := &"Magic"
const NODE_PATH := ^"Magic"

## Returns a float in [0, 1) for each proc roll. Tests replace it to force or block procs.
var roll: Callable

var _player: Player
var _holder: WeaponHolder
var _prev_filter: Callable
var _rng := RandomNumberGenerator.new()
## item uid -> gauge (0..MagicRules.MANA_MAX), this sortie.
var _gauge: Dictionary = {}
## Gains waiting for the attack to finish: {"uid", "gun", "hit", "kills"}.
var _pending: Dictionary = {}
## The hit between hit_filter and hit_landed: {"monster", "hp_before", "stats", "combo_hit", "forced"}.
var _hit: Dictionary = {}
## Gun release: shots left that fire every effect at 100%.
var _charged_shots := 0
## Blade release: hits left, time to the next, damage mult.
var _storm_hits := 0
var _storm_left := 0.0


## Creates the runtime as a child of `player`. Call it from the player's @onready, after ClassSkills.
static func attach(player: Player) -> MagicWeapon:
	var magic := MagicWeapon.new()
	magic.name = NODE_NAME
	player.add_child(magic)
	return magic


## HUD `mana` (issue #28): the weapon in hand's gauge, 0..1. 0 for a normal weapon.
static func hud_mana(player: Node) -> float:
	var magic := player.get_node_or_null(NODE_PATH) as MagicWeapon
	return magic.mana_ratio() if magic != null else 0.0


func _ready() -> void:
	_player = get_parent() as Player
	_holder = _player.get_node_or_null(^"Weapons") as WeaponHolder if _player else null
	if _holder == null:
		push_error("MagicWeapon must be a child of a Player with a Weapons node")
		set_physics_process(false)
		return
	_rng.randomize()
	roll = _rng.randf
	_prev_filter = _holder.hit_filter
	_holder.hit_filter = filter_hit
	_holder.hit_landed.connect(_on_hit_landed)
	_holder.attacked.connect(_on_attacked)
	_holder.weapon_changed.connect(func(_slot: Enums.EquipSlot, _uid: StringName) -> void: _stop_storm())
	_player.downed.connect(_on_downed)
	EventBus.sortie_started.connect(func(_loadout: Dictionary) -> void: reset())
	EventBus.sortie_ended.connect(func(_result: Dictionary) -> void: reset())


func _physics_process(delta: float) -> void:
	if _player.is_downed:
		return
	step(delta, {"release": Input.is_action_just_pressed(&"essence_release")})


## One step. Split from input reading so tests can drive it. input: {"release": bool}
func step(delta: float, input: Dictionary) -> void:
	_flush_mana()
	if input.get("release", false):
		release()
	_step_storm(delta)


# --- Public ---------------------------------------------------------------

## Gauge of `uid` (default: the weapon in hand), 0..MagicRules.MANA_MAX.
func mana(uid: StringName = &"") -> float:
	return float(_gauge.get(uid if uid != &"" else _holder.current_uid(), 0.0))


## Debug console and tests: sets the gauge of the weapon in hand.
func set_mana(value: float) -> void:
	var uid := _holder.current_uid()
	if uid != &"":
		_gauge[uid] = clampf(value, 0.0, MagicRules.MANA_MAX)


func mana_ratio() -> float:
	if not MagicRules.is_magic(_holder.current_stats()):
		return 0.0
	return mana() / MagicRules.MANA_MAX


## Gun release: shots left that fire every effect at 100%.
func charged_shots() -> int:
	return _charged_shots


func can_release() -> bool:
	var stats := _holder.current_stats()
	return MagicRules.is_magic(stats) and mana() >= MagicRules.MANA_MAX and _storm_hits <= 0 \
			and not _player.is_downed and _player.status.can_act() and _holder.can_act() \
			and _holder.usable(stats)


## Essence release (X) with the weapon in hand. Empties its gauge. False when not ready.
func release() -> bool:
	if not can_release():
		return false
	var stats := _holder.current_stats()
	var family := int(stats.get("combat_class", -1))
	var element: Enums.Element = stats["element"]
	var rule: Dictionary = MagicRules.RELEASE.get(family, {})
	_gauge[_holder.current_uid()] = 0.0
	var noise := _player.get_node_or_null(^"Noise") as NoiseEmitter
	if noise != null:
		noise.emit(MagicRules.RELEASE_NOISE)
	Audio.play(&"essence_release", _player.global_position)
	Fx.spawn(&"essence_release", _player.global_position,
			{"element": element, "combat_class": family, "radius": float(rule.get("radius", 0.0))})
	CombatFeel.shake(_player, CombatFeel.SHAKE_RELEASE)
	match family:
		Enums.CombatClass.GUN:
			_charged_shots = int(rule["shots"])
		Enums.CombatClass.BLADE:
			_storm_hits = int(rule["hits"])
			_storm_left = 0.0
		Enums.CombatClass.BLUNT:
			_release_hit(rule, [{"id": &"stagger", "duration": float(rule["stagger_sec"])}])
	released.emit(family, element)
	return true


## New sortie or sortie over: every gauge back to 0, release effects stop.
func reset() -> void:
	_gauge.clear()
	_pending.clear()
	_charged_shots = 0
	_stop_storm()


## WeaponHolder.hit_filter: (target, amount, info) -> amount. Adds essence statuses to the hit.
func filter_hit(target: Node, amount: float, info: Dictionary) -> float:
	if _prev_filter.is_valid():
		amount = _prev_filter.call(target, amount, info)
	_hit = {}
	var stats := _holder.current_stats()
	if not MagicRules.is_magic(stats):
		return amount
	var effects: Array = stats.get("essence_effects", [])
	var forced := _charged_shots > 0 and WeaponHolder.is_gun(stats)
	var stone := MagicRules.effect_params(effects, Enums.Element.STONE)
	var statuses := MagicRules.extend_stagger(info.get("status", []),
			float(stone.get("stagger_bonus", 0.0)))
	statuses.append_array(MagicRules.hit_statuses(effects, roll, forced))
	var combo: Variant = stats.get("combo")
	var combo_hit: bool = combo != null and combo.get("trigger", &"hit") == &"hit" \
			and MagicRules.procs(float(combo.get("proc_rate", 0.0)), roll)
	if combo_hit:
		statuses.append_array(MagicRules.combo_statuses(combo))
	if not statuses.is_empty():
		info["status"] = statuses
	var monster := SkillTargets.monster_of(target)
	_hit = {"monster": monster, "hp_before": monster.hp if monster else 0.0, "stats": stats,
		"combo_hit": combo_hit, "forced": forced}
	return amount


# --- Internals ------------------------------------------------------------

func _on_hit_landed(_target: Node, amount: float, info: Dictionary) -> void:
	var hit := _hit
	_hit = {}
	if hit.is_empty():
		return
	var stats: Dictionary = hit["stats"]
	var effects: Array = stats.get("essence_effects", [])
	var monster: Monster = hit["monster"]
	var killed := monster != null and monster.is_dead()
	if monster != null:
		var dealt: float = hit["hp_before"] - maxf(monster.hp, 0.0)
		var green := MagicRules.effect_params(effects, Enums.Element.GREEN)
		if dealt > 0.0 and not green.is_empty():
			_heal(_player, dealt * float(green.get("lifesteal_ratio", 0.0)))
		_light_chain(monster, amount, effects, stats.get("combo"), hit)
		_combo_after(monster, amount, stats, hit["combo_hit"], killed)
	if info.get("release", false):
		return
	_pending["uid"] = _holder.current_uid()
	_pending["gun"] = WeaponHolder.is_gun(stats)
	_pending["hit"] = true
	_pending["kills"] = int(_pending.get("kills", 0)) + (1 if killed else 0)


## LIGHT: on chain_chance, chain_damage_ratio of the hit to the nearest chain_targets monsters within
## chain_range. Shock puddle combo on a wet target: a chain with range and damage boosted.
func _light_chain(monster: Monster, amount: float, effects: Array, combo: Variant, hit: Dictionary) -> void:
	var p := MagicRules.effect_params(effects, Enums.Element.LIGHT)
	if p.is_empty():
		return
	var chain := MagicRules.procs(float(p.get("chain_chance", 0.0)), roll, hit["forced"])
	var reach := float(p.get("chain_range", 4.0))
	var ratio := float(p.get("chain_damage_ratio", 0.0))
	if hit["combo_hit"] and combo.get("id", &"") == &"shock_puddle" and monster.status.has(&"wet"):
		var cp: Dictionary = combo.get("params", {})
		chain = true
		reach *= float(cp.get("wet_chain_range_mult", 1.0))
		ratio *= float(cp.get("wet_chain_damage_mult", 1.0))
	if not chain:
		return
	var others := SkillTargets.monsters_in_radius(_player, monster.global_position, reach)
	others.erase(monster)
	for other: Monster in MagicRules.nearest(monster.global_position, others,
			int(p.get("chain_targets", 2)), reach):
		Fx.spawn(&"essence_chain", monster.global_position, {"to": other.global_position})
		other.take_damage(amount * ratio, {"source": _player, "element": Enums.Element.LIGHT,
			"position": other.global_position, "magic": &"chain"})


## Combos after the hit: zones (thorn bush, swamp) on a hit proc; photosynthesis and shard burst
## roll on a kill. Mud and shock puddle were handled before / in the chain.
func _combo_after(monster: Monster, amount: float, stats: Dictionary, combo_hit: bool, killed: bool) -> void:
	var combo: Variant = stats.get("combo")
	if combo == null:
		return
	var p: Dictionary = combo.get("params", {})
	if combo_hit:
		MagicZone.create(_player.get_parent(), monster.global_position, combo, stats["element"])
		return
	if not killed or combo.get("trigger", &"") != &"kill" \
			or not MagicRules.procs(float(combo.get("proc_rate", 0.0)), roll):
		return
	var radius := float(p.get("radius", 0.0))
	Fx.spawn(&"essence_combo", monster.global_position, {"id": combo["id"], "radius": radius})
	match combo.get("id", &""):
		&"photosynthesis":
			for body: Node3D in _party():
				if body.global_position.distance_to(_player.global_position) <= radius:
					_heal(body, float(p.get("heal", 0.0)))
		&"shard_burst":
			var others := SkillTargets.monsters_in_radius(_player, monster.global_position, radius)
			others.erase(monster)
			for other in others:
				other.take_damage(amount * float(p.get("damage_ratio", 0.0)), {"source": _player,
					"element": stats["element"], "position": other.global_position, "magic": &"shard_burst"})


func _on_attacked(kind: StringName, _combo_step: int) -> void:
	if kind == &"shot" and _charged_shots > 0:
		_charged_shots -= 1


## Applies the gains of the last step's attacks: one hit gain per step (the game attacks at most
## once a step), plus every kill.
func _flush_mana() -> void:
	if _pending.is_empty():
		return
	var uid: StringName = _pending["uid"]
	if uid != &"":
		_gauge[uid] = MagicRules.add_mana(float(_gauge.get(uid, 0.0)), _pending["gun"],
				_pending["hit"], _pending["kills"])
	_pending.clear()


func _step_storm(delta: float) -> void:
	if _storm_hits <= 0:
		return
	_storm_left -= delta
	if _storm_left > 0.0:
		return
	var rule: Dictionary = MagicRules.RELEASE[Enums.CombatClass.BLADE]
	_storm_hits -= 1
	_storm_left += float(rule["interval_sec"])
	_release_hit(rule, [])


## One release hit on every living monster within rule.radius, through WeaponHolder.skill_hit
## (crit, mastery, class filter and essence effects as usual; no mana).
func _release_hit(rule: Dictionary, statuses: Array) -> void:
	for monster in SkillTargets.monsters_in_radius(_player, _player.global_position, float(rule["radius"])):
		var extra := {"release": true}
		if not statuses.is_empty():
			extra["status"] = statuses.duplicate(true)
		_holder.skill_hit(monster, float(rule["damage_mult"]), extra)


func _stop_storm() -> void:
	_storm_hits = 0
	_storm_left = 0.0


func _on_downed() -> void:
	_stop_storm()
	_charged_shots = 0
	_pending.clear()


## The player and party members (companions, rescued people) that are up.
func _party() -> Array[Node3D]:
	var out: Array[Node3D] = [_player]
	for node in get_tree().get_nodes_in_group(ExtractionManager.PARTY_GROUP):
		if node is Node3D:
			out.append(node)
	return out


## Health up to the body's max. Nothing for the downed.
func _heal(body: Node, amount: float) -> void:
	if amount <= 0.0:
		return
	if body is Player:
		var p := body as Player
		if not p.is_downed:
			p.health = minf(p.health + amount, p.stats.max_health)
			p.health_changed.emit(p.health, p.stats.max_health)
	elif body is FieldCompanion:
		var c := body as FieldCompanion
		if c.state == FieldCompanion.State.ACTIVE:
			c.health = minf(c.health + amount, c.max_health)
	elif body is RescueTarget:
		var r := body as RescueTarget
		if r.state != RescueTarget.State.DOWNED:
			r.health = minf(r.health + amount, r.tuning.max_health)
