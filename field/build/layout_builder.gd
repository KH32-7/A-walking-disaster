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
##
## B-26 pack dressing (when the private assets/ submodule is here): the region's kit buildings
## (kit_buildings) follow their plans instead of the map file outlines, the layout gets their
## collision plus greybox boxes, and out_kit gets the American Suburb and Redwood pack meshes on the
## same parts: buildings, splat-mapped ground, vehicles, clutter, trees, rocks, ground cover, street
## furniture. The game hides the greybox (group kit_greybox) when it loads out_kit.

const INDOOR_ZONE_SCRIPT := "res://field/camera/indoor_zone.gd"
const CityKit := preload("res://field/buildings/city_kit.gd")
const KitScatter := preload("res://field/buildings/kit_scatter.gd")
const GroundSplat := preload("res://field/buildings/ground_splat.gdshader")
## Greybox stand-ins of the kit dressing. The region scene hides them when the pack meshes load.
const KIT_GREYBOX_GROUP := &"kit_greybox"
## Markers inside kit buildings must be this far from walls and furniture.
const KIT_MARKER_CLEAR := 0.3
## B-26 kit dressing: mesh picks and plants use their own seed so the layout seeds keep the map as is.
const KIT_SEED := 20261108
## Kit ground: one mesh over the land 1 cm up, textures picked by a baked splat map (ground_splat).
const KIT_TERRAIN := {
	"land_a": "res://assets/environment/nature/pure_nature_redwood/textures/terrain/grass_mud_a.png",
	"land_b": "res://assets/environment/nature/pure_nature_redwood/textures/terrain/soil_pine_a.png",
	"vegetation": "res://assets/environment/nature/pure_nature_redwood/textures/terrain/grass01_a.png",
	"road": "res://assets/environment/city/american_suburb/textures/terrain/road.png",
	"dirt": "res://assets/environment/nature/pure_nature_redwood/textures/terrain/mud_a.png",
}
const KIT_GROUND_LIFT := 0.01
## Splat map: metres per pixel, and blur radius in metres for R road, G vegetation, B dirt.
const SPLAT_RES := 0.5
const SPLAT_BLUR := Vector3(1.0, 2.5, 2.5)
const KIT_CARS := ["car_sedan_01", "car_sedan_02", "car_sedan_03", "car_crossover_01", "car_crossover_02",
	"car_crossover_04", "car_crossover_05", "car_minivan_01", "police_sedan", "car_sport_01"]
## Clutter kinds drawn with pack meshes; their box takes the mesh size.
const KIT_CLUTTER := {
	"Crate": ["barrel_01", "barrel_02", "plastic_barrel_02", "curbside_trash_bin_01", "curbside_trash_bin_03",
		"tool_cabinet", "pile_garbage_02"],
	"CratePile": ["pile_garbage_01", "pile_garbage_03", "commercial_dumpster_02"],
	"Dumpster": ["commercial_dumpster_01", "commercial_dumpster_02", "commercial_dumpster_03"],
}
## Redwood conifers, full and dense (user feedback 2026-11-05), a few broadleaf trees from the city pack.
const KIT_TREES := ["red_fir4", "red_fir5", "red_fir6", "red_fir7", "red_fir8", "red_pine2", "red_pine3",
	"red_fir4", "red_fir6", "red_pine2", "maple_01"]
## Extra trees on open land (with trunk collision), one try per this many m2.
const LAND_TREE_AREA := 120.0
const KIT_ROCKS := ["boulder_0", "boulder_1", "boulder_2", "boulder_4", "boulder_5"]
## Ground cover: [pieces per m2, pieces] for vegetation zones, open land and roads. No collision.
## User feedback 2026-11-05: too empty, so dense.
const KIT_PLANTS := {
	"vegetation": [1.0, ["grass_1", "grass_2", "grass_3", "thin_fern1", "thin_fern2", "thin_fern3", "thin_fern4",
		"magnus_1", "magnus_2", "bushes_04", "bushes_06", "bushes_07", "bushes_08", "bushes_02", "bushes_05",
		"grass_04", "grass_05", "fern_01_1", "fern_02_1", "clovers_2", "fungi_polyp_1", "dead_leaves_2"]],
	"land": [0.2, ["grass_1", "grass_2", "grass_06", "grass_01", "grass_02", "clovers_1", "clovers_2",
		"dead_leaves_1", "dead_leaves_2", "branches", "rubble_sparse_1", "thin_fern1", "magnus_1"]],
	"road": [0.02, ["dead_leaves_1", "dead_leaves_2", "rubble_sparse_2", "rubble_sparse_3", "branches", "grass_06"]],
}
## Overgrowth bands along every edge (roads, buildings, water banks, vegetation zones) so no edge reads
## as a straight line: one piece every EDGE_STEP metres, up to EDGE_REACH metres out.
const KIT_EDGE_PLANTS := ["grass_3", "grass_2", "grass_04", "grass_05", "thin_fern3", "thin_fern4", "magnus_2",
	"bushes_04", "bushes_06", "bushes_07", "bushes_08", "fern_02_1", "grass_03"]
const EDGE_STEP := 0.8
const EDGE_REACH := 2.2
## Street furniture along road edges: one try every STREET_STEP metres, STREET_OUT metres off the road.
const STREET_PROPS := ["fire_hydrant_01", "fire_hydrant_02", "urn_street_01", "urn_street_02",
	"curbside_trash_bin_01", "curbside_trash_bin_03", "parking_lot_light_pole_01", "parking_lot_light_pole_01",
	"utility_cabinet_01", "sign_stop", "sign_speed_limit", "sign_dead_end", "sign_children", "traffic_cone_big",
	"trash_bag_01", "trash_bag_02"]
const STREET_STEP := 9.0
## Loose props (street furniture, clutter, special places) drawn larger than life so they read from
## the top-down camera (user feedback 2026-11-05). Their collision follows.
const PROP_SCALE := 1.3
const STREET_OUT := 1.3
## Outside the map: a forest ring OUTSKIRT metres wide, roads running on into it with backdrop
## buildings beside them, water carried on where it meets the edge, a dark ground plane beyond.
const OUTSKIRT := 45.0
const OUTSKIRT_TREE_STEP := 2.6
const OUTSKIRT_TREES := ["red_fir5", "red_fir6", "red_fir7", "red_fir8", "red_pine3", "red_pine4", "red_pine2",
	"red_fir4"]
const OUTSKIRT_GIANTS := ["sequoia1", "sequoia2", "sequoia3"]
const OUTSKIRT_UNDER := ["bushes_02", "bushes_05", "bushes_03", "thin_fern4", "grass_3", "fern_02_1", "magnus_2"]
const OUTSKIRT_BUILDINGS := ["motel", "roadside_fast_food", "sheriff_substation", "convenience_store",
	"fuel_mart", "fire_station", "exterior_only_house_01", "exterior_only_house_02", "exterior_only_house_03",
	"exterior_only_house_04", "exterior_only_house_05", "exterior_only_house_06", "exterior_only_house_07",
	"exterior_only_house_08"]
const OUTSKIRT_FAR_COLOR := Color(0.1, 0.13, 0.11)
const WATER_SHADER := preload("res://art/shaders/water_toon.gdshader")
## Roads: pack sidewalk with curb along every road edge that meets land, lane lines down the middle
## of straight roads, power poles with wires along long edges.
const SIDEWALK := {8: "sidewalk_curbstone_a_8m", 4: "sidewalk_curbstone_a_4m", 2: "sidewalk_curbstone_a_2m"}
const POLE_STEP := 20.0
## Junk along building walls (outside).
const WALL_JUNK := ["trash_bag_01", "trash_bag_02", "barrel_01", "barrel_02", "pallet", "curbside_trash_bin_01",
	"conditioner_07", "conditioner_08", "plastic_barrel_02", "pile_garbage_02", "firewood_rack", "wheelbarrow",
	"military_fuel_barrel", "cardboard_box_01", "store_inventory_stack_02"]
const WALL_JUNK_STEP := 4.5
const POLE_OUT := 3.4
const SHOP_INSET := 2.5
const SHOP_CLEAR := 2.4

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
## User feedback 2026-11-05 (B-26): the map felt empty, 5 m -> 3 m.
const TREE_SPACING := 3.0
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
## B-26: 300 -> 150 (user feedback 2026-11-05: farming felt thin).
const LOOT_AREA_PER_SPOT := 150.0
const LOOT_WALL_INSET := 1.0
const LOOT_SPACING := 4.0
const LOOT_CLEAR_DOOR := 2.5

## Greybox clutter on open ground so the map is not empty (user feedback 2026-11-05).
## Seeded clusters (clutter_kits). Pieces up to LOW_COVER_MAX_H are low cover, taller ones block.
## Clusters keep clear of roads, water, buildings, vegetation, markers, doors, extract points
## and the demo routes. Clusters on the unscaled map; the count grows with the area like the rocks.
## B-26: 26 -> 40 (user feedback 2026-11-05: denser, like the reference game).
const CLUTTER_CLUSTERS := 40
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
## B-26 kit dressing. kit_buildings: indoor zone id -> [plan, spec] (field/buildings/city_kit.gd parts()).
## out_kit: the pack dressing scene; out_splat: its ground splat map. kit_cover: cover/blocker prop
## name -> kind drawn with pack meshes (see _kit_cover). shop_fill: [[zone id, "shelves"|"tables",
## m2 per item]] for big interiors.
var kit_buildings := {}
var out_kit := ""
var out_splat := ""
var kit_cover := {}
var shop_fill := []

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
## Kit building zone id -> CityKit.parts() (B-26).
var _kit := {}
## B-26 pack meshes to place: [{piece, xf}] (collision is in the layout), ground cover
## piece -> PackedFloat32Array (x, y, z, yaw, scale), ground polygons by KIT_GROUND key.
var _kit_items: Array[Dictionary] = []
var _kit_plants := {}
var _kit_ground := {"land": [], "road": [], "vegetation": [], "water": []}
var _kit_rng := RandomNumberGenerator.new()
## Layout CSG path -> [texture, tile]: textured at runtime when the kit loads (flooded_mall.gd).
var _kit_skins := {}


func _initialize() -> void:
	var text := FileAccess.get_file_as_string(map_path)
	_map = JSON.parse_string(text)
	if _map.is_empty():
		push_error("Cannot read %s" % map_path)
		quit(1)
		return
	for zone: Dictionary in _map.zones:
		_zones[zone.id] = zone
	for id: String in kit_buildings:
		var b: Array = kit_buildings[id]
		_kit[id] = CityKit.parts(b[0], b[1])
	_kit_rng.seed = KIT_SEED
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
	_build_street()
	_build_shop_fill()
	_build_pois()
	_build_roadside()
	_build_wall_dressing()
	_build_nature()
	_build_bounds()
	_build_outskirts()
	_build_markers()
	_check_kit_markers()
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
	var kit_err := _save_buildings()
	quit(0 if ok and err == OK and kit_err == OK else 1)


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
	_kit_ground.land.append_array(land)
	_kit_ground.land.append_array(crossings)
	_kit_ground.water.append_array(deep)
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
			var overlay := _prism(_title(zone.id), _poly(zone), 0.0, OVERLAY_Y[kind], kind, false)
			overlays.add_child(overlay)
			# B-26: roads and vegetation are painted into the kit ground (splat map) instead.
			if _kit_ground.has(kind):
				_kit_ground[kind].append(_poly(zone))
				overlay.add_to_group(KIT_GREYBOX_GROUP, true)

	var blocked := Node3D.new()
	blocked.name = "Blocked"
	_root.add_child(blocked)
	for zone: Dictionary in _map.zones:
		if zone.kind == "blocked":
			var shape := _prism(_title(zone.id), _poly(zone), 0.0, blocked_h.get(zone.id, DEFAULT_BLOCKED_H), "blocked", true)
			_nav(shape)
			blocked.add_child(shape)
			if zone.id.begins_with("bus"):
				shape.add_to_group(KIT_GREYBOX_GROUP, true)
				_kit_bus_row(_bounds(_poly(zone)))
			elif zone.id == "rubble":
				shape.add_to_group(KIT_GREYBOX_GROUP, true)
				_kit_rubble(_poly(zone), blocked_h.get(zone.id, DEFAULT_BLOCKED_H))


# --- buildings -------------------------------------------------------------

func _build_buildings() -> void:
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	_root.add_child(buildings)
	var zones_node := _indoor_zones_node()
	for zone: Dictionary in _map.zones:
		if zone.kind != "indoor" or zone.floor != 0 or zone.id in custom_buildings:
			continue
		if _kit.has(zone.id):
			_build_kit_building(buildings, zones_node, zone)
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
		var roof := _roof("Roof", poly, h, zone.id)
		building.add_child(roof)
		zones_node.add_child(_indoor_zone(zone.id, [poly], 0.0, h))
		# B-26: pack shopfront, tile floor and a gravel roof over the hidden greybox.
		walls.add_to_group(KIT_GREYBOX_GROUP, true)
		roof.add_to_group(KIT_GREYBOX_GROUP, true)
		_kit_ring(poly, 0.0, h, _doors(zone.id), [], "shop")
		_kit_floor(poly, CityKit.FLOOR_Y, "", [])
		_kit_roof(poly, h + ROOF_T, "roof:%s" % zone.id)


## B-26 kit building: collision from its plan (walls with door gaps, furniture), greybox boxes for
## clones without the pack, and its IndoorZone. The pack meshes go to buildings.tscn.
func _build_kit_building(parent: Node3D, zones_node: Node3D, zone: Dictionary) -> void:
	var parts: Dictionary = _kit[zone.id]
	var poly := _poly(zone)
	var building := Node3D.new()
	building.name = _title(zone.id)
	parent.add_child(building)
	var floor_shape := _prism("Floor", poly, 0.0, OVERLAY_Y.floor, "floor", false)
	floor_shape.add_to_group(KIT_GREYBOX_GROUP, true)
	building.add_child(floor_shape)
	building.add_child(_kit_body("Walls", parts.walls, "wall"))
	var props: Array = CityKit.prop_boxes(parts)
	if not props[0].is_empty():
		building.add_child(_kit_body("Furniture", props[0], "blocked"))
	if not props[1].is_empty():
		var low := _kit_body("LowFurniture", props[1], "cover")
		low.add_to_group(LOW_COVER_GROUP, true)
		building.add_child(low)
	var roof := _roof("Roof", poly, CityKit.WALL_H, zone.id)
	roof.add_to_group(KIT_GREYBOX_GROUP, true)
	building.add_child(roof)
	zones_node.add_child(_indoor_zone(zone.id, [poly], 0.0, CityKit.WALL_H))


## World-layer static body with one box shape per AABB, plus a greybox mesh per box.
func _kit_body(node_name: String, boxes: Array, mat: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = LAYER_WORLD_BIT
	body.collision_mask = 0
	_nav(body)
	for i in boxes.size():
		var box: AABB = boxes[i]
		var shape := BoxShape3D.new()
		shape.size = box.size
		var cs := CollisionShape3D.new()
		cs.name = "Shape%d" % i
		cs.shape = shape
		cs.position = box.get_center()
		body.add_child(cs)
		var mesh := BoxMesh.new()
		mesh.size = box.size
		mesh.material = _mats[mat]
		var grey := MeshInstance3D.new()
		grey.name = "Grey%d" % i
		grey.mesh = mesh
		grey.position = box.get_center()
		grey.add_to_group(KIT_GREYBOX_GROUP, true)
		body.add_child(grey)
	return body


## B-26: map file and extra markers inside kit buildings must keep clear of walls and furniture.
func _check_kit_markers() -> void:
	var points: Array[Vector3] = []
	for m: Dictionary in _map.markers:
		if m.floor == 0:
			points.append(Vector3(m.position[0] * MAP_SCALE, 0.0, m.position[2] * MAP_SCALE))
	for m: Dictionary in _extra_markers:
		if m.pos.y < 1.0:
			points.append(m.pos)
	for id: String in _kit:
		var parts: Dictionary = _kit[id]
		var props: Array = CityKit.prop_boxes(parts)
		var boxes: Array = parts.walls + props[0] + props[1]
		for p in points:
			if not (parts.rect as Rect2).has_point(Vector2(p.x, p.z)):
				continue
			for box: AABB in boxes:
				if box.grow(KIT_MARKER_CLEAR).has_point(Vector3(p.x, 0.5, p.z)):
					push_warning("Kit %s: marker at (%.1f, %.1f) is in a wall or prop" % [id, p.x, p.z])
					break


## B-26: pack dressing -> buildings.tscn: kit buildings, textured ground, vehicles, clutter, trees,
## rocks, street furniture, mall interiors (scene instances) and ground cover (KitScatter, built at
## runtime). Only paths and placements are saved, never pack mesh data. Needs the private assets/
## submodule; without it the saved buildings.tscn stays as it is.
func _save_buildings() -> Error:
	if out_kit.is_empty():
		return OK
	if not CityKit.available():
		push_warning("assets/ pack missing, %s not rebuilt" % out_kit)
		return OK
	var root := Node3D.new()
	root.name = "FloodedMallKit"
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	root.add_child(buildings)
	for id: String in kit_buildings:
		var b: Array = kit_buildings[id]
		CityKit.build_meshes(buildings, StringName(id), b[0], b[1], _kit[id])
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = _flat_mesh(_kit_ground.land, KIT_GROUND_LIFT)
	var mat := ShaderMaterial.new()
	mat.shader = GroundSplat
	mat.set_shader_parameter(&"splat_map", _bake_splat())
	mat.set_shader_parameter(&"splat_origin", Vector2(-MAP_HALF, -MAP_HALF))
	mat.set_shader_parameter(&"splat_size", Vector2(MAP_HALF, MAP_HALF) * 2.0)
	for key: String in KIT_TERRAIN:
		mat.set_shader_parameter(StringName(key), load(KIT_TERRAIN[key]))
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	var holders := {"": props}
	for item: Dictionary in _kit_items:
		var parent := _kit_holder(holders, item.get("holder", ""))
		if item.has("slab"):
			var mi := MeshInstance3D.new()
			mi.name = "Slab"
			mi.mesh = _flat_mesh([item.slab], item.y)
			mi.material_override = CityKit.ground_material(item.texture, item.tile, item.get("tint", Color.WHITE))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi, true)
		elif item.has("water"):
			var water := MeshInstance3D.new()
			water.name = "Water"
			water.mesh = _flat_mesh([item.water], WATER_SURFACE_Y)
			var wm := ShaderMaterial.new()
			wm.shader = WATER_SHADER
			water.material_override = wm
			parent.add_child(water, true)
		elif item.has("far"):
			var far := MeshInstance3D.new()
			far.name = "FarGround"
			var plane := PlaneMesh.new()
			plane.size = Vector2.ONE * item.far
			var fm := StandardMaterial3D.new()
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.albedo_color = OUTSKIRT_FAR_COLOR
			plane.material = fm
			far.mesh = plane
			far.position.y = -0.05
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(far, true)
		else:
			CityKit.place(parent, item.folder, item.piece, item.xf)
	var skins := {}
	for path: String in _kit_skins:
		var skin: Array = _kit_skins[path]
		skins[NodePath(path)] = CityKit.ground_material(skin[0], skin[1])
	root.set_meta(&"layout_skins", skins)
	var scatter := Node3D.new()
	scatter.name = "GroundCover"
	scatter.set_script(KitScatter)
	var scenes := PackedStringArray()
	var data: Array[PackedFloat32Array] = []
	for path: String in _kit_plants:
		scenes.append(path)
		data.append(_kit_plants[path])
	scatter.set(&"scenes", scenes)
	scatter.set(&"instances", data)
	root.add_child(scatter)
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, out_kit)
	print("buildings: %s, nodes: %d" % [error_string(err), _count(root)])
	root.free()
	return err


## Splat map over the whole region (R road, G vegetation, B dirt along building bases and water banks),
## blurred so the shader can break the edges with noise. Saved as our own resource (not pack data).
func _bake_splat() -> ImageTexture:
	var n := int(MAP_HALF * 2.0 / SPLAT_RES)
	var channels: Array[PackedFloat32Array] = []
	for c in 3:
		var a := PackedFloat32Array()
		a.resize(n * n)
		channels.append(a)
	var dirt_polys: Array = []
	for zone: Dictionary in _map.zones:
		if zone.floor == 0 and zone.kind in ["indoor", "blocked"]:
			dirt_polys.append_array(Geometry2D.offset_polygon(_poly(zone), 1.5))
	for w: PackedVector2Array in _kit_ground.water:
		dirt_polys.append_array(Geometry2D.offset_polygon(w, 2.0))
	var sources := [_kit_ground.road, _kit_ground.vegetation, dirt_polys]
	for c in 3:
		for poly: PackedVector2Array in sources[c]:
			_raster(channels[c], n, poly)
		var radius := maxi(1, roundi(SPLAT_BLUR[c] / SPLAT_RES))
		for pass_i in 2:
			_box_blur(channels[c], n, radius)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var i := y * n + x
			img.set_pixel(x, y, Color(channels[0][i], channels[1][i], channels[2][i]))
	var tex := ImageTexture.create_from_image(img)
	var err := ResourceSaver.save(tex, out_splat, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Cannot save %s: %s" % [out_splat, error_string(err)])
	tex.take_over_path(out_splat)
	return tex


## Sets pixels whose centers are inside poly to 1.
func _raster(ch: PackedFloat32Array, n: int, poly: PackedVector2Array) -> void:
	var b := _bounds(poly)
	var x0 := clampi(floori((b.position.x + MAP_HALF) / SPLAT_RES), 0, n - 1)
	var x1 := clampi(ceili((b.end.x + MAP_HALF) / SPLAT_RES), 0, n - 1)
	var y0 := clampi(floori((b.position.y + MAP_HALF) / SPLAT_RES), 0, n - 1)
	var y1 := clampi(ceili((b.end.y + MAP_HALF) / SPLAT_RES), 0, n - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2((x + 0.5) * SPLAT_RES - MAP_HALF, (y + 0.5) * SPLAT_RES - MAP_HALF)
			if Geometry2D.is_point_in_polygon(p, poly):
				ch[y * n + x] = 1.0


## Separable box blur (running sums), edges clamped.
func _box_blur(ch: PackedFloat32Array, n: int, r: int) -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(n * n)
	var w := float(2 * r + 1)
	for y in n:
		var sum := 0.0
		for k in range(-r, r + 1):
			sum += ch[y * n + clampi(k, 0, n - 1)]
		for x in n:
			tmp[y * n + x] = sum / w
			sum += ch[y * n + clampi(x + r + 1, 0, n - 1)] - ch[y * n + clampi(x - r, 0, n - 1)]
	for x in n:
		var sum := 0.0
		for k in range(-r, r + 1):
			sum += tmp[clampi(k, 0, n - 1) * n + x]
		for y in n:
			ch[y * n + x] = sum / w
			sum += tmp[clampi(y + r + 1, 0, n - 1) * n + x] - tmp[clampi(y - r, 0, n - 1) * n + x]


## Node for a holder key: "roof:<zone>" nodes are IndoorZone roofs (group + building_id meta),
## "a/b" nests b under a.
func _kit_holder(holders: Dictionary, key: String) -> Node3D:
	if holders.has(key):
		return holders[key]
	var parent: Node3D = holders[""]
	var name_part := key
	if "/" in key:
		parent = _kit_holder(holders, key.get_slice("/", 0))
		name_part = key.get_slice("/", 1)
	var node := Node3D.new()
	node.name = name_part.replace(":", "_").to_pascal_case()
	if name_part.begins_with("roof:"):
		node.add_to_group(CityKit.ROOF_GROUP, true)
		node.set_meta(CityKit.ROOF_META, StringName(name_part.get_slice(":", 1)))
	parent.add_child(node)
	holders[key] = node
	return node


## Flat ArrayMesh of the polygons at height y, facing up.
func _flat_mesh(polys: Array, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for poly: PackedVector2Array in polys:
		var tris := Geometry2D.triangulate_polygon(poly)
		if tris.is_empty():
			push_warning("Kit ground: cannot triangulate a polygon of %d points" % poly.size())
		for i in range(0, tris.size(), 3):
			# Counter-clockwise from above.
			for k in [0, 2, 1]:
				var q := poly[tris[i + k]]
				st.add_vertex(Vector3(q.x, y, q.y))
	return st.commit()


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		if child.scene_file_path.is_empty():
			_own(child, owner_node)


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
		# Kit buildings (B-26) line their walls with furniture; a spot may stand closer to it.
		var prop_clear := 0.5 if _kit.has(zone.id) else 1.0
		var placed := 0
		for attempt in want * 50:
			if placed >= want:
				break
			var hit := _point_on_ring(ring, rng.randf())
			var p: Vector2 = hit[0]
			if not Geometry2D.is_point_in_polygon(p, poly) or _loot_excluded(p) \
					or _in_prop(p, prop_clear) or _near_door(p, doors, LOOT_CLEAR_DOOR) \
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
	for id: String in _kit:
		doors.append_array(_kit[id].doors)
	var total_weight := 0
	for kit: Array in clutter_kits:
		total_weight += kit[1]
	var cover := _root.get_node("LowCover")
	var blockers := _root.get_node("Props")
	var cover_kit := _root.get_node("LowCoverKit")
	var blockers_kit := _root.get_node("PropsKit")
	var centers := PackedVector2Array()
	var want := roundi(CLUTTER_CLUSTERS * MAP_SCALE * MAP_SCALE)
	var pieces := 0
	for attempt in want * 80:
		if centers.size() >= want:
			break
		var kit := _pick_kit(rng.randi_range(0, total_weight - 1))
		var c := Vector2(rng.randf_range(-MAP_HALF, MAP_HALF), rng.randf_range(-MAP_HALF, MAP_HALF))
		var yaw := rng.randf() * TAU
		var dressed := _kit_clutter(kit[2])
		var kit_pieces: Array = dressed.map(func(d: Array) -> Array: return d[0])
		var radius := _kit_radius(kit_pieces)
		if _near(c, centers, CLUTTER_SPACING) or _near(c, extracts, CLUTTER_CLEAR_EXTRACT + radius) \
				or _near_door(c, doors, CLUTTER_CLEAR_DOOR + radius) \
				or not _open(c, keep_out, routes, CLUTTER_CLEAR_ROUTE + radius) or _near_points(c, points, radius):
			continue
		var fits := true
		for piece: Array in kit_pieces:
			for corner in _piece_corners(c, yaw, piece):
				if not _open(corner, keep_out, [], 0.0):
					fits = false
		if not fits:
			continue
		centers.append(c)
		_taken.append(Vector3(c.x, c.y, radius + CLEAR_PROP))
		for i in dressed.size():
			var piece: Array = dressed[i][0]
			var mesh: String = dressed[i][1]
			var at := c + Vector2(piece[1], piece[2]).rotated(-yaw)
			var low: bool = piece[5] <= LOW_COVER_MAX_H
			var box := _box("Clutter%d_%s%d" % [centers.size(), piece[0], i], at, Vector2(piece[3], piece[4]), 0.0,
				piece[5], rad_to_deg(yaw) + piece[6], "cover" if low else "blocked")
			if mesh.is_empty():
				(cover if low else blockers).add_child(box)
			else:
				(cover_kit if low else blockers_kit).add_child(box)
				_kit_add(mesh, at, yaw + deg_to_rad(piece[6]) + dressed[i][3], 0.0, dressed[i][2])
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


## Within `margin` of a cover_props or blocker_props box (rotation included), or of a kit building's
## wall or furniture (B-26).
func _in_prop(p: Vector2, margin: float) -> bool:
	for b: Array in cover_props + blocker_props:
		var local := (p - Vector2(b[1], b[2]) * MAP_SCALE).rotated(deg_to_rad(b[6]))
		if absf(local.x) <= b[3] * 0.5 + margin and absf(local.y) <= b[4] * 0.5 + margin:
			return true
	for id: String in _kit:
		var parts: Dictionary = _kit[id]
		if not (parts.rect as Rect2).grow(margin).has_point(p):
			continue
		var props: Array = CityKit.prop_boxes(parts)
		for box: AABB in parts.walls + props[0] + props[1]:
			if box.grow(margin).has_point(Vector3(p.x, box.get_center().y, p.y)):
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
	trunks.add_to_group(KIT_GREYBOX_GROUP, true)
	_root.add_child(trunks)
	var crowns := Node3D.new()
	crowns.name = "TreeCrowns"
	crowns.add_to_group(KIT_GREYBOX_GROUP, true)
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
	# B-26: scattered trees on open land too, same clearances.
	var land_want := int(MAP_HALF * MAP_HALF * 4.0 / LAND_TREE_AREA)
	for attempt in land_want:
		var p := Vector2(rng.randf_range(-MAP_HALF, MAP_HALF), rng.randf_range(-MAP_HALF, MAP_HALF))
		if clear.call(p) and not _near(p, trees, TREE_SPACING * 1.6):
			trees.append(p)
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
		var tree: String = KIT_TREES[_kit_rng.randi_range(0, KIT_TREES.size() - 1)]
		# Full Redwood trees are 8 to 11 m; about 6 to 8 m keeps the top-down camera on the ground.
		var tree_h: float = (CityKit.PROPS[tree][2] as Vector3).y
		_kit_add(tree, p, _kit_rng.randf() * TAU, 0.0, _kit_rng.randf_range(6.0, 8.0) / maxf(tree_h, 6.0))

	# Rocks on any open ground, as low cover (shots pass over, close targets behind take x0.5).
	# B-26: drawn with pack boulders, so they live in the hidden LowCoverKit combiner.
	var cover := _root.get_node("LowCoverKit")
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
		# Boulder about as wide as the greybox rock, a quarter sunk.
		var boulder: String = KIT_ROCKS[_kit_rng.randi_range(0, KIT_ROCKS.size() - 1)]
		var info: Array = CityKit.PROPS[boulder]
		var s: float = rock.radius * 2.4 / (info[2] as Vector3).x
		var lift: float = -(info[1] as Vector3).y * s - (info[2] as Vector3).y * s * 0.3
		_kit_add(boulder, rocks[i], rock.rotation.y, lift, s)
	_build_ground_cover(trees)
	print("nature: %d trees, %d rocks" % [trees.size(), rocks.size()])


func _build_ground_cover(trees: PackedVector2Array) -> void:
	var water: Array = _kit_ground.water
	var buildings := _kit_blocked_polys()
	var doors := []
	for id: String in zone_doors:
		doors.append_array(_doors(id))
	for id: String in _kit:
		doors.append_array(_kit[id].doors)
	var count := 0
	var add := func(piece: String, p: Vector2, scale: float) -> void:
		var path := CityKit.piece_path(CityKit.PROPS[piece][0], piece)
		if not _kit_plants.has(path):
			_kit_plants[path] = PackedFloat32Array()
		_kit_plants[path].append_array([p.x, KIT_GROUND_LIFT, p.y, _kit_rng.randf() * TAU, scale])
	for key: String in KIT_PLANTS:
		var density: float = KIT_PLANTS[key][0]
		var pool: Array = KIT_PLANTS[key][1]
		var others: Array = []
		for k: String in ["road", "vegetation"]:
			if k != key and (key == "land" or (key == "road" and k == "vegetation")):
				others.append_array(_kit_ground[k])
		for poly: PackedVector2Array in _kit_ground[key]:
			var bounds := _bounds(poly)
			var want := int(_area(poly) * density)
			for attempt in want * 3:
				if want <= 0:
					break
				var p := Vector2(_kit_rng.randf_range(bounds.position.x, bounds.end.x),
					_kit_rng.randf_range(bounds.position.y, bounds.end.y))
				if not Geometry2D.is_point_in_polygon(p, poly) or _near(p, trees, 0.6) \
						or water.any(func(w: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, w)) \
						or buildings.any(func(b: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, b)) \
						or others.any(func(o: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, o)):
					continue
				want -= 1
				count += 1
				add.call(pool[_kit_rng.randi_range(0, pool.size() - 1)], p, _kit_rng.randf_range(0.9, 1.6))

	# Overgrowth bands just outside every edge.
	var edges: Array = []
	for key: String in ["road", "vegetation", "water"]:
		edges.append_array(_kit_ground[key])
	for zone: Dictionary in _map.zones:
		if zone.floor == 0 and zone.kind in ["indoor", "blocked"]:
			edges.append(_poly(zone))
	var banded := 0
	for poly: PackedVector2Array in edges:
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var length := a.distance_to(b)
			if length < 0.5:
				continue
			var dir := (b - a) / length
			var normal := Vector2(-dir.y, dir.x)
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + normal * 0.3, poly):
				normal = -normal
			var t := _kit_rng.randf() * EDGE_STEP
			while t < length:
				var p := a + dir * t + normal * _kit_rng.randf_range(0.15, EDGE_REACH) + dir * _kit_rng.randf_range(-0.3, 0.3)
				t += EDGE_STEP * _kit_rng.randf_range(0.6, 1.4)
				if _kit_ground.road.any(func(r: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, r)) \
						or water.any(func(w: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, w)) \
						or buildings.any(func(o: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, o)) \
						or _near_door(p, doors, 1.5) or _near(p, trees, 0.6) \
						or absf(p.x) > MAP_HALF - 0.5 or absf(p.y) > MAP_HALF - 0.5:
					continue
				banded += 1
				add.call(KIT_EDGE_PLANTS[_kit_rng.randi_range(0, KIT_EDGE_PLANTS.size() - 1)], p,
					_kit_rng.randf_range(1.0, 1.8))
	print("ground cover: %d pieces, %d along edges" % [count, banded])


## Where plants do not grow: kit buildings (their outline, porches, a lane out of each door), other
## buildings and blocked zones with a 1 m margin.
func _kit_blocked_polys() -> Array:
	var out := []
	for zone: Dictionary in _map.zones:
		if zone.floor == 0 and zone.kind in ["indoor", "blocked"] and not _kit.has(zone.id):
			out.append_array(Geometry2D.offset_polygon(_poly(zone), 1.0))
	for id: String in _kit:
		var parts: Dictionary = _kit[id]
		var porch: bool = kit_buildings[id][0].get("porch", false)
		out.append(_rect_poly((parts.rect as Rect2).grow(0.3)))
		for seg: Dictionary in parts.segments:
			if seg.inner or seg.kind != "e":
				continue
			var out_dir: Vector2 = -seg.inward
			var reach := 3.2 if porch else 2.5
			var a: Vector2 = seg.a
			var b: Vector2 = seg.b
			out.append(PackedVector2Array([a, b, b + out_dir * reach, a + out_dir * reach]))
	return out


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
				# Kit buildings (B-26) have a 2.8 m porch outside their outline.
				grow = CLEAR_BUILDING + (1.0 if _kit.has(zone.id) else 0.0)
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
	var blockers := _combiner("Props")
	_nav(blockers)
	_root.add_child(blockers)
	# B-26: pieces drawn with pack meshes keep their collision in combiners the game hides when the
	# pack loads (hidden CSG roots still collide).
	var cover_kit := _combiner("LowCoverKit")
	cover_kit.add_to_group(LOW_COVER_GROUP, true)
	cover_kit.add_to_group(KIT_GREYBOX_GROUP, true)
	_nav(cover_kit)
	_root.add_child(cover_kit)
	var blockers_kit := _combiner("PropsKit")
	blockers_kit.add_to_group(KIT_GREYBOX_GROUP, true)
	_nav(blockers_kit)
	_root.add_child(blockers_kit)
	for p: Array in cover_props:
		var box := _box(p[0], Vector2(p[1], p[2]) * MAP_SCALE, Vector2(p[3], p[4]), 0.0, p[5], p[6], "cover")
		(cover_kit if kit_cover.has(p[0]) else cover).add_child(box)
		if kit_cover.has(p[0]):
			_kit_cover(kit_cover[p[0]], Vector2(p[1], p[2]) * MAP_SCALE, Vector2(p[3], p[4]), p[6])
	for p: Array in blocker_props:
		var box := _box(p[0], Vector2(p[1], p[2]) * MAP_SCALE, Vector2(p[3], p[4]), 0.0, p[5], p[6], "blocked")
		(blockers_kit if kit_cover.has(p[0]) else blockers).add_child(box)
		if kit_cover.has(p[0]):
			_kit_cover(kit_cover[p[0]], Vector2(p[1], p[2]) * MAP_SCALE, Vector2(p[3], p[4]), p[6])


# --- B-26 kit dressing ---------------------------------------------------------

## Pack meshes over a greybox box (center, size xz, rotation in degrees). Long pieces follow the box's
## long side and are scaled to its length.
func _kit_cover(kind: String, center: Vector2, size: Vector2, rot_deg: float) -> void:
	var along_z := size.y > size.x
	var length := maxf(size.x, size.y)
	var yaw := deg_to_rad(rot_deg)
	match kind:
		"car", "truck":
			var piece: String = "truck" if kind == "truck" else KIT_CARS[_kit_rng.randi_range(0, KIT_CARS.size() - 1)]
			var mesh_len: float = (CityKit.PROPS[piece][2] as Vector3).x
			_kit_add(piece, center, yaw + (PI * 0.5 if along_z else 0.0), 0.0, length / mesh_len)
		"barricade":
			_kit_add("concrete_bump_5m", center, yaw + (0.0 if along_z else PI * 0.5), 0.0, length / 5.0)
		"pump":
			pass # Drawn by the gas station canopy's pump island (_build_pois); only the greybox hides.
		"shelves":
			_kit_shelf_row(center, yaw + (PI * 0.5 if along_z else 0.0), length, 0.0)


## A row of back-to-back retail shelves along the local X of yaw, centered.
func _kit_shelf_row(center: Vector2, yaw: float, length: float, y: float) -> void:
	var axis := Vector2(1.0, 0.0).rotated(-yaw)
	var normal := Vector2(-axis.y, axis.x)
	var width: float = (CityKit.PROPS.retail_shelf_01[2] as Vector3).z
	var depth: float = (CityKit.PROPS.retail_shelf_01[2] as Vector3).x
	var count := maxi(1, floori(length / width))
	for i in count:
		var at := center + axis * (width * (i + 0.5) - width * count * 0.5)
		# Back to back: the shelf on the +normal side faces +normal (row yaw + PI/2), the other -normal.
		_kit_add("retail_shelf_01", at + normal * depth * 0.5, yaw + PI * 0.5, y)
		_kit_add("retail_shelf_01", at - normal * depth * 0.5, yaw - PI * 0.5, y)


## Region hook (B-26): special places dressed with pack pieces. Runs after the street furniture,
## before the nature, so trees keep off what it takes (_taken).
func _build_pois() -> void:
	pass


## Junk against building walls (outside): bins, bags, barrels, pallets, AC units, meters. One try
## every WALL_JUNK_STEP metres of wall, clear of doors, routes and markers. Low ones are cover.
func _build_wall_dressing() -> void:
	var routes := _route_segments()
	var points := _keep_out_points()
	var doors := []
	for id: String in zone_doors:
		doors.append_array(_doors(id))
	for id: String in _kit:
		doors.append_array(_kit[id].doors)
	var outlines: Array = []
	for zone: Dictionary in _map.zones:
		if zone.floor == 0 and zone.kind == "indoor":
			outlines.append(_poly(zone))
	var water: Array = _kit_ground.water
	var roads: Array = _kit_ground.road
	var placed := 0
	for poly: PackedVector2Array in outlines:
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var length := a.distance_to(b)
			var dir := (b - a) / length
			var out := Vector2(-dir.y, dir.x)
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + out * 0.3, poly):
				out = -out
			var t := _kit_rng.randf_range(1.0, WALL_JUNK_STEP)
			while t < length - 1.0:
				var piece: String = WALL_JUNK[_kit_rng.randi_range(0, WALL_JUNK.size() - 1)]
				var yaw := atan2(out.y, -out.x) + PI # back (+X) to the wall
				var size := _kit_size(piece, yaw, PROP_SCALE)
				var depth := absf(Vector2(size.x, size.z).dot(out.abs()))
				var p := a + dir * t + out * (0.45 + depth * 0.5)
				t += WALL_JUNK_STEP * _kit_rng.randf_range(0.6, 1.5)
				var radius := maxf(size.x, size.z) * 0.5
				if _near_door(p, doors, 2.5 + radius) or _near_points(p, points, radius + 0.3) or _in_prop(p, 0.3) \
						or routes.any(func(sg: Array) -> bool:
							return p.distance_to(Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1])) < 1.2 + radius) \
						or water.any(func(w: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, w)) \
						or outlines.any(func(o: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, o)) \
						or absf(p.x) > MAP_HALF - 1.0 or absf(p.y) > MAP_HALF - 1.0:
					continue
				_kit_add(piece, p, yaw, 0.0, PROP_SCALE)
				_taken.append(Vector3(p.x, p.y, radius + 0.3))
				placed += 1
				if size.y >= CityKit.PROP_MIN_COLLIDE_H:
					var low := size.y <= LOW_COVER_MAX_H
					_root.get_node("LowCoverKit" if low else "PropsKit").add_child(_box("Wall_%s_%d" % [piece, placed],
						p, Vector2(size.x, size.z), 0.0, size.y, 0.0, "cover" if low else "blocked"))
	print("wall junk: %d" % placed)


## A row of count pieces side by side (spacing metres apart) somewhere open inside poly, like parked
## cars or trailers. Returns how many were placed (0 or count).
func _poi_row(pool: Array, count: int, spacing: float, poly: PackedVector2Array, keep_out: Array, routes: Array) -> int:
	var b := _bounds(poly)
	var points := _keep_out_points()
	for attempt in 120:
		var c := Vector2(_kit_rng.randf_range(b.position.x, b.end.x), _kit_rng.randf_range(b.position.y, b.end.y))
		var yaw := PI * 0.5 * _kit_rng.randi_range(0, 3)
		var across := Vector2(1.0, 0.0).rotated(-yaw - PI * 0.5)
		var spots: Array[Vector2] = []
		var pieces: Array[String] = []
		var ok := true
		for k in count:
			var p := c + across * spacing * (k - (count - 1) * 0.5)
			var piece: String = pool[_kit_rng.randi_range(0, pool.size() - 1)]
			var size := _kit_size(piece, yaw)
			var radius := maxf(size.x, size.z) * 0.5
			if not Geometry2D.is_point_in_polygon(p, poly) or not _open(p, keep_out, routes, CLEAR_ROUTE + radius * 0.6) \
					or _near_points(p, points, radius * 0.6 + 0.5) or _in_prop(p, radius * 0.6):
				ok = false
				break
			spots.append(p)
			pieces.append(piece)
		if not ok:
			continue
		for k in count:
			var yaw_k := yaw + _kit_rng.randf_range(-0.06, 0.06)
			var size := _kit_size(pieces[k], yaw_k)
			_kit_add(pieces[k], spots[k], yaw_k)
			_taken.append(Vector3(spots[k].x, spots[k].y, maxf(size.x, size.z) * 0.5 + 0.5))
			var low := size.y <= LOW_COVER_MAX_H
			_root.get_node("LowCoverKit" if low else "PropsKit").add_child(_box("Row_%s_%d" % [pieces[k], _taken.size()],
				spots[k], Vector2(size.x, size.z), 0.0, size.y, 0.0, "cover" if low else "blocked"))
		return count
	return 0


## One special-place piece somewhere open inside poly. collide: collision box from its bounds.
func _poi_try(piece: String, poly: PackedVector2Array, keep_out: Array, routes: Array, collide: bool) -> bool:
	var b := _bounds(poly)
	var points := _keep_out_points()
	for attempt in 80:
		var p := Vector2(_kit_rng.randf_range(b.position.x, b.end.x), _kit_rng.randf_range(b.position.y, b.end.y))
		var yaw := _kit_rng.randf() * TAU
		var size := _kit_size(piece, yaw, PROP_SCALE)
		var radius := maxf(size.x, size.z) * 0.5
		if not Geometry2D.is_point_in_polygon(p, poly) or not _open(p, keep_out, routes, CLEAR_ROUTE + radius) \
				or _near_points(p, points, radius + 0.5) or _in_prop(p, radius + 0.5):
			continue
		_kit_add(piece, p, yaw, 0.0, PROP_SCALE)
		_taken.append(Vector3(p.x, p.y, radius + 0.5))
		if collide and size.y >= CityKit.PROP_MIN_COLLIDE_H:
			var low := size.y <= LOW_COVER_MAX_H
			_root.get_node("LowCoverKit" if low else "PropsKit").add_child(_box("Poi_%s_%d" % [piece, _taken.size()],
				p, Vector2(size.x, size.z), 0.0, size.y, 0.0, "cover" if low else "blocked"))
		return true
	return false


func _dist_to_ring(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return best


func _kit_plant(piece: String, p: Vector2, y: float) -> void:
	var path := CityKit.piece_path(CityKit.PROPS[piece][0], piece)
	if not _kit_plants.has(path):
		_kit_plants[path] = PackedFloat32Array()
	_kit_plants[path].append_array([p.x, y, p.y, _kit_rng.randf() * TAU, _kit_rng.randf_range(0.8, 1.4)])


## Clutter kit pieces with pack meshes: [[piece (box sized to the mesh), mesh ("" = greybox), scale,
## mesh yaw offset]]. Cars keep their greybox box and are scaled to it.
func _kit_clutter(pieces: Array) -> Array:
	var out := []
	for piece: Array in pieces:
		var kind: String = piece[0]
		if kind == "Car":
			var car: String = KIT_CARS[_kit_rng.randi_range(0, KIT_CARS.size() - 1)]
			var along_z: bool = piece[4] > piece[3]
			out.append([piece, car, maxf(piece[3], piece[4]) / (CityKit.PROPS[car][2] as Vector3).x,
				PI * 0.5 if along_z else 0.0])
		elif kind in ["Barricade", "LowWall"]:
			# Concrete barrier scaled to the piece's long side. LowWall becomes "Barrier" so Lane D does
			# not grow vines on its hidden greybox box.
			var along_z: bool = piece[4] > piece[3]
			var length: float = maxf(piece[3], piece[4])
			var s: float = length / 5.0
			var bump: Vector3 = CityKit.PROPS.concrete_bump_5m[2]
			var w: float = bump.x * s
			out.append([["Barrier" if kind == "LowWall" else kind, piece[1], piece[2], w if along_z else length,
				length if along_z else w, bump.y * s, piece[6]], "concrete_bump_5m", s, 0.0 if along_z else PI * 0.5])
		elif KIT_CLUTTER.has(kind):
			var pool: Array = KIT_CLUTTER[kind]
			var mesh: String = pool[_kit_rng.randi_range(0, pool.size() - 1)]
			var size: Vector3 = (CityKit.PROPS[mesh][2] as Vector3) * PROP_SCALE
			out.append([[kind, piece[1], piece[2], size.x, size.z, size.y, piece[6]], mesh, PROP_SCALE, 0.0])
		else:
			out.append([piece, "", 1.0, 0.0])
	return out


## Bus wreck lane in a blocked rect: a school bus and two cars nose to tail along the long side.
func _kit_bus_row(rect: Rect2) -> void:
	var along_z := rect.size.y > rect.size.x
	var axis := Vector2(0.0, 1.0) if along_z else Vector2(1.0, 0.0)
	var length := maxf(rect.size.x, rect.size.y)
	var yaw := -PI * 0.5 if along_z else 0.0
	var pieces: Array[String] = ["school_bus", KIT_CARS[_kit_rng.randi_range(0, KIT_CARS.size() - 1)],
		KIT_CARS[_kit_rng.randi_range(0, KIT_CARS.size() - 1)]]
	var lengths: Array[float] = []
	var total := 0.0
	for p in pieces:
		lengths.append((CityKit.PROPS[p][2] as Vector3).x)
		total += lengths[-1] + 0.4
	var scale := minf(1.0, (length - 0.6) / total)
	var at := rect.get_center() - axis * total * scale * 0.5
	for i in pieces.size():
		var half := (lengths[i] + 0.4) * scale * 0.5
		at += axis * half
		_kit_add(pieces[i], at, yaw + _kit_rng.randf_range(-0.12, 0.12), 0.0, scale)
		at += axis * half


## Collapsed houses (blocked rubble zone): big boulders filling its greybox block, rubble heaps
## and a hollow log around them. The greybox prism keeps the collision.
func _kit_rubble(poly: PackedVector2Array, h: float) -> void:
	var inner := _largest(Geometry2D.offset_polygon(poly, -1.6))
	var bounds := _bounds(inner)
	var y := bounds.position.y
	while y <= bounds.end.y:
		var x := bounds.position.x
		while x <= bounds.end.x:
			var p := Vector2(x, y) + Vector2(_kit_rng.randf_range(-0.6, 0.6), _kit_rng.randf_range(-0.6, 0.6))
			x += 3.0
			if not Geometry2D.is_point_in_polygon(p, inner):
				continue
			var piece := "big_boulders_%d" % _kit_rng.randi_range(0, 3)
			var info: Array = CityKit.PROPS[piece]
			var s: float = h * _kit_rng.randf_range(0.75, 1.05) / ((info[2] as Vector3).y * 0.75)
			_kit_add(piece, p, _kit_rng.randf() * TAU, -(info[1] as Vector3).y * s - (info[2] as Vector3).y * s * 0.25, s)
		y += 3.0
	var outer := _bounds(poly)
	for i in 6:
		var p := Vector2(_kit_rng.randf_range(outer.position.x, outer.end.x), _kit_rng.randf_range(outer.position.y, outer.end.y))
		if Geometry2D.is_point_in_polygon(p, poly):
			_kit_add("rubble_dense_%d" % _kit_rng.randi_range(1, 3), p, _kit_rng.randf() * TAU, 0.0, _kit_rng.randf_range(0.6, 0.9))
	_kit_add("redwood_hollow_log2_1", outer.get_center(), _kit_rng.randf() * TAU, h * 0.5)


## Pack walls around a polygon over hidden greybox walls (exterior face on the outline), with gaps at
## doors (snapped to the nearest edge like _add_walls). kind: "shop" (windows and walls), "plain",
## "railing" (porch railing) or "parapet" (1 m wall). Walls taller than 3 m get a band on top.
func _kit_ring(poly: PackedVector2Array, y: float, h: float, doors: Array, skip: Array, kind: String,
		holder := "") -> void:
	var gaps := _edge_gaps(poly, doors)
	for i in poly.size():
		if i in skip:
			continue
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var inward := Vector2(-dir.y, dir.x)
		if not Geometry2D.is_point_in_polygon((a + b) * 0.5 + inward * 0.3, poly):
			inward = -inward
		var spans: Array[Vector2] = [Vector2(0.0, length)]
		var edge_gaps: Array = gaps.get(i, [])
		edge_gaps.sort_custom(func(g1: Vector2, g2: Vector2) -> bool: return g1.x < g2.x)
		for g: Vector2 in edge_gaps:
			var last: Vector2 = spans.pop_back()
			spans.append(Vector2(last.x, g.x))
			spans.append(Vector2(g.y, last.y))
		for span in spans:
			_kit_fill(a, dir, inward, span, y, h, kind, holder, i)


func _kit_fill(a: Vector2, dir: Vector2, inward: Vector2, span: Vector2, y: float, h: float, kind: String,
		holder: String, salt: int) -> void:
	var t := span.x
	var step := 0
	while span.y - t > 0.05:
		var left := span.y - t
		var want := 2
		var piece := ""
		match kind:
			"shop":
				want = 4 if step % 2 == 1 else 2
			"plain", "parapet":
				want = 4
		var length := want
		while length > 1 and length > left + 0.01:
			length /= 2
		if kind == "railing":
			length = 2
		var actual := minf(float(length), left)
		match kind:
			"shop":
				if step % 2 == 1 and length >= 2:
					var pool: Array = CityKit.WINDOW.a[length]
					piece = pool[absi(hash(str(salt) + str(step) + str(a))) % pool.size()]
				else:
					piece = CityKit.WALL.a[length]
			"plain":
				piece = CityKit.WALL.a[length]
			"parapet":
				piece = CityKit.PARAPET[length]
			"railing":
				piece = "house_porch_railing_a_2m"
		var piece_h := 3.0
		if kind == "parapet":
			piece_h = 1.0
		elif kind == "railing":
			piece_h = 1.06
		var seg := {"a": a + dir * t, "b": a + dir * (t + actual), "inward": inward, "inner": false}
		var lower := minf(h, piece_h) if kind in ["shop", "plain"] else h
		_kit_piece(piece, seg, y, lower / piece_h, actual / length, holder)
		if kind in ["shop", "plain"] and h > piece_h + 0.05:
			_kit_piece(CityKit.PARAPET[length], seg, y + piece_h, h - piece_h, actual / length, holder)
		t += actual
		step += 1


## A wall-convention pack piece over a segment, scaled to its height and length.
func _kit_piece(piece: String, seg: Dictionary, y: float, y_scale: float, z_scale: float, holder: String) -> void:
	var xf := CityKit._segment_xf(seg)
	xf.basis = Basis(xf.basis.x, xf.basis.y * y_scale, xf.basis.z * z_scale)
	xf.origin.y = y
	_kit_items.append({"piece": piece, "folder": CityKit.MODULES, "xf": xf, "holder": holder})


## Door gaps per polygon edge: edge index -> [Vector2(from, to)] along the edge (as _add_walls).
func _edge_gaps(poly: PackedVector2Array, doors: Array) -> Dictionary:
	var gaps := {}
	for door: Array in doors:
		var p := Vector2(door[0], door[1])
		var best := -1
		var best_dist := INF
		for i in poly.size():
			var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
			if q.distance_to(p) < best_dist:
				best_dist = q.distance_to(p)
				best = i
		var t := (Geometry2D.get_closest_point_to_segment(p, poly[best], poly[(best + 1) % poly.size()]) - poly[best]).length()
		gaps.get_or_add(best, []).append(Vector2(t - door[2] * 0.5, t + door[2] * 0.5))
	return gaps


## Tile floor over a polygon: 4 m tiles where they fit, 2 m tiles along the edges.
func _kit_floor(poly: PackedVector2Array, y: float, holder: String, skip: Array[Rect2]) -> void:
	var b := _bounds(poly)
	var fits := func(r: Rect2) -> bool:
		for q in _rect_poly(r):
			if not Geometry2D.is_point_in_polygon(q, poly):
				return false
		return not skip.any(func(s: Rect2) -> bool: return s.intersects(r))
	var z := b.position.y
	while z < b.end.y:
		var x := b.position.x
		while x < b.end.x:
			var big := Rect2(x, z, 4.0, 4.0)
			if fits.call(big):
				_kit_tile("house_floor_tile_4x4m", big, y, holder)
			else:
				for k in 4:
					var small := Rect2(x + (k % 2) * 2.0, z + (k / 2) * 2.0, 2.0, 2.0)
					if fits.call(small):
						_kit_tile("house_floor_tile_2x2m", small, y, holder)
			x += 4.0
		z += 4.0


func _kit_tile(piece: String, r: Rect2, y: float, holder: String) -> void:
	_kit_items.append({"piece": piece, "folder": CityKit.MODULES,
		"xf": Transform3D(Basis.IDENTITY, Vector3(r.position.x, y, r.end.y)), "holder": holder})


## Gravel roof surface with a 1 m parapet over a hidden greybox roof.
func _kit_roof(poly: PackedVector2Array, y: float, holder: String) -> void:
	_kit_slab(poly, y + 0.01, CityKit.ROOF_GRAVEL, 3.0, holder)
	_kit_ring(poly, y, 1.0, [], [], "parapet", holder)


## Flat textured surface (our own polygon mesh) at y.
func _kit_slab(poly: PackedVector2Array, y: float, texture: String, tile: float, holder: String,
		tint := Color.WHITE) -> void:
	_kit_items.append({"slab": poly, "y": y, "texture": texture, "tile": tile, "holder": holder, "tint": tint})


# --- B-26 roads and outskirts -----------------------------------------------------

## Pack sidewalks with curbs along road edges on land, lane lines on straight roads, power poles
## and wires along long edges (poles collide, the rest is flat or overhead).
func _build_roadside() -> void:
	var keep_out := _keep_out_polygons()
	var routes := _route_segments()
	var points := _keep_out_points()
	var blocked := _kit_blocked_polys()
	var roads: Array = _kit_ground.road
	var water: Array = _kit_ground.water
	var inside_any := func(p: Vector2, polys: Array) -> bool:
		return polys.any(func(q: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, q))
	var slabs := 0
	var poles := 0
	for poly: PackedVector2Array in roads:
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var length := a.distance_to(b)
			if length < 2.0:
				continue
			var dir := (b - a) / length
			var out := Vector2(-dir.y, dir.x)
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + out * 0.3, poly):
				out = -out
			# Basis X along the walk, Z outward: X x Y = Z needs out = (dir.y, -dir.x) rotated; else walk back.
			var walk_a := a
			var walk_dir := dir
			if not Vector3(dir.x, 0.0, dir.y).cross(Vector3.UP).is_equal_approx(Vector3(out.x, 0.0, out.y)):
				walk_a = b
				walk_dir = -dir
			var t := 0.0
			while length - t >= 1.9:
				var piece_len := 8 if length - t >= 8.0 else (4 if length - t >= 4.0 else 2)
				var mid := walk_a + walk_dir * (t + piece_len * 0.5) + out * 1.3
				t += piece_len
				if inside_any.call(mid, roads) or inside_any.call(mid, water) or inside_any.call(mid, blocked) \
						or absf(mid.x) > MAP_HALF or absf(mid.y) > MAP_HALF:
					continue
				var end := walk_a + walk_dir * t
				var basis := Basis(Vector3(walk_dir.x, 0.0, walk_dir.y), Vector3.UP, Vector3(out.x, 0.0, out.y))
				_kit_items.append({"piece": SIDEWALK[piece_len], "folder": "street",
					"xf": Transform3D(basis, Vector3(end.x, KIT_GROUND_LIFT, end.y)), "holder": ""})
				slabs += 1
			# Power line along long edges, outside the sidewalk.
			if length < POLE_STEP * 2.0:
				continue
			var prev := Vector2.INF
			var s := POLE_STEP * 0.5
			while s < length:
				var p := a + dir * s + out * POLE_OUT
				s += POLE_STEP
				var ok: bool = _open(p, keep_out, routes, 1.5) and not _near_points(p, points, 1.0) \
					and not inside_any.call(p, blocked) and not _in_prop(p, 0.8)
				if not ok:
					prev = Vector2.INF
					continue
				_kit_add("electrical_pole_01", p, atan2(-dir.y, dir.x) + PI * 0.5)
				_root.get_node("PropsKit").add_child(_box("Pole%d" % poles, p, Vector2(0.4, 0.4), 0.0, 9.0, 0.0, "blocked"))
				_taken.append(Vector3(p.x, p.y, 1.0))
				poles += 1
				if prev != Vector2.INF:
					var span := p - prev
					var wire_basis := Basis(Vector3(span.x, 0.0, span.y).normalized(), Vector3.UP,
						Vector3(span.x, 0.0, span.y).normalized().cross(Vector3.UP))
					wire_basis.x *= span.length() / 20.0
					_kit_items.append({"piece": "wires_20m_01", "folder": "outdoor_environment",
						"xf": Transform3D(wire_basis, Vector3(p.x, 0.0, p.y)), "holder": ""})
				prev = p
	# Lane lines down straight roads (4 corners, longer than wide).
	var lines := 0
	for poly: PackedVector2Array in roads:
		if poly.size() != 4:
			continue
		var e0 := poly[1] - poly[0]
		var e1 := poly[2] - poly[1]
		var long_first := e0.length() >= e1.length()
		var width := (e1 if long_first else e0).length()
		var start := (poly[0] + poly[3]) * 0.5 if long_first else (poly[0] + poly[1]) * 0.5
		var stop := (poly[1] + poly[2]) * 0.5 if long_first else (poly[3] + poly[2]) * 0.5
		var length := start.distance_to(stop)
		if width < 5.0 or width > 16.0 or length < 15.0:
			continue
		var dir := (stop - start) / length
		var piece := "line_double_yellow_10m" if width >= 9.0 else "line_broken_white_10m"
		var t := 4.0
		while t + 10.0 <= length - 4.0:
			var end := start + dir * (t + 10.0)
			t += 10.0
			if inside_any.call(end, water) and not inside_any.call(end, roads):
				continue
			_kit_items.append({"piece": piece, "folder": "street", "xf": Transform3D(Basis(Vector3.UP,
				atan2(dir.x, dir.y)), Vector3(end.x, KIT_GROUND_LIFT + 0.01, end.y)), "holder": ""})
			lines += 1
	print("roadside: %d sidewalk pieces, %d poles, %d lane lines" % [slabs, poles, lines])


## Outside the map (no collision, the map bounds stop the player): forest ring, roads running on
## with backdrop buildings, water carried on past the edge, dark ground beyond.
func _build_outskirts() -> void:
	var outer := MAP_HALF + OUTSKIRT
	var strips: Array[PackedVector2Array] = [
		_rect_poly(Rect2(-outer, -outer, outer * 2.0, OUTSKIRT)),
		_rect_poly(Rect2(-outer, MAP_HALF, outer * 2.0, OUTSKIRT)),
		_rect_poly(Rect2(-outer, -MAP_HALF, OUTSKIRT, MAP_HALF * 2.0)),
		_rect_poly(Rect2(MAP_HALF, -MAP_HALF, OUTSKIRT, MAP_HALF * 2.0)),
	]
	var water_out: Array[PackedVector2Array] = []
	for w: PackedVector2Array in _kit_ground.water:
		water_out.append_array(_edge_extensions(w, OUTSKIRT))
	var road_out: Array[PackedVector2Array] = []
	for r: PackedVector2Array in _kit_ground.road:
		road_out.append_array(_edge_extensions(r, OUTSKIRT))
	var land := strips
	for w in water_out:
		land = _clip_all(land, w)
	for poly in land:
		_kit_slab(poly, KIT_GROUND_LIFT, KIT_TERRAIN.land_b, 7.0, "", Color(0.8, 0.85, 0.78))
	for w in water_out:
		_kit_items.append({"water": w, "holder": ""})
	for r in road_out:
		_kit_slab(r, KIT_GROUND_LIFT + 0.01, KIT_TERRAIN.road, 6.0, "")
	_kit_items.append({"far": (outer + 250.0) * 2.0, "holder": ""})
	var on := func(p: Vector2, polys: Array) -> bool:
		return polys.any(func(q: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, q))

	# Backdrop buildings beside the roads that run out of the map, facing the road.
	var built: Array[Rect2] = []
	for r in road_out:
		var rb := _bounds(r)
		var c0 := rb.get_center()
		var outward := Vector2(signf(c0.x), 0.0) if absf(c0.x) > MAP_HALF else Vector2(0.0, signf(c0.y))
		var side := Vector2(outward.y, outward.x)
		var half_w := absf(Vector2(rb.size.x, rb.size.y).dot(side)) * 0.5
		var anchor := _edge_anchor(rb, outward)
		var t := 8.0
		while t < OUTSKIRT - 6.0:
			for sgn: float in [-1.0, 1.0]:
				var piece: String = OUTSKIRT_BUILDINGS[_kit_rng.randi_range(0, OUTSKIRT_BUILDINGS.size() - 1)]
				var size := _kit_size(piece, 0.0)
				var depth := maxf(size.x, size.z)
				var c := anchor + outward * t + side * sgn * (half_w + 3.0 + depth * 0.5)
				# Front (-X) looks at the road.
				var to_road := -side * sgn
				var yaw := atan2(-to_road.y, -to_road.x) + PI
				var foot := _kit_size(piece, yaw)
				var rect := Rect2(c - Vector2(foot.x, foot.z) * 0.5, Vector2(foot.x, foot.z))
				if absf(c.x) < MAP_HALF + depth * 0.5 + 2.0 and absf(c.y) < MAP_HALF + depth * 0.5 + 2.0:
					continue
				if built.any(func(o: Rect2) -> bool: return o.grow(2.0).intersects(rect)) or on.call(c, water_out):
					continue
				built.append(rect)
				_kit_add(piece, c, yaw)
			t += 22.0

	# Forest: dense conifers (giants further out), undergrowth, all as multimesh ground cover.
	var count := 0
	for poly in land:
		var b := _bounds(poly)
		var y := b.position.y
		while y < b.end.y:
			var x := b.position.x
			while x < b.end.x:
				var p := Vector2(x, y) + Vector2(_kit_rng.randf_range(-1.0, 1.0), _kit_rng.randf_range(-1.0, 1.0)) \
					* OUTSKIRT_TREE_STEP * 0.45
				x += OUTSKIRT_TREE_STEP
				if not Geometry2D.is_point_in_polygon(p, poly) or on.call(p, road_out) \
						or built.any(func(o: Rect2) -> bool: return o.grow(1.5).has_point(p)):
					continue
				var depth := maxf(absf(p.x), absf(p.y)) - MAP_HALF
				var piece: String
				var h: float
				if depth > 22.0 and _kit_rng.randf() < 0.08:
					piece = OUTSKIRT_GIANTS[_kit_rng.randi_range(0, OUTSKIRT_GIANTS.size() - 1)]
					h = _kit_rng.randf_range(16.0, 24.0)
				else:
					piece = OUTSKIRT_TREES[_kit_rng.randi_range(0, OUTSKIRT_TREES.size() - 1)]
					h = _kit_rng.randf_range(7.0, 11.0) + depth * 0.08
				var path := CityKit.piece_path(CityKit.PROPS[piece][0], piece)
				if not _kit_plants.has(path):
					_kit_plants[path] = PackedFloat32Array()
				_kit_plants[path].append_array([p.x, 0.0, p.y, _kit_rng.randf() * TAU,
					h / (CityKit.PROPS[piece][2] as Vector3).y])
				count += 1
				if _kit_rng.randf() < 0.7:
					var under: String = OUTSKIRT_UNDER[_kit_rng.randi_range(0, OUTSKIRT_UNDER.size() - 1)]
					_kit_plant(under, p + Vector2(_kit_rng.randf_range(-1.5, 1.5), _kit_rng.randf_range(-1.5, 1.5)),
						KIT_GROUND_LIFT)
			y += OUTSKIRT_TREE_STEP
	print("outskirts: %d trees, %d buildings, %d roads out, %d water out" % [count, built.size(), road_out.size(),
		water_out.size()])


## Where a polygon meets the map edge, the strip carried straight on past it by reach metres.
func _edge_extensions(poly: PackedVector2Array, reach: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for side in 4:
		var axis := 0 if side < 2 else 1 # 0: x edge (west/east), 1: z edge (north/south)
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var on_edge: Array[float] = []
		for p in poly:
			var v := p.x if axis == 0 else p.y
			if absf(v - sgn * MAP_HALF) < 0.6:
				on_edge.append(p.y if axis == 0 else p.x)
		if on_edge.size() < 2:
			continue
		var lo: float = on_edge.min()
		var hi: float = on_edge.max()
		if hi - lo < 0.5:
			continue
		var e := sgn * MAP_HALF
		var f := sgn * (MAP_HALF + reach)
		if axis == 0:
			out.append(PackedVector2Array([Vector2(e, lo), Vector2(f, lo), Vector2(f, hi), Vector2(e, hi)]))
		else:
			out.append(PackedVector2Array([Vector2(lo, e), Vector2(hi, e), Vector2(hi, f), Vector2(lo, f)]))
	return out


## Middle of the rect's side that faces outward (where a road leaves the map).
func _edge_anchor(r: Rect2, outward: Vector2) -> Vector2:
	var c := r.get_center()
	return c - outward * Vector2(r.size.x, r.size.y).dot(outward.abs()) * 0.5


## holder: "" (always shown) or "roof:<zone id>" (hidden with that IndoorZone's roofs); "a/b" nests b in a.
func _kit_add(piece: String, center: Vector2, yaw: float, y := 0.0, scale := 1.0, holder := "") -> void:
	var part := CityKit.prop_part(piece, center, yaw, y, scale)
	if not part.is_empty():
		_kit_items.append({"piece": piece, "folder": part.folder, "xf": part.xf, "holder": holder})


## Footprint size (x, z) and height of a pack piece turned by yaw.
func _kit_size(piece: String, yaw: float, scale := 1.0) -> Vector3:
	return (Basis(Vector3.UP, yaw) * (CityKit.PROPS[piece][2] as Vector3) * scale).abs()


## Street furniture just off the road edges (B-26), with collision as cover or blockers.
func _build_street() -> void:
	var keep_out := _keep_out_polygons()
	var routes := _route_segments()
	var points := _keep_out_points()
	var doors := []
	for id: String in zone_doors:
		doors.append_array(_doors(id))
	for id: String in _kit:
		doors.append_array(_kit[id].doors)
	var cover := _root.get_node("LowCoverKit")
	var blockers := _root.get_node("PropsKit")
	var placed := PackedVector2Array()
	for zone: Dictionary in _map.zones:
		if zone.kind != "road" or zone.floor != 0:
			continue
		var poly := _poly(zone)
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var length := a.distance_to(b)
			var dir := (b - a) / length
			var normal := Vector2(-dir.y, dir.x)
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + normal * 0.5, poly):
				normal = -normal
			var t := _kit_rng.randf_range(2.0, STREET_STEP)
			while t < length - 2.0:
				var p := a + dir * t + normal * STREET_OUT
				t += STREET_STEP * _kit_rng.randf_range(0.8, 1.4)
				var piece: String = STREET_PROPS[_kit_rng.randi_range(0, STREET_PROPS.size() - 1)]
				# Front (-X) looks back at the road.
				var yaw := atan2(-normal.y, normal.x)
				var size := _kit_size(piece, yaw, PROP_SCALE)
				if not _open(p, keep_out, routes, CLEAR_ROUTE) or _near(p, placed, STREET_STEP * 0.6) \
						or _near_door(p, doors, 3.0) or _near_points(p, points, 1.0) or _in_prop(p, 1.0):
					continue
				placed.append(p)
				_taken.append(Vector3(p.x, p.y, 1.0))
				_kit_add(piece, p, yaw, 0.0, PROP_SCALE)
				var low := size.y <= LOW_COVER_MAX_H
				(cover if low else blockers).add_child(_box("Street%d_%s" % [placed.size(), piece], p,
					Vector2(size.x, size.z), 0.0, size.y, 0.0, "cover" if low else "blocked"))
	print("street: %d props" % placed.size())


## Mall interiors (B-26): shelf rows on 1F, cafe tables on 2F, clear of markers, doors, stairs,
## the elevator and the demo routes.
func _build_shop_fill() -> void:
	if shop_fill.is_empty():
		return
	var y2: float = _map.floors[1].y
	var stair := _rect(_link("stairs").rect).grow(SHOP_CLEAR + 1.0)
	var shaft := _rect(_link("elevator").rect).grow(SHOP_CLEAR)
	var routes := _route_segments()
	var cover := _root.get_node("LowCoverKit")
	var blockers := _root.get_node("PropsKit")
	var total := 0
	for fill: Array in shop_fill:
		var zone: Dictionary = _zones[fill[0]]
		var poly := _largest(Geometry2D.offset_polygon(_poly(zone), -SHOP_INSET))
		var bounds := _bounds(poly)
		var y := 0.0 if zone.floor == 0 else y2
		var doors := _doors(zone.id)
		var want := int(_area(poly) / float(fill[2]))
		var taken: Array[Rect2] = []
		for attempt in want * 60:
			if taken.size() >= want:
				break
			var c := Vector2(_kit_rng.randf_range(bounds.position.x, bounds.end.x),
				_kit_rng.randf_range(bounds.position.y, bounds.end.y)).snapped(Vector2(0.5, 0.5))
			var along_x := _kit_rng.randf() < 0.5
			var foot := Vector2(3.8, 1.0) if fill[1] == "shelves" else Vector2(2.4, 2.4)
			if not along_x:
				foot = Vector2(foot.y, foot.x)
			var r := Rect2(c - foot * 0.5, foot)
			var corners := _rect_poly(r)
			if Array(corners).any(func(q: Vector2) -> bool: return not Geometry2D.is_point_in_polygon(q, poly)):
				continue
			if r.intersects(stair) or r.intersects(shaft) or _near_marker(c, zone.floor, SHOP_CLEAR + 2.0) \
					or _near_door(c, doors, SHOP_CLEAR + 2.0) \
					or taken.any(func(o: Rect2) -> bool: return o.grow(SHOP_CLEAR).intersects(r)):
				continue
			if zone.floor == 0 and routes.any(func(s: Array) -> bool:
					return c.distance_to(Geometry2D.get_closest_point_to_segment(c, s[0], s[1])) < SHOP_CLEAR + 1.5):
				continue
			taken.append(r)
			if fill[1] == "shelves":
				_kit_shelf_row(c, 0.0 if along_x else PI * 0.5, 3.8, y)
				blockers.add_child(_box("Shelves_%s_%d" % [zone.id, taken.size()], c, foot - Vector2(0.1, 0.1), y,
					1.85, 0.0, "blocked"))
			else:
				_kit_add("table_02", c, 0.0, y)
				for k in 4:
					var dir := Vector2(1.0, 0.0).rotated(k * PI * 0.5)
					# Chairs face the table: front (-X) toward the center.
					_kit_add("chair_01", c + dir * 0.85, atan2(-dir.y, dir.x), y)
				cover.add_child(_box("Cafe_%s_%d" % [zone.id, taken.size()], c, Vector2(2.2, 2.2), y, 0.9, 0.0, "cover"))
		total += taken.size()
		if taken.size() < want:
			push_warning("Shop fill: %s got %d of %d" % [zone.id, taken.size(), want])
	print("shop fill: %d" % total)


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
	if _kit.has(zone.id):
		return _rect_poly(_kit[zone.id].rect)
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
	if _kit.has(id):
		return _kit[id].doors
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
