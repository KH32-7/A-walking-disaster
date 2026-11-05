extends Node3D
## D-13 preview: talk, gift, night event, relation map and 입주 의식 on a fake base.
## Fake state only: five residents with looks, trust, likes, story and relations of every stage,
## two queued night events and one rescued survivor waiting for the ceremony.
## Optional: -- --view=<name> --shot=user://x.png
##   dialog | dialog_talked | gift | gift_given | night | night_result | relations |
##   welcome | welcome_name | welcome_look | welcome_bed | welcome_talk

var _shot := ""
var _view := "dialog"
var _t := 0.0
var _ids := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # screens pause the tree
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
	_fake_state()
	_scene()
	var talker: StringName = _ids.mechanic
	match _view:
		"dialog":
			UI.open(&"dialog", {"resident_id": talker})
		"dialog_talked":
			UI.open(&"dialog", {"resident_id": talker})
			UI.get_screen(&"dialog").call(&"_on_choice", &"talk")
		"gift":
			UI.open(&"gift", {"resident_id": talker})
		"gift_given":
			UI.open(&"gift", {"resident_id": talker})
			var g := UI.get_screen(&"gift")
			g.set(&"_sel", &"parts")
			g.call(&"give")
		"night", "night_result":
			UI.open(&"night_event")
			if _view == "night_result":
				UI.get_screen(&"night_event").call(&"_on_choice", &"mediate")
		"relations":
			UI.open(&"relations", {"id": _ids.carpenter})
		_:
			UI.open(&"welcome", {"resident_id": _ids.newcomer})
			var w := UI.get_screen(&"welcome")
			var step: int = {"welcome_name": 1, "welcome_look": 2, "welcome_bed": 3, "welcome_talk": 4}.get(_view, 0)
			if step >= 1:
				Colony.set_nickname(_ids.newcomer, "도토리")
			if step >= 2:
				Colony.set_appearance(_ids.newcomer, {"preset": &"bob_teal", "hair": "tied", "hair_color": Color("7a4a2a")})
			w.set(&"step", step)
			w.call(&"_refresh")


func _fake_state() -> void:
	GameState.day = 12
	Economy.set_cap_bonus(5000)
	Economy.apply({&"food": 34, &"meal": 6, &"wood": 40, &"plank": 8, &"parts": 5, &"cloth": 12, &"herbs": 3,
		&"paint": 2, &"textbook": 1, &"battery": 2, &"scrap": 20})
	var a := Colony.add_resident({"id": &"pv_carpenter", "name": "윤기철", "nickname": "목수 할배",
		"age_stage": Enums.AgeStage.ELDER, "former_job": &"carpenter", "likes": [&"tea", &"woodwork"],
		"dislikes": [&"loud_noise"], "story": {"background": "다리를 다친 60대 전직 목수.",
			"fragments": ["경사로 만드는 법을 알고 있다.", "목공을 가르쳐 줄 수 있다."]}})
	var b := Colony.add_resident({"id": &"pv_mechanic", "name": "서하은", "nickname": "렌치",
		"age_stage": Enums.AgeStage.ADULT, "former_job": &"mechanic", "likes": [&"coffee", &"engine_parts"],
		"dislikes": [&"stairs"], "story": {"background": "멈춘 승강기에 갇혀 있던 휠체어 사용자. 전직 정비공.",
			"fragments": ["정비소를 맡겠다고 한다.", "동생이 북쪽 항구에 있었다."], "first_line": "고마워요. 바퀴가 끼어서 꼼짝도 못 했어요."}})
	var c := Colony.add_resident({"id": &"pv_cook", "name": "변미숙", "age_stage": Enums.AgeStage.ADULT,
		"former_job": &"cook", "likes": [&"sweet_food"], "story": {"background": "급식실 조리사."}})
	var d := Colony.add_resident({"id": &"pv_guard", "name": "남궁태", "age_stage": Enums.AgeStage.ADULT,
		"former_job": &"police", "story": {"background": "퇴직 경찰."}})
	var e := Colony.add_resident({"id": &"pv_teacher", "name": "하윤서", "age_stage": Enums.AgeStage.ADULT,
		"former_job": &"teacher", "story": {"background": "초등학교 교사."}})
	var looks := {a: {"preset": &"elder_grey"}, b: {"preset": &"worker_short", "hair": "bob", "hair_color": Color("1f1b1a")},
		c: {"preset": &"tied_nurse", "outfit_color": Color("c9a24a")}, d: {"preset": &"rescuer"},
		e: {"preset": &"long_rain"}}
	for id: StringName in looks:
		Colony.set_appearance(id, looks[id])
	Colony.add_trust(a, 46)
	Colony.add_trust(b, 22)
	Colony.add_trust(c, 8)
	Colony.add_trust(d, 61)
	Colony.add_trust(e, 35)
	Colony.residents[b]["known_likes"] = [&"engine_parts"]  # learned at the ceremony
	# Relations of every stage.
	Colony.add_relation(a, b, 45)    # 친구
	Colony.add_relation(a, e, 70)    # 절친
	Colony.add_relation(b, c, 12)    # 아는 사이
	Colony.add_relation(c, d, -30)   # 서먹함
	Colony.add_relation(d, b, -60)   # 앙숙
	Colony.add_relation(d, e, 75)
	Colony._set_lovers(d, e, 3)      # 연인 (preview only: private Colony call)
	Colony.add_relation(a, c, 55)
	Colony._relation_meta(a, c)["flags"] = [Enums.RelationFlag.MARRIED]  # 배우자 (preview only)
	Colony.add_relation(c, e, 4)
	# Tonight: a quarrel to mediate, then a bonfire.
	Colony.residents[d]["trust"] = 61
	Colony.night_queue = [
		{"event_id": &"quarrel", "participants": [b, d] as Array[StringName], "choices": [&"watch", &"mediate"], "night_day": 12},
		{"event_id": &"bonfire", "participants": [a, c, e] as Array[StringName], "choices": [&"watch"], "night_day": 12},
	]
	Colony.add_beds([&"main_hall_bed_7", &"main_hall_bed_8"] as Array[StringName])  # spare beds for the ceremony
	var n := Colony.add_resident({"id": &"pv_newcomer", "name": "오다은", "age_stage": Enums.AgeStage.TEEN,
		"former_job": &"student", "likes": [&"drawing", &"sweet_food"], "arrival_pending": true,
		"story": {"background": "옥상 물탱크 뒤에 숨어 사흘을 버틴 고등학생.", "first_line": "여기… 진짜 사람들이 사는 데예요?"}})
	_ids = {"carpenter": a, "mechanic": b, "cook": c, "guard": d, "teacher": e, "newcomer": n}


func _scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	var night := _view.begins_with("night")
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
	# A school courtyard corner: ground, wall, bench, crates.
	_box(Vector3(0, -0.1, 0), Vector3(30, 0.2, 30), "toon_concrete")
	_box(Vector3(-3, 2, -4), Vector3(16, 4, 0.4), "toon_concrete")
	_box(Vector3(-0.5, 0.25, -1.5), Vector3(2.4, 0.5, 0.6), "toon_wood")
	_box(Vector3(2.8, 0.4, -2.2), Vector3(0.9, 0.8, 0.9), "toon_wood")
	if night:
		var fire := OmniLight3D.new()
		fire.position = Vector3(0.5, 0.8, 0.5)
		fire.light_color = Color("ffa04a")
		fire.light_energy = 3.0
		fire.omni_range = 7.0
		add_child(fire)
	# The resident being talked to stands in the scene (left side, UI_RULES §4 장면형 화면).
	var who: StringName = _ids.newcomer if _view.begins_with("welcome") else _ids.mechanic
	var look := (load("res://art/characters/character.tscn") as PackedScene).instantiate() as CharacterLook
	add_child(look)
	look.age_stage = int(Colony.get_resident(who).get("age_stage", 3))
	look.apply(Colony.appearance_for_look(who))
	look.position = Vector3(0.3, 0, 0.6)
	look.rotation_degrees.y = 35
	var other := (load("res://art/characters/character.tscn") as PackedScene).instantiate() as CharacterLook
	add_child(other)
	other.apply(Colony.appearance_for_look(_ids.carpenter))
	other.age_stage = 4
	other.position = Vector3(-1.6, 0, -0.6)
	other.rotation_degrees.y = 60


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
