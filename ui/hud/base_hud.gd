class_name BaseHud
extends Control
## Base HUD (D-06). Owner: Lane D. Design: 14 "기지 HUD". Rules: UI_RULES §4, §7 (위협도).
## Top bar: day · season · phase, six main resources (cap shown on capped ones), people / beds,
## power supply / demand, raid threat gauge (3 zones + marker + label).
## Left: actionable notifications (EventBus.notification_posted); click opens the screen named in it.
## Bottom: menu with keys. Draws Colony / Economy / GameState getters only.

const RESOURCES: Array[StringName] = [&"wood", &"stone", &"scrap", &"food", &"parts", &"cloth"]
const SEASONS := ["봄", "여름", "가을", "겨울"]
const PHASES := ["아침", "출격", "기지", "저녁", "밤"]
## [label, key, screen id or action]
const MENU := [["건설", "B", &"build"], ["주민", "R", &"residents"], ["무기고", "I", &"armory"],
	["제작", "C", &"craft"], ["일지", "J", &"journal"], ["전초기지", "O", &"outposts"], ["머무르기", "H", &"@stay"], ["출격", "Enter", &"@sortie"]]
const NOTE_MAX := 4
const NOTE_SEC := 8.0

var _day: Label
var _phase: Label
var _res: HBoxContainer
var _pop: Label
var _beds: Label
var _power: Label
var _threat_label: Label
var _threat: ThreatGauge
var _notes: VBoxContainer
var _menu_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	for sig in [EventBus.resources_changed, EventBus.day_started, EventBus.phase_changed,
			EventBus.resident_joined, EventBus.resident_left, EventBus.resident_died, EventBus.building_completed]:
		# Signals carry 0-2 args (resident_left/died add a reason); the HUD only needs a refresh.
		sig.connect(func(_a: Variant = null, _b: Variant = null) -> void: refresh())
	EventBus.notification_posted.connect(push_note)
	refresh()


func refresh() -> void:
	_day.text = "%d일차 / %s" % [GameState.day, SEASONS[int(GameState.season()) % 4]]
	_phase.text = PHASES[clampi(int(GameState.phase), 0, 4)] + (" / 비" if GameState.is_raining() else "")
	MenuScreen.clear(_res)
	for id in RESOURCES:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 10)
		h.add_child(_lbl(MenuScreen.resource_name(id), &"LabelHud", 17))
		var n := _lbl(str(Economy.get_amount(id)), &"LabelNumber", 24)
		h.add_child(n)
		_res.add_child(h)
	var cap := Economy.storage_cap()
	var cap_l := _lbl("창고 %d/%d" % [Economy.capped_total(), cap], &"LabelDim", 14)
	if Economy.free_space() <= 0:
		cap_l.add_theme_color_override(&"font_color", UiTokens.WARN)
	_res.add_child(cap_l)
	_pop.text = "%d명" % Colony.population()
	_beds.text = "침상 %d/%d" % [Colony.population(), Colony.bed_count()]
	_beds.add_theme_color_override(&"font_color",
		UiTokens.WARN if Colony.population() >= Colony.bed_count() else UiTokens.TEXT)
	var sup := Colony.power_supply()
	var dem := Colony.power_demand()
	_power.text = "전력 %d/%d" % [roundi(sup), dem]
	_power.add_theme_color_override(&"font_color", UiTokens.DANGER if dem > sup else UiTokens.TEXT)
	_threat.value = Colony.threat
	_threat_label.text = "%s %d" % [ThreatGauge.zone_name(Colony.threat), Colony.threat]
	_threat_label.add_theme_color_override(&"font_color", ThreatGauge.zone_color(Colony.threat))


## Notification card. `text` may start with "@screen_id " to make it open that screen on click.
func push_note(text: String, severity: StringName = &"info") -> void:
	var target := &""
	if text.begins_with("@"):
		var sp := text.find(" ")
		target = StringName(text.substr(1, sp - 1))
		text = text.substr(sp + 1)
	var b := Button.new()
	b.theme_type_variation = &"ButtonCancel"
	b.add_theme_stylebox_override(&"normal", _note_box(severity))
	b.add_theme_stylebox_override(&"hover", _note_box(severity, 0.1))
	b.add_theme_stylebox_override(&"pressed", _note_box(severity, 0.1))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = ("▲  " if severity != &"info" else "") + text + ("   ›" if target != &"" else "")
	b.add_theme_color_override(&"font_color", UiTokens.WARN if severity == &"warn"
		else (Color("ff8a7a") if severity == &"danger" else UiTokens.TEXT))
	b.custom_minimum_size = Vector2(360, 0)
	b.focus_mode = Control.FOCUS_NONE
	if target != &"":
		b.pressed.connect(func() -> void: _do(target))
	_notes.add_child(b)
	while _notes.get_child_count() > NOTE_MAX:
		_notes.get_child(0).queue_free()
		_notes.remove_child(_notes.get_child(0))
	# Capture the id, not the card: it may be gone already (more notes came, the HUD was rebuilt).
	var note_id := b.get_instance_id()
	get_tree().create_timer(NOTE_SEC).timeout.connect(func() -> void:
		var n := instance_from_id(note_id) as Node
		if n != null and is_instance_valid(n):
			n.queue_free())


func note_count() -> int:
	return _notes.get_child_count()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not UI.stack_ids().is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := OS.get_keycode_string((event as InputEventKey).keycode)
		for m: Array in MENU:
			if k == m[1]:
				_do(m[2])
				get_viewport().set_input_as_handled()
				return


func _do(target: StringName) -> void:
	match target:
		&"@stay":
			SceneRouter.stay_at_base()
		&"@sortie":
			SceneRouter.open_sortie_prep()
		_:
			if UI.has_screen(target):
				UI.open(target)
			else:
				push_note("아직 준비 중인 화면이에요", &"info")


func _build() -> void:
	# top bar
	var top := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.SLATE, 0.62)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	top.add_theme_stylebox_override(&"panel", sb)
	add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 30)
	top.add_child(h)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override(&"separation", 2)
	_day = _lbl("", &"LabelSection", 22)
	_phase = _lbl("", &"LabelDim", 14)
	dv.add_child(_day)
	dv.add_child(_phase)
	h.add_child(dv)
	h.add_child(_sep())
	_res = HBoxContainer.new()
	_res.add_theme_constant_override(&"separation", 20)
	_res.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_res)
	h.add_child(_sep())
	_pop = _lbl("", &"LabelHud", 18)
	_beds = _lbl("", &"LabelHud", 18)
	_power = _lbl("", &"LabelHud", 18)
	for l in [_pop, _beds, _power]:
		h.add_child(l)
	h.add_child(_sep())
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override(&"separation", 8)
	var th := HBoxContainer.new()
	th.add_child(_lbl("습격 위협도", &"LabelDim", 14))
	_threat_label = _lbl("", &"LabelHud", 15)
	_threat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	th.add_child(_threat_label)
	tv.add_child(th)
	_threat = ThreatGauge.new()
	_threat.custom_minimum_size = Vector2(220, 12)
	tv.add_child(_threat)
	h.add_child(tv)
	# notifications
	_notes = VBoxContainer.new()
	_notes.add_theme_constant_override(&"separation", 8)
	add_child(_notes)
	_notes.position = Vector2(UiTokens.HUD_MARGIN, 120)
	# bottom menu
	var mp := PanelContainer.new()
	mp.theme_type_variation = &"PanelMenu"
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override(&"separation", 10)
	mp.add_child(mh)
	for m: Array in MENU:
		var b := Button.new()
		b.text = "%s  %s" % [m[0], m[1]]
		b.theme_type_variation = &"ButtonPrimary" if m[2] == &"@sortie" else &"TabText"
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_do.bind(m[2]))
		_menu_buttons[m[2]] = b
		mh.add_child(b)
	add_child(mp)
	mp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	mp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mp.position.y -= 28


func _sep() -> Control:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.18)
	c.custom_minimum_size = Vector2(1, 34)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _lbl(t: String, v: StringName, s: int) -> Label:
	return MenuScreen.label(t, v, s)


func _note_box(severity: StringName, lift := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.SLATE, 0.85).lightened(lift)
	sb.set_corner_radius_all(UiTokens.BAND_RADIUS)
	sb.border_width_left = 4
	sb.border_color = UiTokens.WARN if severity == &"warn" else (UiTokens.DANGER if severity == &"danger" else UiTokens.INFO)
	sb.content_margin_left = 16
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## Threat gauge: safe / caution / danger zones from RaidRules night thresholds (C-08),
## hatching on the danger zone, a marker and a text label (never colour alone).
class ThreatGauge:
	extends Control
	var value := 0:
		set(v):
			value = v
			queue_redraw()

	static func caution_at() -> int:
		return int(RaidRules.NIGHT_CHANCES[RaidRules.NIGHT_CHANCES.size() - 1][0])

	static func danger_at() -> int:
		return int(RaidRules.NIGHT_CHANCES[RaidRules.NIGHT_CHANCES.size() - 2][0])

	static func zone_name(v: int) -> String:
		return "위험" if v >= danger_at() else ("주의" if v >= caution_at() else "안전")

	static func zone_color(v: int) -> Color:
		return UiTokens.DANGER if v >= danger_at() else (UiTokens.WARN if v >= caution_at() else UiTokens.GOOD)

	func _draw() -> void:
		var w := size.x
		var mx := float(RaidRules.THREAT_MAX)
		var a := w * caution_at() / mx
		var b := w * danger_at() / mx
		draw_rect(Rect2(0, 2, a - 2, size.y - 4), Color(UiTokens.GOOD, 0.55))
		draw_rect(Rect2(a, 2, b - a - 2, size.y - 4), Color(UiTokens.WARN, 0.55))
		draw_rect(Rect2(b, 2, w - b, size.y - 4), Color(UiTokens.DANGER, 0.5))
		var x := b + 3.0
		while x < w:
			draw_line(Vector2(x, size.y - 2), Vector2(minf(x + 6, w), 2), Color(0, 0, 0, 0.35), 2)
			x += 7.0
		var m := w * clampf(value / mx, 0.0, 1.0)
		draw_rect(Rect2(m - 2, -3, 4, size.y + 6), UiTokens.TEXT)


## Bottom dock button by its id (&"build", &"@sortie" …) for the tutorial spotlight. null = none.
func menu_button(id: StringName) -> Button:
	return _menu_buttons.get(id, null)
