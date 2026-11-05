extends ResidentSceneScreen
## Give a resident something from storage (D-13). Owner: Lane D. Design 07 "신뢰도" (선물 하루 1번).
## Right column: storage list (Economy, amount > 0, no special items) and a cream card with the
## pick and the yellow "주기" button. The reaction comes back from Colony.give_gift() and shows as a
## line, a shaped mark (▲ 좋아해요 / ● 고마워해요 / ▼ 싫어해요) and the trust change. Before giving,
## only likes the player already learned (Colony.known_likes) are marked — no spoilers.
## open_with({"resident_id": id})

const ROW_H := 50

var _sel: StringName = &""
var _given: Dictionary = {}
var _give_button: Button
var _list: VBoxContainer


func _init() -> void:
	title_text = "선물"
	footer_keys = [["Esc", "뒤로"], ["클릭", "고르기"], ["Enter", "주기"]]
	header_resources = [&"food", &"meal", &"wood", &"cloth", &"parts"]


func _start() -> void:
	var r := resident()
	set_subtitle(ResidentText.full_name(r))
	dialog.enter_picks_single = false
	_given = {}
	var items := gift_ids()
	if _sel == &"" or not _sel in items:
		_sel = items[0] if not items.is_empty() else &""
	_refresh_column()
	if r.is_empty():
		dialog.say("", "이 주민은 이제 기지에 없어요.")
		dialog.set_choices([[&"bye", "돌아가기"]])
		return
	var acts := Colony.trust_actions(resident_id)
	if acts.get("gift", false):
		dialog.say(ResidentText.call_name(r), "응? 나 주려고 가져온 거야?", resident_id)
		dialog.set_notes([])
	else:
		dialog.say(ResidentText.call_name(r), "오늘은 벌써 받았잖아. 마음만 받을게.", resident_id)
		dialog.set_notes([["오늘은 이미 선물했어요", UiTokens.TEXT_DIM]])
	_set_choices()


func _set_choices() -> void:
	var out: Array = []
	if not UI.is_open(&"dialog"):
		var can_talk: bool = Colony.trust_actions(resident_id).get("talk", false)
		out.append([&"talk", "이야기를 나눈다", not can_talk, "" if can_talk else "오늘은 했어요"])
	out.append([&"bye", "돌아간다"])
	dialog.set_choices(out)


## Storage resources the player can give: in stock, not special (keys, keepsakes). Sorted: known
## likes first, then by name.
func gift_ids() -> Array:
	var out: Array = []
	for id: StringName in Economy.defs:
		var def: ResourceDef = Economy.defs[id]
		if def.category == Enums.ResourceCategory.SPECIAL or Economy.get_amount(id) <= 0:
			continue
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var la := known_liked(a)
		var lb := known_liked(b)
		if la != lb:
			return la
		return MenuScreen.resource_name(a) < MenuScreen.resource_name(b))
	return out


## True when the resource matches a like the player already knows (tag or resource id, C-12 tags).
func known_liked(res_id: StringName) -> bool:
	for like in Colony.known_likes(resident_id):
		if like == res_id or res_id in TrustRules.GIFT_TAGS.get(like, []):
			return true
	return false


func _refresh_column() -> void:
	if column == null:
		return
	MenuScreen.clear(column)
	if resident().is_empty():
		return
	var items := gift_ids()
	var pn := MenuScreen.panel("창고", "%d종" % items.size())
	(pn[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(pn[0])
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	(pn[1] as VBoxContainer).add_child(sc)
	if items.is_empty():
		_list.add_child(MenuScreen.label("창고에 줄 만한 것이 없어요.", &"LabelDim", 15))
	for id: StringName in items:
		_list.add_child(_row(id))
	column.add_child(_card())


func _row(id: StringName) -> Control:
	var b := Button.new()
	b.theme_type_variation = &"ButtonCancel"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_H)
	var sel := id == _sel
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.1) if sel else Color(1, 1, 1, 0.03)
	box.border_color = UiTokens.ACCENT if sel else Color(1, 1, 1, 0.1)
	box.set_border_width_all(2 if sel else 1)
	box.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	for s in [&"normal", &"hover", &"pressed", &"focus"]:
		b.add_theme_stylebox_override(s, box)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16
	h.offset_right = -16
	h.add_theme_constant_override(&"separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := MenuScreen.label(MenuScreen.resource_name(id), &"LabelSection", 17)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(nm)
	if known_liked(id):
		var like := MenuScreen.label("▲ 좋아함", &"LabelHud", 14)
		like.add_theme_color_override(&"font_color", UiTokens.ACCENT)
		like.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(like)
	var n := MenuScreen.label("×%d" % Economy.get_amount(id), &"LabelNumber", 18)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(n)
	b.add_child(h)
	b.pressed.connect(func() -> void:
		_sel = id
		_refresh_column())
	return b


func _card() -> Control:
	var cc := MenuScreen.cream_card(0)
	var v: VBoxContainer = cc[1]
	var r := resident()
	var can: bool = Colony.trust_actions(resident_id).get("gift", false)
	if _given.get("ok", false):
		var rc: Array = ResidentText.REACTIONS.get(StringName(_given.reaction), ["●", ""])
		v.add_child(MenuScreen.label("%s에게 %s을(를) 줬어요" % [ResidentText.call_name(r), MenuScreen.resource_name(_given.res)],
			&"LabelOnCream", 20))
		v.add_child(MenuScreen.label("%s %s" % [rc[0], rc[1]], &"LabelOnCream", 18))
	elif _sel == &"":
		v.add_child(MenuScreen.label("줄 것을 골라 주세요.", &"LabelOnCream", 18))
	else:
		var t := MenuScreen.label("%s에게 %s 1개를 줄까요?" % [ResidentText.call_name(r), MenuScreen.resource_name(_sel)],
			&"LabelOnCream", 20)
		t.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(t)
		var n := Economy.get_amount(_sel)
		v.add_child(MenuScreen.label("창고  %d → %d" % [n, n - 1], &"LabelOnCreamDim", 15))
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	_give_button = MenuScreen.button("주기", &"ButtonPrimary")
	_give_button.custom_minimum_size = Vector2(180, 52)
	_give_button.disabled = not can or _sel == &"" or Economy.get_amount(_sel) < 1
	_give_button.pressed.connect(give)
	foot.add_child(_give_button)
	if not can:
		var why := MenuScreen.label("오늘은 이미 선물했어요", &"LabelOnCreamDim", 14)
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(why)
		foot.move_child(why, 0)
	v.add_child(foot)
	return cc[0]


## Gives the selected resource through Colony.give_gift and shows the reaction it returns.
func give() -> Dictionary:
	if _sel == &"":
		return {}
	var r := resident()
	var before := int(r.get("trust", 0))
	var res := Colony.give_gift(resident_id, _sel)
	r = resident()
	if not res.get("ok", false):
		dialog.set_notes([[String(res.get("reason", "")), UiTokens.TEXT_DIM]])
		_refresh_column()
		return res
	_given = {"ok": true, "res": _sel, "reaction": res.reaction}
	var line := "고마워. 잘 쓸게."
	match StringName(res.reaction):
		&"liked":
			line = "이거… 내가 정말 좋아하는 거야. 고마워!"
		&"disliked":
			line = "음… 마음은 고마운데, 이건 좀 별로야."
	var rc: Array = ResidentText.REACTIONS.get(StringName(res.reaction), ["●", ""])
	var col: Color = {&"liked": UiTokens.ACCENT, &"disliked": UiTokens.WARN}.get(StringName(res.reaction), UiTokens.TEXT)
	var notes: Array = [["%s %s" % [rc[0], rc[1]], col]]
	notes.append_array(preload("res://ui/screens/dialog_screen.gd").trust_notes(before, int(res.get("trust", before))))
	dialog.say(ResidentText.call_name(r), line, resident_id)
	dialog.set_notes(notes)
	_refresh_column()
	_set_choices()
	return res


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER] \
			and _give_button != null and not _give_button.disabled:
		give()
		get_viewport().set_input_as_handled()


func _on_choice(id: StringName) -> void:
	match id:
		&"talk":
			close()
			UI.open(&"dialog", {"resident_id": resident_id})
		&"bye":
			close()
