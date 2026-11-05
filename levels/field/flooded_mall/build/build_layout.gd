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

const MAP_PATH := "res://levels/field/flooded_mall/build/flooded_mall_map.json"
const OUT_SCENE := "res://levels/field/flooded_mall/layout.tscn"
const OUT_NAVMESH := "res://levels/field/flooded_mall/layout_navmesh.res"

const WALL_H := {"mart_in": 4.0}
const UPPER_WALL_H := 3.5
const BLOCKED_H := {"rubble": 3.5}
const RAMP_WIDTH := 3.5

## Doors: zone id -> [[x, z, width], ...] in map file coordinates (scaled on use, width is not).
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
const LANDMARK_LOOT := {
	"depot_lm": ["TOOLBOX", "TOOLBOX", "DRAWER"],
	"dock_lm": ["TOOLBOX", "DRAWER"],
	"gas_lm": ["TOOLBOX"],
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

	upper.add_child(_roof("Roof2F", shop2_in, y2 + UPPER_WALL_H, &"shop2_in"))

	# Hidden loading ramp: from the deck edge down toward the dock (map hidden_routes[0].to).
	# Its length (so its slope) is the unscaled one; the scaled rest of the route is ground.
	var route: Dictionary = _map.hidden_routes[0]
	var to := _xz(route.to.position)
	var dir := (to - ramp_top).normalized()
	var foot := ramp_top + dir * ramp_top.distance_to(to) / MAP_SCALE
	var side := Vector2(-dir.y, dir.x) * RAMP_WIDTH * 0.5
	_structure_keep_out.append(PackedVector2Array([ramp_top + side, foot + side, foot - side, ramp_top - side]))
	var ramp := _ramp("LoadingRamp", ramp_top - dir * 0.15, foot, RAMP_WIDTH, 0.0, y2, "road")
	_nav(ramp)
	mall.add_child(ramp)

	var zones_node := _root.get_node("IndoorZones")
	zones_node.add_child(_indoor_zone(&"shop_in", [shop_in], 0.0, y2 - SLAB))
	zones_node.add_child(_indoor_zone(&"shop2_in", [shop2_in], y2, y2 + UPPER_WALL_H))


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
