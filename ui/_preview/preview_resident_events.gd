extends Node3D
## #125 parts 1·2·5 preview: 편견 소문 선택, 아이 맞이 대화, 이름 짓기, 결혼식 준비 on a fake base.
## Fake state only (some private Colony calls to stage it, preview only): a resident with 마물 흔적
## and two who hold the prejudice, a married couple with a family house who want a child, a newborn
## waiting for a name, an engaged pair, and tonight's prejudice_talk.
## Optional: -- --view=<name> --shot=user://x.png
##   prejudice | prejudice_done | wish | wish_method | wish_done | wish_blocked | naming | naming_error |
##   naming_meet | wedding | wedding_short | wedding_ready | night_talk | night_proposal | detail | detail_family

var _shot := ""
var _view := "prejudice"
var _t := 0.0
var _ids := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # screens pause the tree
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
	UI.close_all()
	_fake_state()
	_scene()
	if UI.notice_toast != null:
		MenuScreen.clear(UI.notice_toast)  # the staging notices would cover the choices
	match _view:
		"prejudice", "prejudice_done":
			UI.open(&"prejudice_choice", {"resident_id": _ids.marked})
			if _view == "prejudice_done":
				UI.get_screen(&"prejudice_choice").call(&"_on_choice", PrejudiceRules.CHOICE_DEFEND)
		"wish", "wish_method", "wish_done", "wish_blocked":
			if _view == "wish_blocked":
				Colony.residents[_ids.wife]["morale"] = 40
				Economy.apply({&"food": -Economy.get_amount(&"food") + 10})
			UI.open(&"child_wish", {"a": _ids.wife, "b": _ids.husband})
			var w := UI.get_screen(&"child_wish")
			if _view in ["wish_method", "wish_done"]:
				w.call(&"_on_choice", &"now")
			if _view == "wish_done":
				w.call(&"_on_choice", &"birth")
		"naming", "naming_error", "naming_meet":
			UI.open(&"child_naming", {"resident_id": _ids.baby, "method": Enums.ArrivalMethod.BIRTH})
			var n := UI.get_screen(&"child_naming")
			if _view == "naming_error":
				n.call(&"save_name", "이름이너무길어서안돼요")
			elif _view == "naming_meet":
				n.call(&"save_name", "하람")
		"wedding", "wedding_short", "wedding_ready":
			if _view == "wedding_short":
				Economy.apply({&"cloth": -Economy.get_amount(&"cloth") + 2})
			UI.open(&"wedding_prep", {"a": _ids.guard, "b": _ids.teacher})
			if _view == "wedding_ready":
				UI.get_screen(&"wedding_prep").call(&"_on_choice", &"prepare")
		"night_talk":
			Colony.night_queue = [{"event_id": &"prejudice_talk", "participants": [_ids.holder, _ids.marked] as Array[StringName],
				"choices": [&"watch"], "night_day": GameState.day}]
			Colony.prejudice_chains_data[_ids.marked]["step"] = PrejudiceRules.STEP_INCIDENT
			UI.open(&"night_event")
			UI.get_screen(&"night_event").call(&"_on_choice", &"watch")
		"night_proposal":
			var lov: Array[StringName] = [_ids.cook, _ids.guard2]
			Colony.night_queue = [{"event_id": &"proposal", "participants": lov, "choices": [&"watch"], "night_day": GameState.day}]
			UI.open(&"night_event")
			UI.get_screen(&"night_event").call(&"_on_choice", &"watch")
		"detail_family":
			UI.open(&"residents", {"id": _ids.guard})
		_:
			UI.open(&"residents", {"id": _ids.marked})


func _fake_state() -> void:
	GameState.day = 24
	Economy.set_cap_bonus(5000)
	Economy.apply({&"food": 120, &"cloth": 9, &"wood": 40, &"parts": 5, &"scrap": 20, &"stone": 15})
	var marked := Colony.add_resident({"id": &"pv_marked", "name": "주하린", "age_stage": Enums.AgeStage.ADULT,
		"former_job": &"nurse", "traits": [&"monster_mark"], "joined_day": 10,
		"story": {"background": "팔에 마물 흔적이 남은 간호사.", "fragments": [
			"그 흔적은 아이를 감싸다 긁힌 자국이야. 그 뒤로 열이 난 적도 없어.",
			"병원에서 마지막까지 남아 환자들을 내보냈어. 그래서 늦게 나왔지.",
		]}})
	var holder := Colony.add_resident({"id": &"pv_holder", "name": "강도윤", "age_stage": Enums.AgeStage.ADULT,
		"former_job": &"laborer", "traits": [&"prejudiced"], "joined_day": 2})
	var holder2 := Colony.add_resident({"id": &"pv_holder2", "name": "문옥자", "age_stage": Enums.AgeStage.ELDER,
		"former_job": &"cook", "traits": [&"prejudiced"], "joined_day": 3})
	var wife := Colony.add_resident({"id": &"pv_wife", "name": "한소율", "age_stage": Enums.AgeStage.ADULT,
		"former_job": &"teacher", "gender": "female", "joined_day": 1})
	var husband := Colony.add_resident({"id": &"pv_husband", "name": "백지호", "age_stage": Enums.AgeStage.ADULT,
		"former_job": &"carpenter", "gender": "male", "joined_day": 1})
	var guard := Colony.add_resident({"id": &"pv_guard", "name": "남궁태", "age_stage": Enums.AgeStage.ADULT,
		"former_job": &"police", "joined_day": 4})
	var teacher := Colony.add_resident({"id": &"pv_teacher", "name": "하윤서", "age_stage": Enums.AgeStage.ADULT,
		"former_job": &"teacher", "joined_day": 5})
	var cook := Colony.add_resident({"id": &"pv_cook", "name": "변미숙", "age_stage": Enums.AgeStage.ADULT,
		"former_job": &"cook", "joined_day": 6})
	var guard2 := Colony.add_resident({"id": &"pv_guard2", "name": "오세준", "age_stage": Enums.AgeStage.ADULT,
		"former_job": &"mechanic", "joined_day": 6})
	var looks := {marked: {"preset": &"tied_nurse"}, holder: {"preset": &"worker_short"}, holder2: {"preset": &"elder_grey"},
		wife: {"preset": &"long_rain"}, husband: {"preset": &"rescuer", "hair_color": Color("3b2a22")},
		guard: {"preset": &"rescuer"}, teacher: {"preset": &"bob_teal"}, cook: {"preset": &"tied_nurse", "outfit_color": Color("c9a24a")},
		guard2: {"preset": &"worker_short", "hair": "bob"}}
	for id: StringName in looks:
		Colony.set_appearance(id, looks[id])
	for id in looks:
		Colony.residents[id]["morale"] = 70
	Colony.add_relation(marked, holder, -25)
	Colony.add_relation(marked, holder2, -10)
	Colony.add_relation(holder, holder2, 30)
	# 소문 (preview only: private Colony call).
	Colony._start_rumor(marked, [holder, holder2] as Array[StringName], [])
	# 결혼한 가족: 가족 숙소 + 의무실, 아이를 맞고 싶다.
	var house := _build(&"family_house")
	_build(&"infirmary")
	Colony.add_relation(wife, husband, 90)
	var m := Colony._relation_meta(wife, husband)
	m["flags"] = [Enums.RelationFlag.MARRIED]
	m["house_uid"] = house
	Colony._move_into_house([wife, husband], house)
	m["wish_day"] = GameState.day
	# 이름을 기다리는 아기 (a second married family; private _birth, preview only).
	var mom := Colony.add_resident({"id": &"pv_mom", "name": "차유나", "age_stage": Enums.AgeStage.ADULT, "gender": "female"})
	var dad := Colony.add_resident({"id": &"pv_dad", "name": "임재현", "age_stage": Enums.AgeStage.ADULT, "gender": "male"})
	Colony.set_appearance(mom, {"preset": &"long_rain", "hair_color": Color("7a4a2a")})
	Colony.set_appearance(dad, {"preset": &"worker_short"})
	var house2 := _build(&"family_house")
	Colony.add_relation(mom, dad, 88)
	var m2 := Colony._relation_meta(mom, dad)
	m2["flags"] = [Enums.RelationFlag.MARRIED]
	m2["house_uid"] = house2
	Colony._move_into_house([mom, dad], house2)
	m2["carrier"] = mom
	var baby: StringName = Colony._birth(m2)
	# 결혼 약속 (청혼 뒤), 빈 가족 숙소 하나.
	Colony.add_relation(guard, teacher, 85)
	Colony._set_lovers(guard, teacher, 5)
	Colony._apply_night_event({"event_id": &"proposal", "participants": [guard, teacher], "choices": [&"watch"],
		"night_day": GameState.day - 1}, &"")
	_build(&"family_house")
	# 청혼 직전의 연인 (night_proposal view).
	Colony.add_relation(cook, guard2, 85)
	Colony._set_lovers(cook, guard2, 2)
	Colony.last_night_results = []
	_ids = {"marked": marked, "holder": holder, "holder2": holder2, "wife": wife, "husband": husband, "baby": baby,
		"guard": guard, "teacher": teacher, "cook": cook, "guard2": guard2}


func _build(def_id: StringName) -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, &"front_yard", false)
	Colony.complete_building(uid)
	return uid


func _scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	var night := _view.begins_with("night") or _view.begins_with("prejudice")
	env.environment.background_color = Color("1c2433") if night else Color("6d8a73")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("8090b0") if night else Color("c9d6c0")
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.shadow_enabled = true
	sun.light_energy = 0.3 if night else 1.0
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 11
	add_child(cam)
	cam.position = Vector3(8, 9, 11)
	cam.look_at(Vector3(2.2, 0.6, 0))
	_box(Vector3(0, -0.1, 0), Vector3(30, 0.2, 30), "toon_concrete")
	_box(Vector3(-3, 2, -4), Vector3(16, 4, 0.4), "toon_concrete")
	_box(Vector3(-0.5, 0.25, -1.5), Vector3(2.4, 0.5, 0.6), "toon_wood")
	_box(Vector3(2.8, 0.4, -2.2), Vector3(0.9, 0.8, 0.9), "toon_wood")
	if night:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0.5, 0.8, 0.5)
		lamp.light_color = Color("ffa04a")
		lamp.light_energy = 3.0
		lamp.omni_range = 7.0
		add_child(lamp)


func _process(delta: float) -> void:
	_t += delta
	if _shot != "" and _t > 1.0 and _t - delta <= 1.0:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()


func _box(pos: Vector3, size: Vector3, mat: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = load("res://art/materials/%s.tres" % mat)
	add_child(mi)
