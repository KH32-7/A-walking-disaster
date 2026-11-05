class_name MagicRules
extends RefCounted
## Magic weapon numbers and pure rules (B-15). No nodes: tests call these directly.
## The weapon's magic comes only from Armory.get_item_stats(): `element`, `essence_effects`
## ([{element, essence_ids, grade, mult, params}]) and `combo` ({id, name, elements, proc_rate,
## trigger, params} or null). EssenceRules (A-10) already merged two of the same element (x1.5)
## and picked the combo chance, so nothing here multiplies them again.
## The element factor (weakness 1.5 / resist 0.75) is NOT applied here: WeaponHolder puts
## stats.element in the hit info and Monster.take_damage() multiplies Enums.element_multiplier once.
## Numbers are 가안 (docs/design/06-magic-essence.md "마력과 정수 해방"); the ones the design does
## not give are marked.

## Mana gauge per magic weapon (0..MANA_MAX), this sortie only.
const MANA_MAX := 100.0
## Per attack that hit something (a shotgun blast or a swing through three monsters is one hit).
const MANA_MELEE_HIT := 5.0
const MANA_SHOT_HIT := 3.0
const MANA_KILL := 10.0
## NoiseTable action of the release (15 m).
const RELEASE_NOISE := &"essence_release"
## Essence release per class (06 "정수 해방").
## GUN: the next `shots` shots fire every essence effect at 100%.
## BLADE: `hits` hits on every monster within `radius`, one every `interval_sec` (가안, not in 06),
##   each at weapon damage x `damage_mult` (가안).
## BLUNT: one hit within `radius` at weapon damage x `damage_mult` (가안) + stagger `stagger_sec`.
const RELEASE := {
	Enums.CombatClass.GUN: {"shots": 5},
	Enums.CombatClass.BLADE: {"radius": 3.0, "hits": 4, "interval_sec": 0.3, "damage_mult": 1.0},
	Enums.CombatClass.BLUNT: {"radius": 5.0, "damage_mult": 1.5, "stagger_sec": 2.0},
}


## True when the weapon has an essence engraved (its attack element is not NONE).
static func is_magic(stats: Dictionary) -> bool:
	return int(stats.get("element", Enums.Element.NONE)) != Enums.Element.NONE


## Gauge after one step's gains, capped at MANA_MAX.
static func add_mana(gauge: float, is_gun: bool, hit: bool, kills: int) -> float:
	var gain := (MANA_SHOT_HIT if is_gun else MANA_MELEE_HIT) if hit else 0.0
	return minf(gauge + gain + MANA_KILL * kills, MANA_MAX)


## Params of the engraved effect of `element`, or {} when the weapon has none.
static func effect_params(effects: Array, element: Enums.Element) -> Dictionary:
	for effect: Dictionary in effects:
		if int(effect.get("element", Enums.Element.NONE)) == element:
			return effect.get("params", {})
	return {}


## True with probability `chance`. `roll` returns a float in [0, 1). Forced = always.
static func procs(chance: float, roll: Callable, forced: bool = false) -> bool:
	return forced or (chance > 0.0 and float(roll.call()) < chance)


## StatusHolder entries one hit adds from the essence effects (06 "정수" table):
## GREEN bind (root_chance, root_sec), STONE armor break (guard_break_chance),
## WATER slow (slow_ratio for slow_sec) + wet (wet_sec) on slow_chance. LIGHT chains after the hit.
## forced = gun release: every chance is 100%.
static func hit_statuses(effects: Array, roll: Callable, forced: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for effect: Dictionary in effects:
		var p: Dictionary = effect.get("params", {})
		match int(effect.get("element", Enums.Element.NONE)):
			Enums.Element.GREEN:
				if procs(float(p.get("root_chance", 0.0)), roll, forced):
					out.append({"id": &"bind", "duration": float(p.get("root_sec", 1.0))})
			Enums.Element.STONE:
				if procs(float(p.get("guard_break_chance", 0.0)), roll, forced):
					out.append({"id": &"armor_break"})
			Enums.Element.WATER:
				if procs(float(p.get("slow_chance", 0.0)), roll, forced):
					out.append(slow_entry(float(p.get("slow_ratio", 0.0)), float(p.get("slow_sec", 2.0))))
					out.append({"id": &"wet", "duration": float(p.get("wet_sec", 2.0))})
	return out


## STONE "경직 시간 증가": copies of `statuses` with every stagger lasting x(1 + bonus).
static func extend_stagger(statuses: Array, bonus: float) -> Array:
	var out: Array = []
	for entry: Dictionary in statuses:
		var copy := entry.duplicate()
		if bonus > 0.0 and copy.get("id", &"") == &"stagger":
			var def := StatusHolder.get_def(&"stagger")
			copy["duration"] = float(copy.get("duration", def.duration_sec)) * (1.0 + bonus)
		out.append(copy)
	return out


## Statuses a "hit" combo puts on the target it procs on. Mud: armor break + slow together.
## Thorn bush and swamp leave a MagicZone instead; shock puddle boosts the chain.
static func combo_statuses(combo: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p: Dictionary = combo.get("params", {})
	if combo.get("id", &"") == &"mud":
		var sec := float(p.get("duration_sec", 3.0))
		if p.get("guard_break", false):
			out.append({"id": &"armor_break", "duration": sec})
		out.append(slow_entry(float(p.get("slow_ratio", 0.0)), sec))
	return out


## Slow entry with the essence's own ratio: "move_mult" overrides the slow def (StatusHolder).
static func slow_entry(ratio: float, sec: float) -> Dictionary:
	return {"id": &"slow", "duration": sec, "move_mult": clampf(1.0 - ratio, 0.0, 1.0)}


## Up to `count` of `candidates` (Node3D) within `max_range` of `center`, nearest first.
static func nearest(center: Vector3, candidates: Array, count: int, max_range: float) -> Array:
	var near: Array = candidates.filter(func(n: Node3D) -> bool:
		return n.global_position.distance_to(center) <= max_range)
	near.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	return near.slice(0, maxi(count, 0))
