extends RefCounted
## Field buildings from the American Suburb pack (B-26). Owner: Lane B.
## The pack lives in the private assets/ submodule. A clone without it (CI) keeps the layout's
## greybox, so runtime code only calls available().
##
## A building is a plan (outer walls, inner walls, props) on its own grid, put in a region by a
## spec (origin, mirror, style, roof). parts() turns the two into world-space parts. The region's
## layout builder makes collision from them and build_meshes() places the pack meshes on the same
## parts, so walls, doors and furniture line up with their collision.
##
## Pack conventions (measured 2026-11-05):
##  - Every FBX keeps a stray scene offset on its top node (up to 160 m). place() cancels it.
##  - Wall pieces run from z = -length to 0 with the exterior face at x = 0 facing -X and 0.2 m
##    of wall toward +X (the +X side carries the interior paint). Door holes are about 1.25 m
##    wide, centered in the piece.
##  - Floor pieces cover x 0..w, z -d..0 and are named house_floor_<style>_<d>x<w>m.
##  - Gable roofs cover x -depth..0 (plus 0.6 m eaves) and z -length..0, bottom at y -0.19.
##  - Furniture and shop pieces have their back toward +X and face -X. PROPS has their bounds.
##  - Vehicles are centered, length along X. Redwood nature pieces (folder nature/<sub>) are centered.

const ROOT := "res://assets/environment/city/american_suburb/models/"
const NATURE_ROOT := "res://assets/environment/nature/pure_nature_redwood/models/"
const MODULES := "house_modules"
const GROUND_SHADER := preload("res://field/buildings/ground_toon.gdshader")
## Flat roofs: gravel surface and 1 m parapet pieces.
const ROOF_GRAVEL := "res://assets/environment/city/american_suburb/textures/terrain/rocks_ground_01.png"
const PARAPET := {1: "house_a_wall_1x1m", 2: "house_a_wall_2x1m", 4: "house_a_wall_4x1m"}
const ROOFTOP_PROPS := ["conditioner_07", "conditioner_08", "roof_vents_01", "roof_vents_02", "roof_vents_04",
	"satellite_dish"]

## IndoorZone.ROOF_GROUP / ROOF_META (field/camera/indoor_zone.gd).
const ROOF_GROUP := &"field_roof"
const ROOF_META := &"building_id"
## layout_builder.gd KIT_GREYBOX_GROUP: layout geometry the pack dressing replaces.
const GREYBOX_GROUP := &"kit_greybox"

const WALL_H := 3.0
const WALL_T := 0.2
## Collision gap for doors. Wider than the 1.25 m hole so the navmesh (agent radius 0.5, cell 0.25)
## still passes; the door frames overlap the gap by about 0.2 m on each side.
const DOOR_GAP := 1.6
const FLOOR_Y := 0.06
const FLAT_ROOF_T := 0.25
const FLAT_ROOF_EAVE := 0.3
## Props lower than this get no collision (carpets, pictures).
const PROP_MIN_COLLIDE_H := 0.2
## Props up to this height are low cover (shots pass over, B-06).
const LOW_COVER_MAX_H := 1.2

## Wall tokens in a plan: w = wall, n = window, e = entrance, d = inner door, x = open.
## The number after the letter is the length in metres.
const WALL := {
	"a": {1: "house_a_wall_1x3m", 2: "house_a_wall_2x3m", 3: "house_a_wall_3x3m", 4: "house_a_wall_4x3m"},
	"b": {1: "house_b_wall_1x3m", 2: "house_b_wall_2x3m", 4: "house_b_wall_4x3m"},
	"c": {1: "house_c_wall_1x3m", 2: "house_c_wall_2x3m", 4: "house_c_wall_4x3m"},
}
const WINDOW := {
	"a": {2: ["house_a_windows_2x3m_01", "house_a_windows_2x3m_02", "house_a_windows_2x3m_03",
			"house_a_windows_2x3m_04", "house_a_windows_2x3m_05"],
		4: ["house_a_windows_4x3m_01", "house_a_windows_4x3m_02", "house_a_windows_4x3m_03"]},
	"b": {2: ["house_b_windows_2x3m_01", "house_b_windows_2x3m_02"],
		4: ["house_b_windows_4x3m_01", "house_b_windows_4x3m_02", "house_b_windows_4x3m_03"]},
	"c": {2: ["house_c_windows_2x3m_01", "house_c_windows_2x3m_02"],
		4: ["house_c_windows_4x3m_01", "house_c_windows_4x3m_02", "house_c_windows_4x3m_03"]},
}
const ENTRANCE := {
	"a": {2: ["house_a_entrance_03", "house_a_entrance_04"], 4: ["house_a_entrance_01", "house_a_entrance_02"]},
	"b": {4: ["house_b_entrance_01"]},
	"c": {4: ["house_c_entrance_01", "house_c_entrance_02"]},
}
const INNER_WALL := {1: "house_a_interior_wall_1x3m", 2: "house_a_interior_wall_2x3m", 4: "house_a_interior_wall_4x3m"}
const INNER_DOOR := {2: "house_interior_door_a_2x3m", 4: "house_interior_door_a_4x3m"}
## Gable roofs by building depth: roof piece prefix and gable end piece.
const GABLE := {
	8: {"a": ["house_roof_a_10", "house_gable_end_a_01"], "b": ["house_roof_b_10", "house_gable_end_b_01"],
		"c": ["house_roof_c_10", "house_gable_end_c_01"]},
	6: {"a": ["house_roof_a_7", "house_gable_end_a_03"], "b": ["house_roof_b_7", "house_gable_end_b_02"],
		"c": ["house_roof_c_7", "house_gable_end_c_02"]},
}
## Front porch on each outer entrance of that length.
const PORCH := {4: "house_front_porch_a_01", 2: "house_front_porch_a_03"}
## Floor piece sizes [w (x), d (z)] per floor style, biggest first. Missing sizes fall back to "b".
const FLOOR_SIZES := {
	"a": [[4, 4], [2, 4]],
	"b": [[4, 4], [2, 4], [4, 2], [2, 2]],
	"c": [[4, 4], [2, 4]],
	"carpeting": [[4, 4], [2, 4], [4, 2], [2, 2]],
	"tile": [[4, 4], [2, 4], [4, 2], [2, 2]],
}
## Furniture and shop pieces: [folder, bounds position, bounds size] in the piece's pivot space,
## measured from the pack.
const PROPS := {
	"bed_01": ["furniture", Vector3(-1.38, 0.00, -1.10), Vector3(2.77, 1.62, 2.20)],
	"bed_03": ["furniture", Vector3(-1.13, -0.00, -0.67), Vector3(2.26, 1.39, 1.36)],
	"nightstand_01": ["furniture", Vector3(-0.27, -0.00, -0.33), Vector3(0.56, 0.80, 0.67)],
	"wardrobe_01": ["furniture", Vector3(-0.50, 0.00, -0.83), Vector3(0.50, 2.60, 1.66)],
	"dresser_01": ["furniture", Vector3(-0.32, 0.00, -0.63), Vector3(0.63, 0.91, 1.25)],
	"sofa_01": ["furniture", Vector3(-0.51, 0.00, -1.38), Vector3(1.10, 1.14, 2.76)],
	"armchair_01": ["furniture", Vector3(-0.57, 0.00, -0.50), Vector3(1.16, 1.18, 0.99)],
	"tv_chest": ["furniture", Vector3(-0.26, 0.06, -0.82), Vector3(0.54, 0.61, 1.65)],
	"table_02": ["furniture", Vector3(-0.54, 0.01, -0.54), Vector3(1.10, 0.83, 1.10)],
	"chair_01": ["furniture", Vector3(-0.28, 0.00, -0.29), Vector3(0.68, 1.12, 0.59)],
	"chair_04": ["furniture", Vector3(-0.26, -0.00, -0.29), Vector3(0.60, 0.88, 0.58)],
	"kitchen_b_02": ["furniture", Vector3(-0.71, 0.00, -3.98), Vector3(0.71, 2.58, 3.98)],
	"fridge_01": ["furniture", Vector3(-0.50, -0.00, -0.53), Vector3(0.86, 1.95, 1.05)],
	"sink": ["furniture", Vector3(-0.37, 0.11, -0.47), Vector3(0.63, 0.88, 0.95)],
	"carpet_big_01": ["furniture", Vector3(-1.96, 0.00, -1.13), Vector3(3.91, 0.01, 2.25)],
	"bookcase_01": ["furniture", Vector3(-0.42, 0.00, -0.81), Vector3(0.47, 2.28, 1.61)],
	"bookcase_02": ["furniture", Vector3(-0.57, 0.00, -0.65), Vector3(0.58, 2.36, 1.32)],
	"desk_01": ["furniture", Vector3(-0.34, -0.02, -0.60), Vector3(0.68, 0.88, 1.48)],
	"cardboard_box_01": ["furniture", Vector3(-0.24, 0.00, -0.35), Vector3(0.49, 0.49, 0.70)],
	"cardboard_box_02": ["furniture", Vector3(-0.23, -0.00, -0.35), Vector3(0.45, 0.46, 0.70)],
	"box_dirty_clothes": ["furniture", Vector3(-0.42, -0.00, -0.30), Vector3(0.86, 0.43, 0.60)],
	"basket_dirty_clothes": ["furniture", Vector3(-0.24, 0.00, -0.26), Vector3(0.48, 0.90, 0.52)],
	"display_cabinet_01": ["furniture", Vector3(-0.49, -0.00, -0.62), Vector3(0.51, 2.19, 1.25)],
	"shelf_01": ["furniture", Vector3(-0.31, 0.00, -0.73), Vector3(0.62, 2.23, 1.46)],
	"shelf_02": ["furniture", Vector3(-0.32, 0.00, -0.76), Vector3(0.63, 2.46, 1.51)],
	"workbench": ["furniture", Vector3(-0.29, 0.00, -0.92), Vector3(0.58, 1.25, 1.84)],
	"washing_machine": ["furniture", Vector3(-0.36, 0.00, -0.35), Vector3(0.71, 0.99, 0.71)],
	"drying_machine": ["furniture", Vector3(-0.37, -0.00, -0.40), Vector3(0.74, 1.05, 0.80)],
	"ironing_board": ["furniture", Vector3(-0.95, 0.02, -0.28), Vector3(1.84, 0.11, 0.57)],
	"retail_shelf_01": ["retail_shelving", Vector3(-0.45, 0.00, -0.63), Vector3(0.45, 1.85, 1.26)],
	"retail_shelf_03": ["retail_shelving", Vector3(-0.58, 0.00, -0.62), Vector3(0.58, 1.85, 1.24)],
	"display_rack_01": ["retail_shelving", Vector3(-0.27, 0.02, -0.46), Vector3(0.51, 1.60, 0.91)],
	"sellers_counter": ["retail_shelving", Vector3(-0.34, 0.01, -0.51), Vector3(2.10, 0.81, 2.60)],
	"display_refrigerator_cold_drinks": ["retail_shelving", Vector3(-0.29, -0.00, -0.68), Vector3(0.57, 2.29, 1.36)],
	"display_refrigerator_milk": ["retail_shelving", Vector3(-0.29, -0.00, -0.68), Vector3(0.57, 2.29, 1.36)],
	"ice_cream_cooler": ["retail_shelving", Vector3(-0.45, 0.00, -0.86), Vector3(0.91, 1.02, 1.72)],
	"ice_merchandiser": ["retail_shelving", Vector3(-0.43, 0.01, -0.57), Vector3(0.94, 1.74, 1.14)],
	"vending_machine_01": ["retail_shelving", Vector3(-0.20, -0.00, -0.42), Vector3(0.74, 1.87, 0.91)],
	"soda_fountain_machine": ["retail_shelving", Vector3(-1.08, 0.00, -1.67), Vector3(1.08, 2.17, 3.34)],
	"store_inventory_stack_01": ["retail_shelving", Vector3(-0.23, 0.00, -0.64), Vector3(0.48, 1.13, 1.28)],
	"store_inventory_stack_02": ["retail_shelving", Vector3(-0.68, -0.00, -0.50), Vector3(1.31, 0.97, 1.08)],
	# Loot container looks (field/loot/loot_container.gd).
	"medical_supplies_crate": ["gameplay_props", Vector3(-0.27, 0.00, -0.34), Vector3(0.55, 0.42, 0.69)],
	"medical_duffel_bag": ["gameplay_props", Vector3(-0.51, 0.00, -0.29), Vector3(1.02, 0.60, 0.59)],
	"tool_box": ["gameplay_props", Vector3(-0.22, 0.00, -0.35), Vector3(0.44, 0.39, 0.70)],
	"tool_box_green": ["gameplay_props", Vector3(-0.26, 0.00, -0.42), Vector3(0.51, 0.36, 0.83)],
	"food_supplies_crat": ["gameplay_props", Vector3(-0.31, 0.00, -0.36), Vector3(0.67, 0.34, 0.69)],
	"long_hard_case": ["gameplay_props", Vector3(-0.29, 0.00, -0.82), Vector3(0.59, 0.32, 1.63)],
	"small_security_safe": ["gameplay_props", Vector3(-0.26, 0.00, -0.24), Vector3(0.47, 0.39, 0.48)],
	"fungi_polyp_2": ["nature/plants", Vector3(-0.40, -0.11, -0.46), Vector3(0.84, 0.21, 0.86)],
	"red_fir5": ["nature/trees", Vector3(-1.92, -0.17, -1.64), Vector3(3.38, 9.37, 3.34)],
	"red_fir6": ["nature/trees", Vector3(-1.86, -0.08, -1.79), Vector3(3.85, 10.71, 3.80)],
	"red_fir7": ["nature/trees", Vector3(-1.63, -0.17, -1.45), Vector3(2.91, 9.37, 2.86)],
	"red_fir8": ["nature/trees", Vector3(-1.01, -0.17, -1.29), Vector3(2.04, 9.37, 2.26)],
	"red_pine3": ["nature/trees", Vector3(-2.00, -0.29, -2.04), Vector3(4.03, 9.81, 4.07)],
	"red_pine4": ["nature/trees", Vector3(-2.04, -0.29, -2.03), Vector3(4.08, 12.01, 4.07)],
	"red_pine5": ["nature/trees", Vector3(-2.03, -0.29, -1.98), Vector3(4.07, 12.75, 4.02)],
	"sequoia1": ["nature/trees", Vector3(-7.23, -0.76, -7.57), Vector3(14.55, 33.62, 13.84)],
	"sequoia2": ["nature/trees", Vector3(-7.93, -0.76, -7.50), Vector3(16.30, 36.15, 15.27)],
	"sequoia3": ["nature/trees", Vector3(-8.36, -0.76, -8.41), Vector3(16.21, 38.28, 16.87)],
	# Outdoor, vehicles, nature (Redwood pack: folder nature/<sub>).
	"patio_bench_a": ["outdoor_environment", Vector3(-0.23, 0.00, -1.00), Vector3(0.45, 0.56, 2.05)],
	"patio_bench_b": ["outdoor_environment", Vector3(-0.25, 0.00, -1.11), Vector3(0.50, 0.50, 2.22)],
	"riding_lawn_mower": ["outdoor_environment", Vector3(-0.91, -0.00, -0.95), Vector3(1.81, 1.12, 1.53)],
	"vending_machine_02": ["retail_shelving", Vector3(-0.38, -0.00, -0.56), Vector3(0.75, 1.87, 1.12)],
	"speaker_box": ["outdoor_environment", Vector3(-0.23, -0.00, -0.26), Vector3(0.39, 1.20, 0.43)],
	"stepping_stone_path_01": ["outdoor_environment", Vector3(-1.00, 0.00, 0.00), Vector3(1.00, 0.04, 1.00)],
	"outdoor_dining_table_a": ["outdoor_environment", Vector3(-0.52, 0.00, -1.11), Vector3(1.04, 0.90, 2.13)],
	"campfire_patio": ["outdoor_environment", Vector3(-0.51, -0.00, -0.53), Vector3(1.04, 0.48, 1.06)],
	"adirondack_chair": ["outdoor_environment", Vector3(-0.43, 0.00, -0.37), Vector3(0.90, 0.96, 0.84)],
	"compost_bin": ["outdoor_environment", Vector3(-0.34, -0.00, -0.97), Vector3(0.69, 1.07, 1.95)],
	"tv_box": ["outdoor_environment", Vector3(-0.08, -0.00, -0.83), Vector3(0.17, 0.82, 1.60)],
	"dumpster_enclosure": ["outdoor_environment", Vector3(-2.07, -0.02, -5.10), Vector3(2.10, 2.22, 5.10)],
	"charcoal_grill_ball": ["outdoor_environment", Vector3(-0.56, -0.01, -0.42), Vector3(0.97, 1.37, 0.83)],
	"gas_grill": ["outdoor_environment", Vector3(-0.36, -0.00, -0.82), Vector3(0.73, 1.40, 1.62)],
	"lounge_chair": ["outdoor_environment", Vector3(-0.87, 0.00, -0.33), Vector3(1.48, 0.92, 0.68)],
	"outdoor_dining_table_b": ["outdoor_environment", Vector3(-0.59, 0.00, -1.16), Vector3(1.18, 0.84, 2.23)],
	"garden_hose": ["outdoor_environment", Vector3(-0.58, -0.00, -0.32), Vector3(0.80, 0.52, 0.53)],
	"rolled_sleeping_bag": ["gameplay_props", Vector3(-0.18, -0.00, -0.36), Vector3(0.36, 0.36, 0.71)],
	"hiking_backpack": ["gameplay_props", Vector3(-0.29, -0.00, -0.33), Vector3(0.58, 0.91, 0.63)],
	"cooler_box_water": ["gameplay_props", Vector3(-0.18, 0.00, -0.25), Vector3(0.36, 0.40, 0.50)],
	"plastic_storage_bin": ["gameplay_props", Vector3(-0.24, -0.00, -0.34), Vector3(0.47, 0.40, 0.69)],
	"backpack": ["gameplay_props", Vector3(-0.26, -0.00, -0.21), Vector3(0.52, 0.72, 0.43)],
	"water_canister": ["gameplay_props", Vector3(-0.14, 0.00, -0.25), Vector3(0.28, 0.58, 0.50)],
	"redwood_hollow_log_2": ["nature/hollow_logs", Vector3(-0.63, 0.00, -3.46), Vector3(1.25, 1.19, 6.92)],
	"sidewalk_curbstone_a_8m": ["street", Vector3(-8.00, -0.00, -0.09), Vector3(8.00, 0.14, 2.54)],
	"sidewalk_curbstone_a_4m": ["street", Vector3(-4.00, -0.00, -0.09), Vector3(4.00, 0.14, 2.54)],
	"sidewalk_curbstone_a_2m": ["street", Vector3(-2.00, -0.00, -0.09), Vector3(2.00, 0.14, 2.54)],
	"line_broken_white_10m": ["street", Vector3(-0.05, 0.00, -10.00), Vector3(0.09, 0.00, 10.00)],
	"line_double_yellow_10m": ["street", Vector3(-0.15, 0.00, -10.00), Vector3(0.29, 0.00, 10.00)],
	"line_pedestrian_crossing_10m": ["street", Vector3(-10.69, 0.00, 0.01), Vector3(10.45, 0.00, 3.52)],
	"wires_20m_01": ["outdoor_environment", Vector3(-20.00, 6.86, -0.98), Vector3(20.00, 1.98, 1.96)],
	"traffic_light_small": ["outdoor_environment", Vector3(-0.23, 0.00, -0.28), Vector3(0.37, 3.58, 0.55)],
	"fence_c_4m": ["outdoor_environment", Vector3(-0.08, 0.00, -0.03), Vector3(0.19, 1.62, 4.07)],
	"backyard_shed_01": ["outdoor_environment", Vector3(-0.81, -0.01, -4.10), Vector3(4.97, 3.66, 4.21)],
	"backyard_shed_03": ["outdoor_environment", Vector3(-0.18, -0.00, -4.16), Vector3(3.28, 3.07, 4.33)],
	"roadside_billboard": ["outdoor_environment", Vector3(-2.44, -0.01, -5.02), Vector3(3.19, 9.93, 9.30)],
	"cantilever_highway_sign": ["outdoor_environment", Vector3(-0.43, -0.01, -9.21), Vector3(0.85, 8.22, 9.68)],
	"church": ["unique_buildings", Vector3(-10.36, -0.01, -18.78), Vector3(43.14, 28.35, 37.55)],
	"motel": ["unique_buildings", Vector3(-0.81, -0.05, -8.70), Vector3(15.62, 9.27, 29.27)],
	"fire_station": ["unique_buildings", Vector3(-4.52, -0.06, -26.16), Vector3(14.70, 8.76, 27.15)],
	"roadside_fast_food": ["unique_buildings", Vector3(-1.59, -0.01, -16.25), Vector3(16.11, 8.70, 17.06)],
	"sheriff_substation": ["unique_buildings", Vector3(-5.44, -0.05, -20.36), Vector3(18.52, 6.78, 21.11)],
	"convenience_store": ["unique_buildings", Vector3(-0.26, -0.03, -18.48), Vector3(18.32, 7.23, 19.03)],
	"fuel_mart": ["unique_buildings", Vector3(-0.67, -0.04, -18.12), Vector3(14.79, 7.25, 18.48)],
	"exterior_only_house_01": ["house", Vector3(-2.82, -0.08, -12.53), Vector3(11.43, 7.42, 12.83)],
	"exterior_only_house_02": ["house", Vector3(-2.82, -0.08, -16.53), Vector3(11.43, 7.42, 16.83)],
	"exterior_only_house_03": ["house", Vector3(-2.82, -0.03, -14.30), Vector3(11.58, 6.32, 16.73)],
	"exterior_only_house_04": ["house", Vector3(-4.83, -0.05, -16.30), Vector3(15.64, 6.28, 16.60)],
	"exterior_only_house_05": ["house", Vector3(-2.82, -0.06, -12.30), Vector3(14.82, 10.97, 18.71)],
	"exterior_only_house_06": ["house", Vector3(-2.82, -0.06, -13.30), Vector3(12.82, 9.88, 19.71)],
	"exterior_only_house_07": ["house", Vector3(-2.82, -0.06, -12.53), Vector3(12.82, 10.20, 16.94)],
	"exterior_only_house_08": ["house", Vector3(-2.82, -0.06, -16.53), Vector3(14.82, 10.20, 16.83)],
	"dry_van_trailer": ["vehicle", Vector3(-2.86, 0.00, -1.17), Vector3(10.72, 3.49, 2.33)],
	"military_truck_01": ["vehicle", Vector3(-4.31, 0.02, -1.53), Vector3(7.83, 3.22, 3.08)],
	"military_apc": ["vehicle", Vector3(-3.71, 0.01, -1.40), Vector3(6.61, 3.12, 2.78)],
	"military_utility_vehicle": ["vehicle", Vector3(-2.39, 0.01, -1.30), Vector3(4.55, 1.94, 2.60)],
	"anti_tank_hedgehog": ["military", Vector3(-0.50, -0.01, -0.60), Vector3(1.15, 1.25, 1.31)],
	"checkpoint_sign_trailer": ["military", Vector3(-1.27, 0.00, -1.03), Vector3(2.62, 2.30, 2.05)],
	"concrete_road_barrier": ["military", Vector3(-0.37, 0.00, -1.06), Vector3(0.72, 0.95, 2.04)],
	"guard_booth": ["military", Vector3(-1.20, 0.00, -1.17), Vector3(2.34, 2.84, 2.35)],
	"guard_booth_metal": ["military", Vector3(-1.25, 0.00, -1.18), Vector3(2.36, 2.69, 2.38)],
	"hesco_barrier_01": ["military", Vector3(-0.76, -0.00, -0.72), Vector3(1.51, 1.65, 1.45)],
	"hesco_barrier_02": ["military", Vector3(-0.76, -0.00, -0.72), Vector3(1.51, 1.65, 1.45)],
	"military_ammo_crate": ["military", Vector3(-0.28, 0.00, -0.48), Vector3(0.55, 0.47, 0.97)],
	"military_ammo_crate_large": ["military", Vector3(-0.43, -0.00, -0.45), Vector3(0.86, 0.65, 0.90)],
	"military_arched_tent_exterior": ["military", Vector3(-3.54, 0.00, -3.22), Vector3(6.92, 3.45, 6.44)],
	"military_arched_tent_interior": ["military", Vector3(-7.47, -0.00, -3.47), Vector3(14.78, 3.73, 6.95)],
	"military_command_tent_exterior": ["military", Vector3(-3.80, 0.00, -2.27), Vector3(7.40, 3.65, 4.54)],
	"military_command_tent_interior": ["military", Vector3(-3.80, -0.00, -2.27), Vector3(7.40, 3.65, 4.54)],
	"military_equipment_case": ["military", Vector3(-0.40, 0.00, -0.49), Vector3(0.80, 0.60, 0.98)],
	"military_field_canopy_01": ["military", Vector3(-3.55, 0.01, -2.28), Vector3(7.17, 3.72, 4.59)],
	"military_folding_chair": ["military", Vector3(-0.28, -0.01, -0.28), Vector3(0.56, 0.93, 0.57)],
	"military_folding_cot": ["military", Vector3(-1.09, -0.00, -0.38), Vector3(2.20, 0.49, 0.76)],
	"military_folding_table": ["military", Vector3(-0.47, 0.00, -0.98), Vector3(0.99, 0.80, 1.90)],
	"military_fuel_barrel": ["military", Vector3(-0.32, -0.00, -0.33), Vector3(0.65, 1.09, 0.66)],
	"military_generator_large": ["military", Vector3(-1.24, 0.00, -0.61), Vector3(2.49, 1.31, 1.24)],
	"military_light_tower_big": ["military", Vector3(-0.66, -0.02, -0.71), Vector3(1.33, 7.55, 1.42)],
	"military_meal_crate": ["military", Vector3(-0.26, 0.00, -0.45), Vector3(0.54, 0.52, 0.94)],
	"military_rifle_crate": ["military", Vector3(-0.27, 0.01, -0.69), Vector3(0.59, 0.39, 1.43)],
	"military_rocket_crate_01": ["military", Vector3(-0.19, 0.00, -0.52), Vector3(0.38, 0.38, 1.04)],
	"military_rocket_crate_02": ["military", Vector3(-0.22, 0.00, -0.85), Vector3(0.44, 0.38, 1.70)],
	"military_sign_slow": ["military", Vector3(-0.30, -0.00, -0.50), Vector3(0.60, 1.13, 0.97)],
	"military_sign_stop": ["military", Vector3(-0.36, -0.00, -0.40), Vector3(0.73, 1.37, 0.80)],
	"military_sleeping_bag": ["military", Vector3(-1.05, 0.00, -0.44), Vector3(2.14, 0.20, 0.87)],
	"military_vehicle_parts_crate": ["military", Vector3(-0.35, -0.00, -0.52), Vector3(0.70, 0.48, 1.04)],
	"mobile_light_tower": ["military", Vector3(-1.36, -0.01, -0.69), Vector3(2.39, 2.54, 1.37)],
	"portable_field_toilet": ["military", Vector3(-0.48, 0.00, -0.47), Vector3(1.01, 1.93, 0.96)],
	"road_barricade": ["military", Vector3(-0.41, 0.00, -0.96), Vector3(0.82, 1.13, 1.94)],
	"sandbag_pile_01": ["military", Vector3(-0.45, -0.01, -1.54), Vector3(0.82, 1.16, 2.88)],
	"sandbag_pile_02": ["military", Vector3(-0.80, -0.01, -2.46), Vector3(1.17, 1.15, 4.66)],
	"sandbag_pile_03": ["military", Vector3(-3.76, -0.01, -3.61), Vector3(3.98, 1.16, 3.72)],
	"sandbag_pile_04": ["military", Vector3(-0.45, -0.01, -2.79), Vector3(0.87, 1.66, 5.57)],
	"sandbag_pile_05": ["military", Vector3(-0.39, -0.01, -2.95), Vector3(2.93, 1.36, 3.38)],
	"sandbag_pile_06": ["military", Vector3(-0.64, 0.00, -0.64), Vector3(1.32, 1.63, 1.19)],
	"spike_strip": ["military", Vector3(-0.20, 0.00, -1.64), Vector3(0.40, 0.01, 3.27)],
	"striped_concrete_barrier": ["military", Vector3(-0.33, 0.00, -0.90), Vector3(0.65, 0.96, 1.79)],
	"gas_station_canopy": ["unique_buildings", Vector3(-9.00, 0.00, -24.00), Vector3(9.00, 6.14, 24.00)],
	"store_signboard": ["outdoor_environment", Vector3(-0.35, -0.00, -1.83), Vector3(0.69, 8.53, 3.65)],
	"big_kids_slide": ["outdoor_environment", Vector3(-1.33, -0.00, -0.96), Vector3(2.65, 2.32, 3.00)],
	"small_kids_slide": ["outdoor_environment", Vector3(-0.42, -0.02, -0.59), Vector3(0.83, 1.15, 1.60)],
	"wooden_swing": ["outdoor_environment", Vector3(-0.76, 0.02, -1.14), Vector3(1.52, 2.15, 2.31)],
	"backyard_trampoline": ["outdoor_environment", Vector3(-1.32, 0.01, -1.29), Vector3(2.64, 0.74, 2.64)],
	"round_swimming_pool": ["outdoor_environment", Vector3(-2.76, -0.00, -2.39), Vector3(5.13, 1.55, 4.83)],
	"patio_umbrella": ["outdoor_environment", Vector3(-1.29, -0.00, -1.30), Vector3(2.59, 2.67, 2.59)],
	"plastic_table": ["outdoor_environment", Vector3(-0.63, -0.00, -0.64), Vector3(1.25, 0.83, 1.25)],
	"patio_chair_01": ["outdoor_environment", Vector3(-0.46, -0.00, -0.40), Vector3(0.97, 1.08, 0.80)],
	"garden_gnome_01": ["outdoor_environment", Vector3(-0.32, -0.00, -0.22), Vector3(0.52, 0.91, 0.43)],
	"garden_gnome_02": ["outdoor_environment", Vector3(-0.19, -0.00, -0.25), Vector3(0.36, 0.68, 0.47)],
	"motorhome": ["vehicle", Vector3(-3.12, -0.00, -1.28), Vector3(7.24, 2.95, 2.53)],
	"tanker_truck": ["vehicle", Vector3(-3.36, 0.01, -1.19), Vector3(6.48, 2.56, 2.38)],
	"ice_cream_truck": ["vehicle", Vector3(-1.82, 0.01, -1.05), Vector3(4.20, 2.61, 2.17)],
	"house_wooden_deck_c_4x4m": ["house_modules", Vector3(-4.00, 0.00, -4.00), Vector3(4.00, 0.20, 4.00)],
	"compact_power_station": ["gameplay_props", Vector3(-0.33, -0.03, -0.24), Vector3(0.65, 0.64, 0.48)],
	"fuel_canister": ["gameplay_props", Vector3(-0.15, 0.00, -0.33), Vector3(0.30, 0.65, 0.59)],
	"fuel_tank_covers": ["outdoor_environment", Vector3(-0.59, 0.00, -1.10), Vector3(1.18, 0.17, 2.20)],
	"basketball_hoop": ["outdoor_environment", Vector3(-1.20, 0.03, -0.61), Vector3(2.13, 3.46, 1.24)],
	"campaign_yard_sign_01": ["outdoor_environment", Vector3(-0.04, -0.02, -0.48), Vector3(0.05, 0.90, 0.97)],
	"air_vac_station_01": ["outdoor_environment", Vector3(-1.02, 0.00, -1.67), Vector3(1.92, 2.74, 3.32)],
	"fuel_price_sign_01": ["outdoor_environment", Vector3(-0.32, 0.00, -1.14), Vector3(0.82, 5.49, 2.20)],
	"fence_b_4m": ["outdoor_environment", Vector3(-0.08, 0.00, -0.03), Vector3(0.20, 1.62, 4.03)],
	"big_boulders_0": ["nature/rocks", Vector3(-3.03, -2.79, -2.78), Vector3(6.09, 5.59, 5.55)],
	"big_boulders_1": ["nature/rocks", Vector3(-3.04, -2.90, -3.03), Vector3(6.10, 5.74, 6.03)],
	"big_boulders_2": ["nature/rocks", Vector3(-3.04, -2.81, -3.04), Vector3(6.09, 5.70, 6.09)],
	"big_boulders_3": ["nature/rocks", Vector3(-3.03, -2.85, -3.17), Vector3(6.06, 5.71, 6.19)],
	"rubble_dense_1": ["nature/rocks", Vector3(-2.57, -0.22, -2.91), Vector3(4.64, 0.79, 5.25)],
	"rubble_dense_2": ["nature/rocks", Vector3(-3.68, -0.21, -3.12), Vector3(6.33, 0.78, 5.98)],
	"rubble_dense_3": ["nature/rocks", Vector3(-3.46, -0.21, -3.29), Vector3(7.42, 0.89, 7.68)],
	"redwood_hollow_log2_1": ["nature/hollow_logs", Vector3(-0.60, 0.00, -2.69), Vector3(1.21, 1.12, 5.37)],
	"house_porch_railing_a_2m": ["house_modules", Vector3(-0.13, -0.04, -2.00), Vector3(0.25, 1.06, 2.14)],
	"car_sedan_01": ["vehicle", Vector3(-2.25, -0.00, -1.05), Vector3(4.70, 1.39, 2.08)],
	"car_sedan_02": ["vehicle", Vector3(-2.26, 0.00, -0.92), Vector3(4.72, 1.35, 1.85)],
	"car_sedan_03": ["vehicle", Vector3(-2.52, -0.01, -1.05), Vector3(4.89, 1.53, 2.11)],
	"car_crossover_01": ["vehicle", Vector3(-2.27, 0.00, -1.09), Vector3(4.56, 1.74, 2.19)],
	"car_crossover_02": ["vehicle", Vector3(-2.23, -0.00, -1.13), Vector3(4.50, 1.68, 2.23)],
	"car_crossover_03": ["vehicle", Vector3(-1.81, -0.02, -0.94), Vector3(3.82, 1.76, 1.88)],
	"car_crossover_04": ["vehicle", Vector3(-2.28, -0.01, -1.09), Vector3(4.68, 1.81, 2.19)],
	"car_crossover_05": ["vehicle", Vector3(-2.32, -0.01, -1.14), Vector3(4.78, 1.66, 2.23)],
	"car_minivan_01": ["vehicle", Vector3(-2.15, 0.00, -1.01), Vector3(4.41, 1.60, 2.03)],
	"police_sedan": ["vehicle", Vector3(-2.61, 0.00, -1.02), Vector3(4.90, 1.59, 2.03)],
	"car_sport_01": ["vehicle", Vector3(-2.45, -0.00, -1.08), Vector3(4.77, 1.44, 2.14)],
	"school_bus": ["vehicle", Vector3(-4.54, 0.01, -1.56), Vector3(9.91, 3.26, 3.24)],
	"truck": ["vehicle", Vector3(-3.65, 0.00, -1.42), Vector3(7.56, 3.76, 2.84)],
	"service_van": ["vehicle", Vector3(-2.55, -0.00, -0.93), Vector3(5.02, 2.18, 1.98)],
	"barrel_01": ["outdoor_environment", Vector3(-0.31, 0.00, -0.31), Vector3(0.63, 0.95, 0.63)],
	"barrel_02": ["outdoor_environment", Vector3(-0.31, 0.00, -0.31), Vector3(0.63, 0.95, 0.63)],
	"plastic_barrel_02": ["outdoor_environment", Vector3(-0.34, 0.00, -0.34), Vector3(0.67, 1.00, 0.67)],
	"curbside_trash_bin_01": ["outdoor_environment", Vector3(-0.26, 0.00, -0.35), Vector3(0.80, 1.10, 0.69)],
	"curbside_trash_bin_03": ["outdoor_environment", Vector3(-0.42, 0.00, -0.38), Vector3(0.84, 1.00, 0.75)],
	"trash_bag_01": ["outdoor_environment", Vector3(-0.36, -0.00, -0.32), Vector3(0.71, 0.73, 0.64)],
	"trash_bag_02": ["outdoor_environment", Vector3(-0.32, -0.01, -0.39), Vector3(0.64, 0.69, 0.79)],
	"pile_garbage_01": ["outdoor_environment", Vector3(-0.55, -0.10, -0.92), Vector3(1.10, 0.74, 1.68)],
	"pile_garbage_02": ["outdoor_environment", Vector3(-0.44, -0.04, -0.43), Vector3(0.81, 0.53, 0.94)],
	"pile_garbage_03": ["outdoor_environment", Vector3(-0.76, -0.09, -0.89), Vector3(1.78, 0.64, 1.93)],
	"tool_cabinet": ["outdoor_environment", Vector3(-0.26, 0.00, -0.50), Vector3(0.53, 1.02, 1.01)],
	"commercial_dumpster_01": ["outdoor_environment", Vector3(-0.50, 0.00, -0.85), Vector3(1.05, 1.22, 1.70)],
	"commercial_dumpster_02": ["outdoor_environment", Vector3(-0.54, 0.00, -0.89), Vector3(1.14, 1.22, 1.78)],
	"commercial_dumpster_03": ["outdoor_environment", Vector3(-0.48, -0.00, -0.96), Vector3(0.98, 1.21, 1.93)],
	"fire_hydrant_01": ["outdoor_environment", Vector3(-0.19, -0.00, -0.17), Vector3(0.35, 0.84, 0.36)],
	"fire_hydrant_02": ["outdoor_environment", Vector3(-0.20, -0.00, -0.17), Vector3(0.35, 0.89, 0.34)],
	"rural_mailbox_01": ["outdoor_environment", Vector3(-0.55, -0.01, -0.10), Vector3(0.60, 1.33, 0.19)],
	"rural_mailbox_02": ["outdoor_environment", Vector3(-0.54, 0.00, -0.10), Vector3(0.60, 1.44, 0.19)],
	"parking_lot_light_pole_01": ["outdoor_environment", Vector3(-0.43, 0.00, -0.19), Vector3(0.63, 6.85, 0.39)],
	"electrical_pole_01": ["outdoor_environment", Vector3(-0.06, 0.00, -1.21), Vector3(0.34, 9.00, 2.45)],
	"sign_stop": ["outdoor_environment", Vector3(-0.05, 0.00, -0.34), Vector3(0.08, 2.69, 0.68)],
	"sign_speed_limit": ["outdoor_environment", Vector3(-0.08, 0.00, -0.24), Vector3(0.11, 2.53, 0.48)],
	"sign_dead_end": ["outdoor_environment", Vector3(-0.05, 0.00, -0.43), Vector3(0.08, 2.68, 0.85)],
	"sign_children": ["outdoor_environment", Vector3(-0.05, 0.00, -0.31), Vector3(0.07, 2.79, 0.63)],
	"urn_street_01": ["outdoor_environment", Vector3(-0.18, 0.00, -0.19), Vector3(0.35, 0.76, 0.38)],
	"urn_street_02": ["outdoor_environment", Vector3(-0.23, 0.00, -0.23), Vector3(0.46, 0.83, 0.46)],
	"utility_cabinet_01": ["outdoor_environment", Vector3(-0.22, -0.00, -0.49), Vector3(0.47, 0.98, 1.03)],
	"utility_cabinet_03": ["outdoor_environment", Vector3(-0.37, 0.00, -0.58), Vector3(0.73, 1.27, 1.16)],
	"conditioner_07": ["outdoor_environment", Vector3(-0.88, 0.00, -0.59), Vector3(1.75, 0.96, 1.18)],
	"conditioner_08": ["outdoor_environment", Vector3(-0.71, -0.00, -0.43), Vector3(1.42, 0.68, 0.86)],
	"satellite_dish": ["outdoor_environment", Vector3(-1.01, 0.00, -0.57), Vector3(1.33, 1.58, 1.19)],
	"solar_battery_01": ["outdoor_environment", Vector3(-2.02, -0.01, -1.38), Vector3(4.03, 0.10, 2.78)],
	"traffic_cone": ["outdoor_environment", Vector3(-0.21, 0.00, -0.21), Vector3(0.42, 0.79, 0.42)],
	"traffic_cone_big": ["outdoor_environment", Vector3(-0.43, -0.00, -0.43), Vector3(0.85, 1.03, 0.85)],
	"pallet": ["outdoor_environment", Vector3(-0.65, -0.00, -0.54), Vector3(1.29, 0.22, 1.08)],
	"wheelbarrow": ["outdoor_environment", Vector3(-0.77, -0.01, -0.46), Vector3(2.09, 0.80, 0.92)],
	"lawn_mower_01": ["outdoor_environment", Vector3(-0.43, 0.00, -0.38), Vector3(1.85, 1.01, 0.74)],
	"doghouse": ["outdoor_environment", Vector3(-0.58, -0.00, -0.73), Vector3(1.11, 1.20, 1.47)],
	"firewood_rack": ["outdoor_environment", Vector3(-0.25, 0.00, -0.55), Vector3(0.51, 1.16, 1.09)],
	"electrical_service_meter": ["outdoor_environment", Vector3(-0.27, 0.00, -0.17), Vector3(0.29, 3.19, 0.57)],
	"concrete_bump_5m": ["street", Vector3(-0.35, 0.00, -5.00), Vector3(0.69, 1.00, 5.00)],
	"roof_vents_01": ["house_modules", Vector3(-0.29, 0.00, -0.29), Vector3(0.58, 0.44, 0.58)],
	"roof_vents_02": ["house_modules", Vector3(-0.29, 0.00, -0.29), Vector3(0.58, 0.24, 0.58)],
	"roof_vents_03": ["house_modules", Vector3(-0.24, 0.01, -0.24), Vector3(0.48, 0.13, 0.49)],
	"roof_vents_04": ["house_modules", Vector3(-0.22, 0.00, -0.62), Vector3(0.44, 0.20, 1.23)],
	"chimney_02": ["house_modules", Vector3(-0.33, 0.00, -0.33), Vector3(0.67, 1.48, 0.67)],
	"picture_01": ["furniture", Vector3(-0.02, -0.46, -0.36), Vector3(0.02, 0.91, 0.72)],
	"picture_02": ["furniture", Vector3(-0.02, -0.46, -0.36), Vector3(0.02, 0.91, 0.72)],
	"picture_03": ["furniture", Vector3(-0.04, -0.68, -0.53), Vector3(0.00, 1.36, 1.06)],
	"picture_04": ["furniture", Vector3(-0.02, -0.53, -0.41), Vector3(0.00, 1.06, 0.83)],
	"carpet_big_02": ["furniture", Vector3(-1.92, 0.00, -1.02), Vector3(3.84, 0.01, 2.03)],
	"carpet_big_03": ["furniture", Vector3(-1.98, 0.00, -1.01), Vector3(3.97, 0.01, 2.03)],
	"tv_01": ["furniture", Vector3(-0.26, 0.00, -0.44), Vector3(0.71, 0.72, 0.76)],
	"computer": ["furniture", Vector3(-0.42, -0.00, -0.48), Vector3(0.57, 0.77, 0.98)],
	"bookcase_03": ["furniture", Vector3(-0.21, 0.06, -0.27), Vector3(0.47, 1.83, 0.54)],
	"chair_02": ["furniture", Vector3(-0.31, -0.00, -0.27), Vector3(0.73, 1.15, 0.53)],
	"table_03": ["furniture", Vector3(-0.89, 0.01, -1.54), Vector3(1.80, 0.84, 3.15)],
	"cash_register": ["retail_shelving", Vector3(-0.30, -0.01, -0.48), Vector3(0.52, 0.63, 0.97)],
	"birch_03": ["vegetation", Vector3(-0.99, -0.00, -1.14), Vector3(2.21, 3.37, 2.23)],
	"birch_04": ["vegetation", Vector3(-1.62, -0.00, -1.66), Vector3(2.81, 4.98, 3.36)],
	"pine_03": ["vegetation", Vector3(-0.89, -0.00, -1.29), Vector3(2.18, 3.53, 2.69)],
	"spruce_03": ["vegetation", Vector3(-1.06, -0.00, -1.00), Vector3(2.03, 3.36, 2.01)],
	"aspen_03": ["vegetation", Vector3(-2.63, -0.00, -2.46), Vector3(4.88, 5.90, 5.32)],
	"maple_01": ["vegetation", Vector3(-3.09, -0.01, -3.33), Vector3(6.54, 7.99, 6.66)],
	"bushes_02": ["vegetation", Vector3(-1.25, -0.23, -1.20), Vector3(2.52, 3.12, 2.23)],
	"bushes_03": ["vegetation", Vector3(-1.14, -0.07, -1.21), Vector3(2.20, 2.14, 2.33)],
	"bushes_04": ["vegetation", Vector3(-0.90, -0.14, -0.85), Vector3(1.71, 1.45, 1.66)],
	"bushes_05": ["vegetation", Vector3(-1.18, -0.19, -1.39), Vector3(2.56, 2.18, 2.35)],
	"bushes_06": ["vegetation", Vector3(-1.05, -0.09, -1.14), Vector3(2.22, 1.58, 1.99)],
	"bushes_07": ["vegetation", Vector3(-0.81, -0.16, -0.99), Vector3(1.71, 1.58, 1.82)],
	"bushes_08": ["vegetation", Vector3(-0.75, -0.13, -0.93), Vector3(1.66, 1.30, 1.74)],
	"grass_01": ["vegetation", Vector3(-1.01, -0.07, -0.89), Vector3(1.81, 0.56, 1.69)],
	"grass_02": ["vegetation", Vector3(-1.14, -0.05, -1.04), Vector3(2.08, 0.68, 1.96)],
	"grass_03": ["vegetation", Vector3(-1.31, -0.11, -1.51), Vector3(2.55, 1.24, 2.96)],
	"grass_04": ["vegetation", Vector3(-0.55, -0.11, -0.73), Vector3(1.49, 1.50, 1.46)],
	"grass_05": ["vegetation", Vector3(-0.83, -0.06, -0.71), Vector3(1.59, 1.31, 1.52)],
	"grass_06": ["vegetation", Vector3(-0.97, -0.01, -1.13), Vector3(2.02, 0.31, 2.09)],
	"fern_01_1": ["vegetation", Vector3(-0.70, -0.01, -0.72), Vector3(1.42, 0.40, 1.42)],
	"fern_02_1": ["vegetation", Vector3(-0.80, -0.02, -0.79), Vector3(1.57, 0.60, 1.51)],
	"hedge_rectangular_4m": ["vegetation", Vector3(-0.58, -0.10, -0.18), Vector3(1.17, 1.56, 4.38)],
	"red_fir2": ["nature/trees", Vector3(-0.81, -0.17, -0.87), Vector3(1.70, 4.06, 1.57)],
	"red_fir3": ["nature/trees", Vector3(-1.08, -0.08, -1.27), Vector3(2.15, 5.12, 2.38)],
	"red_fir4": ["nature/trees", Vector3(-1.96, -0.16, -1.79), Vector3(3.80, 7.56, 3.05)],
	"red_pine1": ["nature/trees", Vector3(-1.72, -0.29, -1.93), Vector3(3.61, 6.43, 3.69)],
	"red_pine2": ["nature/trees", Vector3(-1.96, -0.29, -2.04), Vector3(3.79, 8.05, 3.67)],
	"grass_1": ["nature/plants", Vector3(-0.76, -0.11, -0.74), Vector3(1.52, 0.34, 1.48)],
	"grass_2": ["nature/plants", Vector3(-1.27, -0.12, -1.37), Vector3(2.54, 0.41, 2.74)],
	"grass_3": ["nature/plants", Vector3(-1.65, -0.13, -1.60), Vector3(3.30, 1.12, 3.21)],
	"thin_fern1": ["nature/plants", Vector3(-0.46, -0.04, -0.39), Vector3(0.92, 0.59, 0.77)],
	"thin_fern2": ["nature/plants", Vector3(-0.62, 0.02, -0.64), Vector3(1.20, 0.39, 1.32)],
	"thin_fern3": ["nature/plants", Vector3(-0.65, 0.02, -0.85), Vector3(1.47, 0.76, 1.48)],
	"thin_fern4": ["nature/plants", Vector3(-1.02, -0.00, -0.99), Vector3(2.08, 1.07, 2.01)],
	"clovers_1": ["nature/plants", Vector3(-0.34, 0.00, -0.33), Vector3(0.68, 0.05, 0.65)],
	"clovers_2": ["nature/plants", Vector3(-0.41, 0.00, -0.42), Vector3(0.89, 0.06, 0.85)],
	"dead_leaves_1": ["nature/plants", Vector3(-0.42, -0.02, -0.38), Vector3(0.84, 0.05, 0.76)],
	"dead_leaves_2": ["nature/plants", Vector3(-0.61, -0.09, -0.58), Vector3(1.22, 0.13, 1.15)],
	"magnus_1": ["nature/plants", Vector3(-0.39, -0.00, -0.43), Vector3(0.79, 0.60, 0.87)],
	"magnus_2": ["nature/plants", Vector3(-0.67, -0.02, -0.65), Vector3(1.34, 0.63, 1.29)],
	"branches": ["nature/plants", Vector3(-0.71, 0.01, -0.65), Vector3(1.43, 0.13, 1.30)],
	"fungi_polyp_1": ["nature/plants", Vector3(-0.41, -0.11, -0.44), Vector3(0.81, 0.22, 0.83)],
	"boulder_0": ["nature/rocks", Vector3(-3.01, -1.86, -2.26), Vector3(6.03, 3.76, 4.48)],
	"boulder_1": ["nature/rocks", Vector3(-3.02, -1.95, -1.80), Vector3(6.02, 3.97, 3.60)],
	"boulder_2": ["nature/rocks", Vector3(-3.01, -2.09, -1.64), Vector3(6.05, 4.21, 3.20)],
	"boulder_4": ["nature/rocks", Vector3(-3.01, -2.43, -2.44), Vector3(6.07, 4.93, 4.85)],
	"boulder_5": ["nature/rocks", Vector3(-3.02, -2.14, -2.11), Vector3(6.07, 4.31, 4.20)],
	"rubble_sparse_1": ["nature/rocks", Vector3(-2.60, -0.21, -2.08), Vector3(4.34, 0.75, 3.86)],
	"rubble_sparse_2": ["nature/rocks", Vector3(-2.83, -0.21, -3.41), Vector3(5.88, 0.80, 5.67)],
	"rubble_sparse_3": ["nature/rocks", Vector3(-3.14, -0.21, -3.32), Vector3(5.80, 0.71, 6.10)],
	"redwood_hollow_log_0": ["nature/hollow_logs", Vector3(-0.43, 0.00, -1.95), Vector3(0.86, 0.83, 3.90)],
	"redwood_hollow_log_1": ["nature/hollow_logs", Vector3(-0.50, 0.00, -2.68), Vector3(1.00, 1.06, 5.37)],
}
## Prop facing (the way its front looks, in the plan) -> yaw. The pack's front is -X.
const FACE_YAW := {"w": 0.0, "e": PI, "s": PI * 0.5, "n": -PI * 0.5}


static func available() -> bool:
	return DirAccess.dir_exists_absolute(ROOT)


static func piece_path(folder: String, piece: String) -> String:
	if folder.begins_with("nature/"):
		return NATURE_ROOT + folder.substr(7) + "/" + piece + ".fbx"
	return ROOT + folder + "/" + piece + ".fbx"


## Pivot transform and world bounds of a PROPS piece whose footprint is centered at center (xz),
## turned by yaw, raised by y and uniformly scaled. decor: y > 0 (on a counter, on a wall), no collision.
static func prop_part(piece: String, center: Vector2, yaw: float, y := 0.0, scale := 1.0) -> Dictionary:
	if not PROPS.has(piece):
		push_error("CityKit: no bounds for prop %s" % piece)
		return {}
	var info: Array = PROPS[piece]
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	var pos: Vector3 = info[1] * scale
	var size: Vector3 = info[2] * scale
	var local_center := pos + size * 0.5
	var turned: Vector3 = (Basis(Vector3.UP, yaw) * size).abs()
	var pivot := Vector3(center.x, y, center.y) - Basis(Vector3.UP, yaw) * Vector3(local_center.x, 0.0, local_center.z)
	var box := AABB(Vector3(center.x - turned.x * 0.5, y + pos.y, center.y - turned.z * 0.5), turned)
	return {"piece": piece, "folder": info[0], "xf": Transform3D(basis, pivot), "box": box, "decor": y > 0.0}


## Instances a pack piece under parent so that its own pivot sits at xf.
static func place(parent: Node3D, folder: String, piece: String, xf: Transform3D) -> Node3D:
	var scene := load(piece_path(folder, piece)) as PackedScene
	if scene == null:
		push_error("CityKit: cannot load %s" % piece_path(folder, piece))
		return null
	var node := scene.instantiate() as Node3D
	node.name = piece.to_pascal_case()
	var top := node.get_child(0) as Node3D
	node.transform = xf * Transform3D(Basis.IDENTITY, -top.position)
	parent.add_child(node, true)
	return node


# --- parts -------------------------------------------------------------------

## World-space parts of one building.
## plan: size (Vector2i: depth along X, length along Z), edges ({n, s, w, e}: tokens, west to east
##   and north to south), inner ([from: Vector2, to: Vector2, tokens]), props ([piece, x, z, face],
##   x/z = footprint center), floor (style), porch (bool). The plan's front is its east edge.
## spec: origin (Vector2i, north-west corner), mirror (true: the plan's east front faces west),
##   style (a, b or c), roof (gable or flat).
## Returns rect (Rect2), segments ([{kind, len, a, b, inward, inner, index}]), doors ([[x, z, gap]]),
## props ([{piece, folder, xf, box: AABB}]), walls (Array[AABB]), floor ([{piece, rect}]).
static func parts(plan: Dictionary, spec: Dictionary) -> Dictionary:
	var size: Vector2i = plan.size
	var out := {"rect": Rect2(Vector2(spec.origin), Vector2(size)), "segments": [], "doors": [],
		"props": [], "walls": [], "floor": []}
	var lines := {
		"n": [Vector2(0, 0), Vector2(size.x, 0), Vector2(0, 1)],
		"s": [Vector2(0, size.y), Vector2(size.x, size.y), Vector2(0, -1)],
		"w": [Vector2(0, 0), Vector2(0, size.y), Vector2(1, 0)],
		"e": [Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(-1, 0)],
	}
	for edge: String in lines:
		var l: Array = lines[edge]
		_cut(out, plan, spec, plan.edges[edge], l[0], l[1], l[2], false)
	for inner: Array in plan.get("inner", []):
		_cut(out, plan, spec, inner[2], inner[0], inner[1], Vector2.ZERO, true)
	for seg: Dictionary in out.segments:
		out.walls.append_array(_segment_boxes(seg))
	for p: Array in plan.get("props", []):
		out.props.append(_prop(plan, spec, p))
	out.floor = _floor_tiles(out.rect, plan.get("floor", "b"))
	return out


## Collision boxes of the props: [tall (Array[AABB]), low (Array[AABB])].
static func prop_boxes(p: Dictionary) -> Array:
	var tall: Array[AABB] = []
	var low: Array[AABB] = []
	for prop: Dictionary in p.props:
		var box: AABB = prop.box
		if prop.decor or box.size.y < PROP_MIN_COLLIDE_H:
			continue
		if box.size.y <= LOW_COVER_MAX_H:
			low.append(box)
		else:
			tall.append(box)
	return [tall, low]


static func _cut(out: Dictionary, plan: Dictionary, spec: Dictionary, tokens: String, from: Vector2,
		to: Vector2, inward: Vector2, inner: bool) -> void:
	var dir := (to - from).normalized()
	var at := 0.0
	for token in tokens.split(" ", false):
		var length := float(token.substr(1))
		var a := from + dir * at
		var b := from + dir * (at + length)
		at += length
		var seg := {"kind": token[0], "len": int(length), "a": _world(plan, spec, a), "b": _world(plan, spec, b),
			"inward": _world_dir(spec, inward), "inner": inner, "index": out.segments.size()}
		out.segments.append(seg)
		if seg.kind in ["e", "d"]:
			var c: Vector2 = (seg.a + seg.b) * 0.5
			out.doors.append([c.x, c.y, DOOR_GAP])
	if not is_equal_approx(at, from.distance_to(to)):
		push_error("CityKit: wall tokens '%s' are %.1f m, the wall is %.1f m" % [tokens, at, from.distance_to(to)])


## Plan point -> world xz.
static func _world(plan: Dictionary, spec: Dictionary, p: Vector2) -> Vector2:
	var size: Vector2i = plan.size
	var x := size.x - p.x if spec.get("mirror", false) else p.x
	return Vector2(spec.origin) + Vector2(x, p.y)


static func _world_dir(spec: Dictionary, d: Vector2) -> Vector2:
	return Vector2(-d.x, d.y) if spec.get("mirror", false) else d


## Wall collision of one segment, 0.2 m thick (inward from the outline for outer walls, centered
## for inner walls), split around a door gap.
static func _segment_boxes(seg: Dictionary) -> Array[AABB]:
	var out: Array[AABB] = []
	if seg.kind == "x":
		return out
	var a: Vector2 = seg.a
	var b: Vector2 = seg.b
	var dir := (b - a).normalized()
	var spans: Array[Vector2] = [Vector2(0.0, a.distance_to(b))]
	if seg.kind in ["e", "d"]:
		var mid := a.distance_to(b) * 0.5
		spans = [Vector2(0.0, mid - DOOR_GAP * 0.5), Vector2(mid + DOOR_GAP * 0.5, a.distance_to(b))]
	var side: Vector2 = seg.inward * WALL_T if not seg.inner else Vector2(-dir.y, dir.x) * WALL_T
	var shift := Vector2.ZERO if not seg.inner else -side * 0.5
	for s in spans:
		if s.y - s.x < 0.05:
			continue
		var p0 := a + dir * s.x + shift
		var p1 := a + dir * s.y + shift + side
		var lo := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y))
		var hi := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y))
		out.append(AABB(Vector3(lo.x, 0.0, lo.y), Vector3(hi.x - lo.x, WALL_H, hi.y - lo.y)))
	return out


## Plan prop [piece, x, z, face, y (optional, on a counter or a wall)].
static func _prop(plan: Dictionary, spec: Dictionary, p: Array) -> Dictionary:
	var face: String = p[3]
	if spec.get("mirror", false):
		face = {"e": "w", "w": "e"}.get(face, face)
	var y: float = p[4] if p.size() > 4 else 0.0
	var part := prop_part(p[0], _world(plan, spec, Vector2(p[1], p[2])), FACE_YAW[face], y)
	if not part.is_empty() and y == 0.0:
		part.xf.origin.y = FLOOR_Y
		part.box.position.y += FLOOR_Y
	return part


## Greedy floor tiling of rect on a 2 m grid, biggest pieces first.
static func _floor_tiles(rect: Rect2, style: String) -> Array:
	var cols := int(rect.size.x / 2.0)
	var rows := int(rect.size.y / 2.0)
	var used := {}
	var out := []
	var sizes: Array = FLOOR_SIZES.get(style, FLOOR_SIZES.b)
	var all_sizes: Array = FLOOR_SIZES.b
	for j in rows:
		for i in cols:
			if used.has(Vector2i(i, j)):
				continue
			for wd: Array in all_sizes:
				var w: int = wd[0] / 2
				var d: int = wd[1] / 2
				if i + w > cols or j + d > rows or not _free(used, i, j, w, d):
					continue
				for di in w:
					for dj in d:
						used[Vector2i(i + di, j + dj)] = true
				var s := style if wd in sizes else "b"
				out.append({"piece": "house_floor_%s_%dx%dm" % [s, wd[1], wd[0]],
					"rect": Rect2(rect.position + Vector2(i, j) * 2.0, Vector2(wd[0], wd[1]))})
				break
	return out


static func _free(used: Dictionary, i: int, j: int, w: int, d: int) -> bool:
	for di in w:
		for dj in d:
			if used.has(Vector2i(i + di, j + dj)):
				return false
	return true


# --- meshes ------------------------------------------------------------------

## Places the pack meshes of one building under parent. Needs the pack (available()).
static func build_meshes(parent: Node3D, id: StringName, plan: Dictionary, spec: Dictionary, p: Dictionary) -> Node3D:
	var building := Node3D.new()
	building.name = String(id).to_pascal_case()
	parent.add_child(building)
	var style: String = spec.style
	var walls := _group(building, "Walls")
	var porch := _group(building, "Porch")
	for seg: Dictionary in p.segments:
		var piece := _segment_piece(seg, style, String(id))
		if piece.is_empty():
			continue
		var xf := _segment_xf(seg)
		place(walls, MODULES, piece, xf)
		if plan.get("porch", false) and seg.kind == "e" and not seg.inner and PORCH.has(seg.len):
			place(porch, MODULES, PORCH[seg.len], xf)
	var floor := _group(building, "Floor")
	for tile: Dictionary in p.floor:
		var r: Rect2 = tile.rect
		place(floor, MODULES, tile.piece, Transform3D(Basis.IDENTITY, Vector3(r.position.x, FLOOR_Y, r.end.y)))
	var props := _group(building, "Props")
	for prop: Dictionary in p.props:
		if not prop.is_empty():
			place(props, prop.folder, prop.piece, prop.xf)
	var roof := _group(building, "Roof")
	roof.add_to_group(ROOF_GROUP, true)
	roof.set_meta(ROOF_META, id)
	if spec.get("roof", "gable") == "gable":
		_gable(roof, p.rect, style)
	else:
		_flat_roof(roof, p.rect, String(id))
	return building


static func _group(parent: Node3D, node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	parent.add_child(node)
	return node


static func _segment_piece(seg: Dictionary, style: String, salt: String) -> String:
	var length: int = seg.len
	if seg.inner:
		match seg.kind:
			"w":
				return INNER_WALL.get(length, "")
			"d":
				return INNER_DOOR.get(length, "")
		return ""
	var pool: Array = []
	match seg.kind:
		"w":
			return WALL[style].get(length, "")
		"n":
			pool = WINDOW[style].get(length, [])
		"e":
			pool = ENTRANCE[style].get(length, [])
	if pool.is_empty():
		if seg.kind != "x":
			push_error("CityKit: style %s has no %s piece of %d m" % [style, seg.kind, length])
		return ""
	return pool[absi(hash(salt + str(seg.index))) % pool.size()]


## Piece pivot for a wall segment: X points inward (exterior face on the outline), Z along the wall,
## origin at the segment end the piece runs back from. Inner walls are centered on their line.
static func _segment_xf(seg: Dictionary) -> Transform3D:
	var a: Vector2 = seg.a
	var b: Vector2 = seg.b
	var dir := (b - a).normalized()
	var inward: Vector2 = seg.inward if not seg.inner else Vector2(-dir.y, dir.x)
	var x := Vector3(inward.x, 0.0, inward.y)
	var z := x.cross(Vector3.UP)
	var end := a if Vector3(a.x, 0.0, a.y).dot(z) > Vector3(b.x, 0.0, b.y).dot(z) else b
	var origin := Vector3(end.x, 0.0, end.y)
	if seg.inner:
		origin -= x * WALL_T * 0.5
	return Transform3D(Basis(x, Vector3.UP, z), origin)


## Gable roof along Z over a 6 or 8 m deep rect, in 4 m pieces (2 m for the rest), with both ends.
static func _gable(roof: Node3D, rect: Rect2, style: String) -> void:
	var depth := int(rect.size.x)
	if not GABLE.has(depth):
		push_error("CityKit: no gable roof for a %d m deep building" % depth)
		return
	var names: Array = GABLE[depth][style]
	var z := rect.position.y
	while z < rect.end.y - 0.01:
		var length := 4 if rect.end.y - z >= 4.0 else 2
		place(roof, MODULES, "%sx%dm" % [names[0], length], Transform3D(Basis.IDENTITY,
			Vector3(rect.end.x, WALL_H, z + length)))
		z += length
	place(roof, MODULES, names[1], Transform3D(Basis.IDENTITY, Vector3(rect.end.x, WALL_H, rect.position.y)))
	place(roof, MODULES, names[1], Transform3D(Basis(Vector3.UP, PI), Vector3(rect.position.x, WALL_H, rect.end.y)))


## Gravel slab with a 1 m parapet and a few machines (air conditioners, vents, a dish), seeded by salt.
static func _flat_roof(roof: Node3D, rect: Rect2, salt: String) -> void:
	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(rect.size.x + FLAT_ROOF_EAVE * 2.0, FLAT_ROOF_T, rect.size.y + FLAT_ROOF_EAVE * 2.0)
	mesh.material = ground_material(ROOF_GRAVEL, 3.0, Color(0.82, 0.8, 0.76))
	slab.mesh = mesh
	var c := rect.get_center()
	slab.position = Vector3(c.x, WALL_H + FLAT_ROOF_T * 0.5, c.y)
	roof.add_child(slab)
	var top := WALL_H + FLAT_ROOF_T
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var inward := (rect.get_center() - (a + b) * 0.5)
		inward = Vector2(signf(inward.x), 0.0) if absf(a.x - b.x) < 0.01 else Vector2(0.0, signf(inward.y))
		var dir := (b - a).normalized()
		var left := a.distance_to(b)
		var at := 0.0
		while left > 0.01:
			var length := 4 if left >= 4.0 else (2 if left >= 2.0 else 1)
			var seg := {"a": a + dir * at, "b": a + dir * (at + length), "inward": inward, "inner": false}
			var xf := _segment_xf(seg)
			xf.origin.y = top
			place(roof, MODULES, PARAPET[length], xf)
			at += length
			left -= length
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(salt)
	var taken: Array[Rect2] = []
	var area := rect.grow(-1.2)
	for attempt in 60:
		if taken.size() >= int(rect.get_area() / 40.0) + 2:
			break
		var piece: String = ROOFTOP_PROPS[rng.randi_range(0, ROOFTOP_PROPS.size() - 1)]
		var at := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var part := prop_part(piece, at, FACE_YAW.values()[rng.randi_range(0, 3)], top)
		var box: AABB = part.box
		var foot := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		if not area.encloses(foot) or taken.any(func(r: Rect2) -> bool: return r.grow(0.6).intersects(foot)):
			continue
		taken.append(foot)
		place(roof, part.folder, piece, part.xf)


## Toon ground material: a pack terrain texture projected from above in world space (ground_toon).
static func ground_material(texture_path: String, tile: float, tint := Color.WHITE) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter(&"albedo_texture", load(texture_path))
	mat.set_shader_parameter(&"tile_size", tile)
	mat.set_shader_parameter(&"albedo", tint)
	return mat


# --- runtime look --------------------------------------------------------------

## Foliage (leaves, needles, grass, ferns: the packs' double-sided toon materials) multiplied by this,
## from the packs' bright yellow-green to a deep green (user feedback 2026-11-06).
const FOLIAGE_TINT := Color(0.55, 0.68, 0.52)
## Higher than Godot's 1.0 keeps the trees' generated LODs detailed further out.
const KIT_LOD_BIAS := 3.0


## Darkens pack foliage and raises the LOD bias under root. Materials and multimesh meshes are
## copied at runtime, never saved.
static func tune_look(root: Node) -> void:
	var cache := {}
	for g: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		g.lod_bias = KIT_LOD_BIAS
		if g is MeshInstance3D:
			var mi := g as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var dark := _dark(mi.get_active_material(s), cache)
				if dark != null:
					mi.set_surface_override_material(s, dark)
		elif g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var mesh := mm.mesh
			var copy: Mesh = null
			for s in mesh.get_surface_count():
				var dark := _dark(mesh.surface_get_material(s), cache)
				if dark != null:
					if copy == null:
						copy = mesh.duplicate()
					copy.surface_set_material(s, dark)
			if copy != null:
				mm.mesh = copy


static func _dark(mat: Material, cache: Dictionary) -> Material:
	var sm := mat as ShaderMaterial
	if sm == null or sm.shader == null or not "double_sided" in sm.shader.resource_path:
		return null
	if not cache.has(sm):
		var d := sm.duplicate() as ShaderMaterial
		var albedo: Variant = sm.get_shader_parameter(&"albedo")
		var base: Color = albedo if albedo is Color else Color.WHITE
		d.set_shader_parameter(&"albedo", Color(base.r * FOLIAGE_TINT.r, base.g * FOLIAGE_TINT.g,
			base.b * FOLIAGE_TINT.b, base.a))
		cache[sm] = d
	return cache[sm]


## Puts a region's pack dressing scene (layout_builder.gd out_kit) under region, next to its layout:
## pack meshes in, greybox (group kit_greybox) out, layout skins on, foliage tuned. Does nothing
## without the private packs (CI keeps the greybox). Returns the dressing root or null.
static func attach(region: Node3D, layout: Node3D, kit_path: String) -> Node3D:
	if not available() or not ResourceLoader.exists(kit_path):
		return null
	var kit := (load(kit_path) as PackedScene).instantiate() as Node3D
	region.add_child(kit)
	tune_look(kit)
	# Layout CSG that stays (stairs, ramps) gets pack textures; Lane D's toon skin leaves ShaderMaterials.
	var skins: Dictionary = kit.get_meta(&"layout_skins", {})
	for path: NodePath in skins:
		var shape := layout.get_node_or_null(path)
		if shape != null:
			shape.set(&"material", skins[path])
	for node in layout.find_children("*", "Node3D", true, false):
		if node.is_in_group(GREYBOX_GROUP):
			node.remove_from_group(ROOF_GROUP)
			(node as Node3D).visible = false
	return kit
