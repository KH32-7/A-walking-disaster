@tool
class_name FieldMarker
extends Marker3D
## Base for every field map marker (B-02). Markers are the contract between
## field layouts (Lane B) and dressing work (Lane D): D sees them in the editor,
## the game never shows them.
##
## Editor: draws a colored shape and a name label as INTERNAL children, so the
## gizmo is never saved into a scene. Runtime: draws nothing and joins
## GROUP_ALL plus the subclass group so field systems can find markers.
## Design reference: docs/design/02-field.md "맵 구조", "데이터 정의"

const GROUP_ALL := &"field_markers"
const LABEL_HEIGHT := 2.4

var _gizmo: Node3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild_gizmo()
		return
	add_to_group(GROUP_ALL)
	add_to_group(_marker_group())


## Override: group name for this marker kind.
func _marker_group() -> StringName:
	return &""


## Override: gizmo color for this marker kind.
func _gizmo_color() -> Color:
	return Color.WHITE


## Override: text shown above the marker in the editor.
func _gizmo_label() -> String:
	return name


## Override: add shapes with the _add_* helpers.
func _build_gizmo() -> void:
	pass


## Override: editor warnings (empty id, invalid values).
func _marker_warnings() -> PackedStringArray:
	return PackedStringArray()


func _get_configuration_warnings() -> PackedStringArray:
	return _marker_warnings()


## Call from exported property setters.
func _refresh() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		_rebuild_gizmo()
		update_configuration_warnings()


func _rebuild_gizmo() -> void:
	if _gizmo:
		_gizmo.queue_free()
	_gizmo = Node3D.new()
	_gizmo.name = "EditorGizmo"
	add_child(_gizmo, false, Node.INTERNAL_MODE_BACK)
	var label := Label3D.new()
	label.text = _gizmo_label()
	label.position.y = LABEL_HEIGHT
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0015
	label.font_size = 24
	label.outline_size = 6
	label.modulate = _gizmo_color().lightened(0.4)
	_gizmo.add_child(label)
	_build_gizmo()


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat


func _add_mesh(mesh: Mesh, offset: Vector3) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = offset
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gizmo.add_child(inst)


## Translucent solid shape standing on the ground.
func _add_solid(mesh: PrimitiveMesh, height: float) -> void:
	var color := _gizmo_color()
	color.a = 0.45
	mesh.material = _material(color)
	_add_mesh(mesh, Vector3(0.0, height * 0.5, 0.0))


func _add_box(size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_solid(mesh, size.y)


func _add_cylinder(radius: float, height: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	_add_solid(mesh, height)


## Flat ring on the ground, in this marker's local space.
func _add_ring(radius: float, segments: int = 48) -> void:
	var points := PackedVector3Array()
	for i in segments + 1:
		var angle := TAU * i / segments
		points.append(Vector3(cos(angle) * radius, 0.05, sin(angle) * radius))
	_add_polyline(points)


## Line strip in this marker's local space.
func _add_polyline(points: PackedVector3Array) -> void:
	if points.size() < 2:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _material(_gizmo_color()))
	for p in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	_add_mesh(mesh, Vector3.ZERO)
