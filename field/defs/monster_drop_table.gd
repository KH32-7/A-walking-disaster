class_name MonsterDropTable
extends Resource
## What one monster kill can drop (B-18). One table per tier: data/loot/drops/<id>.tres.
## Essence and family material ids come from the monster's family (MonsterDrops).
## Design: docs/design/04-monsters.md "드롭", 06-magic-essence.md "얻는 양".
## A chance above 1 (night drop_mult) turns the excess into a chance of one more.

@export var id: StringName = &""

@export_group("Essence")
@export_range(0.0, 1.0) var essence_chance: float = 0.0
@export var essence_grade: Enums.EssenceGrade = Enums.EssenceGrade.LOW
@export_range(1, 99) var essence_min: int = 1
@export_range(1, 99) var essence_max: int = 1

@export_group("Family material")
@export_range(0.0, 1.0) var material_chance: float = 0.0
@export_range(1, 99) var material_min: int = 1
@export_range(1, 99) var material_max: int = 1

@export_group("Gear")
@export_range(0.0, 1.0) var gear_chance: float = 0.0
## Weight per Enums.Rarity index (COMMON, UNCOMMON, RARE, EPIC, LEGENDARY).
@export var gear_rarity_weights: Array[float] = [1.0]
## Equipment def ids from Lane A's data/items. One is picked per gear drop.
@export var gear_pool: Array[StringName] = []
