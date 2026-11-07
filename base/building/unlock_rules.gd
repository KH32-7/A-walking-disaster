class_name UnlockRules
extends RefCounted
## Onboarding unlocks (docs/design/12-progression-balance.md "해금 순서", 사용자 요청 2026-11-07):
## base menus and buildings open a few at a time instead of all at once after the tutorial.
## Buildings use BuildingDef.unlock_flag / tier_min (Colony.is_unlocked); the menus are here.
## take_new_unlocks() reports what opened since the last call, once, for one notification.

## Set when the tutorial ends (IntroTutorial.FLAG_DONE): the first rescue stage.
const FIRST_RESCUE_FLAG := &"tutorial_done"
## GameState flag holding the names already announced (Array[String], JSON-safe).
const SEEN_FLAG := &"unlocks_seen"
## Base menu id -> condition key. Menus not listed are open from the start.
const MENU_RULES := {
	&"residents": &"first_rescue",
	&"armory": &"first_rescue",
	&"craft": &"craft_building",
	&"journal": &"day_2",
	&"outposts": &"settlement",
}
## Buildings that open the 제작 menu once one of them is finished.
const CRAFT_BUILDINGS: Array[StringName] = [&"workshop", &"sewing_room"]
## Menu id -> name in the notification.
const MENU_NAMES := {&"residents": "주민", &"armory": "무기고", &"craft": "제작", &"journal": "일지",
	&"outposts": "전초기지"}
## Building names listed in the notification before "외 N개".
const NOTE_NAMES_MAX := 4


static func menu_open(menu_id: StringName) -> bool:
	match MENU_RULES.get(menu_id, &""):
		&"first_rescue":
			return GameState.has_flag(FIRST_RESCUE_FLAG)
		&"craft_building":
			return CRAFT_BUILDINGS.any(func(id: StringName) -> bool: return Colony.has_completed(id))
		&"day_2":
			return GameState.day >= 2
		&"settlement":
			return Colony.tier >= Enums.BaseTier.SETTLEMENT
	return true


## Menus, buildings and early-closed map parts open now, as "menu:<id>" / "building:<id>" /
## "area:<region id>" keys.
static func open_keys() -> Array[String]:
	var out: Array[String] = []
	for id: StringName in MENU_RULES:
		if menu_open(id):
			out.append("menu:%s" % id)
	for id: StringName in BaseDB.buildings():
		if Colony.is_unlocked(id):
			out.append("building:%s" % id)
	for def in RegionDef.all():
		if def.early_min_z != -INF and EarlyZone.closed_line(def, GameState.day) == -INF:
			out.append("area:%s" % def.id)
	return out


## What opened since the last call, as one notification line ("" = nothing new). The first call
## of a game only records what is open, so a new game or an old save does not announce everything.
static func take_new_unlocks() -> String:
	var now := open_keys()
	if not GameState.flags.has(SEEN_FLAG):
		GameState.set_flag(SEEN_FLAG, now)
		return ""
	var seen: Array = GameState.flags[SEEN_FLAG]
	var menus: Array[String] = []
	var buildings: Array[String] = []
	var areas: Array[String] = []
	for key in now:
		if key in seen:
			continue
		seen.append(key)
		var id := StringName(key.get_slice(":", 1))
		if key.begins_with("menu:"):
			menus.append(MENU_NAMES.get(id, String(id)))
		elif key.begins_with("area:"):
			var region := RegionDef.load_def(id)
			areas.append(region.name if region else String(id))
		else:
			var def := BaseDB.get_building(id)
			buildings.append(def.display_name if def else String(id))
	GameState.set_flag(SEEN_FLAG, seen)
	return note_text(menus, buildings, areas)


static func note_text(menus: Array[String], buildings: Array[String], areas: Array[String] = []) -> String:
	var parts: Array[String] = []
	for area in areas:
		parts.append("%s 북쪽 길이 열렸어요" % area)
	if not menus.is_empty():
		parts.append("새 메뉴: %s" % ", ".join(PackedStringArray(menus)))
	if not buildings.is_empty():
		var shown := buildings.slice(0, NOTE_NAMES_MAX)
		var line := "새로 지을 수 있음: %s" % ", ".join(PackedStringArray(shown))
		if buildings.size() > shown.size():
			line += " 외 %d개" % (buildings.size() - shown.size())
		parts.append(line)
	return ". ".join(PackedStringArray(parts))
