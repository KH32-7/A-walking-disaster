extends ResidentEventScreen
## 편견 소문 선택 (#125 part 1, C-16). Owner: Lane D. Design 08 "편견과 갈등".
## Opens on Colony.prejudice_rumor (ResidentEventFlow). The marked resident and the residents who
## hold the prejudice stand on the left; the centred cream dialogue asks what to do with three cream
## pills (PrejudiceRules.CHOICE_DEFEND / WATCH / SEPARATE) and Colony.choose_prejudice_response()
## answers. The step band on top shows 소문 → 선택 → 사건 → 해소.
## The trust / morale change shown is the difference Colony made, not a number computed here.
## The right card shows the chain (소문 → 선택 → 사건 → 해소) from Colony.prejudice_chain() and says
## plainly that a mark never turns anyone into a monster. Esc = 나중에 (the rumor stays, back tomorrow).
## open_with({"resident_id": target}); without one it takes the oldest rumor waiting.

const LINES := {
	PrejudiceRules.CHOICE_DEFEND: "…고마워. 그렇게 말해 준 사람은 처음이야.",
	PrejudiceRules.CHOICE_WATCH: "괜찮아. 내가 어떤 사람인지 보여 줄게.",
	PrejudiceRules.CHOICE_SEPARATE: "…알았어. 당분간 떨어져 지낼게.",
}
const HINTS := {
	PrejudiceRules.CHOICE_DEFEND: "신뢰 +%d · 사기 +%d" % [PrejudiceRules.DEFEND_TRUST, PrejudiceRules.DEFEND_MORALE],
	PrejudiceRules.CHOICE_WATCH: "그대로 둬요",
	PrejudiceRules.CHOICE_SEPARATE: "사기 %d · 임시 거처로" % PrejudiceRules.SEPARATE_MORALE,
}

var _chain: Dictionary = {}
var _result: Dictionary = {}


func _init() -> void:
	title_text = "소문"
	footer_keys = [["1~3", "고르기"], ["Esc", "나중에"]]
	header_resources = []


func _start() -> void:
	if resident_id == &"" or Colony.prejudice_chain(resident_id).is_empty():
		var q := ResidentEventFlow.rumor_queue()
		resident_id = q[0] if not q.is_empty() else &""
	_chain = Colony.prejudice_chain(resident_id)
	_result = {}
	set_subtitle("%d일차" % GameState.day)
	_band()
	if _chain.is_empty():
		MenuScreen.clear(people)
		dialog.say("", "지금은 기지에 도는 소문이 없어요.")
		dialog.set_notes([])
		dialog.set_choices([[&"close", "돌아간다"]])
		_refresh_column()
		return
	_draw()
	var target := ResidentText.call_name(resident())
	dialog.set_notes([["▼ 기지 전체 사기 %d" % PrejudiceRules.RUMOR_MORALE, UiTokens.WARN]])
	if ResidentEventFlow.chain_step_index(_chain) == 0:
		dialog.say("", "“%s이(가) 언젠가 마물이 된다”는 말이 기지에 돈다. 어떻게 할까?" % target)
		var choices: Array = []
		for c: StringName in PrejudiceRules.CHOICES:
			choices.append([c, ResidentEventFlow.CHOICE_NAMES[c], false, HINTS[c]])
		dialog.set_choices(choices)
	else:
		dialog.say("", "%s에 대한 소문 — %s." % [target,
			ResidentEventFlow.CHOICE_DONE.get(StringName(_chain.get("choice", &"")), "이미 골랐어요")])
		dialog.set_choices([[&"close", "돌아간다"]])
	_refresh_column()


## 소문 → 선택 → 사건 → 해소. A chain in the rumor step is at 선택 (the rumor already went round).
func _band() -> void:
	band.visible = not _chain.is_empty()
	if not _chain.is_empty():
		band.set_steps(ResidentEventFlow.PREJUDICE_STEPS, ResidentEventFlow.chain_step_index(_chain) + 1)


func _draw() -> void:
	var ids: Array = [resident_id]
	var chips := {resident_id: [["◆ 마물 흔적", UiTokens.INFO]]}
	for h in _chain.get("holders", []):
		if not Colony.get_resident(StringName(h)).is_empty():
			ids.append(StringName(h))
			chips[StringName(h)] = [["▲ 편견", UiTokens.WARN]]
	draw_people(ids.slice(0, 3), chips, Vector2(210, 250) if ids.size() > 2 else Vector2(230, 270))


func _on_choice(id: StringName) -> void:
	match id:
		&"close":
			close()
			return
		&"next":
			resident_id = &""
			_start()
			return
	if not id in PrejudiceRules.CHOICES or not _result.is_empty():
		return
	var r0 := resident()
	var trust0 := int(r0.get("trust", 0))
	var morale0 := int(r0.get("morale", 0))
	var res := Colony.choose_prejudice_response(resident_id, id)
	if not res.get("ok", false):
		dialog.set_notes([["✕ " + String(res.get("reason", "")), UiTokens.WARN]])
		return
	_result = res
	_chain = Colony.prejudice_chain(resident_id)
	_band()
	var r := resident()
	var notes: Array = []
	var dt := int(r.get("trust", 0)) - trust0
	var dm := int(r.get("morale", 0)) - morale0
	if dt != 0:
		notes.append([("▲ 신뢰 +%d" if dt > 0 else "▼ 신뢰 %d") % dt, UiTokens.GOOD if dt > 0 else UiTokens.WARN])
	if dm != 0:
		notes.append([("▲ 사기 +%d" if dm > 0 else "▼ 사기 %d") % dm, UiTokens.GOOD if dm > 0 else UiTokens.WARN])
	if id == PrejudiceRules.CHOICE_SEPARATE and StringName(r.get("bed_id", &"")) == &"":
		notes.append(["● 임시 거처로 옮겼어요", UiTokens.TEXT_DIM])
	notes.append(["◆ 며칠 안에 무슨 일이 생길 것 같아요", UiTokens.TEXT])
	dialog.say(ResidentText.call_name(r), LINES[id], resident_id)
	dialog.set_notes(notes)
	if ResidentEventFlow.rumor_queue().is_empty():
		dialog.set_choices([[&"close", "돌아간다"]])
	else:
		dialog.set_choices([[&"next", "다른 소문 보기"]])
	_refresh_column()


func _refresh_column() -> void:
	if column == null:
		return
	MenuScreen.clear(column)
	var v := card()
	if _chain.is_empty():
		v.add_child(card_title("도는 소문이 없어요"))
		v.add_child(card_text("마물 흔적이 있는 주민에 대한 소문이 돌면 여기서 어떻게 할지 골라요.", true))
		return
	v.add_child(card_text("소문", true, 14))
	v.add_child(card_title("“언젠가 마물이 된다”"))
	v.add_child(card_text("흔적이 있다고 마물이 되지는 않아요. 이 소문이 근거 없다는 걸 보여 줄 기회예요."))
	var holders: PackedStringArray = []
	for h in _chain.get("holders", []):
		var hr := Colony.get_resident(StringName(h))
		if not hr.is_empty():
			holders.append(ResidentText.call_name(hr))
	if not holders.is_empty():
		v.add_child(card_text("소문을 믿는 사람  ·  " + ", ".join(holders), true, 15))
	var now := ResidentEventFlow.chain_step_index(_chain) + 1
	if now > 1:
		v.add_child(ResidentEventScreen.mark_row("✓", ResidentEventFlow.CHOICE_DONE.get(StringName(_chain.get("choice", &"")), "")))
	if now == 2:
		v.add_child(card_text("며칠 안에 무슨 일이 생길 것 같아요.", true, 15))
	elif now == 3:
		v.add_child(card_text("편견을 가진 주민과 이야기할 밤을 기다려요.", true, 15))
	if now == 1:
		v.add_child(card_text("따로 지내게 하면 이야기가 더 늦게 풀려요.", true, 15))
