class_name ResidentEventFlow
extends Node
## Resident event screens controller (issue #125 parts 1·2·5, C-14·C-15·C-16). Owner: Lane D.
## A child of the `UI` autoload. Design 08 "아이 맞이", "편견과 갈등", "청혼·결혼식".
##
## Opens one screen at a time while the player is at the base (evening, night, morning, stay day):
##   child_naming      a child came to a family (Colony.child_arrived) and still waits for a name
##   child_wish        a married couple wants a child (Colony.child_wish, Colony.child_wishes())
##   prejudice_choice  a rumor about a 마물 흔적 resident waits for the player's answer (prejudice_rumor)
## It also triggers after the evening settlement and when the welcome / night event screens close,
## so it never covers them. Each screen walks its own queue from Colony; a second signal on the
## same evening only adds to that queue. Closing with something left (Esc, 나중에) leaves it in
## Colony and it comes back the next day. The wedding screen (wedding_prep) is opened by the player
## (resident detail, the proposal night event), not here.
##
## The static helpers are what the resident screens read; they only sort Colony getters, never rules.

const NAMING := &"child_naming"
const WISH := &"child_wish"
const PREJUDICE := &"prejudice_choice"
const WEDDING := &"wedding_prep"
const ORDER: Array[StringName] = [NAMING, WISH, PREJUDICE]
## Screens ours wait for (they are the same evening / night story and come first).
const WAIT_FOR: Array[StringName] = [&"welcome", &"night_event", &"raid_warning", &"raid_result", &"loading"]

const CHAIN_STEPS: Array[StringName] = [PrejudiceRules.STEP_RUMOR, PrejudiceRules.STEP_WAITING,
	PrejudiceRules.STEP_INCIDENT, PrejudiceRules.STEP_RESOLVED]
const CHAIN_STEP_NAMES := ["소문이 돈다", "어떻게 할지 고른다", "며칠 뒤 무슨 일이 생긴다", "편견을 가진 주민과 이야기한다"]
const CHOICE_NAMES := {PrejudiceRules.CHOICE_DEFEND: "공개적으로 감싼다", PrejudiceRules.CHOICE_WATCH: "지켜본다",
	PrejudiceRules.CHOICE_SEPARATE: "따로 지내게 한다"}
const CHOICE_DONE := {PrejudiceRules.CHOICE_DEFEND: "감싸 주기로 했어요", PrejudiceRules.CHOICE_WATCH: "지켜보기로 했어요",
	PrejudiceRules.CHOICE_SEPARATE: "따로 지내게 했어요"}
const METHOD_NAMES := {Enums.ArrivalMethod.BIRTH: "출산", Enums.ArrivalMethod.ADOPTION: "입양"}
## Step bands (UI redesign "순서가 있는 일은 순서를 보여 준다").
const PREJUDICE_STEPS := ["소문", "선택", "사건", "해소"]
const CHILD_STEPS := ["바람", "맞이", "이름 짓기", "입주"]
const WEDDING_STEPS := ["조건", "준비", "다음 밤"]
## Missing words that a building fixes → that building (the "짓기 ›" link). Display-side only.
## TODO(C): a missing-condition getter with ids would replace this word match.
const BUILD_LINKS := [["가족 숙소", &"family_house"], ["의무실", &"infirmary"]]

## Opens screens only while a game scene runs (main.tscn or a preview), like RaidFlow.
## true / false forces it (tests/ui/test_resident_events.gd).
var auto_open: Variant = null
## screen id -> day it was closed with something still waiting (no re-open that day).
var _skipped_day := {}
var _queued := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Colony.child_wish.connect(func(_a: StringName, _b: StringName, _m: Array) -> void: kick())
	Colony.child_arrived.connect(func(_c: StringName, _m: int, _p: Array) -> void: kick())
	Colony.prejudice_rumor.connect(func(_t: StringName, _h: Array) -> void: kick())
	EventBus.evening_settled.connect(func(_r: Dictionary) -> void: kick())
	EventBus.flow_state_changed.connect(func(_s: Enums.FlowState) -> void: kick())
	UI.screen_closed.connect(_on_screen_closed)


## Looks for something to show at the end of the frame (signals arrive mid-settlement).
func kick() -> void:
	if not _queued:
		_queued = true
		_open_next.call_deferred()


func _on_screen_closed(id: StringName) -> void:
	if id in ORDER and pending(id):
		_skipped_day[id] = GameState.day
	if id in ORDER or id in WAIT_FOR:
		kick()


func _can_open() -> bool:
	var on: bool = auto_open if auto_open is bool else get_tree().current_scene != null
	return on and GameState.flow_state in UI.BASE_STATES


## The screen that would open now (&"" = none). Tests and previews read it.
func next_screen() -> StringName:
	for id in ORDER:
		if UI.is_open(id):
			return &""
	for id in WAIT_FOR:
		if UI.is_open(id):
			return &""
	for id in ORDER:
		if UI.has_screen(id) and pending(id) and int(_skipped_day.get(id, -1)) != GameState.day:
			return id
	return &""


func _open_next() -> void:
	_queued = false
	if not _can_open():
		return
	var id := next_screen()
	if id != &"":
		UI.open(id)


# ---------------- queues (Colony getters, sorted) ----------------

static func pending(id: StringName) -> bool:
	match id:
		NAMING:
			return not naming_queue().is_empty()
		WISH:
			return not Colony.child_wishes().is_empty()
		PREJUDICE:
			return not rumor_queue().is_empty()
	return false


## A resident in the ceremony who is a family's child (born here, or a rescued child a waiting family
## adopted): they get the 이름 짓기 scene instead of the adult 입주 의식.
static func is_family_child(id: StringName) -> bool:
	var r := Colony.get_resident(id)
	return not r.is_empty() and bool(r.get("arrival_pending", false)) and ChildRules.is_minor(r) \
		and not Colony.guardians_of(id).is_empty()


static func naming_queue() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Colony.pending_arrivals():
		if is_family_child(id):
			out.append(id)
	return out


## Pending arrivals for the 입주 의식 (welcome) screen: everyone but the family children.
static func welcome_queue() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Colony.pending_arrivals():
		if not is_family_child(id):
			out.append(id)
	return out


## Rumor targets waiting for the player's answer, oldest first.
static func rumor_queue() -> Array[StringName]:
	var chains := Colony.prejudice_chains()
	var out: Array[StringName] = []
	for target: StringName in chains:
		if StringName(chains[target].get("step", &"")) == PrejudiceRules.STEP_RUMOR and not Colony.get_resident(target).is_empty():
			out.append(target)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return int(chains[a].get("started_day", 0)) < int(chains[b].get("started_day", 0)))
	return out


## Index of the chain's step in CHAIN_STEPS (rumor 0 … resolved 3), -1 = no chain.
static func chain_step_index(chain: Dictionary) -> int:
	return CHAIN_STEPS.find(StringName(chain.get("step", &"")))


# ---------------- wedding ----------------

## &"none" (not engaged), &"open" (engaged, not prepared) or &"ready" (prepared: wedding next night).
## TODO(C): wedding_status() has no explicit keys for these; until it does they are read from its
## "missing" words ("청혼 전", "이미 준비됨"). Asked in the PR.
static func wedding_state(status: Dictionary) -> StringName:
	var missing: Array = status.get("missing", [])
	if "청혼 전" in missing:
		return &"none"
	if "이미 준비됨" in missing:
		return &"ready"
	return &"open"


## Wedding missing words with resource ids shown by their names ("food 20 필요" → "식량 20 필요").
static func wedding_missing(status: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var cost: Dictionary = status.get("cost", {})
	for m in status.get("missing", []):
		var t := String(m)
		if t in ["청혼 전", "이미 준비됨"]:
			continue
		for res in cost:
			if t.begins_with(String(res) + " "):
				t = MenuScreen.resource_name(StringName(res)) + t.substr(String(res).length())
		out.append(t)
	return out


# ---------------- resident detail (D-06 screen) ----------------

## Extra lines for the resident detail: [[text, colour], ...]. Prejudice chain, engagement, children.
static func detail_lines(id: StringName) -> Array:
	var out: Array = []
	var chain := Colony.prejudice_chain(id)
	if not chain.is_empty():
		var i := chain_step_index(chain)
		var choice := StringName(chain.get("choice", &""))
		var text := "소문: "
		match i:
			0:
				text += "어떻게 할지 고를 차례예요"
			1:
				text += "%s / 며칠 안에 무슨 일이 생길 것 같아요" % CHOICE_DONE.get(choice, "골랐어요")
			2:
				text += "사건이 있었어요 / 편견을 가진 주민과 이야기할 밤을 기다려요"
			_:
				text = "✓ 소문이 풀렸어요. 마물이 된다는 말은 근거가 없었어요"
		out.append([text, UiTokens.INFO])
	var chains := Colony.prejudice_chains()
	for target: StringName in chains:
		if id in chains[target].get("holders", []) and chain_step_index(chains[target]) < 3:
			out.append(["▲ 편견: %s에 대한 소문을 믿어요" % ResidentText.call_name(Colony.get_resident(target)), UiTokens.WARN])
	var partner := Colony.partner_of(id)
	if partner != &"":
		var pname := ResidentText.call_name(Colony.get_resident(partner))
		if Colony.relation_stage(id, partner) == &"married":
			var st := Colony.child_arrival_status(id, partner)
			if Colony.is_pregnant(id) or Colony.is_pregnant(partner):
				out.append(["아이 맞이: 아기를 기다리는 중이에요", UiTokens.TEXT])
			elif st.get("ok", false):
				out.append(["● 아이 맞이: 조건이 맞아요. 가족이 먼저 이야기를 꺼내요", UiTokens.GOOD])
			# not ok: detail_lack_box() says what the base still lacks
		else:
			var ws := Colony.wedding_status(id, partner)
			match wedding_state(ws):
				&"ready":
					out.append(["결혼 약속: %s와(과) 다음 밤 결혼식" % pname, UiTokens.TEXT])
				&"open":
					var miss := wedding_missing(ws)
					out.append(["결혼 약속: %s / %s" % [pname, "준비할 수 있어요" if miss.is_empty() else "모자란 것 %d개" % miss.size()],
						UiTokens.TEXT])
	return out


## Extra buttons for the resident detail: [[label, screen_id, args], ...] for screens that exist.
static func detail_buttons(id: StringName) -> Array:
	var out: Array = []
	if id in rumor_queue():
		out.append(["소문 대응", PREJUDICE, {"resident_id": id}])
	for w: Dictionary in Colony.child_wishes():
		if id in [StringName(w.a), StringName(w.b)]:
			out.append(["아이 이야기", WISH, {"a": w.a, "b": w.b}])
	var partner := Colony.partner_of(id)
	if partner != &"" and Colony.relation_stage(id, partner) != &"married" \
			and wedding_state(Colony.wedding_status(id, partner)) != &"none":
		out.append(["결혼식 준비", WEDDING, {"a": id, "b": partner}])
	return out.filter(func(b: Array) -> bool: return UI.has_screen(b[1]))


# ---------------- "기지가 아직 못 갖춘 것" (UI redesign: conditions as what the base lacks) ----------------

## The building that fixes a missing word (&"" = none).
static func build_link(missing: String) -> StringName:
	for pair: Array in BUILD_LINKS:
		if missing.contains(String(pair[0])):
			return pair[1]
	return &""


## Teal box: "<title> · 기지가 아직 못 갖춘 것" with one ✕ line per missing word and, when a building
## fixes it, a "<building> 짓기 ›" link that opens the build screen on it. on_cream = inside a cream
## card (dark words) or on a slate panel (light words).
static func lack_box(title: String, missing: Array, on_cream := true) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.INFO, 0.16 if on_cream else 0.14)
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override(&"panel", sb)
	var ink := UiTokens.TEXT_ON_CREAM if on_cream else UiTokens.TEXT
	var link_ink := Color("1f6f74") if on_cream else UiTokens.INFO
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 10)
	head.add_child(InfoIcon.new(20))
	# "기지가 아직 못 갖춘 것" when a building or stock is missing; family-only gaps (사기, 간격) say "아직 모자란 것".
	var base_gap := false
	for m in missing:
		base_gap = base_gap or build_link(String(m)) != &"" or String(m).begins_with(MenuScreen.resource_name(&"food")) 			or String(m).begins_with(MenuScreen.resource_name(&"cloth"))
	var t := MenuScreen.label("%s / %s" % [title, "기지가 아직 못 갖춘 것" if base_gap else "아직 모자란 것"], &"Label", 16)
	t.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	t.add_theme_color_override(&"font_color", ink)
	head.add_child(t)
	v.add_child(head)
	for m in missing:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var l := MenuScreen.label("✕  " + String(m), &"Label", 15)
		l.add_theme_color_override(&"font_color", ink)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var def_id := build_link(String(m))
		var def := BaseDB.get_building(def_id) if def_id != &"" else null
		if def != null and UI.has_screen(&"build"):
			var b := Button.new()
			b.flat = true
			b.text = "%s 짓기 ›" % def.display_name
			b.focus_mode = Control.FOCUS_ALL
			b.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
			b.add_theme_font_size_override(&"font_size", 15)
			for c in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
				b.add_theme_color_override(c, link_ink)
			b.pressed.connect(func() -> void: UI.open(&"build", {"def": def_id}))
			row.add_child(b)
		v.add_child(row)
	return p


## Resident detail: why a married couple cannot welcome a child yet (null when nothing is missing).
static func detail_lack_box(id: StringName) -> Control:
	var partner := Colony.partner_of(id)
	if partner == &"" or Colony.relation_stage(id, partner) != &"married" or Colony.is_pregnant(id) or Colony.is_pregnant(partner):
		return null
	var st := Colony.child_arrival_status(id, partner)
	if st.get("ok", false):
		return null
	return lack_box("아이 맞이", st.get("missing", []), false)
