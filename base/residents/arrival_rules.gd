class_name ArrivalRules
## 입주 의식 (C-13, docs/design/07-residents.md "입주 의식"). A rescued survivor who moves in goes
## through: 1 도착 연출(주민들이 마중) → 2 이름 확인·별명 → 3 외형 프리셋 → 4 침상 → 5 첫 대화.
## The screen is Lane D (D-13); Colony keeps the choices. Numbers are 가안 and live here.

const STEPS: Array[StringName] = [&"welcome", &"name", &"appearance", &"bed", &"first_talk"]
## Same limit as the survivor pool templates (A-16).
const NICKNAME_MAX := ResidentTemplate.NICKNAME_MAX
## Keys of a resident's `appearance` (AppearancePreset / CharacterLook, D-09).
## Colours are stored as html strings ("#3b2a22") so saves stay plain JSON.
const COLOR_KEYS: Array[String] = ["hair_color", "outfit_color", "outfit_accent", "skin"]
const HAIR_STYLES: Array[String] = ["short", "bob", "long", "tied", "cap"]
const PRESET_DIR := "res://data/ui/appearance"


## Cleans a nickname: trims spaces. Returns {"ok", "nickname", "reason"}.
static func check_nickname(text: String, banned: PackedStringArray) -> Dictionary:
	var nick := text.strip_edges()
	if nick.length() > NICKNAME_MAX:
		return {"ok": false, "nickname": nick, "reason": "별명은 %d자까지" % NICKNAME_MAX}
	for word in banned:
		if word != "" and nick.to_lower().contains(word.to_lower()):
			return {"ok": false, "nickname": nick, "reason": "쓸 수 없는 말이 들어 있다"}
	return {"ok": true, "nickname": nick, "reason": ""}


## Validates and normalizes an appearance choice. Returns {"ok", "appearance", "reason"}.
## Accepts Color or html strings for colours; unknown keys are dropped.
static func clean_appearance(src: Dictionary) -> Dictionary:
	var out := {}
	if src.has("preset"):
		var preset := StringName(src["preset"])
		if not ResourceLoader.exists("%s/%s.tres" % [PRESET_DIR, preset]):
			return {"ok": false, "appearance": {}, "reason": "없는 외형 프리셋: %s" % preset}
		out["preset"] = preset
	if src.has("hair"):
		var hair := String(src["hair"])
		if not hair in HAIR_STYLES:
			return {"ok": false, "appearance": {}, "reason": "없는 머리 모양: %s" % hair}
		out["hair"] = hair
	for key in COLOR_KEYS:
		if not src.has(key):
			continue
		var v: Variant = src[key]
		if v is Color:
			out[key] = "#" + (v as Color).to_html(false)
		elif v is String and Color.html_is_valid(v):
			out[key] = "#" + Color.html(v).to_html(false)
		else:
			return {"ok": false, "appearance": {}, "reason": "색이 올바르지 않다: %s" % key}
	return {"ok": true, "appearance": out, "reason": ""}


## The stored appearance with colours turned back into Color, for CharacterLook.apply().
static func to_look(appearance: Dictionary) -> Dictionary:
	var look := appearance.duplicate()
	for key in COLOR_KEYS:
		if look.get(key) is String and Color.html_is_valid(look[key]):
			look[key] = Color.html(look[key])
	return look
