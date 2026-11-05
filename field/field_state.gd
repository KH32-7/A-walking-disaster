extends Node
## Autoload `FieldState`. Owner: Lane B.
## Persistent field-side state that survives between sorties: lost gear, region
## unlocks, boss respawn timers, the current sortie's runtime info.
## Design reference: docs/design/02-field.md

## [{"item_uid": StringName, "region_id": StringName, "position": Vector3 as Array}]
var lost_gear: Array = []
## region_id -> day the boss respawns
var boss_respawn_day: Dictionary = {}


func _ready() -> void:
	SaveSystem.register_provider(&"field", self)


## True while the player is inside a field region.
func in_sortie() -> bool:
	return GameState.phase == Enums.Phase.SORTIE


func save_data() -> Dictionary:
	return {"lost_gear": lost_gear, "boss_respawn_day": boss_respawn_day}


func load_data(data: Dictionary) -> void:
	lost_gear = data.get("lost_gear", [])
	boss_respawn_day = data.get("boss_respawn_day", {})
