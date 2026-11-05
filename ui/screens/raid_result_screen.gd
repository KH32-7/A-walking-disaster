extends MenuScreen
## Raid result (D-14). Owner: Lane D. Design 10 "자동 판정" (사건 요약 3~5줄), 14 "습격 경보·결과",
## UI_RULES §5 정산표 (큰 제목 → 노랑 진행 막대 → 합계 → 항목별 줄), §6 숫자 집계.
## Reads the raid_resolved / Colony.resolve_raid() Dictionary (contracts.md "하루 정산과 습격"):
## {"raid_id", "day", "time", "mode", "ratio", "outcome", "damage": {"damaged", "durability_loss",
## "resources_lost"}, "used": {"decoys", "traps", "essence"}, "casualties": [{resident_id, kind}],
## "loot": {id: n}, "summary": [String]}. Nothing is computed: every value is shown as given.
## args: {"result": Dictionary}. "계속" closes it (the flow goes on underneath).

const COUNT_SEC := 1.8

var result: Dictionary = {}
var _ratio_label: Label
var _odds: RaidWidgets.OddsBar
var _go: Button
var _t := 0.0


func _init() -> void:
	show_back = false
	title_text = "습격 결과"
	header_resources = [&"wood", &"stone", &"scrap", &"food", &"parts"]
	footer_keys = [["Enter", "계속"]]


func open_with(args: Dictionary) -> void:
	if args.has("result"):
		result = args.result
	subtitle_text = "%d일차 %s" % [int(result.get("day", GameState.day)), RaidFlow.time_text(result)]
	if is_inside_tree():
		set_subtitle(subtitle_text)
		_t = 0.0


func close() -> void:
	UI.close(&"raid_result")


func _build_body(b: Control) -> void:
	if result.is_empty() and UI.get_node_or_null(^"RaidFlow") != null:
		result = UI.get_node(^"RaidFlow").last_result
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 20
	row.add_theme_constant_override(&"separation", 22)
	b.add_child(row)

	# --- left: outcome, ratio bar, event summary ---
	var outcome := int(result.get("outcome", Enums.RaidOutcome.WIN))
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(860, 0)
	left.add_theme_constant_override(&"separation", 14)
	var big := MenuScreen.label("%s  %s" % [RaidFlow.outcome_glyph(outcome), RaidFlow.outcome_name(outcome)], &"LabelTitle", 58)
	big.add_theme_color_override(&"font_color", Color("ff8a7a") if outcome == Enums.RaidOutcome.LOSS else (
		UiTokens.ACCENT if outcome == Enums.RaidOutcome.FLAWLESS else UiTokens.TEXT))
	left.add_child(big)
	left.add_child(MenuScreen.label(_mode_line(), &"LabelDim", 16))
	var rp := MenuScreen.panel("방어 비율", "방어 ÷ 습격 강도")
	var rv: VBoxContainer = rp[1]
	var rh := HBoxContainer.new()
	_ratio_label = MenuScreen.label("0.00", &"LabelNumber", 48)
	_ratio_label.add_theme_color_override(&"font_color", UiTokens.ACCENT)
	_ratio_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(_ratio_label)
	rv.add_child(rh)
	_odds = RaidWidgets.OddsBar.new()
	_odds.on_cream = false
	_odds.actual = float(result.get("ratio", 0.0))
	_odds.reveal = 0.0
	_odds.custom_minimum_size = Vector2(800, 60)
	rv.add_child(_odds)
	left.add_child(rp[0])
	var sp := MenuScreen.panel("사건 요약", "")
	(sp[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sv: VBoxContainer = sp[1]
	var lines: Array = result.get("summary", [])
	var stripe := false
	for i in lines.size():
		sv.add_child(_striped(["%d" % (i + 1), String(lines[i])], stripe, true))
		stripe = not stripe
	if lines.is_empty():
		sv.add_child(MenuScreen.label("기록이 없어요.", &"LabelDim", 15))
	left.add_child(sp[0])
	row.add_child(left)

	# --- right: damage, people, gains, threat ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 16)
	var dmg: Dictionary = result.get("damage", {})
	var dp := MenuScreen.panel("피해", "")
	var dv: VBoxContainer = dp[1]
	var rows: Array = []
	for uid in dmg.get("damaged", []):
		rows.append(["✕  " + RaidFlow.building_name(StringName(uid)), "멈춤 / 수리 필요", UiTokens.DANGER])
	var loss: Dictionary = dmg.get("durability_loss", {})
	for uid in loss:
		rows.append(["▼  " + RaidFlow.building_name(StringName(uid)), "내구도 −%d" % int(loss[uid]), UiTokens.WARN])
	var lost: Dictionary = dmg.get("resources_lost", {})
	for id in lost:
		rows.append(["▼  창고 " + MenuScreen.resource_name(StringName(id)), "−%d" % int(lost[id]), UiTokens.DANGER])
	_table(dv, rows, "부서진 것이 없어요.")
	right.add_child(dp[0])

	var pp := MenuScreen.panel("사람", "%d명" % (result.get("casualties", []) as Array).size())
	var pv: VBoxContainer = pp[1]
	rows = []
	for c: Dictionary in result.get("casualties", []):
		var kind := StringName(c.get("kind", &"injured"))
		rows.append(["%s  %s" % [RaidFlow.CASUALTY_GLYPHS.get(kind, "▲"), RaidFlow.resident_name(StringName(c.get("resident_id", &"")))],
			RaidFlow.CASUALTY_NAMES.get(kind, String(kind)), Color("ff8a7a") if kind == &"dead" else UiTokens.WARN])
	_table(pv, rows, "다친 사람이 없어요.")
	right.add_child(pp[0])

	var loot: Dictionary = result.get("loot", {})
	var used: Dictionary = result.get("used", {})
	var gp := MenuScreen.panel("얻은 것과 쓴 것", "")
	var gv: VBoxContainer = gp[1]
	rows = []
	for id in loot:
		rows.append([MenuScreen.resource_name(StringName(id)), "+%d" % int(loot[id]), UiTokens.ACCENT])
	if int(used.get("decoys", 0)) > 0:
		rows.append(["소음 미끼 장치", "%d개 씀" % int(used.decoys), UiTokens.TEXT])
	if int(used.get("traps", 0)) > 0:
		rows.append(["가시 함정", "%d개 1회씩 씀" % int(used.traps), UiTokens.TEXT])
	var ess: Dictionary = used.get("essence", {})
	for id in ess:
		rows.append(["- " + MenuScreen.resource_name(StringName(id)), "−%d (정수 등불)" % int(ess[id]), UiTokens.TEXT])
	_table(gv, rows, "없음")
	right.add_child(gp[0])

	var th := MenuScreen.panel("습격 위협도", "")
	var thv: VBoxContainer = th[1]
	var tl := MenuScreen.label("%s %d / %d  (습격 뒤 내려감)" % [BaseHud.ThreatGauge.zone_name(Colony.threat), Colony.threat, RaidRules.THREAT_MAX], &"LabelHud", 16)
	tl.add_theme_color_override(&"font_color", BaseHud.ThreatGauge.zone_color(Colony.threat))
	thv.add_child(tl)
	var gauge := BaseHud.ThreatGauge.new()
	gauge.value = Colony.threat
	gauge.custom_minimum_size = Vector2(420, 12)
	thv.add_child(gauge)
	right.add_child(th[0])
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(fill)
	_go = MenuScreen.button("계속", &"ButtonPrimary")
	_go.size_flags_horizontal = Control.SIZE_SHRINK_END
	_go.custom_minimum_size = Vector2(240, 0)
	_go.modulate.a = 0.0
	_go.pressed.connect(close)
	right.add_child(_go)
	row.add_child(right)


func _process(delta: float) -> void:
	if _ratio_label == null:
		return
	_t += delta
	var k := clampf(_t / COUNT_SEC, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	_ratio_label.text = "%.2f" % (float(result.get("ratio", 0.0)) * e)
	_odds.reveal = e
	if k >= 1.0:
		_go.modulate.a = 1.0


## "자동 판정 · 북쪽·동쪽 · 3일차 밤" (mode as given by Colony).
func _mode_line() -> String:
	var mode := int(result.get("mode", Enums.RaidMode.AUTO))
	var m := "자동 판정 (기지에 없음)"
	if bool(result.get("direct", false)):
		m = "직접 방어전"
	elif mode == Enums.RaidMode.PLAYED:
		m = "자동 판정 (기지에 있음, 방어 +%d%%)" % roundi((RaidRules.PLAYED_BONUS - 1.0) * 100.0)
	return "%d일차 %s / %s" % [int(result.get("day", GameState.day)), RaidFlow.time_text(result), m]


## Rows [[name, value, colour], ...] in the 정산표 stripe style.
func _table(v: VBoxContainer, rows: Array, empty_text: String) -> void:
	if rows.is_empty():
		v.add_child(MenuScreen.label(empty_text, &"LabelDim", 15))
		return
	var stripe := false
	for r: Array in rows:
		v.add_child(_striped([String(r[0]), String(r[1])], stripe, false, r[2]))
		stripe = not stripe


func _striped(cols: Array, dark: bool, numbered: bool, value_color := UiTokens.TEXT) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.22) if dark else Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	p.add_theme_stylebox_override(&"panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 14)
	if numbered:
		var n := MenuScreen.label(String(cols[0]), &"LabelNumber", 18)
		n.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
		n.custom_minimum_size = Vector2(22, 0)
		h.add_child(n)
		var t := MenuScreen.label(String(cols[1]), &"LabelHud", 17)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
	else:
		var a := MenuScreen.label(String(cols[0]), &"LabelHud", 16)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		var c := MenuScreen.label(String(cols[1]), &"LabelHud", 16)
		c.add_theme_color_override(&"font_color", value_color)
		h.add_child(c)
	p.add_child(h)
	return p


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept") and _go != null and _go.modulate.a >= 1.0:
		# Mark handled first: close() removes this node, so get_viewport() is null afterwards (#86).
		get_viewport().set_input_as_handled()
		close()
