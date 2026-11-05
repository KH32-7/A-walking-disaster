class_name TitleScreen
extends Control
## Title screen (D-19). Owner: Lane D. Screen id `title`, opened by UI on FlowState.TITLE
## (ui.gd FLOW_SCREENS; A's core/flow_prompts.gd steps aside once this id is registered).
## Design 14 "화면 목록": 이어하기, 새 게임(난이도·보호 모드), 설정, 접근성 빠른 설정. Plus 불러오기, 종료.
## Left: game name, Haesol stripe, MenuList. Right: the focused row's detail (slate panel / cream card).
##
## Everything it starts goes through the router: SceneRouter.load_suspended() / load_game(slot) /
## start_new_game(slot, preset). Difficulty values come from Settings.PRESETS; "보호 모드" items are
## the story preset's values (design 12) applied with Settings.set_value() after the new game starts.
## settings / accessibility_quick (D-15) open with UI.open() when registered, else the row is disabled.

const SEASONS := ["봄", "여름", "가을", "겨울"]
const DIFFICULTY_ORDER: Array[StringName] = [&"story", &"normal", &"hard", &"hardcore"]
const DIFFICULTY_NAMES := {&"story": "이야기", &"normal": "보통", &"hard": "어려움", &"hardcore": "하드코어",
	&"custom": "사용자 설정"}
## Protect-mode items (design 12 "보호 모드" = the story preset's items, each one on its own).
const PROTECT := [
	{"key": &"permadeath", "label": "주민 영구 사망 끄기", "note": "죽는 대신 중상으로 남아요"},
	{"key": &"keep_bag_on_down", "label": "쓰러져도 가방 유지", "note": "가방 속 물건을 잃지 않아요"},
	{"key": &"instant_loot", "label": "상자 바로 확인", "note": "칸마다 기다리지 않아요"},
	{"key": &"strand_days", "label": "고립 기한 없음", "note": "두고 온 사람이 실종되지 않아요"},
]
const PROTECT_PRESET := &"story"

## Row the right side shows (continue, new, load, settings, access, quit).
var current: StringName = &""
var list: MenuList
## New game choices.
var new_slot := 0
var new_preset: StringName = &"normal"
## key -> bool (protect item on)
var protect := {}

var _detail: Control
var _focus_target: Control


## "12일차 · 11월 5일 21:30" for a slot_info() Dictionary.
static func saved_text(info: Dictionary) -> String:
	var t := saved_time(info)
	return "%d일차" % int(info.get("day", 0)) + (" · " + t if t != "" else "")


## "11월 5일 21:30" (local time), "" when unknown.
static func saved_time(info: Dictionary) -> String:
	var at := int(info.get("saved_at", 0))
	if at <= 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(at + bias)
	return "%d월 %d일 %02d:%02d" % [d.month, d.day, d.hour, d.minute]


static func season_name(s: int) -> String:
	return SEASONS[posmod(s, SEASONS.size())]


## The most recently saved compatible slot, or -1.
static func latest_slot() -> int:
	var best := -1
	var best_at := -1
	for s in SaveSystem.SLOT_COUNT:
		var info := SaveSystem.slot_info(s)
		if info["exists"] and info["compatible"] and int(info["saved_at"]) > best_at:
			best = s
			best_at = int(info["saved_at"])
	return best


## What "이어하기" loads: {"kind": &"suspend"|&"slot"|&"", "slot": int}
static func continue_target() -> Dictionary:
	if SaveSystem.has_suspend():
		return {"kind": &"suspend", "slot": -1}
	var s := latest_slot()
	return {"kind": &"slot" if s >= 0 else &"", "slot": s}


func open_with(_args: Dictionary) -> void:
	if is_inside_tree():
		_build_list()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UiTokens.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var sky := Skyline.new()
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sky)

	var left := VBoxContainer.new()
	left.position = Vector2(140, 150)
	left.custom_minimum_size = Vector2(640, 0)
	left.add_theme_constant_override(&"separation", 14)
	add_child(left)
	var kicker := MenuScreen.label("해솔시 · 남겨진 사람들의 생존기", &"LabelHud", 20)
	kicker.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	left.add_child(kicker)
	var name_l := Label.new()
	name_l.text = "A WALKING\nDISASTER"
	name_l.add_theme_font_override(&"font", UiThemeBuilder.font_num())
	name_l.add_theme_font_size_override(&"font_size", 92)
	name_l.add_theme_constant_override(&"line_spacing", -18)
	name_l.add_theme_color_override(&"font_color", UiTokens.TEXT)
	left.add_child(name_l)
	var bands := HaesolBands.new()
	bands.custom_minimum_size = Vector2(560, 18)
	bands.teal_width = 7.0
	bands.yellow_width = 3.0
	left.add_child(bands)
	bands.play(HaesolBands.IN_TIME)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	left.add_child(gap)
	list = MenuList.new()
	list.custom_minimum_size = Vector2(500, 0)
	list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	list.row_focused.connect(_on_row_focused)
	left.add_child(list)

	_detail = Control.new()
	_detail.position = Vector2(960, 150)
	_detail.size = Vector2(820, 790)
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail)

	_build_footer()
	_reset_new_game()
	_build_list()


func _build_list() -> void:
	list.clear_rows()
	var ct := continue_target()
	var note := "저장 없음"
	match ct.kind:
		&"suspend": note = "중단한 출격"
		&"slot": note = "슬롯 %d · %s" % [ct.slot + 1, saved_text(SaveSystem.slot_info(ct.slot))]
	list.add_row(&"continue", "이어하기", _continue, note, ct.kind != &"")
	list.add_row(&"new", "새 게임", _enter_detail)
	var any_slot := false
	for s in SaveSystem.SLOT_COUNT:
		any_slot = any_slot or SaveSystem.has_slot(s)
	list.add_row(&"load", "불러오기", _enter_detail, "" if any_slot or SaveSystem.has_suspend() else "저장 없음",
		any_slot or SaveSystem.has_suspend())
	var has_settings := UI.has_screen(&"settings")
	list.add_row(&"settings", "설정", _open_screen.bind(&"settings"), "" if has_settings else "준비 중", has_settings)
	var has_quick := UI.has_screen(&"accessibility_quick")
	list.add_row(&"access", "접근성 빠른 설정", _open_screen.bind(&"accessibility_quick"),
		"" if has_quick else "준비 중", has_quick)
	list.add_row(&"quit", "종료", func() -> void: get_tree().quit())
	var first := list.focus_first()
	if first == &"" or not list.is_inside_tree():
		_show_detail(&"continue" if ct.kind != &"" else &"new")


func _build_footer() -> void:
	var f := HBoxContainer.new()
	f.add_theme_constant_override(&"separation", 26)
	for pair: Array in [["↑ ↓", "고르기"], ["Enter", "확인"], ["Esc", "뒤로"]]:
		var p := HBoxContainer.new()
		p.add_theme_constant_override(&"separation", 10)
		p.add_child(KeyChip.new(String(pair[0]), KeyChip.Style.OUTLINE))
		p.add_child(MenuScreen.label(String(pair[1]), &"LabelHud"))
		f.add_child(p)
	add_child(f)
	f.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	f.grow_vertical = Control.GROW_DIRECTION_BEGIN
	f.position += Vector2(140, -50)


# ---------------- actions ----------------

func _continue() -> void:
	var ct := continue_target()
	match ct.kind:
		&"suspend": SceneRouter.load_suspended()
		&"slot": SceneRouter.load_game(int(ct.slot))


func _open_screen(id: StringName) -> void:
	if UI.has_screen(id):
		UI.open(id)


func _enter_detail() -> void:
	if _focus_target != null and is_instance_valid(_focus_target):
		_focus_target.grab_focus()
		list.mark_selected(current)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		var f := get_viewport().gui_get_focus_owner()
		if f != null and _detail.is_ancestor_of(f):
			list.focus_row(current)
			get_viewport().set_input_as_handled()


## Starts the new game with the chosen slot, preset and protect items.
func start_new_game() -> bool:
	var preset := new_preset
	var overrides := protect_overrides()
	if not SceneRouter.start_new_game(new_slot, preset):
		return false
	for key: StringName in overrides:
		Settings.set_value(key, overrides[key])
	if not overrides.is_empty():
		SaveSystem.autosave()  # the morning save was written before the protect items
	return true


## Settings values that differ from the chosen preset because of the protect toggles.
func protect_overrides() -> Dictionary:
	var out := {}
	var base: Dictionary = Settings.PRESETS[new_preset]
	for item: Dictionary in PROTECT:
		var key: StringName = item.key
		var v: Variant = protect_value(key, bool(protect.get(key, false)))
		if v != base[key]:
			out[key] = v
	return out


## The value a protect item gives: on = the story preset's value, off = the chosen preset's value
## (or the default when the chosen preset is story itself).
func protect_value(key: StringName, on: bool) -> Variant:
	var story: Variant = Settings.PRESETS[PROTECT_PRESET][key]
	if on:
		return story
	var base: Variant = Settings.PRESETS[new_preset][key]
	return base if base != story else Settings.DEFAULTS[key]


## The difficulty the new game ends up with: the preset id, or "custom" with overrides.
func new_difficulty_name() -> String:
	if protect_overrides().is_empty():
		return DIFFICULTY_NAMES[new_preset]
	return "%s + 보호 모드 조정" % DIFFICULTY_NAMES[new_preset]


func _reset_new_game() -> void:
	protect.clear()
	var story: Dictionary = Settings.PRESETS[PROTECT_PRESET]
	var base: Dictionary = Settings.PRESETS[new_preset]
	for item: Dictionary in PROTECT:
		protect[item.key] = base[item.key] == story[item.key]
	# First free slot by default; slot 1 when all are used.
	new_slot = 0
	for s in SaveSystem.SLOT_COUNT:
		if not SaveSystem.has_slot(s):
			new_slot = s
			break


# ---------------- detail panels ----------------

func _on_row_focused(id: StringName) -> void:
	if id != current:
		_show_detail(id)


func _show_detail(id: StringName) -> void:
	current = id
	MenuScreen.clear(_detail)
	_focus_target = null
	match id:
		&"continue": _detail_continue()
		&"new": _detail_new()
		&"load": _detail_load()
		&"settings": _detail_text("설정", "그래픽, 소리, 조작, 접근성, 난이도를 바꿔요.", &"settings")
		&"access": _detail_text("접근성 빠른 설정",
			"자막, 소리 시각화, 색약 필터, 누르기 대신 토글, 보호 모드를 한 화면에서 골라요.", &"accessibility_quick")
		&"quit": _detail_text("종료", "게임을 끝내요. 설정은 바로 저장돼 있어요.", &"")


func _detail_text(title: String, body: String, screen: StringName) -> void:
	var card := MenuScreen.cream_card(520)
	var v: VBoxContainer = card[1]
	v.add_child(_cream_title(title))
	var b := MenuScreen.label(body, &"LabelOnCream", 17)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(480, 0)
	v.add_child(b)
	if screen != &"" and not UI.has_screen(screen):
		v.add_child(_cream_note("이 화면은 아직 준비 중이에요."))
	_detail.add_child(card[0])


func _detail_continue() -> void:
	var ct := continue_target()
	var card := MenuScreen.cream_card(520)
	var v: VBoxContainer = card[1]
	v.add_child(_cream_title("이어하기"))
	match ct.kind:
		&"suspend":
			v.add_child(_cream_line("중단한 출격을 그 자리부터 이어서 해요."))
			v.add_child(_cream_note("출격을 다시 시작하면 중단 저장은 지워져요."))
		&"slot":
			var info := SaveSystem.slot_info(int(ct.slot))
			v.add_child(_cream_line("슬롯 %d · %d일차 · %s" % [ct.slot + 1, int(info.day), season_name(int(info.season))]))
			v.add_child(_cream_note("저장 " + saved_text(info)))
		_:
			v.add_child(_cream_line("이어서 할 저장이 없어요."))
	_detail.add_child(card[0])


func _detail_load() -> void:
	var p := MenuScreen.panel("불러오기", "슬롯 %d개" % SaveSystem.SLOT_COUNT, Vector2(640, 0))
	var v: VBoxContainer = p[1]
	_detail.add_child(p[0])
	if SaveSystem.has_suspend():
		var sb := _slot_button("중단한 출격", "그 자리부터 이어서", true)
		sb.pressed.connect(func() -> void: SceneRouter.load_suspended())
		v.add_child(sb)
		_focus_target = sb
	for s in SaveSystem.SLOT_COUNT:
		var info := SaveSystem.slot_info(s)
		var sub := "비어 있음"
		var ok := false
		if info["exists"] and not info["compatible"]:
			sub = "다른 버전의 저장 · 불러올 수 없어요"
		elif info["exists"]:
			sub = "%d일차 · %s · 저장 %s" % [int(info.day), season_name(int(info.season)), saved_time(info)]
			ok = true
		var b := _slot_button("슬롯 %d" % (s + 1), sub, ok)
		b.pressed.connect(func() -> void: SceneRouter.load_game(s))
		v.add_child(b)
		if ok and _focus_target == null:
			_focus_target = b


func _detail_new() -> void:
	var p := MenuScreen.panel("새 게임", "", Vector2(820, 0))
	var v: VBoxContainer = p[1]
	v.add_theme_constant_override(&"separation", 14)
	_detail.add_child(p[0])
	# Slot
	v.add_child(MenuScreen.label("저장 슬롯", &"LabelSection", 18))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override(&"separation", 10)
	v.add_child(slots)
	for s in SaveSystem.SLOT_COUNT:
		var info := SaveSystem.slot_info(s)
		var b := _choice_button("슬롯 %d" % (s + 1), "%d일차 저장 있음" % int(info.day) if info["exists"] else "비어 있음",
			s == new_slot, Vector2(170, 64))
		b.pressed.connect(func() -> void:
			new_slot = s
			_refresh_new.call_deferred(StringName("slot_%d" % s)))
		b.name = "slot_%d" % s
		slots.add_child(b)
	if SaveSystem.has_slot(new_slot):
		var warn := MenuScreen.label("▲ 슬롯 %d의 %d일차 저장을 덮어써요." % [new_slot + 1,
			int(SaveSystem.slot_info(new_slot).day)], &"LabelHud", 15)
		warn.add_theme_color_override(&"font_color", UiTokens.WARN)
		v.add_child(warn)
	# Difficulty
	v.add_child(MenuScreen.label("난이도", &"LabelSection", 18))
	var diffs := HBoxContainer.new()
	diffs.add_theme_constant_override(&"separation", 10)
	v.add_child(diffs)
	for id in DIFFICULTY_ORDER:
		var pr: Dictionary = Settings.PRESETS[id]
		var sub := "마물 ×%s · 습격 ×%s" % [_mult(pr.monster_mult), _mult(pr.raid_mult)]
		var b := _choice_button(DIFFICULTY_NAMES[id], sub, id == new_preset, Vector2(186, 78))
		b.name = "diff_%s" % id
		b.pressed.connect(func() -> void:
			new_preset = id
			var keep := new_slot
			_reset_new_game()
			new_slot = keep
			_refresh_new.call_deferred(StringName("diff_%s" % id)))
		diffs.add_child(b)
		if id == new_preset:
			_focus_target = b
	# Protect mode + summary side by side
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	v.add_child(row)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override(&"separation", 6)
	pv.custom_minimum_size = Vector2(380, 0)
	row.add_child(pv)
	pv.add_child(MenuScreen.label("보호 모드", &"LabelSection", 18))
	for item: Dictionary in PROTECT:
		pv.add_child(_protect_toggle(item))
	row.add_child(_summary_card())
	# Start
	var start := MenuScreen.button("시작하기  ·  %s" % new_difficulty_name(), &"ButtonPrimary")
	start.name = "start"
	start.custom_minimum_size = Vector2(0, 56)
	start.pressed.connect(start_new_game)
	v.add_child(start)


func _refresh_new(focus_name: StringName) -> void:
	_show_detail(&"new")
	var n := _detail.find_child(String(focus_name), true, false) as Control
	if n != null:
		n.grab_focus()
	list.mark_selected(&"new")


func _protect_toggle(item: Dictionary) -> Control:
	var key: StringName = item.key
	var cb := CheckButton.new()
	cb.name = "protect_%s" % key
	cb.text = String(item.label)
	cb.button_pressed = bool(protect.get(key, false))
	cb.add_theme_font_override(&"font", UiThemeBuilder.font_kr(600))
	cb.add_theme_font_size_override(&"font_size", 17)
	cb.add_theme_color_override(&"font_color", UiTokens.TEXT)
	cb.add_theme_color_override(&"font_pressed_color", UiTokens.TEXT)
	cb.add_theme_color_override(&"font_hover_color", UiTokens.TEXT)
	cb.add_theme_color_override(&"font_focus_color", UiTokens.ACCENT)
	cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cb.tooltip_text = String(item.note)
	cb.toggled.connect(func(on: bool) -> void:
		protect[key] = on
		_refresh_new.call_deferred(StringName("protect_%s" % key)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	v.add_child(cb)
	var n := MenuScreen.label("     " + String(item.note) + ("  · 켜짐" if cb.button_pressed else "  · 꺼짐"),
		&"LabelDim", 13)
	v.add_child(n)
	return v


func _summary_card() -> Control:
	var card := MenuScreen.cream_card(400)
	var v: VBoxContainer = card[1]
	v.add_theme_constant_override(&"separation", 6)
	v.add_child(_cream_title(new_difficulty_name(), 20))
	var pr: Dictionary = (Settings.PRESETS[new_preset] as Dictionary).duplicate()
	pr.merge(protect_overrides(), true)
	var rows := [
		["마물 체력·공격", "×" + _mult(pr.monster_mult)],
		["습격 강도", "×" + _mult(pr.raid_mult)],
		["주민 영구 사망", "켬" if pr.permadeath else "끔 (중상)"],
		["고립 기한", "%d일" % int(pr.strand_days) if int(pr.strand_days) > 0 else "없음"],
		["쓰러졌을 때 가방", "유지" if pr.keep_bag_on_down else "소실"],
		["상자 확인", "즉시" if pr.instant_loot else "칸마다"],
	]
	if pr.hardcore:
		rows.append(["플레이어 사망", "저장 삭제"])
	for r: Array in rows:
		var h := HBoxContainer.new()
		var a := MenuScreen.label(String(r[0]), &"LabelOnCreamDim", 15)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(MenuScreen.label(String(r[1]), &"LabelOnCream", 16))
		v.add_child(h)
	var foot := PanelContainer.new()
	foot.theme_type_variation = &"CardCreamFoot"
	var note := "하드코어는 지금만 고를 수 있고, 나중에 바꿀 수 없어요." if pr.hardcore \
		else "난이도와 보호 모드는 게임 중에도 설정에서 바꿀 수 있어요."
	var fl := MenuScreen.label(note, &"LabelOnCreamDim", 13)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.custom_minimum_size = Vector2(360, 0)
	foot.add_child(fl)
	v.add_child(foot)
	return card[0]


# ---------------- small builders ----------------

static func _mult(x: Variant) -> String:
	return String.num(float(x), 2)


func _choice_button(title: String, sub: String, selected: bool, min_size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.08) if selected else Color(1, 1, 1, 0.03)
	box.border_color = UiTokens.ACCENT if selected else Color(1, 1, 1, 0.14)
	box.set_border_width_all(2 if selected else 1)
	box.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	var focus := box.duplicate() as StyleBoxFlat
	focus.border_color = UiTokens.LINE_STRONG if not selected else UiTokens.ACCENT
	focus.set_border_width_all(3)
	for s in [&"normal", &"hover", &"pressed", &"disabled"]:
		b.add_theme_stylebox_override(s, box)
	b.add_theme_stylebox_override(&"focus", focus)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_right = -10
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := MenuScreen.label(("✓ " if selected else "") + title, &"LabelSection", 18)
	t.add_theme_color_override(&"font_color", UiTokens.ACCENT if selected else UiTokens.TEXT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var s2 := MenuScreen.label(sub, &"LabelDim", 13)
	s2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(s2)
	b.add_child(v)
	return b


func _slot_button(title: String, sub: String, enabled: bool) -> Button:
	var b := _choice_button(title, sub, false, Vector2(0, 76))
	b.disabled = not enabled
	if not enabled:
		b.modulate = Color(1, 1, 1, 0.55)
	return b


func _cream_title(text: String, px := 24) -> Label:
	var t := MenuScreen.label(text, &"LabelSection", px)
	t.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	return t


func _cream_line(text: String) -> Label:
	var l := MenuScreen.label(text, &"LabelOnCream", 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(480, 0)
	return l


func _cream_note(text: String) -> Label:
	var l := MenuScreen.label(text, &"LabelOnCreamDim", 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(480, 0)
	return l


## A quiet flooded-city skyline behind the title: slate blocks, a few dim windows, a teal water line.
## Fixed seed, so it is the same every launch. Decoration only (no information).
class Skyline:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 2611
		var w := size.x
		var h := size.y
		var water := h * 0.86
		var x := w * 0.42
		while x < w:
			var bw := rng.randf_range(60, 150)
			var bh := rng.randf_range(h * 0.18, h * 0.62)
			var c := Color(UiTokens.SLATE.r, UiTokens.SLATE.g, UiTokens.SLATE.b, rng.randf_range(0.35, 0.6))
			draw_rect(Rect2(x, water - bh, bw - 6, bh), c)
			var wy := water - bh + 18
			while wy < water - 20:
				var wx := x + 10
				while wx < x + bw - 22:
					if rng.randf() < 0.07:
						draw_rect(Rect2(wx, wy, 8, 12), Color(UiTokens.TEXT_DIM, 0.22))
					wx += 18
				wy += 24
			x += bw
		draw_rect(Rect2(0, water, w, h - water), Color(UiTokens.INFO, 0.07))
		draw_line(Vector2(w * 0.42, water), Vector2(w, water), Color(UiTokens.INFO, 0.35), 2.0)
