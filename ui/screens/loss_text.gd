class_name LossText
extends RefCounted
## Short words for loss (#125 part 3, C-20): grief days, stranded, missing, the sortie block reason,
## death causes. Owner: Lane D. Used by the residents list / detail, sortie prep, funeral and memorial.
## Every state is a word with a shape mark (◇ 슬픔, △ 고립, ◆ 실종), never colour alone.
## Numbers come from Colony (grief_days, stranded_residents, sortie_block_reason); nothing is computed.

const CAUSES := {&"raid": "습격으로", &"sickness": "병으로", &"debug": "", &"": ""}

## Residents announced missing this session (Colony.resident_missing). Colony has no getter that lists
## missing residents yet (request to C), so a loaded save only shows the ones seen since start.
static var missing_seen: Array[StringName] = []


static func note_missing(resident_id: StringName) -> void:
	if not resident_id in missing_seen:
		missing_seen.append(resident_id)


## "◇ 슬픔 3일" or "" when the resident is not grieving.
static func grief_tag(r: Dictionary) -> String:
	var d := int(r.get("grief_days", 0))
	return "◇ 슬픔 %d일" % d if d > 0 else ""


## "남은 기한 2일" / "기한 없음" (-1).
static func strand_days(days_left: int) -> String:
	return "기한 없음" if days_left < 0 else "남은 기한 %d일" % days_left


## [{resident_id, name, kind: &"stranded"|&"missing", text}] — people who belong to the base but are
## not in it. Stranded from Colony.stranded_residents(), missing from missing_seen.
static func absent_rows() -> Array:
	var out: Array = []
	for s: Dictionary in Colony.stranded_residents():
		var id := StringName(s.get("resident_id", &""))
		var region := FieldHud.region_display_name(StringName(s.get("region_id", &"")))
		out.append({"resident_id": id, "name": display_name(id), "kind": &"stranded",
			"text": "△ 고립 · %s · %s" % [region if region != "" else "필드", strand_days(int(s.get("days_left", -1)))]})
	for id in missing_seen:
		var r := Colony.get_resident(id)
		if r.is_empty() or int(r.get("status", 0)) != Enums.ResidentStatus.MISSING:
			continue
		out.append({"resident_id": id, "name": display_name(id), "kind": &"missing", "text": "◆ 실종 · 끝내 찾지 못했어요"})
	return out


## "" when the resident can go; otherwise the reason with a mark.
static func sortie_block(resident_id: StringName) -> String:
	var why := Colony.sortie_block_reason(resident_id)
	return "" if why == "" else "■ " + why


static func display_name(resident_id: StringName) -> String:
	var r := Colony.get_resident(resident_id)
	var nm := String(r.get("name", ""))
	return nm if nm != "" else String(resident_id)


## "12일차 · 습격으로" for a memorial entry.
static func memorial_line(m: Dictionary) -> String:
	var cause := String(CAUSES.get(StringName(m.get("cause", &"")), ""))
	return "%d일차%s" % [int(m.get("day", 0)), " · " + cause if cause != "" else ""]


## The one-line story for the funeral: the background, else the first fragment, else the job.
static func story_line(resident_id: StringName) -> String:
	var r := Colony.get_resident(resident_id)
	var story: Dictionary = r.get("story", {})
	var bg := String(story.get("background", "")).strip_edges()
	if bg != "":
		var cut := bg.find(".")
		return bg.substr(0, cut + 1) if cut > 0 else bg
	var frags: Array = story.get("fragments", [])
	if not frags.is_empty():
		return String(frags[0])
	return "%d일차부터 함께 지냈어요." % int(r.get("joined_day", 1))


## One short icon + text state for a resident card (UI 재설계: 카드에 상태 한 줄, 새 판 없이).
## Order: 출산 대기 (■) → 슬픔 (◇). Absent residents use absent_rows() instead. "" = nothing to say.
static func card_state(resident_id: StringName) -> String:
	var block := sortie_block(resident_id)
	if block != "":
		return block
	return grief_tag(Colony.get_resident(resident_id))


## The mark FaceDot shows for a resident ("" = none).
static func face_mark(resident_id: StringName) -> String:
	var r := Colony.get_resident(resident_id)
	match int(r.get("status", Enums.ResidentStatus.ACTIVE)):
		Enums.ResidentStatus.STRANDED:
			return "△"
		Enums.ResidentStatus.MISSING:
			return "◆"
		Enums.ResidentStatus.DEAD:
			return "†"
	if sortie_block(resident_id) != "":
		return "■"
	return "◇" if int(r.get("grief_days", 0)) > 0 else ""
