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

signal choice_made(choice_id: StringName)

const MAX_CHOICES := 3
const MAX_LINES := 2

## Enter picks the choice when there is only one (off when the screen uses Enter itself).
var enter_picks_single := true
var portrait: ResidentPortrait
var speaker_label: Label
var line_label: Label
var note_box: HBoxContainer
var _choices_box: VBoxContainer
var _ids: Array[StringName] = []
var _buttons: Array[Button] = []


func _init() -> void:
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
	text.add_theme_constant_override(&"separation", 6)
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
	portrait.visible = speaker_id != &""
	if speaker_id != &"":
		portrait.set_resident(speaker_id)


## Small chips above the speaker name ("▲ 신뢰 +3", "경계 풀림"). [[text, color], ...]
func set_notes(notes: Array) -> void:
	for c in note_box.get_children():
		note_box.remove_child(c)
		c.queue_free()
	for n: Array in notes:
		note_box.add_child(note_chip(String(n[0]), n[1] if n.size() > 1 else UiTokens.TEXT))


## [[id, label], [id, label, disabled, hint], ...] — at most three are shown.
func set_choices(choices: Array) -> void:
	for c in _choices_box.get_children():
		_choices_box.remove_child(c)
		c.queue_free()
	_ids.clear()
	_buttons.clear()
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
