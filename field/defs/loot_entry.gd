class_name LootEntry
extends Resource
## One weighted line of a LootTable (B-08).
## Design: docs/design/11-economy.md "데이터 정의" LootTable.entries[{item, weight, min, max}].
## `min`/`max` are named min_count/max_count here because min()/max() are GDScript builtins.

## Item id from Lane A's data/items (lowercase snake case).
@export var item_id: StringName = &""
## Relative chance against the other entries of the same table. 0 = never.
@export_range(0.0, 1000.0, 0.1) var weight: float = 1.0
@export_range(1, 999) var min_count: int = 1
@export_range(1, 999) var max_count: int = 1
