extends Node
## #125 parts 1·2·5: prejudice_choice, child_wish, child_naming and wedding_prep open by id and act
## only through the Colony API (C-14 wedding, C-15 children, C-16 prejudice chain); the night event
## shows prejudice_talk fragments and offers wedding prep after a proposal; ResidentEventFlow opens
## one waiting screen at a time. Some Colony internals are used only to stage state (no public way
## to force a rumor, wish or birth today). Called by tests/run_tests.gd. Restores Economy, Colony,
## GameState afterwards.


func run() -> bool:
	var snap := {"economy": JSON.from_native(Economy.save_data()), "colony": JSON.from_native(Colony.save_data()),
		"game": JSON.from_native(GameState.save_data())}
	var flow_state := GameState.flow_state
	UI.close_all()
	var ok := true
	ok = _test_registered() and ok
	ok = await _test_prejudice() and ok
	ok = await _test_child_wish() and ok
	ok = await _test_naming() and ok
	ok = await _test_wedding() and ok
	ok = await _test_night_fragments() and ok
	ok = await _test_flow() and ok
	UI.close_all()
	UI.resident_events.auto_open = null
	await get_tree().process_frame
	ok = _expect(not get_tree().paused, "closing the event screens unpauses") and ok
	GameState.flow_state = flow_state
	Economy.load_data(JSON.to_native(snap.economy))
	Colony.load_data(JSON.to_native(snap.colony))
	GameState.load_data(JSON.to_native(snap.game))
	return ok


func _fresh() -> void:
	UI.close_all()
	Economy.load_data({})
	Colony.load_data({})
	GameState.load_data({"day": 30})
	Economy.set_cap_bonus(1000)
	Economy.apply({&"food": 200})


func _build(def_id: StringName) -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, &"front_yard", false)
	Colony.complete_building(uid)
	return uid


## A married couple in their family house with an infirmary. `birth` = one of them can give birth.
func _family(birth: bool) -> Array:
	var a := Colony.add_resident({"name": "가", "gender": "female" if birth else "male"})
	var b := Colony.add_resident({"name": "나", "gender": "male"})
	var house := _build(&"family_house")
	_build(&"infirmary")
	Colony.add_relation(a, b, 85)
	var m := Colony._relation_meta(a, b)
	m["flags"] = [Enums.RelationFlag.MARRIED]
	m["house_uid"] = house
	Colony._move_into_house([a, b], house)
	for id in [a, b]:
		Colony.residents[id]["morale"] = 70
	return [a, b, m]


func _test_registered() -> bool:
	var ok := true
	for id in [&"prejudice_choice", &"child_wish", &"child_naming", &"wedding_prep"]:
		ok = _expect(UI.has_screen(id), "screen '%s' is registered in data/ui/screens" % id) and ok
	return _expect(UI.resident_events is ResidentEventFlow, "UI has the ResidentEventFlow child") and ok


func _test_prejudice() -> bool:
	_fresh()
	var target := Colony.add_resident({"name": "흔적", "traits": [&"monster_mark"],
		"story": {"background": "", "fragments": ["조각 하나", "조각 둘"], "requests": []}})
	var holder := Colony.add_resident({"name": "편견", "traits": [&"prejudiced"]})
	Colony._start_rumor(target, [holder] as Array[StringName], [])
	var ok := _expect(ResidentEventFlow.rumor_queue() == [target], "the rumor waits for an answer")
	ok = _expect(ResidentEventFlow.detail_lines(target).any(func(l: Array) -> bool: return String(l[0]).contains("고를 차례")),
		"resident detail shows the chain step in words") and ok
	UI.open(&"prejudice_choice")
	await get_tree().process_frame
	var s := UI.get_screen(&"prejudice_choice")
	var box: DialogBox = s.get(&"dialog")
	ok = _expect(s.get(&"resident_id") == target, "without args it takes the oldest rumor") and ok
	ok = _expect(box.choice_ids() == PrejudiceRules.CHOICES, "three choices: defend / watch / separate: %s" % [box.choice_ids()]) and ok
	ok = _expect(box.layout == DialogBox.Layout.CENTER and box.primary_choice() == 0,
		"centred dialogue, one yellow ring on the choice to press now") and ok
	var band: StepBand = s.get(&"band")
	ok = _expect(band.visible and band.steps == ResidentEventFlow.PREJUDICE_STEPS and band.state_of(0) == &"done"
		and band.state_of(1) == &"now", "step band 소문 ✓ → 선택 (now)") and ok
	var trust := int(Colony.get_resident(target).trust)
	ok = _expect(box.pick(PrejudiceRules.CHOICE_DEFEND), "defend can be picked") and ok
	var chain := Colony.prejudice_chain(target)
	ok = _expect(chain.step == PrejudiceRules.STEP_WAITING and chain.choice == PrejudiceRules.CHOICE_DEFEND,
		"the answer goes through Colony.choose_prejudice_response") and ok
	ok = _expect(int(Colony.get_resident(target).trust) > trust, "defending raised trust (Colony)") and ok
	ok = _expect(box.choice_ids() == [&"close"] and box.note_box.get_child_count() >= 2, "after the answer: notes and one way out") and ok
	ok = _expect(ResidentEventFlow.detail_lines(target).any(func(l: Array) -> bool: return String(l[0]).contains("감싸 주기로")),
		"detail line shows the choice") and ok
	ok = _expect(ResidentEventFlow.detail_lines(holder).any(func(l: Array) -> bool: return String(l[0]).begins_with("▲ 편견")),
		"the holder's detail says who they hold the prejudice about") and ok
	box.pick(&"close")
	await get_tree().process_frame
	return _expect(not UI.is_open(&"prejudice_choice"), "close closes it") and ok


func _test_child_wish() -> bool:
	_fresh()
	var f := _family(true)
	var a: StringName = f[0]
	var b: StringName = f[1]
	(f[2] as Dictionary)["wish_day"] = GameState.day
	var ok := _expect(ResidentEventFlow.pending(ResidentEventFlow.WISH), "a wish is waiting")
	ok = _expect(ResidentEventFlow.detail_buttons(a).any(func(x: Array) -> bool: return x[1] == &"child_wish"),
		"resident detail offers the talk") and ok
	UI.open(&"child_wish", {"a": a, "b": b})
	await get_tree().process_frame
	var s := UI.get_screen(&"child_wish")
	var box: DialogBox = s.get(&"dialog")
	ok = _expect(box.choice_ids() == [&"now", &"later"], "first 지금 / 나중에: %s" % [box.choice_ids()]) and ok
	box.pick(&"now")
	ok = _expect(box.choice_ids() == [&"birth", &"adoption", &"back"], "then only the methods Colony sent: %s" % [box.choice_ids()]) and ok
	box.pick(&"birth")
	ok = _expect(Colony.is_pregnant(a) and Colony.child_wishes().is_empty(), "출산 goes through Colony.answer_child_wish") and ok
	ok = _expect((s.get(&"band") as StepBand).current == 1, "band: 바람 ✓ → 맞이") and ok
	var notes := _note_texts(box)
	ok = _expect(notes.any(func(t: String) -> bool: return t.contains("%d일차" % (GameState.day + ChildRules.BIRTH_DAYS))),
		"the due day from Colony's result is shown: %s" % [notes]) and ok
	ok = _expect(notes.any(func(t: String) -> bool: return t.contains(Colony.sortie_block_reason(a))) , "the sortie block reason is shown") and ok
	ok = _expect(ResidentEventFlow.detail_lines(a).any(func(l: Array) -> bool: return String(l[0]).contains("아기를 기다리는")),
		"detail: waiting for the baby") and ok
	UI.close(&"child_wish")
	# Two men: adoption only, and the missing conditions are shown as words.
	_fresh()
	var g := _family(false)
	(g[2] as Dictionary)["wish_day"] = GameState.day
	Colony.residents[g[0]]["morale"] = 30
	UI.open(&"child_wish", {"a": g[0], "b": g[1]})
	await get_tree().process_frame
	s = UI.get_screen(&"child_wish")
	box = s.get(&"dialog")
	box.pick(&"now")
	ok = _expect(box.choice_ids() == [&"adoption", &"back"], "a family that cannot give birth sees adoption only") and ok
	var miss: Array = Colony.child_arrival_status(g[0], g[1]).missing
	ok = _expect(not miss.is_empty() and _texts(s.get(&"column")).any(func(t: String) -> bool: return t.contains(String(miss[0]))),
		"why the family cannot welcome a child is written in the card: %s" % [miss]) and ok
	var lack := ResidentEventFlow.detail_lack_box(g[0])
	ok = _expect(lack != null and _texts(lack).any(func(t: String) -> bool: return t.contains(String(miss[0])))
		and _texts(lack).any(func(t: String) -> bool: return t.begins_with("아이 맞이 · ")),
		"and in the resident detail, in the teal 'still lacks' box") and ok
	var food_gap: Control = ResidentEventFlow.lack_box("아이 맞이", ["의무실 필요"])
	ok = _expect(_texts(food_gap).has("아이 맞이 · 기지가 아직 못 갖춘 것")
		and _buttons(food_gap).any(func(bt: Button) -> bool: return bt.text.ends_with("짓기 ›")),
		"a missing building reads as what the base lacks, with a build link") and ok
	food_gap.free()
	if lack != null:
		lack.free()
	box.pick(&"back")
	box.pick(&"later")
	ok = _expect(Colony.child_wishes().is_empty() and box.choice_ids() == [&"close"], "나중에 answers 'later' (Colony)") and ok
	UI.close(&"child_wish")
	await get_tree().process_frame
	return ok


func _test_naming() -> bool:
	_fresh()
	var f := _family(true)
	var m: Dictionary = f[2]
	m["carrier"] = f[0]
	var child: StringName = Colony._birth(m)
	var ok := _expect(ResidentEventFlow.naming_queue() == [child] and ResidentEventFlow.welcome_queue().is_empty(),
		"a newborn gets 이름 짓기, not the adult 입주 의식")
	UI.open(&"child_naming")
	await get_tree().process_frame
	var s := UI.get_screen(&"child_naming")
	ok = _expect(s.get(&"resident_id") == child and s.get(&"step") == 0, "it takes the waiting child") and ok
	ok = _expect((s.get(&"_band") as StepBand).steps == ResidentEventFlow.CHILD_STEPS and (s.get(&"_band") as StepBand).current == 2,
		"band: 바람 ✓ 맞이 ✓ → 이름 짓기") and ok
	ok = _expect(not s.call(&"save_name", "") and String(s.get(&"_error")) != "", "an empty name shows Colony's reason") and ok
	ok = _expect(s.call(&"save_name", "하람") and Colony.get_resident(child).name == "하람" and s.get(&"step") == 1,
		"Colony.name_child saves the name, then 맞이하기") and ok
	s.call(&"welcome_child")
	await get_tree().process_frame
	ok = _expect(not Colony.get_resident(child).arrival_pending and not UI.is_open(&"child_naming"),
		"맞이하기 = Colony.complete_arrival, then it closes") and ok
	return ok


func _test_wedding() -> bool:
	_fresh()
	Economy.load_data({})
	var a := Colony.add_resident({"name": "연인 하나"})
	var b := Colony.add_resident({"name": "연인 둘"})
	Colony.add_relation(a, b, 85)
	Colony._set_lovers(a, b, 1)
	var ok := _expect(ResidentEventFlow.wedding_state(Colony.wedding_status(a, b)) == &"none", "not engaged yet")
	ok = _expect(not ResidentEventFlow.detail_buttons(a).any(func(x: Array) -> bool: return x[1] == &"wedding_prep"),
		"no wedding button before the proposal") and ok
	Colony._apply_night_event({"event_id": &"proposal", "participants": [a, b], "choices": [&"watch"], "night_day": 30}, &"")
	ok = _expect(ResidentEventFlow.wedding_state(Colony.wedding_status(a, b)) == &"open", "engaged after the proposal") and ok
	UI.open(&"wedding_prep", {"resident_id": a})
	await get_tree().process_frame
	var s := UI.get_screen(&"wedding_prep")
	var box: DialogBox = s.get(&"dialog")
	ok = _expect(s.get(&"b") == b, "the partner comes from Colony.partner_of") and ok
	ok = _expect(box.choice_button(&"prepare") != null and box.choice_button(&"prepare").disabled, "prepare is disabled while something is missing") and ok
	var texts := _texts(s.get(&"column"))
	ok = _expect(texts.any(func(t: String) -> bool: return t.contains("식량 20")) and texts.any(func(t: String) -> bool: return t.contains("가족 숙소")),
		"the card lists the cost with names and the family house: %s" % [texts]) and ok
	ok = _expect(_buttons(s.get(&"column")).any(func(bt: Button) -> bool: return bt.text.contains("짓기 ›")),
		"what is missing links to the build screen") and ok
	ok = _expect((s.get(&"band") as StepBand).current == 0, "band: 조건 (now)") and ok
	var link: Button = _buttons(s.get(&"column")).filter(func(bt: Button) -> bool: return bt.text.contains("짓기 ›"))[0]
	link.pressed.emit()
	await get_tree().process_frame
	var bs := UI.get_screen(&"build")
	ok = _expect(bs != null and bs.get(&"_sel") == &"family_house" and int(bs.get(&"_cat")) >= 0,
		"the link opens the build screen on the family house, in its tab") and ok
	UI.close(&"build")
	await get_tree().process_frame
	Economy.set_cap_bonus(1000)
	Economy.apply({&"food": 25, &"cloth": 5})
	_build(&"family_house")
	UI.open(&"wedding_prep", {"a": a, "b": b})
	await get_tree().process_frame
	ok = _expect(box.pick(&"prepare"), "prepare is enabled when everything is there") and ok
	ok = _expect(ResidentEventFlow.wedding_state(Colony.wedding_status(a, b)) == &"ready" and Economy.get_amount(&"food") == 5,
		"Colony.prepare_wedding paid and kept the house") and ok
	ok = _expect(_note_texts(box).any(func(t: String) -> bool: return t.contains("다음 밤")), "says the wedding is the next night") and ok
	UI.close(&"wedding_prep")
	await get_tree().process_frame
	return ok


func _test_night_fragments() -> bool:
	_fresh()
	var target := Colony.add_resident({"name": "흔적", "traits": [&"monster_mark"],
		"story": {"background": "", "fragments": ["첫 조각", "둘째 조각"], "requests": []}})
	var holder := Colony.add_resident({"name": "편견", "traits": [&"prejudiced"]})
	Colony._start_rumor(target, [holder] as Array[StringName], [])
	Colony.choose_prejudice_response(target, PrejudiceRules.CHOICE_WATCH)
	Colony.prejudice_chains_data[target]["step"] = PrejudiceRules.STEP_INCIDENT
	Colony.night_queue = [{"event_id": &"prejudice_talk", "participants": [holder, target] as Array[StringName],
		"choices": [&"watch"], "night_day": 30}]
	UI.open(&"night_event")
	await get_tree().process_frame
	var box: DialogBox = UI.get_screen(&"night_event").get(&"dialog")
	box.pick(&"watch")
	var ok := _expect(box.line_label.text == "첫 조각" and &"more" in box.choice_ids(), "prejudice_talk shows the revealed fragments one by one")
	box.pick(&"more")
	ok = _expect(box.line_label.text == "둘째 조각" and not &"more" in box.choice_ids(), "the last fragment ends the story") and ok
	ok = _expect(Colony.prejudice_chain(target).step == PrejudiceRules.STEP_RESOLVED, "Colony resolved the chain") and ok
	UI.close(&"night_event")
	# Proposal: the result offers 결혼식 준비 보기.
	_fresh()
	var a := Colony.add_resident({"name": "하나"})
	var b := Colony.add_resident({"name": "둘"})
	Colony.add_relation(a, b, 85)
	Colony._set_lovers(a, b, 1)
	Colony.night_queue = [{"event_id": &"proposal", "participants": [a, b] as Array[StringName], "choices": [&"watch"], "night_day": 30}]
	UI.open(&"night_event")
	await get_tree().process_frame
	box = UI.get_screen(&"night_event").get(&"dialog")
	box.pick(&"watch")
	ok = _expect(&"wedding" in box.choice_ids(), "after a proposal the night event offers wedding prep: %s" % [box.choice_ids()]) and ok
	box.pick(&"wedding")
	await get_tree().process_frame
	ok = _expect(UI.top() == &"wedding_prep", "it opens wedding_prep on top") and ok
	UI.close_all()
	await get_tree().process_frame
	return ok


func _test_flow() -> bool:
	_fresh()
	var f := _family(true)
	var m: Dictionary = f[2]
	m["carrier"] = f[0]
	Colony._birth(m)
	m["wish_day"] = GameState.day
	var flow: ResidentEventFlow = UI.resident_events
	flow.auto_open = true
	GameState.flow_state = Enums.FlowState.EVENING
	flow.kick()
	await get_tree().process_frame
	await get_tree().process_frame
	var ok := _expect(UI.top() == &"child_naming" and not UI.is_open(&"child_wish"), "one screen at a time, naming first")
	UI.close(&"child_naming")
	await get_tree().process_frame
	await get_tree().process_frame
	ok = _expect(UI.top() == &"child_wish", "closing it opens the next waiting one") and ok
	UI.close(&"child_wish")
	await get_tree().process_frame
	await get_tree().process_frame
	ok = _expect(flow.next_screen() == &"", "skipped screens do not come back the same day") and ok
	GameState.flow_state = Enums.FlowState.FIELD
	GameState.day += 1
	ok = _expect(not flow.call(&"_can_open"), "nothing opens in the field") and ok
	UI.open(&"welcome")
	GameState.flow_state = Enums.FlowState.EVENING
	ok = _expect(flow.next_screen() == &"", "it waits while the welcome screen is open") and ok
	UI.close_all()
	ok = _expect(flow.next_screen() == &"child_naming", "the next day it comes back") and ok
	flow.auto_open = null
	await get_tree().process_frame
	UI.close_all()
	return ok


func _buttons(n: Node) -> Array:
	var out: Array = []
	if n is Button:
		out.append(n)
	for c in n.get_children():
		out.append_array(_buttons(c))
	return out


func _note_texts(box: DialogBox) -> Array:
	var out: Array = []
	for chip in box.note_box.get_children():
		out.append_array(_texts(chip))
	return out


func _texts(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		out.append_array(_texts(c))
	return out


func _expect(cond: bool, msg: String) -> bool:
	if not cond:
		push_error("test_resident_events: " + msg)
	return cond
