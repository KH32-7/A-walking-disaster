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
## Stage ids match what Journal (A-17) reads: friend, lover, married, separated (이별 때 한 번).
const SEPARATED := &"separated"
const STAGE_NAMES := {
	&"rival": "앙숙", &"awkward": "서먹함", &"acquainted": "아는 사이", &"friend": "친구",
	&"best_friend": "절친", &"lover": "연인", &"married": "배우자", &"separated": "헤어짐",
	&"comrade": "전우",
}

## 같은 작업장 효과
const RIVAL_SAME_WORKPLACE_MORALE := -5
const BEST_FRIEND_WORK_MULT := 1.1

## 요인
## 2026-11-07 패치: 31일 동안 연애가 하나도 안 생겨서 속도를 올림 (1 → 2, 고백 50 → 40, 청혼 80 → 70, 연인 10 → 7일).
const SAME_WORKPLACE := 2
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
## 모닥불: 첫 사람은 무작위, 나머지는 첫 사람과 가까울수록 잘 뽑힌다. 가중치 = 1 + max(관계, 0) / 이 값.
const BONFIRE_CLOSE_PER := 10.0
const QUARREL_BELOW := -10
const QUARREL_FATIGUE_AT := 80
const MEDIATE_SUCCESS_GAIN := 5           # 중재 성공률 = 두 사람 신뢰도 평균 %
const CONFESS_AT := 40
const CHEER_MORALE := 5
const DATE_RELATION := 5
const DATE_MORALE := 5
const PROPOSE_AT := 70
const PROPOSE_LOVERS_DAYS := 7
const PROPOSE_MORALE_AT := 50
const WEDDING_COST := {&"food": 20, &"cloth": 5}
const FAMILY_HOUSE := &"family_house"
const FESTIVAL_MORALE := 15
const FESTIVAL_NEXT_DAY_MULT := 1.1
const BREAKUP_BELOW := 30
const BREAKUP_DAYS := 7
const BREAKUP_MORALE := -15

## --- 2026-11-07 패치: 숫자만 오르는 대신 사건을 늘림 ---
## 전우애: 함께 출격해 살아 돌아온 횟수가 쌓이면 "전우의 약속". 전우는 같이 출격하면 관계가 두 배로 오르고
## 둘 다 사기가 오르며, 같은 작업장에서 절친처럼 효율 +10%.
const COMRADE_SORTIES := 2  # 동행은 최대 2명이라 둘이 함께 나간 출격만 센다
const COMRADE_MIN_RELATION := 20
const COMRADE_OATH_RELATION := 10
const COMRADE_TOAST_COST := {&"food": 2}
const COMRADE_TOAST_MORALE := 5
const COMRADE_SORTIE_MULT := 2
const COMRADE_RETURN_MORALE := 3
## 짝사랑: 고백 문턱 아래인 미혼 성인 둘. 등을 떠밀면 확률로 크게 가까워지거나 어색해진다.
const CRUSH_RANGE := Vector2i(20, 39)
const CRUSH_WATCH := 3
const CRUSH_NUDGE_CHANCE := 0.7
const CRUSH_NUDGE := 8
const CRUSH_NUDGE_FAIL := -4
## 질투: 연인 한 명과 가까운 제3자(관계 이 값 이상)가 있으면. 말리면 신뢰도 평균 % 확률로 연인 관계 +.
const JEALOUSY_AT := 45
const JEALOUSY_MEDIATED := 5
const JEALOUSY_LOVERS := -6
const JEALOUSY_RIVAL := -8
## 기념일: 연인이 된 날부터 이 간격마다.
const ANNIVERSARY_DAYS := 10
const ANNIVERSARY_RELATION := 6
const ANNIVERSARY_MORALE := 5
const ANNIVERSARY_GIFT_COST := {&"cloth": 1}
const ANNIVERSARY_GIFT_MORALE := 5
## 사랑싸움: 연인·배우자 중 한 명이 지쳤거나(피로) 기운이 없을 때(사기).
const SPAT_FATIGUE_AT := 70
const SPAT_MORALE_BELOW := 35
const SPAT_LOSS := -6
const SPAT_MEDIATED := 4
const SPAT_MEDIATED_MORALE := 3
## 화해: 서먹하거나 앙숙인 둘이 오늘 함께 출격해 살아 돌아왔을 때.
const RECONCILE_BELOW := 0
const RECONCILE_RELATION := 12
const RECONCILE_MORALE := 3


## Stage id for a value and its flags (Enums.RelationFlag ints).
static func stage_of(value: int, flags: Array = []) -> StringName:
	if Enums.RelationFlag.MARRIED in flags:
		return &"married"
	if Enums.RelationFlag.LOVERS in flags:
		return &"lover"
	if Enums.RelationFlag.COMRADES in flags and value >= 0:
		return &"comrade"
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


## Replaces the romance flag (LOVERS / MARRIED, -1 = none) and keeps the others (COMRADES).
static func with_romance(flags: Array, flag: int) -> Array:
	var out: Array = flags.filter(func(f): return int(f) != Enums.RelationFlag.LOVERS and int(f) != Enums.RelationFlag.MARRIED)
	if flag >= 0:
		out.append(flag)
	return out


static func pair_key(a: StringName, b: StringName) -> String:
	return "%s|%s" % [a, b] if String(a) < String(b) else "%s|%s" % [b, a]


static func _has_any(r: Dictionary, trait_ids: Array[StringName]) -> bool:
	for t in r["traits"]:
		if StringName(t) in trait_ids:
			return true
	return false
