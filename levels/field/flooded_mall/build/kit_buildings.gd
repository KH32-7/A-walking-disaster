extends RefCounted
## Flooded mall buildings made from the American Suburb pack (B-26), read by build_layout.gd.
## Format: field/buildings/city_kit.gd parts(). Godot metres, not map file coordinates.
##
## Each building replaces its indoor zone's outline in the map file (that file stays as confirmed):
## the kit needs axis-aligned walls on a 1 m grid and its gable roofs span 6 or 8 m, so houses are
## 8 x 12 m main blocks with a front porch (user choice 2026-11-05), inside the old outlines.
## The map file's LootSpot / RescueSpot points inside stay where they are; the plans keep them clear.
##
## Plans have their front on the east edge. mirror turns the front to the west.
## Props: [piece, x, z, face], x/z = footprint center in the plan, face = where the front looks.

const HOME := {
	"size": Vector2i(8, 12), "porch": true, "floor": "b",
	"edges": {"e": "w2 n2 e4 n2 w2", "w": "w2 n2 w4 n2 w2", "n": "w2 n4 w2", "s": "w2 n4 w2"},
	# Living room east (entrance), bedroom north-west, kitchen south-west.
	"inner": [
		[Vector2(4, 0), Vector2(4, 12), "w1 d2 w2 w2 d2 w2 w1"],
		[Vector2(0, 6), Vector2(4, 6), "w4"],
	],
	"props": [
		["bed_01", 1.6, 1.7, "e"],
		["nightstand_01", 0.5, 3.2, "e"],
		["wardrobe_01", 0.45, 4.7, "e"],
		["dresser_01", 3.58, 4.3, "w"],
		["kitchen_b_02", 0.555, 9.0, "e"],
		["fridge_01", 3.2, 11.37, "n"],
		["table_02", 2.2, 9.6, "w"],
		["chair_04", 2.2, 10.7, "n"],
		["sofa_01", 4.65, 10.4, "e"],
		["tv_chest", 7.53, 10.4, "w"],
		["armchair_01", 6.2, 11.2, "n"],
		["bookcase_01", 6.0, 0.435, "s"],
		["cardboard_box_01", 7.4, 1.2, "w"],
		["carpet_big_01", 6.0, 6.0, "s"],
		["carpet_big_02", 1.9, 3.4, "e"],
		["tv_01", 7.55, 10.4, "w", 0.67],
		["picture_01", 7.3, 0.21, "s", 1.5],
		["picture_02", 0.21, 1.1, "e", 1.6],
		["picture_03", 1.2, 11.79, "n", 1.5],
		["picture_04", 3.89, 10.5, "w", 1.5],
	],
}

## 동네 의원: waiting room and desk at the front, exam room behind a north wall.
const CLINIC := {
	"size": Vector2i(8, 12), "porch": true, "floor": "tile",
	"edges": {"e": "w2 n2 e4 n2 w2", "w": "w2 n2 w4 n2 w2", "n": "w2 n4 w2", "s": "w2 n4 w2"},
	"inner": [[Vector2(0, 4), Vector2(8, 4), "w2 w2 d2 w2"]],
	"props": [
		["bed_03", 1.33, 2.0, "e"],
		["shelf_01", 7.0, 0.51, "s"],
		["sink", 3.0, 0.515, "s"],
		["cardboard_box_02", 7.4, 3.3, "w"],
		["chair_01", 0.55, 6.0, "e"],
		["chair_01", 0.55, 6.8, "e"],
		["chair_01", 0.55, 7.6, "e"],
		["desk_01", 5.5, 9.5, "e"],
		["chair_04", 4.8, 9.5, "e"],
		["display_cabinet_01", 2.0, 11.545, "n"],
		["bookcase_02", 4.0, 11.51, "n"],
		["computer", 5.5, 9.5, "e", 0.86],
		["picture_01", 0.21, 6.8, "e", 1.6],
		["picture_04", 2.5, 4.11, "s", 1.5],
		["carpet_big_03", 4.0, 7.6, "s"],
	],
}

## 철물 창고: one open storeroom of shelves.
const HARDWARE := {
	"size": Vector2i(8, 12), "porch": true, "floor": "c",
	"edges": {"e": "w2 n2 e4 n2 w2", "w": "w4 w4 w4", "n": "w2 n4 w2", "s": "w4 w4"},
	"props": [
		["shelf_02", 0.515, 1.5, "e"],
		["shelf_02", 0.515, 3.2, "e"],
		["shelf_02", 0.515, 8.0, "e"],
		["shelf_02", 0.515, 9.7, "e"],
		["workbench", 4.0, 0.49, "s"],
		["shelf_01", 3.5, 8.5, "w"],
		["shelf_01", 4.12, 8.5, "e"],
		["store_inventory_stack_02", 6.0, 10.5, "w"],
		["cardboard_box_01", 7.2, 11.2, "w"],
		["cardboard_box_02", 6.6, 11.4, "n"],
		["store_inventory_stack_01", 2.0, 11.5, "n"],
	],
}

## 세탁소: machines and counter at the front, linen room behind a north wall.
const LAUNDRY := {
	"size": Vector2i(8, 12), "porch": true, "floor": "tile",
	"edges": {"e": "w2 n2 e4 n2 w2", "w": "w2 n2 w4 n2 w2", "n": "w2 n4 w2", "s": "w2 n4 w2"},
	"inner": [[Vector2(0, 4), Vector2(8, 4), "w2 w2 d2 w2"]],
	"props": [
		["shelf_02", 0.515, 2.0, "e"],
		["box_dirty_clothes", 3.0, 0.65, "s"],
		["cardboard_box_01", 7.0, 3.3, "w"],
		["ironing_board", 5.0, 1.5, "s"],
		["washing_machine", 0.555, 7.0, "e"],
		["washing_machine", 0.555, 7.8, "e"],
		["washing_machine", 0.555, 8.6, "e"],
		["washing_machine", 0.555, 9.4, "e"],
		["drying_machine", 1.6, 11.43, "n"],
		["drying_machine", 2.5, 11.43, "n"],
		["drying_machine", 3.4, 11.43, "n"],
		["sellers_counter", 6.5, 10.0, "w"],
		["basket_dirty_clothes", 2.0, 6.0, "e"],
		["cash_register", 6.5, 10.6, "w", 0.82],
		["picture_03", 7.0, 11.79, "n", 1.6],
		["box_dirty_clothes", 2.2, 3.2, "w"],
	],
}

## 구멍가게: one aisle, fridges, counter, stockroom behind a north wall.
const STORE := {
	"size": Vector2i(8, 12), "porch": true, "floor": "tile",
	"edges": {"e": "w2 n2 e4 n2 w2", "w": "w2 n2 w4 n2 w2", "n": "w2 n4 w2", "s": "w2 n4 w2"},
	"inner": [[Vector2(0, 3), Vector2(8, 3), "w4 d2 w2"]],
	"props": [
		["retail_shelf_01", 5.275, 5.0, "w"],
		["retail_shelf_01", 5.275, 6.26, "w"],
		["retail_shelf_01", 5.725, 5.0, "e"],
		["retail_shelf_01", 5.725, 6.26, "e"],
		["sellers_counter", 6.7, 10.5, "w"],
		["display_refrigerator_cold_drinks", 0.49, 6.0, "e"],
		["display_refrigerator_cold_drinks", 0.49, 7.4, "e"],
		["display_refrigerator_milk", 0.49, 8.8, "e"],
		["ice_cream_cooler", 2.0, 11.34, "n"],
		["store_inventory_stack_02", 1.5, 1.5, "s"],
		["cardboard_box_01", 6.5, 0.6, "s"],
		["store_inventory_stack_01", 7.4, 1.6, "w"],
		["cash_register", 6.7, 11.0, "w", 0.82],
		["picture_04", 3.0, 3.11, "s", 1.6],
	],
}

## 해솔약국: shelves along the west wall and one double row, counter by the south door,
## stockroom behind a north wall. Doors: east (main road) and south.
const PHARMACY := {
	"size": Vector2i(12, 24), "floor": "tile",
	"edges": {"e": "w4 n4 w2 n2 e4 n4 w4", "w": "w4 w4 w4 w4 w4 w4", "n": "w4 w4 w4", "s": "w2 n4 e4 w2"},
	"inner": [[Vector2(0, 6), Vector2(12, 6), "w4 d2 w2 w4"]],
	"props": [
		["shelf_02", 1.5, 0.515, "s"],
		["shelf_02", 3.2, 0.515, "s"],
		["shelf_02", 8.5, 0.515, "s"],
		["shelf_02", 10.2, 0.515, "s"],
		["cardboard_box_01", 6.0, 3.0, "w"],
		["cardboard_box_02", 6.6, 3.5, "n"],
		["store_inventory_stack_01", 11.56, 4.0, "w"],
		["shelf_01", 0.51, 8.5, "e"],
		["shelf_01", 0.51, 10.5, "e"],
		["shelf_01", 0.51, 12.5, "e"],
		["shelf_01", 0.51, 14.5, "e"],
		["shelf_01", 0.51, 16.5, "e"],
		["shelf_01", 0.51, 18.5, "e"],
		["shelf_01", 0.51, 20.5, "e"],
		["retail_shelf_03", 2.71, 11.0, "w"],
		["retail_shelf_03", 2.71, 12.24, "w"],
		["retail_shelf_03", 2.71, 13.48, "w"],
		["retail_shelf_03", 2.71, 14.72, "w"],
		["retail_shelf_03", 2.71, 15.96, "w"],
		["retail_shelf_03", 3.29, 11.0, "e"],
		["retail_shelf_03", 3.29, 12.24, "e"],
		["retail_shelf_03", 3.29, 13.48, "e"],
		["retail_shelf_03", 3.29, 14.72, "e"],
		["retail_shelf_03", 3.29, 15.96, "e"],
		["display_rack_01", 11.545, 7.5, "w"],
		["display_rack_01", 11.545, 8.5, "w"],
		["display_rack_01", 11.545, 9.5, "w"],
		["sellers_counter", 10.4, 21.0, "s"],
		["cash_register", 10.4, 21.6, "s", 0.82],
		["picture_03", 1.0, 23.79, "n", 1.7],
		["carpet_big_03", 6.5, 17.0, "s"],
	],
}

## 주유소 편의점: two double rows, fridges on the south wall, counter by the north door,
## stockroom behind a west wall. Doors: north (forecourt) and east.
const GAS_STORE := {
	"size": Vector2i(20, 14), "floor": "tile",
	"edges": {"n": "w4 n4 e4 n4 w4", "e": "w2 n4 e2 n4 w2", "s": "w4 w4 w4 w4 w4", "w": "w4 w4 w2 w4"},
	"inner": [[Vector2(4, 0), Vector2(4, 14), "w4 d2 w4 w4"]],
	"props": [
		["retail_shelf_03", 7.71, 4.0, "w"],
		["retail_shelf_03", 7.71, 5.24, "w"],
		["retail_shelf_03", 7.71, 6.48, "w"],
		["retail_shelf_03", 7.71, 7.72, "w"],
		["retail_shelf_03", 7.71, 8.96, "w"],
		["retail_shelf_03", 8.29, 4.0, "e"],
		["retail_shelf_03", 8.29, 5.24, "e"],
		["retail_shelf_03", 8.29, 6.48, "e"],
		["retail_shelf_03", 8.29, 7.72, "e"],
		["retail_shelf_03", 8.29, 8.96, "e"],
		["retail_shelf_03", 12.71, 4.0, "w"],
		["retail_shelf_03", 12.71, 5.24, "w"],
		["retail_shelf_03", 12.71, 6.48, "w"],
		["retail_shelf_03", 12.71, 7.72, "w"],
		["retail_shelf_03", 12.71, 8.96, "w"],
		["retail_shelf_03", 13.29, 4.0, "e"],
		["retail_shelf_03", 13.29, 5.24, "e"],
		["retail_shelf_03", 13.29, 6.48, "e"],
		["retail_shelf_03", 13.29, 7.72, "e"],
		["retail_shelf_03", 13.29, 8.96, "e"],
		["display_refrigerator_cold_drinks", 6.0, 13.515, "n"],
		["display_refrigerator_cold_drinks", 7.4, 13.515, "n"],
		["display_refrigerator_milk", 8.8, 13.515, "n"],
		["display_refrigerator_milk", 10.2, 13.515, "n"],
		["display_refrigerator_cold_drinks", 11.6, 13.515, "n"],
		["display_refrigerator_cold_drinks", 13.0, 13.515, "n"],
		["sellers_counter", 17.0, 2.0, "e"],
		["cash_register", 17.5, 1.6, "e", 0.82],
		["vending_machine_01", 19.43, 11.0, "w"],
		["ice_merchandiser", 19.33, 12.6, "w"],
		["soda_fountain_machine", 4.64, 10.5, "e"],
		["store_inventory_stack_02", 1.5, 2.0, "w"],
		["store_inventory_stack_01", 0.44, 9.0, "e"],
		["cardboard_box_01", 2.5, 12.5, "w"],
		["cardboard_box_02", 3.0, 13.2, "n"],
	],
}

## 정비실: workbench, shelves and a desk. Door faces the bus yard (west, mirrored).
const DEPOT_OFFICE := {
	"size": Vector2i(8, 8), "floor": "a",
	"edges": {"e": "w2 e4 w2", "w": "w2 n4 w2", "n": "w2 n4 w2", "s": "w4 w4"},
	"props": [
		["workbench", 0.49, 2.0, "e"],
		["shelf_02", 0.515, 6.0, "e"],
		["desk_01", 5.0, 0.54, "s"],
		["chair_01", 5.0, 1.3, "n"],
		["store_inventory_stack_01", 2.5, 7.56, "n"],
		["cardboard_box_01", 6.8, 7.4, "w"],
		["cardboard_box_02", 7.4, 6.6, "w"],
		["computer", 5.0, 0.5, "s", 0.86],
		["picture_02", 1.0, 0.21, "s", 1.6],
	],
}

## Indoor zone id -> [plan, spec]. Houses on the west row face east, the east row faces west,
## across the alley. Origins keep the map file's spots and doors inside and off the roads.
const BUILDINGS := {
	"house1": [HOME, {"origin": Vector2i(-41, 56), "mirror": false, "style": "a", "roof": "gable"}],
	"house2": [CLINIC, {"origin": Vector2i(-22, 57), "mirror": true, "style": "c", "roof": "gable"}],
	"house3": [HARDWARE, {"origin": Vector2i(-41, 80), "mirror": false, "style": "b", "roof": "gable"}],
	"house4": [HOME, {"origin": Vector2i(-23, 80), "mirror": true, "style": "a", "roof": "gable"}],
	"house5": [LAUNDRY, {"origin": Vector2i(-41, 98), "mirror": false, "style": "c", "roof": "gable"}],
	"house6": [STORE, {"origin": Vector2i(-22, 96), "mirror": true, "style": "b", "roof": "gable"}],
	"pharm": [PHARMACY, {"origin": Vector2i(-44, -92), "mirror": false, "style": "c", "roof": "flat"}],
	"gas_store": [GAS_STORE, {"origin": Vector2i(-40, 38), "mirror": false, "style": "a", "roof": "flat"}],
	"depot_office": [DEPOT_OFFICE, {"origin": Vector2i(38, -76), "mirror": true, "style": "b", "roof": "gable"}],
}
