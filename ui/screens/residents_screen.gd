extends MenuScreen
## Residents list + detail (D-06). Owner: Lane D. Design 07 "주민 데이터", 14 "주민 목록", "주민 상세".
## Left: rows with status (job, needs bars, health, bed). Right: detail of the selected resident —
## stats, traits, participation conditions (access needs), job/bed, equipment slots (Armory), trust,
## story. Talk / gift / 관계도 / 입주 의식 open the D-13 screens, equipment with D-08. Reads Colony / Armory / BaseDB only.
## open_with({"id": resident_id}) selects one.

const STAT_NAMES := {&"str": "힘", &"dex": "손재주", &"sense": "감각", &"heart": "마음"}
const AGE_NAMES := ["아기", "어린이", "청소년", "성인", "노년"]
const NEED_NAMES := ["이동 보조 필요", "말이 잘 안 통함", "듣기 어려움", "돌봄 필요"]
const NEED_FIX := ["경사로·승강기 있는 곳에서 일함", "통역 무전기가 있으면 대화", "시각 신호가 있으면 일함", "돌봄 담당이 있으면 생활"]
const HEALTH_NAMES := ["건강", "다침", "아픔"]
const SLOT_NAMES := ["주무기", "보조", "머리", "몸", "다리", "장신구", "가방"]
const FORMER_JOBS := {&"carpenter": "목수", &"nurse": "간호사", &"doctor": "의사", &"mechanic": "정비공",
	&"electrician": "전기 기사", &"cook": "요리사", &"farmer": "농부", &"teacher": "교사", &"interpreter": "통역사",
	&"radio_pd": "라디오 PD", &"police": "경찰", &"athlete": "운동선수", &"painter": "화가", &"laborer": "노동자",
	&"student": "학생"}
const SORTS := [["이름", "name"], ["사기", "morale"], ["배고픔", "hunger"], ["피로", "fatigue"]]

var _sel: StringName = &""
var _sort := "name"
var _list: VBoxContainer
var _detail: VBoxContainer
var _count: Label


func _init() -> void:
	title_text = "주민"
	subtitle_text = "기지"
	footer_keys = [["Esc", "뒤로"], ["클릭", "고르기"]]


func open_with(args: Dictionary) -> void:
	if args.has("id"):
		_sel = StringName(args.id)
		if _list != null:
			_fill()


func _build_body(b: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 24)
	b.add_child(row)
	var left := MenuScreen.panel("주민", "", Vector2(720, 0))
	(left[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left[0])
	_count = (left[2] as HBoxContainer).get_child(1)
	var sorts := HBoxContainer.new()
	sorts.add_theme_constant_override(&"separation", 4)
	(left[2] as HBoxContainer).add_child(sorts)
	if UI.has_screen(&"relations"):
		var rel := MenuScreen.button("관계도", &"ButtonSoft")
		rel.pressed.connect(func() -> void: UI.open(&"relations", {"id": _sel}))
		(left[2] as HBoxContainer).add_child(rel)
	for s: Array in SORTS:
		var t := MenuScreen.button(String(s[0]), &"TabText")
		t.toggle_mode = true
		t.button_pressed = _sort == s[1]
		t.pressed.connect(func() -> void:
			_sort = s[1]
			for c: Button in sorts.get_children():
				c.button_pressed = c == t
			_fill())
		sorts.add_child(t)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	(left[1] as VBoxContainer).add_child(sc)
	var right := MenuScreen.panel("상세", "", Vector2(0, 0))
	(right[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(right[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right[0])
	_detail = right[1]
	UI.screen_closed.connect(_on_screen_closed)
	_fill()


## Back from a D-13 screen: trust, likes, nickname or bed may have changed.
func _on_screen_closed(id: StringName) -> void:
	if id in [&"dialog", &"gift", &"welcome", &"child_naming", &"child_wish", &"prejudice_choice", &"wedding_prep"] 			and is_inside_tree():
		_fill()


func _ids() -> Array:
	var ids: Array = Colony.active_resident_ids()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ra := Colony.get_resident(a)
		var rb := Colony.get_resident(b)
		if _sort == "name":
			return String(ra.get("name", "")) < String(rb.get("name", ""))
		if _sort == "morale":
			return int(ra.get("morale", 0)) < int(rb.get("morale", 0))
		if _sort == "hunger":
			return int(ra.get("hunger", 0)) < int(rb.get("hunger", 0))
		return int(ra.get("fatigue", 0)) > int(rb.get("fatigue", 0)))
	return ids


func _fill() -> void:
	MenuScreen.clear(_list)
	var ids := _ids()
	_count.text = "%d명 · 침상 %d" % [Colony.population(), Colony.bed_count()]
	if (_sel == &"" or not _sel in ids) and not ids.is_empty():
		_sel = ids[0]
	for id: StringName in ids:
		_list.add_child(_row(id))
	_show_detail()


func _row(id: StringName) -> Control:
	var r := Colony.get_resident(id)
	var b := Button.new()
	b.theme_type_variation = &"ButtonCancel"
	var sel := id == _sel
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.08) if sel else Color(1, 1, 1, 0.03)
	box.border_color = UiTokens.ACCENT if sel else Color(1, 1, 1, 0.12)
	box.set_border_width_all(2 if sel else 1)
	box.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	for s in [&"normal", &"hover", &"pressed", &"focus"]:
		b.add_theme_stylebox_override(s, box)
	b.custom_minimum_size = Vector2(0, 68)
	b.focus_mode = Control.FOCUS_NONE
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -14
	h.add_theme_constant_override(&"separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_avatar(String(r.get("name", "?")), 44))
	var nv := VBoxContainer.new()
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.add_theme_constant_override(&"separation", -2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(MenuScreen.label(String(r.get("name", "")), &"LabelSection", 18))
	nv.add_child(MenuScreen.label(_job_line(r), &"LabelDim", 13))
	h.add_child(nv)
	var needs := GridContainer.new()
	needs.columns = 2
	needs.add_theme_constant_override(&"v_separation", 2)
	for pair in [["배고픔", 100 - int(r.get("hunger", 50)), true], ["피로", int(r.get("fatigue", 0)), true],
			["사기", int(r.get("morale", 50)), false]]:
		needs.add_child(MenuScreen.label(String(pair[0]), &"LabelDim", 12))
		var bad: bool = pair[2]
		var v := float(pair[1]) / 100.0
		needs.add_child(MenuScreen.bar(v, UiTokens.WARN if (bad and v > 0.6) or (not bad and v < 0.35) else UiTokens.TEXT, 110, 6))
	needs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(needs)
	var hs := int(r.get("health", 0))
	var hl := MenuScreen.label(HEALTH_NAMES[clampi(hs, 0, 2)], &"LabelHud", 14)
	hl.custom_minimum_size = Vector2(44, 0)
	if hs != 0:
		hl.add_theme_color_override(&"font_color", UiTokens.DANGER)
	h.add_child(hl)
	b.add_child(h)
	b.pressed.connect(func() -> void:
		_sel = id
		_fill())
	return b


func _job_line(r: Dictionary) -> String:
	var a: Dictionary = r.get("assignment", {})
	var job := BaseDB.get_job(StringName(a.get("job", &"")))
	var age: String = AGE_NAMES[clampi(int(r.get("age_stage", 3)), 0, 4)]
	return "%s · %s" % [age, job.display_name if job != null else "일 없음"]


func _show_detail() -> void:
	MenuScreen.clear(_detail)
	if _sel == &"":
		_detail.add_child(MenuScreen.label("아직 주민이 없어요. 필드에서 사람을 구해 오세요.", &"LabelDim", 16))
		return
	var r := Colony.get_resident(_sel)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 16)
	head.add_child(_avatar(String(r.get("name", "?")), 76))
	var hv := VBoxContainer.new()
	var nick := String(r.get("nickname", ""))
	hv.add_child(MenuScreen.label(String(r.get("name", "")) + ("  “%s”" % nick if nick != "" else ""), &"LabelTitle", 26))
	hv.add_child(MenuScreen.label("%s · 전직 %s · %d일차에 합류" % [AGE_NAMES[clampi(int(r.get("age_stage", 3)), 0, 4)],
		String(FORMER_JOBS.get(StringName(r.get("former_job", &"")), r.get("former_job", ""))), int(r.get("joined_day", 1))], &"LabelDim", 14))
	var trust := HBoxContainer.new()
	trust.add_theme_constant_override(&"separation", 4)
	trust.add_child(MenuScreen.label("신뢰", &"LabelDim", 13))
	var t := int(r.get("trust", 0))
	for i in 5:
		var dot := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(7)
		sb.border_color = UiTokens.ACCENT
		sb.set_border_width_all(2)
		sb.bg_color = UiTokens.ACCENT if t >= (i + 1) * 20 else Color.TRANSPARENT
		dot.add_theme_stylebox_override(&"panel", sb)
		dot.custom_minimum_size = Vector2(14, 14)
		trust.add_child(dot)
	trust.add_child(MenuScreen.label("%d/100" % t, &"LabelDim", 13))
	hv.add_child(trust)
	head.add_child(hv)
	_detail.add_child(head)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 30)
	var lc := VBoxContainer.new()
	lc.add_theme_constant_override(&"separation", 8)
	lc.custom_minimum_size = Vector2(330, 0)
	lc.add_child(MenuScreen.label("능력치", &"LabelSection", 16))
	var stats: Dictionary = r.get("stats", {})
	var sg := GridContainer.new()
	sg.columns = 3
	sg.add_theme_constant_override(&"h_separation", 12)
	for k: StringName in STAT_NAMES:
		var v := int(stats.get(k, 1))
		sg.add_child(MenuScreen.label(STAT_NAMES[k], &"LabelHud", 15))
		sg.add_child(MenuScreen.bar(v / 10.0, UiTokens.INFO if v >= 7 else UiTokens.TEXT, 170, 8))
		sg.add_child(MenuScreen.label(str(v), &"LabelNumber", 16))
	lc.add_child(sg)
	lc.add_child(MenuScreen.label("특성", &"LabelSection", 16))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override(&"h_separation", 6)
	chips.add_theme_constant_override(&"v_separation", 6)
	for tr: StringName in r.get("traits", []):
		var td := BaseDB.get_trait(tr)
		chips.add_child(_chip(td.display_name if td != null else String(tr), UiTokens.LINE_STRONG))
	lc.add_child(chips)
	var needs: Array = r.get("access_needs", [])
	if not needs.is_empty():
		lc.add_child(MenuScreen.label("참여 조건", &"LabelSection", 16))
		for n: int in needs:
			var l := MenuScreen.label("◆  %s — %s" % [NEED_NAMES[clampi(n, 0, 3)], NEED_FIX[clampi(n, 0, 3)]], &"LabelHud", 14)
			l.add_theme_color_override(&"font_color", UiTokens.INFO)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(330, 0)
			lc.add_child(l)
	cols.add_child(lc)

	var rc := VBoxContainer.new()
	rc.add_theme_constant_override(&"separation", 8)
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rc.add_child(MenuScreen.label("일·잠자리", &"LabelSection", 16))
	var a: Dictionary = r.get("assignment", {})
	var job := BaseDB.get_job(StringName(a.get("job", &"")))
	var bed := StringName(r.get("bed_id", &""))
	rc.add_child(MenuScreen.label("%s · %s" % [job.display_name if job != null else "일 없음",
		"침상 있음" if bed != &"" else "임시 거처"], &"LabelHud", 15))
	rc.add_child(MenuScreen.label("장비", &"LabelSection", 16))
	var eg := GridContainer.new()
	eg.columns = 4
	eg.add_theme_constant_override(&"h_separation", 8)
	eg.add_theme_constant_override(&"v_separation", 8)
	for s in SLOT_NAMES.size():
		eg.add_child(_equip_slot(_sel, s))
	rc.add_child(eg)
	var story: Dictionary = r.get("story", {})
	rc.add_child(MenuScreen.label("사연", &"LabelSection", 16))
	var st := MenuScreen.label(String(story.get("background", "")), &"LabelHud", 15)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(420, 0)
	rc.add_child(st)
	for f: String in story.get("fragments", []):
		var fl := MenuScreen.label("·  " + f, &"LabelDim", 14)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fl.custom_minimum_size = Vector2(420, 0)
		rc.add_child(fl)
	cols.add_child(rc)
	_detail.add_child(cols)

	# D-13: talk / gift (하루 1번, Colony.trust_actions), 입주 의식 when it is still waiting.
	var known := Colony.known_likes(_sel)
	if not known.is_empty():
		var kl := PackedStringArray()
		for like in known:
			kl.append(ResidentText.tag_name(like))
		_detail.add_child(MenuScreen.label("▲ 좋아하는 것  " + " · ".join(kl), &"LabelDim", 14))
	# #125: 편견 소문 진행, 결혼 약속, 아이 맞이 조건 (ResidentEventFlow reads Colony).
	for line: Array in ResidentEventFlow.detail_lines(_sel):
		var ll := MenuScreen.label(String(line[0]), &"LabelHud", 14)
		ll.add_theme_color_override(&"font_color", line[1])
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(ll)
	var day_acts := Colony.trust_actions(_sel)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override(&"separation", 10)
	var buttons := [["대화", &"ButtonPrimary", &"dialog", day_acts.get("talk", false) or day_acts.get("deep_talk", false), "오늘은 이야기했어요"],
		["선물", &"ButtonSecondary", &"gift", day_acts.get("gift", false), "오늘은 선물했어요"],
		["장비 바꾸기", &"ButtonSecondary", &"armory", true, ""]]
	if ResidentEventFlow.is_family_child(_sel):
		buttons.push_front(["이름 짓기", &"ButtonPrimary", &"child_naming", true, ""])
	elif bool(r.get("arrival_pending", false)):
		buttons.push_front(["입주 의식", &"ButtonPrimary", &"welcome", true, ""])
	for pair: Array in buttons:
		var bt := MenuScreen.button(String(pair[0]), pair[1])
		var target: StringName = pair[2]
		bt.disabled = not UI.has_screen(target)
		bt.tooltip_text = "" if not bt.disabled else "아직 준비 중"
		if not bt.disabled and not bool(pair[3]):
			bt.text += "  ✓"
			bt.tooltip_text = String(pair[4])
		bt.pressed.connect(func() -> void: UI.open(target, {"resident_id": _sel}))
		acts.add_child(bt)
	for ev: Array in ResidentEventFlow.detail_buttons(_sel):
		var eb := MenuScreen.button(String(ev[0]), &"ButtonSecondary")
		var sid: StringName = ev[1]
		var eargs: Dictionary = ev[2]
		eb.pressed.connect(func() -> void: UI.open(sid, eargs))
		acts.add_child(eb)
	_detail.add_child(acts)


func _equip_slot(owner: StringName, slot: int) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(96, 62)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	sb.border_color = UiTokens.LINE
	sb.set_border_width_all(1)
	sb.bg_color = Color(1, 1, 1, 0.04)
	var uid := Armory.get_equipped(owner, slot)
	var text := "비어 있음"
	if uid != &"":
		var it: Variant = Armory.get_item(uid)
		var def: Variant = Armory.get_def(it.def_id) if it != null else null
		text = String(def.name) if def != null else String(uid)
		if it != null:
			sb.bg_color = Color(UiTokens.rarity_color(int(it.rarity)), 0.3)
	box.add_theme_stylebox_override(&"panel", sb)
	var l := MenuScreen.label(text, &"LabelHud" if uid != &"" else &"LabelDim", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	v.add_child(box)
	var cap := MenuScreen.label(SLOT_NAMES[slot], &"LabelDim", 12)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	return v


func _avatar(name_text: String, d: int) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(d / 2)
	sb.bg_color = Color("c98f52")
	sb.border_color = UiTokens.TEXT
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override(&"panel", sb)
	p.custom_minimum_size = Vector2(d, d)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := MenuScreen.label(name_text.substr(name_text.length() - 1, 1) if name_text.length() > 0 else "?",
		&"LabelSection", int(d * 0.42))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override(&"font_color", Color("2a1a0a"))
	p.add_child(l)
	return p


func _chip(text: String, border: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(99)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override(&"panel", sb)
	p.add_child(MenuScreen.label(text, &"LabelHud", 13))
	return p
