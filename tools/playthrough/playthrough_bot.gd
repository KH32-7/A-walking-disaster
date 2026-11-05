extends Node
## Playthrough bot (QA): plays the game from the title screen for two days through the real UI —
## presses the same Buttons a player would, holds real input actions in the field — and reports
## every error, stall and failed check. Owner: Lane A tools (QA pass, user-approved cross-lane).
##
##   godot --path . --resolution 1920x1080 res://tools/playthrough/playthrough_bot.tscn -- --out=<dir>
##
## Day 1: 새 게임 → 건설(벌목장 놓기·일손 보내기) → 주민 → 공원 출격 → 걷기 → 탈출 → 결과 → 저녁 → 밤 → 잠
## Day 2: 침수 상가가 열렸는지 → 출격 → 쓰러짐 → 결과 → 저녁 → 밤 → 3일차 아침
## Writes <out>/report.json and a screenshot per step (<out>/NN_name.png). Exit code 0 = all passed.

const MAIN := "res://main.tscn"
const STEP_TIMEOUT := 25.0

var out_dir := "user://playthrough"
var _main: Node
var _log: BotLogger
var _steps: Array = []
var _checks: Array = []
var _shot_n := 0
var _t0 := 0


class BotLogger extends Logger:
	var errors: Array = []
	var warnings: Array = []
	var _m := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var text := "%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]
		for bt in script_backtraces:
			if bt != null and bt.get_frame_count() > 0:
				text += " <- %s:%d %s" % [bt.get_frame_file(0), bt.get_frame_line(0), bt.get_frame_function(0)]
				break
		_m.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings.append(text)
		else:
			errors.append(text)
		_m.unlock()

	func _log_message(message: String, error: bool) -> void:
		if error:
			_m.lock()
			errors.append(message.strip_edges())
			_m.unlock()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_log = BotLogger.new()
	OS.add_logger(_log)
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


# ---------------- the run ----------------

func _run() -> void:
	_main = (load(MAIN) as PackedScene).instantiate()
	_main.name = &"Main"
	get_tree().root.add_child(_main)
	await _frames(10)
	var ok := await _day1()
	if ok:
		ok = await _day2()
	if ok:
		ok = await _day3()
	if ok:
		ok = await _day4()
	_finish()


func _day1() -> bool:
	_step("title")
	if not await _until(func() -> bool: return UI.is_open(&"title"), "타이틀 화면이 열림"):
		return false
	await _shot("title")
	var title: Node = UI.get_screen(&"title")
	title.list.focus_row(&"new")
	await _frames(3)
	var start := title.find_child("start", true, false) as Button
	if not _check(start != null and not start.disabled, "새 게임 '시작하기' 버튼이 있고 누를 수 있음"):
		return false
	await _shot("new_game_panel")
	start.pressed.emit()
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.BASE_MORNING, "새 게임 → 기지 아침"):
		return false
	await _loading_done()
	_check(GameState.day == 1, "1일차로 시작 (지금 %d)" % GameState.day)
	_check(UI.base_hud != null and UI.base_hud.visible, "기지 HUD가 보임")
	_check(Armory.get_equipped(Armory.PLAYER_ID, Enums.EquipSlot.MAIN) != &"", "시작 무기를 들고 있음")
	_start_state = {"population": Colony.population(), "residents": Colony.active_resident_ids().size(),
		"wood": Economy.get_amount(&"wood"), "stone": Economy.get_amount(&"stone"), "food": Economy.get_amount(&"food"),
		"buildable": BaseDB.buildings().keys().filter(func(id: StringName) -> bool: return Colony.can_build(id).ok)}
	print("[bot] start state ", _start_state)
	await _frames(20)
	await _shot("base_morning_d1")
	_check(UI.tutorial != null and UI.tutorial.current_step() == &"hello", "첫날 안내가 첫 단계로 뜸")
	await _build_something()
	await _visit(&"residents", "주민")
	await _visit(&"craft", "제작")
	await _visit(&"armory", "무기고")
	await _visit(&"journal", "생존 일지")
	if not await _sortie(&"city_park"):
		return false
	if not await _field_walk():
		return false
	if not await _field_extract():
		return false
	return await _back_home_and_sleep(2)


func _day2() -> bool:
	_step("day2")
	await _shot("base_morning_d2")
	_check(GameState.has_flag(&"extracted_city_park"), "공원 탈출 기록이 남음 (침수 상가 해금 조건)")
	_check(GameState.has_flag(&"tutorial_done") and UI.tutorial.current_step() == &"", "2일차 아침: 첫날 안내가 끝남")
	var site_ok := false
	for uid: StringName in Colony.buildings.keys():
		var b := Colony.get_building(uid)
		if b["def_id"] == _built_def and (b["completed"] or int(b["progress"]) > 0):
			site_ok = true
	if _built_def != &"":
		_check(site_ok, "어제 놓은 %s 건설이 진행됨" % _built_def)
	await _build_something()
	UI.base_hud._menu_buttons[&"@sortie"].pressed.emit()
	if not await _until(func() -> bool: return UI.is_open(&"sortie_prep"), "출격 준비 화면이 열림"):
		return false
	var prep: Node = UI.get_screen(&"sortie_prep")
	_check(prep.is_open_region(&"flooded_mall"), "2일차: 침수 상가가 열림")
	_check(not prep.is_open_region(&"hospital"), "병원은 아직 잠김")
	prep.close()
	await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.BASE_MORNING, "출격 준비 취소 → 아침")
	if not await _sortie(&"flooded_mall"):
		return false
	await _frames(30)
	await _shot("field_flooded_mall")
	UI.open(&"map")
	await _frames(15)
	_check(UI.is_open(&"map") and UI.get_screen(&"map").map.place_labels.size() >= 10, "침수 상가 지도에 지명이 뜸")
	await _shot("map_flooded_mall")
	UI.close(&"map")
	await _frames(5)
	if not await _rescue_and_extract():
		return false
	return await _back_home_and_sleep(3)


## 3일차: send the new resident to yesterday's site, stay at base, end the day → the building is done.
func _day3() -> bool:
	_step("day3")
	await _shot("base_morning_d3")
	var people := Colony.active_resident_ids()
	if not _check(not people.is_empty(), "구조한 사람이 주민이 됨 (%d명)" % people.size()):
		return false
	var done_before := Colony.buildings.keys().filter(func(u: StringName) -> bool: return Colony.get_building(u)["completed"]).size()
	_check(done_before >= 2, "어제 놓은 현장을 새 주민이 저녁에 지음 (완성 %d개)" % done_before)
	# a new site, this time with a resident to send (③ 현장 카드의 배정)
	await _build_something()
	var site_uid: StringName = &""
	for uid: StringName in Colony.buildings.keys():
		if not Colony.get_building(uid)["completed"]:
			site_uid = uid
	for uid: StringName in Colony.buildings.keys():
		var bb := Colony.get_building(uid)
		print("[bot] building ", uid, " ", bb["def_id"], " done=", bb["completed"], " prog=", bb["progress"], " workers=", bb["workers"])
	_check(site_uid != &"" and not (Colony.get_building(site_uid)["workers"] as Array).is_empty(), "새 현장에 주민이 일하러 감")
	UI.base_hud._menu_buttons[&"@stay"].pressed.emit()
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.BASE_STAY, "머무르기 → 기지에 머무는 중"):
		return false
	await _frames(20)
	await _shot("base_stay_d3")
	var end := _flow_prompt_button("하루 마치기")
	if not _check(end != null, "머무는 날에 '하루 마치기' 버튼이 있음"):
		return false
	end.pressed.emit()
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.EVENING, "하루 마치기 → 저녁"):
		return false
	if site_uid != &"":
		_check(bool(Colony.get_building(site_uid).get("completed", false)), "일손 + 머무르기로 현장이 완성됨 (진행 %d)" % int(Colony.get_building(site_uid).get("progress", 0)))
	return await _evening_night(4)


## 4일차: park again, go down this time.
func _day4() -> bool:
	if not await _sortie(&"city_park"):
		return false
	await _frames(20)
	_step("downed")
	var player := get_tree().get_first_node_in_group(&"player")
	player.take_damage(float(player.health) + 999.0, {})
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.RESULT, "쓰러짐 → 결과 화면"):
		return false
	_check(bool(SceneRouter.last_sortie_result.get("downed", false)), "결과가 '쓰러짐'으로 기록됨")
	return await _back_home_and_sleep(5)


func _rescue_and_extract() -> bool:
	_step("rescue")
	var player: Node3D = get_tree().get_first_node_in_group(&"player")
	var targets := get_tree().get_nodes_in_group(RescueTarget.GROUP)
	if not _check(not targets.is_empty(), "침수 상가에 구조 대상이 있음 (%d명)" % targets.size()):
		return false
	var who: RescueTarget = targets[0]
	player.global_position = who.global_position + Vector3(1.5, 0, 0)
	await _frames(10)
	var hint: String = who.interact_label()
	var door := who.get_node_or_null(^"Door")
	if hint == "" and door != null:
		hint = door.interact_label()
	_check(hint != "", "구조 대상 앞에서 [F] 안내가 뜸: %s" % hint)
	who._rescue(player)  # the rescue event itself (치료·자물쇠·카드) is Lane B's tests; here: what follows
	await _frames(10)
	_check(who.is_rescued(), "구조하면 따라옴 (%s)" % who.display_name)
	await _shot("rescued")
	var em := get_tree().get_first_node_in_group(&"field_extraction")
	var point: Node3D = null
	for p in em.active_points():
		if int(p.type) != 2:
			point = p
			break
	if not _check(point != null, "열쇠 없이 쓸 수 있는 탈출 지점"):
		return false
	# alone first: the "두고 갈까요?" dialog must come up and "취소" must wait for them
	# they hide where they are (명령: 숨기), the player runs to the exit alone
	who.command_hide()
	who.process_mode = Node.PROCESS_MODE_DISABLED  # stays where they are, whatever their state
	await _frames(5)
	player.global_position = point.global_position + Vector3(0, 0.1, 0)
	if who.global_position.distance_to(point.global_position) < 15.0:
		who.global_position = point.global_position + Vector3(20, 0.1, 0)
	print("[bot] rescue target state=", who.state, " in_party=", who.is_in_group(ExtractionManager.PARTY_GROUP),
		" dist=", who.global_position.distance_to(player.global_position), " template=", who.spawn.template_id)
	var asked := await _until(func() -> bool: return _confirm_dialog() != null, "구조한 사람이 멀면 '두고 갈까요?'를 물음", 20.0)
	if asked:
		await _shot("leave_behind_dialog")
		_button(_confirm_dialog(), "취소").pressed.emit()
		await _frames(5)
		_check(GameState.flow_state == Enums.FlowState.FIELD, "'취소'하면 두고 가지 않고 기다림")
	who.process_mode = Node.PROCESS_MODE_INHERIT
	who.global_position = point.global_position + Vector3(1.0, 0.1, 0)
	who.command_follow(player)
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.RESULT, "다 모이면 함께 탈출", 30.0):
		return false
	_check((SceneRouter.last_sortie_result.get("rescued", []) as Array).size() >= 1, "결과에 구조한 사람이 들어감")
	return true


func _confirm_dialog() -> ConfirmDialog:
	for n in UI.overlay.get_children():
		if n is ConfirmDialog and not n.is_queued_for_deletion():
			return n
	return null


# ---------------- base ----------------

var _built_def: StringName = &""
var _start_state := {}
var _builds := 0


func _build_something() -> void:
	_step("build")
	UI.base_hud._menu_buttons[&"build"].pressed.emit()
	if not await _until(func() -> bool: return UI.is_open(&"build"), "건설 화면이 열림"):
		return
	await _frames(10)
	await _shot("build_menu")
	var screen: Node = UI.get_screen(&"build")
	var pick: StringName = &""
	for id: StringName in [&"bonfire", &"bed", &"lumber_yard", &"quarry"]:
		if Colony.can_build(id).ok:
			pick = id
			break
	if not _check(pick != &"", "1일차에 지을 수 있는 건물이 있음"):
		UI.close(&"build")
		return
	screen._sel = pick
	screen._fill()
	var go := _button(screen._detail, "놓을 곳 고르기")
	if not _check(go != null and not go.disabled, "'놓을 곳 고르기' 버튼을 누를 수 있음"):
		UI.close(&"build")
		return
	go.pressed.emit()
	if not await _until(func() -> bool: return is_instance_valid(UI.build_place_hud), "②놓기 화면이 뜸"):
		return
	var base := _world_scene()
	var mode: BuildMode = base.build_mode
	var grid: BaseGrid = base.grid
	var spot := _find_spot(grid, pick)
	if not _check(not spot.is_empty(), "%s를 놓을 자리가 있음" % pick):
		mode.cancel()
		return
	mode.preview_cell(spot["zone_id"], spot["cell"])
	await _shot("build_place")
	# Same frame as the click: the window's real mouse may move the preview between frames.
	mode.preview_cell(spot["zone_id"], spot["cell"])
	var uid := mode.confirm()
	if not _check(uid != &"", "확인하면 건설 현장이 생김"):
		return
	print("[bot] placed ", uid, " ids=", Colony.buildings.keys())
	_built_def = pick
	_builds += 1
	if not await _until(func() -> bool: return UI.is_open(&"build") and UI.get_screen(&"build")._mode == &"site", "③현장 카드가 열림"):
		return
	await _frames(5)
	var site: Node = UI.get_screen(&"build")
	var put := _button(site._detail, "배정")
	if Colony.active_resident_ids().is_empty():
		_check(put == null and _label_with(site._detail, "주민이 없") != null, "주민이 없으면 현장 카드가 그렇게 알려 줌")
	elif _check(put != null, "현장에 보낼 주민이 있음"):
		put.pressed.emit()
		await _frames(3)
		_check(not (Colony.get_building(uid)["workers"] as Array).is_empty(), "배정하면 현장 일손이 생김")
	await _shot("build_site")
	_button(site._detail, "이대로 짓기").pressed.emit()
	await _until(func() -> bool: return not UI.is_open(&"build"), "현장 카드가 닫힘")
	print("[bot] after close ids=", Colony.buildings.keys(), " uid still=", Colony.buildings.has(uid))
	await _frames(10)
	if GameState.day == 1 and _builds == 1:
		_check(bool(Colony.get_building(uid).get("completed", false)), "첫날 안내: 방송실 지기가 첫 건물을 같이 지어 줌")
		_check(UI.tutorial.current_step() == &"sortie", "첫날 안내가 '출격' 단계로 넘어감 (지금 %s)" % UI.tutorial.current_step())
		await _shot("tutorial_after_build")


func _visit(id: StringName, label: String) -> void:
	_step("visit_" + String(id))
	var b: Button = UI.base_hud._menu_buttons.get(id)
	if not _check(b != null, "기지 메뉴에 '%s' 버튼이 있음" % label):
		return
	b.pressed.emit()
	if not await _until(func() -> bool: return UI.is_open(id), "'%s' 화면이 열림" % label):
		return
	await _frames(12)
	await _shot("screen_" + String(id))
	UI.close(id)
	await _until(func() -> bool: return not UI.is_open(id), "'%s' 화면이 닫힘" % label)
	_check(not get_tree().paused, "'%s'를 닫으면 게임이 다시 흐름" % label)


# ---------------- field ----------------

func _sortie(region: StringName) -> bool:
	_step("sortie_" + String(region))
	if not UI.is_open(&"sortie_prep"):
		UI.base_hud._menu_buttons[&"@sortie"].pressed.emit()
	if not await _until(func() -> bool: return UI.is_open(&"sortie_prep"), "출격 준비 화면이 열림"):
		return false
	var prep: Node = UI.get_screen(&"sortie_prep")
	if not _check(prep.is_open_region(region), "%s에 갈 수 있음" % region):
		return false
	prep._region = region
	prep._refresh()
	await _frames(8)
	await _shot("sortie_prep_" + String(region))
	var go: Button = prep._go
	if not _check(go != null and not go.disabled, "'출격' 버튼을 누를 수 있음"):
		return false
	go.pressed.emit()
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.FIELD, "출격 → 필드"):
		return false
	await _loading_done()
	return await _until(func() -> bool: return get_tree().get_first_node_in_group(&"player") != null, "필드에 플레이어가 나타남")


func _field_walk() -> bool:
	_step("walk")
	var player: Node3D = get_tree().get_first_node_in_group(&"player")
	_check(UI.field_hud != null and UI.field_hud.visible, "필드 HUD가 보임")
	await _frames(20)
	var from := player.global_position
	for action: StringName in [&"move_up", &"move_right"]:
		Input.action_press(action)
	await get_tree().create_timer(1.6).timeout
	for action: StringName in [&"move_up", &"move_right"]:
		Input.action_release(action)
	var moved := Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length()
	_check(moved > 2.0, "WASD로 걸으면 움직임 (%.1fm)" % moved)
	await _shot("field_walk")
	# bag and map open and close in the field
	for pair: Array in [[&"bag", "가방"], [&"map", "지도"]]:
		UI.open(pair[0])
		await _frames(10)
		_check(UI.is_open(pair[0]), "필드에서 %s가 열림" % pair[1])
		await _shot("field_" + String(pair[0]))
		UI.close(pair[0])
		await _frames(4)
	return true


func _field_extract() -> bool:
	_step("extract")
	var em := get_tree().get_first_node_in_group(&"field_extraction")
	if not _check(em != null, "탈출 관리자가 있음"):
		return false
	var point: Node3D = null
	for p in em.active_points():
		if int(p.type) != 2:  # not a key gate
			point = p
			break
	if not _check(point != null, "열쇠 없이 쓸 수 있는 탈출 지점이 열려 있음"):
		return false
	var player: Node3D = get_tree().get_first_node_in_group(&"player")
	player.global_position = point.global_position + Vector3(0, 0.1, 0)
	await _frames(20)
	await _shot("field_extracting")
	return await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.RESULT, "탈출 지점에 서 있으면 탈출 완료", 30.0)


# ---------------- result → evening → night → morning ----------------

func _back_home_and_sleep(next_day: int) -> bool:
	_step("result_d%d" % (next_day - 1))
	if not await _until(func() -> bool: return UI.is_open(&"result"), "결과 화면이 열림"):
		return false
	await _loading_done()
	await get_tree().create_timer(2.2).timeout
	await _shot("result_d%d" % (next_day - 1))
	var res: Node = UI.get_screen(&"result")
	res._go.pressed.emit()
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.EVENING, "결과 → 저녁"):
		return false
	await _frames(20)
	# 입주 의식 for anyone rescued
	var guard := 0
	while UI.is_open(&"welcome") and guard < 40:
		guard += 1
		var w: Node = UI.get_screen(&"welcome")
		if guard == 1:
			await _shot("welcome")
		if w._next_button != null:
			w._next_button.pressed.emit()
		await _frames(4)
	return await _evening_night(next_day)


func _evening_night(next_day: int) -> bool:
	var guard := 0
	while UI.is_open(&"welcome") and guard < 40:
		guard += 1
		var w: Node = UI.get_screen(&"welcome")
		if guard == 1:
			await _shot("welcome")
		if w._next_button != null:
			w._next_button.pressed.emit()
		await _frames(4)
	await _until(func() -> bool: return UI.is_open(&"evening"), "저녁 정산 화면이 열림")
	await _frames(10)
	await _shot("evening_d%d" % (next_day - 1))
	UI.get_screen(&"evening")._go.pressed.emit()
	if not await _until(func() -> bool: return GameState.flow_state in [Enums.FlowState.NIGHT, Enums.FlowState.NIGHT_EVENT, Enums.FlowState.NIGHT_RAID], "저녁 → 밤"):
		return false
	await _frames(30)
	await _shot("night_d%d" % (next_day - 1))
	# night events: play each one with its first choice, then end the night
	guard = 0
	while UI.is_open(&"night_event") and guard < 20:
		guard += 1
		var ne: Node = UI.get_screen(&"night_event")
		var ids: Array = ne.dialog.choice_ids()
		if ids.is_empty():
			await _frames(5)
			continue
		var pick: StringName = &"end" if &"end" in ids and not (ids.size() > 1 and guard < 6) else StringName(ids[0])
		if guard == 1:
			await _shot("night_event_d%d" % (next_day - 1))
		ne.dialog.pick(pick)
		await _frames(8)
	var sleep := _flow_prompt_button("잠자기")
	if not _check(sleep != null, "밤에 '잠자기' 버튼이 있음"):
		return false
	sleep.pressed.emit()
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.BASE_MORNING and GameState.day == next_day, "잠자기 → %d일차 아침" % next_day):
		return false
	await _loading_done()
	await _frames(20)
	_check(SaveSystem.has_slot(SaveSystem.current_slot), "아침에 자동 저장됨")
	return true


# ---------------- helpers ----------------

func _world_scene() -> Node:
	var world := get_node_or_null(SceneRouter.WORLD_PATH)
	return world.get_child(0) if world != null and world.get_child_count() > 0 else null


func _find_spot(grid: BaseGrid, def_id: StringName) -> Dictionary:
	for zone_id: StringName in grid.areas:
		if not grid.is_zone_cleared(zone_id):
			continue
		var area: BuildArea = grid.areas[zone_id]
		for y in area.size_cells.y:
			for x in area.size_cells.x:
				if grid.check(def_id, zone_id, Vector2i(x, y))["ok"]:
					return {"zone_id": zone_id, "cell": Vector2i(x, y)}
	return {}


func _label_with(root: Node, part: String) -> Label:
	if root == null:
		return null
	for l in root.find_children("*", "Label", true, false):
		if not l.is_queued_for_deletion() and part in (l as Label).text:
			return l
	return null


func _flow_prompt_button(prefix: String) -> Button:
	var root := get_node_or_null(^"/root/Main/FlowPrompts/Root")
	if root == null:
		return null
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix) and b.is_visible_in_tree():
			return b
	return null


func _button(root: Node, prefix: String) -> Button:
	if root == null:
		return null
	for b in root.find_children("*", "Button", true, false):
		if not b.is_queued_for_deletion() and (b as Button).text.begins_with(prefix):
			return b
	return null


func _loading_done() -> void:
	await _until(func() -> bool: return not UI.is_open(&"loading"), "로딩 카드가 닫힘", 10.0)


func _until(cond: Callable, what: String, timeout := STEP_TIMEOUT) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			_check(true, what)
			return true
		await get_tree().process_frame
	_check(false, what + " (%.0f초 안에 안 됨, 지금 %s)" % [timeout, Enums.FlowState.keys()[GameState.flow_state]])
	await _shot("STUCK")
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _step(name: String) -> void:
	_steps.append({"step": name, "t": (Time.get_ticks_msec() - _t0) / 1000.0, "day": GameState.day,
		"state": Enums.FlowState.keys()[GameState.flow_state], "errors_so_far": _log.errors.size()})
	print("[bot] ", name)


func _check(ok: bool, what: String) -> bool:
	_checks.append({"ok": ok, "what": what, "step": _steps.back()["step"] if not _steps.is_empty() else "", "t": (Time.get_ticks_msec() - _t0) / 1000.0})
	print("[bot] %s %s" % ["PASS" if ok else "FAIL", what])
	return ok


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_shot_n += 1
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png("%s/%02d_%s.png" % [out_dir, _shot_n, name])


func _finish() -> void:
	var failed := _checks.filter(func(c: Dictionary) -> bool: return not c.ok)
	var report := {"passed": failed.is_empty() and _log.errors.is_empty(), "duration_sec": (Time.get_ticks_msec() - _t0) / 1000.0,
		"day_reached": GameState.day, "start_state": _start_state, "final_state": Enums.FlowState.keys()[GameState.flow_state],
		"checks_total": _checks.size(), "checks_failed": failed.size(), "failed": failed,
		"errors": _log.errors, "warnings": _log.warnings.slice(0, 60), "steps": _steps, "checks": _checks}
	var f := FileAccess.open(out_dir + "/report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[bot] DONE passed=%s checks=%d failed=%d errors=%d" % [report.passed, _checks.size(), failed.size(), _log.errors.size()])
	get_tree().quit(0 if report.passed else 1)
