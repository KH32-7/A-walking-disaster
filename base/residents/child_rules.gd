class_name ChildRules
## 아이 맞이 + 성장 (C-15, docs/design/08-relations-population.md "아이 맞이", "성장").
## All numbers are 가안 and live here.

## 조건: 결혼한 두 사람, 빈 가족 숙소(그 가족 숙소에 빈 침상), 의무실, 식량 ≥ 인구 × 5, 둘 다 사기 60 이상.
const FOOD_PER_RESIDENT := 5
const MORALE_AT := 60
const INFIRMARY := &"infirmary"
## 조건을 만족하면 매일 5% 확률로 "아이를 맞고 싶다" 대화. 가족당 최소 20일 간격.
const WISH_CHANCE := 0.05
const FAMILY_INTERVAL_DAYS := 20
## 출산: 10일 뒤. 그동안 힘 작업 효율 ×0.7, 출격·경비 배정 불가.
const BIRTH_DAYS := 10
const PREGNANT_STR_MULT := 0.7
## 아이 데이터: 초기 능력치 1~3, 특성 1개를 부모 한 명에게서.
const CHILD_STAT_RANGE := Vector2i(1, 3)
const CHILD_NAME := "아기"  # until the family names the child (이름 짓기)
## 부모와 아이의 관계는 여기서 시작 (가안).
const START_RELATION := 50
const NAME_MAX := ResidentTemplate.NAME_MAX

## 성장: 아기 0~9일, 아이 10~29일, 청소년 30~49일, 성인 50일부터. 성인 → 노인 노화는 없음.
const STAGE_START := {
	Enums.AgeStage.BABY: 0, Enums.AgeStage.CHILD: 10, Enums.AgeStage.TEEN: 30, Enums.AgeStage.ADULT: 50,
}
## 아이 놀이: 기지에 아이가 있으면 모두 사기 +2.
const PLAY_MORALE := 2

## 세대 간 전수: 교실에서 20일 배우면 교사의 전직 작업 숙련 1단계. 교실은 능력치 성장 ×2.
const STUDY_DAYS := 20
const CLASSROOM := &"classroom"
const TEACH_SKILL := 1
## 전직 → 그 전직이 하던 기지 작업 (가안).
const FORMER_JOB_WORK := {
	&"carpenter": &"carpentry", &"nurse": &"medical", &"doctor": &"medical", &"mechanic": &"maintenance",
	&"electrician": &"maintenance", &"cook": &"cooking", &"farmer": &"farming", &"teacher": &"teaching",
	&"interpreter": &"radio", &"radio_pd": &"radio", &"police": &"guard", &"athlete": &"construction",
	&"painter": &"tailoring", &"laborer": &"construction",
}

## "보호자를 잊은 아이" 소문 (A-13 퀘스트가 있으면 시작한다).
const LOST_CHILD_QUEST := &"rumor_lost_child"


## Age stage for a number of days since birth (only below ADULT changes).
static func stage_for_days(days: int) -> Enums.AgeStage:
	if days >= STAGE_START[Enums.AgeStage.ADULT]:
		return Enums.AgeStage.ADULT
	if days >= STAGE_START[Enums.AgeStage.TEEN]:
		return Enums.AgeStage.TEEN
	if days >= STAGE_START[Enums.AgeStage.CHILD]:
		return Enums.AgeStage.CHILD
	return Enums.AgeStage.BABY


static func is_minor(r: Dictionary) -> bool:
	return int(r["age_stage"]) < Enums.AgeStage.ADULT


## 출산은 여성 주민만 (연애·결혼은 성별과 상관없음).
static func can_give_birth(r: Dictionary) -> bool:
	return not r.is_empty() and r.get("gender", &"") == ResidentData.GENDER_FEMALE and not is_minor(r)
