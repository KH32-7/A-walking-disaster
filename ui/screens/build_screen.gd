extends MenuScreen
## Build panel (D-06). Owner: Lane D. Design 09 "건물 목록", 14 "건설 모드".
## Lists BaseDB buildings by category with cost and Colony.can_build() reasons. "배치하기" emits
## UI.build_requested(def_id); Lane C runs the grid placement preview (C-03) and calls
## Colony.place_building(). This screen computes no rules.

const CATEGORY_NAMES := ["주거", "생산", "가공", "생활", "제작", "포함", "저장", "군사", "특수", "설비", "방어"]

var _cat := -1
var _sel: StringName = &""
var _tabs: HBoxContainer
var _list: VBoxContainer
var _detail: VBoxContainer
var _count: Label


func _init() -> void:
	title_text = "건설"
	subtitle_text = "기지"
	footer_keys = [["Esc", "뒤로"], ["클릭", "고르기"], ["Enter", "배치하기"]]


func _build_body(b: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 24)
	b.add_child(row)
	var left := MenuScreen.panel("건물", "", Vector2(980, 0))
	(left[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left[0])
	_count = (left[2] as HBoxContainer).get_child(1)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override(&"separation", 4)
	(left[1] as VBoxContainer).add_child(_tabs)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	(left[1] as VBoxContainer).add_child(sc)
	var card := MenuScreen.cream_card(460)
	(card[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(card[0])
	_detail = card[1]
	_build_tabs()
	_fill()


func _build_tabs() -> void:
	MenuScreen.clear(_tabs)
	var all := MenuScreen.button("전체", &"TabText")
	all.toggle_mode = true
	all.button_pressed = _cat == -1
	all.pressed.connect(func() -> void: _set_cat(-1))
	_tabs.add_child(all)
	var used := {}
	for def: BuildingDef in BaseDB.buildings().values():
		if not def.prebuilt and def.attach_to == &"":
			used[int(def.category)] = true
	var cats := used.keys()
	cats.sort()
	for c: int in cats:
		var t := MenuScreen.button(CATEGORY_NAMES[c], &"TabText")
		t.toggle_mode = true
		t.button_pressed = _cat == c
		t.pressed.connect(_set_cat.bind(c))
		_tabs.add_child(t)


func _set_cat(c: int) -> void:
	_cat = c
	_build_tabs()
	_fill()


func _defs() -> Array:
	var out := []
	for def: BuildingDef in BaseDB.buildings().values():
		if def.prebuilt:
			continue
		if _cat >= 0 and int(def.category) != _cat:
			continue
		out.append(def)
	out.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool:
		var oa := bool(Colony.can_build(a.id).ok)
		var ob := bool(Colony.can_build(b.id).ok)
		return oa if oa != ob else a.display_name < b.display_name)
	return out


func _fill() -> void:
	MenuScreen.clear(_list)
	var defs := _defs()
	var ok_n := 0
	for def: BuildingDef in defs:
		var check: Dictionary = Colony.can_build(def.id)
		if check.ok:
			ok_n += 1
		_list.add_child(_row(def, check))
	_count.text = "지을 수 있음 %d / %d" % [ok_n, defs.size()]
	if _sel == &"" and not defs.is_empty():
		_sel = (defs[0] as BuildingDef).id
	_show_detail()


func _row(def: BuildingDef, check: Dictionary) -> Control:
	var b := Button.new()
	b.theme_type_variation = &"ButtonCancel"
	var sel := def.id == _sel
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.08) if sel else Color(1, 1, 1, 0.03)
	box.border_color = UiTokens.ACCENT if sel else Color(1, 1, 1, 0.12)
	box.set_border_width_all(2 if sel else 1)
	box.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	for s in [&"normal", &"hover", &"pressed", &"focus"]:
		b.add_theme_stylebox_override(s, box)
	b.custom_minimum_size = Vector2(0, 62)
	b.focus_mode = Control.FOCUS_NONE
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16
	h.offset_right = -16
	h.add_theme_constant_override(&"separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override(&"separation", -2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := MenuScreen.label(def.display_name, &"LabelSection", 18)
	nv.add_child(nm)
	var sub := "%s · %d×%d칸" % [CATEGORY_NAMES[int(def.category)], def.size.x, def.size.y]
	nv.add_child(MenuScreen.label(sub, &"LabelDim", 13))
	h.add_child(nv)
	var cost := MenuScreen.label(MenuScreen.cost_text(def.cost_for_level(1)), &"LabelHud", 15)
	h.add_child(cost)
	var st := MenuScreen.label("지을 수 있음" if check.ok else String((check.reasons as Array)[0]), &"LabelHud", 14)
	st.add_theme_color_override(&"font_color", UiTokens.GOOD if check.ok else UiTokens.TEXT_DIM)
	st.custom_minimum_size = Vector2(170, 0)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(st)
	b.add_child(h)
	if not check.ok:
		nm.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	b.pressed.connect(func() -> void:
		_sel = def.id
		_fill())
	return b


func _show_detail() -> void:
	MenuScreen.clear(_detail)
	var def := BaseDB.get_building(_sel)
	if def == null:
		return
	var check: Dictionary = Colony.can_build(def.id)
	var tag := MenuScreen.label(CATEGORY_NAMES[int(def.category)] + "  ·  %d×%d칸" % [def.size.x, def.size.y],
		&"LabelOnCreamDim", 13)
	_detail.add_child(tag)
	var t := MenuScreen.label(def.display_name, &"LabelSection", 24)
	t.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	_detail.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 6)
	var cost := def.cost_for_level(1)
	for id: StringName in cost:
		var have := Economy.get_amount(id)
		grid.add_child(MenuScreen.label(MenuScreen.resource_name(id), &"LabelOnCream", 15))
		var v := MenuScreen.label("%d / 보유 %d" % [int(cost[id]), have], &"LabelOnCream", 15)
		if have < int(cost[id]):
			v.add_theme_color_override(&"font_color", UiTokens.DANGER)
		grid.add_child(v)
	if def.power_use[0] > 0:
		grid.add_child(MenuScreen.label("전력", &"LabelOnCream", 15))
		grid.add_child(MenuScreen.label("−%d" % def.power_use[0], &"LabelOnCream", 15))
	if def.noise > 0.0:
		grid.add_child(MenuScreen.label("기지 소음", &"LabelOnCream", 15))
		grid.add_child(MenuScreen.label("+%.1f" % def.noise, &"LabelOnCream", 15))
	if def.capacity > 0:
		grid.add_child(MenuScreen.label("일손", &"LabelOnCream", 15))
		grid.add_child(MenuScreen.label("%d명" % def.capacity, &"LabelOnCream", 15))
	_detail.add_child(grid)
	if not check.ok:
		for r: String in check.reasons:
			var l := MenuScreen.label("▲  " + r, &"LabelOnCream", 14)
			l.add_theme_color_override(&"font_color", UiTokens.DANGER)
			_detail.add_child(l)
	var go := MenuScreen.button("배치하기", &"ButtonPrimary")
	go.disabled = not check.ok
	go.pressed.connect(_place)
	_detail.add_child(go)


func _place() -> void:
	if _sel == &"" or not bool(Colony.can_build(_sel).ok):
		return
	UI.build_requested.emit(_sel)
	close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept"):
		_place()
		get_viewport().set_input_as_handled()
