extends Control
## Emergency return choice in the field (D-14). Owner: Lane D. Design 10 "출격 중 습격과 긴급 귀환",
## 02 "긴급 귀환", 14 "시간 제한이 있는 선택은 없습니다(긴급 귀환도 선택 전까지 게임이 멈춤)".
## Opened by RaidFlow when B-22's EmergencyReturn offers a return (return_offered / state OFFERED).
## The game is paused (ScreenDef pauses_game). Answers with EmergencyReturn.answer(go_back), which
## emits emergency_return_requested itself; the expected outcome comes from Colony.predict_raid().
## args: {"raid": raid_warning info, "node": EmergencyReturn (optional; looked up by group)}

var raid: Dictionary = {}
var node: Node = null
var prediction: Dictionary = {}
var _back_btn: Button
var _stay_btn: Button
var _answered := false


func open_with(args: Dictionary) -> void:
	raid = args.get("raid", raid)
	node = args.get("node", node)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.0, 0.0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	if node == null:
		node = get_tree().get_first_node_in_group(&"field_emergency_return")
	prediction = Colony.predict_raid(raid) if not raid.is_empty() else {}
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := RaidWidgets.danger_card("기지 습격 경보", 880)
	center.add_child(card[0])
	var cv: VBoxContainer = card[1]
	var band: HBoxContainer = card[2]
	var eta := MenuScreen.label("습격까지  " + RaidFlow.eta_text(raid) if RaidFlow.eta_text(raid) != "지금" else "지금 습격 중", &"LabelNumber", 22)
	band.add_child(eta)

	var radio := HBoxContainer.new()
	radio.add_theme_constant_override(&"separation", 12)
	var who := MenuScreen.label("방송실 지기", &"LabelOnCream", 18)
	who.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	radio.add_child(who)
	var said := MenuScreen.label("“기지가 습격받고 있어! 돌아올 수 있겠나?”", &"LabelOnCream", 20)
	radio.add_child(said)
	cv.add_child(radio)
	var dirs: Array = raid.get("directions", [])
	var info := HBoxContainer.new()
	info.add_theme_constant_override(&"separation", 26)
	var compass := RaidWidgets.Compass.new()
	compass.directions = dirs
	compass.custom_minimum_size = Vector2(150, 150)
	info.add_child(compass)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override(&"separation", 8)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iv.add_child(RaidWidgets.cream_row("방향", RaidFlow.directions_text(dirs), UiTokens.DANGER))
	var strength := float(raid.get("strength", 0.0))
	iv.add_child(RaidWidgets.cream_row("규모", "%s%s" % [RaidFlow.type_name(StringName(raid.get("type", &""))),
		(" · 강도 %.0f" % strength) if strength > 0.0 else ""]))
	if not prediction.is_empty():
		var likely := int(prediction.get("likely", Enums.RaidOutcome.WIN))
		iv.add_child(RaidWidgets.cream_row("예상 결과", "%s %s (지금 방어력, 내가 없을 때)" % [
			RaidFlow.outcome_glyph(likely), RaidFlow.outcome_name(likely)]))
		var odds := RaidWidgets.OddsBar.new()
		odds.prediction = prediction
		odds.custom_minimum_size = Vector2(560, 58)
		iv.add_child(odds)
	info.add_child(iv)
	cv.add_child(info)
	var rule := ColorRect.new()
	rule.color = Color(UiTokens.TEXT_ON_CREAM, 0.15)
	rule.custom_minimum_size = Vector2(0, 1)
	cv.add_child(rule)

	var choices := HBoxContainer.new()
	choices.add_theme_constant_override(&"separation", 24)
	var a := _choice("긴급 귀환", "Y", &"ButtonPrimary", [
		"가장 가까운 탈출 지점까지 길을 보여 줘요.",
		"탈출 대기 시간이 0초가 돼요.",
		"가방을 그대로 들고 방어전 2파부터 함께 싸워요. 1파는 자동 판정."])
	_back_btn = a[1]
	_back_btn.pressed.connect(_answer.bind(true))
	choices.add_child(a[0])
	var b := _choice("계속 탐색", "N", &"ButtonCancel", [
		"습격은 자동 판정으로 처리돼요 (기지에 없음).",
		"결과는 탈출한 뒤 결과 화면에서 봐요."])
	_stay_btn = b[1]
	_stay_btn.pressed.connect(_answer.bind(false))
	choices.add_child(b[0])
	cv.add_child(choices)
	cv.add_child(MenuScreen.label("고를 때까지 게임이 멈춰 있어요.", &"LabelOnCreamDim", 14))
	_back_btn.grab_focus.call_deferred()


func _choice(text: String, key: String, variation: StringName, lines: Array) -> Array:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	var chip := KeyChip.new(key, KeyChip.Style.DARK)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chip)
	var btn := MenuScreen.button(text, variation)
	btn.custom_minimum_size = Vector2(0, 52)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(btn)
	v.add_child(h)
	for l: String in lines:
		var n := MenuScreen.label("·  " + l, &"LabelOnCream", 15)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size = Vector2(380, 0)
		v.add_child(n)
	return [v, btn]


func _answer(go_back: bool) -> void:
	if _answered:
		return
	_answered = true
	UI.close(&"emergency_return")
	if node != null and is_instance_valid(node) and node.has_method(&"answer"):
		node.call(&"answer", go_back)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_Y:
			_answer(true)
			get_viewport().set_input_as_handled()
		KEY_N:
			_answer(false)
			get_viewport().set_input_as_handled()
