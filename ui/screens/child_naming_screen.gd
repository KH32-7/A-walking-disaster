extends "res://ui/screens/welcome_screen.gd"
## 이름 짓기 (#125 part 2, C-15). Owner: Lane D. Design 08 "아이 맞이 — 이름 짓기 (입주 의식의 아이 판)".
## The 입주 의식 layout (D-13 welcome screen: full-body portrait left, step track + cream card
## right) with two steps: 이름 짓기 → 맞이하기. Opens when a child came to a family
## (Colony.child_arrived, ResidentEventFlow) and walks ResidentEventFlow.naming_queue().
## Colony.name_child() checks the name (its reason is shown), then Colony.complete_arrival() ends it.
## Esc = 나중에 (the child keeps waiting, back tomorrow).
## open_with({"resident_id": child_id, "method": Enums.ArrivalMethod}).

const CHILD_STEPS := [&"child_name", &"meet"]
const CHILD_STEP_NAMES := ["이름 짓기", "맞이하기"]

var method := -1


func _init() -> void:
	title_text = "이름 짓기"
	subtitle_text = "새 식구"
	show_back = false
	footer_keys = [["Enter", "다음"], ["Esc", "나중에"]]
	header_resources = []


func open_with(args: Dictionary) -> void:
	method = int(args.get("method", -1))
	super.open_with(args)


func _begin() -> void:
	if resident_id == &"" or not ResidentEventFlow.is_family_child(resident_id):
		var q := ResidentEventFlow.naming_queue()
		resident_id = q[0] if not q.is_empty() else &""
	step = 0
	_result = {}
	_error = ""
	_refresh()


func steps() -> Array:
	return CHILD_STEPS


func _refresh() -> void:
	MenuScreen.clear(_card)
	_next_button = null
	_nick_edit = null
	_track.set_steps(CHILD_STEP_NAMES, step)
	var r := Colony.get_resident(resident_id)
	if r.is_empty() or (step == 0 and not ResidentEventFlow.is_family_child(resident_id)):
		_who.text = ""
		_card.add_child(_title("이름을 지을 아이가 없어요"))
		_card.add_child(_text("가족에게 아이가 오면 여기서 함께 이름을 지어요."))
		_buttons([], "닫기", close)
		return
	_portrait.set_resident(resident_id)
	_who.text = String(r.get("name", ""))
	if step == 0:
		_step_child_name(r)
	else:
		_step_meet(r)


func _parents() -> Array[StringName]:
	return Colony.guardians_of(resident_id)


func _family_name() -> String:
	var p := _parents()
	return ResidentText.names_of(p) if not p.is_empty() else "가족"


func _born(r: Dictionary) -> bool:
	if method >= 0:
		return method == Enums.ArrivalMethod.BIRTH
	return int(r.get("age_stage", 0)) == Enums.AgeStage.BABY and String(r.get("name", "")) == ChildRules.CHILD_NAME


func _step_child_name(r: Dictionary) -> void:
	var born := _born(r)
	_card.add_child(_title("%s 가족에게 %s" % [_family_name(), "아기가 태어났어요" if born else "아이가 왔어요"]))
	var f := HFlowContainer.new()
	f.add_theme_constant_override(&"h_separation", 8)
	for id in _parents():
		f.add_child(ResidentSceneScreen.cream_chip(("보호자  " if not born else "부모  ") + ResidentText.call_name(Colony.get_resident(id))))
	_card.add_child(f)
	if not born:
		var bg := String(r.get("story", {}).get("background", ""))
		if bg != "":
			_card.add_child(_dim(bg))
	_card.add_child(_dim("가족과 함께 이름을 지어 주세요 — %d자까지" % ChildRules.NAME_MAX))
	_nick_edit = LineEdit.new()
	var cur := String(r.get("name", ""))
	_nick_edit.text = "" if cur == ChildRules.CHILD_NAME else cur
	_nick_edit.max_length = ChildRules.NAME_MAX
	_nick_edit.placeholder_text = "예: 하람, 보미"
	_nick_edit.add_theme_font_size_override(&"font_size", 26)
	_nick_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_nick_edit.custom_minimum_size = Vector2(520, 60)
	var field := StyleBoxFlat.new()
	field.bg_color = Color.WHITE
	field.border_color = UiTokens.TEXT_ON_CREAM
	field.set_border_width_all(2)
	field.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	field.content_margin_left = 16
	field.content_margin_right = 16
	for st in [&"normal", &"focus", &"read_only"]:
		_nick_edit.add_theme_stylebox_override(st, field)
	_nick_edit.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	_nick_edit.add_theme_color_override(&"font_placeholder_color", UiTokens.TEXT_ON_CREAM_DIM)
	_nick_edit.add_theme_color_override(&"caret_color", UiTokens.TEXT_ON_CREAM)
	_nick_edit.text_submitted.connect(func(_t: String) -> void: save_name())
	_card.add_child(_nick_edit)
	if _error != "":
		_card.add_child(_error_label(_error))
	_buttons([], "이 이름으로", save_name)


## Sends the typed name to Colony.name_child(); on success goes to 맞이하기.
func save_name(text: Variant = null) -> bool:
	var t: String = String(text) if text != null else (_nick_edit.text if _nick_edit != null else "")
	var res := Colony.name_child(resident_id, t)
	if res.get("ok", false):
		_error = ""
		step = 1
	else:
		_error = String(res.get("reason", ""))
	_refresh()
	return res.get("ok", false)


func _step_meet(r: Dictionary) -> void:
	var nm := String(r.get("name", ""))
	_card.add_child(_title("어서 와, %s" % nm))
	var p := _parents()
	if not p.is_empty():
		_card.add_child(_dim("%s의 말" % ResidentText.call_name(Colony.get_resident(p[0]))))
		var q := _text("“오늘부터 여기가 네 집이야.”")
		q.add_theme_font_size_override(&"font_size", 26)
		_card.add_child(q)
	var bed := StringName(r.get("bed_id", &""))
	_card.add_child(_dim("지낼 곳"))
	_card.add_child(_text("가족 숙소에서 가족과 함께 지내요." if bed != &"" else "임시 거처 — 가족 숙소에 빈 침상이 없어요."))
	if int(r.get("age_stage", 0)) == Enums.AgeStage.BABY:
		_card.add_child(_dim("아기는 돌봄이 필요해요. 돌봄방이 있으면 보호자가 일을 덜 쉬어요."))
	var more := ResidentEventFlow.naming_queue()
	more.erase(resident_id)
	_buttons([], "맞이하기" if more.is_empty() else "맞이하고 다음 아이", welcome_child)


## Colony.complete_arrival(), then the next child waiting or close.
func welcome_child() -> void:
	_result = Colony.complete_arrival(resident_id)
	var more := ResidentEventFlow.naming_queue()
	if more.is_empty():
		close()
		return
	resident_id = more[0]
	method = -1
	_begin()
