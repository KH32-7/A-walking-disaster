@tool
class_name OutpostNode
extends ColonyMarker
## A spot where an outpost can be built (C-19): one per direction around the base,
## plus region entrances. Ref: docs/design/10-raids-defense.md "전초기지"

const MARKER_GROUP := &"base_outpost_nodes"

@export var node_id: StringName = &"":
	set(v):
		node_id = v
		_changed()
## Raid direction this outpost covers ("none" for a region entrance node).
@export_enum("none", "north", "east", "south", "west") var direction: String = "none":
	set(v):
		direction = v
		_changed()
## For region-entrance nodes: the field region id (data/regions).
@export var region_id: StringName = &""


## &"" for a region entrance node, otherwise &"north" / &"east" / &"south" / &"west".
func direction_id() -> StringName:
	return &"" if direction == "none" else StringName(direction)


func _marker_group() -> StringName:
	return MARKER_GROUP


func _helper_color() -> Color:
	return Color(0.55, 0.5, 1.0)


func _helper_mesh() -> Mesh:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.25
	pole.bottom_radius = 0.25
	pole.height = 3.0
	return pole


func _helper_offset() -> Vector3:
	return Vector3(0.0, 1.5, 0.0)


func _label_text() -> String:
	var where := String(region_id) if direction == "none" else direction
	return "Outpost %s (%s)" % [node_id, where]


func _label_height() -> float:
	return 3.6
