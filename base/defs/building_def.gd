class_name BuildingDef
extends Resource
## One building type (docs/design/09-base-building.md "건물 목록", "데이터 정의").
## Data lives in data/buildings/<id>.tres. Instances live in Colony.buildings (Dictionary, JSON-safe).
## Defense structures (docs/design/10-raids-defense.md) use the same schema with category DEFENSE.

enum Category { HOUSING, PRODUCTION, PROCESSING, LIVING, CRAFTING, INCLUSION, STORAGE, MILITARY, SPECIAL, UTILITY, DEFENSE }

## Level costs (09 "건물 목록"): Lv2 = Lv1 × 2 + parts 5, Lv3 = Lv1 × 3 + rare_parts 3.
const LEVEL_COST_MULT: Array[int] = [1, 2, 3]
const LEVEL_EXTRA_COST: Array[Dictionary] = [{}, {&"parts": 5}, {&"rare_parts": 3}]
const MAX_LEVEL := 3

## Build work by footprint (09 "건설 규칙"): small (≤ 2×2) 10, medium (3×3) 30, large (4×4+) 60.
const WORK_SMALL := 10
const WORK_MEDIUM := 30
const WORK_LARGE := 60

## Default power-off order when power runs short (09 "전력"): lower = kept on longer.
const POWER_PRIORITY_INCLUSION := 0
const POWER_PRIORITY_INFIRMARY := 1
const POWER_PRIORITY_RADIO := 2
const POWER_PRIORITY_OTHER := 3

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.LIVING
## Footprint in cells (1 cell = 2 m). (0, 0) = not placed on the grid (attached / fixed in the main hall).
@export var size: Vector2i = Vector2i.ONE
## Lv1 cost, resource_id -> amount. Use cost_for_level() for Lv2/Lv3.
@export var cost: Dictionary[StringName, int] = {}
## Build work (진행도). 0 = derive from size (build_work_needed()).
@export var build_work := 0
## Worker slots for jobs (정원). 0 = no workers.
@export var capacity := 0
## Effects at Lv1. Keys used so far:
##   beds (int, 인구 상한), fatigue_recovery, morale_daily, storage (창고 +N), power_supply,
##   power_supply_winter, fuel_per_day, adjacent_farm_bonus, night_talk, grief_recovery,
##   students, care_children, defense, access_mobility / access_language / access_hearing (구역 조건 충족),
##   unlock_trade, class_change, combat_mastery_days
@export var effects: Dictionary[StringName, float] = {}
## Power used at Lv1..Lv3 (09 "전력").
@export var power_use: Array[int] = [0, 0, 0]
## Lower = stays powered longer when supply is short.
@export var power_priority := POWER_PRIORITY_OTHER
## Base noise contribution (09 "기지 소음도").
@export var noise := 0.0
## Building ids that must already be completed (목공소 → 숙소 ...).
@export var requires: Array[StringName] = []
## GameState flags that must be set (blueprints, first death ...).
@export var requires_flags: Array[StringName] = []
## An active resident with this former job must live in the base (발전기 → electrician).
@export var requires_former_job: StringName = &""
@export var tier_min: Enums.BaseTier = Enums.BaseTier.CAMP
## Must be placed in a zone with this id (무전탑 → roof). &"" = any cleared zone.
@export var zone_only: StringName = &""
## Attached to another building instead of the grid (통역 무전기 → radio_room).
@export var attach_to: StringName = &""
## Exists from the start (무전실 = 본관 방송실). Cannot be built or demolished.
@export var prebuilt := false
## Defense structures (10 탭): max durability and contribution to the automatic raid judgment.
@export var durability := 0
@export var defense_value := 0.0
@export var note: String = ""


func cost_for_level(level: int) -> Dictionary:
	var lv := clampi(level, 1, MAX_LEVEL)
	var result := {}
	for res: StringName in cost:
		result[res] = cost[res] * LEVEL_COST_MULT[lv - 1]
	var extra: Dictionary = LEVEL_EXTRA_COST[lv - 1]
	for res: StringName in extra:
		result[res] = result.get(res, 0) + extra[res]
	return result


func power_use_at(level: int) -> int:
	return power_use[clampi(level, 1, power_use.size()) - 1] if not power_use.is_empty() else 0


func build_work_needed() -> int:
	if build_work > 0:
		return build_work
	var longest := maxi(size.x, size.y)
	if longest >= 4:
		return WORK_LARGE
	if longest >= 3:
		return WORK_MEDIUM
	return WORK_SMALL


func effect(key: StringName, default: float = 0.0) -> float:
	return effects.get(key, default)


func bed_count() -> int:
	return int(effects.get(&"beds", 0.0))
