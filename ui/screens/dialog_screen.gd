extends ResidentSceneScreen
## Talk with a resident (D-13). Owner: Lane D. Design 07 "신뢰도", 14 "대화·이벤트".
## Portrait + line (max 2 lines) + up to three cream pill choices along the bottom, the trust card
## on the right. Talking goes through Colony.talk() / deep_talk() (C-12, 하루 1번); the trust change
## shown is the difference Colony reports. A resident who wants to leave (사기 위기) gets a
## "붙잡기" choice (Colony.persuade_to_stay). Gift opens the gift screen on top.
## open_with({"resident_id": id})

var _state: StringName = &"greet"
var _last_notes: Array = []


func _init() -> void:
	title_text = "대화"
	footer_keys = [["Esc", "뒤로"], ["1~3", "고르기"]]
	header_resources = []


func _start() -> void:
	var r := resident()
	set_subtitle(ResidentText.full_name(r))
	_state = &"greet"
	_last_notes = []
	_refresh_column()
	if r.is_empty():
		dialog.say("", "이 주민은 이제 기지에 없어요.")
		dialog.set_choices([[&"bye", "돌아가기"]])
		return
	if bool(r.get("leave_crisis", false)):
		dialog.say(ResidentText.call_name(r), ResidentText.line(r, &"crisis"), resident_id)
	else:
		dialog.say(ResidentText.call_name(r), ResidentText.line(r, &"greet"), resident_id)
	dialog.set_notes([])
	_set_choices()


func _set_choices() -> void:
	var r := resident()
	var acts := Colony.trust_actions(resident_id)
	var out: Array = []
	if bool(r.get("leave_crisis", false)):
		out.append([&"persuade", "붙잡는다", false, "신뢰 %d 이상이면 남아요" % NeedsRules.PERSUADE_TRUST])
	if _state == &"greet":
		if acts.get("deep_talk", false):
			out.append([&"deep_talk", "깊은 대화를 나눈다", false, "머무르는 날"])
		else:
			out.append([&"talk", "이야기를 나눈다", not acts.get("talk", false), "" if acts.get("talk", false) else "오늘은 했어요"])
	if out.size() < 2:
		out.append([&"gift", "선물을 준다", not acts.get("gift", false), "" if acts.get("gift", false) else "오늘은 줬어요"])
	out.append([&"bye", "그만 이야기한다"])
	dialog.set_choices(out)


func _on_choice(id: StringName) -> void:
	var r := resident()
	match id:
		&"talk", &"deep_talk":
			var before := int(r.get("trust", 0))
			var res: Dictionary = Colony.deep_talk(resident_id) if id == &"deep_talk" else Colony.talk(resident_id)
			_state = &"talked"
			r = resident()
			if not res.get("ok", false):
				dialog.say(ResidentText.call_name(r), ResidentText.line(r, &"busy"), resident_id)
				dialog.set_notes([[String(res.get("reason", "")), UiTokens.TEXT_DIM]])
			else:
				var story := Colony.unlocked_story(resident_id)
				dialog.say(ResidentText.call_name(r), ResidentText.line(r, id if id == &"deep_talk" else &"talk", story), resident_id)
				_last_notes = trust_notes(before, int(res.get("trust", before)))
				dialog.set_notes(_last_notes)
			_refresh_column()
			_set_choices()
		&"persuade":
			var res := Colony.persuade_to_stay(resident_id)
			r = resident()
			if res.get("ok", false):
				dialog.say(ResidentText.call_name(r), "…알았어. 조금만 더 있어 볼게.", resident_id)
				dialog.set_notes([["● 남기로 했어요", UiTokens.GOOD]])
			else:
				dialog.say(ResidentText.call_name(r), "미안. 아직은 네 말을 다 믿기 어려워.", resident_id)
				dialog.set_notes([["✕ " + String(res.get("reason", "")), UiTokens.WARN]])
			_refresh_column()
			_set_choices()
		&"gift":
			UI.open(&"gift", {"resident_id": resident_id})
		&"bye":
			close()


func _refresh_column() -> void:
	if column == null:
		return
	MenuScreen.clear(column)
	if resident().is_empty():
		return
	column.add_child(trust_card())


## [["▲ 신뢰 +3", colour], ["단계 경계 풀림", colour]] from the before / after values Colony reported.
static func trust_notes(before: int, after: int) -> Array:
	var d := after - before
	var notes: Array = []
	if d > 0:
		notes.append(["▲ 신뢰 +%d" % d, UiTokens.GOOD])
	elif d < 0:
		notes.append(["▼ 신뢰 %d" % d, UiTokens.WARN])
	else:
		notes.append(["● 신뢰 그대로", UiTokens.TEXT_DIM])
	var s0 := TrustRules.stage_of(before)
	var s1 := TrustRules.stage_of(after)
	if s1 > s0:
		notes.append(["◆ %s — %s" % [TrustRules.STAGE_NAMES[s1], TrustRules.STAGE_UNLOCKS[s1]], UiTokens.ACCENT])
	return notes
