class_name RescuePowerSwitch
extends StaticBody3D
## Power switch for TRAPPED rescues (B-10, 02 "갇힘: 전력 복구"). Put one in a layout with a
## collision shape. Player.interact() (layer 7) turns it on once; every trapped target whose
## RescueSpot has `spot_tag` gets out.

signal power_restored()

@export var spot_tag: StringName = &"elevator"

var is_on := false


func _ready() -> void:
	collision_layer = 1 << (Enums.LAYER_INTERACTABLE - 1)
	collision_mask = 0


func begin_open(_interactor: Node3D) -> bool:
	if is_on:
		return false
	is_on = true
	collision_layer = 0
	for node in get_tree().get_nodes_in_group(RescueTarget.GROUP):
		var t := node as RescueTarget
		if t != null and t.spot_tags.has(spot_tag):
			t.restore_power()
	power_restored.emit()
	return true
