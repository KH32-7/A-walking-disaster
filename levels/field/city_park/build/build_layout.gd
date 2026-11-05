extends "res://field/build/layout_builder.gd"
## Builds levels/field/city_park/layout.tscn (B-24) from the confirmed map file.
##
##   godot --headless --path . --script res://levels/field/city_park/build/build_layout.gd
##
## Source: build/city_park_map.json, exported from the planning board (map the user handed to
## Claude and confirmed, 2026-11-05). One floor. The shared generator (field/build/layout_builder.gd)
## does everything but the old underpass, which this file builds in _build_structures().
## Re-run after the map file changes. Hand edits to layout.tscn are lost on a re-run.
##
## Old underpass (hidden route park_old_underpass, map hidden_routes[0]): a straight tunnel under
## the ground from the route's From (south mouth) to its To (north mouth). A ramp at each mouth goes
## down to the tunnel floor (wheelchairs pass, map floor_links: wheelchair true). The ground above
## the flat part is a roof (IndoorZone "underpass") so the camera sees the player inside.
## B-20 HiddenRouteManager closes it with a gate at the marker's "Gate" child, in the middle of the
## tunnel, until someone in the party matches required_trait.

const MAP_PATH := "res://levels/field/city_park/build/city_park_map.json"
const OUT_SCENE := "res://levels/field/city_park/layout.tscn"
const OUT_NAVMESH := "res://levels/field/city_park/layout_navmesh.res"
## B-26 pack dressing (layout_builder.gd), user feedback 2026-11-06: the park in the packs too.
const OUT_KIT := "res://levels/field/city_park/buildings.tscn"
const OUT_SPLAT := "res://levels/field/city_park/ground_splat.res"
const KIT_COVER := {"PlazaBench": "bench", "BusBench": "bench"}
## Park paths are gravel; only the roads (road_*) get lane lines and poles.
const KIT_PATH_TEXTURE := "res://assets/environment/city/american_suburb/textures/terrain/rocks_ground_01.png"
const KIT_STREET_PREFIX := "road_"
const PARK_FURNITURE := ["patio_bench_b", "patio_bench_a", "patio_bench_b", "urn_street_01", "urn_street_02",
	"parking_lot_light_pole_01", "curbside_trash_bin_03", "garden_gnome_02"]
## Kept clear around the boss arena centre (the giant needs room).
const ARENA_CLEAR := 18.0

## Greenhouse: tall glass hall (plants up to the ceiling). Stage back room a little higher.
const WALL_H := {"gh_in": 5.0, "stage_in": 3.5}
## Fallen old trees block walking and shots. Plaza cover (flowerbed, streetlight) and the slide
## tower are full cover in the boss fight.
const BLOCKED_H := {"log_ne": 1.6, "log_w": 1.6, "plaza_cover1": 1.4, "plaza_cover2": 1.4, "pg_tower": 4.0}

## Doors: zone id -> [[x, z, width], ...] in map file coordinates (scaled on use, width is not).
## Placed from the demo route and the paths each building faces.
const DOORS := {
	# East to the route from the main path, north back door toward the pond.
	"office_in": [[-29.0, 47.0, 2.0], [-38.0, 41.0, 2.0]],
	# Stage back room opens east onto the stage.
	"stage_in": [[-53.0, -5.0, 3.0]],
	# Kiosk and tool shed face the path in front of them.
	"kiosk_in": [[15.0, 41.0, 2.0]],
	"shed_in": [[36.5, -21.0, 2.0]],
	# Greenhouse: south door on the route, east side door.
	"gh_in": [[44.0, -27.8, 3.0], [56.0, -40.0, 2.0]],
}

## Low cover: benches, the overturned duck boat in the pond, the bus stop bench.
const LOW_COVER := [
	["PlazaBench", 11.0, -18.5, 2.0, 0.6, 0.8, 0.0],
	["DuckBoat", 10.0, 30.0, 2.0, 3.2, 1.0, 35.0],
	["BusBench", 72.0, -10.0, 0.6, 2.0, 0.8, 0.0],
]
## Full blockers: bus shelter, the main gate pillars.
const BLOCKERS := [
	["BusShelter", 73.0, -19.0, 1.2, 4.0, 2.5, 0.0],
	["GatePillarW", -19.5, 61.0, 1.0, 1.0, 2.5, 0.0],
	["GatePillarE", -10.5, 61.0, 1.0, 1.0, 2.5, 0.0],
]
const NATURE_SEED := 20261108

## Danger 1, every nest GREEN (02). None on the first sortie route, near an extract point or the
## boss plaza: west woods (31m from the route), northwest woods (50m from the north gate),
## east of the pond (48m from the east spawn).
const EXTRA_NESTS := [
	["nest_w", "GREEN", -66.0, -25.0, 3, 8.0],
	["nest_nw", "GREEN", -50.0, -62.0, 3, 8.0],
	["nest_pond_e", "GREEN", 32.0, 18.0, 4, 10.0],
]

const LOOT_SEED := 20261109
const LOOT_MIN := {"office_in": 2, "gh_in": 2}
## 02: seeds and herbs in the greenhouse, cloth (costumes) behind the stage, medicine in the office.
const ZONE_LOOT := {
	"office_in": ["DRAWER", "MEDICINE"],
	"gh_in": ["DRAWER"],
	"stage_in": ["DRAWER"],
	"kiosk_in": ["DRAWER"],
	"shed_in": ["TOOLBOX"],
}
## The plaza's toolbox is next to the sleeping boss (risk and reward, like the supply crate).
## The amphitheatre's last spot, next to its nest, is a supply crate (2026-11-06: always spawns).
const LANDMARK_LOOT := {
	"amph_lm": ["DRAWER", "TOOLBOX", "SUPPLY_CRATE"],
	"pg_lm": ["DRAWER", "MEDICINE", "TOOLBOX"],
	"plaza_lm": ["TOOLBOX"],
}

const CLUTTER_SEED := 20261110
## Park kits: benches, planters, fallen branches, a maintenance cart, crates, a vending machine.
const CLUTTER_KITS := [
	# [kit, weight, pieces]
	["Benches", 3, [["Bench", 0.0, 0.0, 2.0, 0.6, 0.8, 0.0], ["Bench", 0.0, 2.2, 2.0, 0.6, 0.8, 0.0]]],
	["Planters", 2, [["Planter", 0.0, 0.0, 1.6, 1.6, 1.0, 0.0], ["Planter", 2.4, 0.4, 1.6, 1.6, 1.0, 0.0]]],
	["Branches", 3, [["Branch", 0.0, 0.0, 4.5, 0.7, 0.8, 0.0], ["Branch", 1.0, 1.2, 3.0, 0.6, 0.7, 35.0]]],
	["Cart", 1, [["Cart", 0.0, 0.0, 1.4, 2.6, 1.2, 0.0], ["Crate", 1.6, 0.8, 1.0, 1.0, 0.9, 15.0]]],
	["Crates", 1, [["CratePile", 0.0, 0.0, 2.4, 1.2, 1.8, 0.0], ["Crate", 1.9, 0.3, 1.0, 1.0, 0.9, 10.0]]],
	["Vending", 1, [["VendingMachine", 0.0, 0.0, 1.0, 0.8, 1.9, 0.0], ["Bin", 1.2, 0.0, 0.6, 0.6, 1.0, 0.0]]],
]

const UNDERPASS_ID := "park_old_underpass"
const UNDERPASS_BUILDING := &"underpass"
## Tunnel floor below the ground top (y 0). The ground slab (GROUND_DEPTH) is the ceiling.
const UNDERPASS_FLOOR_Y := -4.0
## Inner width. 4 m let the near wall hide the player from the field camera, 6 m does not.
## city_park.tscn sets HiddenRouteManager.gate_width wider than this.
const UNDERPASS_W := 6.0
## Each mouth ramp (4 m down over 14 m, about 16 degrees).
const UNDERPASS_RAMP_LEN := 14.0
## Gate point height. The B-20 gate box reaches 1.5 m below it and 2.5 m above: -4.5 to -0.5.
const UNDERPASS_GATE_Y := -3.0


func _init() -> void:
	map_path = MAP_PATH
	out_scene = OUT_SCENE
	out_navmesh = OUT_NAVMESH
	root_name = "CityParkLayout"
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
	out_kit = OUT_KIT
	out_splat = OUT_SPLAT
	kit_cover = KIT_COVER
	kit_street_prefix = KIT_STREET_PREFIX
	kit_road_texture = KIT_PATH_TEXTURE
	street_props = PARK_FURNITURE


func _build_structures() -> void:
	_build_underpass()


## The tunnel between the hidden route's two ends (see the file comment).
func _build_underpass() -> void:
	var u := _underpass()
	var a: Vector2 = u.a
	var b: Vector2 = u.b
	var dir: Vector2 = u.dir
	var outer := UNDERPASS_W + WALL_T * 2.0
	var foot_a := a + dir * UNDERPASS_RAMP_LEN
	var foot_b := b - dir * UNDERPASS_RAMP_LEN
	var strip := _strip(a, b, outer)
	_structure_keep_out.append(strip)
	_check_underpass_ground(strip)

	var node := Node3D.new()
	node.name = "Underpass"
	_root.add_child(node)

	# Open the ground over the whole tunnel; the roof below closes the flat part again.
	var cut := _box_along("UnderpassCut", a, b, outer, -GROUND_DEPTH - 0.2, GROUND_DEPTH + 0.4, "ground")
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	_root.get_node("Ground").add_child(cut)
	# Overlays (paths, vegetation) over the tunnel: cut, and a copy of the flat part on the roof.
	var roof := Node3D.new()
	roof.name = "Roof"
	roof.add_to_group(ROOF_GROUP, true)
	roof.set_meta(ROOF_META, UNDERPASS_BUILDING)
	for overlay in _root.get_node("Overlays").get_children():
		var shape := overlay as CSGPolygon3D
		if shape == null or Geometry2D.intersect_polygons(shape.polygon, strip).is_empty():
			continue
		var copy := shape.duplicate(0) as CSGPolygon3D
		var keep := _box_along("Keep", foot_a, foot_b, outer, -0.5, 1.0, "ground")
		keep.operation = CSGShape3D.OPERATION_INTERSECTION
		_add_local(copy, keep)
		roof.add_child(copy)
		copy.add_to_group(KIT_GREYBOX_GROUP, true) # B-26: the pack ground slab below draws it
		var over_cut := _box_along("UnderpassCut", a, b, outer, -0.5, 1.0, "ground")
		over_cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		_add_local(shape, over_cut)

	var tunnel := _combiner("Tunnel")
	_nav(tunnel)
	node.add_child(tunnel)
	tunnel.add_child(_box_along("Floor", a, b, outer, UNDERPASS_FLOOR_Y - SLAB, SLAB, "slab"))
	var depth := -UNDERPASS_FLOOR_Y
	tunnel.add_child(_ramp("RampSouth", a, foot_a, UNDERPASS_W, UNDERPASS_FLOOR_Y, depth, "road"))
	tunnel.add_child(_ramp("RampNorth", b, foot_b, UNDERPASS_W, UNDERPASS_FLOOR_Y, depth, "road"))
	# Side walls: up to the ceiling under the roof, low parapets around the open mouths.
	var side := Vector2(-dir.y, dir.x) * (UNDERPASS_W + WALL_T) * 0.5
	for s in [1.0, -1.0]:
		var off: Vector2 = side * s
		var tag := "L" if s > 0.0 else "R"
		tunnel.add_child(_box_along("WallSouth" + tag, a + off, foot_a + off, WALL_T, UNDERPASS_FLOOR_Y,
			depth + LOW_WALL_H, "wall"))
		tunnel.add_child(_box_along("Wall" + tag, foot_a + off, foot_b + off, WALL_T, UNDERPASS_FLOOR_Y,
			depth - GROUND_DEPTH, "wall"))
		tunnel.add_child(_box_along("WallNorth" + tag, foot_b + off, b + off, WALL_T, UNDERPASS_FLOOR_Y,
			depth + LOW_WALL_H, "wall"))

	var slab := _combiner("RoofSlab")
	_nav(slab)
	roof.add_child(slab)
	slab.add_child(_box_along("Ground", foot_a, foot_b, outer, -GROUND_DEPTH, GROUND_DEPTH, "ground"))
	node.add_child(roof)

	_root.get_node("IndoorZones").add_child(
		_indoor_zone(UNDERPASS_BUILDING, [strip], UNDERPASS_FLOOR_Y - 0.5, -0.5))
	# B-26: the kit ground leaves the whole strip open; over the tunnel it lays the same ground as a
	# roof of the underpass, so it hides when the player goes in.
	_kit_ground_holes.append(strip)
	_kit_items.append({"slab": _strip(foot_a, foot_b, outer), "y": KIT_GROUND_LIFT, "splat": true,
		"holder": "roof:%s" % UNDERPASS_BUILDING})
	print("underpass: %.0fm, ramps %.0fm, floor y %.1f" % [a.distance_to(b), UNDERPASS_RAMP_LEN, UNDERPASS_FLOOR_Y])


## B-26: fallen old trees as Redwood logs, the slide tower as a big slide, the broken flower bed as
## bushes, the fallen street lamp as a lamp post lying down. Prisms keep the collision.
func _kit_blocked(zone: Dictionary, poly: PackedVector2Array, h: float) -> bool:
	var r := _bounds(poly)
	var along_z := r.size.y > r.size.x
	var length := maxf(r.size.x, r.size.y)
	var c := r.get_center()
	match zone.id:
		"log_ne", "log_w":
			var log_len: float = (CityKit.PROPS.redwood_hollow_log_2[2] as Vector3).z
			_kit_add("redwood_hollow_log_2", c, 0.0 if along_z else PI * 0.5, 0.0, length / log_len)
			_kit_add("fungi_polyp_1", c + Vector2(0.8, 0.6), 0.0, 0.0, 1.4)
			return true
		"pg_tower":
			var slide: Vector3 = CityKit.PROPS.big_kids_slide[2]
			_kit_add("big_kids_slide", c, 0.0, 0.0, maxf(r.size.x / slide.x, r.size.y / slide.z) * 1.1)
			return true
		"plaza_cover1":
			for k in 3:
				var at := r.position + r.size * Vector2(0.25 + 0.25 * k, 0.5)
				_kit_add(["bushes_04", "bushes_06", "bushes_08"][k], at, _kit_rng.randf() * TAU, 0.0, 1.2)
			return true
		"plaza_cover2":
			var axis := Vector2(0.0, 1.0) if along_z else Vector2(1.0, 0.0)
			var yaw := atan2(-axis.y, axis.x)
			var lying := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -PI * 0.5)
			var base := c - axis * 3.4
			_kit_items.append({"piece": "parking_lot_light_pole_01", "folder": "outdoor_environment",
				"xf": Transform3D(lying, Vector3(base.x, 0.25, base.y)), "holder": ""})
			return true
	return super(zone, poly, h)


## B-26 special places from the landmark looks in the map file.
func _build_pois() -> void:
	var keep_out := _keep_out_polygons()
	var routes := _route_segments()
	var placed := 0
	# 야외 공연장: rows of benches facing the stage, speakers by the stage.
	var amph := _poly(_zones.amph_lm)
	for k in 5:
		placed += _poi_row(["patio_bench_b"], 4, 2.5, amph, keep_out, routes)
	for piece: String in ["speaker_box", "speaker_box", "plastic_table", "patio_chair_01", "patio_chair_01"]:
		placed += int(_poi_try(piece, amph, keep_out, routes, true))
	# 덩굴 놀이터: playground gear and benches for the parents.
	var pg := _poly(_zones.pg_lm)
	for piece: String in ["big_kids_slide", "small_kids_slide", "small_kids_slide", "wooden_swing", "wooden_swing",
			"wooden_swing", "backyard_trampoline", "backyard_trampoline", "basketball_hoop", "patio_bench_a",
			"patio_bench_a", "garden_gnome_01", "garden_gnome_02"]:
		placed += int(_poi_try(piece, pg, keep_out, routes, not piece.begins_with("garden_gnome")))
	# 유리 온실: the gardeners' yard.
	var gh := _poly(_zones.gh_lm)
	for piece: String in ["compost_bin", "compost_bin", "wheelbarrow", "wheelbarrow", "garden_hose", "tool_cabinet",
			"lawn_mower_01", "riding_lawn_mower", "plastic_storage_bin", "plastic_storage_bin", "pallet",
			"firewood_rack"]:
		placed += int(_poi_try(piece, gh, keep_out, routes, piece not in ["garden_hose", "pallet"]))
	# 관리사무소: the staff's cars and the mail.
	var office := _poly(_zones.office_lm)
	placed += _poi_row(["service_van", "car_minivan_01", "car_crossover_03"], 2, 3.0, office, keep_out, routes)
	for piece: String in ["rural_mailbox_01", "electrical_service_meter", "patio_bench_a", "curbside_trash_bin_01"]:
		placed += int(_poi_try(piece, office, keep_out, routes, piece != "electrical_service_meter"))
	# 연못: picnic spots on the banks.
	var pond := _poly(_zones.pond_lm)
	for k in 3:
		for piece: String in ["outdoor_dining_table_a", "patio_umbrella", "patio_bench_b"]:
			placed += int(_poi_try(piece, pond, keep_out, routes, piece != "patio_umbrella"))
	# 고목 광장: only round the edge, the middle is the giant's arena.
	var plaza := _poly(_zones.plaza_lm)
	var arena := _arena_center()
	var ring_keep := keep_out.duplicate()
	var circle := PackedVector2Array()
	for k in 24:
		circle.append(arena + Vector2(ARENA_CLEAR, 0.0).rotated(TAU * k / 24.0))
	ring_keep.append(circle)
	for piece: String in ["patio_bench_b", "patio_bench_b", "urn_street_02", "parking_lot_light_pole_01",
			"parking_lot_light_pole_01", "bushes_05", "bushes_03"]:
		placed += int(_poi_try(piece, plaza, ring_keep, routes, true))
	print("pois: %d pieces" % placed)


func _arena_center() -> Vector2:
	for m: Dictionary in _map.markers:
		if m["class"] == "BossArena":
			return _xz(m.position)
	return _bounds(_poly(_zones.plaza_lm)).get_center()


## The gate point for B-20, in the middle of the tunnel.
func _marker_built(node: Node3D, m: Dictionary) -> void:
	if m["class"] != "HiddenRoute" or m.props.id != UNDERPASS_ID:
		return
	var u := _underpass()
	var mid: Vector2 = (u.a + u.b) * 0.5
	var along := Vector3(u.dir.x, 0.0, u.dir.y)
	var gate := Node3D.new()
	gate.name = "Gate"
	gate.transform = Transform3D(Basis(Vector3.UP.cross(along), Vector3.UP, along),
		Vector3(mid.x, UNDERPASS_GATE_Y, mid.y) - node.position)
	node.add_child(gate)
	# _set_owners() does not walk into marker instances; a child added to one needs its owner here.
	gate.owner = _root


## {a: south mouth, b: north mouth, dir: a -> b}, scaled plan points.
func _underpass() -> Dictionary:
	for route: Dictionary in _map.hidden_routes:
		if route.id == UNDERPASS_ID:
			var a := _xz(route.from.position)
			var b := _xz(route.to.position)
			return {"a": a, "b": b, "dir": (b - a).normalized()}
	push_error("No hidden route %s in the map file" % UNDERPASS_ID)
	return {"a": Vector2.ZERO, "b": Vector2.UP, "dir": Vector2.UP}


## Nothing on the map should stand on the tunnel's ground (it would hang over the open roof).
func _check_underpass_ground(strip: PackedVector2Array) -> void:
	for zone: Dictionary in _map.zones:
		if zone.kind in ["indoor", "blocked", "flooded"] \
				and not Geometry2D.intersect_polygons(_poly(zone), strip).is_empty():
			push_error("Underpass runs under %s" % zone.id)
	for m: Dictionary in _map.markers:
		if m["class"] != "HiddenRoute" and Geometry2D.is_point_in_polygon(_xz(m.position), strip):
			push_error("Marker %s is on the underpass" % m.node_name)


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
