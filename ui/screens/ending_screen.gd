class_name EndingScreen
extends Control
## Ending card (D-19). Owner: Lane D. Screen id `ending`.
## Design 13 "엔딩": one card per resident, written from the survival journal. The lines come from
## Journal.epilogue(ending) (A-17, ai/journal.gd); this screen only lays them out and pages through.
## Status is a shape + a word, never colour alone: 함께(circle) · 실종(diamond) · 떠남(triangle) · 잃음(cross).
##
## open_with(args):
##   ending  Enums.EndingChoice (LEAVE / STAY) or -1 before the choice (demo ending card)
##   cards   optional epilogue cards (previews / tests); default Journal.epilogue(ending)
## The last card's button leaves to the title (SceneRouter.quit_to_title) unless already there.

signal finished

const TITLE := "아무도 두고 가지 않는다"
const ENDING_NAMES := {Enums.EndingChoice.LEAVE: "떠나기", Enums.EndingChoice.STAY: "남기"}
const STATUS := {
	&"active": {"word": "함께", "shape": &"circle", "color": UiTokens.GOOD},
	&"missing": {"word": "실종", "shape": &"diamond", "color": UiTokens.WARN},
	&"left": {"word": "떠남", "shape": &"triangle", "color": UiTokens.TEXT_DIM},
	&"dead": {"word": "잃음", "shape": &"cross", "color": UiTokens.DANGER},
}

var ending := -1
var cards: Array = []
var index := 0

var _card_holder: CenterContainer
var _counter: Label
var _chips: HBoxContainer
var _next: Button
var _prev: Button
var _summary: Label
var _built := false


func open_with(args: Dictionary) -> void:
	ending = int(args.get("ending", ending))
	if args.has("cards"):
		cards = (args["cards"] as Array).duplicate(true)
	else:
		cards = Journal.epilogue(ending)
	index = clampi(int(args.get("index", 0)), 0, maxi(cards.size() - 1, 0))
	if _built:
		_refresh()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not _built and cards.is_empty() and ending == -1:
		cards = Journal.epilogue(ending)
	var bg := ColorRect.new()
	bg.color = UiTokens.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 96
	top.offset_bottom = 300
	top.add_theme_constant_override(&"separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var kicker := MenuScreen.label(_kicker(), &"LabelHud", 18)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	top.add_child(kicker)
	var title := MenuScreen.label(TITLE, &"LabelTitle", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	var band_row := CenterContainer.new()
	var bands := HaesolBands.new()
	bands.custom_minimum_size = Vector2(620, 18)
	band_row.add_child(bands)
	top.add_child(band_row)
	bands.play(HaesolBands.IN_TIME)
	_summary = MenuScreen.label("", &"LabelHud", 17)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	top.add_child(_summary)

	_card_holder = CenterContainer.new()
	_card_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_holder.offset_top = 300
	_card_holder.offset_bottom = -250
	_card_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_holder)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override(&"separation", 22)
	nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top = -240
	nav.offset_bottom = -180
	add_child(nav)
	_prev = MenuScreen.button("‹  이전", &"ButtonCancel")
	_prev.custom_minimum_size = Vector2(150, 50)
	_prev.pressed.connect(step.bind(-1))
	nav.add_child(_prev)
	_counter = MenuScreen.label("", &"LabelNumber", 24)
	_counter.custom_minimum_size = Vector2(90, 0)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(_counter)
	_next = MenuScreen.button("다음  ›", &"ButtonPrimary")
	_next.custom_minimum_size = Vector2(190, 50)
	_next.pressed.connect(_on_next)
	nav.add_child(_next)

	_chips = HBoxContainer.new()
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.add_theme_constant_override(&"separation", 18)
	_chips.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_chips.offset_top = -160
	_chips.offset_bottom = -120
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chips)

	var f := HBoxContainer.new()
	f.add_theme_constant_override(&"separation", 26)
	for pair: Array in [["← →", "넘기기"], ["Enter", "다음"]]:
		var p := HBoxContainer.new()
		p.add_theme_constant_override(&"separation", 10)
		p.add_child(KeyChip.new(String(pair[0]), KeyChip.Style.OUTLINE))
		p.add_child(MenuScreen.label(String(pair[1]), &"LabelHud"))
		f.add_child(p)
	add_child(f)
	f.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	f.grow_vertical = Control.GROW_DIRECTION_BEGIN
	f.position += Vector2(52, -34)
	_built = true
	_refresh()


func _kicker() -> String:
	var parts: PackedStringArray = ["엔딩"]
	if ENDING_NAMES.has(ending):
		parts.append(ENDING_NAMES[ending])
	parts.append("%d일차" % GameState.day)
	return " · ".join(parts)


## {status: count} over the cards (display only).
func status_counts() -> Dictionary:
	var out := {}
	for c: Dictionary in cards:
		var s := StringName(c.get("status", &"active"))
		out[s] = int(out.get(s, 0)) + 1
	return out


func is_last() -> bool:
	return index >= cards.size() - 1


func step(d: int) -> void:
	if cards.is_empty():
		return
	index = clampi(index + d, 0, cards.size() - 1)
	_refresh()


func _on_next() -> void:
	if is_last():
		finish()
	else:
		step(1)


func finish() -> void:
	finished.emit()
	UI.close(StringName(name))
	if GameState.flow_state != Enums.FlowState.TITLE:
		SceneRouter.quit_to_title()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_right"):
		step(1)
	elif event.is_action_pressed(&"ui_left"):
		step(-1)
	else:
		return
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	var counts := status_counts()
	var parts: PackedStringArray = []
	for s: StringName in [&"active", &"missing", &"left", &"dead"]:
		if counts.has(s):
			parts.append("%s %d명" % [STATUS[s].word, counts[s]])
	_summary.text = "  ·  ".join(parts) if not parts.is_empty() else "기록된 주민이 없어요"
	MenuScreen.clear(_card_holder)
	_card_holder.add_child(_make_card(cards[index] if not cards.is_empty() else {}))
	_counter.text = "%d / %d" % [index + 1 if not cards.is_empty() else 0, cards.size()]
	_prev.disabled = index <= 0
	_next.text = "타이틀로" if is_last() else "다음  ›"
	_focus_next.call_deferred()
	MenuScreen.clear(_chips)
	for i in cards.size():
		_chips.add_child(_chip(cards[i], i == index))


func _focus_next() -> void:
	if _next != null and _next.is_inside_tree():
		_next.grab_focus()


func _make_card(card: Dictionary) -> Control:
	var cc := MenuScreen.cream_card(760)
	var c: PanelContainer = cc[0]
	var v: VBoxContainer = cc[1]
	v.add_theme_constant_override(&"separation", 16)
	if card.is_empty():
		v.add_child(_on_cream("이 도시에 남겨진 사람은 이제 없다.", 22, true))
		return c
	var st: Dictionary = STATUS.get(StringName(card.get("status", &"active")), STATUS[&"active"])
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 14)
	head.add_child(_on_cream(String(card.get("name", "")), 32, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_status_tag(st))
	v.add_child(head)
	var line := ColorRect.new()
	line.color = Color(UiTokens.TEXT_ON_CREAM, 0.15)
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)
	for l in card.get("lines", []):
		var lab := _on_cream(String(l), 21, false)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(700, 0)
		lab.add_theme_constant_override(&"line_spacing", 8)
		v.add_child(lab)
	return c


func _on_cream(text: String, px: int, bold: bool) -> Label:
	var l := MenuScreen.label(text, &"LabelSection" if bold else &"LabelOnCream", px)
	l.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	return l


func _status_tag(st: Dictionary) -> Control:
	var p := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = UiTokens.TEXT_ON_CREAM
	box.set_corner_radius_all(14)
	box.content_margin_left = 12
	box.content_margin_right = 14
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	p.add_theme_stylebox_override(&"panel", box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	var m := StatusMark.new()
	m.shape = st.shape
	m.color = st.color
	m.custom_minimum_size = Vector2(14, 14)
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(m)
	var l := MenuScreen.label(String(st.word), &"LabelHud", 16)
	h.add_child(l)
	p.add_child(h)
	return p


func _chip(card: Dictionary, selected: bool) -> Control:
	var st: Dictionary = STATUS.get(StringName(card.get("status", &"active")), STATUS[&"active"])
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 6)
	var m := StatusMark.new()
	m.shape = st.shape
	m.color = st.color
	m.custom_minimum_size = Vector2(10, 10)
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(m)
	var l := MenuScreen.label(String(card.get("name", "")), &"LabelHud", 16)
	l.add_theme_color_override(&"font_color", UiTokens.ACCENT if selected else UiTokens.TEXT_DIM)
	h.add_child(l)
	return h


## Small status shape (circle / diamond / triangle / cross).
class StatusMark:
	extends Control
	var shape: StringName = &"circle"
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size / 2.0
		var r := s / 2.0
		match shape:
			&"circle":
				draw_circle(c, r, color)
			&"diamond":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r),
					c + Vector2(-r, 0)]), color)
			&"triangle":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r), c + Vector2(-r, r)]), color)
			&"cross":
				draw_line(c + Vector2(-r, -r), c + Vector2(r, r), color, 3.0)
				draw_line(c + Vector2(r, -r), c + Vector2(-r, r), color, 3.0)
