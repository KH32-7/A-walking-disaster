extends Node
## Autoload `SaveSystem`. Owner: Lane A (task A-04).
## Each lane registers ONE provider for its own state instead of the save system
## reaching into other lanes:
##     SaveSystem.register_provider(&"colony", Colony)
## A provider is any object with `save_data() -> Dictionary` and `load_data(Dictionary)`.
## Values must be JSON-safe (no Objects, no Resources - store ids).

const SAVE_DIR := "user://saves"
const SLOT_COUNT := 3

var _providers: Dictionary = {}


func _ready() -> void:
	register_provider(&"game", GameState)


func register_provider(key: StringName, provider: Object) -> void:
	assert(provider.has_method("save_data") and provider.has_method("load_data"),
		"Save provider %s must implement save_data() and load_data()" % key)
	_providers[key] = provider


func save_slot(slot: int) -> void:
	# TODO(A-04): write every provider's data to SAVE_DIR/slot_<n>.json, with a version field.
	pass


func load_slot(slot: int) -> bool:
	# TODO(A-04): read the file and call load_data() on each registered provider.
	return false
