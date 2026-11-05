@tool
class_name ZoneMarker
extends ColonyMarker
## One base zone (본관 1층, 운동장, 체육관 ...). Center of the zone's rectangle, like BuildArea.
## Clearing (C-10) and access checks (C-11) work per zone.
## Values are placeholders from docs/design/09-base-building.md "구역과 개간" (가안).

const MARKER_GROUP := &"base_zones"

@export var zone_id: StringName = &"":
	set(v):
		zone_id = v
		_changed()
@export var size_cells: Vector2i = Vector2i(10, 10):
	set(v):
		size_cells = Vector2i(maxi(v.x, 1), maxi(v.y, 1))
		_changed()
@export var indoor := false:
	set(v):
		indoor = v
		_changed()
## 0 = ground floor. Upper floors need stairs/elevator for access (C-11).
@export var floor_index := 0
@export var unlock_tier: Enums.BaseTier = Enums.BaseTier.CAMP
## Already usable at game start (본관 1층).
@export var starts_cleared := false
## Clearing work needed (진행도). 0 when starts_cleared.
@export var clear_work := 0
## Resources gained when cleared, resource_id -> amount.
@export var clear_yield: Dictionary[StringName, int] = {}


func size_m() -> Vector2:
	return Vector2(size_cells) * CELL_SIZE


func _marker_group() -> StringName:
	return MARKER_GROUP


func _helper_color() -> Color:
	return Color(0.95, 0.85, 0.3) if indoor else Color(0.4, 0.7, 1.0)


func _helper_mesh() -> Mesh:
	var box := BoxMesh.new()
	var s := size_m()
	box.size = Vector3(s.x, 0.4, s.y)
	return box


func _helper_offset() -> Vector3:
	return Vector3(0.0, 0.2, 0.0)


func _label_text() -> String:
	return "Zone %s%s\n%d×%d칸" % [zone_id, " (실내)" if indoor else "", size_cells.x, size_cells.y]


func _label_height() -> float:
	return 3.0


func _make_material(color: Color) -> StandardMaterial3D:
	var mat := super(color)
	mat.albedo_color.a = 0.12
	return mat
