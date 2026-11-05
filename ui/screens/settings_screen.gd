class_name SettingsScreen
extends MenuScreen
## Settings · accessibility · key remapping (D-15). Owner: Lane D.
## Design 14 "설정", "접근성 설정" · 12 "난이도". UI_RULES §9: menu tabs on top, the list on the
## left, a cream "읽을거리" card on the right with what the focused item does and a live preview,
## and a cream key-capture card + yellow confirm for remapping.
##
## Values: Settings.get_value / set_value / apply_preset / matching_preset (A). Keys and their
## names: SettingsCatalog. Bindings: InputMap actions registered by InputSetup (A). Graphics rows
## are applied straight to the window (Settings has no graphics keys yet, so they are not saved).
##
## open_with({"tab": &"access", "new_game": bool, "focus": key}) — all optional. `new_game` is
## true when opened from the title before a game starts: only then can hardcore be picked.

const NOTE_DISPLAY := "아직 저장되지 않는 항목이에요. 게임을 다시 켜면 처음 값으로 돌아가요."
const NOTE_KEYS := "키 배치는 아직 저장되지 않아요. 게임을 다시 켜면 기본 키로 돌아가요."
const NOTE_HARDCORE := "하드코어는 새 게임을 시작할 때만 고를 수 있어요."
const LOCK_HARDCORE := "하드코어 게임은 난이도를 바꿀 수 없어요."
const NOTE_TTS := "이 빌드는 음성 출력(프로젝트 설정)이 아직 꺼져 있어 소리가 나지 않아요."

## Quick accessibility screen (title): one list, no tabs, "확인" button.
var quick := false
var new_game := false

var _tab: StringName = &"access"
var _pending_focus: StringName = &""
var _tab_buttons := {}
var _rows: Array[SettingRow] = []
var _list: VBoxContainer
var _scroll: ScrollContainer
var _list_title: Label
var _list_count: Label
var _card_title: Label
var _card_desc: Label
var _card_default: Label
var _card_note: Label
var _preview: VBoxContainer
var _focus_row: SettingRow
var _refresh_queued := false
## Key capture overlay (null when not capturing).
var _capture: Control
var _capture_action: StringName = &""
var _capture_frame := 0
var _dialog: ConfirmDialog


func _init() -> void:
	title_text = "설정"
	footer_keys = [["Esc", "뒤로"], ["Q / E", "탭"], ["← / →", "값 바꾸기"], ["Enter", "선택"],
		["Backspace", "기본값"]]
	header_resources = []


func open_with(args: Dictionary) -> void:
	if args.has("new_game"):
		new_game = bool(args.new_game)
	if args.has("tab") and _has_tab(StringName(args.tab)):
		_tab = StringName(args.tab)
	if args.has("focus"):
		_pending_focus = StringName(args.focus)
	if _list != null:
		_show_tab(_tab)


func _build_body(b: Control) -> void:
	if not quick:
		_build_tabs()
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override(&"separation", 26)
	b.add_child(root)
	var left: Array = MenuScreen.panel("", "")
	var lp: PanelContainer = left[0]
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(lp)
	var lv: VBoxContainer = left[1]
	var band: HBoxContainer = left[2]
	_list_title = band.get_child(0) as Label
	_list_count = band.get_child(1) as Label
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	lv.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 2)
	_scroll.add_child(_list)
	if quick:
		lv.add_child(_quick_buttons())

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(620, 0)
	right.add_theme_constant_override(&"separation", 18)
	root.add_child(right)
	var card: Array = MenuScreen.cream_card(620)
	var cv: VBoxContainer = card[1]
	cv.add_theme_constant_override(&"separation", 10)
	_card_title = MenuScreen.label("", &"LabelSection")
	_card_title.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	cv.add_child(_card_title)
	_card_desc = MenuScreen.label("", &"LabelOnCream")
	_card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_card_desc)
	_card_default = MenuScreen.label("", &"LabelOnCreamDim")
	cv.add_child(_card_default)
	_card_note = MenuScreen.label("", &"LabelOnCreamDim")
	_card_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_note.add_theme_color_override(&"font_color", UiTokens.DANGER.darkened(0.25))
	cv.add_child(_card_note)
	right.add_child(card[0])
	var pv := PanelContainer.new()
	pv.theme_type_variation = &"PanelSlateInner"
	_preview = VBoxContainer.new()
	_preview.add_theme_constant_override(&"separation", 14)
	pv.add_child(_preview)
	right.add_child(pv)

	EventBus.settings_changed.connect(_on_settings_changed)
	_show_tab(_tab)


func _build_tabs() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 6)
	var group := ButtonGroup.new()
	for t: Array in SettingsCatalog.TABS:
		var btn := MenuScreen.button(String(t[1]), &"TabText")
		btn.toggle_mode = true
		btn.button_group = group
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_show_tab.bind(t[0]))
		bar.add_child(btn)
		_tab_buttons[t[0]] = btn
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.position.y = 34


func _quick_buttons() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_END
	var all := MenuScreen.button("모든 설정 보기", &"ButtonSecondary")
	all.pressed.connect(func() -> void: UI.open(&"settings", {"new_game": new_game}))
	row.add_child(all)
	var ok := MenuScreen.button("확인", &"ButtonPrimary")
	ok.custom_minimum_size = Vector2(180, 0)
	ok.pressed.connect(close)
	row.add_child(ok)
	return row


# ---------------- tabs and rows ----------------

func _has_tab(id: StringName) -> bool:
	for t: Array in SettingsCatalog.TABS:
		if t[0] == id:
			return true
	return false


func _tab_name(id: StringName) -> String:
	for t: Array in SettingsCatalog.TABS:
		if t[0] == id:
			return String(t[1])
	return ""


func _show_tab(id: StringName) -> void:
	_tab = id
	if _tab_buttons.has(id):
		(_tab_buttons[id] as Button).button_pressed = true
	MenuScreen.clear(_list)
	_rows.clear()
	_focus_row = null
	var first := true
	for r: Dictionary in _rows_for(id):
		if r.has("heading"):
			var h := MenuScreen.label(String(r.heading), &"LabelHud")
			h.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
			if not first:
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(0, 10)
				_list.add_child(gap)
			_list.add_child(h)
			first = false
			continue
		first = false
		var row := SettingRow.new(r)
		row.stepped.connect(_on_stepped)
		row.activated.connect(_on_activated)
		row.row_focused.connect(_on_row_focused)
		_list.add_child(row)
		_rows.append(row)
	_list_title.text = "접근성 빠른 설정" if quick else _tab_name(id)
	_list_count.text = "%d개" % _rows.size()
	_refresh_rows()
	_scroll.scroll_vertical = 0
	var target: SettingRow = _rows[0] if not _rows.is_empty() else null
	for row in _rows:
		if row.key == _pending_focus:
			target = row
	_pending_focus = &""
	if target != null:
		_focus_later(target)
		_update_card(target)
	_refresh_preview()


## Focus after the list has its size, then scroll it into view (follow_focus runs too early).
func _focus_later(row: SettingRow) -> void:
	await get_tree().process_frame
	if not is_instance_valid(row) or not row.is_inside_tree():
		return
	row.grab_focus()
	await get_tree().process_frame
	if is_instance_valid(row) and row.is_inside_tree():
		_scroll.ensure_control_visible(row)


func _rows_for(id: StringName) -> Array:
	if quick:
		var out: Array = []
		for k: StringName in SettingsCatalog.QUICK_KEYS:
			var r := SettingsCatalog.row(k)
			if not r.is_empty():
				out.append(r)
		return out
	match id:
		&"controls":
			var out: Array = []
			for r: Dictionary in SettingsCatalog.tab_rows(id):
				if r.get("key", &"") == &"bindings_reset":
					for a: Array in SettingsCatalog.ACTIONS:
						if InputMap.has_action(a[0]):
							out.append({"key": a[0], "kind": "binding", "label": a[1],
								"desc": "%s에 쓸 키입니다. Enter를 누른 뒤 새 키나 버튼을 누르세요." % a[1]})
				out.append(r)
			return out
		&"difficulty":
			return _difficulty_rows()
	return SettingsCatalog.tab_rows(id)


func _difficulty_rows() -> Array:
	var opts: Array = []
	for pid: StringName in Settings.PRESETS:
		if pid == &"hardcore" and not new_game and not bool(Settings.get_value(&"hardcore")):
			continue
		opts.append([pid, String(SettingsCatalog.PRESET_NAMES.get(pid, pid))])
	var out: Array = [{"heading": "난이도 고르기"},
		{"key": &"difficulty", "kind": "preset", "label": "난이도", "options": opts,
			"custom_text": SettingsCatalog.PRESET_NAMES[Settings.CUSTOM], "desc": ""},
		{"heading": "항목별로 바꾸기 (보호 모드)"}]
	out.append_array(SettingsCatalog.difficulty_rows())
	return out


func _difficulty_locked() -> bool:
	return bool(Settings.get_value(&"hardcore")) and not new_game


func _refresh_rows() -> void:
	_refresh_queued = false
	var locked := _difficulty_locked()
	for row in _rows:
		match row.kind:
			"binding":
				row.show_bindings([["키보드", _bind_text(row.key, false)], ["패드", _bind_text(row.key, true)]])
			"button":
				pass
			"display":
				row.show_value(_display_get(row.key))
			"preset":
				row.show_value(Settings.matching_preset())
				row.set_locked(locked, LOCK_HARDCORE)
			"protect":
				row.show_value(Settings.matching_preset() == &"story")
				row.set_locked(locked, LOCK_HARDCORE)
			_:
				row.show_value(Settings.get_value(row.key))
				if row.key in Settings.DIFFICULTY_KEYS:
					row.set_locked(locked, LOCK_HARDCORE)
	if _focus_row != null and is_instance_valid(_focus_row):
		_update_card(_focus_row)


func _queue_refresh() -> void:
	if _refresh_queued or _list == null:
		return
	_refresh_queued = true
	(func() -> void:
		if is_instance_valid(self) and _refresh_queued:
			_refresh_rows()
			_refresh_preview()).call_deferred()


func _bind_text(action: StringName, pad: bool) -> String:
	var ev := SettingsCatalog.binding(action, pad)
	return SettingsCatalog.event_text(ev) if ev != null else ""


# ---------------- changing values ----------------

func _on_stepped(row: SettingRow, value: Variant) -> void:
	match row.kind:
		"display":
			_display_set(row.key, value)
		"preset":
			if not Settings.apply_preset(StringName(value), new_game):
				return
		"protect":
			if not Settings.apply_preset(&"story" if bool(value) else &"normal", new_game):
				return
		_:
			if not Settings.set_value(row.key, value):
				return
	_refresh_rows()
	_refresh_preview()
	MenuReader.say(row.tts_text())


func _on_activated(row: SettingRow) -> void:
	match row.kind:
		"binding":
			start_capture(row.key)
		"button":
			if row.data.get("action", &"") == &"reset_bindings":
				_ask("모든 키를 기본값으로 되돌릴까요?", "키보드·마우스와 게임패드 모두 처음 배치로 돌아가요.",
					"되돌리기", reset_all_bindings, row)


func reset_all_bindings() -> void:
	InputSetup.apply_defaults(true)
	_refresh_rows()


## Backspace: the focused row goes back to its default value.
func reset_row(row: SettingRow) -> void:
	if row == null or row.locked:
		return
	match row.kind:
		"binding":
			_restore_default_binding(row.key)
		"display":
			_display_set(row.key, SettingsCatalog.DISPLAY_DEFAULTS.get(row.key))
		"preset", "protect":
			Settings.apply_preset(Settings.DEFAULTS[&"difficulty"], new_game)
		"button":
			return
		_:
			if Settings.DEFAULTS.has(row.key):
				Settings.set_value(row.key, Settings.DEFAULTS[row.key])
	_refresh_rows()
	_refresh_preview()
	MenuReader.say(row.tts_text())


func _restore_default_binding(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	for spec: Dictionary in InputSetup.DEFAULTS.get(action, []):
		InputMap.action_add_event(action, SettingsCatalog.spec_event(spec))


func _on_settings_changed(_key: StringName) -> void:
	_queue_refresh()


# ---------------- graphics (window) ----------------

func _display_get(key: StringName) -> Variant:
	match key:
		&"gfx_window_mode":
			match DisplayServer.window_get_mode():
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
					return 1
				DisplayServer.WINDOW_MODE_FULLSCREEN:
					return 2
			return 0
		&"gfx_vsync":
			return DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
		&"gfx_max_fps":
			return Engine.max_fps
		&"gfx_render_scale":
			return snappedf(get_viewport().scaling_3d_scale, 0.01)
	return null


func _display_set(key: StringName, value: Variant) -> void:
	match key:
		&"gfx_window_mode":
			var modes := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
				DisplayServer.WINDOW_MODE_FULLSCREEN]
			DisplayServer.window_set_mode(modes[clampi(int(value), 0, 2)])
		&"gfx_vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(value) else DisplayServer.VSYNC_DISABLED)
		&"gfx_max_fps":
			Engine.max_fps = int(value)
		&"gfx_render_scale":
			get_viewport().scaling_3d_scale = float(value)


# ---------------- description card + preview ----------------

func _on_row_focused(row: SettingRow) -> void:
	_focus_row = row
	_update_card(row)


func _update_card(row: SettingRow) -> void:
	_card_title.text = String(row.data.get("label", ""))
	var desc := String(row.data.get("desc", ""))
	var def_text := ""
	var note := ""
	match row.kind:
		"preset":
			desc = String(SettingsCatalog.PRESET_DESC.get(Settings.matching_preset(), ""))
			def_text = "기본값: " + String(SettingsCatalog.PRESET_NAMES.get(Settings.DEFAULTS[&"difficulty"], ""))
			if not new_game:
				note = NOTE_HARDCORE
		"protect":
			def_text = "기본값: 끔 (보통 난이도)"
		"binding":
			var kb := SettingsCatalog.default_binding_text(row.key, false)
			var pad := SettingsCatalog.default_binding_text(row.key, true)
			def_text = "기본 키: 키보드 %s · 패드 %s" % [kb if not kb.is_empty() else "없음", pad if not pad.is_empty() else "없음"]
			note = NOTE_KEYS
		"button":
			if row.data.get("action", &"") == &"reset_bindings":
				note = NOTE_KEYS
		"display":
			def_text = "기본값: " + SettingsCatalog.value_text(row.data, SettingsCatalog.DISPLAY_DEFAULTS.get(row.key))
			note = NOTE_DISPLAY
		_:
			if Settings.DEFAULTS.has(row.key):
				def_text = "기본값: " + SettingsCatalog.value_text(row.data, Settings.DEFAULTS[row.key])
			if row.key == &"tts_menu" and not MenuReader.can_speak():
				note = NOTE_TTS
	if row.locked:
		note = row.lock_reason
	_card_desc.text = desc
	_card_default.text = def_text
	_card_default.visible = not def_text.is_empty()
	_card_note.text = note
	_card_note.visible = not note.is_empty()


## Live sample of what the accessibility values change: subtitle, rarity / element badges
## (colour + shape), status chips (colour + shape + word) and body text at the current size.
func _refresh_preview() -> void:
	if _preview == null:
		return
	MenuScreen.clear(_preview)
	_preview.add_child(MenuScreen.label("미리보기", &"LabelSection"))
	# subtitle
	if bool(Settings.get_value(&"subtitles")):
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, float(Settings.get_value(&"subtitle_bg_alpha")) * 0.6)
		sb.set_corner_radius_all(UiTokens.CARD_RADIUS)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		p.add_theme_stylebox_override(&"panel", sb)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var px := roundi(UiTokens.SIZE_SUBTITLE * UiTokens.SUBTITLE_SCALES[clampi(int(Settings.get_value(&"subtitle_size")), 0, 2)])
		rt.add_theme_font_size_override(&"normal_font_size", px)
		rt.add_theme_font_size_override(&"bold_font_size", px)
		rt.add_theme_font_override(&"normal_font", UiThemeBuilder.font_kr(500))
		rt.add_theme_font_override(&"bold_font", UiThemeBuilder.font_kr(700))
		rt.add_theme_color_override(&"font_shadow_color", UiTokens.SHADOW)
		rt.add_theme_constant_override(&"shadow_offset_y", 2)
		var head := "[color=#%s][b]방송실 지기[/b][/color]  " % UiTokens.ACCENT.to_html(false) \
			if bool(Settings.get_value(&"subtitle_speaker")) else ""
		rt.text = head + "북쪽 골목이 시끄러워요. 오늘은 돌아서 가요."
		p.add_child(rt)
		_preview.add_child(p)
	else:
		_preview.add_child(MenuScreen.label("자막 꺼짐", &"LabelDim"))
	# rarity + element: colour and shape together
	var rar := HBoxContainer.new()
	rar.add_theme_constant_override(&"separation", 18)
	for i in UiTokens.RARITY_NAMES.size():
		rar.add_child(_badge(ShapeBadge.Kind.RARITY, i))
	_preview.add_child(rar)
	var el := HBoxContainer.new()
	el.add_theme_constant_override(&"separation", 18)
	for i in range(1, UiTokens.ELEMENT_NAMES.size()):
		el.add_child(_badge(ShapeBadge.Kind.ELEMENT, i))
	_preview.add_child(el)
	var st := HBoxContainer.new()
	st.add_theme_constant_override(&"separation", 22)
	for s: Array in [["▲ 위험", UiTokens.DANGER], ["◆ 주의", UiTokens.WARN], ["● 완료", UiTokens.GOOD],
			["■ 정보", UiTokens.INFO]]:
		var l := MenuScreen.label(String(s[0]), &"LabelHud")
		l.add_theme_color_override(&"font_color", s[1])
		st.add_child(l)
	_preview.add_child(st)
	var body_l := MenuScreen.label("가방 18/30 · 해질녘까지 04:12 · [F] 뒤지기", &"Label")
	_preview.add_child(body_l)
	_preview.add_child(MenuScreen.label("작은 글: 무게 3.2 · 가격 120", &"LabelDim"))


func _badge(kind: ShapeBadge.Kind, value: int) -> ShapeBadge:
	var b := ShapeBadge.new()
	b.kind = kind
	b.value = value
	b.badge_size = 16
	b.show_label = true
	return b


# ---------------- key remapping ----------------

## Opens the cream capture card; the next key / mouse button / pad button becomes the new binding
## (after a yellow confirm). Esc cancels.
func start_capture(action: StringName) -> void:
	_close_capture()
	_capture_action = action
	_capture_frame = Engine.get_process_frames()
	var o := Control.new()
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.z_index = 70
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.12, 0.15, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	var card: Array = MenuScreen.cream_card(560)
	var c: PanelContainer = card[0]
	var v: VBoxContainer = card[1]
	v.add_theme_constant_override(&"separation", 12)
	var name_text := SettingsCatalog.action_name(action)
	var t := MenuScreen.label("‘%s’ 키 다시 정하기" % name_text, &"LabelSection")
	t.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	v.add_child(t)
	var body_text := "새 키나 버튼을 누르세요. 키보드·마우스로 누르면 키보드 칸이, 게임패드로 누르면 패드 칸이 바뀌어요."
	var b := MenuScreen.label(body_text, &"LabelOnCream")
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(b)
	var kb := _bind_text(action, false)
	var pad := _bind_text(action, true)
	v.add_child(MenuScreen.label("지금: 키보드 %s · 패드 %s" % [kb if not kb.is_empty() else "없음",
		pad if not pad.is_empty() else "없음"], &"LabelOnCreamDim"))
	var foot := PanelContainer.new()
	foot.theme_type_variation = &"CardCreamFoot"
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override(&"separation", 8)
	fh.add_child(KeyChip.new("Esc", KeyChip.Style.DARK))
	fh.add_child(MenuScreen.label("취소", &"LabelOnCreamDim"))
	foot.add_child(fh)
	v.add_child(foot)
	o.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(o)
	_capture = o
	MenuReader.say("%s. %s" % [t.text, body_text])


func is_capturing() -> bool:
	return _capture != null


func _close_capture() -> void:
	if _capture != null:
		_capture.queue_free()
	_capture = null


func _input(event: InputEvent) -> void:
	if _capture == null:
		return
	var ev := captured_event(event)
	var cancel: bool = event is InputEventKey and event.pressed and not event.echo \
		and (event as InputEventKey).physical_keycode == KEY_ESCAPE
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton \
			or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
	if Engine.get_process_frames() <= _capture_frame:
		return  # the press that opened the card
	if cancel:
		var a := _capture_action
		_close_capture()
		_focus_action_row(a)
		return
	if ev != null:
		var a := _capture_action
		_close_capture()
		confirm_binding(a, ev)


## A clean binding made from a raw press, or null if the event is not a press we bind.
static func captured_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if code == KEY_ESCAPE or code == KEY_NONE:
			return null
		var k := InputEventKey.new()
		k.physical_keycode = code
		return k
	if event is InputEventMouseButton and event.pressed:
		var m := InputEventMouseButton.new()
		m.button_index = event.button_index
		return m
	if event is InputEventJoypadButton and event.pressed:
		var jb := InputEventJoypadButton.new()
		jb.button_index = event.button_index
		return jb
	if event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		var jm := InputEventJoypadMotion.new()
		jm.axis = event.axis
		jm.axis_value = signf(event.axis_value)
		return jm
	return null


## Yellow confirm card for a new binding. Same key as now: nothing to ask.
func confirm_binding(action: StringName, ev: InputEvent) -> void:
	var pad := SettingsCatalog.is_pad(ev)
	var old := SettingsCatalog.binding(action, pad)
	if old != null and SettingsCatalog.event_id(old) == SettingsCatalog.event_id(ev):
		_focus_action_row(action)
		return
	var name_text := SettingsCatalog.action_name(action)
	var new_text := SettingsCatalog.event_text(ev)
	var old_text := SettingsCatalog.event_text(old) if old != null else "없음"
	var conflict := find_conflict(ev, action)
	var body := "%s → %s" % [old_text, new_text]
	if not conflict.is_empty():
		var other := SettingsCatalog.action_name(conflict[0])
		if old != null:
			body = "%s은(는) 지금 ‘%s’에 쓰이고 있어요. 바꾸면 ‘%s’에는 %s이(가) 들어가요." % [new_text, other, other, old_text]
		else:
			body = "%s은(는) 지금 ‘%s’에 쓰이고 있어요. 바꾸면 ‘%s’의 %s 칸은 비어요." % [new_text, other, other,
				"패드" if pad else "키보드"]
	var apply := func() -> void: apply_binding(action, ev)
	_ask("‘%s’ 키를 %s(으)로 바꿀까요?" % [name_text, new_text], body, "바꾸기", apply, null, action)


## Replaces the action's binding of the same device class with `ev`. If another remappable
## action used `ev`, it gets this action's old binding (swap). Returns that action or &"".
func apply_binding(action: StringName, ev: InputEvent) -> StringName:
	var pad := SettingsCatalog.is_pad(ev)
	var old := SettingsCatalog.binding(action, pad)
	var conflict := find_conflict(ev, action)
	if old != null:
		InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, ev)
	var other: StringName = &""
	if not conflict.is_empty():
		other = conflict[0]
		InputMap.action_erase_event(other, conflict[1])
		if old != null:
			InputMap.action_add_event(other, old)
	_refresh_rows()
	return other


## [action, event] of another remappable action already using `ev`, or [].
func find_conflict(ev: InputEvent, except: StringName) -> Array:
	var id := SettingsCatalog.event_id(ev)
	for a: Array in SettingsCatalog.ACTIONS:
		if a[0] == except or not InputMap.has_action(a[0]):
			continue
		for e in InputMap.action_get_events(a[0]):
			if SettingsCatalog.event_id(e) == id:
				return [a[0], e]
	return []


func _focus_action_row(action: StringName) -> void:
	for row in _rows:
		if row.key == action:
			row.grab_focus()
			return


func _ask(title: String, body: String, action: String, on_ok: Callable, back_to: SettingRow = null,
		back_action: StringName = &"") -> void:
	_dialog = ConfirmDialog.ask(self, title, body, action, on_ok)
	_dialog.decided.connect(func(_ok: bool) -> void:
		_dialog = null
		if back_to != null and is_instance_valid(back_to):
			back_to.grab_focus()
		elif back_action != &"":
			_focus_action_row(back_action))


func pending_dialog() -> ConfirmDialog:
	return _dialog if _dialog != null and is_instance_valid(_dialog) else null


# ---------------- keys ----------------

func _unhandled_key_input(event: InputEvent) -> void:
	if _capture != null or pending_dialog() != null:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_Q, KEY_E:
			if quick:
				return
			var ids: Array = []
			for t: Array in SettingsCatalog.TABS:
				ids.append(t[0])
			var i := posmod(ids.find(_tab) + (1 if k.keycode == KEY_E else -1), ids.size())
			_show_tab(ids[i])
		KEY_BACKSPACE:
			var f := get_viewport().gui_get_focus_owner()
			if f is SettingRow:
				reset_row(f)
		_:
			return
	get_viewport().set_input_as_handled()
