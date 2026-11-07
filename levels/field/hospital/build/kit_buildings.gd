extends RefCounted
## Hospital buildings made from the American Suburb pack, read by build_layout.gd.
## Format: field/buildings/city_kit.gd parts(). Godot metres (the map file's zone outlines are these
## rects / MAP_SCALE). Plans: north is z = 0, the plan's x runs east. No mirror on this map.
## Props: [piece, x, z, face(, y)], x/z = footprint center in the plan, face = where the front looks.
## Map file markers inside a building keep 0.3 m clear of walls and props (layout_builder checks it).
## Every door is level (no steps), so a wheelchair reaches every room.

## 본관: one long east-west corridor (z 16..20) with wards and rooms on both sides, a north-south
## corridor (x 28..32) to the courtyard door. North band: ward A (nest), ward B, two isolation rooms,
## lab, staff room. South band: three clinics, the open lobby with the main entrance, pharmacy, office.
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
		[Vector2(8, 20), Vector2(8, 36), "w4 w4 w4 w4"],
		[Vector2(16, 20), Vector2(16, 36), "w4 w4 w4 w4"],
		[Vector2(22, 20), Vector2(22, 36), "w4 w4 w4 w4"],
		# Lobby to pharmacy side door.
		[Vector2(38, 20), Vector2(38, 36), "w2 d2 w4 w4 w4"],
		[Vector2(48, 20), Vector2(48, 36), "w4 w4 w4 w4"],
		[Vector2(16, 0), Vector2(16, 16), "w4 w4 w4 w4"],
		[Vector2(28, 0), Vector2(28, 16), "w4 w4 w4 w4"],
		# North isolation room opens on the north-south corridor.
		[Vector2(32, 0), Vector2(32, 16), "w2 d2 w4 w4 w4"],
		[Vector2(40, 0), Vector2(40, 16), "w4 w4 w4 w4"],
		[Vector2(50, 0), Vector2(50, 16), "w4 w4 w4 w4"],
		[Vector2(32, 8), Vector2(40, 8), "w4 w4"],
	],
	"props": [
		# Ward A (x 0..16, z 0..16): the nest room.
		["bed_02", 2.0, 1.7, "s"],
		["bed_02", 5.5, 1.7, "s"],
		["bed_02", 9.0, 1.7, "s"],
		["bed_02", 12.5, 1.7, "s"],
		["bed_02", 2.0, 14.3, "n"],
		["bed_02", 11.0, 14.3, "n"],
		["bed_02", 14.4, 14.3, "n"],
		# Ward B (x 16..28).
		["bed_03", 18.0, 1.33, "s"],
		["bed_03", 20.5, 1.33, "s"],
		["bed_03", 23.0, 1.33, "s"],
		["bed_03", 25.5, 1.33, "s"],
		["bed_03", 18.0, 14.7, "n"],
		["bed_03", 25.5, 14.7, "n"],
		["table_wheels", 31.3, 7.0, "w"],
		# Isolation rooms (x 32..40).
		["bed_03", 38.77, 2.0, "w"],
		["bed_03", 38.77, 11.0, "w"],
		# Lab (x 40..50).
		["workbench", 45.0, 0.49, "s"],
		["desk_01", 49.56, 4.0, "w"],
		["desk_01", 49.56, 7.0, "w"],
		["computer", 49.56, 4.0, "w", 0.86],
		["shelf_01", 40.41, 3.0, "e"],
		["shelf_01", 40.41, 5.0, "e"],
		# Staff room (x 50..60).
		["sofa_01", 59.25, 6.0, "w"],
		["table_02", 56.0, 6.0, "w"],
		["fridge_01", 52.0, 0.73, "s"],
		["locker", 50.27, 9.0, "e"],
		["locker", 50.27, 10.0, "e"],
		["locker", 50.27, 11.0, "e"],
		# Corridor: gurneys left against the walls.
		["table_wheels", 12.0, 16.62, "s"],
		["table_wheels", 48.0, 16.62, "s"],
		["table_wheels", 26.0, 19.38, "n"],
		# Clinics 1 to 3 (z 20..36).
		["desk_01", 0.54, 30.0, "e"],
		["bed_03", 5.0, 34.67, "n"],
		["display_cabinet_01", 7.645, 25.0, "w"],
		["desk_01", 8.44, 30.0, "e"],
		["bed_03", 13.0, 34.67, "n"],
		["desk_01", 16.44, 30.0, "e"],
		["bookcase_01", 21.665, 32.0, "w"],
		# Lobby (x 22..38): reception, waiting chairs, vending machines.
		["sellers_counter", 34.0, 26.0, "w"],
		["office_computer", 34.0, 25.5, "w", 0.81],
		["chair_01", 24.5, 29.0, "s"],
		["chair_01", 25.3, 29.0, "s"],
		["chair_01", 26.1, 29.0, "s"],
		["chair_01", 24.5, 31.0, "s"],
		["chair_01", 25.3, 31.0, "s"],
		["chair_01", 26.1, 31.0, "s"],
		["vending_machine_01", 36.5, 35.43, "n"],
		["vending_machine_01", 23.5, 35.43, "n"],
		# Pharmacy (x 38..48).
		["shelf_02", 47.585, 23.0, "w"],
		["shelf_02", 47.585, 25.0, "w"],
		["shelf_02", 47.585, 27.0, "w"],
		["shelf_02", 47.585, 29.0, "w"],
		["shelf_02", 47.585, 31.0, "w"],
		["shelf_01", 40.0, 35.49, "n"],
		["shelf_01", 42.0, 35.49, "n"],
		["shelf_01", 44.0, 35.49, "n"],
		["shelf_01", 46.0, 35.49, "n"],
		["display_cabinet_01", 38.355, 30.0, "e"],
		# Office (x 48..60).
		["filing_cabinet_a_01", 59.535, 22.5, "w"],
		["filing_cabinet_a_01", 59.535, 23.05, "w"],
		["filing_cabinet_a_01", 59.535, 23.6, "w"],
		["desk_01", 52.0, 28.0, "s"],
		["desk_01", 56.0, 28.0, "s"],
		["office_chair_01", 52.0, 29.0, "n"],
		["office_chair_01", 56.0, 29.0, "n"],
		["locker", 49.0, 35.635, "n"],
		["locker", 49.9, 35.635, "n"],
		["locker", 50.8, 35.635, "n"],
	],
}

## 응급실: treatment hall (x 10..22) behind the ambulance door (east), resuscitation and supply rooms
## and the waiting room (west door, across the walkway from the main building's east door).
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
		["display_cabinet_01", 21.545, 5.5, "w"],
		# Resuscitation (x 0..10, z 0..10).
		["bed_02", 5.0, 1.66, "s"],
		["display_cabinet_01", 0.455, 6.0, "e"],
		# Supply room (z 10..18).
		["shelf_02", 0.515, 12.0, "e"],
		["shelf_02", 0.515, 14.0, "e"],
		["shelf_02", 0.515, 16.0, "e"],
		["shelf_01", 3.0, 10.41, "s"],
		["shelf_01", 5.0, 10.41, "s"],
		["shelf_01", 7.0, 10.41, "s"],
		# Waiting room (z 18..28).
		["chair_01", 3.0, 23.5, "e"],
		["chair_01", 3.0, 24.2, "e"],
		["chair_01", 3.0, 24.9, "e"],
		["chair_01", 5.0, 23.5, "e"],
		["chair_01", 5.0, 24.2, "e"],
		["chair_01", 5.0, 24.9, "e"],
		["vending_machine_01", 0.57, 26.5, "e"],
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
		["shelf_01", 0.51, 4.0, "e"],
		["shelf_01", 0.51, 16.0, "e"],
		["display_cabinet_01", 31.545, 4.0, "w"],
		["display_cabinet_01", 31.545, 16.0, "w"],
		# Scrub corridor.
		["locker", 2.0, 27.635, "n"],
		["locker", 2.9, 27.635, "n"],
		["locker", 3.8, 27.635, "n"],
		["locker", 4.7, 27.635, "n"],
		["locker", 27.3, 27.635, "n"],
		["locker", 28.2, 27.635, "n"],
		["locker", 29.1, 27.635, "n"],
		["locker", 30.0, 27.635, "n"],
		["sink", 9.0, 27.485, "n"],
		["sink", 10.2, 27.485, "n"],
	],
}

## 영안실: cold lockers on the north wall, trolleys. Door south to the back yard.
const MORGUE := {
	"size": Vector2i(16, 12), "floor": "c",
	"edges": {"n": "w2 n4 w4 n4 w2", "s": "w4 w2 e4 w2 w4", "w": "w4 w4 w4", "e": "w4 w4 w4"},
	"props": [
		["locker", 1.0, 0.365, "s"],
		["locker", 1.9, 0.365, "s"],
		["locker", 2.8, 0.365, "s"],
		["locker", 3.7, 0.365, "s"],
		["locker", 4.6, 0.365, "s"],
		["locker", 11.4, 0.365, "s"],
		["locker", 12.3, 0.365, "s"],
		["locker", 13.2, 0.365, "s"],
		["locker", 14.1, 0.365, "s"],
		["locker", 15.0, 0.365, "s"],
		["table_wheels", 4.0, 6.0, "w"],
		["table_wheels", 12.0, 6.0, "w"],
		["table_wheels", 8.0, 3.5, "n"],
	],
}

## 보일러실: workbench and spare parts. Door west, next to the generator extract.
const BOILER := {
	"size": Vector2i(12, 12), "floor": "c",
	"edges": {"w": "w4 e4 w4", "n": "w4 w4 w4", "s": "w2 n4 w4 w2", "e": "w4 w4 w4"},
	"props": [
		["workbench", 6.0, 11.51, "n"],
		["shelf_02", 11.485, 3.0, "w"],
		["shelf_02", 11.485, 5.0, "w"],
		["store_inventory_stack_02", 3.0, 2.0, "s"],
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
		["shelf_02", 19.485, 20.0, "w"],
		["shelf_02", 19.485, 22.0, "w"],
		["shelf_02", 19.485, 24.0, "w"],
		["store_inventory_stack_01", 0.44, 22.0, "e"],
		["cardboard_box_01", 3.0, 26.5, "n"],
	],
}

## 정문 경비실.
const GUARD := {
	"size": Vector2i(6, 6), "floor": "a",
	"edges": {"n": "w2 n2 w2", "s": "w2 e2 w2", "w": "w2 n2 w2", "e": "w2 w2 w2"},
	"props": [["desk_01", 0.54, 2.0, "e"], ["chair_01", 1.5, 2.0, "w"]],
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
