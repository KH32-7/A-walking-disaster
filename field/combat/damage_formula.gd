class_name DamageFormula
extends RefCounted
## Pure combat math (B-06). No nodes, no autoloads: tests call these directly.
## 03 "피해 공식": D = A x (1 + 0.06U) x (1 + 0.03M) x P x E x C x 100 / (100 + R)
## - A x (1 + 0.06U) is Armory.get_item_stats().damage (rarity, upgrade, affixes, durability are
##   already in it). Never multiply the upgrade factor again here.
## - The attacker side computes A, M, C (+ combo, backstab, cover multipliers): attacker_damage().
## - The monster applies P, E, R in Monster.take_damage() (B-07). full() joins both for tests.


## Mastery factor (1 + per_level x M).
static func mastery_factor(mastery: int, per_level: float) -> float:
	return 1.0 + per_level * float(mastery)


## Attacker-side amount passed to take_damage(): A x (1 + 0.03M) x C x extra.
## extra = product of combo finisher, backstab and cover multipliers (1.0 when none).
static func attacker_damage(stat_damage: float, mastery: int, per_level: float,
		crit_mult: float, extra: float = 1.0) -> float:
	return maxf(stat_damage, 0.0) * mastery_factor(mastery, per_level) * crit_mult * extra


## Whole formula with the target side, for tests and previews. R uses the monster's own rule.
static func full(stat_damage: float, mastery: int, per_level: float, part_mult: float,
		element_mult: float, crit_mult: float, defense: float) -> float:
	return attacker_damage(stat_damage, mastery, per_level, crit_mult) * part_mult * element_mult \
			* MonsterRules.defense_factor(defense)


## Crit chance: base rate plus the weapon's crit affix (percentage points), clamped to 0..1.
static func crit_chance(base_rate: float, crit_pctp: float) -> float:
	return clampf(base_rate + crit_pctp / 100.0, 0.0, 1.0)


## `roll` in [0, 1). Returns the crit multiplier to use (crit_mult or 1.0).
static func crit_multiplier(roll: float, chance: float, crit_mult: float) -> float:
	return crit_mult if roll < chance else 1.0


## Full cone angle in degrees for one shot: base + bloom (bloom already capped by the caller),
## x moving_mult while moving, x aim_mult while aiming.
static func spread_deg(base_deg: float, bloom_deg: float, moving: bool, aiming: bool,
		moving_mult: float, aim_mult: float) -> float:
	var spread := base_deg + bloom_deg
	if moving:
		spread *= moving_mult
	if aiming:
		spread *= aim_mult
	return maxf(spread, 0.0)


## Bloom after one more shot, capped so base + bloom never passes cap_deg.
static func add_bloom(bloom_deg: float, per_shot: float, base_deg: float, cap_deg: float) -> float:
	return clampf(bloom_deg + per_shot, 0.0, maxf(cap_deg - base_deg, 0.0))


## True if `to_other` lies within a cone of `arc_deg` (full angle) around `forward`.
## Both are flattened to the ground plane. A zero vector counts as inside.
static func in_arc(forward: Vector3, to_other: Vector3, arc_deg: float) -> bool:
	var f := Vector3(forward.x, 0.0, forward.z)
	var t := Vector3(to_other.x, 0.0, to_other.z)
	if f.length_squared() < 0.0001 or t.length_squared() < 0.0001:
		return true
	return rad_to_deg(f.angle_to(t)) <= arc_deg * 0.5


## Backstab: attacker stands in the rear arc of the target and the target is not aware of them.
static func is_backstab(target_forward: Vector3, target_to_attacker: Vector3, rear_arc_deg: float,
		target_aware: bool) -> bool:
	return not target_aware and in_arc(-target_forward, target_to_attacker, rear_arc_deg)


## Combo step for the next swing. `since_ready` = seconds since the last swing's interval ended
## (negative = still recovering). Returns 1..hits; 1 when the window passed or the combo finished.
static func next_combo(current: int, since_ready: float, window_sec: float, hits: int) -> int:
	if current <= 0 or current >= hits or since_ready > window_sec:
		return 1
	return current + 1


## Incoming damage while blocking. Returns {"damage", "stamina_cost", "perfect"}.
## `since_block` = seconds since the block started. Perfect block = within the window: no damage,
## no stamina. Otherwise damage x block_mult and stamina = incoming x stamina_per_damage.
static func block(incoming: float, since_block: float, perfect_window: float, block_mult: float,
		stamina_per_damage: float) -> Dictionary:
	if since_block <= perfect_window:
		return {"damage": 0.0, "stamina_cost": 0.0, "perfect": true}
	return {"damage": incoming * block_mult, "stamina_cost": incoming * stamina_per_damage,
		"perfect": false}
