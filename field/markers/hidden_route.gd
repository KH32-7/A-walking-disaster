@tool
class_name HiddenRoute
extends FieldMarker
## Hidden route between two points (children "From" and "To", move them in the
## editor). B-20 reveals it when someone in the party has required_trait.
## Data: id, required_trait, from_node, to_node (02-field.md "데이터 정의").

const GROUP := &"field_hidden_routes"

@export var id: StringName = &"":
	set(value):
		id = value
		_refresh()
@export var required_trait: StringName = &"":
	set(value):
		required_trait = value
		_refresh()

var _last_points := PackedVector3Array()


func _ready() -> void:
	super()
	set_process(Engine.is_editor_hint())


## Children move without telling the parent, so redraw when they do (editor only).
func _process(_delta: float) -> void:
	if _points() != _last_points:
		_refresh()


func from_point() -> Vector3:
	var node := get_node_or_null(^"From") as Node3D
	return node.global_position if node else global_position


func to_point() -> Vector3:
	var node := get_node_or_null(^"To") as Node3D
	return node.global_position if node else global_position


func _points() -> PackedVector3Array:
	var from := get_node_or_null(^"From") as Node3D
	var to := get_node_or_null(^"To") as Node3D
	if from == null or to == null:
		return PackedVector3Array()
	return PackedVector3Array([from.position, to.position])


func _marker_group() -> StringName:
	return GROUP


func _gizmo_color() -> Color:
	return Color(0.7, 0.45, 1.0)


func _gizmo_label() -> String:
	return "HiddenRoute %s (%s)" % [id, required_trait]


func _build_gizmo() -> void:
	_last_points = _points()
	_add_polyline(_last_points)


func _marker_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if id == &"":
		warnings.append("id is empty.")
	if required_trait == &"":
		warnings.append("required_trait is empty.")
	if _points().is_empty():
		warnings.append("Needs Node3D children named From and To.")
	return warnings
