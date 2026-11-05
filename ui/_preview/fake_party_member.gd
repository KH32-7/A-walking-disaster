extends Node3D
## Preview stand-in for a party member (B-17 companion / B-10 rescued): only what the map reads.

var display_name := ""
var party_id: StringName = &""
var party_kind: StringName = &"companion"


func _ready() -> void:
	add_to_group(&"escorts")
