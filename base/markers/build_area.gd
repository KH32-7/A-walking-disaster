@tool
class_name BuildArea
extends ColonyMarker
## Rectangle of buildable cells. The marker is the rectangle's center; width runs along
## local X, height along local Z. C-03 (grid building) places buildings on these cells.
## Ref: docs/design/09-base-building.md "건설 규칙", "구역과 개간"

const MARKER_GROUP := &"base_build_areas"

## Zone this area belongs to (ZoneMarker.zone_id). Cells are buildable only once it is cleared.
@export var zone_id: StringName = &"":
	set(v):
		zone_id = v
		_changed()
@export var size_cells: Vector2i = Vector2i(4, 4):
	set(v):
		size_cells = Vector2i(maxi(v.x, 1), maxi(v.y, 1))
		_changed()


func size_m() -> Vector2:
	return Vector2(size_cells) * CELL_SIZE


func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size_cells.x and cell.y < size_cells.y


## Center of `cell` in this marker's local space (y = 0).
func cell_to_local(cell: Vector2i) -> Vector3:
	var origin := -size_m() * 0.5
	return Vector3(origin.x + (cell.x + 0.5) * CELL_SIZE, 0.0, origin.y + (cell.y + 0.5) * CELL_SIZE)


## Cell under a local-space point. May be outside the area; check with has_cell().
func local_to_cell(local_pos: Vector3) -> Vector2i:
	var origin := -size_m() * 0.5
	return Vector2i(floori((local_pos.x - origin.x) / CELL_SIZE), floori((local_pos.z - origin.y) / CELL_SIZE))


func cell_to_world(cell: Vector2i) -> Vector3:
	return to_global(cell_to_local(cell))


func world_to_cell(world_pos: Vector3) -> Vector2i:
	return local_to_cell(to_local(world_pos))


func _marker_group() -> StringName:
	return MARKER_GROUP


func _helper_color() -> Color:
	return Color(0.35, 0.85, 0.45)


func _helper_mesh() -> Mesh:
	# Flat plate with grid lines, one quad per cell edge.
	var im := ImmediateMesh.new()
	var half := size_m() * 0.5
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for x in size_cells.x + 1:
		var px := -half.x + x * CELL_SIZE
		im.surface_add_vertex(Vector3(px, 0.05, -half.y))
		im.surface_add_vertex(Vector3(px, 0.05, half.y))
	for z in size_cells.y + 1:
		var pz := -half.y + z * CELL_SIZE
		im.surface_add_vertex(Vector3(-half.x, 0.05, pz))
		im.surface_add_vertex(Vector3(half.x, 0.05, pz))
	im.surface_end()
	return im


func _label_text() -> String:
	return "BuildArea %s\n%d×%d칸" % [zone_id, size_cells.x, size_cells.y]


func _label_height() -> float:
	return 1.0


## South edge, so it does not sit on top of the zone label at the same center.
func _label_position() -> Vector3:
	return Vector3(0.0, _label_height(), size_m().y * 0.5 - CELL_SIZE)
