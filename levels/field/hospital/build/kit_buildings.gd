extends RefCounted
## Hospital buildings made from the American Suburb pack, read by build_layout.gd.
## Format: field/buildings/city_kit.gd parts(). Godot metres (the map file's zone outlines are these
## rects / MAP_SCALE). Plans: north is z = 0, the plan's x runs east. No mirror on this map.
## Props: [piece, x, z, face(, y)], x/z = footprint center in the plan, face = where the front looks.
## Loot: [piece, x, z, face, container kind, loot table] = furniture that is a container (always there,
## sometimes empty). What a room holds follows what the room was (user request 2026-11-07: dense rooms
## and reasons to search them, like Project Zomboid): pharmacy shelves hold medicine, staff lockers
## clothes and food, office cabinets keys, the security cabinets guns and ammo.
## Map file markers inside a building keep 0.3 m clear of walls and props (layout_builder checks it).
## Every door is level (no steps), so a wheelchair reaches every room.

## Room loot tables (data/loot/tables/hospital_<room>.tres).
const WARD := "hospital_ward_cabinet"
const WARD_LOCKER := "hospital_ward_locker"
const PHARMACY := "hospital_pharmacy"
const ER_SUPPLY := "hospital_er_supply"
const SURGERY_CAB := "hospital_surgery"
const STAFF := "hospital_staff_locker"
const FOOD := "hospital_food"
const OFFICE := "hospital_office"
const LAB := "hospital_lab"
const SECURITY := "hospital_security"
const STASH := "hospital_survivor_stash"
const MORGUE_LOCKER := "hospital_morgue"
const BOILER_ROOM := "hospital_boiler"
const STOREROOM := "hospital_storeroom"

## 본관: one long east-west corridor (z 16..20) with wards and rooms on both sides, a north-south
## corridor (x 28..32) to the courtyard door. North band: ward A (nest), ward B, two isolation rooms,
## lab, staff room (the last survivors' holdout). South band: three clinics, the lobby turned field
## hospital, pharmacy, office.
## Routes: the survivors barricaded the corridor twice, at ward A (x 16.5..19.5, against the nest) and
## at the lab (x 40..43). The west wing is reached through the clinics (they open into each other),
## ward A's door to ward B or the west door; the east wing through the pharmacy (lobby side door, then
## the office door) or the east door.
const MAIN := {
	"size": Vector2i(60, 36), "floor": "tile",
	"edges": {
		"n": "w2 n4 w4 n4 w2 w2 n4 w2 n2 w2 e4 w2 n4 w2 w2 n2 w2 n2 w2 w2 n2 w2 n2 w2",
		"s": "w2 n4 w2 w2 n4 w2 w2 n2 w2 w2 n4 e4 n4 w2 w2 n2 w2 n2 w2 w2 n4 w2 n2 w2",
		"w": "w2 n4 w4 n4 w2 e4 w2 n4 w4 n4 w2",
		"e": "w2 n4 w4 n4 w2 e4 w2 n4 w4 n4 w2",
	},
	"inner": [
		# Corridor walls. North: ward A, ward B, the north-south corridor (open), isolation, lab, staff.
		[Vector2(0, 16), Vector2(60, 16), "w4 w2 d2 w4 w4 w4 d2 w4 w2 x4 w2 d2 w4 w4 d2 w4 w4 d2 w4"],
		# South: clinics 1 to 3, the lobby (open), pharmacy, office.
		[Vector2(0, 20), Vector2(60, 20), "w2 d2 w4 w2 d2 w4 w2 d2 w2 x16 w4 d2 w4 w4 d2 w4 w2"],
		# Clinics open into each other (z 24..26).
		[Vector2(8, 20), Vector2(8, 36), "w4 d2 w4 w4 w2"],
		[Vector2(16, 20), Vector2(16, 36), "w4 d2 w4 w4 w2"],
		[Vector2(22, 20), Vector2(22, 36), "w4 w4 w4 w4"],
		# Lobby to pharmacy side door, pharmacy to office door.
		[Vector2(38, 20), Vector2(38, 36), "w2 d2 w4 w4 w4"],
		[Vector2(48, 20), Vector2(48, 36), "w4 w4 d2 w4 w2"],
		# Ward A to ward B (z 8..10), lab to staff room (z 8..10).
		[Vector2(16, 0), Vector2(16, 16), "w4 w4 d2 w4 w2"],
		[Vector2(28, 0), Vector2(28, 16), "w4 w4 w4 w4"],
		# North isolation room opens on the north-south corridor.
		[Vector2(32, 0), Vector2(32, 16), "w2 d2 w4 w4 w4"],
		[Vector2(40, 0), Vector2(40, 16), "w4 w4 w4 w4"],
		[Vector2(50, 0), Vector2(50, 16), "w4 w4 d2 w4 w2"],
		[Vector2(32, 8), Vector2(40, 8), "w4 w4"],
	],
	"props": [
		# Ward A (x 0..16, z 0..16): the nest room. Beds left where they were.
		["bed_02", 2.0, 1.7, "s"],
		["bed_02", 5.5, 1.7, "s"],
		["bed_02", 9.0, 1.7, "s"],
		["bed_02", 12.5, 1.7, "s"],
		["bed_02", 2.0, 14.3, "n"],
		["bed_02", 11.0, 14.3, "n"],
		["bed_02", 14.4, 14.3, "n"],
		["bathroom_cabinet", 0.32, 11.5, "e"],
		["table_wheels", 10.5, 10.0, "n"],
		["chair_03", 4.0, 6.0, "e"],
		# Ward B (x 16..28).
		["bed_03", 18.0, 1.33, "s"],
		["bed_03", 20.5, 1.33, "s"],
		["bed_03", 23.0, 1.33, "s"],
		["bed_03", 25.5, 1.33, "s"],
		["bed_03", 18.0, 14.7, "n"],
		["bed_03", 25.5, 14.7, "n"],
		["chair_03", 19.5, 4.2, "n"],
		["chair_03", 24.5, 4.2, "n"],
		["table_wheels", 24.0, 10.5, "w"],
		# North-south corridor.
		["table_wheels", 31.3, 7.0, "w"],
		["water_cooler", 28.3, 13.0, "e"],
		# Isolation rooms (x 32..40).
		["bed_03", 38.77, 2.0, "w"],
		["bed_03", 38.77, 11.0, "w"],
		["chair_03", 34.5, 12.5, "e"],
		# Lab (x 40..50): benches, a printer, the centre bench.
		["desk_01", 49.56, 4.0, "w"],
		["desk_01", 49.56, 13.0, "w"],
		["computer", 49.56, 4.0, "w", 0.86],
		["computer", 49.56, 13.0, "w", 0.86],
		["office_chair_01", 48.7, 4.0, "e"],
		["table_01", 44.5, 8.0, "w"],
		["computer", 44.5, 7.3, "w", 0.91],
		["folders_01", 44.5, 9.0, "w", 0.91],
		["printer_big", 47.0, 0.545, "s"],
		# Staff room (x 50..60): the last survivors' holdout. Sofas for beds, a radio, a camp.
		["sofa_01", 59.25, 6.0, "w"],
		["sofa_02", 51.0, 5.0, "e"],
		["table_02", 56.0, 6.0, "w"],
		["handheld_radio", 56.0, 6.0, "w", 0.84],
		["kitchen_island_01", 56.5, 11.0, "s"],
		["cooler_box_water", 58.6, 13.5, "w"],
		["portable_power_station", 52.0, 12.5, "e"],
		["rolled_sleeping_bag", 53.5, 9.0, "e"],
		# Corridor: gurneys against the walls and the two barricades (a bed and a gurney across).
		["table_wheels", 12.0, 16.62, "s"],
		["table_wheels", 48.0, 16.62, "s"],
		["table_wheels", 26.0, 19.38, "n"],
		["bed_02", 18.0, 17.4, "w"],
		["table_wheels", 17.4, 19.1, "e"],
		["bed_02", 41.5, 17.4, "w"],
		["table_wheels", 40.9, 19.1, "e"],
		# Clinics 1 to 3 (z 20..36).
		["desk_01", 0.54, 30.0, "e"],
		["office_chair_01", 1.5, 30.0, "w"],
		["bed_03", 5.0, 34.67, "n"],
		["sink", 4.5, 20.575, "s"],
		["desk_01", 8.44, 30.0, "e"],
		["office_chair_01", 9.4, 30.0, "w"],
		["bed_03", 13.0, 34.67, "n"],
		["desk_01", 16.44, 30.0, "e"],
		["office_chair_01", 17.4, 30.0, "w"],
		["bed_03", 19.5, 34.67, "n"],
		["bookcase_01", 21.665, 32.0, "w"],
		["computer", 0.54, 30.0, "e", 0.86],
		["computer", 16.44, 30.0, "e", 0.86],
		# Lobby (x 22..38): reception, waiting chairs, field-hospital cots, the lane x 27..33 clear.
		["office_computer", 34.0, 25.5, "w", 0.81],
		["office_telephone", 34.2, 26.6, "w", 0.81],
		["chair_01", 24.5, 29.0, "s"],
		["chair_01", 25.3, 29.0, "s"],
		["chair_01", 26.1, 29.0, "s"],
		["chair_01", 24.5, 31.0, "s"],
		["chair_01", 25.3, 31.0, "s"],
		["chair_01", 26.1, 31.0, "s"],
		["military_folding_cot", 25.6, 33.6, "w"],
		["military_folding_cot", 25.4, 21.2, "w"],
		["military_folding_cot", 25.4, 26.0, "w"],
		["military_folding_cot", 35.5, 31.6, "w"],
		["military_folding_cot", 35.5, 33.0, "w"],
		["military_folding_cot", 35.5, 34.4, "w"],
		["military_folding_table", 23.0, 24.5, "e"],
		["cardboard_box_01", 23.0, 22.4, "e"],
		["military_duffel_bag", 24.0, 27.6, "w"],
		["bench", 22.4, 30.2, "e"],
		["bench", 22.4, 31.7, "e"],
		["water_cooler", 36.5, 21.0, "w"],
		# Pharmacy (x 38..48): a double row of shelves in the middle, the counter by the cabinets.
		["retail_shelf_03", 42.71, 26.5, "w"],
		["retail_shelf_03", 42.71, 27.74, "w"],
		["retail_shelf_03", 42.71, 28.98, "w"],
		["retail_shelf_03", 43.29, 26.5, "e"],
		["retail_shelf_03", 43.29, 27.74, "e"],
		["retail_shelf_03", 43.29, 28.98, "e"],
		["sellers_counter", 40.5, 33.0, "s"],
		["cash_register", 40.8, 33.3, "s", 0.82],
		# Office (x 48..60).
		["desk_01", 52.0, 28.0, "s"],
		["desk_01", 56.0, 28.0, "s"],
		["office_chair_01", 52.0, 29.0, "n"],
		["office_chair_01", 56.0, 29.0, "n"],
		["office_computer", 52.0, 27.9, "n", 0.86],
		["documents_01", 56.0, 28.0, "n", 0.86],
		["printer_big", 57.5, 35.455, "n"],
		["water_cooler", 59.6, 30.0, "w"],
		["office_urn", 49.5, 21.0, "e"],
	],
	"loot": [
		# Ward A: bedside cabinets between the beds, a wardrobe of patients' things.
		["nightstand_02", 3.75, 0.505, "s", "DRAWER", WARD],
		["nightstand_02", 7.25, 0.505, "s", "DRAWER", WARD],
		["nightstand_02", 10.75, 0.505, "s", "DRAWER", WARD],
		["wardrobe_02", 0.405, 7.0, "e", "DRAWER", WARD_LOCKER],
		# Ward B.
		["nightstand_03", 19.25, 0.51, "s", "DRAWER", WARD],
		["nightstand_03", 21.75, 0.51, "s", "DRAWER", WARD],
		["nightstand_03", 24.25, 0.51, "s", "DRAWER", WARD],
		["dresser_02", 27.64, 6.5, "w", "DRAWER", WARD_LOCKER],
		# Isolation rooms.
		["nightstand_02", 39.645, 4.5, "w", "DRAWER", WARD],
		["nightstand_02", 39.645, 13.5, "w", "DRAWER", WARD],
		# Lab: the workbench, shelves and filing cabinets.
		["workbench", 45.0, 0.49, "s", "TOOLBOX", LAB],
		["shelf_01", 40.41, 3.0, "e", "TOOLBOX", LAB],
		["shelf_01", 40.41, 5.0, "e", "TOOLBOX", LAB],
		["filing_cabinet_a_01", 41.5, 15.635, "n", "DRAWER", OFFICE],
		["filing_cabinet_a_01", 42.1, 15.635, "n", "DRAWER", OFFICE],
		# Staff room: lockers, the fridge, the survivors' bags.
		["locker", 54.0, 0.365, "s", "DRAWER", STAFF],
		["locker", 54.9, 0.365, "s", "DRAWER", STAFF],
		["locker", 55.8, 0.365, "s", "DRAWER", STAFF],
		["locker", 56.7, 0.365, "s", "DRAWER", STAFF],
		["fridge_01", 52.0, 0.73, "s", "DRAWER", FOOD],
		["hiking_backpack", 53.5, 11.0, "e", "DRAWER", STASH],
		["military_duffel_bag", 58.6, 11.8, "w", "DRAWER", STASH],
		# Clinics: medicine cabinets and record cabinets.
		["display_cabinet_01", 7.645, 31.0, "w", "MEDICINE", PHARMACY],
		["filing_cabinet_b_01", 0.44, 27.0, "e", "DRAWER", OFFICE],
		["display_cabinet_01", 15.645, 31.0, "w", "MEDICINE", PHARMACY],
		["filing_cabinet_b_01", 21.66, 22.5, "w", "DRAWER", OFFICE],
		# Lobby: the reception desk and the vending machines.
		["sellers_counter", 34.0, 26.0, "w", "DRAWER", OFFICE],
		["vending_machine_01", 36.5, 35.43, "n", "DRAWER", FOOD],
		["vending_machine_01", 23.5, 35.43, "n", "DRAWER", FOOD],
		# Pharmacy: wall shelves and cabinets, all medicine.
		["shelf_02", 47.585, 23.0, "w", "MEDICINE", PHARMACY],
		["shelf_02", 47.585, 25.0, "w", "MEDICINE", PHARMACY],
		["shelf_02", 47.585, 32.5, "w", "MEDICINE", PHARMACY],
		["shelf_01", 40.0, 35.49, "n", "MEDICINE", PHARMACY],
		["shelf_01", 44.0, 35.49, "n", "MEDICINE", PHARMACY],
		["shelf_01", 46.0, 35.49, "n", "MEDICINE", PHARMACY],
		["display_cabinet_01", 38.355, 29.0, "e", "MEDICINE", PHARMACY],
		["display_cabinet_01", 38.355, 30.3, "e", "MEDICINE", PHARMACY],
		# Office: filing cabinets (keys), staff lockers, the security cabinet.
		["filing_cabinet_a_01", 59.535, 22.5, "w", "DRAWER", OFFICE],
		["filing_cabinet_a_01", 59.535, 23.05, "w", "DRAWER", OFFICE],
		["filing_cabinet_a_01", 59.535, 23.6, "w", "DRAWER", OFFICE],
		["filing_cabinet_a_01", 59.535, 26.0, "w", "DRAWER", OFFICE],
		["locker", 49.0, 35.635, "n", "DRAWER", STAFF],
		["locker", 49.9, 35.635, "n", "DRAWER", STAFF],
		["locker", 50.8, 35.635, "n", "DRAWER", STAFF],
		["armory_cabinet_01", 59.58, 33.0, "w", "DRAWER", SECURITY],
	],
}

## 응급실: treatment hall (x 10..22) behind the ambulance door (east), resuscitation and supply rooms
## and the waiting room (west door, across the walkway from the main building's east door). The police
## who guarded it left their weapons cabinet in the waiting room.
const ER := {
	"size": Vector2i(22, 28), "floor": "tile",
	"edges": {
		"n": "w2 n4 w4 n4 w4 n2 w2",
		"s": "w2 n4 w4 n4 w4 n2 w2",
		"w": "w2 n4 w4 w2 n4 w2 e4 w2 n2 w2",
		"e": "w2 n4 w4 e4 w4 n4 w2 w4",
	},
	"inner": [
		[Vector2(10, 0), Vector2(10, 28), "w4 d2 w4 w2 d2 w4 x4 w4 w2"],
		[Vector2(0, 10), Vector2(10, 10), "w4 w4 w2"],
		[Vector2(0, 18), Vector2(10, 18), "w4 w4 w2"],
	],
	"props": [
		["bed_03", 12.5, 1.33, "s"],
		["bed_03", 15.0, 1.33, "s"],
		["bed_03", 17.5, 1.33, "s"],
		["bed_03", 20.0, 1.33, "s"],
		["bed_03", 13.0, 26.67, "n"],
		["bed_03", 16.0, 26.67, "n"],
		["bed_03", 19.0, 26.67, "n"],
		["table_wheels", 14.0, 13.0, "w"],
		["table_wheels", 16.5, 20.0, "n"],
		["table_wheels", 18.5, 8.5, "e"],
		["chair_03", 12.0, 21.5, "e"],
		# Resuscitation (x 0..10, z 0..10).
		["bed_02", 5.0, 1.66, "s"],
		["table_wheels", 8.5, 6.5, "n"],
		# Waiting room (z 18..28).
		["chair_01", 3.0, 23.5, "e"],
		["chair_01", 3.0, 24.2, "e"],
		["chair_01", 3.0, 24.9, "e"],
		["chair_01", 5.0, 23.5, "e"],
		["chair_01", 5.0, 24.2, "e"],
		["chair_01", 5.0, 24.9, "e"],
		["water_cooler", 5.5, 27.6, "n"],
	],
	"loot": [
		["nightstand_03", 13.75, 0.51, "s", "DRAWER", WARD],
		["nightstand_03", 16.25, 0.51, "s", "DRAWER", WARD],
		["nightstand_03", 18.75, 0.51, "s", "DRAWER", WARD],
		["display_cabinet_01", 21.545, 5.5, "w", "MEDICINE", ER_SUPPLY],
		["display_cabinet_01", 21.545, 17.0, "w", "MEDICINE", ER_SUPPLY],
		["display_cabinet_01", 0.455, 6.0, "e", "MEDICINE", ER_SUPPLY],
		# Supply room: shelves on two walls.
		["shelf_02", 0.515, 12.0, "e", "MEDICINE", ER_SUPPLY],
		["shelf_02", 0.515, 14.0, "e", "MEDICINE", ER_SUPPLY],
		["shelf_02", 0.515, 16.0, "e", "MEDICINE", ER_SUPPLY],
		["shelf_01", 3.0, 10.41, "s", "MEDICINE", ER_SUPPLY],
		["shelf_01", 5.0, 10.41, "s", "MEDICINE", ER_SUPPLY],
		["shelf_01", 7.0, 10.41, "s", "MEDICINE", ER_SUPPLY],
		["vending_machine_01", 0.57, 26.5, "e", "DRAWER", FOOD],
		["armory_cabinet_02", 8.0, 27.36, "n", "DRAWER", SECURITY],
	],
}

## 수술동: the main operating theatre (x 0..32, z 0..20, the boss arena) and the scrub corridor
## (z 20..28) behind a double door. South door to the courtyard, north door to the back yard.
const SURGERY := {
	"size": Vector2i(32, 28), "floor": "tile",
	"edges": {
		"n": "w2 n4 w4 w4 w4 n4 w4 e4 w2",
		"s": "w2 n4 w4 w2 w2 e4 w2 w2 w4 n4 w2",
		"w": "w4 n4 w4 n4 w4 w4 w4",
		"e": "w4 n4 w4 n4 w4 w4 w4",
	},
	"inner": [[Vector2(0, 20), Vector2(32, 20), "w4 w4 w4 w2 d4 w2 w4 w4 w4"]],
	"props": [
		# Operating tables round the middle, which stays clear for the fight.
		["bed_03", 7.0, 6.0, "w"],
		["bed_03", 25.0, 6.0, "w"],
		["bed_03", 7.0, 14.0, "w"],
		["bed_03", 25.0, 14.0, "w"],
		["table_wheels", 12.0, 3.5, "n"],
		["table_wheels", 20.0, 16.5, "n"],
		["table_wheels", 3.5, 10.0, "w"],
		["table_wheels", 28.5, 10.0, "e"],
		["console_table_01", 16.0, 0.57, "s"],
		# Scrub corridor.
		["locker", 3.8, 27.635, "n"],
		["locker", 4.7, 27.635, "n"],
		["locker", 29.1, 27.635, "n"],
		["locker", 30.0, 27.635, "n"],
		["sink", 9.0, 27.485, "n"],
		["sink", 10.2, 27.485, "n"],
		["sink", 21.8, 27.485, "n"],
		["sink", 23.0, 27.485, "n"],
		["bench", 16.0, 22.5, "s"],
	],
	"loot": [
		["shelf_01", 0.51, 4.0, "e", "MEDICINE", SURGERY_CAB],
		["shelf_01", 0.51, 16.0, "e", "MEDICINE", SURGERY_CAB],
		["display_cabinet_01", 31.545, 4.0, "w", "MEDICINE", SURGERY_CAB],
		["display_cabinet_01", 31.545, 16.0, "w", "MEDICINE", SURGERY_CAB],
		["locker", 2.0, 27.635, "n", "DRAWER", STAFF],
		["locker", 2.9, 27.635, "n", "DRAWER", STAFF],
		["locker", 27.3, 27.635, "n", "DRAWER", STAFF],
		["locker", 28.2, 27.635, "n", "DRAWER", STAFF],
	],
}

## 영안실: cold lockers on the north wall (some still hold people's things), trolleys.
const MORGUE := {
	"size": Vector2i(16, 12), "floor": "c",
	"edges": {"n": "w2 n4 w4 n4 w2", "s": "w4 w2 e4 w2 w4", "w": "w4 w4 w4", "e": "w4 w4 w4"},
	"props": [
		["locker", 1.9, 0.365, "s"],
		["locker", 3.7, 0.365, "s"],
		["locker", 12.3, 0.365, "s"],
		["locker", 14.1, 0.365, "s"],
		["table_wheels", 4.0, 6.0, "w"],
		["table_wheels", 12.0, 6.0, "w"],
		["table_wheels", 8.0, 3.5, "n"],
		["sink", 0.515, 9.5, "e"],
		["filing_cabinet_a_02", 15.535, 10.0, "w"],
	],
	"loot": [
		["locker", 1.0, 0.365, "s", "DRAWER", MORGUE_LOCKER],
		["locker", 2.8, 0.365, "s", "DRAWER", MORGUE_LOCKER],
		["locker", 4.6, 0.365, "s", "DRAWER", MORGUE_LOCKER],
		["locker", 11.4, 0.365, "s", "DRAWER", MORGUE_LOCKER],
		["locker", 13.2, 0.365, "s", "DRAWER", MORGUE_LOCKER],
		["locker", 15.0, 0.365, "s", "DRAWER", MORGUE_LOCKER],
		["desk_01", 15.46, 6.5, "w", "DRAWER", OFFICE],
	],
}

## 보일러실: workbench and spare parts. Door west, next to the generator extract.
const BOILER := {
	"size": Vector2i(12, 12), "floor": "c",
	"edges": {"w": "w4 e4 w4", "n": "w4 w4 w4", "s": "w2 n4 w4 w2", "e": "w4 w4 w4"},
	"props": [
		["store_inventory_stack_02", 3.0, 2.0, "s"],
		["tool_cabinet", 0.465, 10.5, "e"],
		["barrel_01", 10.5, 10.5, "w"],
		["barrel_02", 9.6, 10.9, "w"],
	],
	"loot": [
		["workbench", 6.0, 11.51, "n", "TOOLBOX", BOILER_ROOM],
		["shelf_02", 11.485, 3.0, "w", "TOOLBOX", BOILER_ROOM],
		["shelf_02", 11.485, 5.0, "w", "TOOLBOX", BOILER_ROOM],
		["tool_box", 6.0, 0.6, "s", "TOOLBOX", BOILER_ROOM],
	],
}

## 별관 (재활 병동): rehab ward north, storeroom south. Doors west (road) and east (garden).
const ANNEX := {
	"size": Vector2i(20, 28), "floor": "b",
	"edges": {
		"w": "w4 n4 w2 e4 w2 n4 w4 w4",
		"e": "w4 n4 w4 w2 e4 w2 n4 w4",
		"n": "w2 n4 w2 w2 n4 w4 w2",
		"s": "w2 n4 w2 w2 n4 w4 w2",
	},
	"inner": [[Vector2(0, 14), Vector2(20, 14), "w4 w4 d2 w4 w4 w2"]],
	"props": [
		["bed_03", 3.0, 1.33, "s"],
		["bed_03", 6.0, 1.33, "s"],
		["bed_03", 9.0, 1.33, "s"],
		["bed_03", 12.0, 1.33, "s"],
		["table_02", 15.0, 8.0, "w"],
		["chair_03", 15.0, 9.2, "n"],
		["armchair_02", 3.0, 11.0, "n"],
		["tv_chest", 0.47, 7.0, "e"],
		["store_inventory_stack_01", 0.44, 22.0, "e"],
		["cardboard_box_01", 3.0, 26.5, "n"],
		["cardboard_box_02", 4.2, 26.6, "n"],
	],
	"loot": [
		["nightstand_03", 4.5, 0.51, "s", "DRAWER", WARD],
		["nightstand_03", 7.5, 0.51, "s", "DRAWER", WARD],
		["nightstand_03", 10.5, 0.51, "s", "DRAWER", WARD],
		["shelf_02", 19.485, 20.0, "w", "DRAWER", STOREROOM],
		["shelf_02", 19.485, 22.0, "w", "DRAWER", STOREROOM],
		["shelf_02", 19.485, 24.0, "w", "DRAWER", STOREROOM],
		["shelf_01", 8.0, 27.49, "n", "DRAWER", STOREROOM],
	],
}

## 정문 경비실: the gate guards' desk and their gun cabinet.
const GUARD := {
	"size": Vector2i(6, 6), "floor": "a",
	"edges": {"n": "w2 n2 w2", "s": "w2 e2 w2", "w": "w2 n2 w2", "e": "w2 w2 w2"},
	"props": [["chair_01", 1.5, 2.0, "w"]],
	"loot": [
		["desk_01", 0.54, 2.0, "e", "DRAWER", OFFICE],
		["armory_cabinet_01", 5.58, 2.0, "w", "DRAWER", SECURITY],
	],
}

## Indoor zone id -> [plan, spec].
const BUILDINGS := {
	"main_in": [MAIN, {"origin": Vector2i(-30, -4), "mirror": false, "style": "b", "roof": "flat"}],
	"er_in": [ER, {"origin": Vector2i(38, -6), "mirror": false, "style": "b", "roof": "flat"}],
	"surg_in": [SURGERY, {"origin": Vector2i(-16, -52), "mirror": false, "style": "b", "roof": "flat"}],
	"morgue_in": [MORGUE, {"origin": Vector2i(-60, -84), "mirror": false, "style": "c", "roof": "flat"}],
	"boiler_in": [BOILER, {"origin": Vector2i(58, -88), "mirror": false, "style": "c", "roof": "flat"}],
	"annex_in": [ANNEX, {"origin": Vector2i(-92, -40), "mirror": false, "style": "b", "roof": "flat"}],
	"guard_in": [GUARD, {"origin": Vector2i(8, 86), "mirror": false, "style": "a", "roof": "flat"}],
}
