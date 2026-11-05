extends MenuScreen
## Sortie result (D-07). Owner: Lane D. Design 14 "결과", UI_RULES §5 단계 표시·정산표, §6 숫자 집계.
## Reads SceneRouter.last_sortie_result (format: contracts.md "출격 결과"). "계속" = finish_result().
## Steps: 결과 → 정산 → 밤 (dots, current one large).

const COUNT_SEC := 1.8
## "건진 것": gear and blueprints get big cards that come up one by one after the XP count, rarest
## last; rare+ gear and blueprints flash once with a chime (2026-11-06 reward pass). Seconds apart.
const CARD_GAP_SEC := 0.55
const CARD_SIZE := Vector2(156, 196)
const FLASH_SEC := 0.7

var result: Dictionary = {}
var _xp_label: Label
var _xp_bar: SegBar
var _go: Button
var _t := 0.0
var _cards: Array[Control] = []
## Per card: flash colour, transparent = no flash or chime.
var _card_flash: Array[Color] = []
var _shown := 0


func _init() -> void:
	show_back = false
	title_text = "출격 결과"
	subtitle_text = "%d일차" % GameState.day
	footer_keys = [["Enter", "계속"]]


func open_with(args: Dictionary) -> void:
	if args.has("result"):
		result = args.result


func close() -> void:
	SceneRouter.finish_result()


func _build_body(b: Control) -> void:
	if result.is_empty():
		result = SceneRouter.last_sortie_result
	var steps := StepDots.new()
	steps.steps = ["결과", "저녁 정산", "밤"]
	steps.current = 0
	add_child(steps)
	steps.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	steps.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	steps.position += Vector2(-60, 90)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 40
	row.add_theme_constant_override(&"separation", 22)
	b.add_child(row)

	var extracted := bool(result.get("extracted", false))
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	left.add_theme_constant_override(&"separation", 14)
	var big := MenuScreen.label("탈출 성공" if extracted else "쓰러졌습니다", &"LabelTitle", 54)
	big.add_theme_color_override(&"font_color", UiTokens.TEXT if extracted else Color("ff8a7a"))
	left.add_child(big)
	var reg := StringName(result.get("region_id", &""))
	var rname := String(reg)
	for r: Dictionary in preload("res://ui/screens/sortie_prep_screen.gd").REGIONS:
		if r.id == reg:
			rname = r.name
	left.add_child(MenuScreen.label("%s / %s" % [rname, _dur(float(result.get("duration_sec", 0.0)))], &"LabelDim", 16))
	var xp := MenuScreen.panel("경험치", "Lv %d" % Progression.level)
	var xv: VBoxContainer = xp[1]
	_xp_label = MenuScreen.label("+0", &"LabelNumber", 48)
	_xp_label.add_theme_color_override(&"font_color", UiTokens.ACCENT)
	xv.add_child(_xp_label)
	_xp_bar = SegBar.new()
	_xp_bar.frame = false
	_xp_bar.fill_color = UiTokens.ACCENT
	_xp_bar.custom_minimum_size = Vector2(460, 8)
	xv.add_child(_xp_bar)
	left.add_child(xp[0])
	var people := MenuScreen.panel("사람", "")
	var pv: VBoxContainer = people[1]
	var rescued: Array = result.get("rescued_profiles", [])
	if rescued.is_empty():
		for id in result.get("rescued", []):
			rescued.append({"name": String(id)})
	_rows(pv, [["구한 사람", "%d명" % rescued.size()], ["처치", "%d" % int(result.get("kills", 0))],
		["두고 온 사람", "%d명" % (result.get("stranded", []) as Array).size()]])
	for p: Dictionary in rescued:
		var l := MenuScreen.label("%s: 기지로 함께 왔어요" % String(p.get("name", "")), &"LabelHud", 15)
		l.add_theme_color_override(&"font_color", UiTokens.GOOD)
		pv.add_child(l)
	for s in result.get("stranded", []):
		var l := MenuScreen.label("▲  %s: 필드에 남았어요" % String(s), &"LabelHud", 15)
		l.add_theme_color_override(&"font_color", UiTokens.WARN)
		pv.add_child(l)
	left.add_child(people[0])
	row.add_child(left)

	var loot := MenuScreen.panel("가져온 것", "", Vector2(0, 0))
	(loot[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(loot[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lv: VBoxContainer = loot[1]
	var lt: Dictionary = result.get("loot", {})
	var res: Dictionary = lt.get("resources", {})
	_build_cards(lv, lt.get("items", []), result.get("blueprints", []))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	for id: StringName in res:
		# Resources have no rarity: neutral tile (green is 고급 gear, one colour one meaning).
		grid.add_child(_tile(MenuScreen.resource_name(id), "×%d" % int(res[id]), 0))
	if grid.get_child_count() == 0 and _cards.is_empty():
		lv.add_child(MenuScreen.label("가져온 것이 없어요.", &"LabelDim", 16))
	lv.add_child(grid)
	var disc: Dictionary = lt.get("discarded", {})
	if not disc.is_empty():
		var parts: PackedStringArray = []
		for id in disc:
			parts.append("%s %d" % [MenuScreen.resource_name(id), int(disc[id])])
		var dl := MenuScreen.label("▲  창고가 가득 차서 버림: " + ", ".join(parts), &"LabelHud", 14)
		dl.add_theme_color_override(&"font_color", UiTokens.WARN)
		lv.add_child(dl)
	var down: Dictionary = result.get("down", {})
	if not down.is_empty():
		var ll := MenuScreen.label("▲  잃은 것: 가방 안의 물건%s" % (" / 장비는 그 자리에 떨어졌어요" if not (down.get("gear", []) as Array).is_empty() else ""), &"LabelHud", 14)
		ll.add_theme_color_override(&"font_color", Color("ff8a7a"))
		lv.add_child(ll)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(sp)
	_go = MenuScreen.button("계속", &"ButtonPrimary")
	_go.size_flags_horizontal = Control.SIZE_SHRINK_END
	_go.custom_minimum_size = Vector2(240, 0)
	_go.modulate.a = 0.0
	_go.pressed.connect(close)
	lv.add_child(_go)
	row.add_child(loot[0])


func _process(delta: float) -> void:
	if _xp_label == null:
		return
	_t += delta
	var k := clampf(_t / COUNT_SEC, 0.0, 1.0)
	var xp := int(result.get("xp", 0))
	var v := roundi(xp * (1.0 - pow(1.0 - k, 3.0)))
	_xp_label.text = "+%d" % v
	var need := maxi(1, Progression.xp_needed())
	_xp_bar.value = clampf(float(Progression.xp) / need, 0.0, 1.0) * k
	if k < 1.0:
		return
	var due := mini(_cards.size(), floori((_t - COUNT_SEC) / CARD_GAP_SEC) + 1)
	while _shown < due:
		_reveal_card(_shown)
		_shown += 1
	if _shown >= _cards.size():
		_go.modulate.a = 1.0


## The big cards: gear sorted rarest last, then the blueprints learned this sortie.
func _build_cards(parent: VBoxContainer, items: Array, blueprints: Array) -> void:
	var gear: Array[ItemInstance] = []
	for uid in items:
		var it: ItemInstance = Armory.get_item(uid)
		if it != null:
			gear.append(it)
	gear.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return int(a.rarity) < int(b.rarity))
	if gear.is_empty() and blueprints.is_empty():
		return
	parent.add_child(MenuScreen.label("건진 것", &"LabelSection", 18))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 14)
	flow.add_theme_constant_override(&"v_separation", 14)
	parent.add_child(flow)
	for it in gear:
		var def := Armory.get_def(it.def_id)
		var r := int(it.rarity)
		var rc := UiTokens.rarity_color(r)
		var rname: String = UiTokens.RARITY_NAMES[clampi(r, 0, UiTokens.RARITY_NAMES.size() - 1)]
		_add_card(flow, def.name if def != null else String(it.def_id), rname, it.def_id,
			Color(rc, 0.35) if r > 0 else Color(1, 1, 1, 0.06), UiTokens.TEXT,
			rc if r >= Enums.Rarity.RARE else Color.TRANSPARENT)
	for out_id in blueprints:
		var bdef := Armory.get_def(StringName(out_id))
		_add_card(flow, bdef.name if bdef != null else String(out_id), "설계도",
			StringName(out_id), Color(UiTokens.CREAM, 0.92), UiTokens.TEXT_ON_CREAM, UiTokens.CREAM)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	parent.add_child(gap)


func _add_card(flow: HFlowContainer, name_text: String, line2: String, icon_id: StringName, bg: Color,
		ink: Color, flash: Color) -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size = CARD_SIZE
	p.pivot_offset = CARD_SIZE * 0.5
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(UiTokens.CARD_RADIUS)
	sb.bg_color = bg
	sb.border_color = UiTokens.LINE_STRONG if flash.a > 0.0 else UiTokens.LINE
	sb.set_border_width_all(2 if flash.a > 0.0 else 1)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override(&"panel", sb)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override(&"separation", 6)
	var tex := ItemInfo.icon(icon_id)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(0, 96)
		v.add_child(tr)
	var n := MenuScreen.label(name_text, &"LabelHud", 18)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_theme_color_override(&"font_color", ink)
	v.add_child(n)
	if ink == UiTokens.TEXT_ON_CREAM:  # the HUD label shadow and outline smear on cream
		n.add_theme_constant_override(&"outline_size", 0)
		n.add_theme_color_override(&"font_shadow_color", Color.TRANSPARENT)
	var l2 := MenuScreen.label(line2, &"LabelHud", 14)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l2.add_theme_color_override(&"font_color", ink)
	if ink == UiTokens.TEXT_ON_CREAM:
		l2.add_theme_color_override(&"font_shadow_color", Color.TRANSPARENT)
		l2.add_theme_constant_override(&"outline_size", 0)
	v.add_child(l2)
	p.add_child(v)
	p.modulate.a = 0.0
	flow.add_child(p)
	_cards.append(p)
	_card_flash.append(flash)


func _reveal_card(i: int) -> void:
	var c := _cards[i]
	c.scale = Vector2(0.75, 0.75)
	var tw := c.create_tween().set_parallel()
	tw.tween_property(c, ^"modulate:a", 1.0, 0.18)
	tw.tween_property(c, ^"scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var flash := _card_flash[i]
	if flash.a <= 0.0:
		return
	Audio.play(&"loot_rare")
	if bool(Settings.get_value(&"reduce_flash")):
		return
	var glow := ColorRect.new()
	glow.color = Color(flash, 0.9)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(glow)
	var gt := glow.create_tween()
	gt.tween_property(glow, ^"color:a", 0.0, FLASH_SEC).set_ease(Tween.EASE_OUT)
	gt.tween_callback(glow.queue_free)


func _rows(v: VBoxContainer, rows: Array) -> void:
	for r: Array in rows:
		var h := HBoxContainer.new()
		var a := MenuScreen.label(String(r[0]), &"LabelHud", 16)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(MenuScreen.label(String(r[1]), &"LabelNumber", 18))
		v.add_child(h)


func _tile(name_text: String, count: String, rarity: int) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(120, 96)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	sb.border_color = UiTokens.LINE
	sb.set_border_width_all(1)
	sb.bg_color = Color(UiTokens.rarity_color(rarity), 0.28) if rarity > 0 else Color(1, 1, 1, 0.05)
	p.add_theme_stylebox_override(&"panel", sb)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var c := MenuScreen.label(count, &"LabelNumber", 20)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	var n := MenuScreen.label(name_text, &"LabelHud", 14)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	p.add_child(v)
	return p


func _dur(sec: float) -> String:
	var s := int(sec)
	return "%d분 %02d초" % [s / 60, s % 60]


func _unhandled_input(event: InputEvent) -> void:
	# Enter while the XP counts or the cards come up: skip to the end, a second Enter continues.
	if event.is_action_pressed(&"ui_accept") and _go != null and _go.modulate.a < 1.0:
		get_viewport().set_input_as_handled()
		_t = COUNT_SEC + CARD_GAP_SEC * _cards.size()
		return
	if event.is_action_pressed(&"ui_accept") and _go != null and _go.modulate.a >= 1.0:
		# Mark handled first: close() removes this node, so get_viewport() is null afterwards (#86).
		get_viewport().set_input_as_handled()
		close()


## Step indicator (UI_RULES §5): dots on a line, current one large with its name below.
class StepDots:
	extends Control
	var steps: Array = []
	var current := 0

	func _get_minimum_size() -> Vector2:
		return Vector2(80.0 * maxi(1, steps.size() - 1) + 40.0, 56)

	func _draw() -> void:
		var n := steps.size()
		if n == 0:
			return
		var y := 14.0
		var x0 := 20.0
		var gap := (size.x - 40.0) / maxf(1.0, n - 1)
		draw_line(Vector2(x0, y), Vector2(x0 + gap * (n - 1), y), Color(1, 1, 1, 0.45), 2)
		var f := UiThemeBuilder.font_kr(600)
		for i in n:
			var p := Vector2(x0 + gap * i, y)
			if i == current:
				draw_circle(p, 11, UiTokens.TEXT)
				draw_circle(p, 6, UiTokens.INK)
				var t := String(steps[i])
				var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				draw_string(f, Vector2(p.x - w * 0.5, y + 36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTokens.TEXT)
			else:
				draw_circle(p, 6, Color(1, 1, 1, 0.6) if i < current else Color(1, 1, 1, 0.3))
