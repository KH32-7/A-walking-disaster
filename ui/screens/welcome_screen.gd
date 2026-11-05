extends MenuScreen
## 입주 의식 (D-13). Owner: Lane D. Design 07 "입주 의식". Flow data is Colony's (C-13):
## arrival_info() → set_nickname() → set_appearance() → choose_bed() → complete_arrival().
## Left: the newcomer's full body (CharacterLook, updates as the look changes). Right: one cream card
## per step with the step track on top (도착 · 이름 · 외형 · 침상 · 첫 대화).
## open_with({"resident_id": id}); without an id it takes the oldest Colony.pending_arrivals().

const STEP_NAMES := {&"welcome": "도착", &"name": "이름", &"appearance": "외형", &"bed": "침상", &"first_talk": "첫 대화"}
const HAIR_NAMES := {"short": "짧은 머리", "bob": "단발", "long": "긴 머리", "tied": "묶은 머리", "cap": "모자"}
## Colour presets for 머리·옷 (design 07 "프리셋 조합"). Display palette only.
const HAIR_COLORS: Array[Color] = [Color("1f1b1a"), Color("3b2a22"), Color("7a4a2a"), Color("c9a063"), Color("8e8c88"),
	Color("9e3b2e")]
const OUTFIT_COLORS: Array[Color] = [Color("5f7d6a"), Color("2f7378"), Color("3d5a8a"), Color("8a3d3d"), Color("c9a24a"),
	Color("6b6b6b")]
const COLOR_NAMES := ["1", "2", "3", "4", "5", "6"]

var resident_id: StringName = &""
var step := 0
var _info: Dictionary = {}
var _result: Dictionary = {}
var _error := ""
var _nick_edit: LineEdit

var _portrait: ResidentPortrait
var _who: Label
var _track: StepTrack
var _card: VBoxContainer
var _next_button: Button


func _init() -> void:
	title_text = "입주 의식"
	subtitle_text = "새 식구"
	show_back = false
	footer_keys = [["Enter", "다음"], ["Esc", "나중에"]]
	header_resources = []


func open_with(args: Dictionary) -> void:
	resident_id = StringName(args.get("resident_id", args.get("id", &"")))
	if _card != null:
		_begin()


func _build_body(b: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 40)
	b.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 10)
	left.custom_minimum_size = Vector2(600, 0)
	row.add_child(left)
	_portrait = ResidentPortrait.new(Vector2(600, 760), ResidentPortrait.Framing.FULL)
	left.add_child(_portrait)
	_who = MenuScreen.label("", &"LabelTitle", 28)
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_who)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 26)
	row.add_child(right)
	_track = StepTrack.new()
	right.add_child(_track)
	var cc := MenuScreen.cream_card(0)
	(cc[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(cc[0])
	_card = cc[1]
	_card.add_theme_constant_override(&"separation", 14)
	_begin()


func _begin() -> void:
	if resident_id == &"" or Colony.arrival_info(resident_id).is_empty():
		var waiting := ResidentEventFlow.welcome_queue()  # family children get child_naming (#125)
		resident_id = waiting[0] if not waiting.is_empty() else &""
	step = 0
	_result = {}
	_error = ""
	_refresh()


func steps() -> Array:
	return _info.get("steps", ArrivalRules.STEPS)


func current_step() -> StringName:
	var s := steps()
	return StringName(s[clampi(step, 0, s.size() - 1)]) if not s.is_empty() else &""


func _refresh() -> void:
	_info = Colony.arrival_info(resident_id)
	MenuScreen.clear(_card)
	_next_button = null
	var names: Array = []
	for s in steps():
		names.append(STEP_NAMES.get(StringName(s), String(s)))
	_track.set_steps(names, step)
	if _info.is_empty():
		_who.text = ""
		_card.add_child(_title("맞이할 사람이 없어요"))
		_card.add_child(_text("필드에서 구한 사람이 기지에 오면 여기서 맞이해요."))
		_buttons([], "닫기", close)
		return
	# The resident's own model (ResidentModel, the one the base shows); only the 외형 step previews the
	# customisable body.
	if current_step() == &"appearance":
		_portrait.set_look(_info.get("appearance", {}), int(_info.get("age_stage", 3)))
	else:
		_portrait.set_resident(resident_id)
	var r := Colony.get_resident(resident_id)
	_who.text = ResidentText.full_name(r)
	match current_step():
		&"welcome":
			_step_welcome(r)
		&"name":
			_step_name(r)
		&"appearance":
			_step_appearance()
		&"bed":
			_step_bed()
		&"first_talk":
			_step_first_talk(r)


func _step_welcome(r: Dictionary) -> void:
	_card.add_child(_title("%s이(가) 기지에 왔어요" % String(r.get("name", ""))))
	var others: Array = []
	for id in Colony.active_resident_ids():
		if id != resident_id and not Colony.get_resident(id).get("arrival_pending", false):
			others.append(id)
	if others.is_empty():
		_card.add_child(_text("아직 맞아 줄 사람은 없지만, 오늘부터 여기가 집이에요."))
	else:
		_card.add_child(_text("주민들이 마중 나왔어요."))
		var f := HFlowContainer.new()
		f.add_theme_constant_override(&"h_separation", 8)
		f.add_theme_constant_override(&"v_separation", 8)
		for id in others.slice(0, 8):
			f.add_child(ResidentSceneScreen.cream_chip(ResidentText.call_name(Colony.get_resident(id))))
		_card.add_child(f)
	var bg := String(r.get("story", {}).get("background", ""))
	if bg != "":
		_card.add_child(_dim(bg))
	_buttons([], "맞이하기", _advance)


func _step_name(r: Dictionary) -> void:
	_card.add_child(_title("이름과 별명"))
	_card.add_child(_dim("본래 이름"))
	var nm := _text(String(r.get("name", "")))
	nm.add_theme_font_size_override(&"font_size", 26)
	_card.add_child(nm)
	_card.add_child(_dim("별명 짓기 — %d자까지, 비워 두면 별명 없이" % int(_info.get("nickname_max", 6))))
	_nick_edit = LineEdit.new()
	_nick_edit.text = String(_info.get("nickname", ""))
	_nick_edit.max_length = int(_info.get("nickname_max", 6))
	_nick_edit.placeholder_text = "예: 렌치, 목수 아저씨"
	_nick_edit.add_theme_font_size_override(&"font_size", 22)
	_nick_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_nick_edit.custom_minimum_size = Vector2(520, 56)
	var field := StyleBoxFlat.new()
	field.bg_color = Color.WHITE
	field.border_color = UiTokens.TEXT_ON_CREAM
	field.set_border_width_all(2)
	field.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	field.content_margin_left = 16
	field.content_margin_right = 16
	for st in [&"normal", &"focus", &"read_only"]:
		_nick_edit.add_theme_stylebox_override(st, field)
	_nick_edit.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	_nick_edit.add_theme_color_override(&"font_placeholder_color", UiTokens.TEXT_ON_CREAM_DIM)
	_nick_edit.add_theme_color_override(&"caret_color", UiTokens.TEXT_ON_CREAM)
	_nick_edit.text_submitted.connect(func(_t: String) -> void: _save_nickname())
	_card.add_child(_nick_edit)
	if _error != "":
		_card.add_child(_error_label(_error))
	_buttons([["이전", _back]], "다음", _save_nickname)


func _save_nickname() -> void:
	var res := Colony.set_nickname(resident_id, _nick_edit.text if _nick_edit != null else "")
	if res.get("ok", false):
		_error = ""
		_advance()
	else:
		_error = String(res.get("reason", ""))
		_refresh()


func _step_appearance() -> void:
	var look: Dictionary = _info.get("appearance", {})
	_card.add_child(_title("외형 꾸미기"))
	_card.add_child(_dim("기본 차림"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	for pid: StringName in CharacterLook.preset_ids():
		var p: AppearancePreset = CharacterLook.presets()[pid]
		var on := StringName(look.get("preset", &"")) == pid
		var b := _swatch_button([p.hair_color, p.outfit_color, p.outfit_accent], p.display_name, on, 340)
		b.pressed.connect(func() -> void: _set_look({"preset": pid, "hair": p.hair, "hair_color": p.hair_color,
			"outfit_color": p.outfit_color, "outfit_accent": p.outfit_accent, "skin": p.skin}))
		grid.add_child(b)
	_card.add_child(grid)
	_card.add_child(_dim("머리 모양"))
	var hair := HFlowContainer.new()
	hair.add_theme_constant_override(&"h_separation", 6)
	var cur_hair := String(look.get("hair", ""))
	if cur_hair == "":
		var cp: Variant = CharacterLook.presets().get(StringName(look.get("preset", &"")))
		cur_hair = cp.hair if cp != null else ""
	for h: String in _info.get("hair_styles", ArrivalRules.HAIR_STYLES):
		var b := _pick_button(HAIR_NAMES.get(h, h), h == cur_hair)
		b.pressed.connect(func() -> void: _set_look({"hair": h}))
		hair.add_child(b)
	_card.add_child(hair)
	_color_row("머리 색", HAIR_COLORS, "hair_color", look)
	_color_row("옷 색", OUTFIT_COLORS, "outfit_color", look)
	if _error != "":
		_card.add_child(_error_label(_error))
	_buttons([["이전", _back]], "다음", _advance)


func _color_row(title: String, colors: Array[Color], key: String, look: Dictionary) -> void:
	_card.add_child(_dim(title))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	var cur: Variant = look.get(key)
	if cur == null:
		var cp: Variant = CharacterLook.presets().get(StringName(look.get("preset", &"")))
		if cp != null:
			cur = cp.get(key)
	for i in colors.size():
		var c: Color = colors[i]
		var on := cur is Color and (cur as Color).is_equal_approx(c)
		var b := _swatch_button([c], COLOR_NAMES[i], on, 86)
		b.pressed.connect(func() -> void: _set_look({key: c}))
		h.add_child(b)
	_card.add_child(h)


func _set_look(change: Dictionary) -> void:
	var res := Colony.set_appearance(resident_id, change)
	_error = "" if res.get("ok", false) else String(res.get("reason", ""))
	_refresh()


func _step_bed() -> void:
	_card.add_child(_title("어디서 잘까요?"))
	var cur := StringName(_info.get("bed_id", &""))
	var beds: Array = _info.get("beds", [])
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	if cur != &"":
		v.add_child(_bed_row(cur, "지금 침상  ·  %s" % _bed_name(cur, ""), true))
	for bed: Dictionary in beds:
		var id := StringName(bed.bed_id)
		v.add_child(_bed_row(id, _bed_name(id, String(bed.get("building_name", ""))), false))
	v.add_child(_bed_row(&"", "임시 거처  ·  사기 %d/일, 침상이 생기면 옮길 수 있어요" % NeedsRules.NO_BED, cur == &""))
	_card.add_child(v)
	if beds.is_empty() and cur == &"":
		_card.add_child(_dim("빈 침상이 없어요. 건설에서 침상을 더 지을 수 있어요."))
	_buttons([["이전", _back]], "다음", _advance)


func _bed_row(bed_id: StringName, text: String, on: bool) -> Button:
	var b := _pick_button(text, on)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 50)
	b.pressed.connect(func() -> void:
		if Colony.choose_bed(resident_id, bed_id):
			_error = ""
		else:
			_error = "그 침상은 쓸 수 없어요."
		_refresh())
	return b


func _bed_name(bed_id: StringName, building: String) -> String:
	var s := String(bed_id)
	var num := s.get_slice("_bed_", s.get_slice_count("_bed_") - 1)
	if building == "":
		building = "방송실 야영지" if s.begins_with(Colony.START_BED_PREFIX) else "숙소"
	return "%s %s번 침상" % [building, num] if num.is_valid_int() else building


func _step_first_talk(r: Dictionary) -> void:
	if _result.is_empty():
		_result = Colony.complete_arrival(resident_id)
		r = Colony.get_resident(resident_id)
		_who.text = ResidentText.full_name(r)
	_card.add_child(_title("첫 대화"))
	var first := String(_result.get("first_line", ""))
	if first == "":
		first = "…고마워. 여기 있어도 될까?"
	var q := _text("“%s”" % first)
	q.add_theme_font_size_override(&"font_size", 26)
	_card.add_child(q)
	var bg := String(_result.get("background", ""))
	if bg != "":
		_card.add_child(_dim("들려준 이야기"))
		_card.add_child(_text(bg))
	var like := StringName(_result.get("like", &""))
	if like != &"":
		_card.add_child(_dim("좋아하는 것을 하나 알려 줬어요"))
		var chip := ResidentSceneScreen.cream_chip("▲ " + ResidentText.tag_name(like))
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_card.add_child(chip)
	var more := ResidentEventFlow.welcome_queue()
	more.erase(resident_id)
	if more.is_empty():
		_buttons([], "기지로", close)
	else:
		_buttons([], "다음 사람 맞이하기", func() -> void:
			resident_id = more[0]
			_begin())


func _advance() -> void:
	step = mini(step + 1, steps().size() - 1)
	_error = ""
	_refresh()


func _back() -> void:
	step = maxi(step - 1, 0)
	_error = ""
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER] \
			and _next_button != null and not (_nick_edit != null and _nick_edit.has_focus()):
		_next_button.pressed.emit()
		get_viewport().set_input_as_handled()


# ---------------- small builders ----------------

func _title(t: String) -> Label:
	var l := MenuScreen.label(t, &"LabelOnCream", 30)
	l.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	return l


func _text(t: String) -> Label:
	var l := MenuScreen.label(t, &"LabelOnCream", 19)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _dim(t: String) -> Label:
	var l := MenuScreen.label(t, &"LabelOnCreamDim", 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _error_label(t: String) -> Label:
	var l := MenuScreen.label("✕  " + t, &"LabelOnCream", 16)
	l.add_theme_color_override(&"font_color", UiTokens.DANGER.darkened(0.2))
	return l


## Cream-card choice: dark outline when picked (+ ✓), plain otherwise.
func _pick_button(text: String, on: bool) -> Button:
	var b := Button.new()
	b.text = text + ("  ✓" if on and text != "" else "")
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override(&"font_size", 16)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(99)
	sb.bg_color = UiTokens.CREAM_2 if not on else UiTokens.CREAM
	sb.border_color = UiTokens.TEXT_ON_CREAM if on else Color(UiTokens.TEXT_ON_CREAM, 0.15)
	sb.set_border_width_all(3 if on else 1)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	var hv := sb.duplicate() as StyleBoxFlat
	hv.border_color = UiTokens.TEXT_ON_CREAM
	hv.set_border_width_all(2 if not on else 3)
	b.add_theme_stylebox_override(&"normal", sb)
	b.add_theme_stylebox_override(&"pressed", sb)
	b.add_theme_stylebox_override(&"focus", hv)
	b.add_theme_stylebox_override(&"hover", hv)
	for c in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		b.add_theme_color_override(c, UiTokens.TEXT_ON_CREAM)
	return b


## A pick button with colour chips then the text (and ✓ when picked) in one row.
func _swatch_button(colors: Array, text: String, on: bool, min_w: float) -> Button:
	var b := _pick_button("", on)
	b.custom_minimum_size = Vector2(min_w, 48)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -12
	h.add_theme_constant_override(&"separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw := Swatches.new(colors)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sw)
	var l := MenuScreen.label(text + ("  ✓" if on else ""), &"LabelOnCream", 16)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	h.add_child(l)
	b.add_child(h)
	return b


## Footer of the card: secondary buttons on the left, the yellow one on the right.
func _buttons(extra: Array, main_text: String, main: Callable) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card.add_child(spacer)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	for e: Array in extra:
		var b := MenuScreen.button(String(e[0]), &"ButtonCancel")
		b.custom_minimum_size = Vector2(140, 54)
		b.pressed.connect(e[1])
		h.add_child(b)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(gap)
	_next_button = MenuScreen.button(main_text, &"ButtonPrimary")
	_next_button.custom_minimum_size = Vector2(220, 54)
	_next_button.pressed.connect(main)
	h.add_child(_next_button)
	_card.add_child(h)


## Step track (UI_RULES §5 "단계 표시"): dots joined by a line, the current step a big ring + name.
class StepTrack extends Control:
	var names: Array = []
	var current := 0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 74)

	func set_steps(n: Array, cur: int) -> void:
		names = n
		current = cur
		queue_redraw()

	func _draw() -> void:
		var n := names.size()
		if n == 0:
			return
		var font := UiThemeBuilder.font_kr(600)
		var y := 20.0
		var x0 := 30.0
		var x1 := size.x - 30.0
		draw_line(Vector2(x0, y), Vector2(x1, y), UiTokens.LINE, 2.0)
		draw_line(Vector2(x0, y), Vector2(lerpf(x0, x1, float(current) / maxf(n - 1, 1)), y), UiTokens.ACCENT, 3.0)
		for i in n:
			var x := lerpf(x0, x1, float(i) / maxf(n - 1, 1))
			if i == current:
				draw_circle(Vector2(x, y), 13, UiTokens.INK)
				draw_arc(Vector2(x, y), 13, 0, TAU, 32, UiTokens.ACCENT, 3.0, true)
				draw_circle(Vector2(x, y), 6, UiTokens.ACCENT)
			elif i < current:
				draw_circle(Vector2(x, y), 8, UiTokens.ACCENT)
			else:
				draw_circle(Vector2(x, y), 8, UiTokens.INK)
				draw_arc(Vector2(x, y), 8, 0, TAU, 24, UiTokens.LINE_STRONG, 2.0, true)
			var t := "%d  %s" % [i + 1, names[i]]
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, Vector2(x - w / 2.0, y + 42), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
				UiTokens.TEXT if i == current else UiTokens.TEXT_DIM)


## Small round colour chips drawn inside a button.
class Swatches extends Control:
	var colors: Array = []

	func _init(c: Array) -> void:
		colors = c
		custom_minimum_size = Vector2(6 + 14 * c.size(), 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in colors.size():
			var p := Vector2(10 + i * 14, 10)
			draw_circle(p, 9, colors[i])
			draw_arc(p, 9, 0, TAU, 20, Color(0, 0, 0, 0.35), 1.5, true)
