class_name MenuList
extends VBoxContainer
## Vertical system list (UI_RULES §9 D-19 "시스템 탭 목록"): title menu and pause menu. Owner: Lane D.
## Each row is a flat button: text on the left, a dim note on the right. The focused / hovered row
## is the selected item, so it turns ACCENT (yellow = what Enter presses now). Disabled rows stay
## readable in TEXT_DIM and show why in their note (never colour alone).

## A row got keyboard focus or the mouse (the title shows that row's detail panel).
signal row_focused(id: StringName)

var row_height := 58.0
var font_size := 24

var _rows: Dictionary = {}  # StringName -> Button


func _init() -> void:
	add_theme_constant_override(&"separation", 8)


## Adds a row. `note` is the dim text on the right (slot day, "준비 중", key...).
func add_row(id: StringName, text: String, action: Callable, note := "", enabled := true) -> Button:
	var b := Button.new()
	b.name = String(id)
	b.text = ""
	b.custom_minimum_size = Vector2(0, row_height)
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = not enabled
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(1, 1, 1, 0.0)
	empty.set_corner_radius_all(UiTokens.CARD_RADIUS)
	var on := StyleBoxFlat.new()
	on.bg_color = UiTokens.ACCENT
	on.set_corner_radius_all(UiTokens.CARD_RADIUS)
	for s in [&"normal", &"disabled"]:
		b.add_theme_stylebox_override(s, empty)
	for s in [&"hover", &"pressed", &"focus", &"hover_pressed"]:
		b.add_theme_stylebox_override(s, on)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 22
	h.offset_right = -22
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Label.new()
	t.name = &"Text"
	t.text = text
	t.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	t.add_theme_font_size_override(&"font_size", font_size)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	var n := Label.new()
	n.name = &"Note"
	n.text = note
	n.add_theme_font_override(&"font", UiThemeBuilder.font_kr(500))
	n.add_theme_font_size_override(&"font_size", 15)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(n)
	b.add_child(h)
	if action.is_valid():
		b.pressed.connect(action)
	b.focus_entered.connect(_on_focus.bind(id))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	add_child(b)
	_rows[id] = b
	_paint(b, false)
	return b


func clear_rows() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_rows.clear()


func row(id: StringName) -> Button:
	return _rows.get(id)


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _rows:
		out.append(id)
	return out


func focus_row(id: StringName) -> void:
	var b: Button = _rows.get(id)
	if b != null and not b.disabled and b.is_inside_tree():
		b.grab_focus()


## Focuses the first enabled row. Returns its id (or &"" when every row is disabled).
func focus_first() -> StringName:
	for id: StringName in _rows:
		var b: Button = _rows[id]
		if not b.disabled:
			if b.is_inside_tree():
				b.grab_focus()
			return id
	return &""


func _on_focus(id: StringName) -> void:
	for other: StringName in _rows:
		_paint(_rows[other], other == id)
	row_focused.emit(id)


func _paint(b: Button, selected: bool) -> void:
	var t: Label = b.find_child("Text", true, false)
	var n: Label = b.find_child("Note", true, false)
	var fg := UiTokens.ACCENT_TEXT if selected else UiTokens.TEXT
	var dim := UiTokens.ACCENT_TEXT if selected else UiTokens.TEXT_DIM
	if b.disabled:
		fg = Color(UiTokens.TEXT_DIM, 0.55)
		dim = Color(UiTokens.TEXT_DIM, 0.55)
	t.add_theme_color_override(&"font_color", fg)
	n.add_theme_color_override(&"font_color", dim)
	# A selected row whose focus moved elsewhere keeps a thin yellow edge instead of the fill.
	var keep := StyleBoxFlat.new()
	keep.bg_color = Color(1, 1, 1, 0.06) if selected else Color(1, 1, 1, 0)
	keep.border_color = UiTokens.ACCENT
	keep.border_width_left = 4 if selected else 0
	keep.set_corner_radius_all(UiTokens.CARD_RADIUS)
	b.add_theme_stylebox_override(&"normal", keep)
	if selected and not b.has_focus():
		t.add_theme_color_override(&"font_color", UiTokens.TEXT)
		n.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)


## Called by owners when focus leaves to a sub panel: the selected row keeps its edge, not the fill.
func mark_selected(id: StringName) -> void:
	for other: StringName in _rows:
		_paint(_rows[other], other == id)
