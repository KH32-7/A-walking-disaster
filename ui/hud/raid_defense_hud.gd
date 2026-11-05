class_name RaidDefenseHud
extends Control
## Direct defense HUD (D-14). Owner: Lane D. Design 10 "직접 방어전": 3파, 파 사이 20초 준비
## (함정 다시 놓기, 경비 위치 정하기), 승리 = 모든 파 처치 또는 5분 버티기, 패배 = 대피소 문이 부서지거나
## 플레이어와 경비가 모두 쓰러짐. UI_RULES §4 필드 HUD 규칙(판 없이 선·숫자) + 배치 판만 SLATE.
##
## The HUD draws whatever set_state() gives it; with auto_bind it pulls
## `Colony.defense_state()` every frame (C-17). Guard moves go to
## `Colony.assign_defense_spot(resident_id, spot_id) -> bool` (true without a battle: preview); the chip
## moves locally and guard_moved is emitted. "바로 시작" calls `Colony.skip_defense_prep()`.
##
## State (all optional):
## {"wave": int, "waves": int, "phase": &"prep" | &"fight" | &"done", "time_left": float (prep countdown),
##  "prep_sec": float, "hold_left": float (5분 버티기 남은 시간), "monsters_left": int,
##  "shelter_door": {"hp": int, "max": int}, "traps": {"ready": int, "total": int},
##  "guards": [{"id", "name", "power": float, "spot": StringName, "down": bool}],
##  "spots": [{"id", "name", "kind": &"post" | &"gate" | &"shelter", "cap": int}]}

signal guard_moved(resident_id: StringName, spot_id: StringName)

const STATE_API := &"defense_state"
const ASSIGN_API := &"assign_defense_spot"
const SKIP_API := &"skip_defense_prep"
const KIND_GLYPHS := {&"post": "▲", &"gate": "▮", &"shelter": "■"}

var auto_bind := true
var state: Dictionary = {}

var _pips: WavePips
var _phase_label: Label
var _phase_bar: SegBar
var _hold_label: Label
var _monsters_label: Label
var _door_label: Label
var _door_bar: SegBar
var _traps_label: Label
var _place_panel: PanelContainer
var _place_box: VBoxContainer
var _selected: StringName = &""
var _layout_key := ""
var _keys: HBoxContainer
var _keys_phase := &"-"
var _roster: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_apply()


func set_state(s: Dictionary) -> void:
	state = s
	if is_inside_tree():
		_apply()


func _process(_delta: float) -> void:
	if auto_bind and Colony.has_method(STATE_API):
		set_state(Colony.call(STATE_API))


# ---------------- build ----------------

func _build() -> void:
	var m := UiTokens.HUD_MARGIN
	# top centre: wave pips + phase line + prep bar
	var top := VBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override(&"separation", 6)
	_pips = WavePips.new()
	_pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(_pips)
	_phase_label = _lbl("", &"LabelHud", 22)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_phase_label)
	_phase_bar = SegBar.new()
	_phase_bar.bracket = true
	_phase_bar.fill_color = UiTokens.ACCENT
	_phase_bar.custom_minimum_size = Vector2(360, 16)
	_phase_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(_phase_bar)
	_place(top, Control.PRESET_CENTER_TOP, Vector2(0, m))
	# top right: hold timer + monsters left
	var tr := VBoxContainer.new()
	tr.add_theme_constant_override(&"separation", 4)
	_hold_label = _lbl("", &"LabelNumber", 26)
	_hold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_hold_label)
	var hl := _lbl("버티면 승리 (남은 마물은 물러남)", &"LabelHud", 14)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hl.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	tr.add_child(hl)
	_monsters_label = _lbl("", &"LabelHud", 18)
	_monsters_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_monsters_label)
	_place(tr, Control.PRESET_TOP_RIGHT, Vector2(-m, m))
	# bottom left: shelter door (lose condition) + traps
	var bl := VBoxContainer.new()
	bl.add_theme_constant_override(&"separation", 6)
	var dl := HBoxContainer.new()
	dl.add_theme_constant_override(&"separation", 10)
	var stripe := ColorRect.new()
	stripe.color = UiTokens.DANGER
	stripe.custom_minimum_size = Vector2(4, 0)
	dl.add_child(stripe)
	_door_label = _lbl("", &"LabelHud", 18)
	dl.add_child(_door_label)
	bl.add_child(dl)
	_door_bar = SegBar.new()
	_door_bar.fill_color = UiTokens.TEXT
	_door_bar.custom_minimum_size = Vector2(320, 14)
	bl.add_child(_door_bar)
	var note := _lbl("대피소 문이 부서지거나 모두 쓰러지면 패배", &"LabelHud", 14)
	note.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	bl.add_child(note)
	_traps_label = _lbl("", &"LabelHud", 16)
	bl.add_child(_traps_label)
	_place(bl, Control.PRESET_BOTTOM_LEFT, Vector2(m, -m))
	# right: guard placement (prep only)
	_place_panel = PanelContainer.new()
	_place_panel.theme_type_variation = &"PanelMenu"
	_place_panel.custom_minimum_size = Vector2(400, 0)
	_place_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override(&"separation", 10)
	var band := PanelContainer.new()
	band.theme_type_variation = &"PanelBand"
	var bh := HBoxContainer.new()
	bh.add_child(_lbl("경비 배치", &"LabelSection", 20))
	var hint := _lbl("끌어다 놓기 / 눌러서 고르고 자리 누르기", &"LabelDim", 13)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bh.add_child(hint)
	band.add_child(bh)
	pv.add_child(band)
	_place_box = VBoxContainer.new()
	_place_box.add_theme_constant_override(&"separation", 8)
	pv.add_child(_place_box)
	var start := MenuScreen.button("준비 끝내고 바로 시작", &"ButtonPrimary")
	start.pressed.connect(skip_prep)
	start.disabled = not Colony.has_method(SKIP_API)
	pv.add_child(start)
	_place_panel.add_child(pv)
	_place(_place_panel, Control.PRESET_CENTER_RIGHT, Vector2(-m, 20))
	# right (fight): who is still standing, ✕ = down
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override(&"separation", 4)
	_place(_roster, Control.PRESET_CENTER_RIGHT, Vector2(-m, 0))
	# bottom centre: key hints (rebuilt when the phase changes)
	_keys = HBoxContainer.new()
	_keys.add_theme_constant_override(&"separation", 22)
	_place(_keys, Control.PRESET_CENTER_BOTTOM, Vector2(0, -m))


# ---------------- apply ----------------

func _apply() -> void:
	if _pips == null:
		return
	modulate.a = 0.0 if state.is_empty() else 1.0  # nothing to show until C-17 sends a state
	var waves := int(state.get("waves", 3))
	var wave := int(state.get("wave", 1))
	var phase := StringName(state.get("phase", &"prep"))
	_pips.waves = waves
	_pips.current = wave
	_pips.done = phase == &"done"
	var left := float(state.get("time_left", 0.0))
	match phase:
		&"prep":
			_phase_label.text = "%d파 준비  %s" % [wave, _mmss(left)]
			_phase_label.add_theme_color_override(&"font_color", UiTokens.ACCENT)
			_phase_bar.visible = true
			_phase_bar.value = clampf(left / maxf(1.0, float(state.get("prep_sec", 20.0))), 0.0, 1.0)
		&"fight":
			_phase_label.text = "%d파 / %d파 막는 중" % [wave, waves]
			_phase_label.add_theme_color_override(&"font_color", UiTokens.TEXT)
			_phase_bar.visible = false
		_:
			_phase_label.text = "방어전 끝"
			_phase_bar.visible = false
	var hold := float(state.get("hold_left", -1.0))
	_hold_label.visible = hold >= 0.0
	_hold_label.text = _mmss(hold)
	_monsters_label.text = "▲ 남은 마물 %d" % int(state.get("monsters_left", 0)) if phase == &"fight" else ""
	var door: Dictionary = state.get("shelter_door", {})
	_door_label.text = "대피소 문  %d / %d" % [int(door.get("hp", 0)), int(door.get("max", 0))] if not door.is_empty() else "대피소 문  -"
	var share := float(door.get("hp", 0)) / maxf(1.0, float(door.get("max", 1)))
	_door_bar.value = share if not door.is_empty() else 0.0
	_door_bar.fill_color = UiTokens.DANGER if share < 0.34 else UiTokens.TEXT
	var traps: Dictionary = state.get("traps", {})
	_traps_label.visible = not traps.is_empty()
	_traps_label.text = "가시 함정 %d / %d 준비됨" % [int(traps.get("ready", 0)), int(traps.get("total", 0))]
	_place_panel.visible = phase == &"prep" and not (state.get("spots", []) as Array).is_empty()
	_roster.visible = phase == &"fight"
	if _roster.visible:
		_fill_roster()
	if phase != _keys_phase:
		_keys_phase = phase
		_fill_keys(phase)
	var key := JSON.stringify([state.get("guards", []), state.get("spots", []), _selected])
	if key != _layout_key:
		_layout_key = key
		_rebuild_places()


func _rebuild_places() -> void:
	MenuScreen.clear(_place_box)
	var guards: Array = state.get("guards", [])
	var pool := SpotBox.new(self, &"", "대기 중", "", 99)
	_place_box.add_child(pool)
	for s: Dictionary in state.get("spots", []):
		var kind := StringName(s.get("kind", &"post"))
		var box := SpotBox.new(self, StringName(s.get("id", &"")), String(s.get("name", "")),
			KIND_GLYPHS.get(kind, "▲"), int(s.get("cap", 2)))
		_place_box.add_child(box)
	for g: Dictionary in guards:
		var target := StringName(g.get("spot", &""))
		for box: SpotBox in _place_box.get_children():
			if box.spot_id == target:
				box.add_guard(GuardChip.new(self, g, StringName(g.get("id", &"")) == _selected))
				break
	for box: SpotBox in _place_box.get_children():
		box.refresh_count()


func _fill_keys(phase: StringName) -> void:
	MenuScreen.clear(_keys)
	var pairs := [["끌기", "경비 옮기기"], ["Enter", "바로 시작"], ["Tab", "가방"]] if phase == &"prep" else [["Tab", "가방"]]
	for pair: Array in pairs:
		var k := HBoxContainer.new()
		k.add_theme_constant_override(&"separation", 8)
		k.add_child(KeyChip.new(pair[0], KeyChip.Style.FIELD))
		k.add_child(_lbl(pair[1], &"LabelHud", 16))
		_keys.add_child(k)


func _fill_roster() -> void:
	MenuScreen.clear(_roster)
	var guards: Array = state.get("guards", [])
	var up := guards.filter(func(g): return not bool(g.get("down", false))).size()
	var head := _lbl("경비 %d / %d" % [up, guards.size()], &"LabelHud", 18)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_roster.add_child(head)
	var spot_names := {}
	for s: Dictionary in state.get("spots", []):
		spot_names[StringName(s.get("id", &""))] = String(s.get("name", ""))
	for g: Dictionary in guards:
		var down := bool(g.get("down", false))
		var where: String = spot_names.get(StringName(g.get("spot", &"")), "대기")
		var l := _lbl("%s  %s / %s" % ["✕" if down else "●", String(g.get("name", "")), "쓰러짐" if down else where], &"LabelHud", 15)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.add_theme_color_override(&"font_color", UiTokens.DANGER if down else UiTokens.TEXT)
		_roster.add_child(l)


# ---------------- actions ----------------

## Move a guard to a spot (&"" = back to the pool). Asks Colony (C-17 assign_defense_spot) first;
## once accepted the chip moves at once (the next defense_state() pull says the same).
func move_guard(resident_id: StringName, spot_id: StringName) -> bool:
	if not _can_fit(resident_id, spot_id):
		return false
	_selected = &""
	if Colony.has_method(ASSIGN_API) and not bool(Colony.call(ASSIGN_API, resident_id, spot_id)):
		return false
	for g: Dictionary in state.get("guards", []):
		if StringName(g.get("id", &"")) == resident_id:
			g["spot"] = spot_id
	guard_moved.emit(resident_id, spot_id)
	_apply()
	return true


func select_guard(resident_id: StringName) -> void:
	_selected = &"" if _selected == resident_id else resident_id
	_apply()


func spot_clicked(spot_id: StringName) -> void:
	if _selected != &"":
		move_guard(_selected, spot_id)


func skip_prep() -> void:
	if Colony.has_method(SKIP_API):
		Colony.call(SKIP_API)


func guards_at(spot_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for g: Dictionary in state.get("guards", []):
		if StringName(g.get("spot", &"")) == spot_id:
			out.append(StringName(g.get("id", &"")))
	return out


func _can_fit(resident_id: StringName, spot_id: StringName) -> bool:
	if StringName(state.get("phase", &"prep")) != &"prep":
		return false
	if spot_id == &"":
		return true
	for s: Dictionary in state.get("spots", []):
		if StringName(s.get("id", &"")) == spot_id:
			var here := guards_at(spot_id)
			return resident_id in here or here.size() < int(s.get("cap", 2))
	return false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_accept") and StringName(state.get("phase", &"")) == &"prep":
		skip_prep()


# ---------------- helpers ----------------

func _mmss(sec: float) -> String:
	var s := maxi(0, ceili(sec))
	return "%02d:%02d" % [s / 60, s % 60]


func _lbl(text: String, variation: StringName, size_px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.add_theme_font_size_override(&"font_size", size_px)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _place(c: Control, preset: Control.LayoutPreset, offset: Vector2) -> void:
	add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	match preset:
		Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
		Control.PRESET_TOP_RIGHT, Control.PRESET_CENTER_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_CENTER_BOTTOM]:
		c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if preset == Control.PRESET_CENTER_RIGHT:
		c.grow_vertical = Control.GROW_DIRECTION_BOTH
	c.position += offset


## Wave dots joined by a line; the current wave is a big ring with its number, done waves filled.
class WavePips:
	extends Control
	var waves := 3:
		set(v):
			waves = v
			update_minimum_size()
			queue_redraw()
	var current := 1:
		set(v):
			current = v
			queue_redraw()
	var done := false:
		set(v):
			done = v
			queue_redraw()

	func _get_minimum_size() -> Vector2:
		return Vector2(70.0 * maxi(1, waves - 1) + 60.0, 44)

	func _draw() -> void:
		var y := 20.0
		var x0 := 30.0
		var gap := 70.0
		draw_line(Vector2(x0, y), Vector2(x0 + gap * (waves - 1), y), Color(1, 1, 1, 0.5), 2.0)
		var f := UiThemeBuilder.font_num()
		for i in waves:
			var n := i + 1
			var p := Vector2(x0 + gap * i, y)
			var past := n < current or done
			if n == current and not done:
				draw_circle(p, 17, Color(0, 0, 0, 0.55))
				draw_arc(p, 17, 0, TAU, 32, UiTokens.ACCENT, 3.0, true)
			elif past:
				draw_circle(p, 12, UiTokens.TEXT)
			else:
				draw_circle(p, 12, Color(0, 0, 0, 0.55))
				draw_arc(p, 12, 0, TAU, 24, Color(1, 1, 1, 0.6), 2.0, true)
			var t := "✓" if past else str(n)
			var tf: Font = UiThemeBuilder.font_kr(700) if past else f
			var fs := 18 if n == current else 15
			var tw := tf.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(tf, p + Vector2(-tw * 0.5, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				UiTokens.INK if past else UiTokens.TEXT)


## Drop target: one defense spot (or the pool). Click = put the selected guard here.
class SpotBox:
	extends PanelContainer
	var hud: RaidDefenseHud
	var spot_id: StringName
	var cap := 2
	var _chips: HFlowContainer
	var _count: Label

	func _init(owner_hud: RaidDefenseHud, id: StringName, title: String, glyph: String, capacity: int) -> void:
		hud = owner_hud
		spot_id = id
		cap = capacity
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTokens.SLATE_2 if id != &"" else Color(0, 0, 0, 0.18)
		sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
		sb.border_color = UiTokens.LINE
		sb.set_border_width_all(1)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 8
		sb.content_margin_bottom = 10
		add_theme_stylebox_override(&"panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override(&"separation", 6)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := Label.new()
		t.text = ("%s  %s" % [glyph, title]) if glyph != "" else title
		t.theme_type_variation = &"LabelHud"
		t.add_theme_font_size_override(&"font_size", 16)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		_count = Label.new()
		_count.theme_type_variation = &"LabelDim"
		_count.add_theme_font_size_override(&"font_size", 14)
		h.add_child(_count)
		v.add_child(h)
		_chips = HFlowContainer.new()
		_chips.add_theme_constant_override(&"h_separation", 6)
		_chips.add_theme_constant_override(&"v_separation", 6)
		_chips.custom_minimum_size = Vector2(0, 34)
		_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(_chips)
		add_child(v)

	func add_guard(chip: Control) -> void:
		_chips.add_child(chip)

	func refresh_count() -> void:
		var n := _chips.get_child_count()
		_count.text = ("%d명" % n) if spot_id == &"" else ("%d / %d" % [n, cap])
		if spot_id == &"" and n == 0:
			_count.text = "모두 배치됨"

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hud.spot_clicked(spot_id)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("guard_id") and hud._can_fit(StringName(data.guard_id), spot_id)

	func _drop_data(_at: Vector2, data: Variant) -> void:
		hud.move_guard(StringName(data.guard_id), spot_id)


## Draggable guard: name + power, ✕ when down. Selected = yellow outline.
class GuardChip:
	extends PanelContainer
	var hud: RaidDefenseHud
	var guard: Dictionary

	func _init(owner_hud: RaidDefenseHud, g: Dictionary, selected: bool) -> void:
		hud = owner_hud
		guard = g
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		var down := bool(g.get("down", false))
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTokens.CREAM if not down else UiTokens.GREY_BTN
		sb.set_corner_radius_all(99)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		if selected:
			sb.border_color = UiTokens.ACCENT
			sb.set_border_width_all(3)
		add_theme_stylebox_override(&"panel", sb)
		var l := Label.new()
		l.text = "%s%s  %.1f" % ["✕ " if down else "", String(g.get("name", g.get("id", ""))), float(g.get("power", 0.0))]
		l.theme_type_variation = &"LabelOnCream"
		l.add_theme_font_size_override(&"font_size", 15)
		add_child(l)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hud.select_guard(StringName(guard.get("id", &"")))
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		var p := Label.new()
		p.text = String(guard.get("name", ""))
		p.theme_type_variation = &"LabelHud"
		set_drag_preview(p)
		return {"guard_id": guard.get("id", &"")}
