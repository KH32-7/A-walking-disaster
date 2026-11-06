class_name BuildScreen
extends MenuScreen
## Build panel (D-06) + 개간 · 수리·레벨업 · 접근성 보기 (issue #125 part 6). Owner: Lane D.
## Design 09 "건물 목록"·"구역과 개간", 07 "참여 조건", 14 "건설 모드", UI_RULES §7 "포함 시설".
##
## Four views, picked by the text tabs at the top (or `UI.open(&"build", {"mode": &"access"})`):
##   build  — BaseDB buildings by category with cost and Colony.can_build() reasons. "배치하기" emits
##            UI.build_requested(def_id); Lane C runs the grid placement and calls Colony.place_building().
##   clear  — zones: Colony.can_clear() reasons → start_clearing(), clear_progress_of(), then 건설 주민
##            (assign_job(id, &"construction", zone_id)).
##   repair — completed buildings: can_repair() → start_repair() → 건설 주민, can_upgrade() → upgrade_building().
##   access — Colony.access_map(): per zone 이동·언어 met (check box shape + words) and `missing`,
##            plus hearing_alarm / care / interpreter_radio.
## Selection is by list (the base map's own markers stay Lane C's). This screen computes no rules:
## every yes/no, reason and cost comes from Colony.
##
## 새로 짓기 재설계 (ui/_mockups/ui-redesign.html §03, 컬트 오브 더 램 Build 메뉴 + 덕코프 Build 패널):
## the scene behind goes grey, a ①고르기 ②놓기 ③짓기 strip sits on top, buildings are picture cards
## (BuildingArt shows the footprint) in display groups, and 추천 splits them into "정착지에 필요해요 /
## 지금 지을 수 있어요 / 곧 열려요" under the next-tier card (Colony.next_tier_status()).
## ③주민이 짓기: mode &"site" (BuildPlaceHud opens it after placing) shows only the cream card over the
## live base: progress, 건설 주민 보내기/빼기 (Colony.assign_job construction), 현장 옮기기.

const CATEGORY_NAMES := ["주거", "생산", "가공", "생활", "제작", "포함", "저장", "군사", "특수", "설비", "방어"]
## Display groups for the build tabs: [key (= _cat value), name, icon, categories]. -1 = 추천.
## Data categories stay as they are; only the screen folds 11 into 6.
const GROUPS := [
	[-1, "추천", &"star", []],
	[BuildingDef.Category.HOUSING, "살림", &"home", [BuildingDef.Category.HOUSING, BuildingDef.Category.LIVING]],
	[BuildingDef.Category.PRODUCTION, "생산", &"sprout", [BuildingDef.Category.PRODUCTION, BuildingDef.Category.PROCESSING]],
	[BuildingDef.Category.CRAFTING, "제작", &"anvil", [BuildingDef.Category.CRAFTING]],
	[BuildingDef.Category.INCLUSION, "포용", &"access", [BuildingDef.Category.INCLUSION]],
	[BuildingDef.Category.STORAGE, "보관, 설비", &"box", [BuildingDef.Category.STORAGE, BuildingDef.Category.UTILITY, BuildingDef.Category.SPECIAL]],
	[BuildingDef.Category.DEFENSE, "방어", &"shield", [BuildingDef.Category.DEFENSE, BuildingDef.Category.MILITARY]],
]
## Card tint per group key (display only).
const GROUP_COLORS := {
	BuildingDef.Category.HOUSING: Color("c9a87a"), BuildingDef.Category.PRODUCTION: Color("8fa35a"), BuildingDef.Category.CRAFTING: Color("6f8fa8"),
	BuildingDef.Category.INCLUSION: Color("4fa9ae"), BuildingDef.Category.STORAGE: Color("b59b6e"), BuildingDef.Category.DEFENSE: Color("8c8c92"),
}
const CARD_SIZE := Vector2(172, 222)
const SOON_MAX := 12
const STEPS := ["건물 고르기", "놓을 곳 정하기", "주민이 짓기"]
## Shortfall reason Colony.can_build() gives when only the cost is missing.
const REASON_COST := "자원 부족"
const MODES := [[&"build", "새로 짓기"], [&"clear", "개간"], [&"repair", "수리, 레벨업"], [&"access", "접근성 보기"]]
const MODE_TITLES := {&"build": "건물", &"clear": "구역", &"repair": "지은 건물", &"access": "구역별 참여 조건"}
## ZoneDef.mobility_access → words (07 "참여 조건": 이동).
const MOBILITY_KIND := {"open": "평지", "ramp": "경사로가 있어야 들어감", "elevator": "위층 / 승강기가 있어야 올라감"}
const WORKER_LIST_H := 236.0
## Enums.BaseTier → words (Colony uses the same names in its tier-up notice).
const TIER_NAMES := ["캐프", "정착지", "요새"]

var _mode: StringName = &"build"
var _cat := -1
var _sel: StringName = &""
var _sel_zone: StringName = &""
var _sel_uid: StringName = &""
## Runs the card's main action on Enter (empty when the card has none or it is blocked).
var _primary := Callable()
var _modes: HBoxContainer
var _tabs: HBoxContainer
var _list: VBoxContainer
var _detail: VBoxContainer
var _count: Label
var _list_title: Label
var _steps: StepStrip
var _left: Control
var _row: HBoxContainer
var _blur0 := 2.6
## Build ids in the order the cards are shown (← → moves through it).
var _order: Array[StringName] = []


func _init() -> void:
	title_text = "건설"
	subtitle_text = "기지"
	footer_keys = [["Esc", "뒤로"], ["← →", "고르기"], ["Q E", "분류"], ["Enter", "실행"]]


## args: mode (&"build"|&"clear"|&"repair"|&"access"|&"site"), zone (zone id), uid (building uid),
## select (building def id to pick in the build list).
func open_with(args: Dictionary) -> void:
	_mode = StringName(args.get("mode", _mode))
	if args.has("select"):
		_sel = StringName(args["select"])
	if args.has("zone"):
		_sel_zone = StringName(args["zone"])
	if args.has("uid"):
		_sel_uid = StringName(args["uid"])
	if args.has("def"):  # #125: "가족 숙소 짓기 ›" links from the resident screens open on that building
		_mode = &"build"
		_sel = StringName(args["def"])
		var d := BaseDB.get_building(_sel)
		_cat = group_of(int(d.category)) if d != null else -1
	if _list != null:
		_refresh()


func _build_body(b: Control) -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override(&"separation", 12)
	b.add_child(col)
	_modes = HBoxContainer.new()
	_modes.add_theme_constant_override(&"separation", 10)
	col.add_child(_modes)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", 24)
	col.add_child(row)
	_row = row
	var left := MenuScreen.panel("건물", "", Vector2(980, 0))
	_left = left[0]
	(left[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	(left[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left[0])
	_list_title = (left[2] as HBoxContainer).get_child(0)
	_count = (left[2] as HBoxContainer).get_child(1)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override(&"separation", 8)
	(left[1] as VBoxContainer).add_child(_tabs)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	(left[1] as VBoxContainer).add_child(sc)
	var card := MenuScreen.cream_card(560)
	(card[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(card[0])
	_detail = card[1]
	_build_steps()
	# 컬트 오브 더 램: the base goes grey behind the build menu so the cards stand out.
	var mat := backdrop.material as ShaderMaterial
	if mat != null:
		var lod: Variant = mat.get_shader_parameter(&"blur_lod")
		_blur0 = float(lod) if lod != null else 2.6
	Colony.buildings_changed.connect(_on_colony_changed)
	_refresh()


func _on_colony_changed() -> void:
	if is_inside_tree():
		_refresh()


func set_mode(mode: StringName) -> void:
	_mode = mode
	_refresh()


func _refresh() -> void:
	_build_modes()
	_tabs.visible = _mode == &"build"
	_steps.visible = _mode == &"build" or _mode == &"site"
	_steps.set_current(3 if _mode == &"site" else 1)
	var site := _mode == &"site"
	_modes.visible = not site
	_left.visible = not site
	_row.alignment = BoxContainer.ALIGNMENT_END if site else BoxContainer.ALIGNMENT_BEGIN
	_set_backdrop(site)
	_list_title.text = MODE_TITLES.get(_mode, "건물")
	_primary = Callable()
	match _mode:
		&"site":
			_show_site()
		&"clear":
			_fill_clear()
		&"repair":
			_fill_repair()
		&"access":
			_fill_access()
		_:
			_build_tabs()
			_fill()


func _build_modes() -> void:
	MenuScreen.clear(_modes)
	for m: Array in MODES:
		var t := MenuScreen.button(String(m[1]), &"TabText")
		t.toggle_mode = true
		t.button_pressed = _mode == m[0]
		t.focus_mode = Control.FOCUS_NONE
		t.pressed.connect(set_mode.bind(m[0]))
		_modes.add_child(t)


# ---------------- 새로 짓기 (D-06, 재설계) ----------------

## ① 건물 고르기 ② 놓을 곳 정하기 ③ 주민이 짓기 — on top while choosing (①) and on the site card (③).
## ② is BuildPlaceHud over the base map.
func _build_steps() -> void:
	_steps = StepStrip.new(STEPS, 1)
	add_child(_steps)
	_steps.place_top_center()


## 고르기: the base goes grey and blurred (컬트 오브 더 램). 현장 카드: the live base stays in view.
func _set_backdrop(live: bool) -> void:
	var mat := backdrop.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter(&"saturation", 1.0 if live else 0.12)
	mat.set_shader_parameter(&"blur_lod", 0.0 if live else _blur0)
	mat.set_shader_parameter(&"tint", Color(0.04, 0.05, 0.08, 0.08 if live else 0.5))


# ---------------- ③ 주민이 짓기: 건설 현장 카드 ----------------

func _show_site() -> void:
	MenuScreen.clear(_detail)
	var b := Colony.get_building(_sel_uid)
	var def := BaseDB.get_building(b.get("def_id", &""))
	if b.is_empty() or def == null:
		_detail.add_child(MenuScreen.label("건설 현장이 없어요.", &"LabelOnCreamDim", 15))
		_action("닫기", true, close)
		return
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override(&"separation", 10)
	tags.add_child(_cream_tag("건설 현장", &"hammer"))
	tags.add_child(_cream_tag("%s / %d×%d칸" % [_zone_name(b["zone_id"]), maxi(def.size.x, 1), maxi(def.size.y, 1)]))
	_detail.add_child(tags)
	_detail.add_child(_title(def.display_name))
	var need := def.build_work_needed()
	var prog := int(b["progress"])
	if b["completed"]:
		_detail.add_child(_state_line(true, "다 지었어요. 이제 일손을 배정하면 일을 시작해요."))
		_action("닫기", true, close)
		return
	var desc := MenuScreen.label("일손을 보내야 지어져요. 보낸 주민은 다 지을 때까지 원래 일을 쉬어요.", &"LabelOnCream", 16)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(520, 0)
	_detail.add_child(desc)
	var ph := HBoxContainer.new()
	var pl := MenuScreen.label("진행 %d / %d" % [prog, need], &"LabelOnCream", 16)
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pl)
	ph.add_child(MenuScreen.label("일손 %d명" % (b["workers"] as Array).size(), &"LabelOnCreamDim", 14))
	_detail.add_child(ph)
	_detail.add_child(_cream_bar(_ratio(prog, need), UiTokens.TEXT_ON_CREAM))
	var how := MenuScreen.label("주민 한 명이 하루에 %d쯤 지어요(힘이 세면 더). 기지에 머무르면 하루 +%d." % [
		roundi(WorkRules.build_progress()), WorkRules.stay_build_progress()], &"LabelOnCreamDim", 14)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(520, 0)
	_detail.add_child(how)
	_worker_section(_sel_uid)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override(&"separation", 10)
	var mv := MenuScreen.button("현장 옮기기", &"ButtonCancel")
	mv.pressed.connect(func() -> void:
		var uid := _sel_uid
		close()
		UI.build_move_requested.emit(uid))
	foot.add_child(mv)
	var go := MenuScreen.button("이대로 짓기", &"ButtonPrimary")
	go.pressed.connect(close)
	foot.add_child(go)
	_detail.add_child(foot)
	_primary = close

func _build_tabs() -> void:
	MenuScreen.clear(_tabs)
	for g: Array in GROUPS:
		if int(g[0]) >= 0 and _group_defs(int(g[0])).is_empty():
			continue
		var t := Button.new()
		t.toggle_mode = true
		t.button_pressed = _cat == int(g[0])
		t.focus_mode = Control.FOCUS_NONE
		t.custom_minimum_size = Vector2(0, 46)
		for s: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
			var on := t.button_pressed or s == &"pressed" or s == &"hover_pressed"
			var box := StyleBoxFlat.new()
			box.bg_color = Color(UiTokens.TAB_GLOW, 0.22) if on else Color(1, 1, 1, 0.1 if s == &"hover" else 0.05)
			box.border_color = Color(UiTokens.TAB_GLOW, 0.75)
			box.set_border_width_all(2 if on else 0)
			box.set_corner_radius_all(99)
			t.add_theme_stylebox_override(s, box)
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(LineIcon.new(g[2], 20, UiTokens.TEXT if t.button_pressed else UiTokens.TEXT_DIM))
		var l := MenuScreen.label(String(g[1]), &"LabelHud", 17)
		l.add_theme_color_override(&"font_color", UiTokens.TEXT if t.button_pressed else UiTokens.TEXT_DIM)
		h.add_child(l)
		t.add_child(h)
		t.custom_minimum_size.x = 44 + 8 + l.get_minimum_size().x + 36
		t.pressed.connect(_set_cat.bind(int(g[0])))
		_tabs.add_child(t)


func _set_cat(c: int) -> void:
	_cat = c
	_build_tabs()
	_fill()


## Display group key for a data category (GROUPS). Unknown → its own value.
static func group_of(category: int) -> int:
	for g: Array in GROUPS:
		if category in g[3]:
			return int(g[0])
	return category


static func group_name(category: int) -> String:
	var key := group_of(category)
	for g: Array in GROUPS:
		if int(g[0]) == key:
			return String(g[1])
	return CATEGORY_NAMES[category]


static func group_color(category: int) -> Color:
	return GROUP_COLORS.get(group_of(category), Color("9a7ac4"))


## Buildings the build list can offer (not prebuilt) in a display group, sorted: can build first.
func _group_defs(key: int) -> Array:
	var out := []
	for def: BuildingDef in BaseDB.buildings().values():
		if def.prebuilt or def.story_only:
			continue
		if key >= 0 and group_of(int(def.category)) != key:
			continue
		out.append(def)
	out.sort_custom(_by_ready)
	return out


## Can build first, then tab order (살림 → 생산 → … → 방어), then name.
func _by_ready(a: BuildingDef, b: BuildingDef) -> bool:
	var oa := bool(Colony.can_build(a.id).ok)
	var ob := bool(Colony.can_build(b.id).ok)
	if oa != ob:
		return oa
	var ga := _group_rank(int(a.category))
	var gb := _group_rank(int(b.category))
	return ga < gb if ga != gb else a.display_name < b.display_name


static func _group_rank(category: int) -> int:
	var key := group_of(category)
	for i in GROUPS.size():
		if int(GROUPS[i][0]) == key:
			return i
	return GROUPS.size()


## Kept for callers that want the flat list of the current tab.
func _defs() -> Array:
	return _group_defs(_cat)


## Building ids the next base tier asks for (TierRules data, read for display).
func _goal_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var status := Colony.next_tier_status()
	var next := int(status.get("tier", -1))
	if next < 0 or not TierRules.REQUIREMENTS.has(next):
		return out
	for id: StringName in TierRules.REQUIREMENTS[next]["buildings"]:
		if BaseDB.get_building(id) != null:
			out.append(id)
	return out


func _fill() -> void:
	MenuScreen.clear(_list)
	_order.clear()
	var defs := _group_defs(_cat)
	var ok_n := 0
	for def: BuildingDef in defs:
		if Colony.can_build(def.id).ok:
			ok_n += 1
	_count.text = "지을 수 있음 %d / %d" % [ok_n, defs.size()]
	_list_title.text = "건물" if _cat < 0 else group_name(_cat)
	_list.add_child(_tier_card())
	if _cat < 0:
		_fill_recommended(defs)
	else:
		_list.add_child(_card_section(group_name(_cat), "%d" % defs.size(), defs))
	if not _sel in _order and not _order.is_empty():
		# Nothing picked yet (or it left this tab): pick the first card and draw again so it is lit.
		_sel = _order[0]
		_fill()
		return
	_show_detail()


## 추천: 정착지에 필요해요 · 지금 지을 수 있어요 side by side, then 곧 열려요.
## Buildings 추천 puts first while their condition holds and they are not built (의무실 after the doctor).
const URGENT_IDS: Array[StringName] = [&"infirmary"]


func _fill_recommended(defs: Array) -> void:
	var goal_ids := _goal_ids()
	# 의무실 first once the doctor is here and it is not built yet (사용자 요청 2026-11-06).
	var urgent := []
	for def: BuildingDef in defs:
		if def.id in URGENT_IDS and Colony.buildings.values().all(func(b: Dictionary) -> bool: return b["def_id"] != def.id) 				and not (Colony.can_build(def.id).reasons as Array).any(func(r: String) -> bool: return "전직" in r):
			urgent.append(def)
	var goal := []
	var now := []
	var soon := []
	for def: BuildingDef in defs:
		if def in urgent:
			continue
		if def.id in goal_ids:
			goal.append(def)
		elif Colony.can_build(def.id).ok:
			now.append(def)
		else:
			soon.append(def)
	soon.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool:
		var ra := (Colony.can_build(a.id).reasons as Array).size()
		var rb := (Colony.can_build(b.id).reasons as Array).size()
		return ra < rb if ra != rb else a.display_name < b.display_name)
	soon = soon.slice(0, SOON_MAX)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 28)
	if not urgent.is_empty():
		var us := _card_section("의사가 왔어요", "지금 지어요", urgent)
		us.custom_minimum_size.x = urgent.size() * (CARD_SIZE.x + 14)
		row.add_child(us)
	if not goal.is_empty():
		var built := 0
		for def: BuildingDef in goal:
			if not Colony.working_building_ids(def.id).is_empty():
				built += 1
		var gs := _card_section("정착지에 필요해요", "%d / %d" % [built, goal.size()], goal, true)
		gs.custom_minimum_size.x = goal.size() * (CARD_SIZE.x + 14)
		row.add_child(gs)
	var ns := _card_section("지금 지을 수 있어요", "%d" % now.size(), now)
	ns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ns)
	_list.add_child(row)
	if not soon.is_empty():
		_list.add_child(_card_section("곧 열려요", "조건을 채우면 열려요", soon))


func _card_section(title: String, count: String, defs: Array, goal := false) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	var h := HBoxContainer.new()
	var t := MenuScreen.label(title, &"LabelSection", 17)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(MenuScreen.label(count, &"LabelDim", 14))
	v.add_child(h)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 14)
	flow.add_theme_constant_override(&"v_separation", 14)
	v.add_child(flow)
	if defs.is_empty():
		flow.add_child(MenuScreen.label("지금은 없어요", &"LabelDim", 14))
	for def: BuildingDef in defs:
		flow.add_child(_card(def, Colony.can_build(def.id), goal))
		_order.append(def.id)
	return v


## Next tier card (컬트 오브 더 램 잠금 마름모 "1/4"): what the next tier still needs, in words.
func _tier_card() -> Control:
	var status := Colony.next_tier_status()
	var next := int(status.get("tier", -1))
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.INFO, 0.12)
	sb.border_color = Color(UiTokens.INFO, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	sb.content_margin_left = 14
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override(&"panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 14)
	p.add_child(h)
	if next < 0:
		h.add_child(CheckMark.new(true))
		h.add_child(MenuScreen.label(KoreanText.fix("기지가 %s(이)에요. 더 오를 단계가 없어요." % TIER_NAMES[Colony.tier]), &"LabelHud", 16))
		return p
	var missing: Array = status.get("missing", [])
	var total := _tier_need_count(next)
	h.add_child(TierDiamond.new(maxi(total - missing.size(), 0), total))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override(&"separation", -1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(MenuScreen.label("다음 기지 단계 / %s" % TIER_NAMES[next], &"LabelSection", 17))
	tv.add_child(MenuScreen.label("시설을 Lv%d까지 올릴 수 있어요" % TierRules.level_cap(next), &"LabelDim", 13))
	h.add_child(tv)
	var needs := HFlowContainer.new()
	needs.add_theme_constant_override(&"h_separation", 16)
	needs.alignment = FlowContainer.ALIGNMENT_END
	needs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if missing.is_empty():
		needs.add_child(MenuScreen.label("조건을 다 채웠어요 / 오늘 저녁에 올라가요", &"LabelHud", 14))
	for m: String in missing:
		var mh := HBoxContainer.new()
		mh.add_theme_constant_override(&"separation", 5)
		mh.add_child(CheckMark.new(false, false))
		mh.add_child(MenuScreen.label(m, &"LabelHud", 14))
		needs.add_child(mh)
	h.add_child(needs)
	return p


## How many conditions the next tier has (population + buildings + zones + generator), for "n / total".
func _tier_need_count(next: int) -> int:
	var req: Dictionary = TierRules.REQUIREMENTS.get(next, {})
	if req.is_empty():
		return 0
	return 1 + (req["buildings"] as Dictionary).size() + (req["zones"] as Array).size() + (1 if req["powered_generator"] else 0)


## Only the cost blocks it (the card shows the shortfall in red, not a lock).
func _only_cost(check: Dictionary) -> bool:
	for r: String in check.reasons:
		if r != REASON_COST:
			return false
	return not check.ok


## "나무 6 부족" for the first resource that is short (display arithmetic on Colony's own cost).
func _short_text(def: BuildingDef) -> String:
	var cost := def.cost_for_level(1)
	for id: StringName in cost:
		var lack := int(cost[id]) - Economy.get_amount(id)
		if lack > 0:
			return "%s %d 부족" % [MenuScreen.resource_name(id), lack]
	return REASON_COST


func _card(def: BuildingDef, check: Dictionary, goal: bool) -> Control:
	var sel := def.id == _sel
	var locked: bool = not check.ok and not _only_cost(check)
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = def.description
	for s: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.09, 0.1, 0.13, 0.8) if s != &"hover" else Color(0.13, 0.14, 0.18, 0.85)
		box.border_color = UiTokens.ACCENT if sel else UiTokens.LINE
		box.set_border_width_all(3 if sel else 1)
		box.set_corner_radius_all(12)
		if sel:
			box.shadow_color = Color(UiTokens.ACCENT, 0.22)
			box.shadow_size = 8
		b.add_theme_stylebox_override(s, box)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override(&"separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	# picture
	var art_box := Control.new()
	art_box.custom_minimum_size = Vector2(0, 100)
	art_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_box.clip_contents = true
	v.add_child(art_box)
	var glow := ArtGlow.new(group_color(int(def.category)))
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_box.add_child(glow)
	var art := BuildingArt.for_def(def, group_color(int(def.category)))
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_top = 14
	art.offset_bottom = -4
	art.dim = locked
	art_box.add_child(art)
	BuildingThumbs.show_on(art_box, def.id, art)  # real model picture once it is rendered
	var cat := _corner_chip(LineIcon.new(group_icon(int(def.category)), 15))
	cat.position = Vector2(8, 8)
	art_box.add_child(cat)
	var sz := _corner_chip(MenuScreen.label("%d×%d" % [maxi(def.size.x, 1), maxi(def.size.y, 1)], &"LabelNumber", 13))
	art_box.add_child(sz)
	sz.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	sz.position += Vector2(-8, 8)
	if locked:
		var lk := LockBadge.new()
		art_box.add_child(lk)
		lk.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	if goal:
		var g := _flag_chip()
		art_box.add_child(g)
		g.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
		g.position += Vector2(8, -6)
	# name
	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 12)
	pad.add_theme_constant_override(&"margin_right", 10)
	pad.add_theme_constant_override(&"margin_bottom", 12)  # keeps the 상태 줄 off the card edge
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(pad)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override(&"separation", 10)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(inner)
	var nm := MenuScreen.label(def.display_name, &"LabelSection", 18)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if locked:
		nm.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	inner.add_child(nm)
	var cost := HFlowContainer.new()
	cost.add_theme_constant_override(&"h_separation", 5)
	cost.add_theme_constant_override(&"v_separation", 8)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c1 := def.cost_for_level(1)
	for id: StringName in c1:
		cost.add_child(_cost_chip(id, int(c1[id]), Economy.get_amount(id) < int(c1[id]), false))
	if c1.is_empty():
		cost.add_child(MenuScreen.label("재료 없음", &"LabelDim", 13))
	inner.add_child(cost)
	# state (shape + words)
	var st := HBoxContainer.new()
	st.add_theme_constant_override(&"separation", 5)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st.size_flags_vertical = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	var col := UiTokens.GOOD
	var kind := &"check"
	var text := "지을 수 있음"
	if locked:
		col = UiTokens.TEXT_DIM
		kind = &"lock"
		text = reason_text(_first_block(check))
	elif not check.ok:
		col = Color("ff8a7a")
		kind = &"warn"
		text = _short_text(def)
	st.add_child(LineIcon.new(kind, 15, col))
	var sl := MenuScreen.label(text, &"LabelHud", 13)
	sl.add_theme_color_override(&"font_color", col)
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.clip_text = true
	st.add_child(sl)
	inner.add_child(st)
	b.pressed.connect(func() -> void:
		# First click picks the card; a click on the picked card goes on to ②놓기 (same as Enter).
		if _sel == def.id and bool(Colony.can_build(def.id).ok):
			_place()
			return
		_sel = def.id
		_fill())
	return b


static func group_icon(category: int) -> StringName:
	var key := group_of(category)
	for g: Array in GROUPS:
		if int(g[0]) == key:
			return g[2]
	return &"dot"


## First reason that is not the cost (what keeps the card locked).
func _first_block(check: Dictionary) -> String:
	for r: String in check.reasons:
		if r != REASON_COST:
			return r
	return REASON_COST


func _corner_chip(child: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override(&"panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(child)
	return p


func _flag_chip() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTokens.INFO
	sb.set_corner_radius_all(99)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override(&"panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(LineIcon.new(&"flag", 13, UiTokens.TEXT_ON_CREAM))
	var l := MenuScreen.label("정착지", &"LabelOnCream", 12)
	h.add_child(l)
	p.add_child(h)
	return p


## Resource chip: icon + amount (+ " / 보유 n" on the cream card). Short = red tint + red number.
func _cost_chip(id: StringName, need: int, short: bool, on_cream: bool) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	if on_cream:
		sb.bg_color = Color(UiTokens.DANGER, 0.14) if short else Color(0, 0, 0, 0.07)
	else:
		sb.bg_color = Color(UiTokens.DANGER, 0.24) if short else Color(1, 1, 1, 0.08)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6
	sb.content_margin_right = 7
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override(&"panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.tooltip_text = MenuScreen.resource_name(id)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := UiTokens.TEXT_ON_CREAM if on_cream else UiTokens.TEXT
	var red := Color("b3261e") if on_cream else Color("ff9d93")
	h.add_child(LineIcon.for_resource(id, 15 if not on_cream else 17, red if short else ink))
	var n := MenuScreen.label(str(need), &"LabelNumber", 13 if not on_cream else 16)
	n.add_theme_color_override(&"font_color", red if short else ink)
	h.add_child(n)
	if on_cream:
		var have := MenuScreen.label("%s / 보유 %d" % [MenuScreen.resource_name(id), Economy.get_amount(id)], &"LabelOnCreamDim", 13)
		h.add_child(have)
	p.add_child(h)
	return p


func _show_detail() -> void:
	MenuScreen.clear(_detail)
	var def := BaseDB.get_building(_sel)
	if def == null:
		return
	var check: Dictionary = Colony.can_build(def.id)
	var locked: bool = not check.ok and not _only_cost(check)
	# picture band
	var pic := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = UiTokens.CREAM_2
	psb.set_corner_radius_all(10)
	pic.add_theme_stylebox_override(&"panel", psb)
	pic.custom_minimum_size = Vector2(0, 190)
	var pic_in := Control.new()
	pic.add_child(pic_in)
	var art := BuildingArt.for_def(def, group_color(int(def.category)))
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_top = 30
	art.offset_bottom = -12
	art.dim = locked
	pic_in.add_child(art)
	BuildingThumbs.show_on(pic_in, def.id, art)
	var w := maxi(def.size.x, 1)
	var d := maxi(def.size.y, 1)
	var size_tag := _cream_tag("%d×%d칸 / %dm × %dm" % [w, d, w * 2, d * 2])
	size_tag.position = Vector2(12, 12)
	pic_in.add_child(size_tag)
	var count := Colony.working_building_ids(def.id).size()
	var built_tag := _cream_tag("지은 것 %d" % count)
	pic_in.add_child(built_tag)
	built_tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	built_tag.position += Vector2(-12, 12)
	_detail.add_child(pic)
	# tags
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override(&"separation", 10)
	tags.add_child(_cream_tag(group_name(int(def.category)), group_icon(int(def.category))))
	if def.capacity > 0:
		tags.add_child(_cream_tag("일손 %d명" % def.capacity, &"people"))
	if def.category == BuildingDef.Category.INCLUSION:
		var inc := HBoxContainer.new()
		inc.add_theme_constant_override(&"separation", 5)
		inc.add_child(InfoIcon.new(18))
		inc.add_child(MenuScreen.label("포함 시설", &"LabelOnCream", 14))
		tags.add_child(inc)
	_detail.add_child(tags)
	_detail.add_child(_title(def.display_name))
	if def.description != "":
		var desc := MenuScreen.label(def.description, &"LabelOnCream", 16)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(520, 0)
		_detail.add_child(desc)
	_detail.add_child(HSeparator.new())
	# facts: 필요한 것 / 놓는 곳 / 전력 / 소음
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 8)
	grid.add_child(_fact_key("필요한 것"))
	var costs := HFlowContainer.new()
	costs.add_theme_constant_override(&"h_separation", 6)
	costs.add_theme_constant_override(&"v_separation", 8)
	costs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c1 := def.cost_for_level(1)
	for id: StringName in c1:
		costs.add_child(_cost_chip(id, int(c1[id]), Economy.get_amount(id) < int(c1[id]), true))
	if c1.is_empty():
		costs.add_child(MenuScreen.label("없음", &"LabelOnCream", 15))
	grid.add_child(costs)
	if def.note != "":
		grid.add_child(_fact_key("놓는 곳 / 참고"))
		grid.add_child(_fact_val(def.note))
	if def.power_use[0] > 0:
		grid.add_child(_fact_key("전력"))
		grid.add_child(_fact_val("−%d" % def.power_use[0]))
	if def.noise > 0.0:
		grid.add_child(_fact_key("기지 소음"))
		grid.add_child(_fact_val("+%.1f" % def.noise))
	_detail.add_child(grid)
	_reasons(check.reasons.filter(func(r: String) -> bool: return r != REASON_COST))
	# how it gets built (② ③ happen on the map)
	var how := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0, 0, 0, 0.06)
	hsb.set_corner_radius_all(10)
	hsb.content_margin_left = 12
	hsb.content_margin_right = 12
	hsb.content_margin_top = 8
	hsb.content_margin_bottom = 8
	how.add_theme_stylebox_override(&"panel", hsb)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override(&"separation", 2)
	how.add_child(hv)
	hv.add_child(MenuScreen.label("지어지는 과정", &"LabelOnCream", 14))
	var steps := MenuScreen.label("① 놓을 곳 정하기  →  ② 건설 주민 보내기  →  ③ 진행 %d 채우면 완성" % def.build_work_needed(),
		&"LabelOnCreamDim", 14)
	steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(steps)
	_detail.add_child(how)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	var go := MenuScreen.button("놓을 곳 고르기", &"ButtonPrimary")
	go.disabled = not check.ok
	go.pressed.connect(_place)
	foot.add_child(go)
	_detail.add_child(foot)
	if check.ok:
		_primary = _place


func _cream_tag(text: String, icon: StringName = &"") -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.55) if icon == &"" else Color(0, 0, 0, 0.07)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override(&"panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 5)
	if icon != &"":
		h.add_child(LineIcon.new(icon, 15, UiTokens.TEXT_ON_CREAM))
	h.add_child(MenuScreen.label(text, &"LabelOnCream", 13))
	p.add_child(h)
	return p


func _fact_key(text: String) -> Label:
	var l := MenuScreen.label(text, &"LabelOnCreamDim", 14)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _fact_val(text: String) -> Label:
	var l := MenuScreen.label(text, &"LabelOnCream", 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _move_sel(step: int) -> void:
	if _order.is_empty():
		return
	var i := _order.find(_sel)
	_sel = _order[clampi(i + step, 0, _order.size() - 1)] if i >= 0 else _order[0]
	_fill()


func _step_group(step: int) -> void:
	var keys: Array[int] = []
	for g: Array in GROUPS:
		if int(g[0]) < 0 or not _group_defs(int(g[0])).is_empty():
			keys.append(int(g[0]))
	var i := keys.find(_cat)
	_set_cat(keys[posmod(i + step, keys.size())])

func _place() -> void:
	if _sel == &"" or not bool(Colony.can_build(_sel).ok):
		return
	UI.build_requested.emit(_sel)
	close()


# ---------------- 개간 (C-10) ----------------

## Zones in display order: being cleared, can start, blocked, done.
func _zones() -> Array:
	var out := []
	for zone_id: StringName in BaseDB.zones():
		out.append(zone_id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ra := _zone_rank(a)
		var rb := _zone_rank(b)
		return ra < rb if ra != rb else BaseDB.get_zone(a).display_name < BaseDB.get_zone(b).display_name)
	return out


func _zone_rank(zone_id: StringName) -> int:
	if Colony.is_zone_cleared(zone_id):
		return 3
	if _clearing(zone_id):
		return 0
	return 1 if bool(Colony.can_clear(zone_id).ok) else 2


## Clearing started: the start cost is paid, work was done, or someone is on it.
func _clearing(zone_id: StringName) -> bool:
	return Colony.clear_started.has(zone_id) or Colony.clear_progress_of(zone_id) > 0 \
		or not _workers_on(zone_id).is_empty()


func _fill_clear() -> void:
	MenuScreen.clear(_list)
	var zones := _zones()
	var done := 0
	for zone_id: StringName in zones:
		if Colony.is_zone_cleared(zone_id):
			done += 1
	_count.text = "개간됨 %d / %d" % [done, zones.size()]
	if (_sel_zone == &"" or BaseDB.get_zone(_sel_zone) == null) and not zones.is_empty():
		_sel_zone = zones[0]
	for zone_id: StringName in zones:
		_list.add_child(_zone_row(zone_id))
	_show_zone()


func _zone_row(zone_id: StringName) -> Control:
	var z := BaseDB.get_zone(zone_id)
	var parts: PackedStringArray = ["%d×%d칸" % [z.size.x, z.size.y], "실내" if z.indoor else "야외"]
	if not z.clear_yield.is_empty():
		parts.append("얻는 것 " + MenuScreen.cost_text(z.clear_yield))
	var st := ""
	var col := UiTokens.TEXT_DIM
	var mid: Control = null
	var blocked := false
	if Colony.is_zone_cleared(zone_id):
		st = "✓ 개간됨"
		col = UiTokens.GOOD
	elif _clearing(zone_id):
		st = "개간 중 %d / %d" % [Colony.clear_progress_of(zone_id), z.clear_work]
		col = UiTokens.INFO
		mid = MenuScreen.bar(_ratio(Colony.clear_progress_of(zone_id), z.clear_work), UiTokens.INFO, 140)
	else:
		var check := Colony.can_clear(zone_id)
		blocked = not check.ok
		st = "개간할 수 있음" if check.ok else "▲ " + reason_text(String((check.reasons as Array)[0]), z.clear_cost)
		col = UiTokens.TEXT if check.ok else UiTokens.TEXT_DIM
	return _list_row(zone_id == _sel_zone, z.display_name, " / ".join(parts), st, col, blocked,
		func() -> void:
			_sel_zone = zone_id
			_fill_clear(), null, mid)


func _show_zone() -> void:
	MenuScreen.clear(_detail)
	var z := BaseDB.get_zone(_sel_zone)
	if z == null:
		return
	_detail.add_child(_tag("구역 / %d×%d칸 / %s" % [z.size.x, z.size.y, "실내" if z.indoor else "야외"]))
	_detail.add_child(_title(z.display_name))
	var cleared := Colony.is_zone_cleared(_sel_zone)
	if cleared:
		_detail.add_child(_state_line(true, "개간 완료: 이 구역에 지을 수 있음"))
		return
	var grid := _grid()
	if z.clear_work > 0:
		_pair(grid, "개간 진행도", "%d / %d" % [Colony.clear_progress_of(_sel_zone), z.clear_work])
	if not z.clear_yield.is_empty():
		_pair(grid, "끝나면 얻는 것", MenuScreen.cost_text(z.clear_yield))
	var started := _clearing(_sel_zone)
	if not z.clear_cost.is_empty():
		if started:
			_pair(grid, "시작 비용", MenuScreen.cost_text(z.clear_cost) + " (냄)")
		else:
			_cost_rows(grid, z.clear_cost)
	_detail.add_child(grid)
	if z.clear_work > 0:
		_detail.add_child(_cream_bar(_ratio(Colony.clear_progress_of(_sel_zone), z.clear_work)))
	var check := Colony.can_clear(_sel_zone)
	_reasons(check.reasons, z.clear_cost)
	if not started:
		_action("개간 시작", check.ok, _start_clearing)
		return
	_detail.add_child(_state_line(false, "개간 중: 건설 주민이 저녁마다 진행도를 올립니다"))
	_worker_section(_sel_zone)


func _start_clearing() -> void:
	if Colony.start_clearing(_sel_zone):
		_refresh()


# ---------------- 수리·레벨업 (C-18, C-10) ----------------

func _buildings() -> Array:
	var out := []
	for uid: StringName in Colony.building_ids():
		out.append(uid)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ra := _building_rank(a)
		var rb := _building_rank(b)
		return ra < rb if ra != rb else _bname(a) < _bname(b))
	return out


func _building_rank(uid: StringName) -> int:
	var b := Colony.get_building(uid)
	if b["damaged"]:
		return 0 if int(b["repair_progress"]) < 0 else 1
	if _wear(uid) != Vector2i(-1, -1):
		return 1
	return 2 if bool(Colony.can_upgrade(uid).ok) else 3


func _bname(uid: StringName) -> String:
	var def := BaseDB.get_building(Colony.get_building(uid).get("def_id", &""))
	return def.display_name if def else String(uid)


## Lost durability of a defense structure that is not damaged: (now, max), or (-1, -1).
func _wear(uid: StringName) -> Vector2i:
	var b := Colony.get_building(uid)
	var def := BaseDB.get_building(b["def_id"])
	if b["damaged"] or def.durability <= 0 or int(b["durability"]) >= def.durability:
		return Vector2i(-1, -1)
	return Vector2i(int(b["durability"]), def.durability)


func _zone_name(zone_id: StringName) -> String:
	var z := BaseDB.get_zone(zone_id)
	return z.display_name if z else "기지"


func _fill_repair() -> void:
	MenuScreen.clear(_list)
	var uids := _buildings()
	var broken := 0
	for uid: StringName in uids:
		if Colony.get_building(uid)["damaged"]:
			broken += 1
	_count.text = "파손 %d / 전체 %d" % [broken, uids.size()]
	if not Colony.get_building(_sel_uid).get("completed", false) and not uids.is_empty():
		_sel_uid = uids[0]
	if uids.is_empty():
		_list.add_child(MenuScreen.label("아직 지은 건물이 없습니다.", &"LabelDim", 16))
	for uid: StringName in uids:
		_list.add_child(_building_row(uid))
	_show_building()


func _building_row(uid: StringName) -> Control:
	var b := Colony.get_building(uid)
	var def := BaseDB.get_building(b["def_id"])
	var sub := "%s / %s" % [CATEGORY_NAMES[int(def.category)], _zone_name(b["zone_id"])]
	var st := ""
	var col := UiTokens.TEXT_DIM
	var mid: Control = null
	var wear := _wear(uid)
	if b["damaged"] and int(b["repair_progress"]) < 0:
		st = "■ 파손 / 멈춤"
		col = UiTokens.DANGER
	elif b["damaged"]:
		var need := Colony.repair_work_needed(uid)
		st = "수리 중 %d / %d" % [int(b["repair_progress"]), need]
		col = UiTokens.WARN
		mid = MenuScreen.bar(_ratio(int(b["repair_progress"]), need), UiTokens.WARN, 140)
	elif wear != Vector2i(-1, -1):
		st = "내구도 %d / %d" % [wear.x, wear.y]
		col = UiTokens.WARN
	elif bool(Colony.can_upgrade(uid).ok):
		st = "↑ Lv%d 올릴 수 있음" % (int(b["level"]) + 1)
		col = UiTokens.GOOD
	else:
		st = "● 작동 중"
	var inclusive := def.category == BuildingDef.Category.INCLUSION
	return _list_row(uid == _sel_uid, "%s  Lv%d" % [def.display_name, int(b["level"])], sub, st, col, false,
		func() -> void:
			_sel_uid = uid
			_fill_repair(), InfoIcon.new(20) if inclusive else null, mid)


func _show_building() -> void:
	MenuScreen.clear(_detail)
	var b := Colony.get_building(_sel_uid)
	if b.is_empty():
		_detail.add_child(MenuScreen.label("고를 건물이 없습니다.", &"LabelOnCreamDim", 15))
		return
	var def := BaseDB.get_building(b["def_id"])
	var level := int(b["level"])
	_detail.add_child(_tag("%s / %s / Lv%d / %d" % [CATEGORY_NAMES[int(def.category)], _zone_name(b["zone_id"]),
		level, BuildingDef.MAX_LEVEL]))
	_detail.add_child(_title(def.display_name))
	if def.category == BuildingDef.Category.INCLUSION:
		_detail.add_child(_inclusion_line("포함 시설"))
	var wear := _wear(_sel_uid)
	if b["damaged"]:
		_section("수리")
		if int(b["repair_progress"]) < 0:
			_detail.add_child(_state_line(false, "파손되어 작동이 멈췄습니다"))
			var check := Colony.can_repair(_sel_uid)
			var grid := _grid()
			_cost_rows(grid, check.cost)
			_detail.add_child(grid)
			_reasons(check.reasons)
			_action("수리 시작", check.ok, _start_repair)
		else:
			var need := Colony.repair_work_needed(_sel_uid)
			var grid := _grid()
			_pair(grid, "수리 진행도", "%d / %d" % [int(b["repair_progress"]), need])
			_detail.add_child(grid)
			_detail.add_child(_cream_bar(_ratio(int(b["repair_progress"]), need), UiTokens.WARN))
			_worker_section(_sel_uid)
		return
	if wear != Vector2i(-1, -1):
		_section("내구도 보수")
		var grid := _grid()
		_pair(grid, "내구도", "%d / %d" % [wear.x, wear.y])
		_detail.add_child(grid)
		_detail.add_child(_cream_bar(_ratio(wear.x, wear.y), UiTokens.WARN))
		_worker_section(_sel_uid)
	_section("레벨업")
	var up := Colony.can_upgrade(_sel_uid)
	if level >= BuildingDef.MAX_LEVEL:
		_detail.add_child(_state_line(true, "최고 레벨 (Lv%d)" % level))
		return
	var ug := _grid()
	_cost_rows(ug, up.cost)
	_detail.add_child(ug)
	_reasons(up.reasons)
	_action("레벨업  Lv%d → Lv%d" % [level, level + 1], up.ok, _upgrade)


func _start_repair() -> void:
	if Colony.start_repair(_sel_uid):
		_refresh()


func _upgrade() -> void:
	if Colony.upgrade_building(_sel_uid):
		_refresh()


# ---------------- 건설 주민 배정 (개간·수리 공용) ----------------

## Active residents on the construction job at `target` (zone id or building uid).
func _workers_on(target: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Colony.active_resident_ids():
		var a: Dictionary = Colony.get_resident(id).get("assignment", {})
		if a.get("job", &"") == WorkRules.CONSTRUCTION_JOB and a.get("building_id", &"") == target:
			out.append(id)
	return out


func _worker_section(target: StringName) -> void:
	var on := _workers_on(target)
	_section("건설 주민  %d명" % on.size())
	var ids := Colony.active_resident_ids()
	var rows := []
	for id in ids:
		var reason := "" if id in on else Colony.job_block_reason(id, WorkRules.CONSTRUCTION_JOB, target)
		rows.append([0 if id in on else (1 if reason == "" else 2), id, reason])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if a[0] != b[0] else String(a[1]) < String(b[1]))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, minf(WORKER_LIST_H, maxf(44.0, rows.size() * 44.0)))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override(&"separation", 8)
	sc.add_child(v)
	if rows.is_empty():
		v.add_child(MenuScreen.label("기지에 주민이 없습니다.", &"LabelOnCreamDim", 14))
	for row: Array in rows:
		v.add_child(_worker_row(row[1], target, row[0] == 0, row[2]))
	_detail.add_child(sc)


func _worker_row(id: StringName, target: StringName, here: bool, reason: String) -> Control:
	var r := Colony.get_resident(id)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	h.custom_minimum_size = Vector2(0, 40)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override(&"separation", -3)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.add_child(MenuScreen.label(ResidentText.full_name(r), &"LabelOnCream", 15))
	var job := Colony.job_of(id)
	var jd := BaseDB.get_job(job) if job != &"" else null
	var now := "여기서 일하는 중"
	if not here:
		now = "지금: " + (jd.display_name if jd else "쉬는 중")
		var at: StringName = r.get("assignment", {}).get("building_id", &"")
		if at != &"" and (BaseDB.get_zone(at) != null or not Colony.get_building(at).is_empty()):
			now += " (%s)" % (_zone_name(at) if BaseDB.get_zone(at) != null else _bname(at))
	nv.add_child(MenuScreen.label(now, &"LabelOnCreamDim", 12))
	h.add_child(nv)
	if here:
		var out := MenuScreen.button("빼기", &"ButtonCancel")
		out.pressed.connect(func() -> void:
			Colony.unassign_job(id)
			_refresh())
		h.add_child(out)
	elif reason == "":
		var put := MenuScreen.button("배정", &"ButtonSoft")
		put.pressed.connect(func() -> void:
			if Colony.assign_job(id, WorkRules.CONSTRUCTION_JOB, target):
				_refresh())
		h.add_child(put)
	else:
		var l := MenuScreen.label("▲ " + reason, &"LabelOnCreamDim", 12)
		l.custom_minimum_size = Vector2(190, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.tooltip_text = reason
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(l)
	return h


# ---------------- 접근성 보기 (C-11) ----------------

func _fill_access() -> void:
	MenuScreen.clear(_list)
	var map := Colony.access_map()
	var zones: Dictionary = map.get("zones", {})
	var full := 0
	for zone_id: StringName in zones:
		if (zones[zone_id].get("missing", []) as Array).is_empty():
			full += 1
	_count.text = "모두 갖춘 구역 %d / %d" % [full, zones.size()]
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 16)
	for c: Array in [["구역", 300], ["이동", 210], ["언어", 210], ["포함 시설", 0]]:
		var l := MenuScreen.label(String(c[0]), &"LabelDim", 14)
		l.custom_minimum_size = Vector2(c[1], 0)
		if int(c[1]) == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)
	var hp := MarginContainer.new()
	hp.add_theme_constant_override(&"margin_left", 16)
	hp.add_theme_constant_override(&"margin_right", 16)
	hp.add_child(head)
	_list.add_child(hp)
	var ids := zones.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var za := BaseDB.get_zone(a)
		var zb := BaseDB.get_zone(b)
		var ca := Colony.is_zone_cleared(a)
		var cb := Colony.is_zone_cleared(b)
		return ca if ca != cb else za.display_name < zb.display_name)
	var facilities := _inclusion_by_zone()
	for zone_id: StringName in ids:
		_list.add_child(_access_row(zone_id, zones[zone_id], facilities.get(zone_id, [])))
	_show_access(map)


## zone_id → names of completed inclusion facilities there (UI_RULES §7: INFO 아이콘 + 글). "" = no zone.
func _inclusion_by_zone() -> Dictionary:
	var out := {}
	for uid in Colony.building_ids():
		var b := Colony.get_building(uid)
		var def := BaseDB.get_building(b["def_id"])
		if def.category != BuildingDef.Category.INCLUSION:
			continue
		var text := def.display_name + (" (파손)" if b["damaged"] else "")
		var list: Array = out.get(b["zone_id"], [])
		list.append(text)
		out[b["zone_id"]] = list
	return out


func _access_row(zone_id: StringName, acc: Dictionary, facilities: Array) -> Control:
	var z := BaseDB.get_zone(zone_id)
	var p := PanelContainer.new()
	var box := _row_box(false)
	p.add_theme_stylebox_override(&"panel", box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	v.add_child(h)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override(&"separation", 2)
	nv.custom_minimum_size = Vector2(300, 0)
	var cleared := Colony.is_zone_cleared(zone_id)
	var nm := MenuScreen.label(z.display_name if z else String(zone_id), &"LabelSection", 18)
	if not cleared:
		nm.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	nv.add_child(nm)
	var kind := String(MOBILITY_KIND.get(z.mobility_access, "")) if z else ""
	nv.add_child(MenuScreen.label(kind + ("" if cleared else " / 개간 전"), &"LabelDim", 13))
	h.add_child(nv)
	var mob := bool(acc.get("mobility", true))
	var lang := bool(acc.get("language", true))
	h.add_child(_met_cell(mob, "갈 수 있음" if mob else "못 들어감", 210))
	h.add_child(_met_cell(lang, "그림 표지판 있음" if lang else "그림 표지판 없음", 210))
	var fac := HBoxContainer.new()
	fac.add_theme_constant_override(&"separation", 8)
	fac.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if facilities.is_empty():
		fac.add_child(MenuScreen.label("-", &"LabelDim", 14))
	else:
		fac.add_child(InfoIcon.new(18))
		var fl := MenuScreen.label(", ".join(PackedStringArray(facilities)), &"LabelHud", 14)
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fac.add_child(fl)
	h.add_child(fac)
	var missing: Array = acc.get("missing", [])
	if not missing.is_empty():
		var ml := MenuScreen.label("▲ 아직 없는 것: " + ", ".join(PackedStringArray(missing)), &"LabelHud", 14)
		ml.add_theme_color_override(&"font_color", UiTokens.WARN)
		v.add_child(ml)
	return p


## Check box (filled + tick = met, empty outline = not yet) plus words, so it never reads by colour.
func _met_cell(met: bool, text: String, w: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	h.custom_minimum_size = Vector2(w, 0)
	h.add_child(CheckMark.new(met, false))
	var l := MenuScreen.label(text, &"LabelHud", 15)
	if not met:
		l.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	h.add_child(l)
	return h


func _show_access(map: Dictionary) -> void:
	MenuScreen.clear(_detail)
	_detail.add_child(_tag("07 참여 조건 / 기지가 아직 갖추지 못한 것"))
	_detail.add_child(_title("기지 전체"))
	var hearing := bool(map.get("hearing_alarm", false))
	_detail.add_child(_state_line(hearing, "청각: 시각 경보(경광등) " + ("켜짐" if hearing else "꺼짐 (전력이 들어온 경광등 필요)")))
	var care: Dictionary = map.get("care", {})
	var guardians := int(care.get("guardians", 0))
	var covered := (care.get("covered", []) as Array).size()
	_detail.add_child(_state_line(covered >= guardians, "돌봄: 자리 %d / 보호자 %d명 중 %d명 맡김" % [
		int(care.get("slots", 0)), guardians, covered]))
	var radio := bool(map.get("interpreter_radio", false))
	_detail.add_child(_state_line(radio, "언어. 통역 무전기 " + ("있음 (무전, 외교 가능)" if radio else "없음")))
	_detail.add_child(HSeparator.new())
	var counts := [0, 0, 0]
	for id in Colony.active_resident_ids():
		var needs: Array = Colony.get_resident(id).get("access_needs", [])
		for i in 3:
			if i in needs:
				counts[i] += 1
	_detail.add_child(MenuScreen.label("참여 조건이 있는 주민  이동 %d / 언어 %d / 청각 %d" % counts, &"LabelOnCream", 15))
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override(&"separation", 8)
	legend.add_child(CheckMark.new(true))
	legend.add_child(MenuScreen.label("갖춤", &"LabelOnCreamDim", 13))
	legend.add_child(CheckMark.new(false))
	legend.add_child(MenuScreen.label("아직 없음", &"LabelOnCreamDim", 13))
	legend.add_child(InfoIcon.new(16))
	legend.add_child(MenuScreen.label("포함 시설", &"LabelOnCreamDim", 13))
	_detail.add_child(legend)
	_action("포함 시설 짓기", true, func() -> void:
		_cat = BuildingDef.Category.INCLUSION
		_sel = &""
		set_mode(&"build"))


# ---------------- small builders ----------------

func _row_box(sel: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.08) if sel else Color(1, 1, 1, 0.03)
	box.border_color = UiTokens.ACCENT if sel else Color(1, 1, 1, 0.12)
	box.set_border_width_all(2 if sel else 1)
	box.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


## One list row: [lead icon] name / sub · [mid] · status (right). Dim name when blocked.
func _list_row(sel: bool, title: String, sub: String, status: String, status_color: Color, dim: bool,
		on_press: Callable, lead: Control = null, mid: Control = null) -> Control:
	var b := Button.new()
	b.theme_type_variation = &"ButtonCancel"
	var box := _row_box(sel)
	for s in [&"normal", &"hover", &"pressed", &"focus"]:
		b.add_theme_stylebox_override(s, box)
	b.custom_minimum_size = Vector2(0, 62)
	b.focus_mode = Control.FOCUS_NONE
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16
	h.offset_right = -16
	h.add_theme_constant_override(&"separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if lead != null:
		h.add_child(lead)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override(&"separation", 2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := MenuScreen.label(title, &"LabelSection", 18)
	if dim:
		nm.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	nv.add_child(nm)
	nv.add_child(MenuScreen.label(sub, &"LabelDim", 13))
	h.add_child(nv)
	if mid != null:
		h.add_child(mid)
	var st := MenuScreen.label(status, &"LabelHud", 14)
	st.add_theme_color_override(&"font_color", status_color)
	st.custom_minimum_size = Vector2(170, 0)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(st)
	b.add_child(h)
	b.pressed.connect(on_press)
	return b


func _tag(text: String) -> Label:
	return MenuScreen.label(text, &"LabelOnCreamDim", 13)


func _title(text: String) -> Label:
	var t := MenuScreen.label(text, &"LabelSection", 24)
	t.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	return t


func _section(text: String) -> void:
	var l := MenuScreen.label(text, &"LabelSection", 17)
	l.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	_detail.add_child(l)


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 6)
	return grid


func _pair(grid: GridContainer, key: String, value: String) -> void:
	grid.add_child(MenuScreen.label(key, &"LabelOnCream", 15))
	grid.add_child(MenuScreen.label(value, &"LabelOnCream", 15))


## "목재판 | 10 / 보유 4  ▲ 부족" rows (shortfall in words + colour).
func _cost_rows(grid: GridContainer, cost: Dictionary) -> void:
	for id: StringName in cost:
		var have := Economy.get_amount(id)
		var short := have < int(cost[id])
		grid.add_child(MenuScreen.label(MenuScreen.resource_name(id), &"LabelOnCream", 15))
		var v := MenuScreen.label("%d / 보유 %d%s" % [int(cost[id]), have, "  ▲ 부족" if short else ""], &"LabelOnCream", 15)
		if short:
			v.add_theme_color_override(&"font_color", UiTokens.DANGER)
		grid.add_child(v)


## Colony reason strings with enum keys / raw cost dictionaries put into words. Display only:
## the reason itself (and whether it blocks) is still Colony's.
static func reason_text(r: String, cost: Dictionary = {}) -> String:
	for i in TIER_NAMES.size():
		r = r.replace("기지 단계 %s 필요" % Enums.BaseTier.keys()[i], "기지 단계 '%s' 필요" % TIER_NAMES[i])
	if r.begins_with("시작 비용 부족") and not cost.is_empty():
		r = "시작 비용 부족: " + MenuScreen.cost_text(cost)
	return r


func _reasons(reasons: Array, cost: Dictionary = {}) -> void:
	for raw: String in reasons:
		if raw == "이미 개간됨":
			continue
		var l := MenuScreen.label("▲  " + reason_text(raw, cost), &"LabelOnCream", 14)
		l.add_theme_color_override(&"font_color", UiTokens.DANGER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(l)


func _state_line(met: bool, text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	h.add_child(CheckMark.new(met))
	var l := MenuScreen.label(text, &"LabelOnCream", 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	return h


func _inclusion_line(text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	h.add_child(InfoIcon.new(18))
	h.add_child(MenuScreen.label(text, &"LabelOnCream", 14))
	return h


func _cream_bar(value: float, color := UiTokens.INFO) -> SegBar:
	var bar := MenuScreen.bar(value, color, 0, 8)
	bar.empty_color = Color(0, 0, 0, 0.12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return bar


func _action(text: String, enabled: bool, fn: Callable) -> Button:
	var go := MenuScreen.button(text, &"ButtonPrimary")
	go.disabled = not enabled
	go.pressed.connect(fn)
	_detail.add_child(go)
	if enabled:
		_primary = fn
	return go


func _ratio(v: int, total: int) -> float:
	return clampf(float(v) / float(total), 0.0, 1.0) if total > 0 else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept"):
		# Mark it handled first: _place() / the action may close this screen (no viewport after that).
		get_viewport().set_input_as_handled()
		if _mode == &"build":
			_place()
		elif _primary.is_valid():
			_primary.call()
		return
	if _mode != &"build":
		return
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right"):
		_move_sel(-1 if event.is_action_pressed(&"ui_left") else 1)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_Q or k == KEY_E:
			_step_group(-1 if k == KEY_Q else 1)
			get_viewport().set_input_as_handled()


## Lock diamond with "met / total" (컬트 오브 더 램 신성한 영감의 잠금 마름모).
class TierDiamond extends Control:
	var met := 0
	var total := 0

	func _init(m: int, t: int) -> void:
		met = m
		total = t
		custom_minimum_size = Vector2(46, 46)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := 21.0
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(pts, Color(UiTokens.INK, 0.9))
		pts.append(pts[0])
		draw_polyline(pts, UiTokens.INFO, 2.0, true)
		var font := get_theme_default_font()
		var s := "%d/%d" % [met, total]
		var fs := 13
		var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - tw * 0.5, c.y + fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTokens.TEXT)


## Soft group-colour glow behind the card picture.
class ArtGlow extends Control:
	var col := Color.WHITE

	func _init(c: Color) -> void:
		col = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.7)
		for i in 6:
			var k := 1.0 - i / 6.0
			draw_circle(c, size.x * 0.55 * k, Color(col, 0.06), true, -1.0, true)


## Dark circle with a lock, over a locked card's picture.
class LockBadge extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(36, 36)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		var ic := LineIcon.new(&"lock", 18)
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(ic)

	func _draw() -> void:
		draw_circle(size * 0.5, 17.0, Color(UiTokens.INK, 0.85), true, -1.0, true)
		draw_arc(size * 0.5, 17.0, 0.0, TAU, 32, Color(UiTokens.TEXT, 0.4), 1.5, true)
