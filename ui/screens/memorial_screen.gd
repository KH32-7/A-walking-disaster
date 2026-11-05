class_name MemorialScreen
extends MenuScreen
## Memorial stone (#125 part 3, C-20). Owner: Lane D. Screen id `memorial`. Design 08 "추모비".
## Left: the names carved on the stone (Colony.memorial_names(), oldest first) with day and cause.
## Right: residents, the grieving first, each with a "찾아가기" button → Colony.visit_memorial(id)
## (밤에 하루 한 번: 슬픔 −1일, 사기 +3). A refused visit shows Colony's `reason` as text.
## The visit is offered only at night (design 08); outside the night the buttons say so.

var _names: VBoxContainer
var _people: VBoxContainer
var _status: Label
var _count: Label
## resident_id -> last reason / result text
var _notes: Dictionary = {}


func _init() -> void:
	title_text = "추모비"
	subtitle_text = "기지 뒤뜰"
	footer_keys = [["Esc", "뒤로"], ["클릭", "찾아가기"]]
	header_resources = []


func _build_body(b: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 24)
	b.add_child(row)
	var left := MenuScreen.panel("새긴 이름", "", Vector2(700, 0))
	(left[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left[0])
	_count = (left[2] as HBoxContainer).get_child(1)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_names = VBoxContainer.new()
	_names.add_theme_constant_override(&"separation", 8)
	_names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_names)
	(left[1] as VBoxContainer).add_child(sc)
	var right := MenuScreen.panel("찾아가기", "밤에 하루 한 번", Vector2(0, 0))
	(right[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(right[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right[0])
	var rv: VBoxContainer = right[1]
	_status = MenuScreen.label("", &"LabelHud", 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_status)
	var sc2 := ScrollContainer.new()
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_people = VBoxContainer.new()
	_people.add_theme_constant_override(&"separation", 6)
	_people.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(_people)
	rv.add_child(sc2)
	refresh()


func refresh() -> void:
	_fill_names()
	_fill_people()


static func has_stone() -> bool:
	return not Colony.working_building_ids(LossRules.MEMORIAL).is_empty()


static func is_night() -> bool:
	return GameState.flow_state == Enums.FlowState.NIGHT


func _fill_names() -> void:
	MenuScreen.clear(_names)
	var stones := Colony.memorial_names()
	_count.text = "%d명" % stones.size()
	if stones.is_empty():
		_names.add_child(MenuScreen.label("아직 새긴 이름이 없어요.", &"LabelDim", 16))
		return
	for m: Dictionary in stones:
		var p := PanelContainer.new()
		p.theme_type_variation = &"PanelSlateInner"
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 16)
		var mark := MenuScreen.label("†", &"LabelSection", 20)
		mark.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
		h.add_child(mark)
		var nm := MenuScreen.label(String(m.get("name", "")), &"LabelSection", 20)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		h.add_child(MenuScreen.label(LossText.memorial_line(m), &"LabelDim", 15))
		p.add_child(h)
		_names.add_child(p)


func _people_ids() -> Array:
	var ids: Array = Colony.active_resident_ids()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ga := int(Colony.get_resident(a).get("grief_days", 0))
		var gb := int(Colony.get_resident(b).get("grief_days", 0))
		if ga != gb:
			return ga > gb
		return LossText.display_name(a) < LossText.display_name(b))
	return ids


func _fill_people() -> void:
	MenuScreen.clear(_people)
	if not has_stone():
		_status.text = "■ 추모비가 아직 없어요. 건설에서 추모비를 지으면 찾아갈 수 있어요."
	elif not is_night():
		_status.text = "▲ 밤에 찾아갈 수 있어요. 한 사람이 하루 한 번, 슬픔 −1일 · 사기 +%d." % LossRules.MEMORIAL_VISIT_MORALE
	else:
		_status.text = "한 사람이 하루 한 번 찾아갈 수 있어요. 슬픔 −1일 · 사기 +%d." % LossRules.MEMORIAL_VISIT_MORALE
	for id: StringName in _people_ids():
		_people.add_child(_person_row(id))


func _person_row(id: StringName) -> Control:
	var r := Colony.get_resident(id)
	var p := PanelContainer.new()
	p.theme_type_variation = &"PanelSlateInner"
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 14)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(MenuScreen.label(LossText.display_name(id), &"LabelSection", 18))
	var grief := LossText.grief_tag(r)
	var sub := MenuScreen.label(grief if grief != "" else "슬픔 없음", &"LabelHud" if grief != "" else &"LabelDim", 14)
	if grief != "":
		sub.add_theme_color_override(&"font_color", UiTokens.WARN)
	v.add_child(sub)
	if _notes.has(id):
		var n := MenuScreen.label(String(_notes[id]), &"LabelDim", 13)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(n)
	h.add_child(v)
	var visited := int(r.get("memorial_day", -1)) == GameState.day
	var b := MenuScreen.button("✓ 오늘 다녀옴" if visited else "찾아가기", &"ButtonSecondary" if grief != "" else &"ButtonCancel")
	b.custom_minimum_size = Vector2(150, 0)
	b.disabled = visited or not has_stone() or not is_night()
	b.tooltip_text = "오늘은 이미 다녀왔어요" if visited else ("밤에만" if not is_night() else "")
	b.pressed.connect(visit.bind(id))
	h.add_child(b)
	p.add_child(h)
	return p


## Calls Colony.visit_memorial and keeps its answer next to the resident.
func visit(id: StringName) -> Dictionary:
	var before := int(Colony.get_resident(id).get("grief_days", 0))
	var res := Colony.visit_memorial(id)
	if res.get("ok", false):
		var left := int(Colony.get_resident(id).get("grief_days", 0))
		if before <= 0:
			_notes[id] = "다녀왔어요. 마음이 조금 가벼워졌어요."
		else:
			_notes[id] = "다녀왔어요. " + ("슬픔 %d일 남음" % left if left > 0 else "슬픔이 걷혔어요")
	else:
		_notes[id] = "■ " + String(res.get("reason", "찾아갈 수 없어요"))
	_fill_people()
	return res
