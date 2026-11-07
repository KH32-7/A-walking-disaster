extends "res://field/build/layout_builder.gd"
## Builds levels/field/hospital/layout.tscn from the map file.
##
##   godot --headless --path . --script res://levels/field/hospital/build/build_layout.gd
##
## Source: build/hospital_map.json (Claude's design, 2026-11-07, the user left the design to Claude).
## One floor plus a tunnel under the ground. The shared generator (field/build/layout_builder.gd) does
## the terrain, the buildings (build/kit_buildings.gd plans), props, extra markers, clutter, nature,
## markers and the navmesh. This file has the hospital's settings, the tunnel (_build_structures),
## the quarantine wall drawn with army barriers (_kit_blocked) and the special places (_build_pois).
## Re-run after the map file or the plans change. Hand edits to layout.tscn are lost on a re-run.
##
## Tunnel (map floor_links kind "tunnel"): a straight passage under the ground from the ambulance bay
## (From, south mouth) to the back yard (To, north mouth), like the park underpass but always open.
## A ramp at each mouth goes down to the floor (wheelchairs pass). The ground over the flat part is a
## roof (IndoorZone "tunnel") so the camera sees the player inside. A shadow-only slab stays over it
## when that roof hides, so no sun reaches the floor; red emergency lights (buildings.tscn) are all
## the light there is.

const MAP_PATH := "res://levels/field/hospital/build/hospital_map.json"
const OUT_SCENE := "res://levels/field/hospital/layout.tscn"
const OUT_NAVMESH := "res://levels/field/hospital/layout_navmesh.res"
const OUT_KIT := "res://levels/field/hospital/buildings.tscn"
const OUT_SPLAT := "res://levels/field/hospital/ground_splat.res"
const KitBuildings := preload("res://levels/field/hospital/build/kit_buildings.gd")

## Quarantine wall: army hesco barriers (1.65 m) with a little headroom, full cover.
const BLOCKED_H := {"wall_w1": 2.2, "wall_w2": 2.2, "wall_e1": 2.2, "wall_e2": 2.2}
## The wall carries on over the tunnel's roof between wall_e1 and wall_e2 (a blocked zone there
## would stand on the open tunnel). x, z in map file coordinates.
const BLOCKERS := [["TunnelFence", 78.0 / MAP_SCALE, -52.0 / MAP_SCALE, 9.4, 1.4, 2.2, 0.0]]
const KIT_COVER := {"TunnelFence": "hesco"}

const NATURE_SEED := 20261111
## Danger 3, families WATER and LIGHT (data/regions/hospital.tres). Map file coordinates.
## None on the main gate route or near an extract point: back yard east of the morgue, between the
## annex and the wall, the east woods, the courtyard's east half (on the way to the surgery wing).
const EXTRA_NESTS := [
	["nest_yard", "LIGHT", -36.0 / MAP_SCALE, -78.0 / MAP_SCALE, 4, 10.0],
	["nest_annex", "WATER", -84.0 / MAP_SCALE, -47.0 / MAP_SCALE, 3, 8.0],
	["nest_woods_e", "WATER", 100.0 / MAP_SCALE, 10.0 / MAP_SCALE, 4, 10.0],
	["nest_court", "LIGHT", 16.0 / MAP_SCALE, -14.0 / MAP_SCALE, 3, 8.0],
]

const LOOT_SEED := 20261112
const LOOT_MIN := {"main_in": 12, "er_in": 4, "surg_in": 4}
## 02: medicine cabinets are common in the hospital.
const ZONE_LOOT := {
	"main_in": ["MEDICINE", "DRAWER"],
	"er_in": ["MEDICINE"],
	"surg_in": ["MEDICINE", "TOOLBOX", "MEDICINE"],
	"morgue_in": ["DRAWER", "MEDICINE"],
	"boiler_in": ["TOOLBOX"],
	"annex_in": ["MEDICINE", "DRAWER"],
	"guard_in": ["DRAWER"],
}
## Open ground only (the bay and the car park are roads; _build_pois puts their spots by hand).
const LANDMARK_LOOT := {"garden_lm": ["DRAWER", "TOOLBOX", "MEDICINE"]}

const CLUTTER_SEED := 20261113
const CLUTTER_KITS := [
	# [kit, weight, pieces]
	["Wreck", 3, [["Car", 0.0, 0.0, 2.0, 4.2, 1.2, 0.0], ["Crate", 2.0, 2.5, 1.0, 1.0, 0.9, 15.0]]],
	["Pileup", 1, [["Car", 0.0, 0.0, 2.0, 4.2, 1.2, 0.0], ["Car", 2.8, 1.2, 2.0, 4.2, 1.2, 25.0]]],
	["Crates", 2, [["CratePile", 0.0, 0.0, 2.4, 1.2, 1.8, 0.0], ["Crate", 1.9, 0.3, 1.0, 1.0, 0.9, 10.0],
		["Crate", -0.3, 1.5, 1.0, 1.0, 0.9, -20.0]]],
	# Leftover quarantine barricades.
	["Barricade", 3, [["Barricade", -2.5, 0.0, 3.0, 0.5, 1.1, 0.0], ["Barricade", 2.5, 0.0, 3.0, 0.5, 1.1, 0.0]]],
	["Dumpster", 2, [["Dumpster", 0.0, 0.0, 2.0, 1.2, 1.5, 0.0], ["Crate", 1.8, 0.7, 1.0, 1.0, 0.9, 30.0]]],
	["Barrels", 2, [["Crate", 0.0, 0.0, 0.8, 0.8, 1.0, 0.0], ["Crate", 0.9, 0.1, 0.8, 0.8, 1.0, 20.0],
		["Crate", 0.4, 0.9, 0.8, 0.8, 1.0, -15.0], ["CratePile", 2.2, -0.4, 2.4, 1.2, 1.8, 10.0]]],
	["Benches", 1, [["Bench", 0.0, 0.0, 2.0, 0.6, 0.8, 0.0], ["Bin", 1.4, 0.4, 0.6, 0.6, 1.0, 0.0]]],
]

const TUNNEL_BUILDING := &"tunnel"
## Each mouth ramp (4 m down over 14 m, about 16 degrees, like the park underpass).
const TUNNEL_RAMP_LEN := 14.0
## Emergency lights along the flat part: one every TUNNEL_LIGHT_STEP metres, alternating walls.
const TUNNEL_LIGHT_STEP := 10.0
const TUNNEL_LIGHT_COLOR := Color(1.0, 0.28, 0.18)
const TUNNEL_LIGHT_ENERGY := 1.4
const TUNNEL_LIGHT_RANGE := 7.0
const TUNNEL_LIGHT_H := 2.6

## Car park rows (world metres): row centres along z, cars every PARK_STEP along x, PARK_SKIP of the
## stalls left empty.
const PARK_ROWS := [49.0, 54.5, 66.5, 72.0, 84.0, 89.5]
const PARK_X := Vector2(-94.0, -46.0)
const PARK_STEP := 2.9
const PARK_SKIP := 0.3

## 02 "탈것" (_build_late_markers): land vehicle spots, world metres and yaw. Car park aisles, the
## ambulance bay, the south road, the back yard. A spot under a placed piece or a marker is skipped.
const VEHICLE_SPOT_SCENE := "res://field/markers/vehicle_spot.tscn"
const VEHICLE_SPOTS := [
	[Vector2(-82.0, 60.5), 0.0], [Vector2(-75.0, 78.5), 0.0], [Vector2(75.5, 20.0), PI * 0.5],
	[Vector2(-40.0, 99.0), 0.0], [Vector2(40.0, 99.0), PI], [Vector2(-80.0, -90.0), 0.0],
	[Vector2(30.0, -88.0), 0.0],
]
const VEHICLE_SPOTS_MIN := 5
## Free radius around a vehicle spot (m).
const VEHICLE_CLEAR := 1.5

## Footprints of the pieces _fixed() placed (world xz), for _spot().
var _fixed_boxes: Array[Rect2] = []


func _init() -> void:
	map_path = MAP_PATH
	out_scene = OUT_SCENE
	out_navmesh = OUT_NAVMESH
	root_name = "HospitalLayout"
	blocked_h = BLOCKED_H
	blocker_props = BLOCKERS
	extra_nests = EXTRA_NESTS
	loot_min = LOOT_MIN
	zone_loot = ZONE_LOOT
	landmark_loot = LANDMARK_LOOT
	clutter_kits = CLUTTER_KITS
	nature_seed = NATURE_SEED
	loot_seed = LOOT_SEED
	clutter_seed = CLUTTER_SEED
	kit_buildings = KitBuildings.BUILDINGS
	out_kit = OUT_KIT
	out_splat = OUT_SPLAT
	kit_cover = KIT_COVER
	kit_street_prefix = "road_"


func _build_structures() -> void:
	_build_tunnel()


## The passage between the tunnel link's two ends (see the file comment).
func _build_tunnel() -> void:
	var t := _tunnel()
	var a: Vector2 = t.a
	var b: Vector2 = t.b
	var dir: Vector2 = t.dir
	var floor_y: float = t.floor_y
	var width: float = t.width
	var outer := width + WALL_T * 2.0
	var foot_a := a + dir * TUNNEL_RAMP_LEN
	var foot_b := b - dir * TUNNEL_RAMP_LEN
	var strip := _strip(a, b, outer)
	_structure_keep_out.append(strip)
	_check_tunnel_ground(strip)

	var node := Node3D.new()
	node.name = "Tunnel"
	_root.add_child(node)

	# Open the ground over the whole passage; the roof below closes the flat part again.
	var cut := _box_along("TunnelCut", a, b, outer, -GROUND_DEPTH - 0.2, GROUND_DEPTH + 0.4, "ground")
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	_root.get_node("Ground").add_child(cut)
	var roof := Node3D.new()
	roof.name = "Roof"
	roof.add_to_group(ROOF_GROUP, true)
	roof.set_meta(ROOF_META, TUNNEL_BUILDING)
	# Overlays (roads, vegetation) over the passage: cut, and a copy of the flat part on the roof.
	for overlay in _root.get_node("Overlays").get_children():
		var shape := overlay as CSGPolygon3D
		if shape == null or Geometry2D.intersect_polygons(shape.polygon, strip).is_empty():
			continue
		var copy := shape.duplicate(0) as CSGPolygon3D
		var keep := _box_along("Keep", foot_a, foot_b, outer, -0.5, 1.0, "ground")
		keep.operation = CSGShape3D.OPERATION_INTERSECTION
		_add_local(copy, keep)
		roof.add_child(copy)
		copy.add_to_group(KIT_GREYBOX_GROUP, true)
		var over_cut := _box_along("TunnelCut", a, b, outer, -0.5, 1.0, "ground")
		over_cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		_add_local(shape, over_cut)

	var tube := _combiner("Passage")
	_nav(tube)
	node.add_child(tube)
	tube.add_child(_box_along("Floor", a, b, outer, floor_y - SLAB, SLAB, "slab"))
	var depth := -floor_y
	tube.add_child(_ramp("RampSouth", a, foot_a, width, floor_y, depth, "road"))
	tube.add_child(_ramp("RampNorth", b, foot_b, width, floor_y, depth, "road"))
	# Side walls: up to the ceiling under the roof, low parapets round the open mouths.
	var side := Vector2(-dir.y, dir.x) * (width + WALL_T) * 0.5
	for s in [1.0, -1.0]:
		var off: Vector2 = side * s
		var tag := "L" if s > 0.0 else "R"
		tube.add_child(_box_along("WallSouth" + tag, a + off, foot_a + off, WALL_T, floor_y, depth + LOW_WALL_H, "wall"))
		tube.add_child(_box_along("Wall" + tag, foot_a + off, foot_b + off, WALL_T, floor_y, depth - GROUND_DEPTH, "wall"))
		tube.add_child(_box_along("WallNorth" + tag, foot_b + off, b + off, WALL_T, floor_y, depth + LOW_WALL_H, "wall"))
	_kit_skins["Tunnel/Passage/Floor"] = [KIT_TERRAIN.road, 6.0]
	_kit_skins["Tunnel/Passage/RampSouth"] = [KIT_TERRAIN.road, 6.0]
	_kit_skins["Tunnel/Passage/RampNorth"] = [KIT_TERRAIN.road, 6.0]

	var slab := _combiner("RoofSlab")
	_nav(slab)
	roof.add_child(slab)
	slab.add_child(_box_along("Ground", foot_a, foot_b, outer, -GROUND_DEPTH, GROUND_DEPTH, "ground"))
	node.add_child(roof)
	# Keeps the sun off the floor while the roof is hidden (player inside). Never drawn.
	var shade := MeshInstance3D.new()
	shade.name = "ShadowRoof"
	var box := BoxMesh.new()
	box.size = Vector3(foot_a.distance_to(foot_b), 0.2, outer)
	shade.mesh = box
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var mid := (foot_a + foot_b) * 0.5
	shade.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(mid.x, -GROUND_DEPTH * 0.5, mid.y))
	node.add_child(shade)

	_root.get_node("IndoorZones").add_child(_indoor_zone(TUNNEL_BUILDING, [strip], floor_y - 0.5, -0.5))
	# Kit ground: leave the strip open, lay the same ground over the flat part as the tunnel's roof.
	# The strip lies inside the land, so cutting it would leave a hole the mesh cannot draw: split the
	# land along the tunnel first, each half then loses a notch.
	var across := Vector2(-dir.y, dir.x) * MAP_HALF * 4.0
	var reach := dir * MAP_HALF * 4.0
	var split: Array = []
	for land: PackedVector2Array in _kit_ground.land:
		for s in [1.0, -1.0]:
			var half := PackedVector2Array([a - reach, b + reach, b + reach + across * s, a - reach + across * s])
			split.append_array(Geometry2D.intersect_polygons(land, half))
	_kit_ground.land = split
	_kit_ground_holes.append(strip)
	_kit_items.append({"slab": _strip(foot_a, foot_b, outer), "y": KIT_GROUND_LIFT, "splat": true,
		"holder": "roof:%s" % TUNNEL_BUILDING})
	# Emergency lights, alternating walls.
	var length := foot_a.distance_to(foot_b)
	var n := int(length / TUNNEL_LIGHT_STEP)
	for i in n + 1:
		var at := foot_a + dir * (length * i / maxf(n, 1)) + side * (0.8 if i % 2 == 0 else -0.8)
		_kit_items.append({"light": Vector3(at.x, floor_y + TUNNEL_LIGHT_H, at.y), "color": TUNNEL_LIGHT_COLOR,
			"energy": TUNNEL_LIGHT_ENERGY, "range": TUNNEL_LIGHT_RANGE, "holder": ""})
	print("tunnel: %.0fm, ramps %.0fm, floor y %.1f, %d lights" % [a.distance_to(b), TUNNEL_RAMP_LEN, floor_y, n + 1])


## {a: south mouth, b: north mouth, dir: a -> b, floor_y, width}, scaled plan points.
func _tunnel() -> Dictionary:
	var link := _link("tunnel")
	var a := _xz(link.from.position)
	var b := _xz(link.to.position)
	return {"a": a, "b": b, "dir": (b - a).normalized(), "floor_y": float(link.floor_y), "width": float(link.width_m)}


## Nothing may stand on the tunnel's ground but the markers inside it (floor y below -1).
func _check_tunnel_ground(strip: PackedVector2Array) -> void:
	for zone: Dictionary in _map.zones:
		if zone.kind in ["indoor", "blocked", "flooded"] \
				and not Geometry2D.intersect_polygons(_poly(zone), strip).is_empty():
			push_error("Tunnel runs under %s" % zone.id)
	for m: Dictionary in _map.markers:
		if m.position[1] > -1.0 and Geometry2D.is_point_in_polygon(_xz(m.position), strip):
			push_error("Marker %s is on the tunnel" % m.node_name)


## Quarantine wall segments as rows of army barriers. The prisms keep the collision.
func _kit_blocked(zone: Dictionary, poly: PackedVector2Array, h: float) -> bool:
	if not zone.id.begins_with("wall_"):
		return super(zone, poly, h)
	_hesco_row(_bounds(poly))
	return true


func _kit_cover(kind: String, center: Vector2, size: Vector2, rot_deg: float) -> void:
	if kind == "hesco":
		_hesco_row(Rect2(center - size * 0.5, size))
		return
	super(kind, center, size, rot_deg)


## Hesco barriers along the long side of r, a stop sign on the hospital (south) face now and then.
func _hesco_row(r: Rect2) -> void:
	var along_x := r.size.x >= r.size.y
	var length := maxf(r.size.x, r.size.y)
	var axis := Vector2(1.0, 0.0) if along_x else Vector2(0.0, 1.0)
	var start := r.get_center() - axis * length * 0.5
	var step: float = (CityKit.PROPS.hesco_barrier_01[2] as Vector3).x
	var count := maxi(1, floori(length / step))
	var pad := (length - count * step) * 0.5
	var base_yaw := 0.0 if along_x else PI * 0.5
	for i in count:
		var at := start + axis * (pad + step * (i + 0.5))
		_kit_add("hesco_barrier_02" if i % 3 == 0 else "hesco_barrier_01", at, base_yaw + (PI if i % 2 == 1 else 0.0))
		if i % 14 == 7 and along_x:
			_kit_add("military_sign_stop", at + Vector2(0.0, 1.5), FACE_SOUTH, 0.0, PROP_SCALE)


const FACE_SOUTH := PI * 0.5


## Special places from the landmark looks in the map file. Fixed pieces get collision (cover up to
## 1.2 m, else blockers), like _poi_try.
func _build_pois() -> void:
	var keep_out := _keep_out_polygons()
	var routes := _route_segments()
	var loot_scene := _scene_of("LootSpot")
	var placed := 0

	# 응급실 승강장: ambulances nosed in by the treatment hall, a fire truck, a triage canopy and cots.
	var bay_cars := ["ambulance", "ambulance", "military_ambulance", "ambulance"]
	for k in bay_cars.size():
		placed += _fixed(bay_cars[k], Vector2(67.5, 13.0 + 4.0 * k), _kit_rng.randf_range(-0.05, 0.05), true)
	placed += _fixed("fire_truck", Vector2(86.5, 8.0), PI * 0.5, true)
	placed += _fixed("military_field_canopy_01", Vector2(84.0, 22.0), 0.0, false)
	for x in [81.5, 84.0, 86.5]:
		placed += _fixed("military_folding_cot", Vector2(x, 22.0), PI * 0.5, true)
	placed += _fixed("military_folding_table", Vector2(88.8, 25.5), 0.0, true)
	placed += _fixed("mobile_light_tower", Vector2(90.0, 28.0), PI, true)
	# One more ambulance stalled on the way in.
	placed += _fixed("ambulance", Vector2(74.6, 62.0), PI * 0.5 + 0.15, true)
	_spot(loot_scene, "bay_ambulance", Vector2(72.0, 15.0), "MEDICINE")
	_spot(loot_scene, "bay_truck", Vector2(83.4, 8.0), "TOOLBOX")

	# 정문 광장: the army checkpoint at the main entrance. The lane x -5..5 stays clear.
	placed += _fixed("military_arched_tent_exterior", Vector2(-20.0, 43.0), 0.0, true)
	placed += _fixed("military_command_tent_exterior", Vector2(18.0, 43.0), 0.0, true)
	placed += _fixed("sandbag_pile_04", Vector2(-7.0, 44.0), 0.0, true)
	placed += _fixed("sandbag_pile_04", Vector2(7.0, 44.0), PI, true)
	placed += _fixed("concrete_road_barrier", Vector2(-3.0, 58.0), PI * 0.5, true)
	placed += _fixed("concrete_road_barrier", Vector2(3.0, 63.0), PI * 0.5, true)
	placed += _fixed("checkpoint_sign_trailer", Vector2(8.5, 54.0), 0.0, true)
	placed += _fixed("military_light_tower_big", Vector2(-9.5, 38.5), 0.0, true)
	placed += _fixed("police_sedan", Vector2(-30.0, 47.0), 0.3, true)
	placed += _fixed("ambulance", Vector2(27.0, 39.5), -0.45, true)
	placed += _fixed("military_truck_01", Vector2(-35.5, 41.0), PI * 0.5, true)
	_spot(loot_scene, "plaza_tent", Vector2(-20.0, 48.5), "TOOLBOX")
	_spot(loot_scene, "plaza_command", Vector2(13.0, 47.5), "DRAWER")

	# 주차장: rows of abandoned cars, some stalls empty, clear round the nest and the crate.
	var cars := 0
	var pool: Array = KIT_CARS + ["service_van", "car_minivan_01"]
	for z: float in PARK_ROWS:
		var x := PARK_X.x
		while x <= PARK_X.y:
			var at := Vector2(x, z)
			x += PARK_STEP
			if _kit_rng.randf() < PARK_SKIP:
				continue
			var piece: String = pool[_kit_rng.randi_range(0, pool.size() - 1)]
			var yaw := PI * 0.5 + (PI if _kit_rng.randf() < 0.5 else 0.0) + _kit_rng.randf_range(-0.08, 0.08)
			cars += _fixed(piece, at, yaw, true)
	placed += cars
	_spot(loot_scene, "parking_aisle1", Vector2(-70.0, 60.5), "TOOLBOX")
	_spot(loot_scene, "parking_aisle2", Vector2(-56.0, 78.0), "DRAWER")

	# 병원 정원: patients' benches and sun loungers in the overgrowth.
	var garden := _poly(_zones.garden)
	for piece: String in ["patio_bench_a", "patio_bench_a", "patio_bench_a", "patio_bench_b", "patio_bench_b",
			"lounge_chair", "lounge_chair", "lounge_chair", "lounge_chair", "outdoor_dining_table_a",
			"outdoor_dining_table_a", "patio_umbrella", "patio_umbrella", "urn_street_01", "urn_street_02",
			"garden_gnome_02"]:
		placed += int(_poi_try(piece, garden, keep_out, routes, piece not in ["patio_umbrella", "garden_gnome_02"]))
	# 안뜰: benches by the path.
	for half: String in ["courtyard", "courtyard_e"]:
		for piece: String in ["patio_bench_b", "patio_bench_a", "urn_street_02"]:
			placed += int(_poi_try(piece, _poly(_zones[half]), keep_out, routes, true))

	# 뒷마당: the generator by the boiler room, fuel, a morgue tent, army trucks left behind.
	placed += _fixed("military_generator_large", Vector2(54.5, -86.0), 0.0, true)
	var boiler_yard := _rect_poly(Rect2(44.0, -94.0, 30.0, 22.0))
	for piece: String in ["military_fuel_barrel", "military_fuel_barrel", "military_fuel_barrel", "pallet",
			"commercial_dumpster_01", "fuel_canister", "barrel_01"]:
		placed += int(_poi_try(piece, boiler_yard, keep_out, routes, piece != "pallet"))
	placed += _fixed("military_command_tent_exterior", Vector2(-28.0, -66.0), 0.0, true)
	var yard := _rect_poly(Rect2(-96.0, -94.0, 190.0, 38.0))
	placed += _poi_row(["military_truck_01", "military_utility_vehicle"], 2, 3.6, yard, keep_out, routes)
	for piece: String in ["commercial_dumpster_01", "commercial_dumpster_02", "pile_garbage_03", "military_folding_table",
			"hesco_barrier_01", "sandbag_pile_06", "sandbag_pile_02", "anti_tank_hedgehog", "anti_tank_hedgehog",
			"military_meal_crate", "military_equipment_case", "portable_field_toilet", "mobile_light_tower"]:
		placed += int(_poi_try(piece, yard, keep_out, routes, true))

	# 서쪽 외곽 도로: the checkpoint where the road passes the wall line.
	placed += _fixed("guard_booth", Vector2(-109.0, -48.5), 0.0, true)
	placed += _fixed("road_barricade", Vector2(-103.5, -47.5), PI * 0.5, true)
	placed += _fixed("hesco_barrier_01", Vector2(-95.0, -48.5), 0.0, true)
	placed += _fixed("striped_concrete_barrier", Vector2(-100.5, -56.0), PI * 0.5, true)
	print("pois: %d pieces, %d parked cars" % [placed, cars])


## Vehicle spots (02 "탈것") after all dressing, so the earlier random draws stay as they were.
func _build_late_markers() -> void:
	var points := _keep_out_points()
	var placed := 0
	var blocked := func(p: Vector2) -> bool:
		return _near_points(p, _taken, VEHICLE_CLEAR) or _near_points(p, points, VEHICLE_CLEAR) 				or _in_prop(p, VEHICLE_CLEAR) or _near_plant(p, VEHICLE_CLEAR) 				or _fixed_boxes.any(func(r: Rect2) -> bool: return r.grow(VEHICLE_CLEAR).has_point(p))
	for v: Array in VEHICLE_SPOTS:
		# The listed point, else the nearest free one within 8 m (2 m steps, 8 directions).
		var p: Vector2 = v[0]
		var found: bool = not blocked.call(p)
		for ring in range(1, 5):
			if found:
				break
			for k in 8:
				var q: Vector2 = v[0] + Vector2(2.0 * ring, 0.0).rotated(TAU * k / 8.0)
				if not blocked.call(q):
					p = q
					found = true
					break
		if not found:
			continue
		placed += 1
		_add_extra(VEHICLE_SPOT_SCENE, "VehicleSpot_land_%d" % placed, Vector3(p.x, 0.0, p.y), v[1], {})
		_taken.append(Vector3(p.x, p.y, VEHICLE_CLEAR + 1.5))
	if placed < VEHICLE_SPOTS_MIN:
		push_error("vehicle spots: only %d of %d" % [placed, VEHICLE_SPOTS.size()])
	print("vehicle spots: %d" % placed)


## One pack piece at a fixed spot (world metres), with collision from its bounds unless collide is
## false. Skipped (0) when a marker is under it.
func _fixed(piece: String, at: Vector2, yaw: float, collide: bool) -> int:
	var scale := 1.0 if piece in KIT_CARS or CityKit.PROPS[piece][0] == "vehicle" else PROP_SCALE
	var size := _kit_size(piece, yaw, scale)
	var radius := maxf(size.x, size.z) * 0.5
	if _near_marker(at, 0, radius + 0.8):
		return 0
	_kit_add(piece, at, yaw, 0.0, scale)
	_taken.append(Vector3(at.x, at.y, radius + 0.5))
	_fixed_boxes.append(Rect2(at - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)))
	if collide and size.y >= CityKit.PROP_MIN_COLLIDE_H:
		var low := size.y <= LOW_COVER_MAX_H
		_root.get_node("LowCoverKit" if low else "PropsKit").add_child(_box("Fixed_%s_%d" % [piece, _taken.size()],
			at, Vector2(size.x, size.z), 0.0, size.y, 0.0, "cover" if low else "blocked"))
	return 1


## A LootSpot placed by hand on open or paved ground (the bay, the plaza, the car park).
func _spot(scene: String, id: String, at: Vector2, kind: String) -> void:
	if _in_prop(at, 0.6) or _fixed_boxes.any(func(r: Rect2) -> bool: return r.grow(0.6).has_point(at)):
		push_warning("Loot spot %s is in a prop" % id)
	_add_extra(scene, "LootSpot_loot_%s" % id, Vector3(at.x, 0.0, at.y), _kit_rng.randf() * TAU,
		{"container_type": kind, "loot_table_id": ""})


## Rectangle of the given width along a -> b.
func _strip(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x) * width * 0.5
	return PackedVector2Array([a + side, b + side, b - side, a - side])


## Box from a to b (length along the line), width across, from y up by h.
func _box_along(node_name: String, a: Vector2, b: Vector2, width: float, y: float, h: float,
		mat: String) -> CSGBox3D:
	var dir := (b - a).normalized()
	return _box(node_name, (a + b) * 0.5, Vector2(a.distance_to(b), width), y, h,
		rad_to_deg(atan2(-dir.y, dir.x)), mat)


## Adds a CSG child given in world space under a transformed CSG parent (parent's parent at origin).
func _add_local(parent: CSGShape3D, child: CSGShape3D) -> void:
	child.transform = parent.transform.affine_inverse() * child.transform
	parent.add_child(child)
