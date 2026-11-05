extends Node
## Autoload `Colony`. Owner: Lane C.
## Residents, buildings, relationships, raids threat - everything that lives in the base.
## Other lanes read through the getters below; they never edit resident data directly.
## Design reference: docs/design/07-residents.md .. 10-raids-defense.md

## resident_id -> Dictionary (fields: docs/design/07-residents.md "데이터 정의")
var residents: Dictionary = {}
var threat: int = 0
var tier: Enums.BaseTier = Enums.BaseTier.CAMP


func _ready() -> void:
	SaveSystem.register_provider(&"colony", self)


func get_resident(resident_id: StringName) -> Dictionary:
	return residents.get(resident_id, {})


func active_resident_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in residents:
		if residents[id].get("status", Enums.ResidentStatus.ACTIVE) == Enums.ResidentStatus.ACTIVE:
			ids.append(id)
	return ids


## Base noise level that feeds the raid threat (docs/design/09-base-building.md).
func base_noise() -> float:
	# TODO(C-xx)
	return 0.0


func save_data() -> Dictionary:
	return {"residents": residents, "threat": threat, "tier": tier}


func load_data(data: Dictionary) -> void:
	residents = data.get("residents", {})
	threat = int(data.get("threat", 0))
	tier = int(data.get("tier", Enums.BaseTier.CAMP)) as Enums.BaseTier
