class_name ResidentText
## Words for the resident screens (D-13). Owner: Lane D. No rules here: names, labels and
## placeholder lines only. Numbers (trust, reactions, outcomes) come from Colony.
##
## TODO(A): talk lines are Lane A's (Radio / AI 대화, C-12 "대사 문장은 A"). Until a line API exists,
## line() builds a short line from what the resident already told the player (first_line,
## unlocked story fragments, known likes). Swap the body of line() when A ships one.

## Like / dislike tags (resident data) → words. Unknown tags fall back to the resource name or the id.
const TAG_NAMES := {
	&"tea": "차", &"coffee": "커피", &"woodwork": "목공", &"engine_parts": "엔진 부품",
	&"sweet_food": "단 음식", &"drawing": "그림 그리기", &"canned_fish": "생선 통조림",
	&"reading": "책 읽기", &"gardening": "텃밭 가꾸기", &"electronics": "전자기기",
	&"loud_noise": "시끄러운 소리", &"stairs": "계단", &"waiting": "기다리기", &"dark": "어둠",
	&"shouting": "고함", &"music": "음악", &"cooking": "요리", &"cats": "고양이", &"rain": "비",
	&"crowds": "사람 많은 곳", &"cold": "추위", &"bugs": "벌레",
}

## Night event choices (NightEventDef.choices) → what the player does.
const CHOICE_NAMES := {&"watch": "지켜본다", &"mediate": "둘을 말린다", &"cheer": "응원한다"}

## One scene-setting line per night event (fallback: NightEventDef.display_name).
const NIGHT_INTRO := {
	&"bonfire": "%s이(가) 모닥불가에 둘러앉았다.",
	&"quarrel": "%s 사이에 목소리가 높아졌다.",
	&"confession": "%s이(가) 조용한 복도 끝에서 마주 섰다.",
	&"date": "%s이(가) 공터 가장자리에서 별을 보고 있다.",
	&"proposal": "%s이(가) 할 말이 있다며 모두를 불렀다.",
	&"wedding": "%s의 결혼식. 모두가 강당에 모였다.",
	&"breakup": "%s이(가) 서로 눈을 피한다.",
	&"prejudice_talk": "%s이(가) 늦은 밤 마주 앉았다. 미뤄 둔 이야기를 꺼낼 때다.",
}

## Gift reactions (Colony.give_gift "reaction") → [mark, words]. The mark is a shape glyph so the
## reaction never reads by colour alone.
const REACTIONS := {
	&"liked": ["▲", "좋아해요"],
	&"normal": ["●", "고마워해요"],
	&"disliked": ["▼", "싫어해요"],
}

const GREETINGS := ["무슨 일 있어?", "왔구나.", "잠깐 쉬던 참이야.", "오늘도 무사히 돌아왔네."]


## "서하은" or "서하은 “렌치”".
static func full_name(r: Dictionary) -> String:
	var nick := String(r.get("nickname", ""))
	var nm := String(r.get("name", ""))
	return nm + ("  “%s”" % nick if nick != "" else "")


## What others call them: nickname first.
static func call_name(r: Dictionary) -> String:
	var nick := String(r.get("nickname", ""))
	return nick if nick != "" else String(r.get("name", ""))


static func tag_name(tag: StringName) -> String:
	if TAG_NAMES.has(tag):
		return TAG_NAMES[tag]
	var def: Variant = Economy.get_def(tag)
	return String(def.name) if def != null else String(tag)


static func choice_name(choice: StringName) -> String:
	return CHOICE_NAMES.get(choice, String(choice))


static func names_of(ids: Array) -> String:
	var out: PackedStringArray = []
	for id in ids:
		out.append(call_name(Colony.get_resident(StringName(id))))
	return ", ".join(out)


static func night_intro(event_id: StringName, participants: Array) -> String:
	var fmt: String = NIGHT_INTRO.get(event_id, "%s")
	return fmt % names_of(participants)


## Placeholder line (see TODO above). kind: &"greet" | &"talk" | &"deep" | &"busy" | &"crisis".
static func line(r: Dictionary, kind: StringName, story: Array = []) -> String:
	var morale := int(r.get("morale", 50))
	match kind:
		&"crisis":
			return "여기 있으면 안 될 것 같아. 오늘 밤에 떠날까 해."
		&"busy":
			return "오늘은 이야기 많이 했잖아. 내일 또 와."
		&"talk", &"deep":
			var likes: Array = Colony.known_likes(StringName(r.get("id", &"")))
			if kind == &"deep" and not story.is_empty():
				return String(story.back())
			if not story.is_empty() and story.size() > 1:
				return String(story[0])
			if not likes.is_empty():
				return "%s 생각이 나더라. 그런 게 있으면 좀 나아." % tag_name(likes[0])
			return "그냥… 이렇게 얘기하는 게 좋아." if morale >= 40 else "요즘 좀 지쳤어. 들어줘서 고마워."
	if morale < 20:
		return "…응."
	var first := String(r.get("story", {}).get("first_line", ""))
	if first != "" and int(r.get("trust", 0)) < 20:
		return first
	return GREETINGS[absi(hash(StringName(r.get("id", &"")))) % GREETINGS.size()]
