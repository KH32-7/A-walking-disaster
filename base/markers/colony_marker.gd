@tool
class_name ColonyMarker
extends Marker3D
## Base class for Lane C base-map markers (docs/dev/contracts.md "맵 파일과 마커").
## Each marker draws a helper (shape + label) in the editor so Lane D can see it while
## dressing. In game the helper is not created, unless `show_in_game` is on (sandbox debug).
## The helper is an internal child without an owner, so it is never saved into a scene.

## 1 cell = 2 m (docs/design/09-base-building.md "건설 규칙").
const CELL_SIZE := 2.0
## Every base marker is in this group, plus its own group (see subclasses).
const GROUP := &"base_markers"

## Sandbox/debug only. Set before markers enter the tree, or call refresh_all() after.
static var show_in_game := false

var _helper: Node3D


static func refresh_all(tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		(node as ColonyMarker).refresh_helper()


func _ready() -> void:
	add_to_group(GROUP)
	var own_group := _marker_group()
	if own_group != &"":
		add_to_group(own_group)
	refresh_helper()


func refresh_helper() -> void:
	if _helper:
		_helper.queue_free()
		_helper = null
	if not is_inside_tree() or not (Engine.is_editor_hint() or show_in_game):
		return
	_helper = Node3D.new()
	_helper.name = "_Helper"
	var color := _helper_color()
	var mesh := _helper_mesh()
	if mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = _helper_offset()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _make_material(color)
		_helper.add_child(mi)
	var label := Label3D.new()
	label.text = _label_text()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 64
	label.outline_size = 16
	label.pixel_size = 0.02
	label.modulate = color.lightened(0.4)
	label.position = _label_position()
	_helper.add_child(label)
	add_child(_helper, false, Node.INTERNAL_MODE_FRONT)


# --- Overridden by subclasses -------------------------------------------------

func _marker_group() -> StringName:
	return &""


func _helper_color() -> Color:
	return Color.WHITE


func _helper_mesh() -> Mesh:
	return null


func _helper_offset() -> Vector3:
	return Vector3.ZERO


func _label_text() -> String:
	return name


func _label_height() -> float:
	return 2.0


func _label_position() -> Vector3:
	return Vector3(0.0, _label_height(), 0.0)


# --- Helpers ------------------------------------------------------------------

func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, 0.35)
	return mat


## Typical setter body for exported fields: redraw only while in the editor/tree.
func _changed() -> void:
	if is_inside_tree():
		refresh_helper()
