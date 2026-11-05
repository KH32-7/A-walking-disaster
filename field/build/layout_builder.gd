extends SceneTree
## Shared field layout generator (B-12, B-24). A region's build script extends this file, fills the
## per-region settings below in _init() and adds what only that map has in _build_structures().
##
##   godot --headless --path . --script res://levels/field/<id>/build/build_layout.gd
##
## Input: the region's confirmed map file (planning board export, schema "awd-field-map/1").
## Coordinates are Godot meters, origin at the map center, +X east, +Z south.
## The map file has zones, floor links and markers. What it does not say is decided in the region
## script: wall heights, doors, greybox props, extra nests and loot, clutter kits.
## Output: levels/field/<id>/layout.tscn and its navmesh. Hand edits to layout.tscn are lost on a re-run.
##
## MAP_SCALE stretches the map file's floor plan (x, z) without editing the confirmed file:
## zones, marker and prop positions, door positions, floor-link positions and hidden route ends.
## Heights, door widths, prop sizes and gameplay radii in marker props (zone_radius, noise_radius,
## wander_radius, radius) are design values and stay as they are.
##
## Density rules (user feedback 2026-11-05), the same on every map: nest interval and cap
## multipliers, extra nests, one indoor LootSpot per LOOT_AREA_PER_SPOT m2, landmark loot,
## rocks and clutter clusters per unscaled map area.
##
## Navigation layers (agreed with B-10): 1 = everyone on foot, 2 = wheelchair.

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

## Floor plan scale over the map file, every region. User feedback 2026-11-05: x1 felt cramped,
## x2 too big and empty, so x1.5 (0.75 of x2).
const MAP_SCALE := 1.5
const MAP_HALF := 75.0 * MAP_SCALE
const GROUND_DEPTH := 1.0
const SLAB := 0.3
const WALL_T := 0.3
const ROOF_T := 0.2
const DEFAULT_WALL_H := 3.0
## Railings, deck parapets and the deep-water lip stay under the 1.0m shot height (B-06).
const LOW_WALL_H := 0.9
const WATER_EDGE_H := 0.8
const WATER_SURFACE_Y := -0.3
const DEFAULT_BLOCKED_H := 3.0
const BOUNDS_H := 4.0

## Trees in vegetation zones, rocks on open ground. Seeded, so a re-run plants the same map.
## Rocks are low cover. Nothing grows on roads, water, near buildings, markers, props or demo routes.
const TREE_SPACING := 5.0
const TREE_TRUNK_RADIUS := 0.3
const TREE_TRUNK_H := 2.4
const TREE_CROWN_R := 1.6
## Rocks on the unscaled map; the count grows with the area so the density stays.
const ROCK_COUNT := 40
const ROCK_SPACING := 6.0
const CLEAR_MARKER := 3.0
const CLEAR_ROUTE := 2.5
const CLEAR_PROP := 3.0
const CLEAR_BUILDING := 2.5
const CLEAR_ROAD := 1.0
const CLEAR_EDGE := 3.0

## Monster density over the map file's nest values (user feedback 2026-11-05: more monsters).
## Applied to every MonsterNest, map file and extra nests alike. 04 design: 3 min, region cap 40.
const NEST_INTERVAL_MULT := 2.0 / 3.0 ## spawn_interval_sec 180 -> 120
const NEST_MAX_MULT := 1.5 ## max_alive rounded up: 6 -> 9, 5 -> 8
## Map file nest interval before NEST_INTERVAL_MULT, also used for extra nests.
const NEST_BASE_INTERVAL := 180.0
## Nest LootSpot offset from its nest, map file coordinates.
const NEST_LOOT_OFFSET := Vector2(2.0, 0.0)

## Extra LootSpots (user feedback 2026-11-05: more to loot). The map file's spots stay as they are.
## Indoor zones get one spot per LOOT_AREA_PER_SPOT m2 of scaled floor (at least loot_min),
## counting the map file's spots, along the walls. Kinds cycle through zone_loot (default DRAWER).
const LOOT_AREA_PER_SPOT := 300.0
const LOOT_WALL_INSET := 1.0
const LOOT_SPACING := 4.0
const LOOT_CLEAR_DOOR := 2.5

## Greybox clutter on open ground so the map is not empty (user feedback 2026-11-05).
## Seeded clusters (clutter_kits). Pieces up to LOW_COVER_MAX_H are low cover, taller ones block.
## Clusters keep clear of roads, water, buildings, vegetation, markers, doors, extract points
## and the demo routes. Clusters on the unscaled map; the count grows with the area like the rocks.
const CLUTTER_CLUSTERS := 26
const CLUTTER_SPACING := 14.0
const CLUTTER_CLEAR_ROUTE := 4.0
const CLUTTER_CLEAR_EXTRACT := 10.0
const CLUTTER_CLEAR_DOOR := 5.0
const LOW_COVER_MAX_H := 1.2

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

# --- per-region settings, set in the region script's _init() ---------------------------
var map_path := ""
var out_scene := ""
var out_navmesh := ""
var root_name := ""
## zone id -> wall height, default DEFAULT_WALL_H.
var wall_h := {}
## zone id -> blocked zone height, default DEFAULT_BLOCKED_H.
var blocked_h := {}
## zone id -> [[x, z, width], ...] in map file coordinates (scaled on use, width is not).
## The point snaps to the nearest wall edge.
var zone_doors := {}
## Greybox props not in the map file. [name, x, z, size_x, size_z, height, rot_y_deg], x, z in map
## file coordinates (scaled on use), sizes are real object sizes. cover_props: shots pass over.
var cover_props := []
var blocker_props := []
## Nests not in the map file. [id, family, x, z, max_alive, wander_radius], x, z in map file
## coordinates. Each gets a MONSTER_NEST LootSpot next to it like the map file nests.
var extra_nests := []
## Indoor zone id -> minimum LootSpots, default 1.
var loot_min := {}
## Indoor zone id -> container kinds for its extra LootSpots, default ["DRAWER"].
var zone_loot := {}
## Outdoor landmark zone id -> container kinds added on open ground inside the landmark.
var landmark_loot := {}
## [kit, weight, pieces], pieces: [name, local_x, local_z, size_x, size_z, height, rot_y_deg].
var clutter_kits := []
var nature_seed := 0
var loot_seed := 0
var clutter_seed := 0
## Indoor zones the region script builds in _build_structures() instead of _build_buildings().
var custom_buildings: Array[String] = []

var _map: Dictionary
var _zones := {}
var _mats := {}
var _root: Node3D
## Ground that _build_structures() takes (mall ramp, park underpass). Nothing grows on it.
var _structure_keep_out: Array[PackedVector2Array] = []
## Indoor floor where no extra LootSpot goes (mall stairs and elevator shaft).
var _loot_exclude: Array[Rect2] = []
## Markers made here, not in the map file: {scene, node_name, pos: Vector3, rot: float, props}.
var _extra_markers: Array[Dictionary] = []
## Taken ground as (x, z, radius): extra markers and clutter clusters. Rocks and trees keep off.
var _taken: Array[Vector3] = []


func _initialize() -> void:
	var text := FileAccess.get_file_as_string(map_path)
	_map = JSON.parse_string(text)
	if _map.is_empty():
		push_error("Cannot read %s" % map_path)
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
	_root.name = root_name
	_build_terrain()
	_build_buildings()
	_build_structures()
	_build_props()
	_plan_extra_markers()
	_build_clutter()
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
		err = ResourceSaver.save(packed, out_scene)
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
			var shape := _prism(_title(zone.id), _poly(zone), 0.0, blocked_h.get(zone.id, DEFAULT_BLOCKED_H), "blocked", true)
			_nav(shape)
			blocked.add_child(shape)


# --- buildings -------------------------------------------------------------

func _build_buildings() -> void:
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	_root.add_child(buildings)
	var zones_node := _indoor_zones_node()
	for zone: Dictionary in _map.zones:
		if zone.kind != "indoor" or zone.floor != 0 or zone.id in custom_buildings:
			continue
		var poly := _poly(zone)
		var h: float = wall_h.get(zone.id, DEFAULT_WALL_H)
		var building := Node3D.new()
		building.name = _title(zone.id)
		buildings.add_child(building)
		building.add_child(_prism("Floor", poly, 0.0, OVERLAY_Y.floor, "floor", false))
		var walls := _combiner("Walls")
		_nav(walls)
		building.add_child(walls)
		_add_walls(walls, poly, 0.0, h, _doors(zone.id), [])
		building.add_child(_roof("Roof", poly, h, zone.id))
		zones_node.add_child(_indoor_zone(zone.id, [poly], 0.0, h))


## Region hook: structures only this map has (mall 2F and ramp, park underpass). Runs after
## _build_buildings(), before the props. Fill _structure_keep_out and _loot_exclude here.
func _build_structures() -> void:
	pass


## Region hook: called for every marker after its map file props and children are set.
func _marker_built(_node: Node3D, _m: Dictionary) -> void:
	pass


# --- extra markers and clutter -----------------------------------------------

## Extra nests (extra_nests) and LootSpots (indoor zones by area, landmarks), see the constants.
func _plan_extra_markers() -> void:
	var nest_scene := _scene_of("MonsterNest")
	var loot_scene := _scene_of("LootSpot")
	for n: Array in extra_nests:
		var at := Vector2(n[2], n[3]) * MAP_SCALE
		_add_extra(nest_scene, "MonsterNest_%s" % n[0], Vector3(at.x, 0.0, at.y), 0.0, {"family": n[1],
			"spawn_interval_sec": NEST_BASE_INTERVAL, "max_alive": n[4], "wander_radius": n[5]})
		var spot := (Vector2(n[2], n[3]) + NEST_LOOT_OFFSET) * MAP_SCALE
		_add_extra(loot_scene, "LootSpot_loot_%s" % n[0], Vector3(spot.x, 0.0, spot.y), 0.0,
			{"container_type": "MONSTER_NEST", "loot_table_id": ""})

	var rng := RandomNumberGenerator.new()
	rng.seed = loot_seed
	var added := 0
	for zone: Dictionary in _map.zones:
		if zone.kind != "indoor":
			continue
		var poly := _poly(zone)
		var have := 0
		for m: Dictionary in _map.markers:
			if m["class"] == "LootSpot" and m.floor == zone.floor \
					and Geometry2D.is_point_in_polygon(_xz(m.position), poly):
				have += 1
		var want: int = maxi(loot_min.get(zone.id, 1), ceili(_area(poly) / LOOT_AREA_PER_SPOT)) - have
		var kinds: Array = zone_loot.get(zone.id, ["DRAWER"])
		var ring := _largest(Geometry2D.offset_polygon(poly, -LOOT_WALL_INSET))
		var doors := _doors(zone.id)
		var placed := 0
		for attempt in want * 50:
			if placed >= want:
				break
			var hit := _point_on_ring(ring, rng.randf())
			var p: Vector2 = hit[0]
			if not Geometry2D.is_point_in_polygon(p, poly) or _loot_excluded(p) \
					or _in_prop(p, 1.0) or _near_door(p, doors, LOOT_CLEAR_DOOR) \
					or _near_marker(p, zone.floor, LOOT_SPACING):
				continue
			var dir: Vector2 = hit[1]
			placed += 1
			_add_extra(loot_scene, "LootSpot_loot_%s_%d" % [zone.id, placed],
				Vector3(p.x, _floor_y(zone.floor), p.y), atan2(-dir.y, dir.x),
				{"container_type": kinds[(placed - 1) % kinds.size()], "loot_table_id": ""})
		if placed < want:
			push_warning("Loot: %s got %d of %d extra spots" % [zone.id, placed, want])
		added += placed

	var keep_out := _keep_out_polygons()
	var routes := _route_segments()
	for id: String in landmark_loot:
		var poly := _largest(Geometry2D.offset_polygon(_poly(_zones[id]), -2.0))
		var bounds := _bounds(poly)
		var placed := 0
		for kind: String in landmark_loot[id]:
			for attempt in 200:
				var p := Vector2(rng.randf_range(bounds.position.x, bounds.end.x),
					rng.randf_range(bounds.position.y, bounds.end.y))
				if not Geometry2D.is_point_in_polygon(p, poly) or not _open(p, keep_out, routes, CLEAR_ROUTE) \
						or _in_prop(p, 1.5) or _near_marker(p, 0, LOOT_SPACING):
					continue
				placed += 1
				_add_extra(loot_scene, "LootSpot_loot_%s_%d" % [id, placed], Vector3(p.x, 0.0, p.y),
					rng.randf() * TAU, {"container_type": kind, "loot_table_id": ""})
				break
		if placed < landmark_loot[id].size():
			push_warning("Loot: %s got %d of %d spots" % [id, placed, landmark_loot[id].size()])
		added += placed
	print("extra markers: %d nests, %d loot spots" % [extra_nests.size(), extra_nests.size() + added])


## Seeded clutter clusters on open ground (clutter_kits).
func _build_clutter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = clutter_seed
	var keep_out := _keep_out_polygons()
	for zone: Dictionary in _map.zones:
		if zone.kind == "vegetation" and zone.floor == 0:
			keep_out.append(_poly(zone))
	var routes := _route_segments()
	var points := _keep_out_points()
	var extracts := PackedVector2Array()
	for m: Dictionary in _map.markers:
		if m["class"] == "ExtractPoint":
			extracts.append(_xz(m.position))
	var doors := []
	for id: String in zone_doors:
		if _zones[id].floor == 0:
			doors.append_array(_doors(id))
	var total_weight := 0
	for kit: Array in clutter_kits:
		total_weight += kit[1]
	var cover := _root.get_node("LowCover")
	var blockers := _root.get_node("Props")
	var centers := PackedVector2Array()
	var want := roundi(CLUTTER_CLUSTERS * MAP_SCALE * MAP_SCALE)
	var pieces := 0
	for attempt in want * 80:
		if centers.size() >= want:
			break
		var kit := _pick_kit(rng.randi_range(0, total_weight - 1))
		var c := Vector2(rng.randf_range(-MAP_HALF, MAP_HALF), rng.randf_range(-MAP_HALF, MAP_HALF))
		var yaw := rng.randf() * TAU
		var radius := _kit_radius(kit[2])
		if _near(c, centers, CLUTTER_SPACING) or _near(c, extracts, CLUTTER_CLEAR_EXTRACT + radius) \
				or _near_door(c, doors, CLUTTER_CLEAR_DOOR + radius) \
				or not _open(c, keep_out, routes, CLUTTER_CLEAR_ROUTE + radius) or _near_points(c, points, radius):
			continue
		var fits := true
		for piece: Array in kit[2]:
			for corner in _piece_corners(c, yaw, piece):
				if not _open(corner, keep_out, [], 0.0):
					fits = false
		if not fits:
			continue
		centers.append(c)
		_taken.append(Vector3(c.x, c.y, radius + CLEAR_PROP))
		for i in kit[2].size():
			var piece: Array = kit[2][i]
			var at := c + Vector2(piece[1], piece[2]).rotated(-yaw)
			var low: bool = piece[5] <= LOW_COVER_MAX_H
			var box := _box("Clutter%d_%s%d" % [centers.size(), piece[0], i], at, Vector2(piece[3], piece[4]), 0.0,
				piece[5], rad_to_deg(yaw) + piece[6], "cover" if low else "blocked")
			(cover if low else blockers).add_child(box)
			pieces += 1
	print("clutter: %d clusters, %d pieces" % [centers.size(), pieces])


func _add_extra(scene: String, node_name: String, pos: Vector3, rot: float, props: Dictionary) -> void:
	_extra_markers.append({"scene": scene, "node_name": node_name, "pos": pos, "rot": rot, "props": props})
	_taken.append(Vector3(pos.x, pos.z, CLEAR_MARKER))


func _scene_of(marker_class: String) -> String:
	for m: Dictionary in _map.markers:
		if m["class"] == marker_class:
			return m.scene
	push_error("No %s in the map file" % marker_class)
	return ""


## On the map, off every keep-out polygon and at least route_clear from the demo routes.
func _open(p: Vector2, keep_out: Array[PackedVector2Array], routes: Array, route_clear: float) -> bool:
	if absf(p.x) > MAP_HALF - CLEAR_EDGE or absf(p.y) > MAP_HALF - CLEAR_EDGE:
		return false
	for poly in keep_out:
		if Geometry2D.is_point_in_polygon(p, poly):
			return false
	for seg: Array in routes:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])) < route_clear:
			return false
	return true


## Closer than q.z + pad to any (x, z, radius) point.
func _near_points(p: Vector2, points: Array[Vector3], pad: float) -> bool:
	for q in points:
		if p.distance_to(Vector2(q.x, q.y)) < q.z + pad:
			return true
	return false


## Within `margin` of a cover_props or blocker_props box (rotation included).
func _in_prop(p: Vector2, margin: float) -> bool:
	for b: Array in cover_props + blocker_props:
		var local := (p - Vector2(b[1], b[2]) * MAP_SCALE).rotated(deg_to_rad(b[6]))
		if absf(local.x) <= b[3] * 0.5 + margin and absf(local.y) <= b[4] * 0.5 + margin:
			return true
	return false


## doors: [[x, z, width], ...] already scaled.
func _near_door(p: Vector2, doors: Array, clear: float) -> bool:
	for d: Array in doors:
		if p.distance_to(Vector2(d[0], d[1])) < clear + d[2] * 0.5:
			return true
	return false


## Closer than dist to any map file or extra marker on the same floor.
func _near_marker(p: Vector2, floor_index: int, dist: float) -> bool:
	for m: Dictionary in _map.markers:
		if m.floor == floor_index and p.distance_to(_xz(m.position)) < dist:
			return true
	for m: Dictionary in _extra_markers:
		var on_floor := 0 if m.pos.y < 1.0 else 1
		if on_floor == floor_index and p.distance_to(Vector2(m.pos.x, m.pos.z)) < dist:
			return true
	return false


## [point, edge direction] at fraction u of the ring's perimeter.
func _point_on_ring(ring: PackedVector2Array, u: float) -> Array:
	var total := 0.0
	for i in ring.size():
		total += ring[i].distance_to(ring[(i + 1) % ring.size()])
	var left := u * total
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var length := a.distance_to(b)
		if left <= length or i == ring.size() - 1:
			return [a.lerp(b, clampf(left / length, 0.0, 1.0)), (b - a) / length]
		left -= length
	return [ring[0], Vector2.RIGHT]


func _largest(polys: Array[PackedVector2Array]) -> PackedVector2Array:
	var best := PackedVector2Array()
	for p in polys:
		if best.is_empty() or _area(p) > _area(best):
			best = p
	return best


func _pick_kit(roll: int) -> Array:
	for kit: Array in clutter_kits:
		roll -= kit[1]
		if roll < 0:
			return kit
	return clutter_kits[0]


func _kit_radius(pieces: Array) -> float:
	var r := 0.0
	for piece: Array in pieces:
		r = maxf(r, Vector2(piece[1], piece[2]).length() + Vector2(piece[3], piece[4]).length() * 0.5)
	return r


func _piece_corners(c: Vector2, yaw: float, piece: Array) -> PackedVector2Array:
	var at := c + Vector2(piece[1], piece[2]).rotated(-yaw)
	var turn := yaw + deg_to_rad(piece[6])
	var half := Vector2(piece[3], piece[4]) * 0.5
	var out := PackedVector2Array()
	for s: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		out.append(at + (half * s).rotated(-turn))
	return out


# --- trees and rocks --------------------------------------------------------

func _build_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = nature_seed
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
	var left := roundi(ROCK_COUNT * MAP_SCALE * MAP_SCALE)
	for attempt in left * 60:
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


## Ground where nothing grows: roads, water, blocked zones, buildings and _structure_keep_out.
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
	for poly in _structure_keep_out:
		for p in Geometry2D.offset_polygon(poly, CLEAR_BUILDING):
			out.append(p)
	return out


## [x, z, clearance] for 1F markers and greybox props.
func _keep_out_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for m: Dictionary in _map.markers:
		if m.floor == 0:
			var at := _xz(m.position)
			out.append(Vector3(at.x, at.y, CLEAR_MARKER))
	for p: Array in cover_props + blocker_props:
		var at := Vector2(p[1], p[2]) * MAP_SCALE
		out.append(Vector3(at.x, at.y, CLEAR_PROP + maxf(p[3], p[4]) * 0.5))
	out.append_array(_taken)
	return out


## 1F segments of the demo routes as [Vector2, Vector2].
func _route_segments() -> Array:
	var out := []
	for route: Dictionary in _map.demo_routes:
		var pts: Array = route.points
		for i in range(1, pts.size()):
			if pts[i - 1][1] == 0.0 and pts[i][1] == 0.0:
				out.append([_xz(pts[i - 1]), _xz(pts[i])])
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
	for p: Array in cover_props:
		cover.add_child(_box(p[0], Vector2(p[1], p[2]) * MAP_SCALE, Vector2(p[3], p[4]), 0.0, p[5], p[6], "cover"))
	var blockers := _combiner("Props")
	_nav(blockers)
	_root.add_child(blockers)
	for p: Array in blocker_props:
		blockers.add_child(_box(p[0], Vector2(p[1], p[2]) * MAP_SCALE, Vector2(p[3], p[4]), 0.0, p[5], p[6], "blocked"))


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
	for m: Dictionary in _map.markers:
		var node := _marker(m)
		node.position = _v3(m.position)
		if m.has("rotation_y_deg"):
			node.rotation.y = deg_to_rad(m.rotation_y_deg)
		if m.has("children"):
			for child_name: String in m.children:
				(node.get_node(child_name) as Node3D).position = _v3(m.children[child_name])
		markers.add_child(node)
		if m.has("children"):
			_root.set_editable_instance(node, true)
		_marker_built(node, m)
	for m: Dictionary in _extra_markers:
		var node := _marker(m)
		node.position = m.pos
		node.rotation.y = m.rot
		markers.add_child(node)


## Marker scene instance with the map file's props (enum names, ids) converted.
func _marker(m: Dictionary) -> Node3D:
	var element: Dictionary = load("res://core/enums.gd").get_script_constant_map().Element
	var node := (load(m.scene) as PackedScene).instantiate() as Node3D
	node.name = m.node_name
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
			"id", "spawn_id", "recording_id", "required_trait", "loot_table_id", "boss_id":
				value = StringName(value)
			"spawn_tags":
				var tags: Array[StringName] = []
				for t: String in value:
					tags.append(StringName(t))
				value = tags
			"wait_sec", "noise_radius", "zone_radius", "wander_radius", "radius":
				value = float(value)
			"spawn_interval_sec":
				value = float(value) * NEST_INTERVAL_MULT
			"max_alive":
				value = ceili(int(value) * NEST_MAX_MULT)
		node.set(key, value)
	return node


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
	var err := ResourceSaver.save(nm, out_navmesh, ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Cannot save %s: %s" % [out_navmesh, error_string(err)])
		return false
	nm.take_over_path(out_navmesh)
	return true


## Recast also walks on top of buses, shelves and cover. Keep only the polygons connected to a
## player spawn (mall: 2F and the dock join through the ramp, the stairs through the link).
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
		out.append(Vector2(p[0], p[1]) * MAP_SCALE)
	return out


## Floor link rect: the center moves with the plan, the size (shaft, stair flight) stays.
func _rect(r: Dictionary) -> Rect2:
	var size := Vector2(r.w, r.d)
	return Rect2((Vector2(r.x, r.z) + size * 0.5) * MAP_SCALE - size * 0.5, size)


## Doors of a zone (zone_doors), scaled. Widths stay.
func _doors(id: String) -> Array:
	var out := []
	for door: Array in zone_doors.get(id, []):
		out.append([door[0] * MAP_SCALE, door[1] * MAP_SCALE, door[2]])
	return out


func _floor_y(floor_index: int) -> float:
	return _map.floors[floor_index].y


func _loot_excluded(p: Vector2) -> bool:
	for r in _loot_exclude:
		if r.has_point(p):
			return true
	return false


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _rect_xz(r: Rect2) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in _rect_poly(r):
		out.append(Vector3(p.x, 0.0, p.y))
	return out


## Map file [x, y, z] -> scaled plan position, height unchanged.
func _v3(a: Array) -> Vector3:
	return Vector3(a[0] * MAP_SCALE, a[1], a[2] * MAP_SCALE)


## Map file [x, y, z] -> scaled plan point (x, z).
func _xz(a: Array) -> Vector2:
	return Vector2(a[0], a[2]) * MAP_SCALE


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
