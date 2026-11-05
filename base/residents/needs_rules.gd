class_name NeedsRules
## Morale and health rules for the daily settlement (C-06). Pure: Colony passes data in.
## Ref: docs/design/07-residents.md "상태와 필요" (사기 요인 표), "능력치" (마음 7 이상), "특성".
## All numbers are 가안 and live here in one place.

## 사기 요인 (매일)
const LIKED_JOB := 3
const DISLIKED_JOB := -3
const COOKED_MEAL := 2          # 요리 식사 (부엌에 요리사가 일한 날 먹은 사람)
const FRIEND_SAME_WORKPLACE := 2
const NO_BED := -10             # 임시 거처
const HUNGRY := -10             # 배고픔 20 미만
const STRANDED_COMPANION := -5  # 동료가 고립 중 (전원, 고립된 사람마다)
const KIND_COWORKER := 1        # 같은 작업장에 마음 7 이상인 동료
const KIND_HEART_AT := 7
## Relation value that counts as a friend for the workplace bonus (C-14 sets relations).
const FRIEND_RELATION := RelationRules.FRIEND_AT  # 08 "관계 수치": 친구 30 이상

## 떠날 위기: 사기 20 미만이 3일 이어지면 "떠나려 한다". Unresolved by the next evening → leaves (가안).
const CRISIS_MORALE := 20
const CRISIS_DAYS := 3
const PERSUADE_TRUST := 40      # 신뢰 40 이상이면 대화로 붙잡기 성공
const PERSUADE_MORALE := 25     # 붙잡으면 사기를 여기까지 올림 (가안)

## 참여 조건 (07 "참여 조건", C-11): F_access when the base has not met the need yet.
const LANGUAGE_UNMET_MULT := 0.7   # 언어: 그림 표지판이 없으면 효율 −30%
const CARE_UNMET_MULT := 0.5       # 돌봄: 돌봄방이 없으면 하루 작업 효율 0.5
## Raid warning delay for 청각 조건 without a visual alarm, for direct defense (C-17).
const HEARING_EVACUATION_DELAY_SEC := 10.0

## 건강 (07 "상태와 필요")
const INFIRMARY_RECOVER_DAYS := 1   # 의무실이 있으면 부상 1일
const SICK_CHANCE := 0.05           # 겨울이거나 배고픔 20 미만일 때 하루 확률 (가안)
const SICK_DAYS := 4                # 치료 안 하면 앓는 날 (가안)
const CONTAGION_CHANCE := 0.1       # 아픈 사람 한 명당 다른 주민에게 하루 10%
const MEDICINE_PER_CURE := 1


## Morale change today from 07 "사기 요인" for one resident. `ctx` (from Colony):
##   job_id, workplace_uid, coworkers (Array of resident dicts at the same workplace),
##   ate_cooked (bool), has_bed (bool), living_bonus (int: 모닥불·식당·숙소), stranded_count (int)
static func daily_morale(resident: Dictionary, ctx: Dictionary) -> int:
	var delta := 0
	var job: StringName = ctx.get("job_id", &"")
	if job != &"" and job in resident["likes"]:
		delta += LIKED_JOB
	if job != &"" and job in resident["dislikes"]:
		delta += DISLIKED_JOB
	if ctx.get("ate_cooked", false):
		delta += COOKED_MEAL
	delta += int(ctx.get("living_bonus", 0))
	if not ctx.get("has_bed", true):
		delta += NO_BED
	if int(resident["hunger"]) < WorkRules.HUNGRY_BELOW:
		delta += HUNGRY
	delta += STRANDED_COMPANION * int(ctx.get("stranded_count", 0))
	var friend := false
	var kind := false
	var rival := false
	for other: Dictionary in ctx.get("coworkers", []):
		var value := int(resident["relations"].get(other["id"], 0))
		if value >= FRIEND_RELATION:
			friend = true
		if value <= RelationRules.RIVAL_AT:
			rival = true
		if int(other["stats"].get(&"heart", 0)) >= KIND_HEART_AT:
			kind = true
	if friend:
		delta += FRIEND_SAME_WORKPLACE
	if rival:
		delta += RelationRules.RIVAL_SAME_WORKPLACE_MORALE  # 앙숙과 같은 작업장 −5 (08)
	if kind:
		delta += KIND_COWORKER
	return delta


## New morale after `delta`, with traits: 비관적 (사기 상승 ×0.7), 낙천적 (하한 30).
static func apply_morale(resident: Dictionary, delta: int) -> int:
	var d := float(delta)
	if d > 0.0:
		d *= WorkRules._trait_mult(resident, &"morale_gain_mult")
	var floor_value := int(WorkRules.trait_sum(resident, &"morale_floor"))
	return clampi(int(resident["morale"]) + roundi(d), floor_value, 100)
