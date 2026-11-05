extends MenuScreen
## Relation map (D-13). Owner: Lane D. Design 08 "관계 수치", 14 "관계도".
## Left: residents as dots, relations as lines whose *shape* tells the stage (RelationGraph).
## Right: the line legend and the selected resident's relations (stage, value) from
## Colony.relations_of(). Clicking a dot or a row selects. open_with({"id": resident_id}).

var _sel: StringName = &""
var _graph: RelationGraph
var _list: VBoxContainer
var _count: Label


func _init() -> void:
	title_text = "관계도"
	subtitle_text = "주민"
	footer_keys = [["Esc", "뒤로"], ["클릭", "주민 고르기"]]
	header_resources = []


func open_with(args: Dictionary) -> void:
	if args.has("id") or args.has("resident_id"):
		_sel = StringName(args.get("id", args.get("resident_id", &"")))
	if _graph != null:
		_fill()


func _build_body(b: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 24)
	b.add_child(row)
	var left := MenuScreen.panel("기지 사람들", "")
	(left[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(left[0] as Control).size_flags_stretch_ratio = 1.7
	row.add_child(left[0])
	_count = (left[2] as HBoxContainer).get_child(1)
	_graph = RelationGraph.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.resident_selected.connect(func(id: StringName) -> void:
		_sel = id
		_fill())
	(left[1] as VBoxContainer).add_child(_graph)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 16)
	row.add_child(right)
	var legend := MenuScreen.panel("선 모양", "")
	right.add_child(legend[0])
	var lg := GridContainer.new()
	lg.columns = 4
	lg.add_theme_constant_override(&"h_separation", 12)
	lg.add_theme_constant_override(&"v_separation", 8)
	for stage: StringName in RelationGraph.STAGE_ORDER:
		lg.add_child(RelationGraph.LineSample.new(stage))
		var l := MenuScreen.label(RelationGraph.stage_name(stage), &"LabelHud", 15)
		l.custom_minimum_size = Vector2(110, 0)
		lg.add_child(l)
	(legend[1] as VBoxContainer).add_child(lg)
	var rel := MenuScreen.panel("관계", "")
	(rel[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(rel[0])
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	(rel[1] as VBoxContainer).add_child(sc)
	_fill()


## Graph data straight from Colony: every active resident, every known pair once.
func graph_data() -> Array:
	var ids: Array = Colony.active_resident_ids()
	ids.sort()
	var nodes: Array = []
	var edges: Array = []
	var seen := {}
	for id: StringName in ids:
		var r := Colony.get_resident(id)
		var look := Colony.appearance_for_look(id)
		var preset: Variant = CharacterLook.presets().get(StringName(look.get("preset", &"")))
		var col: Color = look.get("outfit_color", preset.outfit_color if preset != null else Color("c98f52"))
		nodes.append({"id": id, "name": ResidentText.call_name(r), "color": col.lightened(0.15)})
		var rels := Colony.relations_of(id)
		for other: StringName in rels:
			var key := "%s|%s" % ([id, other] if String(id) < String(other) else [other, id])
			if seen.has(key):
				continue
			seen[key] = true
			edges.append({"a": id, "b": other, "stage": StringName(rels[other].stage), "value": int(rels[other].value)})
	return [nodes, edges]


func _fill() -> void:
	var data := graph_data()
	var nodes: Array = data[0]
	if (_sel == &"" or not nodes.any(func(n: Dictionary) -> bool: return n.id == _sel)) and not nodes.is_empty():
		_sel = nodes[0].id
	_count.text = "%d명 / 관계 %d" % [nodes.size(), (data[1] as Array).size()]
	_graph.set_data(nodes, data[1], _sel)
	MenuScreen.clear(_list)
	if _sel == &"":
		_list.add_child(MenuScreen.label("아직 주민이 없어요.", &"LabelDim", 16))
		return
	var r := Colony.get_resident(_sel)
	_list.add_child(MenuScreen.label(ResidentText.full_name(r), &"LabelSection", 20))
	var rels := Colony.relations_of(_sel)
	var others: Array = rels.keys()
	others.sort_custom(func(a: StringName, b: StringName) -> bool: return int(rels[a].value) > int(rels[b].value))
	if others.is_empty():
		_list.add_child(MenuScreen.label("아직 다른 주민과 쌓인 관계가 없어요.", &"LabelDim", 15))
	for other: StringName in others:
		_list.add_child(_row(other, StringName(rels[other].stage), int(rels[other].value)))


func _row(other: StringName, stage: StringName, value: int) -> Control:
	var b := Button.new()
	b.theme_type_variation = &"ButtonCancel"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 50)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.04)
	box.border_color = Color(1, 1, 1, 0.1)
	box.set_border_width_all(1)
	box.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	for s in [&"normal", &"hover", &"pressed", &"focus"]:
		b.add_theme_stylebox_override(s, box)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -14
	h.add_theme_constant_override(&"separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := MenuScreen.label(ResidentText.call_name(Colony.get_resident(other)), &"LabelSection", 17)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(nm)
	var sample := RelationGraph.LineSample.new(stage)
	sample.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sample)
	var st := MenuScreen.label(RelationGraph.stage_name(stage), &"LabelHud", 15)
	st.custom_minimum_size = Vector2(70, 0)
	st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(st)
	var v := MenuScreen.label("%+d" % value, &"LabelNumber", 18)
	v.custom_minimum_size = Vector2(52, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(v)
	b.add_child(h)
	b.pressed.connect(func() -> void:
		_sel = other
		_fill())
	return b
