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

const CATEGORY_NAMES := ["주거", "생산", "가공", "생활", "제작", "포함", "저장", "군사", "특수", "설비", "방어"]
const MODES := [[&"build", "새로 짓기"], [&"clear", "개간"], [&"repair", "수리·레벨업"], [&"access", "접근성 보기"]]
const MODE_TITLES := {&"build": "건물", &"clear": "구역", &"repair": "지은 건물", &"access": "구역별 참여 조건"}
## ZoneDef.mobility_access → words (07 "참여 조건": 이동).
const MOBILITY_KIND := {"open": "평지", "ramp": "경사로가 있어야 들어감", "elevator": "위층 · 승강기가 있어야 올라감"}
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


func _init() -> void:
	title_text = "건설"
	subtitle_text = "기지"
	footer_keys = [["Esc", "뒤로"], ["클릭", "고르기"], ["Enter", "실행"]]


## args: mode (&"build"|&"clear"|&"repair"|&"access"), zone (zone id), uid (building uid).
func open_with(args: Dictionary) -> void:
	_mode = StringName(args.get("mode", _mode))
	if args.has("zone"):
		_sel_zone = StringName(args["zone"])
	if args.has("uid"):
		_sel_uid = StringName(args["uid"])
	if args.has("def"):  # #125: "가족 숙소 짓기 ›" links from the resident screens
		_mode = &"build"
		_cat = -1
		_sel = StringName(args["def"])
	if _list != null:
		_refresh()


func _build_body(b: Control) -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override(&"separation", 12)
	b.add_child(col)
	_modes = HBoxContainer.new()
	_modes.add_theme_constant_override(&"separation", 6)
	col.add_child(_modes)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", 24)
	col.add_child(row)
	var left := MenuScreen.panel("건물", "", Vector2(980, 0))
	(left[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left[0])
	_list_title = (left[2] as HBoxContainer).get_child(0)
	_count = (left[2] as HBoxContainer).get_child(1)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override(&"separation", 4)
	(left[1] as VBoxContainer).add_child(_tabs)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	(left[1] as VBoxContainer).add_child(sc)
	var card := MenuScreen.cream_card(460)
	(card[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(card[0])
	_detail = card[1]
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
	_list_title.text = MODE_TITLES.get(_mode, "건물")
	_primary = Callable()
	match _mode:
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


# ---------------- 새로 짓기 (D-06) ----------------

func _build_tabs() -> void:
	MenuScreen.clear(_tabs)
	var all := MenuScreen.button("전체", &"TabText")
	all.toggle_mode = true
	all.button_pressed = _cat == -1
	all.pressed.connect(func() -> void: _set_cat(-1))
	_tabs.add_child(all)
	var used := {}
	for def: BuildingDef in BaseDB.buildings().values():
		if not def.prebuilt and def.attach_to == &"":
			used[int(def.category)] = true
	var cats := used.keys()
	cats.sort()
	for c: int in cats:
		var t := MenuScreen.button(CATEGORY_NAMES[c], &"TabText")
		t.toggle_mode = true
		t.button_pressed = _cat == c
		t.pressed.connect(_set_cat.bind(c))
		_tabs.add_child(t)


func _set_cat(c: int) -> void:
	_cat = c
	_build_tabs()
	_fill()


func _defs() -> Array:
	var out := []
	for def: BuildingDef in BaseDB.buildings().values():
		if def.prebuilt:
			continue
		if _cat >= 0 and int(def.category) != _cat:
			continue
		out.append(def)
	out.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool:
		var oa := bool(Colony.can_build(a.id).ok)
		var ob := bool(Colony.can_build(b.id).ok)
		return oa if oa != ob else a.display_name < b.display_name)
	return out


func _fill() -> void:
	MenuScreen.clear(_list)
	var defs := _defs()
	var ok_n := 0
	for def: BuildingDef in defs:
		var check: Dictionary = Colony.can_build(def.id)
		if check.ok:
			ok_n += 1
		_list.add_child(_row(def, check))
	_count.text = "지을 수 있음 %d / %d" % [ok_n, defs.size()]
	if _sel == &"" and not defs.is_empty():
		_sel = (defs[0] as BuildingDef).id
	_show_detail()


func _row(def: BuildingDef, check: Dictionary) -> Control:
	var sub := "%s · %d×%d칸" % [CATEGORY_NAMES[int(def.category)], def.size.x, def.size.y]
	var inclusive := def.category == BuildingDef.Category.INCLUSION
	var st := "지을 수 있음" if check.ok else reason_text(String((check.reasons as Array)[0]))
	return _list_row(def.id == _sel, def.display_name, sub, st, UiTokens.GOOD if check.ok else UiTokens.TEXT_DIM,
		not check.ok, func() -> void:
			_sel = def.id
			_fill(),
		InfoIcon.new(20) if inclusive else null,
		MenuScreen.label(MenuScreen.cost_text(def.cost_for_level(1)), &"LabelHud", 15))


func _show_detail() -> void:
	MenuScreen.clear(_detail)
	var def := BaseDB.get_building(_sel)
	if def == null:
		return
	var check: Dictionary = Colony.can_build(def.id)
	_detail.add_child(_tag(CATEGORY_NAMES[int(def.category)] + "  ·  %d×%d칸" % [def.size.x, def.size.y]))
	_detail.add_child(_title(def.display_name))
	if def.category == BuildingDef.Category.INCLUSION:
		_detail.add_child(_inclusion_line("포함 시설 — 참여 조건을 채워 줍니다"))
	var grid := _grid()
	_cost_rows(grid, def.cost_for_level(1))
	if def.power_use[0] > 0:
		_pair(grid, "전력", "−%d" % def.power_use[0])
	if def.noise > 0.0:
		_pair(grid, "기지 소음", "+%.1f" % def.noise)
	if def.capacity > 0:
		_pair(grid, "일손", "%d명" % def.capacity)
	_detail.add_child(grid)
	_reasons(check.reasons)
	_action("배치하기", check.ok, _place)


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
	return _list_row(zone_id == _sel_zone, z.display_name, " · ".join(parts), st, col, blocked,
		func() -> void:
			_sel_zone = zone_id
			_fill_clear(), null, mid)


func _show_zone() -> void:
	MenuScreen.clear(_detail)
	var z := BaseDB.get_zone(_sel_zone)
	if z == null:
		return
	_detail.add_child(_tag("구역  ·  %d×%d칸  ·  %s" % [z.size.x, z.size.y, "실내" if z.indoor else "야외"]))
	_detail.add_child(_title(z.display_name))
	var cleared := Colony.is_zone_cleared(_sel_zone)
	if cleared:
		_detail.add_child(_state_line(true, "개간 완료 — 이 구역에 지을 수 있음"))
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
	_detail.add_child(_state_line(false, "개간 중 — 건설 주민이 저녁마다 진행도를 올립니다"))
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
	_count.text = "파손 %d · 전체 %d" % [broken, uids.size()]
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
	var sub := "%s · %s" % [CATEGORY_NAMES[int(def.category)], _zone_name(b["zone_id"])]
	var st := ""
	var col := UiTokens.TEXT_DIM
	var mid: Control = null
	var wear := _wear(uid)
	if b["damaged"] and int(b["repair_progress"]) < 0:
		st = "■ 파손 · 멈춤"
		col = UiTokens.DANGER
	elif b["damaged"]:
		var need := Colony.repair_work_needed(uid)
		st = "수리 중 %d / %d" % [int(b["repair_progress"]), need]
		col = UiTokens.WARN
		mid = MenuScreen.bar(_ratio(int(b["repair_progress"]), need), UiTokens.WARN, 140)
	elif wear != Vector2i(-1, -1):
		st = "◆ 내구도 %d / %d" % [wear.x, wear.y]
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
	_detail.add_child(_tag("%s  ·  %s  ·  Lv%d / %d" % [CATEGORY_NAMES[int(def.category)], _zone_name(b["zone_id"]),
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
	v.add_theme_constant_override(&"separation", 4)
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
	v.add_theme_constant_override(&"separation", 4)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	v.add_child(h)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override(&"separation", -2)
	nv.custom_minimum_size = Vector2(300, 0)
	var cleared := Colony.is_zone_cleared(zone_id)
	var nm := MenuScreen.label(z.display_name if z else String(zone_id), &"LabelSection", 18)
	if not cleared:
		nm.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	nv.add_child(nm)
	var kind := String(MOBILITY_KIND.get(z.mobility_access, "")) if z else ""
	nv.add_child(MenuScreen.label(kind + ("" if cleared else " · 개간 전"), &"LabelDim", 13))
	h.add_child(nv)
	var mob := bool(acc.get("mobility", true))
	var lang := bool(acc.get("language", true))
	h.add_child(_met_cell(mob, "갈 수 있음" if mob else "못 들어감", 210))
	h.add_child(_met_cell(lang, "그림 표지판 있음" if lang else "그림 표지판 없음", 210))
	var fac := HBoxContainer.new()
	fac.add_theme_constant_override(&"separation", 8)
	fac.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if facilities.is_empty():
		fac.add_child(MenuScreen.label("—", &"LabelDim", 14))
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
	_detail.add_child(_tag("07 참여 조건  ·  기지가 아직 갖추지 못한 것"))
	_detail.add_child(_title("기지 전체"))
	var hearing := bool(map.get("hearing_alarm", false))
	_detail.add_child(_state_line(hearing, "청각 — 시각 경보(경광등) " + ("켜짐" if hearing else "꺼짐 (전력이 들어온 경광등 필요)")))
	var care: Dictionary = map.get("care", {})
	var guardians := int(care.get("guardians", 0))
	var covered := (care.get("covered", []) as Array).size()
	_detail.add_child(_state_line(covered >= guardians, "돌봄 — 자리 %d · 보호자 %d명 중 %d명 맡김" % [
		int(care.get("slots", 0)), guardians, covered]))
	var radio := bool(map.get("interpreter_radio", false))
	_detail.add_child(_state_line(radio, "언어 — 통역 무전기 " + ("있음 (무전·외교 가능)" if radio else "없음")))
	_detail.add_child(HSeparator.new())
	var counts := [0, 0, 0]
	for id in Colony.active_resident_ids():
		var needs: Array = Colony.get_resident(id).get("access_needs", [])
		for i in 3:
			if i in needs:
				counts[i] += 1
	_detail.add_child(MenuScreen.label("참여 조건이 있는 주민  이동 %d · 언어 %d · 청각 %d" % counts, &"LabelOnCream", 15))
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
	nv.add_theme_constant_override(&"separation", -2)
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
		if _mode == &"build":
			_place()
		elif _primary.is_valid():
			_primary.call()
		get_viewport().set_input_as_handled()
