class_name SettingRow
extends PanelContainer
## One line of the settings list (D-15, UI_RULES §9 "왼쪽 목록"). Owner: Lane D.
## Name on the left, the value on the right as a stepper `‹  보통  ›` (←/→ or the arrows),
## a bar for volumes, key chips for bindings, or a soft button. The focused row gets the yellow
## side bar (§1.4 "고른 항목"). The row never writes a value itself: it asks with `stepped` /
## `activated` and the screen calls Settings / InputMap, then `show_value()`.

signal stepped(row: SettingRow, value: Variant)
signal activated(row: SettingRow)
signal row_focused(row: SettingRow)

const VALUE_W := 230.0

## Row dict from SettingsCatalog (key, kind, label, desc, options ...).
var data: Dictionary = {}
var key: StringName = &""
var kind := ""
var options: Array = []
var index := -1
var locked := false
var lock_reason := ""
var _raw: Variant = null

var _bar_mark: ColorRect
var _name: Label
var _prev: Button
var _next: Button
var _value: Label
var _bar: SegBar
var _chips: HBoxContainer
var _button: Button
var _sb_normal: StyleBoxFlat
var _sb_focus: StyleBoxFlat


func _init(row: Dictionary = {}) -> void:
	data = row
	key = row.get("key", &"")
	kind = String(row.get("kind", ""))
	options = row.get("options", [])
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 50)
	_sb_normal = _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0))
	_sb_focus = _box(Color(1, 1, 1, 0.08), UiTokens.LINE_STRONG)
	add_theme_stylebox_override(&"panel", _sb_normal)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	_bar_mark = ColorRect.new()
	_bar_mark.color = UiTokens.ACCENT
	_bar_mark.custom_minimum_size = Vector2(4, 26)
	_bar_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_mark.modulate.a = 0.0
	h.add_child(_bar_mark)
	_name = Label.new()
	_name.text = String(row.get("label", ""))
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_name)
	match kind:
		"binding":
			_chips = HBoxContainer.new()
			_chips.add_theme_constant_override(&"separation", 10)
			_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(_chips)
		"button":
			_button = MenuScreen.button(String(row.get("button", "실행")), &"ButtonSoft")
			_button.focus_mode = Control.FOCUS_NONE
			_button.pressed.connect(func() -> void: activated.emit(self))
			h.add_child(_button)
		_:
			if kind == "percent":
				_bar = MenuScreen.bar(0.0, UiTokens.TEXT, 150, 6)
				h.add_child(_bar)
			_prev = _arrow("‹", -1)
			h.add_child(_prev)
			_value = Label.new()
			_value.custom_minimum_size = Vector2(VALUE_W if kind != "percent" else 70, 0)
			_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_value.theme_type_variation = &"LabelHud" if kind != "percent" else &"LabelNumber"
			_value.mouse_filter = Control.MOUSE_FILTER_STOP
			_value.gui_input.connect(_on_value_click)
			h.add_child(_value)
			_next = _arrow("›", 1)
			h.add_child(_next)
	mouse_entered.connect(func() -> void:
		if not has_focus():
			grab_focus())
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))


## Shows `value` (its option label). Values outside the steps show as they are.
func show_value(value: Variant) -> void:
	_raw = value
	if _value == null:
		return
	index = SettingsCatalog.option_index(options, value)
	if index < 0 and data.has("custom_text"):
		_value.text = String(data.custom_text)
	else:
		_value.text = SettingsCatalog.value_text(data, value)
	if _bar != null:
		_bar.value = clampf(float(value), 0.0, 1.0)
	_refresh_arrows()


## Binding rows: [[device name, key text], ...] e.g. [["키보드", "R"], ["패드", "X"]].
func show_bindings(pairs: Array) -> void:
	if _chips == null:
		return
	MenuScreen.clear(_chips)
	for p: Array in pairs:
		var box := HBoxContainer.new()
		box.add_theme_constant_override(&"separation", 10)
		box.custom_minimum_size = Vector2(190, 0)
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dev := MenuScreen.label(String(p[0]), &"LabelDim")
		dev.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(dev)
		var text := String(p[1])
		if text.is_empty():
			box.add_child(MenuScreen.label("—", &"LabelDim"))
		else:
			var chip := KeyChip.new(text, KeyChip.Style.OUTLINE)
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(chip)
		_chips.add_child(box)


func set_locked(on: bool, reason := "") -> void:
	locked = on
	lock_reason = reason
	_name.modulate.a = 0.55 if on else 1.0
	if _value != null:
		_value.modulate.a = 0.55 if on else 1.0
	if _button != null:
		_button.disabled = on
	_refresh_arrows()


func current_value() -> Variant:
	return options[index][0] if index >= 0 and index < options.size() else null


## Spoken by MenuReader: "자막 크기, 보통".
func tts_text() -> String:
	var v := ""
	if _value != null:
		v = _value.text
	elif _chips != null:
		var parts: PackedStringArray = []
		for box in _chips.get_children():
			var t := ""
			for c in box.get_children():
				t += (c.key_text if c is KeyChip else (c as Label).text) + " "
			parts.append(t.strip_edges())
		v = ", ".join(parts)
	elif _button != null:
		v = _button.text
	var out := "%s, %s" % [_name.text, v] if not v.is_empty() else _name.text
	return out + (" (잠김)" if locked else "")


## +1 / -1. Toggles wrap around, other steppers stop at the ends. From a value that is not one
## of the steps (set elsewhere, or "직접 정함"), the first step lands on the nearest option.
func step(dir: int) -> void:
	if locked or options.is_empty() or _value == null:
		return
	var n: int
	if index < 0:
		n = clampi(SettingsCatalog.nearest_index(options, _raw), 0, options.size() - 1)
	else:
		n = index + dir
		if kind == "toggle" or kind == "protect":
			n = posmod(n, options.size())
		n = clampi(n, 0, options.size() - 1)
	if n == index:
		return
	stepped.emit(self, options[n][0])


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right"):
		step(1)
		accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		_activate()
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		if kind == "binding" or kind == "button":
			_activate()
		accept_event()


func _activate() -> void:
	if locked:
		return
	if kind == "binding" or kind == "button":
		activated.emit(self)
	elif kind == "toggle" or kind == "protect":
		step(1)


func _on_value_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		if not locked and not options.is_empty():
			var n := posmod(index + 1, options.size())
			if n != index:
				stepped.emit(self, options[n][0])
		accept_event()


func _arrow(text: String, dir: int) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"TabText"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40, 0)
	b.pressed.connect(func() -> void:
		grab_focus()
		step(dir))
	return b


func _refresh_arrows() -> void:
	if _prev == null:
		return
	var wrap := kind == "toggle" or kind == "protect"
	_prev.disabled = locked or (not wrap and index == 0)
	_next.disabled = locked or (not wrap and index == options.size() - 1)
	_prev.modulate.a = 0.25 if _prev.disabled else 1.0
	_next.modulate.a = 0.25 if _next.disabled else 1.0


func _on_focus(on: bool) -> void:
	add_theme_stylebox_override(&"panel", _sb_focus if on else _sb_normal)
	_bar_mark.modulate.a = 1.0 if on else 0.0
	if on:
		row_focused.emit(self)


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0.0 else 0)
	sb.set_corner_radius_all(UiTokens.BAND_RADIUS)
	sb.content_margin_left = 10
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.anti_aliasing = true
	return sb
