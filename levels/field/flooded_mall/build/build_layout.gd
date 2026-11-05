extends SceneTree
## Builds levels/field/flooded_mall/layout.tscn (B-12) from the confirmed map file.
##
##   godot --headless --path . --script res://levels/field/flooded_mall/build/build_layout.gd
##
## Source: build/flooded_mall_map.json, exported from the planning board (user-confirmed map,
## 2026-11-05). Coordinates are Godot meters, origin at the map center, +X east, +Z south.
## The map file has zones, floor links and markers. What it does not say is decided here:
## wall heights, doors, stair direction, the ramp shape, greybox props (DOORS, PROPS below).
## Re-run after the map file changes. Hand edits to layout.tscn are lost on a re-run.
##
## Navigation layers (agreed with B-10): 1 = everyone on foot, 2 = wheelchair.
## The region has both layers. Stairs are cut out of the navmesh and joined by a layer-1-only
## NavigationLink3D, so a wheelchair path from the mall's 2F can only use the hidden ramp.

const MAP_PATH := "res://levels/field/flooded_mall/build/flooded_mall_map.json"
const OUT_SCENE := "res://levels/field/flooded_mall/layout.tscn"
const OUT_NAVMESH := "res://levels/field/flooded_mall/layout_navmesh.res"
const INDOOR_ZONE_SCRIPT := "res://field/camera/indoor_zone.gd"

const NAV_GROUP := &"nav_source"
## B-04 IndoorZone.ROOF_GROUP / ROOF_META (field/camera/indoor_zone.gd).
const ROOF_GROUP := &"field_roof"
const ROOF_META := &"building_id"
## B-06 WeaponHolder.LOW_COVER_GROUP: shots pass over, target close behind takes x0.5.
const LOW_COVER_GROUP := &"low_cover"

const LAYER_WORLD_BIT := 1
const LAYER_PLAYER_BIT := 1 << 1
const LAYER_TRIGGER_BIT := 1 << 7
const NAV_LAYER_WALK := 1
const NAV_LAYER_WHEELCHAIR := 2

const MAP_HALF := 75.0
const GROUND_DEPTH := 1.0
const SLAB := 0.3
const WALL_T := 0.3
const ROOF_T := 0.2
const DEFAULT_WALL_H := 3.0
const WALL_H := {"mart_in": 4.0}
const UPPER_WALL_H := 3.5
## Railings, deck parapets and the deep-water lip stay under the 1.0m shot height (B-06).
const LOW_WALL_H := 0.9
const WATER_EDGE_H := 0.8
const WATER_SURFACE_Y := -0.3
const BLOCKED_H := {"rubble": 3.5}
const DEFAULT_BLOCKED_H := 3.0
const RAMP_WIDTH := 3.5
const BOUNDS_H := 4.0

## Doors: zone id -> [[x, z, width], ...]. The point snaps to the nearest wall edge.
## Placed from the demo routes and the roads/bridges each building faces.
const DOORS := {
	"mart_in": [[-33.0, -58.0, 3.0], [-56.0, -43.0, 3.0]],
	"pharm": [[-24.0, -45.0, 2.0], [-21.0, -52.0, 2.0]],
	"depot_office": [[25.0, -48.0, 2.0]],
	"gas_store": [[-20.0, 25.0, 2.0], [-13.0, 30.0, 2.0]],
	"house1": [[-20.0, 41.0, 2.0]],
	"house2": [[-16.0, 42.0, 2.0]],
	"house3": [[-20.5, 57.0, 2.0]],
	"house4": [[-15.5, 57.0, 2.0]],
	"house5": [[-21.0, 69.0, 2.0]],
	"house6": [[-16.0, 68.0, 2.0]],
	# Mall 1F: north road, east pier, south dock, west footbridge.
	"shop_in": [[29.0, 17.9, 4.0], [49.9, 29.0, 3.0], [38.0, 49.0, 4.0], [21.0, 27.5, 5.0]],
	# Mall 2F wall between the food court and the roof deck.
	"shop2_in": [[41.0, 33.6, 3.0]],
}
## Elevator door (2F, the car is stuck there): side of the shaft rect.
const ELEVATOR_DOOR := [38.0, 27.0, 2.0]

## Greybox props not in the map file. [name, x, z, size_x, size_z, height, rot_y_deg]
## Low cover (1.2m, B-06 sandbox size): cars on the bridge, gas pumps, gate barricade.
const LOW_COVER := [
	["Car1", 23.0, -22.0, 2.0, 4.2, 1.2, 0.0],
	["Car2", 26.5, -12.0, 2.0, 4.2, 1.2, 10.0],
	["Car3", 23.5, -2.0, 2.0, 4.2, 1.2, -8.0],
	["Pump1", -26.0, 10.0, 1.0, 3.0, 1.2, 0.0],
	["Pump2", -26.0, 16.0, 1.0, 3.0, 1.2, 0.0],
	["GateBarricadeW", -17.75, -68.0, 2.5, 1.0, 1.2, 0.0],
	["GateBarricadeE", -12.25, -68.0, 2.5, 1.0, 1.2, 0.0],
]
## Trees in vegetation zones, rocks on open ground. Seeded, so a re-run plants the same map.
## Rocks are low cover. Nothing grows on roads, water, near buildings, markers, props or demo routes.
const NATURE_SEED := 20261105
const TREE_SPACING := 5.0
const TREE_TRUNK_RADIUS := 0.3
const TREE_TRUNK_H := 2.4
const TREE_CROWN_R := 1.6
const ROCK_COUNT := 40
const ROCK_SPACING := 6.0
const CLEAR_MARKER := 3.0
const CLEAR_ROUTE := 2.5
const CLEAR_PROP := 3.0
const CLEAR_BUILDING := 2.5
const CLEAR_ROAD := 1.0
const CLEAR_EDGE := 3.0
## Full blockers: dock trucks (landmark look: 트럭 두 대), mart shelf rows (선반 사이로 덩굴).
const BLOCKERS := [
	["TruckA", 31.0, 63.0, 7.0, 2.5, 3.0, 0.0],
	["TruckB", 42.0, 68.0, 2.5, 7.0, 3.0, 0.0],
	["MartShelf1", -62.0, -65.0, 10.0, 0.8, 2.2, 0.0],
	["MartShelf2", -62.0, -61.0, 10.0, 0.8, 2.2, 0.0],
	["MartShelf3", -62.0, -53.0, 10.0, 0.8, 2.2, 0.0],
]

const COLORS := {
	"ground": Color(0.80, 0.76, 0.66),
	"road": Color(0.62, 0.62, 0.60),
	"shallow": Color(0.55, 0.75, 0.85),
	"deep": Color(0.25, 0.45, 0.65),
	"vegetation": Color(0.50, 0.68, 0.38),
	"floor": Color(0.74, 0.66, 0.52),
	"wall": Color(0.85, 0.78, 0.62),
	"roof": Color(0.45, 0.38, 0.32),
	"blocked": Color(0.55, 0.48, 0.42),
	"cover": Color(0.85, 0.55, 0.25),
	"slab": Color(0.66, 0.66, 0.64),
	"stairs": Color(0.35, 0.35, 0.38),
	"trunk": Color(0.42, 0.32, 0.22),
	"crown": Color(0.30, 0.50, 0.28),
	"rock": Color(0.55, 0.55, 0.52),
}
## Overlay heights so overlapping flat zones do not z-fight.
const OVERLAY_Y := {"shallow": 0.02, "road": 0.03, "vegetation": 0.04, "floor": 0.05}

var _map: Dictionary
var _zones := {}
var _mats := {}
var _root: Node3D
var _ramp_poly := PackedVector2Array()


func _initialize() -> void:
	var text := FileAccess.get_file_as_string(MAP_PATH)
	_map = JSON.parse_string(text)
	if _map.is_empty():
		push_error("Cannot read %s" % MAP_PATH)
		quit(1)
		return
	for zone: Dictionary in _map.zones:
		_zones[zone.id] = zone
	for key: String in COLORS:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COLORS[key]
		mat.resource_name = key
		_mats[key] = mat

	_root = Node3D.new()
	_root.name = "FloodedMallLayout"
	_build_terrain()
	_build_buildings()
	_build_mall()
	_build_props()
	_build_nature()
	_build_bounds()
	_build_markers()
	var region := _build_navigation()

	get_root().add_child(_root)
	# CSG shapes build their meshes and collision deferred.
	for i in 3:
		await process_frame
		await physics_frame
	var ok := _bake(region)
	_set_owners(_root)
	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_SCENE)
	print("layout: %s, navmesh polygons: %d, nodes: %d" % [
		error_string(err), region.navigation_mesh.get_polygon_count(), _count(_root)])
	quit(0 if ok and err == OK else 1)


# --- terrain ---------------------------------------------------------------

func _build_terrain() -> void:
	var deep: Array[PackedVector2Array] = []
	var crossings: Array[PackedVector2Array] = []
	for zone: Dictionary in _map.zones:
		if zone.floor == 0 and zone.kind == "flooded" and not zone.passable:
			deep.append(_poly(zone))
	for zone: Dictionary in _map.zones:
		if zone.floor == 0 and zone.kind == "road" and _overlaps_any(_poly(zone), deep):
			crossings.append(_poly(zone))

	# Ground: land minus deep water, plus the bridges and the pier over it.
	var square := PackedVector2Array([
		Vector2(-MAP_HALF, -MAP_HALF), Vector2(MAP_HALF, -MAP_HALF),
		Vector2(MAP_HALF, MAP_HALF), Vector2(-MAP_HALF, MAP_HALF)])
	var land: Array[PackedVector2Array] = [square]
	for water in deep:
		land = _clip_all(land, water)
	var ground := _combiner("Ground")
	_nav(ground)
	_root.add_child(ground)
	for i in land.size():
		ground.add_child(_prism("Land%d" % i, land[i], -GROUND_DEPTH, GROUND_DEPTH, "ground", false))
	for i in crossings.size():
		ground.add_child(_prism("Crossing%d" % i, crossings[i], -GROUND_DEPTH, GROUND_DEPTH, "road", false))

	# Deep water: visible surface below ground, invisible lip that stops walking but not shots.
	var water := Node3D.new()
	water.name = "DeepWater"
	_root.add_child(water)
	for i in deep.size():
		water.add_child(_prism("Surface%d" % i, deep[i], WATER_SURFACE_Y - 0.05, 0.05, "deep", false))
	var lip := _combiner("Edge")
	lip.visible = false
	water.add_child(lip)
	var pieces: Array[PackedVector2Array] = []
	for w in deep:
		var cut: Array[PackedVector2Array] = [w]
		for c in crossings:
			cut = _clip_all(cut, c)
		pieces.append_array(cut)
	for i in pieces.size():
		lip.add_child(_prism("Lip%d" % i, pieces[i], -GROUND_DEPTH, GROUND_DEPTH + WATER_EDGE_H, "deep", false))

	# Flat overlays (no collision): shallow water, roads, vegetation.
	var overlays := Node3D.new()
	overlays.name = "Overlays"
	_root.add_child(overlays)
	for zone: Dictionary in _map.zones:
		if zone.floor != 0:
			continue
		var kind := ""
		if zone.kind == "flooded" and zone.passable:
			kind = "shallow"
		elif zone.kind == "road" or zone.kind == "vegetation":
			kind = zone.kind
		if kind != "":
			overlays.add_child(_prism(_title(zone.id), _poly(zone), 0.0, OVERLAY_Y[kind], kind, false))

	var blocked := Node3D.new()
	blocked.name = "Blocked"
	_root.add_child(blocked)
	for zone: Dictionary in _map.zones:
		if zone.kind == "blocked":
			var shape := _prism(_title(zone.id), _poly(zone), 0.0, BLOCKED_H.get(zone.id, DEFAULT_BLOCKED_H), "blocked", true)
			_nav(shape)
			blocked.add_child(shape)


# --- buildings -------------------------------------------------------------

func _build_buildings() -> void:
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	_root.add_child(buildings)
	var zones_node := _indoor_zones_node()
	for zone: Dictionary in _map.zones:
		if zone.kind != "indoor" or zone.floor != 0 or zone.id == "shop_in":
			continue
		var poly := _poly(zone)
		var h: float = WALL_H.get(zone.id, DEFAULT_WALL_H)
		var building := Node3D.new()
		building.name = _title(zone.id)
		buildings.add_child(building)
		building.add_child(_prism("Floor", poly, 0.0, OVERLAY_Y.floor, "floor", false))
		var walls := _combiner("Walls")
		_nav(walls)
		building.add_child(walls)
		_add_walls(walls, poly, 0.0, h, DOORS.get(zone.id, []), [])
		building.add_child(_roof("Roof", poly, h, zone.id))
		zones_node.add_child(_indoor_zone(zone.id, [poly], 0.0, h))


func _build_mall() -> void:
	var shop_in := _poly(_zones.shop_in)
	var shop2_in := _poly(_zones.shop2_in)
	var deck := _poly(_zones.shop2_deck)
	var y2: float = _map.floors[1].y
	var stairs: Dictionary = _link("stairs")
	var elevator: Dictionary = _link("elevator")
	var stair_rect := _rect(stairs.rect)
	var el_rect := _rect(elevator.rect)

	var mall := Node3D.new()
	mall.name = "Mall"
	_root.add_child(mall)
	mall.add_child(_prism("Floor1F", shop_in, 0.0, OVERLAY_Y.floor, "floor", false))

	# 1F: outer walls up to the slab, the elevator shaft is closed (the car is stuck on 2F).
	var walls1 := _combiner("Walls1F")
	_nav(walls1)
	mall.add_child(walls1)
	_add_walls(walls1, shop_in, 0.0, y2 - SLAB, DOORS.shop_in, [])
	walls1.add_child(_box("ElevatorShaft1F", el_rect.get_center(), el_rect.size, 0.0, y2 - SLAB, 0.0, "wall"))

	# Stairs: one flight, foot on the south side of the stair rect, top on the north side.
	var stair_x := stair_rect.get_center().x
	var stair_top := Vector2(stair_x, stair_rect.position.y)
	var stair_foot := Vector2(stair_x, stair_rect.end.y)
	var stair := _ramp("Stairs", stair_top, stair_foot, stair_rect.size.x, 0.0, y2, "stairs")
	_nav(stair)
	mall.add_child(stair)
	# Cut the stairs out of the navmesh; the layer-1 link below is the only way across.
	var cut := NavigationObstacle3D.new()
	cut.name = "StairsNavCut"
	cut.position = Vector3(0.0, -0.5, 0.0)
	cut.height = y2 + 1.5
	cut.vertices = _rect_xz(stair_rect)
	cut.affect_navigation_mesh = true
	cut.carve_navigation_mesh = true
	cut.avoidance_enabled = false
	_nav(cut)
	mall.add_child(cut)
	var link := NavigationLink3D.new()
	link.name = "StairsLink"
	link.bidirectional = true
	link.navigation_layers = NAV_LAYER_WALK
	link.start_position = Vector3(stair_foot.x, 0.0, stair_foot.y + 1.0)
	link.end_position = Vector3(stair_top.x, y2, stair_top.y - 1.0)
	mall.add_child(link)

	# Everything above the 1F ceiling. Tagged as a roof of the 1F zone so the 1F stays visible.
	var upper := Node3D.new()
	upper.name = "Upper"
	upper.add_to_group(ROOF_GROUP, true)
	upper.set_meta(ROOF_META, &"shop_in")
	mall.add_child(upper)
	var slab := _combiner("Slab2F")
	_nav(slab)
	upper.add_child(slab)
	slab.add_child(_prism("Indoor", shop2_in, y2 - SLAB, SLAB, "slab", false))
	slab.add_child(_prism("Deck", deck, y2 - SLAB, SLAB, "road", false))
	var hole := _box("StairHole", stair_rect.get_center(), stair_rect.size, y2 - SLAB - 0.2, SLAB + 0.4, 0.0, "slab")
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	slab.add_child(hole)

	var walls2 := _combiner("Walls2F")
	_nav(walls2)
	upper.add_child(walls2)
	# Food court walls. The edge it shares with the deck gets the door to the deck.
	_add_walls(walls2, shop2_in, y2, UPPER_WALL_H, DOORS.shop2_in, [])
	# Elevator shaft on 2F: open door on one side, the trapped person is inside.
	_add_walls(walls2, _rect_poly(el_rect), y2, UPPER_WALL_H, [ELEVATOR_DOOR], [])
	# Stairwell railings on the three open sides (north side is the top of the flight).
	var well := _rect_poly(stair_rect)
	_add_walls(walls2, well, y2, LOW_WALL_H, [], [0])
	# Deck parapets on the outer edges, gap where the hidden ramp starts.
	var ramp_top := _ramp_top(deck)
	_add_walls(walls2, deck, y2, LOW_WALL_H, [[ramp_top.x, ramp_top.y, RAMP_WIDTH + 0.5]], [0])

	upper.add_child(_roof("Roof2F", shop2_in, y2 + UPPER_WALL_H, &"shop2_in"))

	# Hidden loading ramp: from the deck edge down to the dock (map hidden_routes[0].to).
	var route: Dictionary = _map.hidden_routes[0]
	var to := Vector2(route.to.position[0], route.to.position[2])
	var dir := (to - ramp_top).normalized()
	var side := Vector2(-dir.y, dir.x) * RAMP_WIDTH * 0.5
	_ramp_poly = PackedVector2Array([ramp_top + side, to + side, to - side, ramp_top - side])
	var ramp := _ramp("LoadingRamp", ramp_top - dir * 0.15, to, RAMP_WIDTH, 0.0, y2, "road")
	_nav(ramp)
	mall.add_child(ramp)

	var zones_node := _root.get_node("IndoorZones")
	zones_node.add_child(_indoor_zone(&"shop_in", [shop_in], 0.0, y2 - SLAB))
	zones_node.add_child(_indoor_zone(&"shop2_in", [shop2_in], y2, y2 + UPPER_WALL_H))


## Where the ramp line (map hidden route) leaves the deck polygon.
func _ramp_top(deck: PackedVector2Array) -> Vector2:
	var route: Dictionary = _map.hidden_routes[0]
	var from := Vector2(route.from.position[0], route.from.position[2])
	var to := Vector2(route.to.position[0], route.to.position[2])
	for i in deck.size():
		var hit = Geometry2D.segment_intersects_segment(from, to, deck[i], deck[(i + 1) % deck.size()])
		if hit != null:
			return hit
	push_error("Hidden route does not cross the deck edge")
	return from


# --- trees and rocks --------------------------------------------------------

func _build_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = NATURE_SEED
	var keep_out := _keep_out_polygons()
	var keep_out_points := _keep_out_points()
	var routes := _route_segments()
	var clear := func(p: Vector2) -> bool:
		if absf(p.x) > MAP_HALF - CLEAR_EDGE or absf(p.y) > MAP_HALF - CLEAR_EDGE:
			return false
		for poly in keep_out:
			if Geometry2D.is_point_in_polygon(p, poly):
				return false
		for q: Vector3 in keep_out_points:
			if p.distance_to(Vector2(q.x, q.y)) < q.z:
				return false
		for seg: Array in routes:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])) < CLEAR_ROUTE:
				return false
		return true

	var trunks := _combiner("TreeTrunks")
	_nav(trunks)
	_root.add_child(trunks)
	var crowns := Node3D.new()
	crowns.name = "TreeCrowns"
	_root.add_child(crowns)
	var trees := PackedVector2Array()
	for zone: Dictionary in _map.zones:
		if zone.kind != "vegetation" or zone.floor != 0:
			continue
		var poly := _poly(zone)
		var bounds := _bounds(poly)
		var want := int(_area(poly) / (TREE_SPACING * TREE_SPACING * 1.5))
		for attempt in want * 30:
			if want <= 0:
				break
			var p := Vector2(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(bounds.position.y, bounds.end.y))
			if not Geometry2D.is_point_in_polygon(p, poly) or not clear.call(p) or _near(p, trees, TREE_SPACING):
				continue
			trees.append(p)
			want -= 1
	for i in trees.size():
		var p := trees[i]
		var trunk := CSGCylinder3D.new()
		trunk.name = "Trunk%d" % i
		trunk.radius = TREE_TRUNK_RADIUS
		trunk.height = TREE_TRUNK_H
		trunk.sides = 6
		trunk.position = Vector3(p.x, TREE_TRUNK_H * 0.5, p.y)
		trunk.material = _mats.trunk
		trunks.add_child(trunk)
		var crown: CSGShape3D
		var r := TREE_CROWN_R * rng.randf_range(0.8, 1.2)
		if rng.randf() < 0.5:
			var ball := CSGSphere3D.new()
			ball.radius = r
			ball.radial_segments = 8
			ball.rings = 5
			ball.position = Vector3(p.x, TREE_TRUNK_H + r * 0.6, p.y)
			crown = ball
		else:
			var cone := CSGCylinder3D.new()
			cone.cone = true
			cone.radius = r
			cone.height = r * 2.2
			cone.sides = 8
			cone.position = Vector3(p.x, TREE_TRUNK_H * 0.7 + cone.height * 0.5, p.y)
			crown = cone
		crown.name = "Crown%d" % i
		crown.material = _mats.crown
		crowns.add_child(crown)

	# Rocks on any open ground, as low cover (shots pass over, close targets behind take x0.5).
	var cover := _root.get_node("LowCover")
	var rocks := PackedVector2Array()
	var left := ROCK_COUNT
	for attempt in ROCK_COUNT * 60:
		if left <= 0:
			break
		var p := Vector2(rng.randf_range(-MAP_HALF, MAP_HALF), rng.randf_range(-MAP_HALF, MAP_HALF))
		if not clear.call(p) or _near(p, rocks, ROCK_SPACING) or _near(p, trees, CLEAR_PROP):
			continue
		rocks.append(p)
		left -= 1
	for i in rocks.size():
		var rock := CSGSphere3D.new()
		rock.name = "Rock%d" % i
		rock.radius = rng.randf_range(0.6, 1.0)
		rock.radial_segments = 7
		rock.rings = 4
		var squash := rng.randf_range(0.7, 0.9)
		rock.scale = Vector3(rng.randf_range(1.0, 1.4), squash, 1.0)
		rock.rotation.y = rng.randf() * TAU
		rock.position = Vector3(rocks[i].x, rock.radius * squash * 0.3, rocks[i].y)
		rock.material = _mats.rock
		cover.add_child(rock)
	print("nature: %d trees, %d rocks" % [trees.size(), rocks.size()])


## Ground where nothing grows: roads, water, blocked zones, buildings, the mall and the ramp.
func _keep_out_polygons() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for zone: Dictionary in _map.zones:
		if zone.floor != 0:
			continue
		var grow := -1.0
		match zone.kind:
			"road", "flooded", "blocked":
				grow = CLEAR_ROAD
			"indoor":
				grow = CLEAR_BUILDING
		if grow >= 0.0:
			for p in Geometry2D.offset_polygon(_poly(zone), grow):
				out.append(p)
	for p in Geometry2D.offset_polygon(_ramp_poly, CLEAR_BUILDING):
		out.append(p)
	return out


## [x, z, clearance] for 1F markers and greybox props.
func _keep_out_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for m: Dictionary in _map.markers:
		if m.floor == 0:
			out.append(Vector3(m.position[0], m.position[2], CLEAR_MARKER))
	for p: Array in LOW_COVER + BLOCKERS:
		out.append(Vector3(p[1], p[2], CLEAR_PROP + maxf(p[3], p[4]) * 0.5))
	return out


## 1F segments of the demo routes as [Vector2, Vector2].
func _route_segments() -> Array:
	var out := []
	for route: Dictionary in _map.demo_routes:
		var pts: Array = route.points
		for i in range(1, pts.size()):
			if pts[i - 1][1] == 0.0 and pts[i][1] == 0.0:
				out.append([Vector2(pts[i - 1][0], pts[i - 1][2]), Vector2(pts[i][0], pts[i][2])])
	return out


func _near(p: Vector2, others: PackedVector2Array, dist: float) -> bool:
	for o in others:
		if p.distance_to(o) < dist:
			return true
	return false


func _area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in poly.size():
		sum += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(sum) * 0.5


func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


# --- props, bounds, markers --------------------------------------------------

func _build_props() -> void:
	var cover := _combiner("LowCover")
	cover.add_to_group(LOW_COVER_GROUP, true)
	_nav(cover)
	_root.add_child(cover)
	for p: Array in LOW_COVER:
		cover.add_child(_box(p[0], Vector2(p[1], p[2]), Vector2(p[3], p[4]), 0.0, p[5], p[6], "cover"))
	var blockers := _combiner("Props")
	_nav(blockers)
	_root.add_child(blockers)
	for p: Array in BLOCKERS:
		blockers.add_child(_box(p[0], Vector2(p[1], p[2]), Vector2(p[3], p[4]), 0.0, p[5], p[6], "blocked"))


func _build_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "MapBounds"
	body.collision_layer = LAYER_WORLD_BIT
	body.collision_mask = 0
	_root.add_child(body)
	var sides := {
		"North": [Vector3(0, BOUNDS_H * 0.5, -MAP_HALF - 0.5), Vector3(MAP_HALF * 2 + 2, BOUNDS_H, 1)],
		"South": [Vector3(0, BOUNDS_H * 0.5, MAP_HALF + 0.5), Vector3(MAP_HALF * 2 + 2, BOUNDS_H, 1)],
		"West": [Vector3(-MAP_HALF - 0.5, BOUNDS_H * 0.5, 0), Vector3(1, BOUNDS_H, MAP_HALF * 2 + 2)],
		"East": [Vector3(MAP_HALF + 0.5, BOUNDS_H * 0.5, 0), Vector3(1, BOUNDS_H, MAP_HALF * 2 + 2)],
	}
	for side: String in sides:
		var shape := CollisionShape3D.new()
		shape.name = side
		var box := BoxShape3D.new()
		box.size = sides[side][1]
		shape.shape = box
		shape.position = sides[side][0]
		body.add_child(shape)


func _build_markers() -> void:
	var markers := Node3D.new()
	markers.name = "Markers"
	_root.add_child(markers)
	var element: Dictionary = load("res://core/enums.gd").get_script_constant_map().Element
	for m: Dictionary in _map.markers:
		var node := (load(m.scene) as PackedScene).instantiate() as Node3D
		node.name = m.node_name
		node.position = _v3(m.position)
		if m.has("rotation_y_deg"):
			node.rotation.y = deg_to_rad(m.rotation_y_deg)
		var enums: Dictionary = node.get_script().get_script_constant_map()
		for key: String in m.props:
			var value = m.props[key]
			match key:
				"type":
					value = enums.Type[value]
				"container_type":
					value = enums.ContainerType[value]
				"family":
					value = element[value]
				"id", "spawn_id", "recording_id", "required_trait", "loot_table_id":
					value = StringName(value)
				"spawn_tags":
					var tags: Array[StringName] = []
					for t: String in value:
						tags.append(StringName(t))
					value = tags
				"wait_sec", "noise_radius", "zone_radius", "spawn_interval_sec", "wander_radius":
					value = float(value)
				"max_alive":
					value = int(value)
			node.set(key, value)
		if m.has("children"):
			for child_name: String in m.children:
				(node.get_node(child_name) as Node3D).position = _v3(m.children[child_name])
		markers.add_child(node)
		if m.has("children"):
			_root.set_editable_instance(node, true)


# --- navigation --------------------------------------------------------------

func _build_navigation() -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_layers = NAV_LAYER_WALK | NAV_LAYER_WHEELCHAIR
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = LAYER_WORLD_BIT
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = NAV_GROUP
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	# Multiples of the cell size (player capsule: radius 0.35, height 1.8).
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	region.navigation_mesh = nm
	_root.add_child(region)
	return region


func _bake(region: NavigationRegion3D) -> bool:
	var nm := region.navigation_mesh
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, source, _root)
	NavigationServer3D.bake_from_source_geometry_data(nm, source)
	_drop_islands(nm)
	if nm.get_polygon_count() == 0:
		push_error("Navmesh bake produced no polygons")
		return false
	var err := ResourceSaver.save(nm, OUT_NAVMESH, ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Cannot save %s: %s" % [OUT_NAVMESH, error_string(err)])
		return false
	nm.take_over_path(OUT_NAVMESH)
	return true


## Recast also walks on top of buses, shelves and cover. Keep only the polygons connected to a
## player spawn (2F and the dock join through the ramp, the stairs through the link).
func _drop_islands(nm: NavigationMesh) -> void:
	var verts := nm.get_vertices()
	var parent := range(verts.size())
	var find := func(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i
	var polys: Array[PackedInt32Array] = []
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		polys.append(poly)
		for j in range(1, poly.size()):
			parent[find.call(poly[j])] = find.call(poly[0])
	var keep := {}
	for m: Dictionary in _map.markers:
		if m["class"] == "PlayerSpawn":
			var seed := _v3(m.position)
			var best := 0
			for i in verts.size():
				if verts[i].distance_to(seed) < verts[best].distance_to(seed):
					best = i
			keep[find.call(best)] = true
	var remap := {}
	var kept_verts := PackedVector3Array()
	var kept_polys: Array[PackedInt32Array] = []
	for poly in polys:
		if not keep.has(find.call(poly[0])):
			continue
		var out := PackedInt32Array()
		for v in poly:
			if not remap.has(v):
				remap[v] = kept_verts.size()
				kept_verts.append(verts[v])
			out.append(remap[v])
		kept_polys.append(out)
	print("navmesh: kept %d of %d polygons" % [kept_polys.size(), polys.size()])
	nm.clear_polygons()
	nm.vertices = kept_verts
	for poly in kept_polys:
		nm.add_polygon(poly)


# --- builders ----------------------------------------------------------------

func _indoor_zones_node() -> Node3D:
	var node := Node3D.new()
	node.name = "IndoorZones"
	_root.add_child(node)
	return node


## B-04 IndoorZone (trigger layer, sees the player) covering the interior.
func _indoor_zone(id: StringName, polys: Array, y0: float, y1: float) -> Area3D:
	var area := Area3D.new()
	area.set_script(load(INDOOR_ZONE_SCRIPT))
	area.name = "IndoorZone_%s" % id
	area.set(&"building_id", id)
	area.collision_layer = LAYER_TRIGGER_BIT
	area.collision_mask = LAYER_PLAYER_BIT
	area.monitorable = false
	var n := 0
	for poly: PackedVector2Array in polys:
		for part in Geometry2D.decompose_polygon_in_convex(poly):
			var points := PackedVector3Array()
			for p in part:
				points.append(Vector3(p.x, y0, p.y))
				points.append(Vector3(p.x, y1, p.y))
			var shape := ConvexPolygonShape3D.new()
			shape.points = points
			var cs := CollisionShape3D.new()
			cs.name = "Shape%d" % n
			cs.shape = shape
			area.add_child(cs)
			n += 1
	return area


func _roof(node_name: String, poly: PackedVector2Array, y: float, id: StringName) -> CSGPolygon3D:
	var roof := _prism(node_name, poly, y, ROOF_T, "roof", false)
	roof.add_to_group(ROOF_GROUP, true)
	roof.set_meta(ROOF_META, id)
	return roof


## Walls on every edge of a closed polygon with door gaps. skip_edges: edge indices left open.
func _add_walls(parent: Node, poly: PackedVector2Array, y: float, h: float,
		doors: Array, skip_edges: Array) -> void:
	var count := poly.size()
	var gaps := {}
	for door: Array in doors:
		var p := Vector2(door[0], door[1])
		var best := -1
		var best_dist := INF
		for i in count:
			var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
			if q.distance_to(p) < best_dist:
				best_dist = q.distance_to(p)
				best = i
		if best_dist > 1.0:
			push_error("Door %s is %.1fm from the nearest wall" % [p, best_dist])
		var a := poly[best]
		var t := (Geometry2D.get_closest_point_to_segment(p, a, poly[(best + 1) % poly.size()]) - a).length()
		gaps.get_or_add(best, []).append(Vector2(t - door[2] * 0.5, t + door[2] * 0.5))
	for i in count:
		if i in skip_edges:
			continue
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var length := a.distance_to(b)
		var spans := [Vector2(-WALL_T * 0.5, length + WALL_T * 0.5)]
		var edge_gaps: Array = gaps.get(i, [])
		edge_gaps.sort_custom(func(g1: Vector2, g2: Vector2) -> bool: return g1.x < g2.x)
		for g: Vector2 in edge_gaps:
			var last: Vector2 = spans.pop_back()
			spans.append(Vector2(last.x, g.x))
			spans.append(Vector2(g.y, last.y))
		var dir := (b - a) / length
		var angle := rad_to_deg(atan2(-dir.y, dir.x))
		for s: Vector2 in spans:
			if s.y - s.x < 0.05:
				continue
			var center := a + dir * (s.x + s.y) * 0.5
			var wall := _box("Wall%d_%d" % [parent.get_child_count(), i], center, Vector2(s.y - s.x, WALL_T), y, h, angle,
				"wall")
			parent.add_child(wall)


## Solid wedge from a top edge (height h above base y) down to the foot. Width across.
func _ramp(node_name: String, top: Vector2, foot: Vector2, width: float, y: float, h: float, mat: String) -> CSGPolygon3D:
	var length := top.distance_to(foot)
	var dir := (foot - top) / length
	var shape := CSGPolygon3D.new()
	shape.name = node_name
	# Side profile in local XY (x along the slope), extruded along -Z across the width.
	shape.polygon = PackedVector2Array([Vector2(0, 0), Vector2(length, 0), Vector2(0, h)])
	shape.depth = width
	var x := Vector3(dir.x, 0.0, dir.y)
	var z := x.cross(Vector3.UP)
	shape.transform = Transform3D(Basis(x, Vector3.UP, z), Vector3(top.x, y, top.y) + z * width * 0.5)
	shape.use_collision = true
	shape.collision_layer = LAYER_WORLD_BIT
	shape.collision_mask = 0
	shape.material = _mats[mat]
	return shape


## Flat polygon (map x, z) extruded upward from y by height.
func _prism(node_name: String, poly: PackedVector2Array, y: float, height: float, mat: String,
		collide: bool) -> CSGPolygon3D:
	var shape := CSGPolygon3D.new()
	shape.name = node_name
	shape.polygon = poly
	shape.depth = height
	shape.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	shape.position = Vector3(0.0, y, 0.0)
	shape.material = _mats[mat]
	if collide:
		shape.use_collision = true
		shape.collision_layer = LAYER_WORLD_BIT
		shape.collision_mask = 0
	return shape


func _box(node_name: String, center: Vector2, size: Vector2, y: float, h: float, rot_deg: float,
		mat: String) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = node_name
	box.size = Vector3(size.x, h, size.y)
	box.position = Vector3(center.x, y + h * 0.5, center.y)
	box.rotation.y = deg_to_rad(rot_deg)
	box.material = _mats[mat]
	return box


func _combiner(node_name: String) -> CSGCombiner3D:
	var node := CSGCombiner3D.new()
	node.name = node_name
	node.use_collision = true
	node.collision_layer = LAYER_WORLD_BIT
	node.collision_mask = 0
	return node


func _nav(node: Node) -> void:
	node.add_to_group(NAV_GROUP, true)


# --- geometry helpers --------------------------------------------------------

func _poly(zone: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in zone.polygon:
		out.append(Vector2(p[0], p[1]))
	return out


func _rect(r: Dictionary) -> Rect2:
	return Rect2(r.x, r.z, r.w, r.d)


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _rect_xz(r: Rect2) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in _rect_poly(r):
		out.append(Vector3(p.x, 0.0, p.y))
	return out


func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _link(kind: String) -> Dictionary:
	for link: Dictionary in _map.floor_links:
		if link.kind == kind:
			return link
	push_error("No floor link %s" % kind)
	return {}


func _overlaps_any(poly: PackedVector2Array, others: Array[PackedVector2Array]) -> bool:
	for o in others:
		if not Geometry2D.intersect_polygons(poly, o).is_empty():
			return true
	return false


## Clips every polygon by `cutter`. Fails loudly on holes (CSGPolygon3D cannot have them).
func _clip_all(polys: Array[PackedVector2Array], cutter: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for p in polys:
		var parts := Geometry2D.clip_polygons(p, cutter)
		for part in parts:
			for other in parts:
				if other != part and Geometry2D.is_point_in_polygon(part[0], other):
					push_error("Polygon clip made a hole, split the cutter")
			out.append(part)
	return out


func _title(id: String) -> String:
	return id.to_pascal_case()


func _set_owners(node: Node) -> void:
	for child in node.get_children():
		child.owner = _root
		if child.scene_file_path.is_empty():
			_set_owners(child)


func _count(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _count(child)
	return n
