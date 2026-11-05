extends ResidentEventScreen
## 아이 맞이 대화 (#125 part 2, C-15). Owner: Lane D. Design 08 "아이 맞이".
## Opens on Colony.child_wish (ResidentEventFlow) and walks Colony.child_wishes() one family at a
## time. First "지금 / 나중에", then the way (only the methods Colony sent: 출산 / 입양), then
## Colony.answer_child_wish() answers. What happens next comes from its result (due_day, child_id,
## waiting) and Colony.sortie_block_reason(). The right card lists the ways and, from
## Colony.child_arrival_status().missing, why the family could not welcome a child right now.
## Esc = 나중에 without answering (the wish stays). open_with({"a": id, "b": id}).

var a: StringName = &""
var b: StringName = &""
var methods: Array = []
var _stage: StringName = &"ask"  # ask → method → done
var _result: Dictionary = {}


func _init() -> void:
	title_text = "아이 맞이"
	footer_keys = [["1~3", "고르기"], ["Esc", "나중에"]]
	header_resources = []


func open_with(args: Dictionary) -> void:
	a = StringName(args.get("a", &""))
	b = StringName(args.get("b", &""))
	if dialog != null:
		_start()


func _wish() -> Dictionary:
	for w: Dictionary in Colony.child_wishes():
		if (StringName(w.a) == a and StringName(w.b) == b) or (StringName(w.a) == b and StringName(w.b) == a):
			return w
	return {}


func _start() -> void:
	var w := _wish()
	if w.is_empty():
		var all := Colony.child_wishes()
		w = all[0] if not all.is_empty() else {}
	_result = {}
	_stage = &"ask"
	band.visible = not w.is_empty()
	band.set_progress(ResidentEventFlow.CHILD_STEPS, 0)
	if w.is_empty():
		a = &""
		b = &""
		methods = []
		set_subtitle("")
		MenuScreen.clear(people)
		dialog.say("", "아이를 맞고 싶어 하는 가족이 없어요.")
		dialog.set_notes([])
		dialog.set_choices([[&"close", "돌아간다"]])
		_refresh_column()
		return
	a = StringName(w.a)
	b = StringName(w.b)
	resident_id = a
	methods = w.get("methods", [])
	set_subtitle("%s 가족" % ResidentText.call_name(Colony.get_resident(a)))
	draw_people([a, b])
	dialog.say(ResidentText.call_name(Colony.get_resident(a)), "우리… 아이를 맞이하면 어떨까? 여기라면 함께 키울 수 있을 것 같아.", a)
	dialog.set_notes([["◆ 아이를 맞고 싶어 해요", UiTokens.TEXT]])
	dialog.set_choices([[&"now", "지금 맞이한다"], [&"later", "나중에 생각한다", false, "다시 이야기해요"]])
	_refresh_column()


func _ask_method() -> void:
	_stage = &"method"
	dialog.say(ResidentText.call_name(Colony.get_resident(b)), "그럼 어떻게 맞이할까?", b)
	dialog.set_notes([])
	var choices: Array = []
	for m: int in methods:
		choices.append([method_choice(m), ResidentEventFlow.METHOD_NAMES.get(m, str(m)), false, method_hint(m)])
	choices.append([&"back", "이전으로"])
	dialog.set_choices(choices)


static func method_choice(m: int) -> StringName:
	return &"birth" if m == Enums.ArrivalMethod.BIRTH else &"adoption"


static func method_hint(m: int) -> String:
	if m == Enums.ArrivalMethod.BIRTH:
		return "%d일 뒤 태어나요" % ChildRules.BIRTH_DAYS
	return "보호자 없는 아이를 맞아요"


func _on_choice(id: StringName) -> void:
	match id:
		&"close":
			close()
		&"next":
			a = &""
			b = &""
			_start()
		&"back":
			_start()
		&"now":
			_ask_method()
		&"later":
			_answer(&"later", Enums.ArrivalMethod.ADOPTION)
		&"birth":
			_answer(&"now", Enums.ArrivalMethod.BIRTH)
		&"adoption":
			_answer(&"now", Enums.ArrivalMethod.ADOPTION)


func _answer(choice: StringName, method: int) -> void:
	if _stage == &"done":
		return
	var res := Colony.answer_child_wish(a, b, choice, method)
	_result = res
	var ra := Colony.get_resident(a)
	var rb := Colony.get_resident(b)
	if not res.get("ok", false):
		dialog.set_notes([["✕ " + String(res.get("reason", "")), UiTokens.WARN]])
		return
	_stage = &"done"
	# 바람 → 맞이 → 이름 짓기 → 입주: an orphan adopted now already lives here (all done).
	var arrived := choice == &"now" and StringName(res.get("child_id", &"")) != &""
	band.set_progress(ResidentEventFlow.CHILD_STEPS, ResidentEventFlow.CHILD_STEPS.size() if arrived else (1 if choice == &"now" else 0))
	var notes: Array = []
	if choice == &"later":
		dialog.say(ResidentText.call_name(ra), "그래, 조금 더 생각해 보자.", a)
		notes.append(["● 나중에 다시 이야기해요", UiTokens.TEXT_DIM])
	elif method == Enums.ArrivalMethod.BIRTH:
		dialog.say(ResidentText.call_name(rb), "열흘이면 우리 아기를 만나겠네.", b)
		notes.append(["◆ %d일차에 아기가 와요" % int(res.get("due_day", 0)), UiTokens.TEXT])
		for id in [a, b]:
			var why := Colony.sortie_block_reason(id)
			if why != "":
				notes.append(["▲ %s — %s, 출격을 쉬어요" % [ResidentText.call_name(Colony.get_resident(id)), why], UiTokens.WARN])
	elif StringName(res.get("child_id", &"")) != &"":
		var child := Colony.get_resident(StringName(res.child_id))
		dialog.say(ResidentText.call_name(ra), "오늘부터 우리 가족이야, %s." % ResidentText.call_name(child), a)
		notes.append(["● %s을(를) 맞이했어요" % ResidentText.call_name(child), UiTokens.GOOD])
	elif res.get("waiting", false):
		dialog.say(ResidentText.call_name(rb), "기다려 보자. 어딘가에 우리를 기다리는 아이가 있을 거야.", b)
		notes.append(["◆ 방송실이 보호자를 잊은 아이 소문을 기다려요", UiTokens.INFO])
	dialog.set_notes(notes)
	if Colony.child_wishes().is_empty():
		dialog.set_choices([[&"close", "돌아간다"]])
	else:
		dialog.set_choices([[&"next", "다른 가족 보기"]])
	_refresh_column()


func _refresh_column() -> void:
	if column == null:
		return
	MenuScreen.clear(column)
	var v := card()
	if a == &"":
		v.add_child(card_title("기다리는 가족이 없어요"))
		v.add_child(card_text("결혼한 가족이 조건을 갖추면, 가족이 먼저 아이 이야기를 꺼내요.", true))
		return
	v.add_child(card_text("가족", true, 14))
	v.add_child(card_title("%s · %s" % [ResidentText.call_name(Colony.get_resident(a)), ResidentText.call_name(Colony.get_resident(b))]))
	v.add_child(card_text("고를 수 있는 방식", true, 14))
	for m: int in methods:
		var detail := "%d일 뒤 태어나요. 그동안 아기를 품은 사람은 출격·경비를 쉬어요." % ChildRules.BIRTH_DAYS \
			if m == Enums.ArrivalMethod.BIRTH else "기지에 보호자 없는 아이가 있으면 바로, 없으면 방송실이 소문을 기다려요."
		v.add_child(ResidentEventScreen.mark_row("●", "%s — %s" % [ResidentEventFlow.METHOD_NAMES.get(m, str(m)), detail]))
	if _stage == &"done":
		return  # answered: the conditions now only say "already waiting"
	var st := Colony.child_arrival_status(a, b)
	var missing: Array = st.get("missing", [])
	if missing.is_empty():
		v.add_child(ResidentEventScreen.mark_row("✓", "아이를 맞을 조건을 모두 갖췄어요"))
	else:
		v.add_child(ResidentEventFlow.lack_box("아이 맞이", missing))
