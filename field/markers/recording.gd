@tool
class_name Recording
extends FieldMarker
## Left-behind recorder (collectible). Speaker and text live in the recording
## data; the marker only says which one sits here.
## Design reference: docs/design/13-world-narrative.md "남겨진 녹음"

const GROUP := &"field_recordings"

@export var recording_id: StringName = &"":
	set(value):
		recording_id = value
		_refresh()


func _marker_group() -> StringName:
	return GROUP


func _gizmo_color() -> Color:
	return Color(0.95, 0.95, 0.95)


func _gizmo_label() -> String:
	return "Recording %s" % recording_id


func _build_gizmo() -> void:
	_add_box(Vector3(0.3, 0.2, 0.2))


func _marker_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if recording_id == &"":
		warnings.append("recording_id is empty.")
	return warnings
