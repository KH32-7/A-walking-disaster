extends RefCounted
## KoreanText (QA 2026-11-06): particles fit the word before them, so lines read "윤하진이 기지 식구가
## 되었다" and not "윤하진이(가)". Also: night event screens show a mood line, not the design note.

const NIGHT_DIR := "res://data/events/night/"


func run() -> bool:
	var ok := true
	# particle(): either spelling in, the fitting one out
	for c: Array in [["윤하진", "가", "이"], ["이소아", "이", "가"], ["정수", "을", "를"], ["손전등", "를", "을"],
			["의사", "은", "는"], ["윤기철", "와", "과"], ["서울", "으로", "로"], ["정착지", "로", "로"],
			["마을", "로", "로"], ["공방", "로", "으로"], ["3", "가", "이"], ["2", "을", "를"],
			["정착지", "이에요", "예요"], ["야영지", "예요", "예요"], ["공방", "예요", "이에요"]]:
		ok = _expect(KoreanText.particle(c[0], c[1]) == c[2], "particle(%s, %s) = %s, want %s"
			% [c[0], c[1], KoreanText.particle(c[0], c[1]), c[2]]) and ok
	# fix(): placeholders in whole lines
	for c: Array in [
			["윤하진이(가) 기지 식구가 되었다", "윤하진이 기지 식구가 되었다"],
			["이소아이(가) 기지 식구가 되었다", "이소아가 기지 식구가 되었다"],
			["윤기철, 윤하진이(가) 모닥불가에 둘러앉았다.", "윤기철, 윤하진이 모닥불가에 둘러앉았다."],
			["윤기철이(가) 윤하진에게서 의사을(를) 배웠다", "윤기철이 윤하진에게서 의사를 배웠다"],
			["기지가 정착지(으)로 성장했다", "기지가 정착지로 성장했다"],
			["기지가 정착지(이)에요.", "기지가 정착지예요."],
			["윤하진와(과) 윤기철은(는) 아직", "윤하진과 윤기철은 아직"],
			["손전등 ×3을(를) 만들었어요.", "손전등 ×3을 만들었어요."],
			["권총 (희귀)을(를) 만들었어요.", "권총 (희귀)를 만들었어요."],
			["“윤하진이(가) 언젠가 마물이 된다”", "“윤하진이 언젠가 마물이 된다”"],
			["괄호 없는 문장 (그대로)", "괄호 없는 문장 (그대로)"]]:
		var got := KoreanText.fix(c[0])
		ok = _expect(got == c[1], "fix(%s) = %s, want %s" % [c[0], got, c[1]]) and ok
	# Journal keeps working through the shared helper
	ok = _expect(Journal.particle("지은", "가") == "이" and Journal.PARTICLES.has("을"), "Journal.particle uses KoreanText") and ok
	# Colony event lines come out fixed
	var ev: Dictionary = Colony._event(&"recovered", &"", "%s이(가) 회복했다" % "이소아")
	ok = _expect(ev.text == "이소아가 회복했다", "Colony._event fixes particles: %s" % ev.text) and ok
	ok = _expect(ResidentText.night_intro(&"bonfire", []).find("(가)") < 0, "night intro has no placeholder") and ok
	# Night events: every one has a mood line with no numbers or rules in it
	for file in ResourceLoader.list_directory(NIGHT_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load(NIGHT_DIR + file) as NightEventDef
		ok = _expect(def != null and def.tagline != "", "%s has no tagline" % file) and ok
		if def != null:
			var digits := RegEx.create_from_string("[0-9+−]")
			ok = _expect(digits.search(def.tagline) == null, "%s tagline has numbers: %s" % [file, def.tagline]) and ok
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr("test_korean_text: " + message)
	return cond
