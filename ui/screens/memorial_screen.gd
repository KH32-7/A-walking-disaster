class_name MemorialScreen
extends MenuScreen
## Memorial stone (#125 part 3, C-20). Owner: Lane D. Screen id `memorial`. Design 08 "추모비".
## A place in the base (UI 재설계 "기지는 걸어서 쓴다"): a scene-type screen. The base stays visible on
## the left with a world tag on the stone (marker_lines()); the right column has a cream reading card
## with the carved names (Colony.memorial_names()) and a slate list of residents, the grieving first,
## each with a "찾아가기" button → Colony.visit_memorial(id) (밤에 하루 한 번: 슬픔 −1일, 사기 +3).
## A refused visit shows Colony's `reason` as text. Faces come before names (FaceDot).
## Only one yellow button: the first visit that can be made now. Opened by UI.open(&"memorial");
## facility_choices() gives the stone's [F] lines for the coming facility list.

const RIGHT := 0.55

var _names: VBoxContainer
var _people: VBoxContainer
var _status: Label
var _count: Label
var _tag: WorldTag
## resident_id -> last reason / result text
var _notes: Dictionary = {}


func _init() -> void:
	title_text = "추모비"
	subtitle_text = "기지 뒤뜰"
	footer_keys = [["Esc", "뒤로"], ["클릭", "찾아가기"]]
	header_resources = []


static func has_stone() -> bool:
	return not Colony.working_building_ids(LossRules.MEMORIAL).is_empty()


static func is_night() -> bool:
	return GameState.flow_state == Enums.FlowState.NIGHT


static func visited_today() -> int:
	var n := 0
	for id in Colony.active_resident_ids():
		if int(Colony.get_resident(id).get("memorial_day", -1)) == GameState.day:
			n += 1
	return n


static func grieving() -> int:
	var n := 0
	for id in Colony.active_resident_ids():
		if int(Colony.get_resident(id).get("grief_days", 0)) > 0:
			n += 1
	return n


## World tag text: [small name, big state].
static func marker_lines() -> Array[String]:
	return ["추모비", "새긴 이름 %d · 오늘 다녀감 %d" % [Colony.memorial_names().size(), visited_today()]]


## The stone's [F] lines: [{label, state, screen, args}].
static func facility_choices() -> Array:
	return [{"label": "찾아가기", "state": "슬픔 %d명" % grieving() if grieving() > 0 else "",
		"screen": &"memorial", "args": {}}]


func _build_body(_b: Control) -> void:
	backdrop.anchor_left = RIGHT
	# Same top shade as the resident scene screens, so the header reads over a bright base.
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.anchor_right = RIGHT
	add_child(shade)
	move_child(shade, backdrop.get_index() + 1)
	_tag = WorldTag.new()
	_tag.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tag.anchor_right = RIGHT
	add_child(_tag)
	move_child(_tag, backdrop.get_index() + 1)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.anchor_left = RIGHT
	col.offset_left = 40
	col.offset_right = -52
	col.offset_top = 110
	col.offset_bottom = -90
	col.add_theme_constant_override(&"separation", 16)
	add_child(col)
	var cc := MenuScreen.cream_card(0)
	var cv: VBoxContainer = cc[1]
	var head := HBoxContainer.new()
	head.add_child(MenuScreen.label("새긴 이름", &"LabelOnCream", 20))
	_count = MenuScreen.label("", &"LabelOnCreamDim", 15)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_count)
	cv.add_child(head)
	_names = VBoxContainer.new()
	_names.add_theme_constant_override(&"separation", 8)
	cv.add_child(_names)
	col.add_child(cc[0])
	var right := MenuScreen.panel("찾아가기", "밤에 하루 한 번", Vector2(0, 0))
	(right[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(right[0])
	var rv: VBoxContainer = right[1]
	_status = MenuScreen.label("", &"LabelHud", 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_status)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_people = VBoxContainer.new()
	_people.add_theme_constant_override(&"separation", 10)
	_people.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_people)
	rv.add_child(sc)
	refresh()


func refresh() -> void:
	_fill_names()
	_fill_people()
	var lines := marker_lines()
	_tag.small = lines[0]
	_tag.big = lines[1]
	_tag.queue_redraw()


func _fill_names() -> void:
	MenuScreen.clear(_names)
	var stones := Colony.memorial_names()
	_count.text = "%d명" % stones.size()
	if stones.is_empty():
		_names.add_child(MenuScreen.label("아직 새긴 이름이 없어요.", &"LabelOnCreamDim", 16))
		return
	for m: Dictionary in stones:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 14)
		h.add_child(FaceDot.new(String(m.get("name", "")), 40, true))
		var nm := MenuScreen.label(String(m.get("name", "")), &"LabelOnCream", 19)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		h.add_child(MenuScreen.label(LossText.memorial_line(m), &"LabelOnCreamDim", 15))
		_names.add_child(h)


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
	var yellow_used := false
	for id: StringName in _people_ids():
		var row := _person_row(id, not yellow_used)
		if row.get_meta(&"primary", false):
			yellow_used = true
		_people.add_child(row)


func _person_row(id: StringName, may_be_primary: bool) -> Control:
	var r := Colony.get_resident(id)
	var p := PanelContainer.new()
	p.theme_type_variation = &"PanelSlateInner"
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 14)
	var grief := LossText.grief_tag(r)
	h.add_child(FaceDot.new(LossText.display_name(id), 44, false, "◇" if grief != "" else ""))
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(MenuScreen.label(LossText.display_name(id), &"LabelSection", 18))
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
	var can := not visited and has_stone() and is_night()
	var primary := may_be_primary and can and grief != ""
	var b := MenuScreen.button("✓ 오늘 다녀옴" if visited else "찾아가기", &"ButtonPrimary" if primary else &"ButtonSecondary")
	b.custom_minimum_size = Vector2(150, 0)
	b.disabled = not can
	b.tooltip_text = "오늘은 이미 다녀왔어요" if visited else ("밤에만" if not is_night() else "")
	b.pressed.connect(visit.bind(id))
	h.add_child(b)
	p.add_child(h)
	p.set_meta(&"primary", primary)
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
	refresh()
	return res


## World tag (UI_RULES §4 지점 표지): dark two-line chip (small name / big state), thin leader line,
## white dot on the place. Drawn over the visible base on the left of the screen.
class WorldTag extends Control:
	var small := ""
	var big := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var dot := Vector2(size.x * 0.46, size.y * 0.62)
		var font := UiThemeBuilder.font_kr(500)
		var bold := UiThemeBuilder.font_kr(700)
		var w := maxf(bold.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, 120.0) + 28.0
		var chip := Rect2(dot + Vector2(-w * 0.5, -150), Vector2(w, 62))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiTokens.INK, 0.82)
		sb.set_corner_radius_all(8)
		draw_style_box(sb, chip)
		draw_string(font, chip.position + Vector2(14, 22), small, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTokens.TEXT_DIM)
		draw_string(bold, chip.position + Vector2(14, 48), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTokens.TEXT)
		draw_line(Vector2(dot.x, chip.end.y), dot, Color(UiTokens.TEXT, 0.8), 1.5, true)
		draw_circle(dot, 5.0, UiTokens.TEXT)
