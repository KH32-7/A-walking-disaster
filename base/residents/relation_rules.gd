class_name RelationRules
## Relations between residents and the night events (C-14, docs/design/08-relations-population.md
## "관계 수치", "밤 이벤트"). All numbers are 가안 and live here.

const MIN := -100
const MAX := 100

## Stages by value (08 "관계 수치"). LOVERS / MARRIED come from flags, not from the value.
const RIVAL_AT := -50          # 앙숙: −50 이하
const AWKWARD_AT := -10        # 서먹함: −49 ~ −10
const FRIEND_AT := 30          # 친구: 30 ~ 59
const BEST_FRIEND_AT := 60     # 절친: 60 이상
const STAGE_NAMES := {
	&"rival": "앙숙", &"awkward": "서먹함", &"acquainted": "아는 사이", &"friend": "친구",
	&"best_friend": "절친", &"lovers": "연인", &"married": "배우자",
}

## 같은 작업장 효과
const RIVAL_SAME_WORKPLACE_MORALE := -5
const BEST_FRIEND_WORK_MULT := 1.1

## 요인
const SAME_WORKPLACE := 1
const BONFIRE := Vector2i(2, 5)
const SHARED_LIKE_BONUS := 2
const SORTIE_TOGETHER := 5
const SAVED_PARTNER := 15      # 상대를 구해줌 (B·C-17이 add_relation으로 부름)
const QUARREL := Vector2i(-15, -5)
## 편견 (08 "편견과 갈등"): holder → target tag. The chain itself is C-16.
const PREJUDICE_TARGET_TRAITS: Array[StringName] = [&"monster_mark"]

## 감소: 30 이상인 관계는 10일 교류가 없으면 하루 −1씩 30까지.
const DECAY_FROM := 30
const DECAY_AFTER_DAYS := 10
const DECAY_PER_DAY := 1

## 밤 이벤트
const NIGHT_EVENTS_MAX := 2               # 조건을 만족하는 것 중 1~2개
const NIGHT_SECOND_EVENT_CHANCE := 0.5
const BONFIRE_PARTICIPANTS := Vector2i(2, 3)
const QUARREL_BELOW := -10
const QUARREL_FATIGUE_AT := 80
const MEDIATE_SUCCESS_GAIN := 5           # 중재 성공률 = 두 사람 신뢰도 평균 %
const CONFESS_AT := 50
const CHEER_MORALE := 5
const DATE_RELATION := 5
const DATE_MORALE := 5
const PROPOSE_AT := 80
const PROPOSE_LOVERS_DAYS := 10
const PROPOSE_MORALE_AT := 50
const WEDDING_COST := {&"food": 20, &"cloth": 5}
const FAMILY_HOUSE := &"family_house"
const FESTIVAL_MORALE := 15
const FESTIVAL_NEXT_DAY_MULT := 1.1
const BREAKUP_BELOW := 30
const BREAKUP_DAYS := 7
const BREAKUP_MORALE := -15


## Stage id for a value and its flags (Enums.RelationFlag ints).
static func stage_of(value: int, flags: Array = []) -> StringName:
	if Enums.RelationFlag.MARRIED in flags:
		return &"married"
	if Enums.RelationFlag.LOVERS in flags:
		return &"lovers"
	if value <= RIVAL_AT:
		return &"rival"
	if value <= AWKWARD_AT:
		return &"awkward"
	if value < FRIEND_AT:
		return &"acquainted"
	if value < BEST_FRIEND_AT:
		return &"friend"
	return &"best_friend"


## Multiplier for a positive change between `a` and `b` (resident dictionaries):
## 혼자가 편함 ×0.5, 편견 ×0.3 toward the target, 연애에 관심 없음 우정 +30% (not for lovers).
static func gain_mult(a: Dictionary, b: Dictionary, romantic: bool) -> float:
	var m := 1.0
	for pair: Array in [[a, b], [b, a]]:
		var me: Dictionary = pair[0]
		var other: Dictionary = pair[1]
		m *= WorkRules._trait_mult(me, &"relation_gain_mult")
		if prejudiced_against(me, other):
			m *= WorkRules._trait_mult(me, &"prejudice_relation_mult")
		if not romantic:
			m *= 1.0 + WorkRules.trait_sum(me, &"friendship_gain_bonus")
	return m


## 모닥불 수다쟁이 ×2: the highest bonfire multiplier among the pair.
static func bonfire_mult(a: Dictionary, b: Dictionary) -> float:
	return maxf(WorkRules._trait_mult(a, &"bonfire_relation_mult"), WorkRules._trait_mult(b, &"bonfire_relation_mult"))


## `holder` has 편견 and `other` carries a target trait (마물 흔적).
static func prejudiced_against(holder: Dictionary, other: Dictionary) -> bool:
	return WorkRules.trait_sum(holder, &"prejudice_relation_mult") > 0.0 and _has_any(other, PREJUDICE_TARGET_TRAITS)


static func romance_ok(r: Dictionary) -> bool:
	return int(r["age_stage"]) >= Enums.AgeStage.ADULT and WorkRules.trait_sum(r, &"romance_exempt") <= 0.0


static func shared_like(a: Dictionary, b: Dictionary) -> bool:
	for like in a["likes"]:
		if like in b["likes"]:
			return true
	return false


static func pair_key(a: StringName, b: StringName) -> String:
	return "%s|%s" % [a, b] if String(a) < String(b) else "%s|%s" % [b, a]


static func _has_any(r: Dictionary, trait_ids: Array[StringName]) -> bool:
	for t in r["traits"]:
		if StringName(t) in trait_ids:
			return true
	return false
