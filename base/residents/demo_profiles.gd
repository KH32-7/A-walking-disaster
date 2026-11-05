class_name DemoProfiles
## TEMPORARY: the three demo survivors (docs/design/13-world-narrative.md "데모 구조자"),
## hand-written until Lane A's survivor pool (A-16, data/resident_pool/) exists.
## Same fields as a rescue profile (see ResidentData). Missing fields are rolled.
## Names and stories are placeholders (가안).

const PROFILES: Array[Dictionary] = [
	{
		"id": &"demo_carpenter",
		"name": "윤기철",
		"age_stage": Enums.AgeStage.ELDER,
		"former_job": &"carpenter",
		"traits": [&"diligent", &"pessimist"],
		"likes": [&"tea", &"woodwork"],
		"dislikes": [&"loud_noise", &"canned_fish"],
		"access_needs": [Enums.AccessNeed.MOBILITY],
		"stats": {&"str": 3, &"dex": 7, &"sense": 4, &"heart": 5},
		"story": {
			"background": "다리를 다친 60대 전직 목수. 대피 버스를 기다리다 혼자 남았다.",
			"fragments": ["경사로 만드는 법을 알고 있다.", "목공을 가르쳐 줄 수 있다."],
		},
	},
	{
		"id": &"demo_mechanic",
		"name": "서하은",
		"age_stage": Enums.AgeStage.ADULT,
		"former_job": &"mechanic",
		"traits": [&"quick_hands", &"brave"],
		"likes": [&"coffee", &"engine_parts"],
		"dislikes": [&"stairs", &"waiting"],
		"access_needs": [Enums.AccessNeed.MOBILITY],
		"stats": {&"dex": 7},
		"story": {
			"background": "멈춘 승강기에 갇혀 있던 30대 휠체어 사용자. 전직 자동차 정비공.",
			"fragments": ["정비소를 맡겠다고 한다."],
		},
	},
	{
		# New-game intro (사용자 요청 2026-11-06): hiding in the park 관리사무소; makes the 의무실 possible.
		"id": &"demo_doctor",
		"name": "윤하진",
		"age_stage": Enums.AgeStage.ADULT,
		"former_job": &"doctor",
		"traits": [&"diligent"],
		"likes": [&"coffee", &"books"],
		"dislikes": [&"waiting"],
		"stats": {&"heart": 7, &"sense": 6},
		"story": {
			"background": "공원 관리사무소에 숨어 있던 30대 응급의학과 의사. 대피소로 가던 길에 마물에게 막혔다.",
			"fragments": ["의무실을 맡겠다고 한다.", "약초로 약을 만드는 법을 안다."],
			"first_line": "살았네요... 다친 사람이 있다고요? 가요, 지금 바로.",
		},
	},
	{
		"id": &"demo_child",
		"name": "린",
		"age_stage": Enums.AgeStage.CHILD,
		"former_job": &"student",
		"traits": [&"monster_mark", &"timid"],
		"likes": [&"drawing", &"sweet_food"],
		"dislikes": [&"dark", &"shouting"],
		"access_needs": [Enums.AccessNeed.LANGUAGE],
		"story": {
			"background": "말이 잘 통하지 않는 이주민 가정의 아이. 마물에게 닿은 팔에 흔적이 남았다.",
			"fragments": ["그림으로 이야기하는 것을 좋아한다."],
		},
	},
]
