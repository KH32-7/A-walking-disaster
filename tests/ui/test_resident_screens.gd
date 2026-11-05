extends Node
## D-13: talk, gift, night event, relation map and 입주 의식 screens open by id and act only through
## the Colony API (C-12 trust, C-13 arrival, C-14 night events and relations).
## Called by tests/run_tests.gd. Restores Economy, Colony and GameState afterwards.


func run() -> bool:
	var snap := {"economy": JSON.from_native(Economy.save_data()), "colony": JSON.from_native(Colony.save_data()),
		"game": JSON.from_native(GameState.save_data())}
	UI.close_all()
	var ok := true
	ok = _test_registered() and ok
	_setup()
	ok = await _test_dialog() and ok
	ok = await _test_gift() and ok
	ok = await _test_night_event() and ok
	ok = await _test_relations() and ok
	ok = await _test_welcome() and ok
	ok = await _test_residents_buttons() and ok
	UI.close_all()
	await get_tree().process_frame
	ok = _expect(not get_tree().paused, "closing the resident screens unpauses") and ok
	Economy.load_data(JSON.to_native(snap.economy))
	Colony.load_data(JSON.to_native(snap.colony))
	GameState.load_data(JSON.to_native(snap.game))
	return ok


var _a: StringName
var _b: StringName
var _c: StringName


func _setup() -> void:
	Economy.load_data({})
	Colony.load_data({})
	GameState.load_data({"day": 7})
	Economy.set_cap_bonus(1000)
	Economy.apply({&"parts": 3, &"wood": 10, &"food": 5})
	_a = Colony.add_resident({"id": &"t_mech", "name": "테스트 정비공", "likes": [&"engine_parts"], "dislikes": [&"stairs"],
		"story": {"background": "정비공", "fragments": ["조각 하나"]}})
	_b = Colony.add_resident({"id": &"t_cook", "name": "테스트 요리사", "likes": [&"sweet_food"]})
	_c = Colony.add_resident({"id": &"t_guard", "name": "테스트 경비"})
	Colony.add_relation(_a, _b, 40)   # 친구
	Colony.add_relation(_b, _c, -60)  # 앙숙


func _test_registered() -> bool:
	var ok := true
	for id in [&"dialog", &"gift", &"night_event", &"relations", &"welcome"]:
		ok = _expect(UI.has_screen(id), "screen '%s' is registered in data/ui/screens" % id) and ok
	return ok


func _test_dialog() -> bool:
	UI.open(&"dialog", {"resident_id": _a})
	await get_tree().process_frame
	var s := UI.get_screen(&"dialog")
	var ok := _expect(s is ResidentSceneScreen and get_tree().paused, "dialog opens as a scene-type screen and pauses")
	var box: DialogBox = s.get(&"dialog")
	ok = _expect(box.choice_ids().size() <= DialogBox.MAX_CHOICES and &"talk" in box.choice_ids(),
		"at most three choices, talk among them: %s" % [box.choice_ids()]) and ok
	ok = _expect(box.line_label.max_lines_visible == 2 and box.line_label.text != "", "the line is shown, two lines at most") and ok
	var before := int(Colony.get_resident(_a).trust)
	ok = _expect(box.pick(&"talk"), "talk can be picked") and ok
	ok = _expect(int(Colony.get_resident(_a).trust) > before, "talking goes through Colony.talk (trust up)") and ok
	ok = _expect(not &"talk" in box.choice_ids(), "after talking, talk is no longer offered") and ok
	ok = _expect(not Colony.trust_actions(_a).talk, "Colony counts today's talk") and ok
	var notes: Array = s.call(&"trust_notes", 18, 21)
	ok = _expect(notes.size() == 2 and String(notes[0][0]).contains("+3") and String(notes[1][0]).contains("경계 풀림"),
		"trust notes show the change and a new stage in words: %s" % [notes]) and ok
	box.pick(&"bye")
	await get_tree().process_frame
	return _expect(not UI.is_open(&"dialog"), "bye closes the dialog") and ok


func _test_gift() -> bool:
	UI.open(&"gift", {"resident_id": _a})
	await get_tree().process_frame
	var s := UI.get_screen(&"gift")
	var ids: Array = s.call(&"gift_ids")
	var ok := _expect(&"parts" in ids and &"wood" in ids, "storage resources in stock are listed: %s" % [ids])
	ok = _expect(not s.call(&"known_liked", &"parts"), "likes are not revealed before the player learns them") and ok
	s.set(&"_sel", &"parts")
	var res: Dictionary = s.call(&"give")
	ok = _expect(res.get("ok", false) and res.reaction == &"liked", "giving parts goes through Colony.give_gift (liked)") and ok
	ok = _expect(Economy.get_amount(&"parts") == 2, "one part left storage") and ok
	ok = _expect(s.call(&"known_liked", &"parts"), "a liked gift is marked from now on") and ok
	var btn: Button = s.get(&"_give_button")
	ok = _expect(btn != null and btn.disabled, "a second gift today is blocked") and ok
	var box: DialogBox = s.get(&"dialog")
	var marks := ""
	for c in box.note_box.get_children():
		marks += (c.get_child(0) as Label).text
	ok = _expect(marks.contains("▲") and marks.contains("좋아해요"), "the reaction has a shape mark and words, not only colour") and ok
	UI.close(&"gift")
	await get_tree().process_frame
	return ok


func _test_night_event() -> bool:
	Colony.night_queue = [{"event_id": &"quarrel", "participants": [_b, _c] as Array[StringName],
		"choices": [&"watch", &"mediate"], "night_day": 7}]
	UI.open(&"night_event")
	await get_tree().process_frame
	var s := UI.get_screen(&"night_event")
	var box: DialogBox = s.get(&"dialog")
	var ok := _expect(Colony.pending_night_events().size() == 1, "opening the scene does not start the event yet")
	ok = _expect(box.choice_ids() == ([&"watch", &"mediate"] as Array[StringName]), "the event's choices are offered: %s" % [box.choice_ids()]) and ok
	ok = _expect(not get_tree().paused, "the night event does not pause the base") and ok
	var before := Colony.relation(_b, _c)
	box.pick(&"mediate")
	var result: Dictionary = s.get(&"_result")
	ok = _expect(Colony.pending_night_events().is_empty() and result.get("choice", &"") == &"mediate",
		"picking resolves through Colony with that choice") and ok
	ok = _expect(Colony.relation(_b, _c) != before, "the relation changed (화해 or 다툼)") and ok
	ok = _expect(box.choice_ids() == ([&"end"] as Array[StringName]), "with nothing left, the scene offers to end the night") and ok
	box.pick(&"end")
	await get_tree().process_frame
	return _expect(not UI.is_open(&"night_event"), "ending closes the scene") and ok


func _test_relations() -> bool:
	UI.open(&"relations", {"id": _b})
	await get_tree().process_frame
	var s := UI.get_screen(&"relations")
	var data: Array = s.call(&"graph_data")
	var edges: Array = data[1]
	var ok := _expect((data[0] as Array).size() == 3, "every resident is a dot")
	ok = _expect(edges.size() >= 2, "each pair is one line: %s" % [edges]) and ok
	var stages := {}
	for e: Dictionary in edges:
		stages["%s|%s" % [e.a, e.b]] = e.stage
		stages["%s|%s" % [e.b, e.a]] = e.stage
	ok = _expect(stages.get("%s|%s" % [_a, _b]) == Colony.relation_stage(_a, _b) and stages.get("%s|%s" % [_b, _c]) == &"rival",
		"line stages come from Colony.relation_stage") and ok
	for st: StringName in RelationGraph.STAGE_ORDER:
		ok = _expect(RelationGraph.stage_name(st) != String(st), "stage %s has a name in the legend" % st) and ok
	var g: RelationGraph = s.get(&"_graph")
	ok = _expect(g.selected == _b, "open_with selects the resident") and ok
	UI.close(&"relations")
	await get_tree().process_frame
	return ok


func _test_welcome() -> bool:
	var n := Colony.add_resident({"id": &"t_new", "name": "테스트 새 식구", "likes": [&"tea"], "arrival_pending": true,
		"story": {"background": "옥상에서 버팀", "first_line": "여기 사람 있어요?"}})
	UI.open(&"welcome")
	await get_tree().process_frame
	var s := UI.get_screen(&"welcome")
	var ok := _expect(s.get(&"resident_id") == n, "without an id the oldest pending arrival is taken")
	var box: DialogBox = s.get(&"dialog")
	ok = _expect(box.line_label.text.begins_with("고마워요") and box.line_label.text.contains("테스트 새 식구"),
		"one line: thanks and who they are (%s)" % box.line_label.text) and ok
	var notes := box.note_box.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	ok = _expect(notes.has("옥상에서 버팀") and notes.has("좋아하는 것: 차"), "story and the first like as notes: %s" % [notes]) and ok
	ok = _expect(Colony.get_resident(n).arrival_pending, "nothing is decided before 반가워요") and ok
	s.call(&"_on_choice", &"hello")
	await get_tree().process_frame
	ok = _expect(not Colony.get_resident(n).arrival_pending and &"tea" in Colony.known_likes(n),
		"반가워요 completes the arrival in Colony and tells the like") and ok
	return _expect(not UI.is_open(&"welcome"), "the last newcomer's 반가워요 closes the screen") and ok


func _test_residents_buttons() -> bool:
	UI.open(&"resident_detail", {"id": _a})
	await get_tree().process_frame
	var s := UI.get_screen(&"resident_detail")
	var texts := []
	for b in s.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	var ok := _expect(texts.any(func(t: String) -> bool: return t.begins_with("대화")) and texts.has("관계도"),
		"resident detail links to talk and the relation map: %s" % [texts])
	var talk: Button = null
	for b in s.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("대화"):
			talk = b
	ok = _expect(talk != null and not talk.disabled, "the talk button is live") and ok
	if talk != null:
		talk.pressed.emit()
		await get_tree().process_frame
	ok = _expect(UI.top() == &"dialog", "talk opens the dialog screen") and ok
	UI.close_all()
	await get_tree().process_frame
	return ok


func _expect(cond: bool, msg: String) -> bool:
	if not cond:
		push_error("test_resident_screens: " + msg)
	return cond
