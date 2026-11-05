extends Node
## Issue #125 part 6: the build screen's 개간 · 수리·레벨업 · 접근성 보기 views call Colony
## (start_clearing, assign_job construction, start_repair, upgrade_building, access_map) and show
## met / not met with a shape and words. Called by tests/run_tests.gd. Restores Economy, Colony and
## GameState afterwards.

var _screen: Node


func run() -> bool:
	var snap := {"economy": JSON.from_native(Economy.save_data()), "colony": JSON.from_native(Colony.save_data()),
		"game": JSON.from_native(GameState.save_data())}
	var tier := Colony.tier
	var ok := true
	ok = _test_reason_text() and ok
	_setup()
	ok = await _test_clear() and ok
	ok = await _test_clear_cost() and ok
	ok = await _test_repair() and ok
	ok = await _test_upgrade() and ok
	ok = await _test_access() and ok
	UI.close(&"build")
	await get_tree().process_frame
	ok = _expect(not get_tree().paused, "closing the build screen unpauses") and ok
	Economy.load_data(JSON.to_native(snap.economy))
	Colony.load_data(JSON.to_native(snap.colony))
	Colony.tier = tier
	GameState.load_data(JSON.to_native(snap.game))
	return ok


var _worker: StringName
var _wheel: StringName


func _setup() -> void:
	Economy.load_data({})
	Colony.load_data({})
	Economy.set_cap_bonus(5000)
	Colony.tier = Enums.BaseTier.CAMP
	_worker = Colony.add_resident({"id": &"test_builder", "name": "테스트 일꾼", "age_stage": Enums.AgeStage.ADULT,
		"stats": {&"str": 6}, "access_needs": []})
	_wheel = Colony.add_resident({"id": &"test_wheel", "name": "테스트 휠체어", "age_stage": Enums.AgeStage.ADULT,
		"access_needs": [Enums.AccessNeed.MOBILITY]})


func _open(args: Dictionary) -> void:
	UI.open(&"build", args)
	await get_tree().process_frame
	_screen = UI.get_screen(&"build")


func _test_reason_text() -> bool:
	var s: Script = load("res://ui/screens/build_screen.gd")
	var ok := _expect(s.reason_text("기지 단계 FORTRESS 필요") == "기지 단계 '요새' 필요", "tier key in words")
	var t: String = s.reason_text("시작 비용 부족: {&\"plank\": 10}", {&"plank": 10})
	ok = _expect(t.begins_with("시작 비용 부족: ") and not "&" in t, "start cost in words: %s" % t) and ok
	return ok


func _test_clear() -> bool:
	await _open({"mode": &"clear", "zone": &"park_a"})
	var ok := _expect(_screen.get(&"_mode") == &"clear", "opens on the clear view")
	ok = _expect(_list().get_child_count() == BaseDB.zones().size(), "one row per zone") and ok
	var start := _button(_detail(), "개간 시작")
	ok = _expect(start != null and not start.disabled, "개간 시작 offered for 공원 숲 A") and ok
	if start == null:
		return false
	start.pressed.emit()
	ok = _expect(Colony.clear_started.has(&"park_a"), "개간 시작 calls Colony.start_clearing") and ok
	ok = _expect(_button(_detail(), "배정") != null, "worker list shows after starting") and ok
	_button(_detail(), "배정").pressed.emit()
	var on: Array = _screen.call(&"_workers_on", &"park_a")
	ok = _expect(on.size() == 1 and Colony.job_of(on[0]) == WorkRules.CONSTRUCTION_JOB,
		"배정 puts a resident on construction at the zone") and ok
	_button(_detail(), "빼기").pressed.emit()
	ok = _expect((_screen.call(&"_workers_on", &"park_a") as Array).is_empty(), "빼기 unassigns") and ok
	# The wheelchair user cannot reach 체육관 (no ramp): the reason shows instead of a button.
	_screen.set(&"_sel_zone", &"gym")
	Colony.start_clearing(&"gym")
	_screen.call(&"_refresh")
	ok = _expect(_label_with(_detail(), "경사로") != null, "mobility block reason shown in the worker list") and ok
	return ok


func _test_clear_cost() -> bool:
	await _open({"mode": &"clear", "zone": &"roof"})
	var start := _button(_detail(), "개간 시작")
	var ok := _expect(start != null and start.disabled, "옥상 blocked without its start cost")
	var why := _label_with(_detail(), "시작 비용 부족")
	ok = _expect(why != null and not "&" in why.text, "start cost reason in words") and ok
	return ok


func _test_repair() -> bool:
	var uid := Colony.place_building(&"workshop", Vector2i(2, 2), 0, &"playground", false)
	Colony.complete_building(uid)
	Colony.damage_building(uid, 999)
	Economy.apply(Colony.repair_cost(uid))
	await _open({"mode": &"repair", "uid": uid})
	var go := _button(_detail(), "수리 시작")
	var ok := _expect(go != null and not go.disabled, "수리 시작 offered for a damaged building")
	if go == null:
		return false
	go.pressed.emit()
	ok = _expect(int(Colony.get_building(uid)["repair_progress"]) >= 0, "수리 시작 calls Colony.start_repair") and ok
	var put := _button(_detail(), "배정")
	ok = _expect(put != null, "worker list shows while repairing") and ok
	if put != null:
		put.pressed.emit()
		ok = _expect((_screen.call(&"_workers_on", uid) as Array).size() == 1, "repair worker assigned") and ok
	return ok


func _test_upgrade() -> bool:
	Colony.tier = Enums.BaseTier.SETTLEMENT
	var uid := Colony.place_building(&"kitchen", Vector2i(6, 2), 0, &"main_hall", false)
	Colony.complete_building(uid)
	Economy.set_cap_bonus(5000)
	Economy.apply(Colony.can_upgrade(uid).cost)
	await _open({"mode": &"repair", "uid": uid})
	var go := _button(_detail(), "레벨업")
	var ok := _expect(go != null and not go.disabled, "레벨업 offered")
	if go == null:
		return false
	go.pressed.emit()
	ok = _expect(int(Colony.get_building(uid)["level"]) == 2, "레벨업 calls Colony.upgrade_building") and ok
	return ok


func _test_access() -> bool:
	await _open({"mode": &"access"})
	var ok := _expect(_list().get_child_count() == BaseDB.zones().size() + 1, "header + one row per zone")
	var blocked := _labels(_list(), "못 들어감").size()
	ok = _expect(blocked >= 1, "zones without a ramp read 못 들어감") and ok
	for l: Label in _labels(_list(), "못 들어감") + _labels(_list(), "갈 수 있음"):
		var mark := l.get_parent().get_child(0)
		ok = _expect(mark is CheckMark and (mark as CheckMark).done == (l.text == "갈 수 있음"),
			"met / not met has a shape next to the words") and ok
	ok = _expect(_find(_list(), func(n: Node) -> bool: return n is InfoIcon) == null, "no inclusion facility yet") and ok
	var ramp := Colony.place_building(&"ramp", Vector2i(1, 1), 0, &"gym", false)
	Colony.complete_building(ramp)  # buildings_changed → the view redraws
	await get_tree().process_frame
	ok = _expect(_labels(_list(), "못 들어감").size() == blocked - 1, "a ramp in 체육관 makes it reachable") and ok
	ok = _expect(_find(_list(), func(n: Node) -> bool: return n is InfoIcon) != null,
		"inclusion facility shown with the INFO icon") and ok
	ok = _expect(_label_with(_detail(), "청각") != null and _label_with(_detail(), "돌봄") != null
		and _label_with(_detail(), "통역 무전기") != null, "hearing / care / interpreter lines") and ok
	_button(_detail(), "포함 시설 짓기").pressed.emit()
	ok = _expect(_screen.get(&"_mode") == &"build" and _screen.get(&"_cat") == BuildingDef.Category.INCLUSION,
		"포함 시설 짓기 opens the build list on 포함") and ok
	return ok


# ---------------- helpers ----------------

func _list() -> Node:
	return _screen.get(&"_list")


func _detail() -> Node:
	return _screen.get(&"_detail")


func _find(root: Node, pred: Callable) -> Node:
	for c in root.get_children():
		if c.is_queued_for_deletion():
			continue
		if pred.call(c):
			return c
		var f := _find(c, pred)
		if f != null:
			return f
	return null


func _button(root: Node, prefix: String) -> Button:
	return _find(root, func(n: Node) -> bool: return n is Button and (n as Button).text.begins_with(prefix)) as Button


func _label_with(root: Node, part: String) -> Label:
	return _find(root, func(n: Node) -> bool: return n is Label and part in (n as Label).text) as Label


func _labels(root: Node, text: String, out: Array = []) -> Array:
	for c in root.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Label and (c as Label).text == text:
			out.append(c)
		_labels(c, text, out)
	return out


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
