@tool
class_name VehicleSpot
extends FieldMarker
## Candidate spot for a field vehicle (02 "탈것"). VehicleSpawner draws a share of them each sortie.
## WATER spots sit on deep water (boats). The first WATER spot (by name) is also where a boat
## brought from the base appears.

const GROUP := &"field_vehicle_spots"

## Vehicle ids that may appear here (data/vehicles). Empty = every vehicle of `surface`.
@export var vehicle_ids: Array[StringName] = []:
	set(value):
		vehicle_ids = value
		_refresh()
@export var surface: VehicleDef.Surface = VehicleDef.Surface.LAND:
	set(value):
		surface = value
		_refresh()


func _marker_group() -> StringName:
	return GROUP


func _gizmo_color() -> Color:
	return Color(0.3, 0.8, 1.0) if surface == VehicleDef.Surface.WATER else Color(0.6, 0.9, 0.3)


func _gizmo_label() -> String:
	var ids := " %s" % ", ".join(vehicle_ids) if not vehicle_ids.is_empty() else ""
	return "VehicleSpot %s%s" % [VehicleDef.Surface.keys()[surface], ids]


func _build_gizmo() -> void:
	_add_box(Vector3(1.8, 1.2, 4.0))
