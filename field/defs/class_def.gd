class_name ClassDef
extends Resource
## One combat class (B-13): GUN, BLADE, BLUNT. Data: data/classes/<gun|blade|blunt>.tres.
## The class is the main weapon's family (Armory.get_combat_class). Changing it is the base's job
## (훈련장, Lane C); the field only reads it.
## Fields follow docs/design/03-combat-classes.md "데이터 정의" ClassDef. Passive ids are read by
## ClassSkills: reload_fast, weak_point_bonus, backstab_bonus, bleed_stacks, stagger_longer,
## armor_broken_bonus. All numbers are 가안.

## Mastery level that unlocks passive_5 / passive_10.
const PASSIVE_LEVELS := [5, 10]
const PATHS := ["res://data/classes/gun.tres", "res://data/classes/blade.tres",
	"res://data/classes/blunt.tres"]

static var _cache: Dictionary = {}

@export var id: Enums.CombatClass = Enums.CombatClass.GUN
@export var skill_q: SkillDef
@export var skill_e: SkillDef
@export var passive_5: StringName = &""
@export var passive_10: StringName = &""
## Armory item def ids of this family (reference list; the family itself is ItemDef.combat_class).
@export var weapon_types: Array[StringName] = []

@export_group("Runtime")
## reload_fast 0.25 = -25%, weak_point_bonus 0.3 = +30%, backstab_bonus 0.5, bleed_stacks 2,
## stagger_longer 0.3, armor_broken_bonus 0.15.
@export var passive_5_value: float = 0.0
@export var passive_10_value: float = 0.0
## Added to every hit of this family's weapons (blade: bleed). StatusHolder entries.
@export var hit_status: Array[Dictionary] = []
## Added to the combo finisher (blunt: stagger + armor break). The finisher is hit
## CombatTuning.combo_hits, or the weapon's guard_break_hits stat when it has one (hammer 2).
@export var finisher_status: Array[Dictionary] = []


## data/classes/<id>.tres for an Enums.CombatClass value, or null (-1 = no main weapon).
static func for_class(combat_class: int) -> ClassDef:
	if combat_class < 0 or combat_class >= PATHS.size():
		return null
	if not _cache.has(combat_class):
		_cache[combat_class] = load(PATHS[combat_class]) as ClassDef
	return _cache[combat_class]


## The class's Q skill if it is enabled, else null. Companions use only this (03 "동행 주민 전투").
static func skill_q_for(combat_class: int) -> SkillDef:
	var def := for_class(combat_class)
	return def.skill_q if def != null and def.skill_q != null and def.skill_q.enabled else null


## Value of `passive` at this mastery level, or 0 when it is not this class's or not unlocked yet.
func passive_value(passive: StringName, mastery: int) -> float:
	if passive == passive_5 and mastery >= PASSIVE_LEVELS[0]:
		return passive_5_value
	if passive == passive_10 and mastery >= PASSIVE_LEVELS[1]:
		return passive_10_value
	return 0.0
