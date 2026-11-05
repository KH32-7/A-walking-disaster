class_name IntroTutorial
extends Node
## New-game tutorial (사용자 요청 2026-11-06), replacing the old first-day guide card. Owner: Lane D.
##   house (IntroCutscene): open the case → take the 권총 → equip it → close the bag → talk to 한도윤
##                          → walk out.
##   base:  출격 → pick the park.
##   park:  quest 「의사를 찾아서」 shown on arrival (Quests.start) → go to the 관리사무소 (double yellow
##          diamond on the minimap and M map) → kill the blobs around it → help the doctor up → extract.
##   after: the doctor joins; 의무실 can be built (infirmary requires_former_job = doctor).
## Every frame the step is worked out again from the game state (flags, open screens, bag, quest),
## never from a stored index, so closing the bag early, dying in the park or loading a save all land
## on the right step. Each step shows UI.spotlight: a hole over the thing to use plus a key card.

const QUEST := &"tutorial_doctor"
const REGION := &"city_park"
const OFFICE_MARKER := &"RescueSpot_rs_office"
const DOCTOR_ID := &"demo_doctor"
const FLAG_DONE := &"tutorial_done"
const FLAG_WELCOMED := &"tutorial_welcomed"
const GUARD_DEF := "res://data/monsters/vine_tendril.tres"
const GUARD_COUNT := 4
## The guards stand this far around the office door (m); "near the office" for the hints.
const GUARD_RING := 7.0
const NEAR_OFFICE := 26.0
const NEAR_DOCTOR := 6.0
const WELCOME_SEC := 9.0

var _step := &""
var _guards: Array = []
var _guards_sortie := -1
var _welcome_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func active() -> bool:
	return GameState.flow_state != Enums.FlowState.TITLE and GameState.has_flag(IntroCutscene.FLAG_PENDING) \
		and not GameState.has_flag(FLAG_DONE)


func current_step() -> StringName:
	return _step


## Ends the tutorial for this game (debug, bot).
func skip() -> void:
	GameState.set_flag(FLAG_DONE)
	_show(&"")


func _process(delta: float) -> void:
	if not active():
		_show(&"")
		return
	_show(_work_out(delta))


func _work_out(delta: float) -> StringName:
	var s := GameState.flow_state
	var intro := _intro()
	if intro != null and intro.phase() == &"cinematic":
		return &""
	if intro != null and intro.phase() == &"house":
		return _house_step()
	if Quests.is_completed(QUEST):
		if s in [Enums.FlowState.RESULT, Enums.FlowState.EVENING, Enums.FlowState.NIGHT, Enums.FlowState.BASE_MORNING]:
			if UI.stack_ids().is_empty():
				_welcome_t += delta  # counts only while the card can be seen
			if _welcome_t >= WELCOME_SEC:
				GameState.set_flag(FLAG_DONE)
				return &""
			return &"welcome"
		return &""
	match s:
		Enums.FlowState.BASE_MORNING:
			if not GameState.has_flag(IntroCutscene.FLAG_HOUSE_DONE):
				return &""
			return &"sortie_go" if UI.is_open(&"sortie_prep") else &"sortie"
		Enums.FlowState.SORTIE_PREP:
			return &"sortie_go"
		Enums.FlowState.FIELD:
			return _field_step()
	return &""


func _house_step() -> StringName:
	var gun := Armory.get_equipped(Armory.PLAYER_ID, Enums.EquipSlot.MAIN)
	var in_bag := _bag_pistol()
	if UI.is_open(&"bag"):
		if gun != &"":
			return &"close_bag"
		return &"equip" if in_bag != &"" else &"take_gun"
	if UI.cinematic.is_talking():
		return &""
	if gun == &"":
		return &"chest_again" if in_bag != &"" else &"chest"
	return &"exit" if GameState.has_flag(IntroCutscene.FLAG_TALKED) else &"talk"


func _field_step() -> StringName:
	if FieldState.region_id != REGION or not GameState.has_flag(IntroCutscene.FLAG_TALKED):
		return &""
	if not Quests.is_active(QUEST) and not Quests.is_completed(QUEST):
		Quests.start(QUEST, &"intro_doyun")  # Quests posts the "새 의뢰" toast itself
	_spawn_guards()
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	var doctor := _doctor()
	if p == null:
		return &""
	if doctor != null and doctor.is_rescued():
		return &"extract"
	var office := _office_pos()
	var alive := _guards.filter(func(m) -> bool: return is_instance_valid(m) and not m.is_queued_for_deletion() and m.hp > 0.0)
	if not alive.is_empty() and p.global_position.distance_to(office) < NEAR_OFFICE:
		return &"fight"
	if doctor != null and p.global_position.distance_to(doctor.global_position) < NEAR_OFFICE:
		return &"rescue"
	return &"quest"


# ---------------- what each step shows ----------------

func _show(step: StringName) -> void:
	var sp := UI.spotlight
	if sp == null:
		return
	if step != _step:
		_step = step
		if step == &"":
			sp.clear()
	if step == &"":
		return
	var intro := _intro()
	match step:
		&"chest":
			_world(intro.interior.chest if intro else null, "총이 든 가방이에요. 가까이 가서 열어 봐요.",
				[["WASD", "이동"], ["F", "열기"]], 90.0, 0.4)
		&"chest_again":
			_world(intro.interior.chest if intro else null, "권총을 아직 안 들었어요. 상자를 다시 열면 가방이 열려요.",
				[["F", "열기"]], 90.0, 0.4)
		&"take_gun":
			var bag := UI.get_screen(&"bag")
			var cell: Control = bag.call(&"loot_cell", 0) if bag != null and bag.has_method(&"loot_cell") else null
			_control(cell, "권총이에요! 눌러서 가방에 넣어요.", [["클릭", "챙기기"]])
		&"equip":
			var bag := UI.get_screen(&"bag")
			var r: Rect2 = bag.call(&"bag_entry_rect", _bag_pistol()) if bag != null else Rect2()
			if r.size == Vector2.ZERO:
				sp.clear()
			elif sp.current_text() != _EQUIP_TEXT:
				sp.focus_rect(r, _EQUIP_TEXT, [["우클릭", "메뉴"], ["장착", "손에 들기"]])
			else:
				sp.move_rect(r)
		&"close_bag":
			var bag := UI.get_screen(&"bag")
			var cell: Control = bag.call(&"equip_cell", Enums.EquipSlot.MAIN) if bag != null else null
			_control(cell, "손에 들었어요. 가방을 닫아요.", [["Esc", "닫기"]])
		&"talk":
			_world(intro.interior.patient if intro else null, "다친 사람이 있어요. 말을 걸어 봐요.",
				[["F", "이야기하기"]], 120.0, 0.6)
		&"exit":
			_world(intro.interior.door if intro else null, "공원에 의사가 있대요. 밖으로 나가요.",
				[["F", "나가기"]], 100.0, 1.0)
		&"sortie":
			var hud: BaseHud = UI.base_hud
			var b: Button = hud.menu_button(&"@sortie") if hud != null else null
			_control(b, "공원으로 의사를 찾으러 가요.", [["Enter", "출격"]], 12.0)
		&"sortie_go":
			_card("'숲이 된 도심 공원'을 고르고 출격해요. 해가 지기 전에 돌아와야 해요.", [["클릭", "고르기"], ["Enter", "출격"]])
		&"quest":
			_card("새 의뢰 · 의사를 찾아서\n의사는 관리사무소 건물 안에 있어요. 미니맵과 지도의 노란 이중 마름모로 가요.",
				[["WASD", "이동"], ["M", "지도"], ["Shift", "달리기"]])
		&"fight":
			_card("관리사무소를 마물이 지키고 있어요! 조준하고 쏴요.",
				[["우클릭", "조준"], ["클릭", "사격"], ["R", "재장전"], ["Space", "구르기"]])
		&"rescue":
			_world(_doctor(), "의사 선생님이에요. 일으켜 세워요.", [["F", "일으켜 세우기"]], 110.0, 0.9)
		&"extract":
			_card("의사 선생님이 따라와요. 초록 마름모 탈출 지점에 잠깐 서 있으면 기지로 돌아가요.", [["M", "탈출 지점 찾기"]])
		&"welcome":
			_card("의사가 기지에 왔어요! 이제 '건설'에서 의무실을 지을 수 있어요. 한도윤의 다리도 고칠 수 있겠어요.", [])


const _EQUIP_TEXT := "가방에 들어왔어요. 권총을 우클릭하고 '장착'을 눌러요."


func _world(node: Node3D, text: String, keys: Array, radius: float, lift: float) -> void:
	if UI.spotlight.current_text() != text:
		UI.spotlight.focus_world(node, text, keys, radius, lift)


func _control(c: Control, text: String, keys: Array, pad := 10.0) -> void:
	if UI.spotlight.current_text() != text:
		UI.spotlight.focus_control(c, text, keys, pad)


func _card(text: String, keys: Array) -> void:
	if not UI.stack_ids().is_empty() and not UI.is_open(&"sortie_prep"):
		UI.spotlight.clear()  # a goal card waits while the map / journal is open
		return
	if UI.spotlight.current_text() != text:
		UI.spotlight.focus_rect(Rect2(), text, keys)


# ---------------- field ----------------

## Blob-ish guards around the office, once per sortie while the quest runs.
func _spawn_guards() -> void:
	if _guards_sortie == FieldState.sortie_seed and not _guards.is_empty():
		return
	var spawner := get_tree().root.find_child("RoamingSpawner", true, false) as RoamingSpawner
	var office := _office_pos()
	if spawner == null or office == Vector3.INF or not ResourceLoader.exists(GUARD_DEF):
		return
	_guards_sortie = FieldState.sortie_seed
	_guards.clear()
	var def := load(GUARD_DEF) as MonsterDef
	for i in GUARD_COUNT:
		var a := TAU * float(i) / GUARD_COUNT + 0.4
		_guards.append_array(spawner.spawn_group(office + Vector3(cos(a), 0, sin(a)) * GUARD_RING, 1, def))


func _office_pos() -> Vector3:
	var scene := get_tree().current_scene
	var n := scene.find_child(String(OFFICE_MARKER), true, false) as Node3D if scene else null
	if n == null:
		for m in get_tree().get_nodes_in_group(RescueSpot.GROUP):
			if (m as Node).name == OFFICE_MARKER:
				n = m
	return n.global_position if n != null else Vector3.INF


func _doctor() -> RescueTarget:
	for t in get_tree().get_nodes_in_group(RescueTarget.GROUP):
		if t is RescueTarget and StringName((t as RescueTarget).profile.get("id", &"")) == DOCTOR_ID:
			return t
	return null


func _intro() -> IntroCutscene:
	return get_tree().get_first_node_in_group(IntroCutscene.GROUP) as IntroCutscene


## Uid of a 권총 in the bag, or &"".
func _bag_pistol() -> StringName:
	for e: Dictionary in Bag.entries():
		if StringName(e.get("kind", &"")) == &"item":
			var it := Armory.get_item(StringName(e.ref))
			if it != null and it.def_id == &"pistol":
				return StringName(e.ref)
	return &""
