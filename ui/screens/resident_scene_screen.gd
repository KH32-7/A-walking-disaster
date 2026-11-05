class_name ResidentSceneScreen
extends MenuScreen
## Shared layout of the D-13 talk and gift screens (UI_RULES §4 "장면형 화면", §9 D-13).
## Owner: Lane D. The base stays visible on the left, the right column is blurred and holds a
## cream card, and the conversation strip (DialogBox) runs along the bottom. Also builds the
## trust card both screens show. Numbers come from Colony (trust, trust_actions, known_likes) and
## the TrustRules stage tables (C-12); nothing is computed here.

const RIGHT := 0.6

var resident_id: StringName = &""
var dialog: DialogBox
## DialogBox layout; the #125 event screens use Layout.CENTER (UI redesign 대화).
var dialog_layout: DialogBox.Layout = DialogBox.Layout.STRIP
## Right column (above the strip). Subclasses fill it.
var column: VBoxContainer


func open_with(args: Dictionary) -> void:
	if args.has("resident_id"):
		resident_id = StringName(args.resident_id)
	elif args.has("id"):
		resident_id = StringName(args.id)
	if dialog != null:
		_start()


func _build_body(_b: Control) -> void:
	backdrop.anchor_left = RIGHT
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.anchor_right = RIGHT
	add_child(shade)
	move_child(shade, backdrop.get_index() + 1)
	column = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.anchor_left = RIGHT
	column.offset_left = 40
	column.offset_right = -52
	column.offset_top = 110
	column.offset_bottom = -330
	column.add_theme_constant_override(&"separation", 14)
	add_child(column)
	dialog = DialogBox.new(dialog_layout)
	dialog.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dialog.offset_top = -330
	dialog.offset_bottom = 0
	add_child(dialog)
	move_child(dialog, body.get_index() + 1)  # under the footer key hints
	dialog.choice_made.connect(_on_choice)
	Colony.trust_changed.connect(_on_trust_changed)
	_start()


func on_closing() -> void:
	if Colony.trust_changed.is_connected(_on_trust_changed):
		Colony.trust_changed.disconnect(_on_trust_changed)


## Subclasses: draw the first state for resident_id.
func _start() -> void:
	pass


func _on_choice(_id: StringName) -> void:
	pass


func _on_trust_changed(id: StringName, _trust: int, _stage: int, _reason: StringName) -> void:
	if id == resident_id:
		_refresh_column()


func _refresh_column() -> void:
	pass


func resident() -> Dictionary:
	return Colony.get_resident(resident_id)


# ---------------- trust card ----------------

## Cream card: stage name, 5-step track with the value, next stage and what it opens, today's
## talk / gift / deep talk, and the likes the player has learned (Colony.known_likes).
func trust_card() -> Control:
	var r := resident()
	var cc := MenuScreen.cream_card(0)
	var v: VBoxContainer = cc[1]
	v.add_theme_constant_override(&"separation", 10)
	var trust := int(r.get("trust", 0))
	var stage := Colony.trust_stage(resident_id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	head.add_child(MenuScreen.label("신뢰", &"LabelOnCreamDim", 15))
	var st := MenuScreen.label(TrustRules.STAGE_NAMES[stage], &"LabelOnCream", 24)
	st.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(st)
	head.add_child(MenuScreen.label("%d / 100" % trust, &"LabelOnCream", 20))
	v.add_child(head)
	v.add_child(TrustTrack.new(trust, stage))
	if stage + 1 < TrustRules.STAGES.size():
		var nx := MenuScreen.label("다음  %s (%d): %s" % [TrustRules.STAGE_NAMES[stage + 1], TrustRules.STAGES[stage + 1],
			TrustRules.STAGE_UNLOCKS[stage + 1]], &"LabelOnCreamDim", 14)
		nx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(nx)
	var sep := HSeparator.new()
	v.add_child(sep)
	v.add_child(MenuScreen.label("오늘", &"LabelOnCreamDim", 14))
	var acts := Colony.trust_actions(resident_id)
	var rows := [
		["대화", acts.get("talk", false), "할 수 있어요", "오늘은 이미 이야기했어요"],
		["선물", acts.get("gift", false), "할 수 있어요", "오늘은 이미 선물했어요"],
		["깊은 대화", acts.get("deep_talk", false), "할 수 있어요", "기지에 머무르는 날 한 번"],
	]
	for row: Array in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 10)
		var can: bool = row[1]
		var mark := MenuScreen.label("○" if can else "✓" if row[0] != "깊은 대화" else "-", &"LabelOnCream", 16)
		mark.custom_minimum_size = Vector2(20, 0)
		h.add_child(mark)
		var nm := MenuScreen.label(String(row[0]), &"LabelOnCream", 16)
		nm.custom_minimum_size = Vector2(90, 0)
		h.add_child(nm)
		h.add_child(MenuScreen.label(String(row[2] if can else row[3]), &"LabelOnCream" if can else &"LabelOnCreamDim", 15))
		v.add_child(h)
	var likes := Colony.known_likes(resident_id)
	v.add_child(MenuScreen.label("알고 있는 좋아하는 것", &"LabelOnCreamDim", 14))
	if likes.is_empty():
		v.add_child(MenuScreen.label("아직 몰라요. 이야기하거나 선물해 보면 알게 돼요.", &"LabelOnCreamDim", 14))
	else:
		var f := HFlowContainer.new()
		f.add_theme_constant_override(&"h_separation", 6)
		for like in likes:
			f.add_child(cream_chip("▲ " + ResidentText.tag_name(like)))
		v.add_child(f)
	return cc[0]


static func cream_chip(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(99)
	sb.bg_color = UiTokens.CREAM_2
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override(&"panel", sb)
	p.add_child(MenuScreen.label(text, &"LabelOnCream", 14))
	return p


## Five stage pips on a track with a marker at the value (shape: filled pip = reached).
class TrustTrack extends Control:
	var trust := 0
	var stage := 0

	func _init(t: int, s: int) -> void:
		trust = t
		stage = s
		custom_minimum_size = Vector2(0, 40)

	func _draw() -> void:
		var y := 14.0
		var x0 := 8.0
		var x1 := size.x - 8.0
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(UiTokens.TEXT_ON_CREAM, 0.25), 4.0)
		var xv := lerpf(x0, x1, clampf(trust / 100.0, 0.0, 1.0))
		draw_line(Vector2(x0, y), Vector2(xv, y), UiTokens.TEXT_ON_CREAM, 4.0)
		var font := UiThemeBuilder.font_num()
		for i in TrustRules.STAGES.size():
			var x := lerpf(x0, x1, TrustRules.STAGES[i] / 100.0)
			var reached := i <= stage
			draw_circle(Vector2(x, y), 7.0, UiTokens.TEXT_ON_CREAM if reached else UiTokens.CREAM)
			draw_arc(Vector2(x, y), 7.0, 0, TAU, 20, UiTokens.TEXT_ON_CREAM, 2.0, true)
			var t := str(TrustRules.STAGES[i])
			draw_string(font, Vector2(x - 6, y + 24), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTokens.TEXT_ON_CREAM_DIM)
		draw_colored_polygon(PackedVector2Array([Vector2(xv, y - 6), Vector2(xv - 7, y - 16), Vector2(xv + 7, y - 16)]),
			UiTokens.ACCENT.darkened(0.25))
