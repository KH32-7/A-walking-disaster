@tool
class_name BossArena
extends FieldMarker
## Boss arena center. B-19 spawns boss_id here; radius is the fight area.

const GROUP := &"field_boss_arenas"

@export var boss_id: StringName = &"":
	set(value):
		boss_id = value
		_refresh()
@export var radius: float = 15.0:
	set(value):
		radius = value
		_refresh()


func _marker_group() -> StringName:
	return GROUP


func _gizmo_color() -> Color:
	return Color(0.9, 0.15, 0.15)


func _gizmo_label() -> String:
	return "BossArena %s (r %sm)" % [boss_id, radius]


func _build_gizmo() -> void:
	_add_cylinder(0.25, 3.0)
	_add_ring(radius)


func _marker_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if boss_id == &"":
		warnings.append("boss_id is empty.")
	return warnings
