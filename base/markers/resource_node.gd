@tool
class_name ResourceNode
extends ColonyMarker
## A tree or debris pile residents harvest (벌목 / 해체). Ref: docs/design/07-residents.md "직업".

const MARKER_GROUP := &"base_resource_nodes"

enum Kind { TREE, DEBRIS }

@export var kind: Kind = Kind.TREE:
	set(v):
		kind = v
		_changed()
## Resource given (Economy id). Empty = default for the kind (tree -> wood, debris -> scrap).
@export var resource_id: StringName = &""
## Total amount before the node is used up. 0 = never runs out.
@export var amount := 0


func get_resource_id() -> StringName:
	if resource_id != &"":
		return resource_id
	return &"wood" if kind == Kind.TREE else &"scrap"


func _marker_group() -> StringName:
	return MARKER_GROUP


func _helper_color() -> Color:
	return Color(0.3, 0.75, 0.3) if kind == Kind.TREE else Color(0.7, 0.55, 0.4)


func _helper_mesh() -> Mesh:
	if kind == Kind.TREE:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.0
		cone.height = 3.0
		return cone
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 0.8, 1.2)
	return box


func _helper_offset() -> Vector3:
	return Vector3(0.0, 1.5 if kind == Kind.TREE else 0.4, 0.0)


func _label_text() -> String:
	return "%s %s" % ["Tree" if kind == Kind.TREE else "Debris", get_resource_id()]


func _label_height() -> float:
	return 3.6 if kind == Kind.TREE else 1.6
