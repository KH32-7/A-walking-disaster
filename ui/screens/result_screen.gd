extends MenuScreen
## Sortie result (D-07). Owner: Lane D. Design 14 "결과", UI_RULES §5 단계 표시·정산표, §6 숫자 집계.
## Reads SceneRouter.last_sortie_result (format: contracts.md "출격 결과"). "계속" = finish_result().
## Steps: 결과 → 정산 → 밤 (dots, current one large).

const COUNT_SEC := 1.8

var result: Dictionary = {}
var _xp_label: Label
var _xp_bar: SegBar
var _go: Button
var _t := 0.0


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
	left.add_child(MenuScreen.label("%s  ·  %s" % [rname, _dur(float(result.get("duration_sec", 0.0)))], &"LabelDim", 16))
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
		var l := MenuScreen.label("◆  %s — 기지로 함께 왔어요" % String(p.get("name", "")), &"LabelHud", 15)
		l.add_theme_color_override(&"font_color", UiTokens.GOOD)
		pv.add_child(l)
	for s in result.get("stranded", []):
		var l := MenuScreen.label("▲  %s — 필드에 남았어요" % String(s), &"LabelHud", 15)
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
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	for id: StringName in res:
		grid.add_child(_tile(MenuScreen.resource_name(id), "×%d" % int(res[id]), 1))
	for uid in lt.get("items", []):
		var it: ItemInstance = Armory.get_item(uid)
		var def: ItemDef = Armory.get_def(it.def_id) if it != null else null
		grid.add_child(_tile(def.name if def != null else String(uid), "장비", int(it.rarity) if it != null else 0))
	if grid.get_child_count() == 0:
		lv.add_child(MenuScreen.label("가져온 것이 없어요.", &"LabelDim", 15))
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
		var ll := MenuScreen.label("▲  잃은 것: 가방 안의 물건%s" % (" · 장비는 그 자리에 떨어졌어요" if not (down.get("gear", []) as Array).is_empty() else ""), &"LabelHud", 14)
		ll.add_theme_color_override(&"font_color", Color("ff8a7a"))
		lv.add_child(ll)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(sp)
	_go = MenuScreen.button("계속", &"ButtonSecondary")
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
	if k >= 1.0:
		_go.modulate.a = 1.0


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
	p.custom_minimum_size = Vector2(108, 84)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	sb.border_color = UiTokens.LINE
	sb.set_border_width_all(1)
	sb.bg_color = Color(UiTokens.rarity_color(rarity), 0.28) if rarity > 0 else Color(1, 1, 1, 0.05)
	p.add_theme_stylebox_override(&"panel", sb)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var c := MenuScreen.label(count, &"LabelNumber", 18)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	var n := MenuScreen.label(name_text, &"LabelHud", 12)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	p.add_child(v)
	return p


func _dur(sec: float) -> String:
	var s := int(sec)
	return "%d분 %02d초" % [s / 60, s % 60]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept") and _go != null and _go.modulate.a >= 1.0:
		close()
		get_viewport().set_input_as_handled()


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
