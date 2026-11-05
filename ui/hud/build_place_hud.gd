class_name BuildPlaceHud
extends Control
## ②놓을 곳 정하기 overlay for Lane C's BuildMode (D-06 재설계, ui/_mockups/ui-redesign.html §03-2).
## Owner: Lane D. The ground cells, range ring and ghost are BuildMode's; this draws the screen parts:
##   - ①②③ step strip (② lit)
##   - top left: the building being placed (mini model, size, cost) + "[Q] 다른 건물"
##   - a cream card next to the cursor: "여기에 놓을 수 있어요 · 범위 안 나무 6곳" or the reasons in red
##   - bottom: [클릭] 벌목장 놓기 · [R] 돌리기 · [Q] 다른 건물 · [Esc] 다시 고르기
## Placed → opens the site card (build screen, mode site). Cancelled (Esc / Q / RMB) → back to the
## build list with the same building picked. Reads BuildMode signals only; computes no rule.

const STEPS := ["건물 고르기", "놓을 곳 정하기", "주민이 짓기"]
const CURSOR_OFFSET := Vector2(30, 26)

var mode: Node
var _def_id: StringName = &""
var _moving := false
var _card: PanelContainer
var _card_icon: LineIcon
var _card_title: Label
var _card_lines: VBoxContainer
var _done := false
## World point the cursor card sits next to (footprint centre), or null.
var _anchor: Variant = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(build_mode: Node) -> void:
	mode = build_mode
	_def_id = build_mode.get(&"def_id")
	_moving = build_mode.get(&"move_uid") != &""
	build_mode.preview_info.connect(_on_info)
	build_mode.placed.connect(_on_placed)
	build_mode.moved.connect(_on_moved)
	build_mode.cancelled.connect(_on_cancelled)
	_build()


func _build() -> void:
	var def := BaseDB.get_building(_def_id)
	var strip := StepStrip.new(STEPS, 2)
	add_child(strip)
	strip.place_top_center()
	# top left: what is being placed
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"PanelMenu"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.position = Vector2(UiTokens.HUD_MARGIN, 34)
	add_child(chip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	chip.add_child(h)
	if def != null:
		var art := BuildingArt.for_def(def, BuildScreen.group_color(int(def.category)))
		art.custom_minimum_size = Vector2(76, 56)
		h.add_child(art)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var nm := HBoxContainer.new()
	nm.add_theme_constant_override(&"separation", 8)
	nm.add_child(MenuScreen.label(def.display_name if def else String(_def_id), &"LabelSection", 19))
	if def != null:
		nm.add_child(MenuScreen.label("%d×%d" % [maxi(def.size.x, 1), maxi(def.size.y, 1)], &"LabelNumber", 15))
	v.add_child(nm)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override(&"separation", 8)
	if _moving:
		sub.add_child(MenuScreen.label("옮기는 중 · 무료, 진행도 그대로", &"LabelDim", 14))
	elif def != null:
		var cost := def.cost_for_level(1)
		for id: StringName in cost:
			var c := HBoxContainer.new()
			c.add_theme_constant_override(&"separation", 3)
			c.add_child(LineIcon.for_resource(id, 15, UiTokens.TEXT_DIM))
			c.add_child(MenuScreen.label(str(cost[id]), &"LabelNumber", 14))
			sub.add_child(c)
		sub.add_child(MenuScreen.label("·  다른 건물", &"LabelDim", 14))
		sub.add_child(KeyChip.new("Q", KeyChip.Style.OUTLINE))
	v.add_child(sub)
	# cursor card
	_card = PanelContainer.new()
	_card.theme_type_variation = &"CardCream"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	add_child(_card)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override(&"separation", 10)
	_card.add_child(ch)
	_card_icon = LineIcon.new(&"check", 22, Color("2f8a3a"))
	_card_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ch.add_child(_card_icon)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override(&"separation", 2)
	ch.add_child(cv)
	_card_title = MenuScreen.label("", &"LabelOnCream", 16)
	cv.add_child(_card_title)
	_card_lines = VBoxContainer.new()
	_card_lines.add_theme_constant_override(&"separation", 0)
	cv.add_child(_card_lines)
	# bottom key line
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.INK, 0.82)
	sb.set_corner_radius_all(99)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar.add_theme_stylebox_override(&"panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override(&"separation", 22)
	bar.add_child(bh)
	var name_text := def.display_name if def else String(_def_id)
	bh.add_child(_key_pair("클릭", name_text, " 옮기기" if _moving else " 놓기"))
	bh.add_child(_key_pair("R", "", "돌리기"))
	if not _moving:
		bh.add_child(_key_pair("Q", "", "다른 건물"))
	bh.add_child(_key_pair("Esc", "", "취소" if _moving else "다시 고르기"))
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position.y -= UiTokens.HUD_MARGIN


## [key] + highlighted name (ACCENT: the one thing being acted on) + rest.
func _key_pair(key: String, accent: String, rest: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 7)
	h.add_child(KeyChip.new(key, KeyChip.Style.FIELD))
	if accent != "":
		var a := MenuScreen.label(accent, &"LabelHud", 17)
		a.add_theme_color_override(&"font_color", UiTokens.ACCENT)
		h.add_child(a)
	h.add_child(MenuScreen.label(rest, &"LabelHud", 17))
	return h


func _on_info(info: Dictionary) -> void:
	_card.visible = true
	_anchor = info.get("center", null) if bool(info.get("on_grid", false)) else null
	for c in _card_lines.get_children():
		_card_lines.remove_child(c)
		c.queue_free()
	var ok: bool = info.get("ok", false)
	_card_icon.kind = &"check" if ok else &"warn"
	_card_icon.set_color(Color("2f8a3a") if ok else Color("b3261e"))
	if ok:
		_card_title.text = "여기에 %s 수 있어요" % ("옮길" if _moving else "놓을")
		var kind: String = info.get("node_kind", "")
		if kind != "":
			_line("범위 %dm 안 %s %d곳" % [roundi(float(info.get("radius", 0.0))), kind, int(info.get("nodes", 0))], false)
		else:
			_line("주민이 걸어서 닿는 자리예요", false)
	else:
		_card_title.text = "여기엔 %s 수 없어요" % ("옮길" if _moving else "놓을")
		for r: String in info.get("reasons", []):
			_line(BuildScreen.reason_text(r), true)
		var kind2: String = info.get("node_kind", "")
		if kind2 != "" and bool(info.get("on_grid", false)):
			_line("범위 %dm 안 %s %d곳" % [roundi(float(info.get("radius", 0.0))), kind2, int(info.get("nodes", 0))], false)
	_card.reset_size()


func _line(text: String, bad: bool) -> void:
	var l := MenuScreen.label(("·  " if bad else "") + text, &"LabelOnCreamDim", 14)
	if bad:
		l.add_theme_color_override(&"font_color", Color("b3261e"))
	_card_lines.add_child(l)


func _process(_delta: float) -> void:
	if _card == null or not _card.visible:
		return
	var vp := get_viewport_rect().size
	# Next to the footprint when it is on the grid (also right for a gamepad), else next to the mouse.
	var p := get_viewport().get_mouse_position() + CURSOR_OFFSET
	var cam := get_viewport().get_camera_3d()
	if _anchor != null and cam != null and not cam.is_position_behind(_anchor):
		p = cam.unproject_position(_anchor) + Vector2(90, -40)
	p.x = minf(p.x, vp.x - _card.size.x - 16)
	p.y = minf(p.y, vp.y - _card.size.y - 90)
	_card.position = p


func _unhandled_input(event: InputEvent) -> void:
	if _moving or mode == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_Q:
		mode.call(&"cancel", true)
		get_viewport().set_input_as_handled()


func _on_placed(uid: StringName) -> void:
	_finish()
	UI.open(&"build", {"mode": &"site", "uid": uid})


func _on_moved(uid: StringName) -> void:
	_finish()
	if not bool(Colony.get_building(uid).get("completed", true)):
		UI.open(&"build", {"mode": &"site", "uid": uid})


func _on_cancelled() -> void:
	var moving := _moving
	var by_player: bool = mode != null and bool(mode.get(&"cancelled_by_player"))
	_finish()
	if not moving and by_player:
		UI.open(&"build", {"mode": &"build", "select": _def_id})


func _finish() -> void:
	if _done:
		return
	_done = true
	for sig: Array in [[&"preview_info", _on_info], [&"placed", _on_placed], [&"moved", _on_moved], [&"cancelled", _on_cancelled]]:
		if mode != null and mode.is_connected(sig[0], sig[1]):
			mode.disconnect(sig[0], sig[1])
	queue_free()
