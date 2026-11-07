class_name RegionDef
extends Resource
## One field region (B-24). Data lives in data/regions/<id>.tres, the map in map_scene
## (levels/field/<id>/<id>.tscn, SceneRouter.REGION_SCENE_FMT).
## Fields follow docs/design/02-field.md "데이터 정의" Region. Not in the design table:
## family_shares, resources, unlock_* (design 02 "해금 조건" and 12 "해금 순서" as checks).
## Readers: Progression.region_danger() (danger, Lane A), the sortie prep screen (Lane D: name,
## danger, monster_families, resources, unlock_text, is_unlocked()).

const DIR := "res://data/regions/"
const FMT := "res://data/regions/%s.tres"

@export var id: StringName = &""
@export var name: String = ""
@export_range(1, 5) var danger: int = 1
@export_file("*.tscn") var map_scene: String = ""
## Main monster families, most common first (02 "주요 마물 계열").
@export var monster_families: Array[Enums.Element] = []
## Share of each family above, same order, sums to 1 (가안).
@export var family_shares: Array[float] = []
## Representative resources (02 "대표 자원"), ids in data/resources/.
@export var resources: Array[StringName] = []
## LootTable.region_id this region's containers use (LootData.find_table). Usually the region id.
@export var loot_table_id: StringName = &""
## data/monsters/<boss_id>.tres once B-19 / B-25 add it (가안 ids).
@export var boss_id: StringName = &""
## ExtractPoint ids on the map. ExtractionManager activates ExtractionManager.ACTIVE_COUNT of them.
@export var extract_candidates: Array[StringName] = []
## HiddenRoute ids on the map.
@export var hidden_routes: Array[StringName] = []
## 02 "탈것": the map has a WATER VehicleSpot to put a boat from the base on (the sortie screen
## offers boats only here).
@export var boat_dock := false
## Place names drawn on the field map and minimap (Lane D). Generated from the map file by
## field/build/export_map_labels.gd; edit the map file and run that again rather than this list.
## [{"text": String, "pos": Vector2 (world x/z, metres), "kind": StringName}]
## kind, most important first: landmark, water, area, road, spot (MAP_LABEL_KINDS).
@export var map_labels: Array[Dictionary] = []

const MAP_LABEL_KINDS: Array[StringName] = [&"landmark", &"water", &"area", &"road", &"spot"]

@export_group("Early days")
## 02 "맵 구조" 초반 구역 (EarlyZone): before early_open_day only the map south of this world z line
## (m) is open. -INF = the whole map from day 1.
@export var early_min_z := -INF
@export var early_open_day := 3

@export_group("Unlock")
## Shown on the sortie prep screen (02 "해금 조건").
@export var unlock_text: String = ""
## Every condition below must hold. Empty or default means no check.
@export var unlock_flags: Array[StringName] = []
@export var unlock_tier: Enums.BaseTier = Enums.BaseTier.CAMP
## Building def id (data/buildings) and the level it must reach.
@export var unlock_facility: StringName = &""
@export var unlock_facility_level: int = 0
## Quest id that must be completed (Quests.is_completed).
@export var unlock_quest: StringName = &""


static func load_def(region_id: StringName) -> RegionDef:
	var path := FMT % region_id
	return load(path) as RegionDef if ResourceLoader.exists(path) else null


## Every RegionDef in DIR, by danger then id.
static func all() -> Array[RegionDef]:
	var out: Array[RegionDef] = []
	for file in ResourceLoader.list_directory(DIR):
		if file.ends_with(".tres"):
			var def := load(DIR + file) as RegionDef
			if def != null:
				out.append(def)
	out.sort_custom(func(a: RegionDef, b: RegionDef) -> bool:
		return a.danger < b.danger if a.danger != b.danger else String(a.id) < String(b.id))
	return out


func has_map() -> bool:
	return map_scene != "" and ResourceLoader.exists(map_scene)


func is_unlocked(state: Dictionary = {}) -> bool:
	return missing_unlocks(state).is_empty()


## Unmet unlock conditions: &"flag:<id>", &"tier", &"facility", &"quest". Empty when open.
## state overrides the live game for tests and previews: {"flags": Dictionary,
## "tier": Enums.BaseTier, "facility_levels": {def_id: level}, "completed_quests": Array}.
func missing_unlocks(state: Dictionary = {}) -> Array[StringName]:
	var missing: Array[StringName] = []
	for flag in unlock_flags:
		var on: bool = bool(state["flags"].get(flag, false)) if state.has("flags") else GameState.has_flag(flag)
		if not on:
			missing.append(StringName("flag:%s" % flag))
	var tier: int = state.get("tier", Colony.tier)
	if tier < unlock_tier:
		missing.append(&"tier")
	if unlock_facility != &"":
		var level: int = state["facility_levels"].get(unlock_facility, 0) if state.has("facility_levels") \
				else Colony.facility_level(unlock_facility)
		if level < unlock_facility_level:
			missing.append(&"facility")
	if unlock_quest != &"":
		var done: bool = unlock_quest in state["completed_quests"] if state.has("completed_quests") \
				else Quests.is_completed(unlock_quest)
		if not done:
			missing.append(&"quest")
	return missing
