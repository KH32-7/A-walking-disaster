class_name JournalScreen
extends MenuScreen
## Survival journal (생존 일지) + quest log (D-16). Owner: Lane D.
## Design 14 "생존 일지: 날짜별 기록, 주민별 보기, 녹음 모음", 15 "생존 일지와 에필로그",
## 13 "남겨진 녹음", "퀘스트 유형". UI_RULES §4 menu (dark list panel = 목록, cream card = 읽을거리),
## §5 "퀘스트 카드".
##
## Tabs: days / people / recordings / quests. Everything is drawn from getters, nothing is computed:
##   Journal.days(), entries_for_day(), entries_for_resident(), people(), resident_name(), epilogue()
##   (A-17; redraw on journal_entry_added), Quests.active_quests(), get_def() (A-13; redraw on
##   quest_started / updated / completed / failed).
## Recordings: no getter yet. Reads Journal.recordings() once it exists (requested from Lane A:
## [{"id", "speaker", "text", "region_id", "place", "day"}]); until then the tab shows its empty state.
##
## open_with({"tab": &"days" | &"people" | &"recordings" | &"quests", "day": int, "resident_id",
##   "quest_id", "recordings": Array (preview / test data in the format above)}) — all optional.

const TABS := [[&"days", "날짜별"], [&"people", "주민별"], [&"recordings", "녹음"], [&"quests", "퀘스트"]]
const QUEST_TYPES := ["주 이야기", "개인 요청", "무전 소문", "공동체", "거래"]
const REQUEST_TYPES := ["찾기", "데려가기", "만들기", "지키기"]
## Epilogue / journal status -> words. Status is always text, never colour alone.
const STATUS_TEXT := {&"active": "함께 지내요", &"missing": "실종", &"left": "떠났어요", &"dead": "세상을 떠났어요"}
const STATUS_COLOR := {&"active": UiTokens.GOOD, &"missing": UiTokens.WARN, &"left": UiTokens.GREY_BTN,
	&"dead": UiTokens.DANGER}
const BROADCASTER_NAME := "방송실 지기"
const LIST_W := 460.0

var _tab: StringName = &"days"
var _day := -1
var _resident: StringName = &""
var _quest: StringName = &""
var _recording: StringName = &""
var _recordings_override: Variant = null

var _tab_bar: HBoxContainer
var _list_head: Label
var _list_count: Label
var _list: VBoxContainer
var _page: Control
## Row buttons in list order, for ↑/↓ and tests: [{"key": Variant, "button": Button}]
var _rows: Array = []


func _init() -> void:
	title_text = "생존 일지"
	footer_keys = [["Esc", "뒤로"], ["1~4", "보기"], ["↑ / ↓", "고르기"]]
	header_resources = []


func open_with(args: Dictionary) -> void:
	if args.has("tab"):
		for t: Array in TABS:
			if t[0] == StringName(args.tab):
				_tab = t[0]
	if args.has("day"):
		_day = int(args.day)
	if args.has("resident_id"):
		_resident = StringName(args.resident_id)
	if args.has("quest_id"):
		_quest = StringName(args.quest_id)
	if args.has("recordings"):
		_recordings_override = args.recordings
	if _list != null:
		_refresh()


func _build_body(b: Control) -> void:
	set_subtitle("%d일차" % GameState.day)
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override(&"separation", 10)
	b.add_child(_tab_bar)
	_tab_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_tab_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tab_bar.position.y = -78

	var lp := MenuScreen.panel("", "")
	var left: PanelContainer = lp[0]
	b.add_child(left)
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = LIST_W
	var band: HBoxContainer = lp[2]
	_list_head = band.get_child(0)
	_list_count = band.get_child(1)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	(lp[1] as VBoxContainer).add_child(sc)

	_page = Control.new()
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(_page)
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.offset_left = LIST_W + 24

	EventBus.journal_entry_added.connect(func(_d: int, _t: String) -> void: _refresh())
	for s: Signal in [EventBus.quest_started, EventBus.quest_completed]:
		s.connect(func(_q: StringName) -> void: _refresh())
	EventBus.quest_updated.connect(func(_q: StringName, _o: StringName, _p: int) -> void: _refresh())
	EventBus.quest_failed.connect(func(_q: StringName, _r: StringName) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	set_subtitle("%d일차" % GameState.day)
	_fill_tabs()
	MenuScreen.clear(_list)
	MenuScreen.clear(_page)
	_rows.clear()
	match _tab:
		&"days": _show_days()
		&"people": _show_people()
		&"recordings": _show_recordings()
		&"quests": _show_quests()


func _fill_tabs() -> void:
	MenuScreen.clear(_tab_bar)
	var i := 1
	for t: Array in TABS:
		var b := MenuScreen.button("%d  %s" % [i, t[1]], &"TabText")
		b.toggle_mode = true
		b.button_pressed = t[0] == _tab
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_tab.bind(t[0]))
		_tab_bar.add_child(b)
		i += 1


func _set_tab(tab: StringName) -> void:
	_tab = tab
	_refresh()


# ---------------- days ----------------

## Journal days, newest first. Today is always listed so the page is never missing.
func day_list() -> Array[int]:
	var days: Array[int] = Journal.days()
	if not GameState.day in days:
		days.append(GameState.day)
	days.sort()
	days.reverse()
	return days


func _show_days() -> void:
	var days := day_list()
	_list_head.text = "날짜별"
	_list_count.text = "%d일" % days.size()
	if not _day in days:
		_day = days[0]
	for d in days:
		var entries := Journal.entries_for_day(d)
		var first := String(entries[0].get("body", "")) if not entries.is_empty() else "아직 적힌 일이 없어요."
		var tag := "오늘" if d == GameState.day else ("%d줄" % entries.size())
		_add_row(d, "%d일차" % d, first, tag, d == _day, _pick_day.bind(d))
	var card := _page_card("%d일차" % _day, "오늘" if _day == GameState.day else "%d일 전" % (GameState.day - _day))
	var v: VBoxContainer = card[1]
	var entries := Journal.entries_for_day(_day)
	if entries.is_empty():
		v.add_child(_cream_line("아직 적힌 일이 없어요. 하루가 지나면 일지에 한 줄씩 남아요.", true))
	for e: Dictionary in entries:
		v.add_child(_entry_line(String(e.get("body", e.get("text", ""))), _names_of(e.get("residents", []))))


func _pick_day(d: int) -> void:
	_day = d
	_refresh()


# ---------------- people ----------------

func _statuses() -> Dictionary:
	var out := {}
	for c: Dictionary in Journal.epilogue():
		out[StringName(c.get("resident_id", &""))] = StringName(c.get("status", &"active"))
	return out


func _show_people() -> void:
	var ids: Array[StringName] = Journal.people()
	var statuses := _statuses()
	_list_head.text = "주민별"
	_list_count.text = "%d명" % ids.size()
	if ids.is_empty():
		_page_empty("아직 만난 사람이 없어요.", "구조한 생존자와 주민의 이야기가 여기에 모여요.")
		return
	if not _resident in ids:
		_resident = ids[0]
	for id in ids:
		var entries := Journal.entries_for_resident(id)
		var st: StringName = statuses.get(id, &"active")
		var last := String(entries.back().get("text", "")) if not entries.is_empty() else "아직 기록이 없어요."
		_add_row(id, Journal.resident_name(id), last, STATUS_TEXT.get(st, ""), id == _resident,
			_pick_resident.bind(id), STATUS_COLOR.get(st, UiTokens.TEXT_DIM))
	var st: StringName = statuses.get(_resident, &"active")
	var card := _page_card(Journal.resident_name(_resident), STATUS_TEXT.get(st, ""))
	var v: VBoxContainer = card[1]
	var entries := Journal.entries_for_resident(_resident)
	if entries.is_empty():
		v.add_child(_cream_line("아직 이 사람의 이야기가 일지에 없어요.", true))
	for e: Dictionary in entries:
		v.add_child(_entry_line(String(e.get("text", "")), []))


func _pick_resident(id: StringName) -> void:
	_resident = id
	_refresh()


# ---------------- recordings ----------------

## Collected recordings. Preview / test data first, then Journal.recordings() once Lane A adds it.
func recordings() -> Array:
	if _recordings_override != null:
		return _recordings_override
	if Journal.has_method(&"recordings"):
		return Journal.call(&"recordings")
	return []


func _show_recordings() -> void:
	var recs := recordings()
	_list_head.text = "녹음 모음"
	_list_count.text = "%d개" % recs.size()
	if recs.is_empty():
		_page_empty("아직 찾은 녹음기가 없어요.",
			"필드 곳곳에 대범람 때의 목소리가 담긴 녹음기가 남아 있어요. 찾으면 여기서 다시 들을 수 있어요.")
		return
	var ids: Array = recs.map(func(r: Dictionary) -> StringName: return StringName(r.get("id", &"")))
	if not _recording in ids:
		_recording = ids[0]
	var sel: Dictionary = recs[ids.find(_recording)]
	for r: Dictionary in recs:
		var id := StringName(r.get("id", &""))
		var where := String(r.get("place", ""))
		_add_row(id, String(r.get("speaker", "이름 모를 목소리")), where,
			("%d일차" % int(r.day)) if r.has("day") else "", id == _recording, _pick_recording.bind(id))
	var card := _page_card(String(sel.get("speaker", "이름 모를 목소리")), String(sel.get("place", "")))
	var v: VBoxContainer = card[1]
	var tape := MenuScreen.label("녹음 자막", &"LabelOnCreamDim")
	v.add_child(tape)
	var text := MenuScreen.label(String(sel.get("text", "")), &"LabelOnCream", 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_constant_override(&"line_spacing", 8)
	v.add_child(text)
	if sel.has("day"):
		var foot := _cream_foot(card[0])
		foot.add_child(MenuScreen.label("%d일차에 찾음" % int(sel.day), &"LabelOnCreamDim"))


func _pick_recording(id: StringName) -> void:
	_recording = id
	_refresh()


# ---------------- quests ----------------

func _show_quests() -> void:
	var quests: Array[Dictionary] = Quests.active_quests()
	_list_head.text = "진행 중인 퀘스트"
	_list_count.text = "%d개" % quests.size()
	if quests.is_empty():
		_page_empty("진행 중인 퀘스트가 없어요.", "아침 방송과 주민의 부탁에서 새 일이 생겨요.")
		return
	var ids: Array = quests.map(func(q: Dictionary) -> StringName: return StringName(q.id))
	if not _quest in ids:
		_quest = ids[0]
	for q: Dictionary in quests:
		var done := 0
		for o: Dictionary in q.objectives:
			done += 1 if o.done else 0
		var tag := _days_left_text(int(q.days_left))
		_add_row(q.id, String(q.title), "%s / 목표 %d/%d" % [_type_text(q), done, q.objectives.size()], tag,
			q.id == _quest, _pick_quest.bind(q.id), UiTokens.WARN if int(q.days_left) in [0, 1] else UiTokens.TEXT_DIM)
	_build_quest_card(quests[ids.find(_quest)])


func _pick_quest(id: StringName) -> void:
	_quest = id
	_refresh()


func _type_text(q: Dictionary) -> String:
	var t := int(q.get("type", 0))
	var text: String = QUEST_TYPES[clampi(t, 0, QUEST_TYPES.size() - 1)]
	var def: QuestDef = Quests.get_def(StringName(q.get("id", &"")))
	if t == Enums.QuestType.PERSONAL and def != null:
		text += " / " + REQUEST_TYPES[clampi(int(def.request_type), 0, 3)]
	return text


## "남은 날 N일" with a ▲ when the last day is close; "" without a deadline.
static func _days_left_text(days_left: int) -> String:
	if days_left < 0:
		return ""
	if days_left == 0:
		return "▲ 오늘까지"
	return ("▲ " if days_left == 1 else "") + "%d일 남음" % days_left


static func giver_name(giver_id: StringName) -> String:
	if giver_id == Quests.BROADCASTER:
		return BROADCASTER_NAME
	if giver_id == &"":
		return "무전 소문"
	return Journal.resident_name(giver_id)


## UI_RULES §5 quest card: picture on top, bold title, story paragraph; cream column on the right
## with goal checkboxes and rewards.
func _build_quest_card(q: Dictionary) -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = &"PanelMenu"
	_page.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 22)
	p.add_child(h)

	var story := VBoxContainer.new()
	story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story.add_theme_constant_override(&"separation", 14)
	h.add_child(story)
	story.add_child(_quest_picture(q))
	var title := MenuScreen.label(String(q.title), &"LabelTitle")
	story.add_child(title)
	var giver := StringName(q.giver_id)
	var meta_text := _type_text(q) + (" / 의뢰 " + giver_name(giver) if giver != &"" else " / 무전으로 들은 이야기")
	var meta := MenuScreen.label(meta_text, &"LabelDim", 16)
	story.add_child(meta)
	var desc := MenuScreen.label(String(q.description), &"Label", 18)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_constant_override(&"line_spacing", 7)
	story.add_child(desc)

	var cc := MenuScreen.cream_card(440)
	var cream: PanelContainer = cc[0]
	cream.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(cream)
	var v: VBoxContainer = cc[1]
	v.add_theme_constant_override(&"separation", 10)
	v.add_child(MenuScreen.label("목표", &"LabelOnCream", 20))
	for o: Dictionary in q.objectives:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		row.add_child(CheckMark.new(bool(o.done)))
		var t := MenuScreen.label(String(o.text), &"LabelOnCream")
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if bool(o.done):
			t.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM_DIM)
		row.add_child(t)
		var n := MenuScreen.label("%d/%d" % [int(o.progress), int(o.count)], &"LabelOnCream", 17)
		n.add_theme_font_override(&"font", UiThemeBuilder.font_num())
		row.add_child(n)
		v.add_child(row)
	v.add_child(HSeparator.new())
	v.add_child(MenuScreen.label("보상", &"LabelOnCream", 20))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	var rewards := reward_rows(StringName(q.id))
	for r: Array in rewards:
		grid.add_child(_reward_chip(r[0], r[1], int(r[2]) if r.size() > 2 else -1))
	if rewards.is_empty():
		grid.add_child(MenuScreen.label("이야기가 이어져요.", &"LabelOnCreamDim", 15))
	v.add_child(grid)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	var foot := PanelContainer.new()
	foot.theme_type_variation = &"CardCreamFoot"
	var fl := MenuScreen.label("", &"LabelOnCream", 16)
	var dl := int(q.days_left)
	fl.text = ("기한  " + _days_left_text(dl)) if dl >= 0 else "기한 없음"
	if dl in [0, 1]:
		fl.add_theme_color_override(&"font_color", UiTokens.DANGER)
	foot.add_child(fl)
	v.add_child(foot)


## Reward lines from QuestDef.rewards: [[name, amount text, rarity (items only)]]. Flags stay hidden.
static func reward_rows(quest_id: StringName) -> Array:
	var def: QuestDef = Quests.get_def(quest_id)
	var out: Array = []
	if def == null:
		return out
	var res: Dictionary = def.rewards.get("resources", {})
	for id in res:
		out.append([MenuScreen.resource_name(StringName(id)), "×%d" % int(res[id])])
	for it: Dictionary in def.rewards.get("items", []):
		var idef: ItemDef = Armory.get_def(StringName(it.get("def_id", &"")))
		var nm := idef.name if idef != null else String(it.get("def_id", ""))
		out.append([nm, "", int(it.get("rarity", 0))])
	if int(def.rewards.get("trust", 0)) != 0:
		out.append(["신뢰", "+%d" % int(def.rewards.trust)])
	return out


func _reward_chip(nm: String, amount: String, rarity: int) -> Control:
	var c := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTokens.CREAM_2
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	c.add_theme_stylebox_override(&"panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	c.add_child(h)
	if rarity >= 0:
		var badge := ShapeBadge.new()
		badge.value = rarity
		badge.badge_size = 14
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(badge)
	h.add_child(MenuScreen.label(nm, &"LabelOnCream"))
	if amount != "":
		# Reward numbers are yellow (UI_RULES §1.4): a yellow chip so it reads on cream.
		var chip := PanelContainer.new()
		var cs := StyleBoxFlat.new()
		cs.bg_color = UiTokens.ACCENT
		cs.set_corner_radius_all(6)
		cs.content_margin_left = 7
		cs.content_margin_right = 7
		chip.add_theme_stylebox_override(&"panel", cs)
		var n := MenuScreen.label(amount, &"LabelOnCream", 17)
		n.add_theme_font_override(&"font", UiThemeBuilder.font_num())
		n.add_theme_color_override(&"font_color", UiTokens.ACCENT_TEXT)
		chip.add_child(n)
		h.add_child(chip)
	return c


## No quest art yet: a dark plate with the quest kind and a drawn horizon line (placeholder for the
## picture UI_RULES §5 puts on top of the card).
func _quest_picture(q: Dictionary) -> Control:
	var pic := PanelContainer.new()
	pic.theme_type_variation = &"PanelSlateInner"
	pic.custom_minimum_size = Vector2(0, 300)
	pic.clip_contents = true
	var art := _QuestArt.new()
	art.kind = int(q.get("type", 0))
	art.clip_contents = true
	pic.add_child(art)
	var tag := MenuScreen.label(_type_text(q), &"LabelHud", 16)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.size_flags_vertical = Control.SIZE_SHRINK_END
	pic.add_child(tag)
	return pic


class _QuestArt extends Control:
	var kind := 0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sky := UiTokens.INFO.darkened(0.55) if kind == Enums.QuestType.MAIN else UiTokens.SLATE_2.lightened(0.1)
		draw_rect(r, sky.darkened(0.2))
		var water := size.y * 0.66
		draw_rect(Rect2(0, water, size.x, size.y - water), UiTokens.INFO.darkened(0.7))
		# skyline of half-sunk buildings
		var x := 0.0
		var i := 0
		while x < size.x:
			var w := 46.0 + float((i * 37) % 60)
			var hgt := 40.0 + float((i * 53) % 90)
			draw_rect(Rect2(x, water - hgt, w - 8.0, hgt + 8.0), UiTokens.INK.lerp(sky, 0.35))
			x += w
			i += 1
		for k in 4:
			var y := water + 10.0 + k * 14.0
			draw_line(Vector2(size.x * 0.1 + k * 30.0, y), Vector2(size.x * 0.4 + k * 50.0, y),
				Color(UiTokens.TEXT, 0.12), 2.0)


# ---------------- builders ----------------

func _add_row(key: Variant, title: String, sub: String, tag: String, selected: bool, on_pick: Callable,
		tag_color: Color = UiTokens.TEXT_DIM) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 74)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.07) if selected else Color(1, 1, 1, 0.0)
	n.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	if selected:
		n.border_color = UiTokens.ACCENT
		n.border_width_left = 4
	var hv := n.duplicate() as StyleBoxFlat
	hv.bg_color = Color(1, 1, 1, 0.1)
	for s in [&"normal", &"pressed", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(s, n)
	b.add_theme_stylebox_override(&"hover", hv)
	b.pressed.connect(on_pick)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10 if side in ["top", "bottom"] else 16)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override(&"separation", 2)
	m.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := MenuScreen.label(title, &"LabelSection", 19)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if selected:
		t.add_theme_color_override(&"font_color", UiTokens.ACCENT)
	top.add_child(t)
	if tag != "":
		var tl := MenuScreen.label(tag, &"LabelDim", 14)
		tl.add_theme_color_override(&"font_color", tag_color)
		top.add_child(tl)
	v.add_child(top)
	var s := MenuScreen.label(sub, &"LabelDim", 14)
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.clip_text = true
	v.add_child(s)
	for c in [t, s]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(b)
	var line := ColorRect.new()
	line.color = UiTokens.LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(line)
	_rows.append({"key": key, "button": b})


## A cream "page" filling the right side. Returns [card, content VBox].
func _page_card(title: String, sub: String) -> Array:
	var cc := MenuScreen.cream_card(0)
	var card: PanelContainer = cc[0]
	_page.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var outer: VBoxContainer = cc[1]
	outer.add_theme_constant_override(&"separation", 14)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 14)
	var t := MenuScreen.label(title, &"LabelOnCream", 30)
	t.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	head.add_child(t)
	var s := MenuScreen.label(sub, &"LabelOnCreamDim", 17)
	s.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(s)
	outer.add_child(head)
	var rule := ColorRect.new()
	rule.color = Color(UiTokens.TEXT_ON_CREAM, 0.18)
	rule.custom_minimum_size = Vector2(0, 1.5)
	outer.add_child(rule)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return [card, v]


func _cream_foot(card: PanelContainer) -> HBoxContainer:
	var foot := PanelContainer.new()
	foot.theme_type_variation = &"CardCreamFoot"
	var h := HBoxContainer.new()
	foot.add_child(h)
	(card.get_child(0) as VBoxContainer).add_child(foot)
	return h


func _page_empty(title: String, body_text: String) -> void:
	var card := _page_card(title, "")
	(card[1] as VBoxContainer).add_child(_cream_line(body_text, true))


func _cream_line(text: String, dim := false) -> Label:
	var l := MenuScreen.label(text, &"LabelOnCreamDim" if dim else &"LabelOnCream", 18 if not dim else 16)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## One journal line: a pen mark, the sentence, and who it is about (text, never colour only).
func _entry_line(text: String, names: PackedStringArray) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 14)
	var mark := MenuScreen.label("-", &"LabelOnCreamDim", 20)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(mark)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override(&"separation", 2)
	var l := MenuScreen.label(text, &"LabelOnCream", 21)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	if not names.is_empty():
		v.add_child(MenuScreen.label(" / ".join(names), &"LabelOnCreamDim", 14))
	h.add_child(v)
	return h


func _names_of(ids: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids:
		out.append(Journal.resident_name(StringName(id)))
	return out


# ---------------- keys ----------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or UI.top() != StringName(name) or not event.is_pressed() or event.is_echo():
		return
	var k := (event as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_4:
		_set_tab(TABS[k - KEY_1][0])
	elif k == KEY_UP or k == KEY_DOWN:
		move_selection(-1 if k == KEY_UP else 1)
	else:
		return
	get_viewport().set_input_as_handled()


## Picks the row above (-1) or below (+1) the selected one.
func move_selection(step: int) -> void:
	if _rows.is_empty():
		return
	var cur := 0
	for i in _rows.size():
		var key: Variant = _rows[i].key
		if key == _selected_key():
			cur = i
	var next := clampi(cur + step, 0, _rows.size() - 1)
	(_rows[next].button as Button).pressed.emit()


func _selected_key() -> Variant:
	match _tab:
		&"days": return _day
		&"people": return _resident
		&"recordings": return _recording
		&"quests": return _quest
	return null
