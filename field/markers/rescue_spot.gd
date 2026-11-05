@tool
class_name RescueSpot
extends FieldMarker
## Where a rescue target can appear. B-10 matches a RescueSpawn's spawn_tags
## against these tags.

const GROUP := &"field_rescue_spots"

@export var spawn_tags: Array[StringName] = []:
	set(value):
		spawn_tags = value
		_refresh()


func _marker_group() -> StringName:
	return GROUP


func _gizmo_color() -> Color:
	return Color(1.0, 0.5, 0.8)


func _gizmo_label() -> String:
	return "RescueSpot %s" % ", ".join(PackedStringArray(spawn_tags))


func _build_gizmo() -> void:
	_add_cylinder(0.35, 1.6)
	_add_ring(1.0)


func _marker_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if spawn_tags.is_empty():
		warnings.append("spawn_tags is empty. Any rescue target can appear here.")
	return warnings
