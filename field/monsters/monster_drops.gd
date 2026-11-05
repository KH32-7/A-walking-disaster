class_name MonsterDrops
extends RefCounted
## Monster kill drops (B-18): essence of the monster's family, family material and gear.
## A kill leaves a MonsterDropPile where the monster died; the player picks it up with interact.
## Design: docs/design/04-monsters.md "드롭", 11-economy.md "계열 재료".

const TABLE_DIR := "res://data/loot/drops/"
const PILE_SCENE := preload("res://field/loot/monster_drop_pile.tscn")
## Elites always use this table, whatever their def says (04 "드롭" 정예 row).
const ELITE_TABLE_ID := &"monster_elite"
const ELEMENT_KEYS := {
	Enums.Element.GREEN: "green", Enums.Element.STONE: "stone",
	Enums.Element.WATER: "water", Enums.Element.LIGHT: "light",
}
const GRADE_KEYS := ["low", "mid", "high"]
## 11 "계열 재료 4종": Lane A's data/resources ids.
const MATERIALS := {
	Enums.Element.GREEN: &"vine_fiber", Enums.Element.STONE: &"stone_shard",
	Enums.Element.WATER: &"water_moss", Enums.Element.LIGHT: &"neon_dust",
}


## contracts.md "아이템 id 규칙": essence_<element>_<grade>, for example essence_green_low.
static func essence_id(element: Enums.Element, grade: Enums.EssenceGrade) -> StringName:
	if not ELEMENT_KEYS.has(element):
		return &""
	return StringName("essence_%s_%s" % [ELEMENT_KEYS[element], GRADE_KEYS[grade]])


static func material_id(element: Enums.Element) -> StringName:
	return MATERIALS.get(element, &"")


static func table(table_id: StringName) -> MonsterDropTable:
	if table_id == &"":
		return null
	var path := TABLE_DIR + String(table_id) + ".tres"
	return load(path) as MonsterDropTable if ResourceLoader.exists(path) else null


## The table a monster drops from: the elite table for elites, else def.drop_table_id.
static func table_for(monster: Monster) -> MonsterDropTable:
	return table(ELITE_TABLE_ID if monster.elite else monster.def.drop_table_id)


## One kill's drops: {"resources": {id: n}, "gear": [{"def_id": StringName, "rarity": int}]}.
static func roll(drop_table: MonsterDropTable, family: Enums.Element, mult: float,
		rng: RandomNumberGenerator) -> Dictionary:
	var out := {"resources": {}, "gear": []}
	if drop_table == null or mult <= 0.0:
		return out
	var essence := _count(drop_table.essence_chance, mult, drop_table.essence_min, drop_table.essence_max, rng)
	var essence_key := essence_id(family, drop_table.essence_grade)
	if essence > 0 and essence_key != &"":
		out.resources[essence_key] = essence
	var material := _count(drop_table.material_chance, mult, drop_table.material_min, drop_table.material_max, rng)
	var material_key := material_id(family)
	if material > 0 and material_key != &"":
		out.resources[material_key] = material
	for i in _hits(drop_table.gear_chance, mult, rng):
		var rarity := rng.rand_weighted(PackedFloat32Array(drop_table.gear_rarity_weights))
		var def_id := _pick_gear(drop_table.gear_pool, rarity, rng)
		if rarity >= 0 and def_id != &"":
			out.gear.append({"def_id": def_id, "rarity": rarity})
	return out


## Rolls a dead monster's drops and leaves a pile where it died. Returns the pile, or null
## when nothing dropped. Called by Monster._die().
static func drop_for(monster: Monster, rng: RandomNumberGenerator = null) -> MonsterDropPile:
	var parent := monster.get_parent()
	if parent == null:
		return null
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var drops := roll(table_for(monster), monster.def.family, monster.drop_mult, rng)
	if drops.resources.is_empty() and drops.gear.is_empty():
		return null
	var pile := PILE_SCENE.instantiate() as MonsterDropPile
	pile.resources = drops.resources
	pile.gear.assign(drops.gear)
	pile.monster_id = monster.def.id
	var at := monster.global_position
	pile.position = (parent as Node3D).to_local(at) if parent is Node3D else at
	# Deferred: death can happen inside a physics callback (melee hitbox).
	parent.add_child.call_deferred(pile, true)
	return pile


## How many of one line: 0 on a miss, else min..max plus one per extra hit.
static func _count(chance: float, mult: float, lo: int, hi: int, rng: RandomNumberGenerator) -> int:
	var hits := _hits(chance, mult, rng)
	if hits <= 0:
		return 0
	return rng.randi_range(lo, maxi(lo, hi)) + hits - 1


## chance x mult rounded at random: 0.39 -> 0 or 1, 1.3 -> 1 or 2.
static func _hits(chance: float, mult: float, rng: RandomNumberGenerator) -> int:
	var p := maxf(chance * mult, 0.0)
	var hits := floori(p)
	if rng.randf() < p - hits:
		hits += 1
	return hits


static func _pick_gear(pool: Array[StringName], rarity: int, rng: RandomNumberGenerator) -> StringName:
	var fits: Array[StringName] = []
	for def_id in pool:
		var def := Armory.get_def(def_id)
		if def and def.rarity_min <= rarity:
			fits.append(def_id)
	if fits.is_empty():
		return &""
	return fits[rng.randi_range(0, fits.size() - 1)]
