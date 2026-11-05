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

var _pop_before := 0
## Yesterday's site had nobody able to work on it (day 1: only the injured), so no progress is due.
var _unstaffed_site := false
var _doctor_node: RescueTarget = null
## Resource the next evening report must show as produced (&"" = no check).
var _watch_produced := &""
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
	if "--quick=base" in OS.get_cmdline_user_args():
		await _quick_base()
		_finish()
		return
	if "--quick=screens" in OS.get_cmdline_user_args():
		await _quick_screens()
		_finish()
		return
	if "--quick=rain" in OS.get_cmdline_user_args():
		await _quick_rain()
		_finish()
		return
	if "--quick=cinema" in OS.get_cmdline_user_args():
		# Only the cutscene, for --write-movie (look at it as a video, then delete it).
		await _until(func() -> bool: return UI.is_open(&"title"), "타이틀", 60.0)
		UI.get_screen(&"title").list.focus_row(&"new")
		await _frames(3)
		(UI.get_screen(&"title").find_child("start", true, false) as Button).pressed.emit()
		await _until(func() -> bool: return get_tree().get_first_node_in_group(IntroCutscene.GROUP) != null, "인트로", 60.0)
		var intro := get_tree().get_first_node_in_group(IntroCutscene.GROUP) as IntroCutscene
		await _until(func() -> bool: return intro.phase() == &"house" and intro.player.script_input.is_empty(), "컷신 끝", 300.0)
		await get_tree().create_timer(1.5).timeout
		_finish()
		return
	if "--quick=intro" in OS.get_cmdline_user_args():
		await _quick_intro()
		_finish()
		return
	if "--quick=prompts" in OS.get_cmdline_user_args():
		await _quick_prompts()
		_finish()
		return
	var ok := await _day1()
	if ok:
		ok = await _day2()
	if ok:
		ok = await _day3()
	if ok:
		ok = await _day4()
	if ok:
		ok = await _day5()
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
	if not await _intro(false):
		return false
	UI.tutorial.skip()  # the full run checks the rest of the game; --quick=intro checks the tutorial
	_check(UI.base_hud != null and UI.base_hud.visible, "기지 HUD가 보임")
	_check(Armory.get_equipped(Armory.PLAYER_ID, Enums.EquipSlot.MAIN) != &"", "시작 무기를 들고 있음")
	_start_state = {"population": Colony.population(), "residents": Colony.active_resident_ids().size(),
		"wood": Economy.get_amount(&"wood"), "stone": Economy.get_amount(&"stone"), "food": Economy.get_amount(&"food"),
		"buildable": BaseDB.buildings().keys().filter(func(id: StringName) -> bool: return Colony.can_build(id).ok)}
	print("[bot] start state ", _start_state)
	await _frames(20)
	await _shot("base_morning_d1")
	await _build_something()
	await _visit(&"residents", "주민")
	await _visit(&"craft", "제작")
	await _visit(&"armory", "무기고")
	await _visit(&"journal", "생존 일지")
	if not await _sortie(&"city_park"):
		return false
	if not await _field_walk():
		return false
	_pop_before = Colony.active_resident_ids().size()
	if not await _rescue_doctor():
		return false
	if not await _field_extract():
		return false
	_check((SceneRouter.last_sortie_result.get("rescued", []) as Array).size() >= 1, "공원: 의사를 데리고 함께 탈출함")
	return await _back_home_and_sleep(2)


func _day2() -> bool:
	_step("day2")
	await _shot("base_morning_d2")
	_check(GameState.has_flag(&"extracted_city_park"), "공원 탈출 기록이 남음 (침수 상가 해금 조건)")
	_check(GameState.has_flag(&"tutorial_done") and UI.tutorial.current_step() == &"", "2일차 아침: 첫날 안내가 끝남")
	var doc := _resident_with_job(&"doctor")
	_check(doc != &"", "구한 의사가 주민이 됨 (주민 %d → %d명)" % [_pop_before, Colony.active_resident_ids().size()])
	_check(Colony.active_resident_ids().size() == _pop_before + 1, "주민 수가 한 명 늘어남")
	if doc != &"":
		_check(int(Colony.get_resident(doc).get("health", 0)) == Enums.HealthState.OK, "의사는 다치지 않아 바로 일할 수 있음")
	var inf: Array = Colony.can_build(&"infirmary").reasons
	_check(not inf.any(func(r: String) -> bool: return "의사" in r), "의사가 오면 의무실의 전직 의사 조건이 풀림 (남은 조건 %s)" % [inf])
	var site_ok := false
	for uid: StringName in Colony.buildings.keys():
		var b := Colony.get_building(uid)
		if b["def_id"] == _built_def and (b["completed"] or int(b["progress"]) > 0):
			site_ok = true
	if _built_def != &"" and not _unstaffed_site:
		_check(site_ok, "어제 놓은 %s 건설이 진행됨" % _built_def)
	_unstaffed_site = false
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
	if not _check(people.size() >= _pop_before + 2, "침수 상가에서 구한 사람도 주민이 됨 (%d명)" % people.size()):
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


## 4일차: a lumber yard with the doctor on it, then the park again, going down this time.
## The evening report must show the wood the lumber yard made.
func _day4() -> bool:
	_step("day4_lumber")
	var wood_job := await _staff(&"lumber_yard", &"woodcutting")
	if not await _sortie(&"city_park"):
		return false
	await _frames(20)
	_step("downed")
	var player := get_tree().get_first_node_in_group(&"player")
	player.take_damage(float(player.health) + 999.0, {})
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.RESULT, "쓰러짐 → 결과 화면"):
		return false
	_check(bool(SceneRouter.last_sortie_result.get("downed", false)), "결과가 '쓰러짐'으로 기록됨")
	_watch_produced = &"wood" if wood_job else &""
	return await _back_home_and_sleep(5)


## 5일차: a quarry with the doctor on it, stay home; the evening shows the stone.
func _day5() -> bool:
	_step("day5_quarry")
	await _shot("base_morning_d5")
	var ok := await _staff(&"quarry", &"quarrying")
	UI.base_hud._menu_buttons[&"@stay"].pressed.emit()
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.BASE_STAY, "5일차 머무르기"):
		return false
	_flow_prompt_button("하루 마치기").pressed.emit()
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.EVENING, "하루 마치기 → 저녁"):
		return false
	_watch_produced = &"stone" if ok else &""
	return await _evening_night(6)


## Builds `def_id` where the grid allows (paid when affordable, else given), finishes it and sends a
## healthy resident to `job_id` there. True when someone works there now.
func _staff(def_id: StringName, job_id: StringName) -> bool:
	var base := _world_scene()
	var spot := _find_spot(base.grid, def_id)
	if not _check(not spot.is_empty(), "%s를 놓을 자리가 있음" % def_id):
		return false
	var pay: bool = Colony.can_build(def_id).ok
	var uid := Colony.place_building(def_id, spot["cell"], 0, spot["zone_id"], pay)
	if not _check(uid != &"", "%s 건설 현장을 놓음" % def_id):
		return false
	Colony.complete_building(uid)
	var worker := &""
	for id: StringName in Colony.active_resident_ids():
		var r := Colony.get_resident(id)
		if int(r.get("health", 0)) == Enums.HealthState.OK:
			worker = id
			break
	if not _check(worker != &"", "일할 수 있는 주민이 있음"):
		return false
	var reason := Colony.job_block_reason(worker, job_id, uid)
	var ok := _check(Colony.assign_job(worker, job_id, uid), "%s에 %s 배정 (%s)" % [def_id, Colony.get_resident(worker).get("name", ""), reason])
	UI.open(&"residents", {"id": worker})
	await _frames(15)
	await _shot("residents_" + String(job_id))
	UI.close(&"residents")
	await _frames(5)
	return ok


func _resident_with_job(former_job: StringName) -> StringName:
	for id: StringName in Colony.active_resident_ids():
		if Colony.get_resident(id).get("former_job", &"") == former_job:
			return id
	return &""


## Park: walk to the 관리사무소, help the doctor up with F, bring him to the exit (he follows).
func _rescue_doctor() -> bool:
	_step("rescue_doctor")
	var player: Node3D = get_tree().get_first_node_in_group(&"player")
	var doctor: RescueTarget = null
	for t in get_tree().get_nodes_in_group(RescueTarget.GROUP):
		if StringName((t as RescueTarget).profile.get("id", &"")) == &"demo_doctor":
			doctor = t
	if not _check(doctor != null, "공원 관리사무소에 의사가 있음"):
		return false
	player.global_position = doctor.global_position + Vector3(1.0, 0, 0.6)
	await _frames(10)
	_check(doctor.interact_label() != "", "의사 앞에서 [F] 안내: %s" % doctor.interact_label())
	_check(UI.world_prompts._chip.visible, "의사 옆에 [F] 툴팁이 보임")
	await _shot("doctor_prompt")
	(player as Player).interact()
	await _frames(10)
	if not _check(doctor.is_rescued(), "F를 누르면 의사가 따라옴"):
		return false
	_doctor_node = doctor
	return true


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
	var asked := await _until(func() -> bool: return _confirm_dialog() != null, "구조한 사람이 멀면 '두고 갈까요?'를 물음", 30.0)  # the generator exit waits 20 s
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


## Short look at the world prompts: [F] chip beside a container, exit diamonds (QA 화면 확인용).
func _quick_prompts() -> void:
	_step("quick_prompts")
	await _until(func() -> bool: return UI.is_open(&"title"), "타이틀")
	UI.get_screen(&"title").list.focus_row(&"new")
	await _frames(3)
	(UI.get_screen(&"title").find_child("start", true, false) as Button).pressed.emit()
	await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.BASE_MORNING, "기지")
	await _loading_done()
	UI.tutorial.skip()
	if not await _sortie(&"city_park"):
		return
	await _frames(20)
	var player: Node3D = get_tree().get_first_node_in_group(&"player")
	var box: Node3D = null
	var best := INF
	for n in get_tree().get_nodes_in_group(&"loot_containers"):
		if n is Node3D and player.global_position.distance_to(n.global_position) < best:
			best = player.global_position.distance_to(n.global_position)
			box = n
	if box == null:
		for n in get_tree().root.find_children("*", "LootContainer", true, false):
			box = n
			break
	if _check(box != null, "상자가 있음"):
		player.global_position = box.global_position + Vector3(1.0, 0, 0.6)
		await get_tree().create_timer(1.5).timeout  # camera catches up
		_check(UI.world_prompts._chip.visible, "상자 옆에 [F] 칩이 뜸: %s" % UI.world_prompts._chip_label.text)
		await _shot("prompt_container")
	var em := get_tree().get_first_node_in_group(&"field_extraction")
	var pts: Array = em.active_points()
	if not pts.is_empty():
		player.global_position = (pts[0] as Node3D).global_position + Vector3(6, 0, 6)
		await _frames(20)
		await _shot("exit_marker")


## New-game intro with shots of each beat: cutscene, the house steps, then the park quest up to the
## doctor following. Shots go to --out; they show paid assets, so delete them after looking.
func _quick_intro() -> void:
	_step("quick_intro")
	await _until(func() -> bool: return UI.is_open(&"title"), "타이틀")
	UI.get_screen(&"title").list.focus_row(&"new")
	await _frames(3)
	(UI.get_screen(&"title").find_child("start", true, false) as Button).pressed.emit()
	await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.BASE_MORNING, "새 게임 → 기지")
	await _loading_done()
	if not await _intro(true):
		return
	await get_tree().create_timer(1.2).timeout
	await _shot("i_base_after_house")
	_check(UI.tutorial.current_step() == &"sortie", "집을 나오면 '출격' 안내 (지금 %s)" % UI.tutorial.current_step())
	var base_cam := get_viewport().get_camera_3d()
	_check(base_cam is BaseCamera, "집을 나오면 기지 클릭 카메라로 돌아옴")
	_check(get_tree().get_first_node_in_group(&"player") == null, "기지에 걷는 플레이어가 다시 없음")
	_check(not UI.cinematic.skippable and UI.hud.visible and UI.base_hud.visible, "HUD가 원래대로")
	UI.open(&"build")
	await _until(func() -> bool: return UI.is_open(&"build"), "집을 나온 뒤 건설 화면이 열림")
	UI.close(&"build")
	await _frames(5)
	var base: Node = _world_scene()
	_check(base.build_mode.start(&"bonfire"), "건설 놓기 모드가 정상으로 시작됨")
	await _frames(10)
	await _shot("i_build_after_intro")
	base.build_mode.cancel()
	await _frames(5)
	if not await _sortie(&"city_park"):
		return
	await get_tree().create_timer(1.5).timeout
	_check(Quests.is_active(&"tutorial_doctor"), "공원에 오면 '의사를 찾아서' 의뢰가 시작됨")
	var doctor: RescueTarget = UI.tutorial._doctor()
	_check(doctor != null, "관리사무소에 의사가 있음")
	var people := get_tree().get_nodes_in_group(RescueTarget.GROUP)
	print("[bot] park survivors: ", people.map(func(t) -> String: return "%s(%s)" % [t.profile.get("name", "?"), t.interact_label()]))
	_check(people.size() >= 3, "공원에 구할 사람이 여럿 있음 (%d명)" % people.size())
	var office_rect: Rect2 = UI.tutorial._building_rect(UI.tutorial._office_pos())
	var inside := UI.tutorial._guards.filter(func(m) -> bool:
		return is_instance_valid(m) and office_rect.has_point(Vector2(m.global_position.x, m.global_position.z)))
	_check(office_rect.has_area() and not UI.tutorial._guards.is_empty() and inside.is_empty(),
		"관리사무소 마물은 건물 밖에 있음 (%d마리 중 안에 %d)" % [UI.tutorial._guards.size(), inside.size()])
	_check(UI.world_markers.banner_text().begins_with("의사는"), "목표 설명이 위쪽에 잠깐 뜸 (지금 '%s')" % UI.world_markers.banner_text())
	await _shot("i_park_quest")
	await get_tree().create_timer(WorldMarkers.BANNER_SEC).timeout
	_check(UI.world_markers.banner_text() == "", "목표 설명은 잠깐 뒤 사라짐")
	_check(not UI.subtitle.visible or UI.subtitle.current_text() != "", "빈 무전 자막 창이 남지 않음")
	await _shot("i_park_diamond_only")
	UI.open(&"map")
	await _frames(20)
	await _shot("i_park_map")
	UI.close(&"map")
	await _frames(5)
	var player: Player = get_tree().get_first_node_in_group(&"player")
	var office: Vector3 = UI.tutorial._office_pos()
	player.global_position = office + Vector3(6, 0, 12)
	await get_tree().create_timer(1.0).timeout
	_check(UI.tutorial.current_step() == &"fight", "관리사무소 근처: 마물 처치 안내 (지금 %s)" % UI.tutorial.current_step())
	await _shot("i_fight")
	for m in UI.tutorial._guards:
		if is_instance_valid(m):
			m.take_damage(99999.0, {"source": player})
	await get_tree().create_timer(1.5).timeout
	var outside := Vector3(office_rect.end.x + 3.0, player.global_position.y, office_rect.get_center().y)
	player.global_position = outside
	await get_tree().create_timer(0.6).timeout
	_check(UI.tutorial.current_step() == &"quest", "관리사무소 밖에선 아직 일으켜 세우기 안내 없음 (지금 %s)" % UI.tutorial.current_step())
	if doctor != null:
		player.global_position = doctor.global_position + Vector3(1.2, 0, 1.2)
		await get_tree().create_timer(0.8).timeout
		_check(UI.tutorial.current_step() == &"rescue", "의사 옆: 일으켜 세우기 안내 (지금 %s)" % UI.tutorial.current_step())
		await _shot("i_rescue")
		doctor.begin_open(player)
		await get_tree().create_timer(1.0).timeout
		_check(doctor.is_rescued(), "의사가 따라옴")
		_check(UI.tutorial.current_step() == &"extract", "탈출 안내 (지금 %s)" % UI.tutorial.current_step())
		await _shot("i_extract")
	var em := get_tree().get_first_node_in_group(ExtractionManager.GROUP) as ExtractionManager
	var points: Array[ExtractPoint] = em.active_points() if em != null else []
	_check(not points.is_empty() and points.all(func(e: ExtractPoint) -> bool: return e.has_node(^"ExtractBeacon")),
		"열린 탈출 지점마다 빛기둥 표시")
	if not points.is_empty():
		player.global_position = points[0].global_position + Vector3(0, 0, 9)
		await get_tree().create_timer(1.0).timeout
		await _shot("i_extract_point")


## The intro: cutscene (shots, or skipped), then the house steps done by hand.
func _intro(shots: bool) -> bool:
	_step("intro")
	var intro := get_tree().get_first_node_in_group(IntroCutscene.GROUP) as IntroCutscene
	if not _check(intro != null, "새 게임이면 인트로가 시작됨"):
		return false
	_check(Armory.get_equipped(Armory.PLAYER_ID, Enums.EquipSlot.MAIN) == &"", "처음엔 총이 없음")
	var player: Player = intro.player
	if shots:
		var t0 := Time.get_ticks_msec()
		for at: Array in [[2.2, "i_radio"], [8.4, "i_dawn"], [10.4, "i_chase_wide"], [12.2, "i_chase_front"]]:
			while Time.get_ticks_msec() - t0 < int(float(at[0]) * 1000.0):
				await get_tree().process_frame
			await _shot(String(at[1]))
		await _until(func() -> bool: return not player.visible, "주인공이 집으로 뛰어듦", 20.0)
		await get_tree().create_timer(0.35).timeout
		await _shot("i_door_slam")
		await get_tree().create_timer(1.1).timeout
		await _shot("i_splat")
		await _until(func() -> bool: return UI.cinematic._title.modulate.a > 0.95, "타이틀 카드", 10.0)
		await _shot("i_title")
	else:
		await _frames(5)
		UI.cinematic.skip_requested.emit()
	await _until(func() -> bool: return intro.phase() == &"house", "집 안", 25.0)
	if shots:
		await get_tree().create_timer(1.4).timeout
		await _shot("i_inside_close")
	await _until(func() -> bool: return player.script_input.is_empty(), "조작할 수 있음", 10.0)
	await get_tree().create_timer(0.8).timeout
	_check(UI.tutorial.current_step() == &"chest", "상자 안내 (지금 %s)" % UI.tutorial.current_step())
	if shots:
		await _shot("i_chest_spot")
	var chest := intro.interior.chest
	player.global_position = chest.global_position + Vector3(0, 0, 1.1)
	await _frames(5)
	player.interact()
	if not await _until(func() -> bool: return UI.is_open(&"bag"), "상자를 열면 가방이 열림", 10.0):
		return false
	await _until(func() -> bool: return bool(chest.get_slots()[0].identified), "권총 확인", 5.0)
	await _frames(10)
	_check(UI.tutorial.current_step() == &"take_gun", "권총 챙기기 안내 (지금 %s)" % UI.tutorial.current_step())
	if shots:
		await get_tree().create_timer(0.7).timeout
		await _shot("i_take_gun")
	(UI.get_screen(&"bag").call(&"loot_cell", 0) as Button).pressed.emit()
	await _frames(10)
	var uid: StringName = UI.tutorial._bag_pistol()
	_check(uid != &"", "권총이 가방에 들어감")
	_check(UI.tutorial.current_step() == &"equip", "장착 안내 (지금 %s)" % UI.tutorial.current_step())
	if shots:
		await get_tree().create_timer(0.7).timeout
		await _shot("i_equip")
	for e: Dictionary in Bag.entries():
		if StringName(e.get("ref", &"")) == uid:
			Bag.equip_entry(int(e.id))
	await _frames(10)
	_check(Armory.get_equipped(Armory.PLAYER_ID, Enums.EquipSlot.MAIN) == uid, "권총을 장착함")
	if shots:
		await get_tree().create_timer(0.7).timeout
		await _shot("i_equipped")
	UI.close(&"bag")
	await _frames(10)
	_check(UI.tutorial.current_step() == &"talk", "대화 안내 (지금 %s)" % UI.tutorial.current_step())
	if shots:
		await get_tree().create_timer(0.7).timeout
		await _shot("i_talk_spot")
	player.global_position = intro.interior.patient_point() + Vector3(1.4, 0, 0.6)
	await _frames(5)
	player.interact()
	await _until(func() -> bool: return UI.cinematic.is_talking(), "대화가 시작됨", 5.0)
	var n := 0
	while UI.cinematic.is_talking() and n < 40:
		await get_tree().create_timer(0.5).timeout
		if n == 2 and shots:
			await _shot("i_talk")
		var ev := InputEventKey.new()
		ev.keycode = KEY_F
		ev.pressed = true
		UI.cinematic._input(ev)
		n += 1
	_check(GameState.has_flag(IntroCutscene.FLAG_TALKED), "방송실 지기가 의사를 부탁함")
	_check(Colony.get_resident(&"broadcaster").is_empty(), "방송실 지기는 주민이 아님 (고정 NPC)")
	await get_tree().create_timer(0.8).timeout
	_check(UI.tutorial.current_step() == &"exit", "나가기 안내 (지금 %s)" % UI.tutorial.current_step())
	if shots:
		await _shot("i_exit_spot")
	player.global_position = intro.interior.door_point() + Vector3(0, 0, -0.9)
	await _frames(5)
	player.interact()
	return await _until(func() -> bool: return get_tree().get_first_node_in_group(IntroCutscene.GROUP) == null, "집을 나와 기지로", 10.0)


## Every base screen once, with a few residents and resources, one shot each (UI review).
## The shots show paid assets: delete them after looking.
func _quick_screens() -> void:
	_step("quick_screens")
	await _until(func() -> bool: return UI.is_open(&"title"), "타이틀")
	await _shot("s_title")
	UI.get_screen(&"title").list.focus_row(&"new")
	await _frames(3)
	(UI.get_screen(&"title").find_child("start", true, false) as Button).pressed.emit()
	await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.BASE_MORNING, "기지")
	await _loading_done()
	await _intro(false)
	UI.tutorial.skip()
	for p: Dictionary in DemoProfiles.PROFILES:
		if Colony.get_resident(p.id).is_empty():
			Colony.add_resident(p.duplicate(true))
	Economy.set_cap_bonus(500)
	Economy.apply({&"wood": 60, &"stone": 40, &"food": 30, &"scrap": 20, &"cloth": 10, &"plank": 25, &"medicine": 6})
	await get_tree().create_timer(1.5).timeout
	await _shot("s_base_hud")
	var someone: StringName = Colony.active_resident_ids()[0]
	for entry: Array in [[&"build", {}], [&"residents", {"id": someone}], [&"craft", {}], [&"armory", {}],
			[&"journal", {}], [&"outposts", {}], [&"relations", {}], [&"dialog", {"resident_id": someone}],
			[&"gift", {"resident_id": someone}], [&"welcome", {"resident_id": someone}], [&"settings", {}],
			[&"pause", {}]]:
		UI.open(entry[0], entry[1])
		await _frames(25)
		await get_tree().create_timer(0.6).timeout
		_check(UI.is_open(entry[0]), "%s 화면이 열림" % entry[0])
		await _shot("s_" + String(entry[0]))
		UI.close(entry[0])
		await _frames(8)
	UI.base_hud._menu_buttons[&"@sortie"].pressed.emit()
	await _until(func() -> bool: return UI.is_open(&"sortie_prep"), "출격 준비")
	await _frames(20)
	await _shot("s_sortie_prep")
	var prep: Node = UI.get_screen(&"sortie_prep")
	var rows := 0
	for c in prep._regions_box.get_children():
		if c is Button:
			rows += 1
	_check(rows == 2, "출격 준비에 맵이 있는 지역 2곳만 뜸 (%d곳)" % rows)
	prep.close()
	await _frames(10)
	UI.base_hud._menu_buttons[&"@stay"].pressed.emit()
	await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.BASE_STAY, "머무르기")
	_flow_prompt_button("하루 마치기").pressed.emit()
	await _until(func() -> bool: return UI.is_open(&"evening") or UI.is_open(&"welcome"), "저녁")
	var guard := 0
	while UI.is_open(&"welcome") and guard < 40:
		guard += 1
		var w: Node = UI.get_screen(&"welcome")
		if w._next_button != null:
			w._next_button.pressed.emit()
		await _frames(4)
	await _until(func() -> bool: return UI.is_open(&"evening"), "저녁 정산")
	await _frames(20)
	await _shot("s_evening")


## A rainy day at the base and in the park, a few seconds each (for --write-movie / shots).
func _quick_rain() -> void:
	_step("quick_rain")
	await _until(func() -> bool: return UI.is_open(&"title"), "타이틀")
	UI.get_screen(&"title").list.focus_row(&"new")
	await _frames(3)
	(UI.get_screen(&"title").find_child("start", true, false) as Button).pressed.emit()
	await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.BASE_MORNING, "기지")
	await _loading_done()
	await _intro(false)
	UI.tutorial.skip()
	GameState.set_weather(Enums.Weather.RAIN)
	await get_tree().create_timer(4.0).timeout
	_check(Fx.rain.amount() > 0.9, "비가 오면 기지에 비가 보임 (%.2f)" % Fx.rain.amount())
	await _shot("rain_base")
	await get_tree().create_timer(3.0).timeout
	if not await _sortie(&"city_park"):
		return
	GameState.set_weather(Enums.Weather.RAIN)
	await get_tree().create_timer(4.0).timeout
	await _shot("rain_park")
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	for a: StringName in [&"move_up", &"move_right"]:
		Input.action_press(a)
	await get_tree().create_timer(3.0).timeout
	for a: StringName in [&"move_up", &"move_right"]:
		Input.action_release(a)
	await _shot("rain_park_walk")
	GameState.set_weather(Enums.Weather.CLEAR)
	await get_tree().create_timer(3.0).timeout
	_check(Fx.rain.amount() < 0.05, "비가 그치면 사라짐 (%.2f)" % Fx.rain.amount())


## Short look at the base: 45° camera, no player, grid while placing, [클릭] chip on hover.
func _quick_base() -> void:
	_step("quick_base")
	await _until(func() -> bool: return UI.is_open(&"title"), "타이틀")
	UI.get_screen(&"title").list.focus_row(&"new")
	await _frames(3)
	(UI.get_screen(&"title").find_child("start", true, false) as Button).pressed.emit()
	await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.BASE_MORNING, "기지")
	await _loading_done()
	await _intro(false)
	UI.tutorial.skip()
	await get_tree().create_timer(1.0).timeout
	_check(get_viewport().get_camera_3d() is BaseCamera, "기지 카메라가 BaseCamera")
	_check(get_tree().get_first_node_in_group(&"player") == null, "기지에 걷는 플레이어가 없음")
	await _shot("base_camera")
	UI.base_hud._menu_buttons[&"build"].pressed.emit()
	await _until(func() -> bool: return UI.is_open(&"build"), "건설 화면")
	var screen: Node = UI.get_screen(&"build")
	screen._sel = &"bonfire"
	screen._fill()
	_button(screen._detail, "놓을 곳 고르기").pressed.emit()
	await _until(func() -> bool: return is_instance_valid(UI.build_place_hud), "②놓기")
	var base := _world_scene()
	var spot := _find_spot(base.grid, &"bonfire")
	base.build_mode.preview_cell(spot["zone_id"], spot["cell"])
	await _frames(10)
	await _shot("base_grid")
	base.build_mode.preview_cell(spot["zone_id"], spot["cell"])
	var uid: StringName = base.build_mode.confirm()
	await _until(func() -> bool: return UI.is_open(&"build"), "현장 카드")
	_button(UI.get_screen(&"build")._detail, "이대로 짓기").pressed.emit()
	await _frames(10)
	var cam := get_viewport().get_camera_3d()
	var at: Vector3 = base.grid.footprint_center(spot["zone_id"], spot["cell"], Vector2i.ONE)
	(cam as BaseCamera).focus = at + Vector3(0, 0, 4)
	await _frames(30)
	var hover_at := cam.unproject_position(at)
	for i in 15:  # again every frame: a real mouse moving over the window would win otherwise
		Input.warp_mouse(hover_at)
		await _frames(1)
	print("[quick_base] site=%s hover_at=%s mouse=%s pick=%s" % [at, hover_at, get_viewport().get_mouse_position(),
		(cam as BaseCamera)._pick(hover_at)])
	_check(not (cam as BaseCamera).hover.is_empty(), "건물에 마우스를 올리면 안내가 뜸: %s" % (cam as BaseCamera).hover.get("text", ""))
	await _shot("base_hover")


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
	var able := Colony.active_resident_ids().filter(func(id: StringName) -> bool:
		return int(Colony.get_resident(id).get("health", 0)) == Enums.HealthState.OK)
	if Colony.active_resident_ids().is_empty():
		_check(put == null and _label_with(site._detail, "주민이 없") != null, "주민이 없으면 현장 카드가 그렇게 알려 줌")
		_unstaffed_site = true
	elif able.is_empty():
		# Only injured residents: the card says why nobody can go.
		_check(put == null and _label_with(site._detail, "부상") != null, "다친 주민뿐이면 현장 카드가 '부상'이라고 알려 줌")
		_unstaffed_site = true
	elif _check(put != null, "현장에 보낼 주민이 있음"):
		put.pressed.emit()
		await _frames(3)
		_check(not (Colony.get_building(uid)["workers"] as Array).is_empty(), "배정하면 현장 일손이 생김")
	await _shot("build_site")
	_button(site._detail, "이대로 짓기").pressed.emit()
	await _until(func() -> bool: return not UI.is_open(&"build"), "현장 카드가 닫힘")
	print("[bot] after close ids=", Colony.buildings.keys(), " uid still=", Colony.buildings.has(uid))
	await _frames(10)


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
	if _doctor_node != null and is_instance_valid(_doctor_node):
		_doctor_node.global_position = point.global_position + Vector3(1.0, 0.1, 0.5)  # he kept up
		_doctor_node = null
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
	if res != null:  # already gone = something moved on to the evening (a key press in the window)
		res._go.pressed.emit()
	else:
		print("[bot] result screen closed before the bot pressed it (state %s)" % Enums.FlowState.keys()[GameState.flow_state])
	if not await _until(func() -> bool: return GameState.flow_state == Enums.FlowState.EVENING, "결과 → 저녁"):
		return false
	await _frames(20)
	# 새 식구 인사 for anyone rescued
	var guard := 0
	while UI.is_open(&"welcome") and guard < 40:
		guard += 1
		var w: Node = UI.get_screen(&"welcome")
		if guard == 1:
			await _shot("welcome")
		w._on_choice(&"hello")  # 새 식구 인사: one line, "반가워요" (2026-11-06)
		await _frames(4)
	return await _evening_night(next_day)


func _evening_night(next_day: int) -> bool:
	var guard := 0
	while UI.is_open(&"welcome") and guard < 40:
		guard += 1
		var w: Node = UI.get_screen(&"welcome")
		if guard == 1:
			await _shot("welcome")
		w._on_choice(&"hello")  # 새 식구 인사: one line, "반가워요" (2026-11-06)
		await _frames(4)
	await _until(func() -> bool: return UI.is_open(&"evening"), "저녁 정산 화면이 열림")
	await _frames(10)
	if _watch_produced != &"":
		var made := float((SceneRouter.last_evening_report.get("produced", {}) as Dictionary).get(_watch_produced, 0.0))
		_check(made > 0.0, "저녁 정산: 배정한 주민이 %s를 생산함 (+%s)" % [_watch_produced, made])
		_watch_produced = &""
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
