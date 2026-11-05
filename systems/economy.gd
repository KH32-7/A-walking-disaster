extends Node
## Autoload `Economy`. Owner: Lane A (task A-06).
## Base storage of bulk resources (wood, stone, scrap, food, parts, essences ...).
## Equipment instances live in `Armory`, not here.
## Design reference: docs/design/11-economy.md

## resource_id -> amount
var amounts: Dictionary = {}
var storage_cap: int = 200


func _ready() -> void:
	SaveSystem.register_provider(&"economy", self)


func get_amount(resource_id: StringName) -> int:
	return int(amounts.get(resource_id, 0))


func can_afford(cost: Dictionary) -> bool:
	for id: StringName in cost:
		if get_amount(id) < int(cost[id]):
			return false
	return true


## Positive values add, negative values spend. Returns false (and changes nothing)
## if any amount would drop below zero. Cap handling: TODO(A-06).
func apply(changes: Dictionary) -> bool:
	for id: StringName in changes:
		if get_amount(id) + int(changes[id]) < 0:
			return false
	for id: StringName in changes:
		amounts[id] = get_amount(id) + int(changes[id])
	EventBus.resources_changed.emit(changes)
	return true


func save_data() -> Dictionary:
	return {"amounts": amounts, "storage_cap": storage_cap}


func load_data(data: Dictionary) -> void:
	amounts = data.get("amounts", {})
	storage_cap = int(data.get("storage_cap", 200))
