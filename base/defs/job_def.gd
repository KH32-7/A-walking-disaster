class_name JobDef
extends Resource
## One resident job (docs/design/07-residents.md "직업"). Data lives in data/jobs/<id>.tres.
## Daily output formula is applied by C-05:
##   O = B × (1 + 0.1S) × (1 + 0.15K) × F_morale × F_tool × F_access
## where B = base_output, S = the resident's `main_stat`, K = job skill (0..5).

## Resident stat keys (Colony resident "stats" dictionary).
const STATS: Array[StringName] = [&"str", &"dex", &"sense", &"heart"]

@export var id: StringName = &""
@export var display_name: String = ""
## Building def id of the workplace (data/buildings, C-04). &"" = no building (휴식).
@export var workplace: StringName = &""
@export_enum("str", "dex", "sense", "heart", "none") var main_stat: String = "str"
## Base daily output, resource_id -> amount (B in the formula).
@export var base_output: Dictionary[StringName, float] = {}
## Resources consumed per day to produce base_output (목공: 나무 8 → 목재판 4).
@export var base_input: Dictionary[StringName, float] = {}
## Non-resource daily effects, read by the system that owns them:
##   food_efficiency, morale_bonus, heal_per_day, study_speed_mult, care_children,
##   build_progress, fatigue, guard_power, threat_reduction
@export var effects: Dictionary[StringName, float] = {}
## Teens may take this job (가벼운 작업, efficiency TEEN_EFFICIENCY). Children never work.
@export var teen_allowed := false
## Efficiency multiplier for elders (교육·의료·요리 1.2).
@export var elder_efficiency := 1.0
## Combat role (경비·파견): children and teens cannot be assigned.
@export var combat_role := false
## Shown in the job list; a short reminder of what the job needs.
@export var note: String = ""


func main_stat_key() -> StringName:
	return &"" if main_stat == "none" else StringName(main_stat)
