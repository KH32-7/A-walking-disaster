class_name OutpostsScreen
extends MenuScreen
## Outposts (#125 part 4, C-19). Owner: Lane D. Screen id `outposts`. Design 10 "방어 시설", "전초기지".
## Left: a small world map — the base in the middle, the four direction nodes around it and one node
## per region entrance on the outer ring (Colony.outpost_nodes()). Each node's state is a shape + word:
##   ○ 비어 있음 · ◐ 짓는 중 · △ 주둔 부족 (멈춤) · ✕ 부서짐 (멈춤) · ◆ 가동 중
## Right: the chosen node — build (can_build_outpost reasons + cost → build_outpost), the 2 garrison
## places (assign_garrison; leaving is unassign_job — never assign_job), repair (outpost_repair_cost →
## repair_outpost). Redraws on Colony.outposts_changed. open_with({"node_id": id}) picks one.
## UI 재설계: a step band shows the order (① 짓기 → ② 주둔 2명 → ③ 가동; a broken one starts with 수리),
## faces come before names, and only the current step's button is yellow. Outposts are places:
## marker_lines() / facility_choices() give the world tag and the [F] lines for the coming facility list.

const STATE_WORDS := {
	&"empty": "○ 비어 있음", &"building": "◐ 짓는 중", &"short": "△ 주둔 부족 · 멈춤",
	&"damaged": "✕ 부서짐 · 멈춤", &"active": "◆ 가동 중",
}

var _sel: StringName = &""
var _map: OutpostMap
var _detail: VBoxContainer
var _count: Label
## Last refused action, shown under the buttons.
var _note := ""


func _init() -> void:
	title_text = "전초기지"
	subtitle_text = "기지 밖"
	footer_keys = [["Esc", "뒤로"], ["클릭", "고르기"]]


func open_with(args: Dictionary) -> void:
	if args.has("node_id"):
		_sel = StringName(args.node_id)
		if _map != null:
			refresh()


func _build_body(b: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 24)
	b.add_child(row)
	var left := MenuScreen.panel("지도", "", Vector2(760, 0))
	(left[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left[0])
	_count = (left[2] as HBoxContainer).get_child(1)
	_map = OutpostMap.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.picked.connect(func(id: StringName) -> void:
		_sel = id
		_note = ""
		refresh())
	(left[1] as VBoxContainer).add_child(_map)
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override(&"h_separation", 22)
	for k: StringName in STATE_WORDS:
		legend.add_child(MenuScreen.label(STATE_WORDS[k], &"LabelDim", 14))
	(left[1] as VBoxContainer).add_child(legend)
	var right := MenuScreen.panel("전초기지", "", Vector2(0, 0))
	(right[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(right[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right[0])
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override(&"separation", 12)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_detail)
	(right[1] as VBoxContainer).add_child(sc)
	Colony.outposts_changed.connect(refresh)
	refresh()


func on_closing() -> void:
	if Colony.outposts_changed.is_connected(refresh):
		Colony.outposts_changed.disconnect(refresh)


func refresh() -> void:
	var nodes := Colony.outpost_nodes()
	if (_sel == &"" or _node(nodes, _sel).is_empty()) and not nodes.is_empty():
		_sel = StringName(nodes[0]["node_id"])
	var active := 0
	for n: Dictionary in nodes:
		if n.get("active", false):
			active += 1
	_count.text = "가동 %d / %d곳" % [active, nodes.size()]
	_map.nodes = nodes
	_map.selected = _sel
	_map.queue_redraw()
	_show_detail(_node(nodes, _sel))


static func state_of(n: Dictionary) -> StringName:
	if not n.get("built", false):
		return &"empty"
	if n.get("damaged", false):
		return &"damaged"
	if not n.get("ready", false):
		return &"building"
	if n.get("active", false):
		return &"active"
	return &"short"


static func node_name(n: Dictionary) -> String:
	var dir := StringName(n.get("direction", &""))
	if dir != &"":
		return "%s 전초기지" % RaidFlow.DIRECTION_NAMES.get(dir, String(dir))
	var region := FieldHud.region_display_name(StringName(n.get("region_id", &"")))
	return "%s 입구 전초기지" % region


static func short_name(n: Dictionary) -> String:
	var dir := StringName(n.get("direction", &""))
	if dir != &"":
		return String(RaidFlow.DIRECTION_NAMES.get(dir, String(dir)))
	return "%s 입구" % FieldHud.region_display_name(StringName(n.get("region_id", &"")))


## The order of the work for a node, as StepBand steps.
static func steps_for(n: Dictionary) -> Array:
	var g: int = (n.get("garrison", []) as Array).size()
	var full := g >= OutpostRules.GARRISON_SIZE
	var crew := "주둔 %d/%d" % [g, OutpostRules.GARRISON_SIZE]
	match state_of(n):
		&"empty":
			return [{"label": "짓기 · %d일" % OutpostRules.BUILD_DAYS, "state": StepBand.NOW},
				{"label": crew, "state": StepBand.TODO}, {"label": "가동", "state": StepBand.TODO}]
		&"building":
			return [{"label": "짓는 중 · %d일차 완성" % int(n.get("ready_day", 0)), "state": StepBand.NOW},
				{"label": crew, "state": StepBand.TODO}, {"label": "가동", "state": StepBand.TODO}]
		&"damaged":
			return [{"label": "수리", "state": StepBand.NOW},
				{"label": crew, "state": StepBand.DONE if full else StepBand.TODO}, {"label": "가동", "state": StepBand.TODO}]
		&"short":
			return [{"label": "짓기", "state": StepBand.DONE}, {"label": crew, "state": StepBand.NOW},
				{"label": "가동", "state": StepBand.TODO}]
	return [{"label": "짓기", "state": StepBand.DONE}, {"label": crew, "state": StepBand.DONE},
		{"label": "가동 중", "state": StepBand.DONE}]


## World tag text for a node: [small name, big state].
static func marker_lines(n: Dictionary) -> Array[String]:
	var g: int = (n.get("garrison", []) as Array).size()
	var big: String = {&"empty": "빈 노드 · 지을 수 있음", &"building": "짓는 중 · %d일차" % int(n.get("ready_day", 0)),
		&"damaged": "✕ 부서짐 · 수리 필요", &"short": "주둔 %d/%d" % [g, OutpostRules.GARRISON_SIZE],
		&"active": "◆ 가동 중 · 주둔 %d/%d" % [g, OutpostRules.GARRISON_SIZE]}[state_of(n)]
	return [node_name(n), big]


## A node's [F] lines: [{label, state, screen, args}] (the screen opens on that node).
static func facility_choices(n: Dictionary) -> Array:
	var args := {"node_id": StringName(n.get("node_id", &""))}
	var g: int = (n.get("garrison", []) as Array).size()
	match state_of(n):
		&"empty":
			return [{"label": "전초기지 짓기", "state": "", "screen": &"outposts", "args": args}]
		&"building":
			return [{"label": "짓는 중", "state": "%d일차" % int(n.get("ready_day", 0)), "screen": &"outposts", "args": args}]
		&"damaged":
			return [{"label": "수리", "state": "", "screen": &"outposts", "args": args},
				{"label": "주둔 배정", "state": "%d/%d" % [g, OutpostRules.GARRISON_SIZE], "screen": &"outposts", "args": args}]
	return [{"label": "주둔 배정", "state": "%d/%d" % [g, OutpostRules.GARRISON_SIZE], "screen": &"outposts", "args": args}]


func _node(nodes: Array, id: StringName) -> Dictionary:
	for n: Dictionary in nodes:
		if StringName(n["node_id"]) == id:
			return n
	return {}


func _show_detail(n: Dictionary) -> void:
	MenuScreen.clear(_detail)
	if n.is_empty():
		_detail.add_child(MenuScreen.label("전초기지를 지을 곳이 없어요.", &"LabelDim", 16))
		return
	var id := StringName(n["node_id"])
	var st := state_of(n)
	_detail.add_child(MenuScreen.label(node_name(n), &"LabelTitle", 26))
	var sl := MenuScreen.label(STATE_WORDS[st], &"LabelSection", 18)
	sl.add_theme_color_override(&"font_color", {&"active": UiTokens.GOOD, &"damaged": UiTokens.DANGER,
		&"short": UiTokens.WARN}.get(st, UiTokens.TEXT))
	_detail.add_child(sl)
	var band := StepBand.new()
	band.set_steps(steps_for(n))
	_detail.add_child(band)
	_detail.add_child(_effect_card(n))
	match st:
		&"empty":
			_build_part(id)
		&"building":
			_detail.add_child(MenuScreen.label("%d일차에 완성돼요. 완성되면 주민 %d명을 주둔시킬 수 있어요." % [
				int(n.get("ready_day", 0)), OutpostRules.GARRISON_SIZE], &"LabelHud", 15))
		&"damaged":
			_repair_part(id)
			_garrison_part(n, false)
		&"short":
			_garrison_part(n, true)
		_:
			_garrison_part(n, false)
	if _note != "":
		var nl := MenuScreen.label(_note, &"LabelHud", 14)
		nl.add_theme_color_override(&"font_color", UiTokens.WARN)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(nl)


## What an active outpost does (design 10 table, numbers from OutpostRules / RaidRules).
func _effect_card(n: Dictionary) -> Control:
	var cc := MenuScreen.cream_card(0)
	var v: VBoxContainer = cc[1]
	v.add_child(MenuScreen.label("가동하면 (주둔 %d명)" % OutpostRules.GARRISON_SIZE, &"LabelOnCreamDim", 14))
	var lines: PackedStringArray = []
	lines.append("위협도 −%d/일" % roundi(RaidRules.THREAT_PER_OUTPOST))
	if StringName(n.get("direction", &"")) != &"":
		lines.append("이 방향 습격 강도 −%d%% · 하루 전 예고 + 규모·계열" % roundi(OutpostRules.DIRECTION_CUT * 100.0))
	var gather: PackedStringArray = []
	for res: StringName in OutpostRules.GATHER:
		gather.append("%s +%d" % [MenuScreen.resource_name(res), int(OutpostRules.GATHER[res])])
	lines.append("주변 채집 %s /일" % " · ".join(gather))
	lines.append("유지비 %s /일" % MenuScreen.cost_text(OutpostRules.UPKEEP))
	for t in lines:
		var l := MenuScreen.label("·  " + t, &"LabelOnCream", 15)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	var warn := MenuScreen.label("습격의 일부는 전초기지를 노려요. 무너지면 주둔 주민이 다치고 멈춰요.", &"LabelOnCreamDim", 13)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(warn)
	return cc[0]


func _build_part(id: StringName) -> void:
	var can := Colony.can_build_outpost(id)
	_detail.add_child(MenuScreen.label("짓기", &"LabelSection", 16))
	_detail.add_child(_cost_row(can.get("cost", {})))
	_detail.add_child(MenuScreen.label("기지 밖이라 건설 주민 없이 %d일 걸려요." % OutpostRules.BUILD_DAYS, &"LabelDim", 14))
	for r: String in can.get("reasons", []):
		var l := MenuScreen.label("■ " + r, &"LabelHud", 14)
		l.add_theme_color_override(&"font_color", UiTokens.DANGER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(l)
	var b := MenuScreen.button("짓기", &"ButtonPrimary")
	b.custom_minimum_size = Vector2(200, 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.disabled = not can.get("ok", false)
	b.pressed.connect(build.bind(id))
	_detail.add_child(b)


func _repair_part(id: StringName) -> void:
	var cost := Colony.outpost_repair_cost(id)
	var ok := Economy.can_afford(cost)
	_detail.add_child(MenuScreen.label("수리", &"LabelSection", 16))
	_detail.add_child(_cost_row(cost))
	if not ok:
		var l := MenuScreen.label("■ 자원이 모자라요", &"LabelHud", 14)
		l.add_theme_color_override(&"font_color", UiTokens.DANGER)
		_detail.add_child(l)
	var b := MenuScreen.button("수리", &"ButtonPrimary")
	b.custom_minimum_size = Vector2(200, 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.disabled = not ok
	b.pressed.connect(repair.bind(id))
	_detail.add_child(b)


## Cost chips: name + amount, short ones marked ■ and "부족" (not colour alone).
func _cost_row(cost: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 18)
	for res: StringName in cost:
		var have := Economy.get_amount(res)
		var short := have < int(cost[res])
		var l := MenuScreen.label("%s%s %d (%d)%s" % ["■ " if short else "", MenuScreen.resource_name(res), int(cost[res]), have,
			" 부족" if short else ""], &"LabelHud", 15)
		if short:
			l.add_theme_color_override(&"font_color", UiTokens.DANGER)
		h.add_child(l)
	return h


## `lead`: the garrison is the current step, so the first resident who can go gets the yellow button.
func _garrison_part(n: Dictionary, lead: bool) -> void:
	var id := StringName(n["node_id"])
	var garrison: Array = n.get("garrison", [])
	_detail.add_child(MenuScreen.label("주둔  %d / %d" % [garrison.size(), OutpostRules.GARRISON_SIZE], &"LabelSection", 16))
	for i in OutpostRules.GARRISON_SIZE:
		var p := PanelContainer.new()
		p.theme_type_variation = &"PanelSlateInner"
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 12)
		if i < garrison.size():
			var rid := StringName(garrison[i])
			h.add_child(FaceDot.new(LossText.display_name(rid), 40))
			var nm := MenuScreen.label(LossText.display_name(rid), &"LabelSection", 17)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(nm)
			var off := MenuScreen.button("해제", &"ButtonCancel")
			off.pressed.connect(release.bind(rid))
			h.add_child(off)
		else:
			h.add_child(EmptySeat.new())
			var e := MenuScreen.label("빈 자리", &"LabelDim", 16)
			e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(e)
		p.add_child(h)
		_detail.add_child(p)
	_detail.add_child(MenuScreen.label("주둔할 주민", &"LabelSection", 16))
	var full := garrison.size() >= OutpostRules.GARRISON_SIZE
	var any := false
	var yellow := lead
	for rid: StringName in Colony.active_resident_ids():
		if rid in garrison:
			continue
		any = true
		var row := _candidate_row(id, rid, full, yellow)
		if row.get_meta(&"primary", false):
			yellow = false
		_detail.add_child(row)
	if not any:
		_detail.add_child(MenuScreen.label("보낼 수 있는 주민이 없어요.", &"LabelDim", 15))


func _candidate_row(node_id: StringName, rid: StringName, full: bool, may_be_primary := false) -> Control:
	var r := Colony.get_resident(rid)
	var why := Colony.job_block_reason(rid, OutpostRules.GARRISON_JOB)
	if why == "" and full:
		why = "자리가 다 찼어요"
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	h.add_child(FaceDot.new(LossText.display_name(rid), 36, why != "", LossText.face_mark(rid)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(MenuScreen.label(LossText.display_name(rid), &"LabelHud", 16))
	var job := BaseDB.get_job(Colony.job_of(rid))
	var sub := "지금 " + (job.display_name if job != null else "일 없음")
	if Colony.job_of(rid) == OutpostRules.GARRISON_JOB:
		sub = "다른 전초기지에서 옮겨요"
	var grief := LossText.grief_tag(r)
	if grief != "":
		sub += " · " + grief
	v.add_child(MenuScreen.label(sub, &"LabelDim", 13))
	if why != "":
		var wl := MenuScreen.label("■ " + why, &"LabelDim", 13)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(wl)
	h.add_child(v)
	var primary := may_be_primary and why == ""
	var b := MenuScreen.button("주둔", &"ButtonPrimary" if primary else &"ButtonSecondary")
	b.disabled = why != ""
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(station.bind(node_id, rid))
	h.add_child(b)
	h.set_meta(&"primary", primary)
	return h


# ---------------- actions (Colony only) ----------------

func build(id: StringName) -> bool:
	var ok := Colony.build_outpost(id)
	_note = "" if ok else "■ 지을 수 없어요: " + ", ".join(PackedStringArray(Colony.can_build_outpost(id).get("reasons", [])))
	refresh()
	return ok


func station(node_id: StringName, rid: StringName) -> bool:
	var ok := Colony.assign_garrison(node_id, rid)
	if not ok:
		var why := Colony.job_block_reason(rid, OutpostRules.GARRISON_JOB)
		_note = "■ 주둔시킬 수 없어요" + (": " + why if why != "" else "")
	else:
		_note = ""
	refresh()
	return ok


## Leaving the garrison is the ordinary unassign (Colony emits nothing for it, so redraw here).
func release(rid: StringName) -> void:
	Colony.unassign_job(rid)
	_note = ""
	refresh()


func repair(id: StringName) -> bool:
	var ok := Colony.repair_outpost(id)
	_note = "" if ok else "■ 수리할 수 없어요"
	refresh()
	return ok


## Dashed circle for an empty garrison seat (the mockup's "자리 하나 비어 있음" card).
class EmptySeat extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(40, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		for i in 16:
			if i % 2 == 0:
				draw_arc(c, 18.0, TAU * i / 16.0, TAU * (i + 1) / 16.0, 4, UiTokens.TEXT_DIM, 1.5, true)


## World map of the outpost nodes. Pure drawing + click picking; state comes from `nodes`.
class OutpostMap extends Control:
	signal picked(node_id: StringName)

	const DIR_VEC := {&"north": Vector2(0, -1), &"east": Vector2(1, 0), &"south": Vector2(0, 1), &"west": Vector2(-1, 0)}
	const NODE_R := 16.0
	const INNER := 0.24
	const OUTER := 0.40

	var nodes: Array = []
	var selected: StringName = &""

	func _init() -> void:
		custom_minimum_size = Vector2(0, 560)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func positions() -> Dictionary:
		var out := {}
		var c := size * 0.5
		var inner := minf(size.x, size.y) * INNER
		var outer := minf(size.x, size.y) * OUTER
		var regions: Array = []
		for n: Dictionary in nodes:
			var dir := StringName(n.get("direction", &""))
			if DIR_VEC.has(dir):
				out[n["node_id"]] = c + DIR_VEC[dir] * inner
			else:
				regions.append(n["node_id"])
		# Region entrances share the four quadrants between the direction nodes (round-robin, clockwise
		# from the north-east), so no connector crosses a direction node.
		var per := ceili(regions.size() / 4.0)
		for i in regions.size():
			var ang := deg_to_rad(90.0 * (i % 4) + 90.0 * (i / 4 + 1) / (per + 1))
			out[regions[i]] = c + Vector2(sin(ang), -cos(ang)) * outer
		return out

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var pos := positions()
			for id in pos:
				if (pos[id] as Vector2).distance_to(event.position) < NODE_R * 2.2:
					picked.emit(StringName(id))
					accept_event()
					return

	func _draw() -> void:
		var c := size * 0.5
		var font := UiThemeBuilder.font_kr(500)
		var inner := minf(size.x, size.y) * INNER
		var outer := minf(size.x, size.y) * OUTER
		draw_arc(c, inner, 0, TAU, 64, Color(UiTokens.LINE, 0.5), 1.0, true)
		_dashed_circle(c, outer, Color(UiTokens.LINE, 0.4))
		# base
		draw_rect(Rect2(c - Vector2(34, 26), Vector2(68, 52)), UiTokens.SLATE_2)
		draw_rect(Rect2(c - Vector2(34, 26), Vector2(68, 52)), UiTokens.LINE_STRONG, false, 2.0)
		draw_string(font, c + Vector2(-34, 6), "기지", HORIZONTAL_ALIGNMENT_CENTER, 68, 16, UiTokens.TEXT)
		var pos := positions()
		for n: Dictionary in nodes:
			var p: Vector2 = pos[n["node_id"]]
			var st := OutpostsScreen.state_of(n)
			draw_line(c + (p - c).normalized() * 40.0, p - (p - c).normalized() * (NODE_R + 4), Color(UiTokens.LINE, 0.7 if st == &"active" else 0.35), 2.0 if st == &"active" else 1.0)
			_node_shape(p, st)
			if StringName(n["node_id"]) == selected:
				draw_arc(p, NODE_R + 8, 0, TAU, 40, UiTokens.ACCENT, 3.0, true)
			var g: Array = n.get("garrison", [])
			var sub := "주둔 %d/%d" % [g.size(), OutpostRules.GARRISON_SIZE] if n.get("built", false) else "빈 노드"
			var o := (p - c).normalized()
			if StringName(n.get("direction", &"")) == &"":
				o = Vector2(0, -1 if o.y < 0 else 1)  # outer ring: always above / below, inside the map
			_node_label(font, p, o, OutpostsScreen.short_name(n), sub)

	## Two lines on the outer side of the node, so the connector line to the base stays clear.
	func _node_label(font: Font, p: Vector2, o: Vector2, title: String, sub: String) -> void:
		var w := 200.0
		if absf(o.y) >= absf(o.x) - 0.01:
			var y := p.y - NODE_R - 30 if o.y < 0 else p.y + NODE_R + 26
			var x := clampf(p.x - w * 0.5, 0.0, maxf(size.x - w, 0.0))
			draw_string(font, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_CENTER, w, 16, UiTokens.TEXT)
			draw_string(font, Vector2(x, y + 18), sub, HORIZONTAL_ALIGNMENT_CENTER, w, 13, UiTokens.TEXT_DIM)
		else:
			var x := p.x + NODE_R + 12 if o.x > 0 else p.x - NODE_R - 12 - w
			var al := HORIZONTAL_ALIGNMENT_LEFT if o.x > 0 else HORIZONTAL_ALIGNMENT_RIGHT
			draw_string(font, Vector2(x, p.y - 2), title, al, w, 16, UiTokens.TEXT)
			draw_string(font, Vector2(x, p.y + 16), sub, al, w, 13, UiTokens.TEXT_DIM)

	func _node_shape(p: Vector2, st: StringName) -> void:
		var r := NODE_R
		match st:
			&"empty":
				draw_arc(p, r, 0, TAU, 32, UiTokens.TEXT_DIM, 2.0, true)
			&"building":
				draw_arc(p, r, 0, TAU, 32, UiTokens.TEXT, 2.0, true)
				var half := PackedVector2Array([p + Vector2(0, -r)])
				for i in 17:
					half.append(p + Vector2(0, -r).rotated(PI * i / 16.0))
				draw_colored_polygon(half, UiTokens.TEXT)
			&"short":
				var tri := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, r * 0.8), p + Vector2(-r, r * 0.8), p + Vector2(0, -r)])
				draw_polyline(tri, UiTokens.WARN, 3.0, true)
			&"damaged":
				draw_line(p + Vector2(-r, -r) * 0.8, p + Vector2(r, r) * 0.8, UiTokens.DANGER, 4.0, true)
				draw_line(p + Vector2(r, -r) * 0.8, p + Vector2(-r, r) * 0.8, UiTokens.DANGER, 4.0, true)
			&"active":
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), UiTokens.GOOD)

	func _dashed_circle(c: Vector2, r: float, col: Color) -> void:
		var n := 72
		for i in n:
			if i % 2 == 0:
				draw_arc(c, r, TAU * i / n, TAU * (i + 1) / n, 4, col, 1.0, true)
