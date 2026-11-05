@tool
class_name WorkSpot
extends ColonyMarker
## A fixed place on the map where residents stand to work (방송실, 벌목터 ...).
## Spots that belong to a building are placed inside the building scene instead (C-04).
## job_id uses data/jobs ids (docs/design/07-residents.md "직업").

const MARKER_GROUP := &"base_work_spots"

@export var job_id: StringName = &"":
	set(v):
		job_id = v
		_changed()
## How many residents can work here at once.
@export var capacity := 1:
	set(v):
		capacity = maxi(v, 1)
		_changed()


func _marker_group() -> StringName:
	return MARKER_GROUP


func _helper_color() -> Color:
	return Color(1.0, 0.75, 0.2)


func _helper_mesh() -> Mesh:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.6
	disc.bottom_radius = 0.6
	disc.height = 0.1
	return disc


func _helper_offset() -> Vector3:
	return Vector3(0.0, 0.05, 0.0)


func _label_text() -> String:
	return "Work %s ×%d" % [job_id, capacity]


func _label_height() -> float:
	return 1.2
