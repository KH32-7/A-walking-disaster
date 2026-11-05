class_name DialogBox
extends Control
## Conversation strip (D-13, design 14 "대화·이벤트": 초상, 대사 최대 2줄, 선택지 최대 3개).
## Owner: Lane D. Sits along the bottom of a scene-type screen: dark fade, portrait card on the left,
## speaker name in ACCENT and the line in subtitle style (shadow only, UI_RULES §5 "자막"), and up
## to three cream pill choices on the right with number key chips (1–3). Enter picks the only
## choice. Emits choice_made(id).
##
##   box.say("서하은", "오늘도 무사히 돌아왔네.", resident_id)
##   box.set_choices([[&"talk", "이야기 나누기"], [&"gift", "선물 주기"], [&"bye", "그만"]])
##
## Layout.CENTER (UI redesign "대화·이벤트", #125): a cream box at the bottom centre with the speaker
## in a yellow name pill on its top edge, the notes as small chips inside the box, and the choices
## as a row of cream pills ("1 · …") under it. The choice to press now (the first one that can be
## picked) gets the screen's one yellow ring. No portrait: the faces are in the scene above.

signal choice_made(choice_id: StringName)

enum Layout { STRIP, CENTER }

const MAX_CHOICES := 3
const MAX_LINES := 2

## Enter picks the choice when there is only one (off when the screen uses Enter itself).
var enter_picks_single := true
var portrait: ResidentPortrait
var speaker_label: Label
var line_label: Label
var note_box: HBoxContainer
var _choices_box: BoxContainer
var _ids: Array[StringName] = []
var _buttons: Array[Button] = []
var layout: Layout = Layout.STRIP
var _speaker_pill: Control


func _init(l: Layout = Layout.STRIP) -> void:
	layout = l
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 250)


func _ready() -> void:
	var fade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.78)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_to = Vector2(0, 1)
	fade.texture = gt
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.offset_top = -60
	add_child(fade)
	if layout == Layout.CENTER:
		_build_center()
		return
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 52
	row.offset_right = -52
	row.offset_bottom = -84
	row.add_theme_constant_override(&"separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	portrait = ResidentPortrait.new(Vector2(170, 200))
	portrait.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(portrait)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_END
	text.add_theme_constant_override(&"separation", 10)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	note_box = HBoxContainer.new()
	note_box.add_theme_constant_override(&"separation", 8)
	text.add_child(note_box)
	speaker_label = Label.new()
	speaker_label.theme_type_variation = &"LabelSpeaker"
	text.add_child(speaker_label)
	line_label = Label.new()
	line_label.theme_type_variation = &"LabelSubtitle"
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.max_lines_visible = MAX_LINES
	line_label.custom_minimum_size = Vector2(560, 0)
	text.add_child(line_label)
	_choices_box = VBoxContainer.new()
	_choices_box.alignment = BoxContainer.ALIGNMENT_END
	_choices_box.add_theme_constant_override(&"separation", 10)
	_choices_box.custom_minimum_size = Vector2(430, 0)
	row.add_child(_choices_box)


## speaker_id: a resident id for the portrait, &"" = narration (portrait hidden).
func say(speaker: String, text: String, speaker_id: StringName = &"") -> void:
	speaker_label.text = speaker
	speaker_label.visible = speaker != ""
	line_label.text = text
	if layout == Layout.CENTER:
		_speaker_pill.visible = speaker != ""
		return
	portrait.visible = speaker_id != &""
	if speaker_id != &"":
		portrait.set_resident(speaker_id)


## Small chips above the speaker name ("▲ 신뢰 +3", "경계 풀림"). [[text, color], ...]
func set_notes(notes: Array) -> void:
	for c in note_box.get_children():
		note_box.remove_child(c)
		c.queue_free()
	for n: Array in notes:
		var c: Color = n[1] if n.size() > 1 else UiTokens.TEXT
		note_box.add_child(cream_note_chip(String(n[0]), c) if layout == Layout.CENTER else note_chip(String(n[0]), c))
	note_box.visible = notes.size() > 0 or layout == Layout.STRIP


## [[id, label], [id, label, disabled, hint], ...] — at most three are shown.
func set_choices(choices: Array) -> void:
	for c in _choices_box.get_children():
		_choices_box.remove_child(c)
		c.queue_free()
	_ids.clear()
	_buttons.clear()
	if layout == Layout.CENTER:
		_set_center_choices(choices)
		return
	for i in mini(choices.size(), MAX_CHOICES):
		var ch: Array = choices[i]
		var id := StringName(ch[0])
		var b := Button.new()
		b.theme_type_variation = &"ButtonSecondary"
		b.custom_minimum_size = Vector2(430, 58)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "        " + String(ch[1])
		b.disabled = ch.size() > 2 and bool(ch[2])
		if ch.size() > 3 and String(ch[3]) != "":
			b.text += "  ·  " + String(ch[3])
		b.focus_mode = Control.FOCUS_ALL
		var chip := KeyChip.new(str(i + 1), KeyChip.Style.DARK)
		chip.position = Vector2(18, 16)
		b.add_child(chip)
		b.pressed.connect(func() -> void: choice_made.emit(id))
		_choices_box.add_child(b)
		_ids.append(id)
		_buttons.append(b)


func choice_ids() -> Array[StringName]:
	return _ids.duplicate()


func choice_button(id: StringName) -> Button:
	var i := _ids.find(id)
	return null if i < 0 else _buttons[i]


## Presses a choice as the player would (keys, tests). Disabled choices do nothing.
func pick(id: StringName) -> bool:
	var b := choice_button(id)
	if b == null or b.disabled:
		return false
	choice_made.emit(id)
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed() or event.is_echo():
		return
	var k := (event as InputEventKey).keycode
	var idx := -1
	if k >= KEY_1 and k <= KEY_3:
		idx = k - KEY_1
	elif (k == KEY_ENTER or k == KEY_KP_ENTER) and enter_picks_single and _ids.size() == 1:
		idx = 0
	if idx >= 0 and idx < _ids.size() and pick(_ids[idx]):
		get_viewport().set_input_as_handled()


static func note_chip(text: String, color: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(99)
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override(&"panel", sb)
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"LabelHud"
	l.add_theme_font_size_override(&"font_size", 15)
	l.add_theme_color_override(&"font_color", color)
	p.add_child(l)
	return p


# ---------------- Layout.CENTER ----------------

func _build_center() -> void:
	var col := VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 1.0
	col.anchor_bottom = 1.0
	col.offset_left = -560
	col.offset_right = 560
	col.offset_bottom = -96
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.add_theme_constant_override(&"separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	# Name pill on the box's top edge (drawn above the box).
	var pill_row := MarginContainer.new()
	pill_row.add_theme_constant_override(&"margin_left", 30)
	pill_row.add_theme_constant_override(&"margin_bottom", -20)
	pill_row.z_index = 1
	pill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = UiTokens.ACCENT
	psb.set_corner_radius_all(99)
	psb.content_margin_left = 22
	psb.content_margin_right = 22
	psb.content_margin_top = 3
	psb.content_margin_bottom = 4
	pill.add_theme_stylebox_override(&"panel", psb)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	speaker_label = Label.new()
	speaker_label.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	speaker_label.add_theme_font_size_override(&"font_size", 21)
	speaker_label.add_theme_color_override(&"font_color", UiTokens.ACCENT_TEXT)
	pill.add_child(speaker_label)
	pill_row.add_child(pill)
	col.add_child(pill_row)
	_speaker_pill = pill_row
	var box := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = UiTokens.CREAM
	bsb.set_corner_radius_all(18)
	bsb.content_margin_left = 38
	bsb.content_margin_right = 38
	bsb.content_margin_top = 34
	bsb.content_margin_bottom = 26
	bsb.shadow_color = Color(0, 0, 0, 0.35)
	bsb.shadow_size = 16
	bsb.shadow_offset = Vector2(0, 8)
	box.add_theme_stylebox_override(&"panel", bsb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", 10)
	box.add_child(text)
	note_box = HBoxContainer.new()
	note_box.add_theme_constant_override(&"separation", 8)
	note_box.visible = false
	text.add_child(note_box)
	line_label = Label.new()
	line_label.theme_type_variation = &"LabelOnCream"
	line_label.add_theme_font_size_override(&"font_size", 26)
	line_label.add_theme_constant_override(&"line_spacing", 6)
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.max_lines_visible = MAX_LINES
	line_label.custom_minimum_size = Vector2(1044, 0)
	text.add_child(line_label)
	col.add_child(box)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	col.add_child(gap)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 14)
	col.add_child(row)
	_choices_box = row  # no portrait in this layout (portrait stays null)


func _set_center_choices(choices: Array) -> void:
	var primary := -1
	for i in mini(choices.size(), MAX_CHOICES):
		var ch: Array = choices[i]
		var id := StringName(ch[0])
		var off := ch.size() > 2 and bool(ch[2])
		if primary < 0 and not off:
			primary = i
		var b := Button.new()
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(0, 60)
		b.text = "%d · %s" % [i + 1, String(ch[1])]
		if ch.size() > 3 and String(ch[3]) != "":
			b.text += "  —  " + String(ch[3])
		b.disabled = off
		b.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
		b.add_theme_font_size_override(&"font_size", 19)
		var ring := i == primary
		for st: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
			b.add_theme_stylebox_override(st, _pill_style(st, ring))
		for c in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
			b.add_theme_color_override(c, UiTokens.TEXT_ON_CREAM)
		b.add_theme_color_override(&"font_disabled_color", UiTokens.TEXT_ON_CREAM_DIM)
		b.pressed.connect(func() -> void: choice_made.emit(id))
		_choices_box.add_child(b)
		_ids.append(id)
		_buttons.append(b)


## Index of the choice that wears the yellow ring (-1 = none). Tests read it.
func primary_choice() -> int:
	for i in _buttons.size():
		if not _buttons[i].disabled:
			return i
	return -1


## Cream pill; `ring` = the choice to press now (the one yellow on the screen).
static func _pill_style(state: StringName, ring: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(99)
	sb.bg_color = Color("fffaf0") if state != &"disabled" else Color(UiTokens.CREAM_2, 0.85)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.border_color = Color(UiTokens.TEXT_ON_CREAM, 0.18)
	sb.set_border_width_all(2)
	if state in [&"hover", &"focus", &"pressed"]:
		sb.border_color = UiTokens.TEXT_ON_CREAM
	if ring and state != &"disabled":
		sb.border_color = UiTokens.ACCENT
		sb.set_border_width_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	if state == &"focus":
		sb.draw_center = false  # focus draws over the normal style
		sb.shadow_size = 0
	return sb


## A note on the cream box: CREAM_2 chip, the shape glyph and words in a cream-safe tone.
static func cream_note_chip(text: String, color: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(99)
	sb.bg_color = UiTokens.CREAM_2
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override(&"panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	l.add_theme_font_size_override(&"font_size", 15)
	l.add_theme_color_override(&"font_color", on_cream(color))
	p.add_child(l)
	return p


## A dark-background status colour turned into one readable on cream. Yellow becomes ink: yellow is
## kept for the one button to press.
static func on_cream(c: Color) -> Color:
	if c.is_equal_approx(UiTokens.GOOD):
		return Color("2f8a3a")
	if c.is_equal_approx(UiTokens.WARN):
		return Color("a0620f")
	if c.is_equal_approx(UiTokens.INFO):
		return Color("1f6f74")
	if c.is_equal_approx(UiTokens.DANGER):
		return UiTokens.DANGER.darkened(0.2)
	if c.is_equal_approx(UiTokens.TEXT_DIM):
		return UiTokens.TEXT_ON_CREAM_DIM
	return UiTokens.TEXT_ON_CREAM
