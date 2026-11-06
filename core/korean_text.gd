class_name KoreanText
extends RefCounted
## Korean particles (조사) that fit the word before them. Shared by Journal templates, Colony event
## lines, notifications and screens, so nothing shows "윤하진이(가)" (QA 2026-11-06).
##
##   KoreanText.particle("윤하진", "가")      -> "이"
##   KoreanText.fix("%s이(가) 왔다" % name)   -> "윤하진이 왔다" / "이소아가 왔다"
##
## fix() rewrites the placeholder forms 이(가) 을(를) 은(는) 과(와) 와(과) (으)로 (이)에요 by the last
## letter before them. Closing quotes, brackets and spaces are skipped ("‘손전등’을(를)" -> 을/를
## by 등). Digits are read in Korean (3 = 삼 -> 을). Latin letters and other signs count as a vowel.

const PARTICLES := {
	"이": ["이", "가"], "가": ["이", "가"],
	"을": ["을", "를"], "를": ["을", "를"],
	"은": ["은", "는"], "는": ["은", "는"],
	"과": ["과", "와"], "와": ["과", "와"],
	"아": ["아", "야"], "야": ["아", "야"],
	"이랑": ["이랑", "랑"], "랑": ["이랑", "랑"],
	"으로": ["으로", "로"], "로": ["으로", "로"],
	"이에요": ["이에요", "예요"], "예요": ["이에요", "예요"],
}
## Final consonant (jongseong index, 0 = none) of digits read in Korean: 영 일 이 삼 사 오 육 칠 팔 구.
const DIGIT_FINALS := [21, 8, 0, 16, 0, 0, 1, 8, 8, 0]
const FINAL_RIEUL := 8
## Placeholder -> PARTICLES key.
const PLACEHOLDERS := {
	"이(가)": "이", "을(를)": "을", "은(는)": "은", "과(와)": "과", "와(과)": "과",
	"(으)로": "으로", "(이)에요": "이에요",
}
## Skipped when looking for the letter a particle attaches to.
const SKIP := " )]}’”\"'»》」』"


## The form of `which` (either form: "이" or "가") that fits after `word`.
static func particle(word: String, which: String) -> String:
	if which == "" or not PARTICLES.has(which):
		return which
	var forms: Array = PARTICLES[which]
	var final := final_consonant(word)
	if forms[0] == "으로":
		return forms[1] if final == 0 or final == FINAL_RIEUL else forms[0]
	return forms[1] if final == 0 else forms[0]


## `text` with every placeholder particle replaced by the form that fits the word before it.
static func fix(text: String) -> String:
	if text.find("(") < 0:
		return text
	for ph: String in PLACEHOLDERS:
		var at := text.find(ph)
		while at >= 0:
			var form := particle(text.substr(0, at), PLACEHOLDERS[ph])
			text = text.substr(0, at) + form + text.substr(at + ph.length())
			at = text.find(ph, at + form.length())
	return text


## Jongseong index (0 = none) of the last letter of `word`, skipping closing quotes/brackets/spaces.
static func final_consonant(word: String) -> int:
	var i := word.length() - 1
	while i >= 0 and SKIP.contains(word[i]):
		i -= 1
	if i < 0:
		return 0
	var code := word.unicode_at(i)
	if code >= 0xAC00 and code <= 0xD7A3:
		return (code - 0xAC00) % 28
	if code >= 0x30 and code <= 0x39:
		return DIGIT_FINALS[code - 0x30]
	return 0
