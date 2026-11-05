class_name LootTable
extends Resource
## Weighted list of what a container can hold (B-08). Values live in data/loot/tables/.
## Design: docs/design/11-economy.md "데이터 정의" LootTable (id, region_id, container_type, entries).
## roll_min/roll_max (how many slots one container gets) are not in the design table yet.

@export var id: StringName = &""
@export var region_id: StringName = &""
@export var container_type: LootSpot.ContainerType = LootSpot.ContainerType.DRAWER
## Number of slots one container gets, picked uniformly in [roll_min, roll_max].
@export_range(0, 20) var roll_min: int = 1
@export_range(0, 20) var roll_max: int = 1
@export var entries: Array[LootEntry] = []

@export_group("Gear")
## Chance of one more slot holding a piece of equipment (design 05 "등급" 주로 얻는 곳).
@export_range(0.0, 1.0) var gear_chance: float = 0.0
## Weight per Enums.Rarity index (COMMON, UNCOMMON, RARE, EPIC, LEGENDARY).
@export var gear_rarity_weights: Array[float] = [1.0]
## Equipment def ids from data/items. One is picked whose rarity_min allows the rolled rarity.
@export var gear_pool: Array[StringName] = []

@export_group("Blueprint")
## Chance of one more slot holding a weapon or armour blueprint the player does not know yet.
## Taking it learns it at once (user decision 2026-11-06: no bag space, kept when downed).
@export_range(0.0, 1.0) var blueprint_chance: float = 0.0

## item_id of a blueprint slot. The slot also has "blueprint" (GameState flag) and "output_id".
const BLUEPRINT_ITEM := &"blueprint"


## Returns one container's contents: [{"item_id": StringName, "count": int}, ...].
## Each roll is one slot, so the same item can appear in two slots.
## Gear slots add "rarity" (item_id is the def id), blueprint slots add "blueprint" and "output_id".
## Tables without gear or blueprints draw the same random numbers as before.
func roll(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var weights := PackedFloat32Array()
	for entry in entries:
		weights.append(entry.weight)
	for i in (0 if entries.is_empty() else rng.randi_range(roll_min, roll_max)):
		var picked := rng.rand_weighted(weights)
		if picked < 0:
			break
		var entry := entries[picked]
		result.append({
			"item_id": entry.item_id,
			"count": rng.randi_range(entry.min_count, maxi(entry.min_count, entry.max_count)),
		})
	if gear_chance > 0.0 and rng.randf() < gear_chance:
		var rarity := rng.rand_weighted(PackedFloat32Array(gear_rarity_weights))
		var def_id := MonsterDrops.pick_gear(gear_pool, rarity, rng)
		if rarity >= 0 and def_id != &"":
			result.append({"item_id": def_id, "count": 1, "rarity": rarity})
	if blueprint_chance > 0.0 and rng.randf() < blueprint_chance:
		var unknown := unknown_blueprints()
		if not unknown.is_empty():
			var pick: Dictionary = unknown[rng.randi_range(0, unknown.size() - 1)]
			result.append({"item_id": BLUEPRINT_ITEM, "count": 1, "blueprint": pick.flag,
				"output_id": pick.output_id})
	return result


## Blueprint-gated recipes whose blueprint is not learned yet: [{"flag", "output_id"}], one per flag.
static func unknown_blueprints() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for recipe_id in Armory.list_recipes():
		var recipe := Armory.get_recipe(recipe_id)
		if recipe == null or not recipe.blueprint_required:
			continue
		var flag := Armory.blueprint_flag(recipe_id)
		if seen.has(flag) or GameState.has_flag(flag):
			continue
		seen[flag] = true
		out.append({"flag": flag, "output_id": recipe.output_id})
	return out
