class_name Affix
extends Resource
## A random bonus line rolled onto an item instance by rarity. Owner: Lane A (task A-07).
## Data: data/items/affixes/<id>.tres. Design reference: docs/design/05-gear.md "부가 옵션 후보".
## The rolled value is an integer between min_value and max_value (both inclusive).

@export var id: StringName
## Display text for Lane D, `%d` is replaced by the rolled value.
@export var label: String
## Key added to Armory.get_item_stats(), e.g. attack_pct, noise_m, max_hp.
@export var stat: StringName
@export var min_value := 0
@export var max_value := 0
## Enums.EquipSlot values this affix may roll on.
@export var allowed_slots: Array[int] = []
