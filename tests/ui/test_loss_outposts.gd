extends Node
## #125 parts 3·4·7: funeral ends with Colony.end_funeral(), the memorial visits through
## Colony.visit_memorial (night only, refusal reason shown), grief / stranded (-1 = 기한 없음) /
## missing words, the outposts screen builds · garrisons (assign_garrison) · releases (unassign_job) ·
## repairs through Colony and redraws on outposts_changed, and sortie prep refuses a resident whose
## Colony.sortie_block_reason is not empty. Called by tests/run_tests.gd. Restores what it changes.


func run() -> bool:
	var snap := {"economy": JSON.from_native(Economy.save_data()), "colony": JSON.from_native(Colony.save_data()),
		"game": JSON.from_native(GameState.save_data())}
	var flow := GameState.flow_state
	var strand_days = Settings.get_value(&"strand_days")
	var missing_before := LossText.missing_seen.duplicate()
	UI.close_all()
	var ok := true
	ok = _expect(UI.has_screen(&"funeral") and UI.has_screen(&"memorial") and UI.has_screen(&"outposts"),
		"funeral · memorial · outposts registered") and ok
	ok = _test_words() and ok
	ok = _test_funeral() and ok
	ok = _test_memorial() and ok
	ok = _test_absent() and ok
	ok = _test_outposts() and ok
	ok = _test_sortie_block() and ok
	UI.close_all()
	await get_tree().process_frame
	ok = _expect(not get_tree().paused, "closing the screens unpauses") and ok
	Settings.set_value(&"strand_days", strand_days)
	LossText.missing_seen = missing_before
	Economy.load_data(JSON.to_native(snap.economy))
	Colony.load_data(JSON.to_native(snap.colony))
	GameState.load_data(JSON.to_native(snap.game))
	GameState.flow_state = flow
	return ok


func _fresh() -> void:
	UI.close_all()
	GameState.load_data({"day": 12})
	Economy.load_data({})
	Economy.set_cap_bonus(5000)
	Colony.load_data({})
	GameState.flow_state = Enums.FlowState.BASE_STAY


func _add(name_text: String) -> StringName:
	return Colony.add_resident({"name": name_text, "age_stage": Enums.AgeStage.ADULT, "traits": [], "access_needs": []})


func _test_words() -> bool:
	var ok := _expect(LossText.strand_days(-1) == "기한 없음" and LossText.strand_days(2) == "남은 기한 2일", "stranded days words")
	ok = _expect(LossText.grief_tag({"grief_days": 3}) == "◇ 슬픔 3일" and LossText.grief_tag({"grief_days": 0}) == "", "grief tag") and ok
	ok = _expect(LossText.memorial_line({"day": 9, "cause": &"raid"}) == "9일차 · 습격으로", "memorial line") and ok
	return ok


func _test_funeral() -> bool:
	_fresh()
	var a := _add("정다온")
	var b := _add("한지호")
	Colony.add_relation(a, b, 70)
	Colony._kill(a, &"raid")
	var ok := _expect(Colony.pending_funeral() == [a], "a death queues a funeral")
	# Auto-open only inside a running scene (the runner has none).
	Colony.funeral_ready.emit(Colony.pending_funeral())
	ok = _expect(not UI.is_open(&"funeral"), "funeral does not auto-open under the test runner") and ok
	UI.open(&"funeral", {"resident_ids": Colony.pending_funeral()})
	var s = UI.get_screen(&"funeral")
	ok = _expect(s != null and s._name.text == "정다온", "funeral shows the name") and ok
	ok = _expect(s._story.text != "" and s._next.text == "보내 주기", "one story line, last page button") and ok
	ok = _expect(s._mourners.text.contains("한지호"), "the grieving are named") and ok
	s._next.pressed.emit()
	ok = _expect(not UI.is_open(&"funeral") and Colony.pending_funeral().is_empty(), "the last button ends the funeral") and ok
	return ok


func _test_memorial() -> bool:
	_fresh()
	var a := _add("정다온")
	var b := _add("한지호")
	Colony.add_relation(a, b, 70)
	Colony._kill(a, &"raid")
	Colony.end_funeral()
	UI.open(&"memorial")
	var s = UI.get_screen(&"memorial")
	var ok := _expect(s._names.get_child_count() == 1, "one name on the stone")
	ok = _expect(s._status.text.contains("추모비가 아직 없어요"), "no stone: says so") and ok
	var stone := Colony.place_building(LossRules.MEMORIAL, Vector2i(2, 8), 0, &"", false)
	Colony.complete_building(stone)
	s.refresh()
	ok = _expect(s._status.text.contains("밤에"), "daytime: visits wait for the night") and ok
	ok = _expect(_buttons_disabled(s._people), "daytime: visit buttons disabled") and ok
	GameState.flow_state = Enums.FlowState.NIGHT
	s.refresh()
	ok = _expect(_yellow_count(s._people) == 1, "night: one yellow visit button") and ok
	ok = _expect(MemorialScreen.marker_lines()[1].contains("새긴 이름 1"), "memorial world tag") and ok
	var before := int(Colony.get_resident(b)["grief_days"])
	var res: Dictionary = s.visit(b)
	ok = _expect(res.ok and int(Colony.get_resident(b)["grief_days"]) == before - 1, "visit goes through Colony (슬픔 −1일)") and ok
	res = s.visit(b)
	ok = _expect(not res.ok and String(s._notes[b]).contains(String(res.reason)), "a refused visit shows Colony's reason") and ok
	UI.close(&"memorial")
	return ok


func _yellow_count(n: Node) -> int:
	return n.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.theme_type_variation == &"ButtonPrimary").size()


func _buttons_disabled(n: Node) -> bool:
	var found := false
	for c in n.find_children("*", "Button", true, false):
		found = true
		if not (c as Button).disabled:
			return false
	return found


func _test_absent() -> bool:
	_fresh()
	var a := _add("이은비")
	var m := _add("최민")
	Settings.set_value(&"strand_days", 0)  # 보호 모드: 기한 없음
	Colony._on_companion_stranded(a, &"flooded_mall")
	Settings.set_value(&"strand_days", 1)
	Colony._on_companion_stranded(m, &"flooded_mall")
	Colony._settle_loss([])  # UI hears resident_missing → LossText.note_missing
	var rows := LossText.absent_rows()
	var texts := rows.map(func(r: Dictionary) -> String: return r.text)
	var ok := _expect(rows.size() == 2, "stranded + missing listed")
	ok = _expect(texts.any(func(t: String) -> bool: return t.contains("고립") and t.contains("기한 없음")), "-1 days → 기한 없음") and ok
	ok = _expect(texts.any(func(t: String) -> bool: return t.contains("실종")), "missing resident listed") and ok
	_add("한지호")
	UI.open(&"residents")
	var s = UI.get_screen(&"residents")
	var labels: Array = s._list.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	ok = _expect(labels.any(func(t: String) -> bool: return t.contains("△ 고립")) and labels.any(func(t: String) -> bool: return t.contains("◆ 실종")),
		"residents list shows who is away as one-line card states") and ok
	UI.close(&"residents")
	return ok


func _test_outposts() -> bool:
	_fresh()
	var a := _add("강도윤")
	var b := _add("문소라")
	var c := _add("한지호")
	UI.open(&"outposts", {"node_id": &"outpost_north"})
	var s = UI.get_screen(&"outposts")
	var ok := _expect(s._map.nodes.size() == Colony.outpost_nodes().size() and s._map.nodes.size() >= 4, "map shows every node")
	ok = _expect(not s.build(&"outpost_north"), "cannot build without resources") and ok
	ok = _expect(String(s._note).contains("자원 부족"), "the build refusal shows Colony's reasons") and ok
	Economy.apply(OutpostRules.COST)
	ok = _expect(s.build(&"outpost_north") and OutpostsScreen.state_of(s._node(s._map.nodes, &"outpost_north")) == &"building",
		"build → 짓는 중") and ok
	Colony.outposts[&"outpost_north"]["ready_day"] = GameState.day
	Colony.outposts_changed.emit()
	ok = _expect(OutpostsScreen.state_of(s._node(s._map.nodes, &"outpost_north")) == &"short", "outposts_changed redraws (주둔 부족)") and ok
	var steps := OutpostsScreen.steps_for(s._node(s._map.nodes, &"outpost_north"))
	ok = _expect(steps.size() == 3 and steps[0].state == StepBand.DONE and steps[1].state == StepBand.NOW,
		"step band: 짓기 ✓ → 주둔 (now) → 가동") and ok
	ok = _expect(_yellow_count(s._detail) == 1, "one yellow button: the first resident who can be stationed") and ok
	ok = _expect(OutpostsScreen.facility_choices(s._node(s._map.nodes, &"outpost_north"))[0].label == "주둔 배정"
		and OutpostsScreen.marker_lines(s._node(s._map.nodes, &"outpost_north"))[1] == "주둔 0/2", "[F] line and world tag text") and ok
	ok = _expect(s.station(&"outpost_north", a) and s.station(&"outpost_north", b), "two residents garrisoned") and ok
	ok = _expect(Colony.garrison_of(&"outpost_north").size() == 2 and Colony.job_of(a) == OutpostRules.GARRISON_JOB,
		"garrison goes through assign_garrison") and ok
	ok = _expect(OutpostsScreen.state_of(s._node(s._map.nodes, &"outpost_north")) == &"active", "2명 → 가동") and ok
	ok = _expect(not s.station(&"outpost_north", c), "a third resident is refused") and ok
	s.release(a)
	ok = _expect(Colony.job_of(a) == &"" and Colony.garrison_of(&"outpost_north") == [b], "release = unassign_job") and ok
	ok = _expect(OutpostsScreen.state_of(s._node(s._map.nodes, &"outpost_north")) == &"short", "release redraws") and ok
	Colony.outposts[&"outpost_north"]["damaged"] = true
	Colony.outposts_changed.emit()
	ok = _expect(OutpostsScreen.state_of(s._node(s._map.nodes, &"outpost_north")) == &"damaged", "damaged state") and ok
	ok = _expect(OutpostsScreen.steps_for(s._node(s._map.nodes, &"outpost_north"))[0].label == "수리", "broken: the first step is 수리") and ok
	ok = _expect(not s.repair(&"outpost_north"), "repair needs resources") and ok
	Economy.apply(Colony.outpost_repair_cost(&"outpost_north"))
	ok = _expect(s.repair(&"outpost_north") and not Colony.outposts[&"outpost_north"]["damaged"], "repair through Colony") and ok
	UI.close(&"outposts")
	ok = _expect(not Colony.outposts_changed.is_connected(s.refresh), "closing disconnects outposts_changed") and ok
	ok = _expect(BaseHud.MENU.any(func(m: Array) -> bool: return m[2] == &"outposts"), "base menu opens the outposts screen") and ok
	return ok


func _test_sortie_block() -> bool:
	_fresh()
	var a := _add("문소라")
	var b := _add("박서진")
	var meta: Dictionary = Colony._relation_meta(a, b)
	meta["due_day"] = GameState.day + 3
	meta["carrier"] = a
	var ok := _expect(Colony.sortie_block_reason(a) != "" and Colony.sortie_block_reason(b) == "", "fixture: only 문소라 is blocked")
	UI.open(&"sortie_prep")
	var s = UI.get_screen(&"sortie_prep")
	var blocked: Button = null
	var free: Button = null
	for btn: Button in s._right.find_children("*", "Button", true, false):
		if btn.text.contains("문소라"):
			blocked = btn
		elif btn.text.contains("박서진"):
			free = btn
	ok = _expect(blocked != null and blocked.disabled and blocked.text.contains(Colony.sortie_block_reason(a)),
		"blocked companion is disabled and shows the reason") and ok
	ok = _expect(free != null and not free.disabled, "others can still be picked") and ok
	blocked.pressed.emit()
	ok = _expect(not a in s.loadout().companions, "the blocked resident never joins the loadout") and ok
	UI.close(&"sortie_prep")
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
