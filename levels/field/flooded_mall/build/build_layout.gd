extends "res://field/build/layout_builder.gd"
## Builds levels/field/flooded_mall/layout.tscn (B-12) from the confirmed map file.
##
##   godot --headless --path . --script res://levels/field/flooded_mall/build/build_layout.gd
##
## Source: build/flooded_mall_map.json, exported from the planning board (user-confirmed map,
## 2026-11-05). The shared generator (field/build/layout_builder.gd) does the terrain, buildings,
## props, extra markers, clutter, nature, markers and the navmesh. This file has the mall's
## settings and the mall itself (_build_structures): stairs, elevator shaft, 2F and the ramp.
## Re-run after the map file changes. Hand edits to layout.tscn are lost on a re-run.
##
## Stairs, the elevator shaft and the loading ramp move with the plan but keep their shape
## (size, rise, slope), so the ramp ends short of the scaled route end and the rest is ground.
## Stairs are cut out of the navmesh and joined by a layer-1-only NavigationLink3D, so a
## wheelchair path from the mall's 2F can only use the hidden ramp.
##
## B-26: the houses, the pharmacy, the gas station store and the depot office follow the plans in
## build/kit_buildings.gd; the pack dressing goes to buildings.tscn (see layout_builder.gd). This
## file adds the mall's pack shopfronts and roofs and the special places (_build_pois).

const MAP_PATH := "res://levels/field/flooded_mall/build/flooded_mall_map.json"
const OUT_SCENE := "res://levels/field/flooded_mall/layout.tscn"
const OUT_NAVMESH := "res://levels/field/flooded_mall/layout_navmesh.res"
const OUT_KIT := "res://levels/field/flooded_mall/buildings.tscn"
const OUT_SPLAT := "res://levels/field/flooded_mall/ground_splat.res"
const KitBuildings := preload("res://levels/field/flooded_mall/build/kit_buildings.gd")
## Greybox cover and blockers drawn with pack meshes: name -> kind (layout_builder.gd _kit_cover).
const KIT_COVER := {"Car1": "car", "Car2": "car", "Car3": "car", "GateBarricadeW": "barricade",
	"GateBarricadeE": "barricade", "TruckA": "truck", "TruckB": "truck", "MartShelf1": "shelves",
	"MartShelf2": "shelves", "MartShelf3": "shelves", "Pump1": "pump", "Pump2": "pump"}
## Mall interiors: shelf rows on 1F (3 back-to-back pairs), cafe tables on 2F. [zone, kind, m2 per item]
const SHOP_FILL := [["shop_in", "shelves", 170.0], ["shop2_in", "tables", 110.0]]

const WALL_H := {"mart_in": 4.0}
const UPPER_WALL_H := 3.5
const BLOCKED_H := {"rubble": 3.5}
const RAMP_WIDTH := 3.5

## Doors: zone id -> [[x, z, width], ...] in map file coordinates (scaled on use, width is not).
## Placed from the demo routes and the roads/bridges each building faces.
const DOORS := {
	"mart_in": [[-33.0, -58.0, 3.0], [-56.0, -43.0, 3.0]],
	# B-26: the kit buildings (houses, pharm, gas_store, depot_office) take their doors from their
	# plans in kit_buildings.gd.
	# Mall 1F: north road, east pier, south dock, west footbridge.
	"shop_in": [[29.0, 17.9, 4.0], [49.9, 29.0, 3.0], [38.0, 49.0, 4.0], [21.0, 27.5, 5.0]],
	# Mall 2F wall between the food court and the roof deck.
	"shop2_in": [[41.0, 33.6, 3.0]],
}
## Elevator door (2F, the car is stuck there): middle of the shaft's south side.
const ELEVATOR_DOOR_W := 2.0

## Low cover (1.2m, B-06 sandbox size): cars on the bridge, gas pumps, gate barricade.
## The gate barricade spans the road and widens with it.
const LOW_COVER := [
	["Car1", 23.0, -22.0, 2.0, 4.2, 1.2, 0.0],
	["Car2", 26.5, -12.0, 2.0, 4.2, 1.2, 10.0],
	["Car3", 23.5, -2.0, 2.0, 4.2, 1.2, -8.0],
	["Pump1", -26.0, 10.0, 1.0, 3.0, 1.2, 0.0],
	["Pump2", -26.0, 16.0, 1.0, 3.0, 1.2, 0.0],
	["GateBarricadeW", -17.75, -68.0, 2.5 * MAP_SCALE, 1.0, 1.2, 0.0],
	["GateBarricadeE", -12.25, -68.0, 2.5 * MAP_SCALE, 1.0, 1.2, 0.0],
]
const NATURE_SEED := 20261105
## Full blockers: dock trucks (landmark look: 트럭 두 대), mart shelf rows (선반 사이로 덩굴).
const BLOCKERS := [
	["TruckA", 31.0, 63.0, 7.0, 2.5, 3.0, 0.0],
	["TruckB", 42.0, 68.0, 2.5, 7.0, 3.0, 0.0],
	["MartShelf1", -62.0, -65.0, 10.0, 0.8, 2.2, 0.0],
	["MartShelf2", -62.0, -61.0, 10.0, 0.8, 2.2, 0.0],
	["MartShelf3", -62.0, -53.0, 10.0, 0.8, 2.2, 0.0],
]

## None on the sortie 1 loop or near an extract point: depot east (65m from the north gate),
## the woods behind the depot (47m from the east spawn), the pier (dead end).
const EXTRA_NESTS := [
	["nest_depot", "GREEN", 28.0, -57.0, 4, 10.0],
	["nest_ne", "GREEN", 40.0, -72.0, 3, 8.0],
	["nest_pier", "WATER", 60.0, 28.0, 3, 8.0],
]

const LOOT_SEED := 20261107
const LOOT_MIN := {"pharm": 2, "gas_store": 2, "depot_office": 2}
const ZONE_LOOT := {
	"mart_in": ["DRAWER"],
	"pharm": ["MEDICINE"],
	"gas_store": ["DRAWER"],
	"depot_office": ["TOOLBOX"],
	"house2": ["MEDICINE"],
	"house3": ["TOOLBOX"],
	# 02: paint and scrap on the mall's 1F, medicine cabinets common in shops.
	"shop_in": ["TOOLBOX", "DRAWER", "MEDICINE"],
	"shop2_in": ["DRAWER", "MEDICINE"],
}
## B-26 (user feedback 2026-11-05: farming felt thin): more spots, and the flooded park and the pier
## get spots too. Supply crates (2026-11-06) only where the risk is, since they always spawn: the depot
## checkpoint next to its nest, the flooded park by the wraith's arena, the pier by its nest and the
## golem. The dock keeps the map file's crate only.
const LANDMARK_LOOT := {
	"depot_lm": ["TOOLBOX", "TOOLBOX", "DRAWER", "SUPPLY_CRATE", "MEDICINE"],
	"dock_lm": ["TOOLBOX", "DRAWER", "TOOLBOX", "TOOLBOX"],
	"gas_lm": ["TOOLBOX", "DRAWER", "TOOLBOX"],
	"veg_sw": ["DRAWER", "TOOLBOX", "SUPPLY_CRATE"],
	"pier_lm": ["TOOLBOX", "SUPPLY_CRATE"],
}

const CLUTTER_SEED := 20261106
const CLUTTER_KITS := [
	# [kit, weight, pieces]
	["Wreck", 3, [["Car", 0.0, 0.0, 2.0, 4.2, 1.2, 0.0], ["Crate", 2.0, 2.5, 1.0, 1.0, 0.9, 15.0]]],
	["Pileup", 1, [["Car", 0.0, 0.0, 2.0, 4.2, 1.2, 0.0], ["Car", 2.8, 1.2, 2.0, 4.2, 1.2, 25.0]]],
	["Crates", 2, [["CratePile", 0.0, 0.0, 2.4, 1.2, 1.8, 0.0], ["Crate", 1.9, 0.3, 1.0, 1.0, 0.9, 10.0],
		["Crate", -0.3, 1.5, 1.0, 1.0, 0.9, -20.0]]],
	["Barricade", 2, [["Barricade", -2.5, 0.0, 3.0, 0.5, 1.1, 0.0], ["Barricade", 2.5, 0.0, 3.0, 0.5, 1.1, 0.0]]],
	["LowWall", 2, [["LowWall", 0.0, 0.0, 6.0, 0.4, 1.0, 0.0], ["LowWall", -2.8, 2.0, 0.4, 4.0, 1.0, 0.0]]],
	["Dumpster", 1, [["Dumpster", 0.0, 0.0, 2.0, 1.2, 1.5, 0.0], ["Crate", 1.8, 0.7, 1.0, 1.0, 0.9, 30.0]]],
	# B-26: barrel and junk heaps like the reference game's yards.
	["Barrels", 3, [["Crate", 0.0, 0.0, 0.8, 0.8, 1.0, 0.0], ["Crate", 0.9, 0.1, 0.8, 0.8, 1.0, 20.0],
		["Crate", 0.4, 0.9, 0.8, 0.8, 1.0, -15.0], ["Crate", -0.6, 0.8, 0.8, 0.8, 1.0, 40.0],
		["CratePile", 2.2, -0.4, 2.4, 1.2, 1.8, 10.0]]],
]


func _init() -> void:
	map_path = MAP_PATH
	out_scene = OUT_SCENE
	out_navmesh = OUT_NAVMESH
	root_name = "FloodedMallLayout"
	wall_h = WALL_H
	blocked_h = BLOCKED_H
	zone_doors = DOORS
	cover_props = LOW_COVER
	blocker_props = BLOCKERS
	extra_nests = EXTRA_NESTS
	loot_min = LOOT_MIN
	zone_loot = ZONE_LOOT
	landmark_loot = LANDMARK_LOOT
	clutter_kits = CLUTTER_KITS
	nature_seed = NATURE_SEED
	loot_seed = LOOT_SEED
	clutter_seed = CLUTTER_SEED
	custom_buildings = ["shop_in"]
	# 2F dressing (tables, deck cars) hides with the mall roof while the player is on the 1F.
	upper_floor_holder = "roof:shop_in"
	kit_buildings = KitBuildings.BUILDINGS
	out_kit = OUT_KIT
	out_splat = OUT_SPLAT
	kit_cover = KIT_COVER
	shop_fill = SHOP_FILL




## The mall: 1F, stairs, elevator shaft, 2F food court and deck, the hidden loading ramp.
func _build_structures() -> void:
	var shop_in := _poly(_zones.shop_in)
	var shop2_in := _poly(_zones.shop2_in)
	var deck := _poly(_zones.shop2_deck)
	var y2: float = _map.floors[1].y
	var stairs: Dictionary = _link("stairs")
	var elevator: Dictionary = _link("elevator")
	var stair_rect := _rect(stairs.rect)
	var el_rect := _rect(elevator.rect)
	# No extra LootSpot on the stairs or in the shaft.
	_loot_exclude.append(stair_rect.grow(2.0))
	_loot_exclude.append(el_rect.grow(1.5))

	var mall := Node3D.new()
	mall.name = "Mall"
	_root.add_child(mall)
	mall.add_child(_prism("Floor1F", shop_in, 0.0, OVERLAY_Y.floor, "floor", false))

	# 1F: outer walls up to the slab, the elevator shaft is closed (the car is stuck on 2F).
	var walls1 := _combiner("Walls1F")
	_nav(walls1)
	mall.add_child(walls1)
	_add_walls(walls1, shop_in, 0.0, y2 - SLAB, _doors("shop_in"), [])
	walls1.add_child(_box("ElevatorShaft1F", el_rect.get_center(), el_rect.size, 0.0, y2 - SLAB, 0.0, "wall"))
	# B-26: pack shopfront and tiles over the hidden greybox 1F.
	walls1.add_to_group(KIT_GREYBOX_GROUP, true)
	_kit_ring(shop_in, 0.0, y2 - SLAB, _doors("shop_in"), [], "shop")
	_kit_ring(_rect_poly(el_rect), 0.0, y2 - SLAB, [], [], "plain")
	_kit_floor(shop_in, CityKit.FLOOR_Y, "", [stair_rect, el_rect])

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
	_add_walls(walls2, shop2_in, y2, UPPER_WALL_H, _doors("shop2_in"), [])
	# Elevator shaft on 2F: open door on one side, the trapped person is inside.
	_add_walls(walls2, _rect_poly(el_rect), y2, UPPER_WALL_H,
		[[el_rect.get_center().x, el_rect.end.y, ELEVATOR_DOOR_W]], [])
	# Stairwell railings on the three open sides (north side is the top of the flight).
	var well := _rect_poly(stair_rect)
	_add_walls(walls2, well, y2, LOW_WALL_H, [], [0])
	# Deck parapets on the outer edges, gap where the hidden ramp starts.
	var ramp_top := _ramp_top(deck)
	_add_walls(walls2, deck, y2, LOW_WALL_H, [[ramp_top.x, ramp_top.y, RAMP_WIDTH + 0.5]], [0])

	var roof2 := _roof("Roof2F", shop2_in, y2 + UPPER_WALL_H, &"shop2_in")
	upper.add_child(roof2)
	# B-26: the 2F in pack pieces, hidden with the 1F roofs like the greybox Upper node.
	walls2.add_to_group(KIT_GREYBOX_GROUP, true)
	roof2.add_to_group(KIT_GREYBOX_GROUP, true)
	var up := "roof:shop_in"
	_kit_ring(shop2_in, y2, UPPER_WALL_H, _doors("shop2_in"), [], "shop", up)
	_kit_ring(_rect_poly(el_rect), y2, UPPER_WALL_H, [[el_rect.get_center().x, el_rect.end.y, ELEVATOR_DOOR_W]],
		[], "plain", up)
	_kit_ring(well, y2, LOW_WALL_H, [], [0], "railing", up)
	_kit_ring(deck, y2, LOW_WALL_H, [[ramp_top.x, ramp_top.y, RAMP_WIDTH + 0.5]], [0], "railing", up)
	_kit_floor(shop2_in, y2 + 0.01, up, [stair_rect, el_rect])
	_kit_slab(deck, y2 + 0.01, KIT_TERRAIN.road, 6.0, up)
	_kit_roof(shop2_in, y2 + UPPER_WALL_H + ROOF_T, up + "/roof:shop2_in")
	_kit_skins["Mall/Stairs"] = [KIT_TERRAIN.road, 3.0]

	# Hidden loading ramp: from the deck edge down toward the dock (map hidden_routes[0].to).
	# Its length (so its slope) is the unscaled one; the scaled rest of the route is ground.
	var route: Dictionary = _map.hidden_routes[0]
	var to := _xz(route.to.position)
	var dir := (to - ramp_top).normalized()
	var foot := ramp_top + dir * ramp_top.distance_to(to) / MAP_SCALE
	var side := Vector2(-dir.y, dir.x) * RAMP_WIDTH * 0.5
	_structure_keep_out.append(PackedVector2Array([ramp_top + side, foot + side, foot - side, ramp_top - side]))
	var ramp := _ramp("LoadingRamp", ramp_top - dir * 0.15, foot, RAMP_WIDTH, 0.0, y2, "road")
	_kit_skins["Mall/LoadingRamp"] = [KIT_TERRAIN.road, 6.0]
	_nav(ramp)
	mall.add_child(ramp)

	var zones_node := _root.get_node("IndoorZones")
	zones_node.add_child(_indoor_zone(&"shop_in", [shop_in], 0.0, y2 - SLAB))
	zones_node.add_child(_indoor_zone(&"shop2_in", [shop2_in], y2, y2 + UPPER_WALL_H))


## B-26 special places, from the landmark looks in the map file (user feedback 2026-11-05: nothing
## to head for). Pieces that stand in the way get collision (cover up to 1.2 m, else blockers).
func _build_pois() -> void:
	var keep_out := _keep_out_polygons()
	var routes := _route_segments()
	var y2: float = _map.floors[1].y
	var placed := 0

	# 잠긴 놀이공원: a playground swallowed by the bush (veg_sw).
	var park := _poly(_zones.veg_sw)
	for piece: String in ["big_kids_slide", "big_kids_slide", "small_kids_slide", "small_kids_slide", "wooden_swing",
			"wooden_swing", "backyard_trampoline", "backyard_trampoline", "round_swimming_pool", "basketball_hoop",
			"plastic_table", "plastic_table", "patio_umbrella", "garden_gnome_01", "garden_gnome_02",
			"garden_gnome_01", "campaign_yard_sign_01"]:
		placed += int(_poi_try(piece, park, keep_out, routes, piece not in ["patio_umbrella", "garden_gnome_01",
			"garden_gnome_02", "campaign_yard_sign_01"]))

	# 주유소: one tilted canopy over the two pumps, the emergency generator and fuel by the store.
	var pumps: Array = cover_props.filter(func(p: Array) -> bool: return String(p[0]).begins_with("Pump"))
	if pumps.size() == 2:
		var mid := (Vector2(pumps[0][1], pumps[0][2]) + Vector2(pumps[1][1], pumps[1][2])) * 0.5 * MAP_SCALE
		var part := CityKit.prop_part("gas_station_canopy", mid, 0.0)
		var pivot := Vector3(mid.x, 0.0, mid.y)
		var xf: Transform3D = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(4.0)), pivot) \
			* Transform3D(Basis.IDENTITY, -pivot) * part.xf
		_kit_items.append({"piece": "gas_station_canopy", "folder": part.folder, "xf": xf, "holder": ""})
		var gas := _poly(_zones.gas_lm)
		for piece: String in ["conditioner_07", "compact_power_station", "fuel_canister", "fuel_canister",
				"fuel_tank_covers", "fuel_price_sign_01"]:
			placed += int(_poi_try(piece, gas, keep_out, routes, piece in ["conditioner_07", "fuel_price_sign_01"]))

	# 해솔마트: the sign half off its post by the front door. No plants inside (user decision
	# 2026-11-06: nothing grows on indoor floors).
	var mart_doors := _doors("mart_in")
	if not mart_doors.is_empty():
		var mart := _poly(_zones.mart_in)
		var d := Vector2(mart_doors[0][0], mart_doors[0][1])
		var out := (d - _bounds(mart).get_center()).normalized()
		var at := d + out * 4.5
		if not _near_points(at, _keep_out_points(), 1.0):
			var part := CityKit.prop_part("store_signboard", at, atan2(-out.y, out.x))
			var xf: Transform3D = part.xf
			var tilt := Transform3D(Basis(Vector3(out.y, 0.0, -out.x), deg_to_rad(28.0)), Vector3(at.x, 0.0, at.y))
			xf = tilt * Transform3D(Basis.IDENTITY, -Vector3(at.x, 0.0, at.y)) * xf
			_kit_items.append({"piece": "store_signboard", "folder": part.folder, "xf": xf, "holder": ""})
			_root.get_node("PropsKit").add_child(_box("MartSign", at, Vector2(0.8, 0.8), 0.0, 2.0, 0.0, "blocked"))
		var inner := _largest(Geometry2D.offset_polygon(mart, -1.0))
		var b := _bounds(inner)
		for i in int(_area(inner) * 0.12):
			var p := Vector2(_kit_rng.randf_range(b.position.x, b.end.x), _kit_rng.randf_range(b.position.y, b.end.y))
			if Geometry2D.is_point_in_polygon(p, inner) and not _near_door(p, mart_doors, 2.0) and not _in_prop(p, 0.3):
				# The old overgrowth spot: draw the same random numbers as before (piece, yaw,
				# scale) without placing a plant, so the rest of the map keeps its layout.
				_kit_rng.randi_range(0, KIT_EDGE_PLANTS.size() - 1)
				_kit_rng.randf()
				_kit_rng.randf_range(0.8, 1.4)

	# 옥상 주차 데크: cars left parked on the mall roof deck.
	var deck := _largest(Geometry2D.offset_polygon(_poly(_zones.shop2_deck), -2.5))
	var deck_cars := 0
	var db := _bounds(deck)
	var ramp_top := _ramp_top(_poly(_zones.shop2_deck))
	for attempt in 200:
		if deck_cars >= 5:
			break
		var p := Vector2(_kit_rng.randf_range(db.position.x, db.end.x), _kit_rng.randf_range(db.position.y, db.end.y))
		var yaw := PI * 0.5 * _kit_rng.randi_range(0, 3) + _kit_rng.randf_range(-0.1, 0.1)
		var car: String = KIT_CARS[_kit_rng.randi_range(0, KIT_CARS.size() - 1)]
		var size := _kit_size(car, yaw)
		var corners := _rect_poly(Rect2(p - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)))
		if Array(corners).any(func(q: Vector2) -> bool: return not Geometry2D.is_point_in_polygon(q, deck)) \
				or p.distance_to(ramp_top) < 7.0 or _near_marker(p, 1, 4.0) or _near_door(p, _doors("shop2_in"), 4.0) \
				or _kit_items.any(func(it: Dictionary) -> bool: return it.has("deck") and (it.deck as Vector2).distance_to(p) < 5.5):
			continue
		deck_cars += 1
		_kit_add(car, p, yaw, y2, 1.0, upper_floor_holder)
		_kit_items[-1]["deck"] = p
		_root.get_node("PropsKit").add_child(_box("DeckCar%d" % deck_cars, p, Vector2(size.x, size.z), y2, size.y, 0.0, "blocked"))
	placed += deck_cars

	# 선착장: wooden planks on the pier, a camper van half sunk off its end.
	var pier := _poly(_zones.pier)
	var pb := _bounds(pier)
	var z := pb.position.y
	while z < pb.end.y - 0.5:
		var x := pb.position.x
		while x < pb.end.x - 0.5:
			var r := Rect2(x, z, 4.0, 4.0)
			if Geometry2D.is_point_in_polygon(r.get_center(), pier):
				_kit_items.append({"piece": "house_wooden_deck_c_4x4m", "folder": CityKit.MODULES,
					"xf": Transform3D(Basis.IDENTITY, Vector3(r.end.x, OVERLAY_Y.road - 0.15, r.end.y)), "holder": ""})
			x += 4.0
		z += 4.0
	# Wrecks half under water: deep water near its banks, away from bridges.
	var wrecks := 0
	for attempt in 400:
		if wrecks >= 9:
			break
		var w: PackedVector2Array = _kit_ground.water[_kit_rng.randi_range(0, _kit_ground.water.size() - 1)]
		var wb := _bounds(w)
		var p := Vector2(_kit_rng.randf_range(wb.position.x, wb.end.x), _kit_rng.randf_range(wb.position.y, wb.end.y))
		var bank := _dist_to_ring(p, w)
		if not Geometry2D.is_point_in_polygon(p, w) or bank < 2.5 or bank > 9.0 \
				or _kit_ground.road.any(func(rp: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, rp)) \
				or _kit_items.any(func(it: Dictionary) -> bool: return it.has("wreck") and (it.wreck as Vector2).distance_to(p) < 12.0):
			continue
		var piece: String = ["school_bus", "motorhome", "ice_cream_truck", "car_sedan_01", "car_crossover_02",
			"police_sedan", "car_minivan_01"][_kit_rng.randi_range(0, 6)]
		var part := CityKit.prop_part(piece, p, _kit_rng.randf() * TAU)
		var sink := Transform3D(Basis(Vector3(_kit_rng.randf_range(-1, 1), 0.0, _kit_rng.randf_range(-1, 1)).normalized(),
			deg_to_rad(_kit_rng.randf_range(8.0, 22.0))), Vector3(p.x, WATER_SURFACE_Y - (part.box as AABB).size.y * 0.45, p.y))
		var xf: Transform3D = sink * Transform3D(Basis.IDENTITY, -Vector3(p.x, 0.0, p.y)) * part.xf
		_kit_items.append({"piece": piece, "folder": part.folder, "xf": xf, "holder": "", "wreck": p})
		wrecks += 1

	# 버스 차고지: an abandoned army checkpoint in the yard (tents, sandbags, vehicles, supplies).
	var depot := _poly(_zones.depot_lm)
	placed += _poi_row(["military_truck_01", "military_apc", "military_utility_vehicle"], 3, 3.6, depot, keep_out, routes)
	for piece: String in ["military_arched_tent_exterior", "military_command_tent_exterior", "military_field_canopy_01",
			"guard_booth", "checkpoint_sign_trailer", "military_light_tower_big", "military_generator_large",
			"portable_field_toilet", "hesco_barrier_01", "hesco_barrier_02", "hesco_barrier_01", "hesco_barrier_02",
			"sandbag_pile_02", "sandbag_pile_04", "sandbag_pile_06", "sandbag_pile_01", "anti_tank_hedgehog",
			"anti_tank_hedgehog", "anti_tank_hedgehog", "concrete_road_barrier", "striped_concrete_barrier",
			"road_barricade", "military_sign_stop", "military_ammo_crate_large", "military_rifle_crate",
			"military_meal_crate", "military_equipment_case", "military_vehicle_parts_crate", "military_fuel_barrel",
			"military_fuel_barrel", "military_fuel_barrel", "military_folding_table", "military_folding_chair",
			"spike_strip"]:
		placed += int(_poi_try(piece, depot, keep_out, routes, piece not in ["spike_strip", "military_folding_chair"]))
	# 하역장: a trailer yard by the stalled trucks, pallets and junk between them.
	var dock := _poly(_zones.dock_lm)
	placed += _poi_row(["dry_van_trailer"], 3, 3.4, dock, keep_out, routes)
	placed += _poi_row(["dry_van_trailer"], 2, 3.4, dock, keep_out, routes)
	for piece: String in ["pallet", "pallet", "commercial_dumpster_01", "pile_garbage_03", "curbside_trash_bin_01",
			"wheelbarrow", "pallet", "military_fuel_barrel", "barrel_01", "barrel_02", "barrel_01", "hesco_barrier_01",
			"store_inventory_stack_02", "store_inventory_stack_01"]:
		placed += int(_poi_try(piece, dock, keep_out, routes, piece not in ["pallet"]))
	# 해솔마트 앞: rows of cars left in the car park.
	var mart_lot := _poly(_zones.mart_lm)
	for k in 3:
		placed += _poi_row(KIT_CARS, 4, 2.9, mart_lot, keep_out, routes)
	# 주유소: a tanker and a mail truck stalled by the pumps.
	placed += _poi_row(["tanker_truck", "ice_cream_truck"], 1, 0.0, _poly(_zones.gas_lm), keep_out, routes)
	print("pois: %d pieces, %d deck cars, %d wrecks" % [placed, deck_cars, wrecks])


## Where the ramp line (map hidden route) leaves the deck polygon.
func _ramp_top(deck: PackedVector2Array) -> Vector2:
	var route: Dictionary = _map.hidden_routes[0]
	var from := _xz(route.from.position)
	var to := _xz(route.to.position)
	for i in deck.size():
		var hit = Geometry2D.segment_intersects_segment(from, to, deck[i], deck[(i + 1) % deck.size()])
		if hit != null:
			return hit
	push_error("Hidden route does not cross the deck edge")
	return from
