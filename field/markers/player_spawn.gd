@tool
class_name PlayerSpawn
extends FieldMarker
## Region entry point (1~2 per map). Faces local -Z, the arrow in the editor.

const GROUP := &"field_player_spawns"

@export var spawn_id: StringName = &"main":
	set(value):
		spawn_id = value
		_refresh()


func _marker_group() -> StringName:
	return GROUP


func _gizmo_color() -> Color:
	return Color(0.3, 0.9, 0.4)


func _gizmo_label() -> String:
	return "PlayerSpawn %s" % spawn_id


func _build_gizmo() -> void:
	_add_cylinder(0.4, 1.8)
	_add_polyline(PackedVector3Array([
		Vector3(0.0, 0.05, 0.0), Vector3(0.0, 0.05, -1.5),
		Vector3(-0.4, 0.05, -1.1), Vector3(0.0, 0.05, -1.5), Vector3(0.4, 0.05, -1.1),
	]))


func _marker_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if spawn_id == &"":
		warnings.append("spawn_id is empty.")
	return warnings
