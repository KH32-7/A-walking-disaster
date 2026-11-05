class_name BaseGrid
extends RefCounted
## Placement rules on a base map (C-03, docs/design/09-base-building.md "건설 규칙").
## Built from a layout (BuildArea / ZoneMarker / ResourceNode markers). Each BuildArea has its own
## cell grid (1 cell = 2 m); Colony building instances keep (zone_id, cell, rotation) of that grid.
## Checks only *where* a building may go. *Whether* it can be built (cost, tier, blueprints) is
## Colony.can_build(). Pure logic, no nodes are created.

## Buildings that must stand near a resource node (09 "건물 목록" 조건: 반경 10m).
const NEEDS_NODE := {
	&"lumber_yard": ResourceNode.Kind.TREE,
	&"quarry": ResourceNode.Kind.DEBRIS,
}
const NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## zone_id -> BuildArea / ZoneMarker
var areas: Dictionary = {}
var zones: Dictionary = {}
var resource_nodes: Array[ResourceNode] = []


static func from_layout(layout: Node) -> BaseGrid:
	var grid := BaseGrid.new()
	for node in layout.find_children("*", "Marker3D", true, false):
		if node is BuildArea:
			grid.areas[node.zone_id] = node
		elif node is ZoneMarker:
			grid.zones[node.zone_id] = node
		elif node is ResourceNode:
			grid.resource_nodes.append(node)
	return grid


## Footprint in cells after rotation (0..3, 90° steps): odd rotations swap width and height.
static func footprint(def: BuildingDef, rotation: int) -> Vector2i:
	return Vector2i(def.size.y, def.size.x) if posmod(rotation, 2) == 1 else def.size


static func cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in size.x:
		for y in size.y:
			out.append(origin + Vector2i(x, y))
	return out


func is_zone_cleared(zone_id: StringName) -> bool:
	var zone: ZoneMarker = zones.get(zone_id)
	return (zone != null and zone.starts_cleared) or Colony.is_zone_cleared(zone_id)


## World position of a footprint's center (origin = top-left cell).
func footprint_center(zone_id: StringName, origin: Vector2i, size: Vector2i) -> Vector3:
	var area: BuildArea = areas[zone_id]
	var a := area.cell_to_world(origin)
	var b := area.cell_to_world(origin + size - Vector2i.ONE)
	return (a + b) * 0.5


## Which area and cell a world point falls on: {"zone_id", "cell"}, or {} off every area.
func pick(world_pos: Vector3) -> Dictionary:
	for zone_id: StringName in areas:
		var area: BuildArea = areas[zone_id]
		var cell := area.world_to_cell(world_pos)
		if area.has_cell(cell):
			return {"zone_id": zone_id, "cell": cell}
	return {}


## Cells taken in `zone_id` by Colony buildings: cell -> uid. `ignore_uid` is left out (moving).
func occupied(zone_id: StringName, ignore_uid: StringName = &"") -> Dictionary:
	var taken := {}
	for uid: StringName in Colony.buildings:
		var b: Dictionary = Colony.buildings[uid]
		if uid == ignore_uid or b["zone_id"] != zone_id:
			continue
		var def := BaseDB.get_building(b["def_id"])
		if def == null or def.size == Vector2i.ZERO:
			continue
		for c in cells(Vector2i(b["cell"][0], b["cell"][1]), footprint(def, int(b["rotation"]))):
			taken[c] = uid
	return taken


## Can `def_id` stand at `origin` (top-left cell) of `zone_id` with `rotation`?
## Returns {"ok": bool, "reasons": Array[String]} (reasons are shown to the player).
func check(def_id: StringName, zone_id: StringName, origin: Vector2i, rotation: int = 0,
		ignore_uid: StringName = &"") -> Dictionary:
	var reasons: Array[String] = []
	var def := BaseDB.get_building(def_id)
	var area: BuildArea = areas.get(zone_id)
	if def == null:
		return {"ok": false, "reasons": ["알 수 없는 건물"]}
	if area == null:
		return {"ok": false, "reasons": ["건설 부지가 아님"]}
	if def.size == Vector2i.ZERO or def.prebuilt or def.attach_to != &"":
		return {"ok": false, "reasons": ["격자에 놓는 건물이 아님"]}
	if def.zone_only != &"" and def.zone_only != zone_id:
		reasons.append("이 구역에는 못 지음 (%s 전용)" % def.zone_only)
	if not is_zone_cleared(zone_id):
		reasons.append("개간되지 않은 구역")
	var size := footprint(def, rotation)
	var mine := cells(origin, size)
	var taken := occupied(zone_id, ignore_uid)
	var out_of_bounds := false
	var overlap := false
	for c in mine:
		if not area.has_cell(c):
			out_of_bounds = true
		elif taken.has(c):
			overlap = true
	if out_of_bounds:
		reasons.append("부지 밖으로 나감")
	if overlap:
		reasons.append("다른 건물과 겹침")
	if NEEDS_NODE.has(def_id):
		var radius := def.effect(&"resource_node_radius", 10.0)
		if _nearest_node(NEEDS_NODE[def_id], footprint_center(zone_id, origin, size)) > radius:
			reasons.append("%s가 %.0fm 안에 없음" % ["나무" if NEEDS_NODE[def_id] == ResourceNode.Kind.TREE else "잔해 더미", radius])
	if not out_of_bounds and not overlap and not _paths_ok(area, taken, mine):
		reasons.append("통로가 막힘 (걸어서 닿을 수 없는 건물이 생김)")
	return {"ok": reasons.is_empty(), "reasons": reasons}


func _nearest_node(kind: ResourceNode.Kind, pos: Vector3) -> float:
	var best := INF
	for node in resource_nodes:
		if node.kind == kind:
			best = minf(best, Vector2(node.global_position.x, node.global_position.z).distance_to(Vector2(pos.x, pos.z)))
	return best


## After placing `new_cells`, every building in the area still touches a walkable cell: a free
## cell reachable from the area's border (outside the area is open ground), or the border itself.
func _paths_ok(area: BuildArea, taken: Dictionary, new_cells: Array[Vector2i]) -> bool:
	var blocked := taken.duplicate()
	for c in new_cells:
		blocked[c] = &"__new__"
	var reachable := {}
	var queue: Array[Vector2i] = []
	for x in area.size_cells.x:
		for y in area.size_cells.y:
			var c := Vector2i(x, y)
			var border := x == 0 or y == 0 or x == area.size_cells.x - 1 or y == area.size_cells.y - 1
			if border and not blocked.has(c):
				reachable[c] = true
				queue.append(c)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in NEIGHBORS:
			var n := c + d
			if area.has_cell(n) and not blocked.has(n) and not reachable.has(n):
				reachable[n] = true
				queue.append(n)
	var by_owner := {}
	for c: Vector2i in blocked:
		var owner: StringName = blocked[c]
		if not by_owner.has(owner):
			by_owner[owner] = []
		by_owner[owner].append(c)
	for owner: StringName in by_owner:
		var touches := false
		for c: Vector2i in by_owner[owner]:
			for d in NEIGHBORS:
				var n := c + d
				if not area.has_cell(n) or reachable.has(n):
					touches = true
					break
			if touches:
				break
		if not touches:
			return false
	return true
