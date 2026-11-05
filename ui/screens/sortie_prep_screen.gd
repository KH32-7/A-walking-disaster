extends MenuScreen
## Sortie preparation (D-07). Owner: Lane D. Design 01 "출격 준비", 02 "지역", 14 "출격 준비".
## Left: regions (danger, monster families, resources, unlock). Middle: player loadout (Armory).
## Right: companion (max 1, healthy adults), raid risk while away. "출격" calls
## SceneRouter.go_to_field({region_id, companions, gear}); Esc / "취소" calls cancel_sortie_prep().
## Region names come from data/regions (Lane B) when present; until then the design 02 table below.

const REGIONS := [
	{"id": &"city_park", "name": "숲이 된 도심 공원", "danger": 1, "families": "수풀", "res": "씨앗 / 약초 / 천", "unlock": "시작부터"},
	{"id": &"flooded_mall", "name": "침수 상가", "danger": 2, "families": "물 / 수풀", "res": "페인트 / 천 / 통조림 / 고철", "unlock": "공원 탈출 1회"},
	{"id": &"hospital", "name": "병원", "danger": 3, "families": "물 / 빛", "res": "의약품 / 의료 기구", "unlock": "기지 단계 정착지"},
	{"id": &"office_district", "name": "고층 업무지구", "danger": 4, "families": "빛 / 잔해", "res": "전자부품 / 모터 / 무전 부품", "unlock": "정착지 + 승강기 열쇠"},
	{"id": &"harbor", "name": "항구", "danger": 5, "families": "잔해 / 물", "res": "연료 / 발전기 코어 / 철판", "unlock": "방송실 Lv2"},
]
const MAX_COMPANIONS := 1

var _region: StringName = &""
var _companions: Array[StringName] = []
var _regions_box: VBoxContainer
var _mid: VBoxContainer
var _right: VBoxContainer
var _go: Button


func _init() -> void:
	title_text = "출격 준비"
	subtitle_text = "%d일차 아침" % GameState.day
	footer_keys = [["Esc", "취소"], ["클릭", "고르기"], ["Enter", "출격"]]


func close() -> void:
	SceneRouter.cancel_sortie_prep()


## A region can be picked when its map exists AND its unlock conditions are met (RegionDef, Lane B
## data: flags such as extracted_city_park, base tier, facility level, quest).
static func is_open_region(id: StringName) -> bool:
	if not ResourceLoader.exists(SceneRouter.REGION_SCENE_FMT % [id, id]):
		return false
	var def := RegionDef.load_def(id)
	return def == null or def.is_unlocked()


## Words for a region's state, so a closed row says why (not colour alone).
static func region_status(id: StringName, fallback_unlock: String) -> String:
	var def := RegionDef.load_def(id)
	if not ResourceLoader.exists(SceneRouter.REGION_SCENE_FMT % [id, id]):
		return "준비 중 / 아직 갈 수 없어요"
	if def != null and not def.is_unlocked():
		return "잠김 / " + (def.unlock_text if def.unlock_text != "" else fallback_unlock)
	if not ResourceLoader.exists("res://levels/field/%s/dressing.tscn" % id):
		return "갈 수 있음 / 시험용 지형"
	return "갈 수 있음"


func _build_body(b: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 22)
	b.add_child(row)
	var l := MenuScreen.panel("지역", "위험도 / 계열 / 자원", Vector2(640, 0))
	(l[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(l[0])
	_regions_box = l[1]
	var m := MenuScreen.panel("장비", "", Vector2(520, 0))
	(m[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(m[0])
	_mid = m[1]
	var r := MenuScreen.panel("동행", "최대 %d명" % MAX_COMPANIONS, Vector2(0, 0))
	(r[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(r[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(r[0])
	_right = r[1]
	for reg: Dictionary in REGIONS:
		if is_open_region(reg.id) and _region == &"":
			_region = reg.id
	_refresh()


func _refresh() -> void:
	_fill_regions()
	_fill_loadout()
	_fill_companions()


func _fill_regions() -> void:
	MenuScreen.clear(_regions_box)
	var band := _regions_box.get_child(0) if _regions_box.get_child_count() > 0 else null
	for reg: Dictionary in REGIONS:
		# Only the regions that have a map (사용자 요청 2026-11-06: 맵이 2개인데 5개가 떠 있음).
		if ResourceLoader.exists(SceneRouter.REGION_SCENE_FMT % [reg.id, reg.id]):
			_regions_box.add_child(_region_row(reg))


func _region_row(reg: Dictionary) -> Control:
	var open := is_open_region(reg.id)
	var sel: bool = reg.id == _region
	var b := Button.new()
	b.theme_type_variation = &"ButtonCancel"
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.08) if sel else Color(1, 1, 1, 0.03)
	box.border_color = UiTokens.ACCENT if sel else Color(1, 1, 1, 0.12)
	box.set_border_width_all(2 if sel else 1)
	box.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	for s in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(s, box)
	b.custom_minimum_size = Vector2(0, 92)
	b.disabled = not open
	b.focus_mode = Control.FOCUS_NONE
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16
	h.offset_right = -16
	h.add_theme_constant_override(&"separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_danger_pips(int(reg.danger)))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := MenuScreen.label(String(reg.name), &"LabelSection", 19)
	if not open:
		nm.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	v.add_child(nm)
	v.add_child(MenuScreen.label("마물 %s / %s" % [reg.families, reg.res], &"LabelDim", 13))
	h.add_child(v)
	var st := MenuScreen.label(region_status(reg.id, String(reg.unlock)), &"LabelHud", 13)
	st.add_theme_color_override(&"font_color", UiTokens.GOOD if open else UiTokens.TEXT_DIM)
	h.add_child(st)
	b.add_child(h)
	b.pressed.connect(func() -> void:
		_region = reg.id
		_refresh())
	return b


func _danger_pips(n: int) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(MenuScreen.label("위험도", &"LabelDim", 11))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 3)
	for i in 5:
		var c := ColorRect.new()
		c.custom_minimum_size = Vector2(9, 16)
		c.color = (UiTokens.DANGER if n >= 4 else (UiTokens.WARN if n >= 3 else UiTokens.TEXT)) if i < n else Color(1, 1, 1, 0.15)
		h.add_child(c)
	v.add_child(h)
	v.add_child(MenuScreen.label(str(n), &"LabelNumber", 18))
	return v


func _fill_loadout() -> void:
	while _mid.get_child_count() > 1:
		var c := _mid.get_child(1)
		_mid.remove_child(c)
		c.queue_free()
	var eq: Dictionary = Armory.list_equipped(Armory.PLAYER_ID)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	var names := ["주무기", "보조", "머리", "몸", "다리", "장신구", "가방"]
	for s in names.size():
		var uid := Armory.get_equipped(Armory.PLAYER_ID, s)
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(112, 70)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
		sb.border_color = UiTokens.LINE
		sb.set_border_width_all(1)
		sb.bg_color = Color(1, 1, 1, 0.04)
		var text := "비어 있음"
		if uid != &"":
			var it: ItemInstance = Armory.get_item(uid)
			var def: ItemDef = Armory.get_def(it.def_id) if it != null else null
			text = def.name if def != null else String(uid)
			if it != null:
				sb.bg_color = Color(UiTokens.rarity_color(int(it.rarity)), 0.3)
		box.add_theme_stylebox_override(&"panel", sb)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var t := MenuScreen.label(text, &"LabelHud" if uid != &"" else &"LabelDim", 13)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(t)
		var cap := MenuScreen.label(names[s], &"LabelDim", 11)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cap)
		box.add_child(v)
		grid.add_child(box)
	_mid.add_child(grid)
	var sum: Dictionary = Armory.get_owner_summary(Armory.PLAYER_ID)
	var sl := MenuScreen.label("방어 %d / 방어구 소음 %+.1fm / 최대 체력 +%d" % [int(sum.get("defense", 0)),
		float(sum.get("armor_noise", 0.0)), int(sum.get("max_hp", 0))], &"LabelDim", 14)
	_mid.add_child(sl)
	var eb := MenuScreen.button("장비 바꾸기", &"ButtonSoft")
	eb.disabled = not UI.has_screen(&"armory")
	eb.pressed.connect(func() -> void: UI.open(&"armory"))
	_mid.add_child(eb)
	var reg: Dictionary = {}
	for r: Dictionary in REGIONS:
		if r.id == _region:
			reg = r
	if not reg.is_empty():
		var card := MenuScreen.cream_card(480)
		var cv: VBoxContainer = card[1]
		cv.add_child(_cream_label("목적지", 13, true))
		cv.add_child(_cream_label(String(reg.name), 22))
		cv.add_child(_cream_label("위험도 %d / 마물 %s" % [reg.danger, reg.families], 15))
		cv.add_child(_cream_label("이런 걸 찾을 수 있어요: %s" % reg.res, 15))
		cv.add_child(_cream_label("해질녘까지 %d분. 해가 지면 마물이 강해집니다." % int(GameState.SORTIE_DUSK_SEC / 60.0), 14, true))
		_mid.add_child(card[0])


func _fill_companions() -> void:
	while _right.get_child_count() > 1:
		var c := _right.get_child(1)
		_right.remove_child(c)
		c.queue_free()
	var any := false
	for id: StringName in Colony.active_resident_ids():
		var r := Colony.get_resident(id)
		var block := LossText.sortie_block(id)  # #125 part 7: Colony.sortie_block_reason
		var ok := int(r.get("health", 0)) == 0 and int(r.get("age_stage", 3)) >= Enums.AgeStage.TEEN and block == ""
		if not ok:
			_companions.erase(id)
		var on := id in _companions
		var b := Button.new()
		b.theme_type_variation = &"ButtonCancel"
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.08) if on else Color(1, 1, 1, 0.03)
		box.border_color = UiTokens.ACCENT if on else Color(1, 1, 1, 0.12)
		box.set_border_width_all(2 if on else 1)
		box.set_corner_radius_all(UiTokens.SLOT_RADIUS)
		box.content_margin_left = 14
		for s in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
			b.add_theme_stylebox_override(s, box)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var why := ""
		if int(r.get("health", 0)) != 0:
			why = "다침, 아픔"
		elif int(r.get("age_stage", 3)) < Enums.AgeStage.TEEN:
			why = "어려서 못 감"
		elif block != "":
			why = block
		var grief := LossText.grief_tag(r)
		b.text = "%s%s   %s" % ["✓ " if on else "", String(r.get("name", "")),
			why if why != "" else grief]
		b.tooltip_text = why
		b.add_theme_color_override(&"font_color", UiTokens.TEXT if ok else UiTokens.TEXT_DIM)
		b.custom_minimum_size = Vector2(0, 48)
		b.disabled = not ok
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			if id in _companions:
				_companions.erase(id)
			elif _companions.size() < MAX_COMPANIONS:
				_companions.append(id)
			else:
				_companions = [id]
			_fill_companions())
		_right.add_child(b)
		any = true
	if not any:
		_right.add_child(MenuScreen.label("함께 갈 주민이 없어요. 혼자 출발합니다.", &"LabelDim", 15))
	_add_stranded()
	_right.add_child(MenuScreen.label("기지를 비우는 동안", &"LabelSection", 16))
	var ch: Dictionary = RaidRules.raid_chance(Enums.RaidTime.DAY, Colony.threat)
	var pct := roundi(float(ch.get("chance", 0.0)) * 100.0)
	var risk := MenuScreen.label("낮 습격 확률 %d%% / 위협도 %s %d" % [pct, BaseHud.ThreatGauge.zone_name(Colony.threat),
		Colony.threat], &"LabelHud", 15)
	risk.add_theme_color_override(&"font_color", UiTokens.WARN if pct > 0 else UiTokens.TEXT)
	_right.add_child(risk)
	_right.add_child(MenuScreen.label("소문", &"LabelSection", 16))
	# 소문 = what the active quests say (Quests, Lane A), not a fixed line.
	var lines: PackedStringArray = []
	for q: Dictionary in Quests.active_quests():
		for o: Dictionary in q["objectives"]:
			if not bool(o["done"]):
				lines.append("%s: %s" % [String(q["title"]), String(o["text"])])
				break
	if lines.is_empty():
		lines.append("오늘은 들어온 소문이 없어요.")
	var rumor := MenuScreen.label("
".join(lines.slice(0, 3)), &"LabelDim", 14)
	rumor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right.add_child(rumor)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(sp)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var cancel := MenuScreen.button("취소", &"ButtonCancel")
	cancel.pressed.connect(close)
	row.add_child(cancel)
	_go = MenuScreen.button("출격", &"ButtonPrimary")
	_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_go.disabled = _region == &""
	_go.pressed.connect(_depart)
	row.add_child(_go)
	_right.add_child(row)


## #125 part 3: residents left in the field — where, and how long until they go missing.
func _add_stranded() -> void:
	var rows := LossText.absent_rows().filter(func(a: Dictionary) -> bool: return a.kind == &"stranded")
	if rows.is_empty():
		return
	_right.add_child(MenuScreen.label("필드에 남은 사람", &"LabelSection", 16))
	for a: Dictionary in rows:
		var l := MenuScreen.label("%s   %s" % [a.name, a.text], &"LabelHud", 15)
		l.add_theme_color_override(&"font_color", UiTokens.WARN)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_right.add_child(l)


func loadout() -> Dictionary:
	return {"region_id": _region, "companions": _companions.duplicate(), "gear": {}}


func _depart() -> void:
	if _region == &"":
		return
	SceneRouter.go_to_field(loadout())


func _cream_label(t: String, s: int, dim := false) -> Label:
	var l := MenuScreen.label(t, &"LabelOnCreamDim" if dim else &"LabelOnCream", s)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept"):
		# Mark handled first: departing closes this screen, so get_viewport() is null afterwards.
		get_viewport().set_input_as_handled()
		_depart()
