class_name TrustRules
## Trust between the player and a resident (C-12, docs/design/07-residents.md "신뢰도").
## All numbers are 가안 and live here.

## Stage thresholds and names: 낯섬 0, 경계 풀림 20, 믿음 40, 가까움 60, 가족 같은 80.
const STAGES: Array[int] = [0, 20, 40, 60, 80]
const STAGE_NAMES: Array[String] = ["낯섬", "경계 풀림", "믿음", "가까움", "가족 같은"]
## What each stage opens (for the resident screen, D-13).
const STAGE_UNLOCKS: Array[String] = ["", "사연 1", "개인 요청 1, 떠날 위기 때 붙잡기", "사연 2, 고유 특기", "개인 요청 2, 동행 시 고유 스킬"]
## Story fragment n is revealed from this stage (사연 1 at 경계 풀림, 사연 2 at 가까움).
const FRAGMENT_STAGES: Array[int] = [1, 3]

## 오르는 법
const TALK := 3                # 하루 대화 1회
const DEEP_TALK := 6           # 머무르기 날 깊은 대화 1회 (기획 01, 수치는 가안)
const GIFT_LIKED := 8
const GIFT_NORMAL := 3
const GIFT_DISLIKED := -5
const PERSONAL_REQUEST := 20   # A-13 calls Colony.add_trust with its own amount
const SORTIE_RETURN := 5       # 함께 출격해 살아 돌아옴
const RESCUED_FROM_STRAND := 15
const GIFT_AMOUNT := {&"liked": GIFT_LIKED, &"normal": GIFT_NORMAL, &"disliked": GIFT_DISLIKED}

## Resident likes/dislikes are tags ("tea", "woodwork"...). A gift matches a tag when the resource id
## is the tag itself or is listed under it here (가안, grows with the resource list and A-16's pool).
const GIFT_TAGS := {
	&"woodwork": [&"wood", &"plank"],
	&"engine_parts": [&"parts", &"motor", &"rare_parts"],
	&"sweet_food": [&"meal"],
	&"drawing": [&"paint"],
	&"canned_fish": [&"food"],
	&"reading": [&"textbook"],
	&"gardening": [&"seeds", &"herbs"],
	&"electronics": [&"electronics", &"battery", &"radio_parts"],
}


static func stage_of(trust: int) -> int:
	var stage := 0
	for i in STAGES.size():
		if trust >= STAGES[i]:
			stage = i
	return stage


## &"liked" / &"normal" / &"disliked". Dislikes win when a resource matches both.
static func gift_reaction(resident: Dictionary, resource_id: StringName) -> StringName:
	if resident.is_empty():
		return &"normal"
	if _matches(resident.get("dislikes", []), resource_id):
		return &"disliked"
	if _matches(resident.get("likes", []), resource_id):
		return &"liked"
	return &"normal"


static func _matches(tags: Array, resource_id: StringName) -> bool:
	for tag in tags:
		var t := StringName(tag)
		if t == resource_id or resource_id in GIFT_TAGS.get(t, []):
			return true
	return false
