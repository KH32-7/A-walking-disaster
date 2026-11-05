extends MenuScreen
## Raid warning (D-14). Owner: Lane D. Design 10 "예고"·"직접 방어전", 14 "습격 경보·결과",
## UI_RULES §9: the guide card's DANGER variant.
## Shows direction (compass + words), size (type + strength), time left (warning_sec) and the expected
## outcome band from Colony.predict_raid(). Choices: 직접 방어 (C-17, RaidFlow.DIRECT_API) or
## 자동 판정으로 넘기기 (Colony.resolve_raid(raid, PLAYED): player at base, defense bonus).
## args: {"raid": raid_warning info}

var raid: Dictionary = {}
var prediction: Dictionary = {}
var _direct_btn: Button
var _auto_btn: Button
var _chosen := false


func _init() -> void:
	show_back = false
	title_text = "습격 경보"
	subtitle_text = "%d일차 %s" % [GameState.day, "낮"]
	header_resources = []
	footer_keys = [["D", "직접 방어"], ["Enter", "자동 판정으로 넘기기"]] if RaidFlow.can_direct() \
		else [["Enter", "자동 판정으로 넘기기"]]


func open_with(args: Dictionary) -> void:
	if args.has("raid"):
		raid = args.raid
	subtitle_text = "%d일차 %s" % [GameState.day, RaidFlow.time_text(raid)]
	if is_inside_tree():
		set_subtitle(subtitle_text)


## Esc does nothing here: a raid needs an answer (closes_on_cancel = false in the ScreenDef).
func close() -> void:
	pass


func _build_body(b: Control) -> void:
	if raid.is_empty() and UI.get_node_or_null(^"RaidFlow") != null:
		raid = UI.get_node(^"RaidFlow").last_warning
	prediction = Colony.predict_raid(raid) if not raid.is_empty() else {}
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(center)
	var card := RaidWidgets.danger_card("마물 무리가 기지로 오고 있어요", 900)
	center.add_child(card[0])
	var cv: VBoxContainer = card[1]
	var band: HBoxContainer = card[2]
	var eta := MenuScreen.label(("남은 시간  " + RaidFlow.eta_text(raid)) if RaidFlow.eta_text(raid) != "지금" else "지금 시작", &"LabelNumber", 22)
	eta.add_theme_color_override(&"font_color", UiTokens.TEXT)
	band.add_child(eta)

	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 28)
	var compass := RaidWidgets.Compass.new()
	compass.directions = raid.get("directions", [])
	compass.custom_minimum_size = Vector2(190, 190)
	top.add_child(compass)
	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 10)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dirs: Array = raid.get("directions", [])
	info.add_child(RaidWidgets.cream_row("방향", "%s  (%d방향)" % [RaidFlow.directions_text(dirs), dirs.size()], UiTokens.DANGER))
	var type := StringName(raid.get("type", &""))
	var size_text := "%s · 강도 %.0f" % [RaidFlow.type_name(type), float(raid.get("strength", 0.0))]
	if bool(raid.get("small", false)):
		size_text += " · 소규모"
	info.add_child(RaidWidgets.cream_row("규모", size_text))
	if RaidFlow.type_note(type) != "":
		var note := MenuScreen.label(RaidFlow.type_note(type), &"LabelOnCreamDim", 14)
		note.custom_minimum_size = Vector2(0, 0)
		var nh := HBoxContainer.new()
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(112, 0)
		nh.add_child(pad)
		nh.add_child(note)
		info.add_child(nh)
	info.add_child(RaidWidgets.cream_row("남은 시간", _eta_long()))
	var fam := int(raid.get("family", Enums.Element.NONE))
	if fam != Enums.Element.NONE:
		info.add_child(RaidWidgets.cream_row("계열", "%s 계열" % UiTokens.ELEMENT_NAMES[fam]))
	top.add_child(info)
	cv.add_child(top)

	cv.add_child(_rule())
	var ph := HBoxContainer.new()
	var pt := MenuScreen.label("예상 결과", &"LabelOnCream", 17)
	pt.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	pt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pt)
	if not prediction.is_empty():
		var likely := int(prediction.get("likely", Enums.RaidOutcome.WIN))
		var lk := MenuScreen.label("%s %s 가능성이 커요" % [RaidFlow.outcome_glyph(likely), RaidFlow.outcome_name(likely)], &"LabelOnCream", 17)
		lk.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
		ph.add_child(lk)
	cv.add_child(ph)
	var odds := RaidWidgets.OddsBar.new()
	odds.prediction = prediction
	odds.custom_minimum_size = Vector2(820, 60)
	cv.add_child(odds)
	cv.add_child(MenuScreen.label(_defense_line(), &"LabelOnCreamDim", 14))

	cv.add_child(_rule())
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override(&"separation", 20)
	var direct_ok := RaidFlow.can_direct()
	var dcol := _choice("직접 방어", "D", &"ButtonPrimary" if direct_ok else &"ButtonCancel",
		"기지에서 3파를 직접 막아요. 파 사이 20초 동안 함정과 경비 자리를 정해요." if direct_ok
		else "직접 방어전은 아직 열리지 않았어요.")
	_direct_btn = dcol[1]
	_direct_btn.disabled = not direct_ok
	_direct_btn.pressed.connect(_choose.bind(true))
	choices.add_child(dcol[0])
	var bonus := roundi((RaidRules.PLAYED_BONUS - 1.0) * 100.0)
	var acol := _choice("자동 판정으로 넘기기", "Enter", &"ButtonSecondary" if direct_ok else &"ButtonPrimary",
		"지금 방어력으로 바로 판정해요. 기지에 있어서 방어 +%d%%." % bonus)
	_auto_btn = acol[1]
	_auto_btn.pressed.connect(_choose.bind(false))
	choices.add_child(acol[0])
	cv.add_child(choices)


func _choice(text: String, key: String, variation: StringName, note: String) -> Array:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn := MenuScreen.button(text, variation)
	btn.custom_minimum_size = Vector2(0, 52)
	v.add_child(btn)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	var chip := KeyChip.new(key, KeyChip.Style.DARK)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(chip)
	var n := MenuScreen.label(note, &"LabelOnCreamDim", 14)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	v.add_child(h)
	return [v, btn]


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiTokens.TEXT_ON_CREAM, 0.15)
	r.custom_minimum_size = Vector2(0, 1)
	return r


func _eta_long() -> String:
	var sec := float(raid.get("warning_sec", 0.0))
	if sec <= 0.0:
		return "지금 몰려오는 중" if int(raid.get("time", 0)) == Enums.RaidTime.DAY else "오늘 밤, 지금"
	return "%s 뒤 도착" % RaidFlow.eta_text(raid)


## "경비 2명 · 시설 4곳 · 지금 방어 18.1 / 강도 38" from Colony.defense_breakdown() (read only).
func _defense_line() -> String:
	if not Colony.has_method(&"defense_breakdown"):
		return ""
	var d: Dictionary = Colony.call(&"defense_breakdown")
	var r := ""
	if not prediction.is_empty():
		r = "  ·  방어 비율 %.2f ~ %.2f" % [float(prediction.ratio_min), float(prediction.ratio_max)]
	return "경비 %d명 · 방어 시설 %d곳 · 지금 방어 %.1f%s" % [(d.get("guards", {}) as Dictionary).size(),
		(d.get("facilities", {}) as Dictionary).size(), float(d.get("total", 0.0)), r]


func _choose(direct: bool) -> void:
	if _chosen or (direct and not RaidFlow.can_direct()):
		return
	_chosen = true
	UI.close(&"raid_warning")
	RaidFlow.choose(raid, direct)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()  # first: the action may close this screen
		_choose(false)
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_D:
		_choose(true)
		get_viewport().set_input_as_handled()
