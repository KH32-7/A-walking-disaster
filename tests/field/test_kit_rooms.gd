extends RefCounted
## Kit building rooms (field/buildings/city_kit.gd parts() rooms, user feedback 2026-11-07): every
## room of the flooded mall and hospital plans is on the floor grid inside its building with a known
## floor and paint, the floor pieces cover each building exactly once, walls take the paint of the
## room on each of their sides (outer walls only inside), and the map file's spots inside kit
## buildings keep clear of the new walls and furniture. Needs no assets/ pack.

const CityKit := preload("res://field/buildings/city_kit.gd")
const LayoutBuilder := preload("res://field/build/layout_builder.gd")
## [kit_buildings.gd, map file] per region.
const REGIONS := [
	["res://levels/field/flooded_mall/build/kit_buildings.gd", "res://levels/field/flooded_mall/build/flooded_mall_map.json"],
	["res://levels/field/hospital/build/kit_buildings.gd", "res://levels/field/hospital/build/hospital_map.json"],
]
## layout_builder.gd KIT_MARKER_CLEAR.
const MARKER_CLEAR := 0.3
## Probe distance for the expected paint, further out than CityKit.PAINT_PROBE.
const FAR_PROBE := 1.0

var _ok := true


func run() -> bool:
	_check_shader()
	for region: Array in REGIONS:
		var buildings: Dictionary = load(region[0]).BUILDINGS
		var markers := _markers(region[1])
		for id: String in buildings:
			var plan: Dictionary = buildings[id][0]
			var spec: Dictionary = buildings[id][1]
			var p := CityKit.parts(plan, spec)
			_check_rooms(id, plan)
			_check_floor(id, p)
			_check_paint(id, plan, p)
			_check_markers(id, p, markers)
	return _ok


func _fail(msg: String) -> void:
	push_error("test_kit_rooms: " + msg)
	_ok = false


func _check_shader() -> void:
	var names := []
	for u: Dictionary in CityKit.PAINT_SHADER.get_shader_uniform_list():
		names.append(u.name)
	for want in ["albedo", "albedo_texture", "paint_uv", "paint_base"]:
		if not want in names:
			_fail("room_paint.gdshader has no uniform %s (got %s)" % [want, names])


func _check_rooms(id: String, plan: Dictionary) -> void:
	var size: Vector2i = plan.size
	for room: Dictionary in plan.get("rooms", []):
		var r: Rect2i = room.rect
		var grid := CityKit.FLOOR_GRID
		if r.position.x % grid or r.position.y % grid or r.size.x % grid or r.size.y % grid:
			_fail("%s room %s %s is off the %d m floor grid" % [id, room.name, r, grid])
		if not Rect2i(Vector2i.ZERO, size).encloses(r):
			_fail("%s room %s %s is outside the %s plan" % [id, room.name, r, size])
		if not CityKit.FLOOR_SIZES.has(room.get("floor", plan.get("floor", "b"))):
			_fail("%s room %s has unknown floor %s" % [id, room.name, room.get("floor")])
		var paint: String = room.get("paint", "")
		if not paint.is_empty() and not CityKit.PAINT.has(paint):
			_fail("%s room %s has unknown paint %s" % [id, room.name, paint])


## Floor pieces: inside the building, no overlap, the whole building covered.
func _check_floor(id: String, p: Dictionary) -> void:
	var rect: Rect2 = p.rect
	var cells := {}
	for tile: Dictionary in p.floor:
		var r: Rect2 = tile.rect
		if not rect.encloses(r):
			_fail("%s floor piece %s at %s sticks out of %s" % [id, tile.piece, r, rect])
		for i in roundi(r.size.x / CityKit.FLOOR_GRID):
			for j in roundi(r.size.y / CityKit.FLOOR_GRID):
				var c := Vector2i(roundi(r.position.x) + i * CityKit.FLOOR_GRID, roundi(r.position.y) + j * CityKit.FLOOR_GRID)
				if cells.has(c):
					_fail("%s floor pieces overlap at %s" % [id, c])
				cells[c] = true
	var want := roundi(rect.get_area()) / (CityKit.FLOOR_GRID * CityKit.FLOOR_GRID)
	if cells.size() != want:
		_fail("%s floor covers %d of %d cells" % [id, cells.size(), want])


## Each wall side's paint is the room a metre off the wall on that side; outer walls paint only
## their inner (+X) face.
func _check_paint(id: String, plan: Dictionary, p: Dictionary) -> void:
	if plan.get("rooms", []).is_empty():
		return
	for seg: Dictionary in p.segments:
		if seg.kind == "x":
			continue
		var xf := CityKit._segment_xf(seg)
		var sides := CityKit._wall_paint(p.rooms, seg, xf)
		var mid: Vector2 = (seg.a + seg.b) * 0.5
		var x := Vector2(xf.basis.x.x, xf.basis.x.z).normalized()
		var want := [CityKit._room_paint_at(p.rooms, mid + x * FAR_PROBE), CityKit._room_paint_at(p.rooms, mid - x * FAR_PROBE)]
		for s in 2:
			if not sides[s].is_equal_approx(want[s]):
				_fail("%s wall %d (%s, inner %s) side %d paint %s, the room there is %s"
					% [id, seg.index, seg.kind, seg.inner, s, sides[s], want[s]])
		if not seg.inner and sides[1].a > 0.0:
			_fail("%s outer wall %d paints its outside" % [id, seg.index])


func _markers(path: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for m: Dictionary in map.markers:
		if m.floor == 0:
			out.append(Vector2(m.position[0], m.position[2]) * LayoutBuilder.MAP_SCALE)
	return out


func _check_markers(id: String, p: Dictionary, markers: Array[Vector2]) -> void:
	var props: Array = CityKit.prop_boxes(p)
	var boxes: Array = p.walls + props[0] + props[1]
	for m in markers:
		if not (p.rect as Rect2).has_point(m):
			continue
		for box: AABB in boxes:
			if box.grow(MARKER_CLEAR).has_point(Vector3(m.x, 0.5, m.y)):
				_fail("%s: map marker at (%.2f, %.2f) is within %.1f m of a wall or prop %s" % [id, m.x, m.y, MARKER_CLEAR, box])
				break
