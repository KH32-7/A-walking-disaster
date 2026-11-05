extends Node
## Autoload `Armory`. Owner: Lane A (tasks A-07 .. A-09).
## Owns every equipment ItemInstance (player's and residents') and who wears what.
## Lane B reads the player's equipped stats; Lane C reads residents' equipped stats.
## Design reference: docs/design/05-gear.md, 06-magic-essence.md

const PLAYER_ID := &"player"


func _ready() -> void:
	SaveSystem.register_provider(&"armory", self)


## Returns the item uid in `slot` for `owner_id` (PLAYER_ID or a resident id), or &"".
func get_equipped(owner_id: StringName, slot: Enums.EquipSlot) -> StringName:
	# TODO(A-07)
	return &""


## Final stats of an item instance after rarity, upgrade level and engravings.
## Keys: "damage", "attack_interval", "range", "noise", "defense", "element", "essence_effects" ...
func get_item_stats(item_uid: StringName) -> Dictionary:
	# TODO(A-07/A-09)
	return {}


func save_data() -> Dictionary:
	return {}


func load_data(_data: Dictionary) -> void:
	pass
