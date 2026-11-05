extends MenuScreen
## Night event scene (D-13). Owner: Lane D. Design 08 "밤 이벤트", 14 "대화·이벤트".
## Plays tonight's events one by one (C-14): shows the next queued event (Colony.pending_night_events),
## and when the player picks a choice calls Colony.next_night_event() (router → NIGHT_EVENT,
## night_event_started) and Colony.resolve_night_event(choice) (router → NIGHT). The outcome text,
## story fragment and relation change come from Colony's result. Nothing changes until a choice is
## picked, so an unplayed event is still resolved by Colony in the morning.
## Opened by UI when Colony.night_events_ready fires at night; open_with({}) also works.

var _ev: Dictionary = {}
var _index := 0
var _total := 0
var _result: Dictionary = {}
var _before: Dictionary = {}  # pair key -> relation value before the choice

var _day_label: Label
var _title: Label
var _desc: Label
var _people: HBoxContainer
var dialog: DialogBox


func _init() -> void:
	show_back = false
	title_text = ""
	footer_keys = [["1~3", "고르기"]]
	header_resources = []


func open_with(_args: Dictionary) -> void:
	if dialog != null and _ev.is_empty():
		_begin()


func _build_body(b: Control) -> void:
	var night := ColorRect.new()
	night.color = Color(UiTokens.INK, 0.62)
	night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	night.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(night)
	move_child(night, backdrop.get_index() + 1)
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.62, 0.25, 0.30), Color(1.0, 0.55, 0.2, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.62)
	gt.fill_to = Vector2(0.5, 0.0)
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)
	move_child(glow, night.get_index() + 1)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override(&"separation", 6)
	b.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_day_label = MenuScreen.label("", &"LabelDim", 16)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_day_label)
	_title = MenuScreen.label("", &"LabelTitle", 40)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_title)
	_desc = MenuScreen.label("", &"LabelDim", 15)
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_desc)
	_people = HBoxContainer.new()
	_people.alignment = BoxContainer.ALIGNMENT_CENTER
	_people.add_theme_constant_override(&"separation", 18)
	_people.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_people.offset_top = 150
	_people.offset_bottom = 520
	b.add_child(_people)
	dialog = DialogBox.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dialog.offset_top = -330
	dialog.offset_bottom = 0
	add_child(dialog)
	move_child(dialog, body.get_index() + 1)  # under the footer key hints
	dialog.choice_made.connect(_on_choice)
	EventBus.flow_state_changed.connect(_on_flow_state_changed)
	_begin()


## Morning came (잠자기): Colony resolved what was left, so the scene ends.
func _on_flow_state_changed(state: Enums.FlowState) -> void:
	if state == Enums.FlowState.BASE_MORNING and is_inside_tree():
		close()


func _begin() -> void:
	_index = 0
	_total = Colony.pending_night_events().size()
	_next()


## Shows the next queued event (does not start it yet). Closes when nothing is left.
func _next() -> void:
	var queued := Colony.pending_night_events()
	_result = {}
	if queued.is_empty():
		_ev = {}
		_title.text = "조용한 밤"
		_day_label.text = "%d일차 밤" % GameState.day
		_desc.text = ""
		MenuScreen.clear(_people)
		dialog.say("", "오늘 밤은 별일 없이 지나간다.")
		dialog.set_notes([])
		dialog.set_choices([[&"end", "밤을 보낸다"]])
		return
	_ev = queued[0]
	_index += 1
	_total = maxi(_total, _index + queued.size() - 1)
	var def := BaseDB.get_night_event(StringName(_ev.event_id))
	_day_label.text = "%d일차 밤  ·  %d / %d" % [GameState.day, _index, _total]
	_title.text = def.display_name if def != null else String(_ev.event_id)
	_desc.text = def.description if def != null else ""
	_before = {}
	var who: Array = _ev.get("participants", [])
	for i in who.size():
		for j in range(i + 1, who.size()):
			_before[_key(who[i], who[j])] = Colony.relation(who[i], who[j])
	_draw_people({})
	dialog.say("", ResidentText.night_intro(StringName(_ev.event_id), who))
	dialog.set_notes([])
	var choices: Array = []
	for c in _ev.get("choices", []):
		choices.append([StringName(c), ResidentText.choice_name(StringName(c))])
	if choices.is_empty():
		choices.append([&"watch", ResidentText.choice_name(&"watch")])
	dialog.set_choices(choices)


## Portrait cards with the relation stage line between neighbours; deltas after the outcome.
func _draw_people(deltas: Dictionary) -> void:
	MenuScreen.clear(_people)
	var who: Array = _ev.get("participants", [])
	for i in who.size():
		if i > 0:
			_people.add_child(_link(who[i - 1], who[i], deltas))
		var card := VBoxContainer.new()
		card.add_theme_constant_override(&"separation", 8)
		var p := ResidentPortrait.new(Vector2(230, 270))
		card.add_child(p)
		p.set_resident(StringName(who[i]))
		var nm := MenuScreen.label(ResidentText.call_name(Colony.get_resident(StringName(who[i]))), &"LabelSection", 20)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(nm)
		_people.add_child(card)


func _link(a: StringName, b: StringName, deltas: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override(&"separation", 4)
	v.custom_minimum_size = Vector2(150, 270)
	var stage := Colony.relation_stage(a, b)
	var s := RelationGraph.LineSample.new(stage)
	s.custom_minimum_size = Vector2(150, 26)
	v.add_child(s)
	var l := MenuScreen.label(RelationGraph.stage_name(stage), &"LabelHud", 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var key := _key(a, b)
	if deltas.has(key) and int(deltas[key]) != 0:
		var d := int(deltas[key])
		var dl := MenuScreen.label(("▲ 관계 +%d" if d > 0 else "▼ 관계 %d") % d, &"LabelHud", 15)
		dl.add_theme_color_override(&"font_color", UiTokens.GOOD if d > 0 else UiTokens.WARN)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(dl)
	return v


func _on_choice(id: StringName) -> void:
	match id:
		&"next":
			_next()
		&"end":
			close()
		_:
			if _ev.is_empty() or not _result.is_empty():
				return
			Colony.next_night_event()
			_result = Colony.resolve_night_event(id)
			_show_result()


func _show_result() -> void:
	var deltas := {}
	var who: Array = _ev.get("participants", [])
	for key: String in _before:
		var pair := key.split("|")
		deltas[key] = Colony.relation(StringName(pair[0]), StringName(pair[1])) - int(_before[key])
	_draw_people(deltas)
	var notes: Array = []
	if _result.has("mediated"):
		notes.append(["● 화해했어요", UiTokens.GOOD] if _result.mediated else ["✕ 말리지 못했어요", UiTokens.WARN])
	var text := String(_result.get("text", ""))
	if text == "" and _result.get("skipped", false):
		text = "%s 중 누군가 자리에 없어 지나갔다." % ResidentText.names_of(who)
	var frag: Dictionary = _result.get("fragment", {})
	if not frag.is_empty():
		notes.append([text, UiTokens.TEXT])
		notes.append(["◆ 사연 한 조각", UiTokens.ACCENT])
		var r := Colony.get_resident(StringName(frag.resident_id))
		dialog.say(ResidentText.call_name(r), String(frag.text), StringName(frag.resident_id))
	else:
		dialog.say("", text)
	dialog.set_notes(notes)
	if Colony.pending_night_events().is_empty():
		dialog.set_choices([[&"end", "밤을 보낸다"]])
	else:
		dialog.set_choices([[&"next", "다음 일 보기"]])


static func _key(a: Variant, b: Variant) -> String:
	return "%s|%s" % [a, b]
