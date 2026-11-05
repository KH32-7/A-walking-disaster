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
## Low chance of one finished weapon (사용자 요청 2026-11-06), on top of the slots: 0..1 per container.
## The weapon is picked evenly from gear_pool (ItemDef ids); its grade is rolled by Armory.
@export_range(0.0, 1.0) var gear_chance: float = 0.0
@export var gear_pool: Array[StringName] = []


## A weapon def id to add to this container, or &"" (no luck / no pool).
func roll_gear(rng: RandomNumberGenerator) -> StringName:
	if gear_pool.is_empty() or rng.randf() >= gear_chance:
		return &""
	return gear_pool[rng.randi_range(0, gear_pool.size() - 1)]


## Returns one container's contents: [{"item_id": StringName, "count": int}, ...].
## Each roll is one slot, so the same item can appear in two slots.
func roll(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var weights := PackedFloat32Array()
	for entry in entries:
		weights.append(entry.weight)
	if entries.is_empty():
		return result
	for i in rng.randi_range(roll_min, roll_max):
		var picked := rng.rand_weighted(weights)
		if picked < 0:
			break
		var entry := entries[picked]
		result.append({
			"item_id": entry.item_id,
			"count": rng.randi_range(entry.min_count, maxi(entry.min_count, entry.max_count)),
		})
	return result
