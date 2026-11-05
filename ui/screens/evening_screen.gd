extends MenuScreen
## Evening settlement (D-07). Owner: Lane D. Design 01 "저녁 정산", 14 "저녁 정산".
## Reads SceneRouter.last_evening_report (Colony.settle_day() + "discarded"). "밤으로" = confirm_evening().
## Table: produced / consumed / net per resource, storage discards, morale changes, today's events,
## threat now. Numbers count up like the result screen.

const StepDots := preload("res://ui/screens/result_screen.gd").StepDots

var report: Dictionary = {}
var _go: Button


func _init() -> void:
	show_back = false
	title_text = "저녁 정산"
	subtitle_text = "%d일차" % GameState.day
	footer_keys = [["Enter", "밤으로"]]


func open_with(args: Dictionary) -> void:
	if args.has("report"):
		report = args.report


func close() -> void:
	SceneRouter.confirm_evening()


## SceneRouter enters EVENING before it settles the day, and UI opens this screen on the state
## change: without a welcome first, the screen would draw the old report. It redraws once the
## settlement arrives (기지 검사 2026-11-06: 벌목 +11이 정산 화면에 안 보이던 문제).
func _on_evening_settled(r: Dictionary) -> void:
	report = r
	if _steps != null:
		_steps.queue_free()
		_steps = null
	if body != null:
		MenuScreen.clear(body)
		_build_body(body)


var _steps: Control


func _build_body(b: Control) -> void:
	if not EventBus.evening_settled.is_connected(_on_evening_settled):
		EventBus.evening_settled.connect(_on_evening_settled)
	if report.is_empty():
		report = SceneRouter.last_evening_report
	var steps := StepDots.new()
	steps.steps = ["결과", "저녁 정산", "밤"]
	steps.current = 1
	_steps = steps
	add_child(steps)
	steps.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	steps.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	steps.position += Vector2(-60, 90)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 40
	row.add_theme_constant_override(&"separation", 22)
	b.add_child(row)

	var table := MenuScreen.panel("생산과 소비", "오늘", Vector2(760, 0))
	(table[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tv: VBoxContainer = table[1]
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override(&"h_separation", 40)
	g.add_theme_constant_override(&"v_separation", 8)
	for h in ["자원", "생산", "소비", "합계"]:
		g.add_child(MenuScreen.label(h, &"LabelDim", 13))
	var produced: Dictionary = report.get("produced", {})
	var consumed: Dictionary = report.get("consumed", {})
	var ids := {}
	for id in produced:
		ids[id] = true
	for id in consumed:
		ids[id] = true
	var stripe := false
	for id: StringName in ids:
		var p := int(produced.get(id, 0))
		var c := int(consumed.get(id, 0))
		g.add_child(MenuScreen.label(MenuScreen.resource_name(id), &"LabelHud", 16))
		g.add_child(MenuScreen.label("+%d" % p if p > 0 else "-", &"LabelNumber", 17))
		g.add_child(MenuScreen.label("−%d" % c if c > 0 else "-", &"LabelNumber", 17))
		var net := MenuScreen.label(("%+d" % (p - c)), &"LabelNumber", 18)
		net.add_theme_color_override(&"font_color", UiTokens.GOOD if p - c > 0 else (UiTokens.DANGER if p - c < 0 else UiTokens.TEXT))
		g.add_child(net)
		stripe = not stripe
	if ids.is_empty():
		tv.add_child(MenuScreen.label("오늘은 만든 것도 쓴 것도 없어요.", &"LabelDim", 15))
	else:
		tv.add_child(g)
	var disc: Dictionary = report.get("discarded", {})
	if not disc.is_empty():
		var parts: PackedStringArray = []
		for id in disc:
			parts.append("%s %d" % [MenuScreen.resource_name(id), int(disc[id])])
		var dl := MenuScreen.label("▲  창고가 가득 차서 버림: " + ", ".join(parts), &"LabelHud", 14)
		dl.add_theme_color_override(&"font_color", UiTokens.WARN)
		tv.add_child(dl)
	var food := Economy.get_amount(&"food")
	var need := int(consumed.get(&"food", 0))
	var fl := MenuScreen.label("남은 식량 %d%s" % [food, (" / 약 %d일치" % (food / need)) if need > 0 else ""], &"LabelHud", 15)
	if need > 0 and food < need * 2:
		fl.add_theme_color_override(&"font_color", UiTokens.WARN)
	tv.add_child(fl)
	row.add_child(table[0])

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 16)
	var mood := MenuScreen.panel("사기 변화", "")
	var mv: VBoxContainer = mood[1]
	var morale: Dictionary = report.get("morale", {})
	for rid in morale:
		var r := Colony.get_resident(StringName(rid))
		var d := int(morale[rid])
		var h := HBoxContainer.new()
		var n := MenuScreen.label(String(r.get("name", rid)), &"LabelHud", 15)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var dl := MenuScreen.label(("▲ %+d" if d >= 0 else "▼ %+d") % d, &"LabelNumber", 16)
		dl.add_theme_color_override(&"font_color", UiTokens.GOOD if d > 0 else (UiTokens.DANGER if d < 0 else UiTokens.TEXT_DIM))
		h.add_child(dl)
		mv.add_child(h)
	if morale.is_empty():
		mv.add_child(MenuScreen.label("변화 없음", &"LabelDim", 15))
	right.add_child(mood[0])
	var ev := MenuScreen.panel("오늘 있었던 일", "")
	var evv: VBoxContainer = ev[1]
	for e: Dictionary in report.get("events", []):
		var l := MenuScreen.label("- " + String(e.get("text", "")), &"LabelHud", 15)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(440, 0)
		evv.add_child(l)
	if (report.get("events", []) as Array).is_empty():
		evv.add_child(MenuScreen.label("조용한 하루였어요.", &"LabelDim", 15))
	right.add_child(ev[0])
	var th := MenuScreen.panel("습격 위협도", "")
	var thv: VBoxContainer = th[1]
	var tl := MenuScreen.label("%s %d / %d" % [BaseHud.ThreatGauge.zone_name(Colony.threat), Colony.threat, RaidRules.THREAT_MAX], &"LabelHud", 17)
	tl.add_theme_color_override(&"font_color", BaseHud.ThreatGauge.zone_color(Colony.threat))
	thv.add_child(tl)
	var gauge := BaseHud.ThreatGauge.new()
	gauge.value = Colony.threat
	gauge.custom_minimum_size = Vector2(440, 12)
	thv.add_child(gauge)
	right.add_child(th[0])
	_go = MenuScreen.button("밤으로", &"ButtonPrimary")
	_go.size_flags_horizontal = Control.SIZE_SHRINK_END
	_go.custom_minimum_size = Vector2(240, 0)
	_go.pressed.connect(close)
	right.add_child(_go)
	row.add_child(right)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept"):
		# Mark handled first: close() removes this node, so get_viewport() is null afterwards (#86).
		get_viewport().set_input_as_handled()
		close()
