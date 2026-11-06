class_name WorkRules
## Pure work/needs rules for the daily settlement (C-05). No state: Colony passes data in.
## Ref: docs/design/07-residents.md "능력치", "상태와 필요", "직업", docs/design/11-economy.md.
## All numbers are 가안 (design placeholders) and live here in one place.
##
##   O = B × (1 + 0.1S) × (1 + 0.15K) × F_morale × F_tool × F_access × (age, traits, needs)

const STAT_BONUS := 0.1
const SKILL_BONUS := 0.15
const SKILL_MAX := 5
## Same job this many days → job skill +1 (07 "직업").
const DAYS_PER_SKILL := 7
## Using a stat for this many work days → stat +1 (07 "능력치" 성장).
const DAYS_PER_STAT := 10

## Morale bands (07 "상태와 필요"): 0~19 떠날 위기 / 20~39 0.8 / 40~69 1.0 / 70~100 1.2.
## The 0~19 band has no efficiency in the design; it uses the 20~39 value (가안).
const MORALE_LOW := 20
const MORALE_MID := 40
const MORALE_HIGH := 70
const MORALE_MULT_LOW := 0.8
const MORALE_MULT_HIGH := 1.2

const TEEN_EFFICIENCY := 0.7
const HUNGRY_BELOW := 20
const TIRED_ABOVE := 80
const NEEDS_PENALTY := 0.7  # 배고픔 20 미만 / 피로 80 초과: 효율 −30%

## Food per day (11 "자원이 빠지는 곳"): adult/teen/elder 2, child/baby 1, 대식가 +1 / 소식가 −1.
const FOOD_ADULT := 2
const FOOD_CHILD := 1
const HUNGER_PER_DAY := 40
const MEAL_HUNGER := 50
const COOKED_MEAL_HUNGER := 70

const FATIGUE_WORK := 30
const FATIGUE_REST := -60
## Sleeping with no bed (임시 거처) recovers nothing (가안).
const FATIGUE_NO_BED := 0
## Main-hall start beds recover like a 침상 building.
const FATIGUE_START_BED := 40

## Generator fuel per day (11 "자원이 빠지는 곳"): 2, winter 3.
const FUEL_PER_GENERATOR_WINTER := 3

## Jobs whose output counts as crafting for 손이 빠름 (+15%).
const CRAFT_JOBS: Array[StringName] = [&"carpentry", &"maintenance", &"tailoring", &"essence_research"]
const REST_JOB := &"rest"
const CONSTRUCTION_JOB := &"construction"
## Game pace (사용자 요청 2026-11-06: 전체 진행을 빠르게): build progress, job output and resident growth
## are multiplied by this; the consts below stay the design numbers. Tests set it to 1.0.
static var pace := 1.5


static func build_progress() -> float:
	return BUILD_PROGRESS_BASE * pace


static func stay_build_progress() -> int:
	return roundi(STAY_BUILD_PROGRESS * pace)


## Days of the same work for +1 (skill / stat), shorter with a faster pace.
static func days_per_skill() -> int:
	return maxi(roundi(DAYS_PER_SKILL / pace), 1)


static func days_per_stat() -> int:
	return maxi(roundi(DAYS_PER_STAT / pace), 1)


## Base build progress per construction worker per day (09 "건설 규칙": 하루 10 + 힘 보정).
const BUILD_PROGRESS_BASE := 10.0

## Live construction (사용자 요청 2026-11-06: 지으면 실시간으로 건설도가 오르게): seconds of base time
## (morning / sortie prep / stay) for one day of a construction worker's progress. The evening adds
## only what is left of that day's amount, so the daily total stays the design number.
const LIVE_BUILD_SEC := 45.0

## Stay day (기획 01 "기지에 머무르기"): 그날 생산 +20%; 09 "건설 규칙": 머무르면 진행도 +20.
const STAY_OUTPUT_MULT := 1.2
const STAY_BUILD_PROGRESS := 20
## Workshop / infirmary worker: batches per day at efficiency 1.0 (가안, issue #45).
const CRAFT_BATCHES_PER_DAY := 2.0


static func can_work(resident: Dictionary) -> bool:
	var age := int(resident["age_stage"])
	return age != Enums.AgeStage.BABY and age != Enums.AgeStage.CHILD \
		and int(resident["health"]) == Enums.HealthState.OK \
		and int(resident["status"]) == Enums.ResidentStatus.ACTIVE


## Why `resident` cannot take `job` ("" = allowed). Workplace capacity is checked by Colony.
static func job_block_reason(resident: Dictionary, job: JobDef) -> String:
	if job == null:
		return "알 수 없는 직업"
	var age := int(resident["age_stage"])
	if job.id == REST_JOB:
		return ""
	if age == Enums.AgeStage.BABY or age == Enums.AgeStage.CHILD:
		return "아이는 일하지 않음 (돌봄방, 교실)"
	if age == Enums.AgeStage.TEEN and (not job.teen_allowed or job.combat_role):
		return "청소년은 가벼운 작업만"
	if int(resident["health"]) != Enums.HealthState.OK:
		return "부상, 질병 중"
	return ""


static func morale_multiplier(morale: int) -> float:
	if morale >= MORALE_HIGH:
		return MORALE_MULT_HIGH
	if morale >= MORALE_MID:
		return 1.0
	return MORALE_MULT_LOW


## Everything except B in the formula, for one resident doing `job`.
## `alone` = the only worker at that workplace (혼자가 편함 +15%).
## TODO(C-11): F_access (참여 조건). TODO(A-07/A-09): F_tool (좋은 도구 1.3).
static func efficiency(resident: Dictionary, job: JobDef, alone: bool = false) -> float:
	var stat_key := job.main_stat_key()
	var s := int(resident["stats"].get(stat_key, 0)) if stat_key != &"" else 0
	var k := int(resident["job_skill"].get(job.id, 0))
	var f := (1.0 + STAT_BONUS * s) * (1.0 + SKILL_BONUS * k)
	f *= morale_multiplier(int(resident["morale"]))
	match int(resident["age_stage"]):
		Enums.AgeStage.TEEN:
			f *= TEEN_EFFICIENCY
		Enums.AgeStage.ELDER:
			f *= job.elder_efficiency
	var trait_bonus := trait_sum(resident, &"work_efficiency")
	if alone:
		trait_bonus += trait_sum(resident, &"solo_work_efficiency")
	if job.id in CRAFT_JOBS:
		trait_bonus += trait_sum(resident, &"craft_efficiency")
	f *= 1.0 + trait_bonus
	if int(resident["hunger"]) < HUNGRY_BELOW:
		f *= NEEDS_PENALTY
	if int(resident["fatigue"]) > TIRED_ABOVE:
		f *= NEEDS_PENALTY
	return maxf(f, 0.0)


static func food_need(resident: Dictionary) -> int:
	var age := int(resident["age_stage"])
	var base := FOOD_CHILD if age == Enums.AgeStage.BABY or age == Enums.AgeStage.CHILD else FOOD_ADULT
	return maxi(base + roundi(trait_sum(resident, &"food_use")), 0)


static func fatigue_change(worked: bool, rested: bool, sleep_recovery: int, resident: Dictionary) -> int:
	var change := 0
	if rested:
		change += FATIGUE_REST
	elif worked:
		change += roundi(FATIGUE_WORK * _trait_mult(resident, &"fatigue_gain_mult"))
	return change - sleep_recovery


## Sum of one effect over the resident's traits.
static func trait_sum(resident: Dictionary, key: StringName) -> float:
	var total := 0.0
	for t in resident["traits"]:
		var def := BaseDB.get_trait(t)
		if def:
			total += def.effect(key)
	return total


## Product of a multiplier effect over the resident's traits (missing = 1.0).
static func _trait_mult(resident: Dictionary, key: StringName) -> float:
	var m := 1.0
	for t in resident["traits"]:
		var def := BaseDB.get_trait(t)
		if def and def.effects.has(key):
			m *= def.effects[key]
	return m
