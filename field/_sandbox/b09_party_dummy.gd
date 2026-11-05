extends Node3D
## Sandbox / test stand-in for a party member (B-09) until B-10 rescued people and B-17
## companions exist. Shows the shape ExtractionManager reads: group PARTY_GROUP plus
## party_id, display_name, party_kind.

@export var party_id: StringName = &""
@export var display_name := ""
@export var party_kind: StringName = ExtractionManager.KIND_COMPANION


func _ready() -> void:
	add_to_group(ExtractionManager.PARTY_GROUP)
