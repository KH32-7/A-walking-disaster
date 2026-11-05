class_name LootContainerDef
extends Resource
## How one kind of loot container behaves (B-08). Values live in data/loot/containers/.
## Design: docs/design/02-field.md "루팅" table and "데이터 정의"
## LootContainer (type, loot_table_id, open_sec, locked, noise_on_force).
## key_item_id is not in the design table yet: which bag item opens the lock quietly.

@export var type: LootSpot.ContainerType = LootSpot.ContainerType.DRAWER
## Fallback table when neither the LootSpot nor the region picks one. Usually empty.
@export var loot_table_id: StringName = &""
@export_range(0.0, 30.0, 0.1) var open_sec: float = 1.5
@export var locked: bool = false
## Noise radius (m) when a locked container is forced open without a key.
@export_range(0.0, 50.0, 0.5) var noise_on_force: float = 0.0
## Bag item that opens the lock without noise (used up on open). Empty = no key works.
@export var key_item_id: StringName = &""
