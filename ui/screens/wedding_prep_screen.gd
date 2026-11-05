extends ResidentEventScreen
## 결혼식 준비 (#125 part 5, C-14). Owner: Lane D. Design 08 "청혼 → 결혼식".
## After the proposal night event (its result offers "결혼식 준비 보기") or from the resident detail.
## The engaged pair on the left; the right card shows Colony.wedding_status(): each cost line with
## what the base has, the family house, and anything else missing in words. The strip's first
## choice calls Colony.prepare_wedding(); it is disabled with the reason while something is missing.
## Prepared = the wedding is the next night (C-14 picks it). open_with({"a": id, "b": id}) or
## open_with({"resident_id": id}) for that resident and their partner.

var a: StringName = &""
var b: StringName = &""
var _status: Dictionary = {}
var _done := false


func _init() -> void:
	title_text = "결혼식 준비"
	footer_keys = [["1~2", "고르기"], ["Esc", "뒤로"]]
	header_resources = [&"food", &"cloth"]


func open_with(args: Dictionary) -> void:
	a = StringName(args.get("a", args.get("resident_id", args.get("id", &""))))
	b = StringName(args.get("b", &""))
	if b == &"" and a != &"":
		b = Colony.partner_of(a)
	if dialog != null:
		_start()


func _start() -> void:
	resident_id = a
	_done = false
	_status = Colony.wedding_status(a, b) if a != &"" and b != &"" else {}
	var state := ResidentEventFlow.wedding_state(_status) if not _status.is_empty() else &"none"
	dialog.set_notes([])
	if a == &"" or b == &"" or Colony.get_resident(a).is_empty() or Colony.get_resident(b).is_empty():
		set_subtitle("")
		MenuScreen.clear(people)
		dialog.say("", "결혼을 약속한 두 사람이 없어요.")
		dialog.set_choices([[&"close", "돌아간다"]])
		_refresh_column()
		return
	var na := ResidentText.call_name(Colony.get_resident(a))
	var nb := ResidentText.call_name(Colony.get_resident(b))
	set_subtitle("%s · %s" % [na, nb])
	var chip := ["◆ 결혼 약속", UiTokens.ACCENT] if state != &"none" else ["● 연인", UiTokens.TEXT]
	draw_people([a, b], {a: [chip], b: [chip]})
	match state:
		&"none":
			dialog.say("", "%s와(과) %s은(는) 아직 결혼을 약속하지 않았어요. 청혼은 밤 이벤트로 와요." % [na, nb])
			dialog.set_choices([[&"close", "돌아간다"]])
		&"ready":
			dialog.say(na, "다음 밤이면 우리 결혼식이야. 다들 와 줄 거지?", a)
			dialog.set_notes([["◆ 다음 밤 결혼식", UiTokens.ACCENT]])
			dialog.set_choices([[&"close", "돌아간다"]])
		_:
			dialog.say(na, "우리, 정말 결혼하는 거야. 준비를 도와줄래?", a)
			var ok := bool(_status.get("ok", false))
			var miss := ResidentEventFlow.wedding_missing(_status)
			dialog.set_choices([
				[&"prepare", "결혼식을 준비한다", not ok, MenuScreen.cost_text(_status.get("cost", {})) if ok else (miss[0] if miss.size() == 1 else "모자란 것 %d개" % miss.size())],
				[&"later", "나중에 준비한다"],
			])
	_refresh_column()


func _on_choice(id: StringName) -> void:
	match id:
		&"close", &"later":
			close()
		&"prepare":
			if _done:
				return
			var cost: Dictionary = _status.get("cost", {})
			if Colony.prepare_wedding(a, b):
				_done = true
				_status = Colony.wedding_status(a, b)
				dialog.say(ResidentText.call_name(Colony.get_resident(b)), "고마워. 다음 밤, 모두 와 줘.", b)
				dialog.set_notes([["◆ 다음 밤 결혼식", UiTokens.ACCENT], ["▼ " + MenuScreen.cost_text(cost), UiTokens.TEXT_DIM]])
				dialog.set_choices([[&"close", "좋아요"]])
				refresh_header()
				_refresh_column()
			else:
				dialog.set_notes([["✕ 준비하지 못했어요", UiTokens.WARN]])


func _refresh_column() -> void:
	if column == null:
		return
	MenuScreen.clear(column)
	var v := card()
	if _status.is_empty():
		v.add_child(card_title("준비할 결혼식이 없어요"))
		v.add_child(card_text("연인이 청혼하면 여기서 결혼식을 준비해요.", true))
		return
	var state := ResidentEventFlow.wedding_state(_status)
	v.add_child(card_text("결혼식", true, 14))
	match state:
		&"none":
			v.add_child(card_title("아직 청혼 전이에요"))
			v.add_child(card_text("연인이 된 지 오래되고 관계가 깊어지면 청혼하는 밤이 와요.", true))
			return
		&"ready":
			v.add_child(card_title("준비 끝 — 다음 밤 결혼식"))
		_:
			v.add_child(card_title("준비할 것"))
	var cost: Dictionary = _status.get("cost", {})
	for res in cost:
		var need := int(cost[res])
		var have := Economy.get_amount(StringName(res))
		var enough := state == &"ready" or have >= need
		v.add_child(ResidentEventScreen.mark_row("✓" if enough else "✕", "%s %d  ·  지금 %d" % [MenuScreen.resource_name(StringName(res)), need, have]
			if state != &"ready" else "%s %d  ·  냈어요" % [MenuScreen.resource_name(StringName(res)), need], enough,
			UiTokens.TEXT_ON_CREAM if enough else UiTokens.DANGER.darkened(0.2)))
	var house := StringName(_status.get("house_uid", &""))
	if state == &"ready":
		v.add_child(ResidentEventScreen.mark_row("✓", "가족 숙소  ·  두 사람이 함께 쓸 곳을 맡아 뒀어요"))
	elif house != &"":
		v.add_child(ResidentEventScreen.mark_row("✓", "빈 가족 숙소  ·  %s 하나가 비어 있어요" % _building_name(house)))
	else:
		v.add_child(ResidentEventScreen.mark_row("✕", "빈 가족 숙소  ·  건설에서 가족 숙소를 지어요", true, UiTokens.DANGER.darkened(0.2)))
	# Anything else Colony says is missing (resources and the house are listed above).
	for m in ResidentEventFlow.wedding_missing(_status):
		var t := String(m)
		var listed := t == "빈 가족 숙소 필요"
		for res in cost:
			listed = listed or t.begins_with(MenuScreen.resource_name(StringName(res)) + " ")
		if not listed:
			v.add_child(ResidentEventScreen.mark_row("✕", t, true, UiTokens.DANGER.darkened(0.2)))
	v.add_child(HSeparator.new())
	v.add_child(card_text("준비하면 다음 밤에 결혼식을 올려요. 결혼식 다음 날은 축제라 일을 쉬고 모두 기운이 나요.", true, 15))


static func _building_name(uid: StringName) -> String:
	var bd := Colony.get_building(uid)
	var def := BaseDB.get_building(StringName(bd.get("def_id", &""))) if not bd.is_empty() else null
	return def.display_name if def != null else "가족 숙소"
