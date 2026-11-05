extends Node3D
## #125 parts 3·4·7 preview: funeral · memorial · outposts · residents (grief / stranded / missing /
## 출산 대기) · sortie prep companions. Fake state only, built through Colony's own functions where they
## exist (add_resident, add_relation, _kill, _on_companion_stranded, _settle_loss, build_outpost).
## Optional: -- --view=funeral|memorial|memorial_day|outposts|outposts_empty|residents|sortie
##           --shot=user://x.png

var _shot := ""
var _view := "funeral"
var _t := 0.0
var ids := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # screens pause the tree
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
	UI.close_all()  # the title screen opens on boot
	_scene()
	fake_state()
	match _view:
		"funeral":
			UI.open(&"funeral", {"resident_ids": Colony.pending_funeral()})
		"memorial":
			GameState.flow_state = Enums.FlowState.NIGHT
			UI.open(&"memorial")
			(UI.get_screen(&"memorial") as MemorialScreen).visit(ids.doyun)
		"memorial_day":
			UI.open(&"memorial")
		"outposts":
			UI.open(&"outposts", {"node_id": &"outpost_east"})
		"outposts_empty":
			UI.open(&"outposts", {"node_id": &"outpost_flooded_mall"})
		"residents":
			UI.open(&"residents", {"id": ids.sora})
		"sortie":
			UI.open(&"sortie_prep")


## Day 14 after a raid: 정다온 died (funeral pending), 이은비 is stranded in the mall, 최민 went
## missing, 문소라 waits for a birth, four outposts in every state.
func fake_state() -> void:
	GameState.day = 13
	Colony.threat = 34
	Economy.set_cap_bonus(5000)
	Economy.apply({&"wood": 142, &"stone": 64, &"scrap": 37, &"food": 48, &"parts": 6, &"cloth": 9})
	var people := [["doyun", "강도윤", 8], ["sora", "문소라", 6], ["jiho", "한지호", 5], ["haneul", "윤하늘", 4],
		["seojin", "박서진", 5], ["eunbi", "이은비", 6], ["min", "최민", 5], ["daon", "정다온", 5]]
	for p: Array in people:
		ids[p[0]] = Colony.add_resident({"id": StringName("preview_" + p[0]), "name": p[1], "age_stage": Enums.AgeStage.ADULT,
			"stats": {&"str": 6, &"dex": 5, &"sense": p[2], &"heart": 4}, "access_needs": [], "traits": []})
	Colony.get_resident(ids.daon)["story"] = {"background": "물에 잠긴 상가에서 끝까지 무전을 붙들고 있던 사람. 아이들에게 별자리를 가르쳐 주곤 했다.", "fragments": []}
	Colony.add_relation(ids.daon, ids.jiho, 70)
	Colony.add_relation(ids.daon, ids.haneul, 55)
	# 문소라 · 박서진 가족: 아기를 기다리는 중 (sortie_block_reason).
	var meta: Dictionary = Colony._relation_meta(ids.sora, ids.seojin)
	meta["due_day"] = 16
	meta["carrier"] = ids.sora
	# 고립 / 실종.
	Settings.set_value(&"strand_days", 3)
	Colony._on_companion_stranded(ids.eunbi, &"flooded_mall")
	Colony._on_companion_stranded(ids.min, &"flooded_mall")
	Colony.residents[ids.min]["strand_days_left"] = 1
	Colony._settle_loss([])  # 최민 → 실종 (resident_missing), 이은비 2일 남음
	GameState.day = 14
	Colony._kill(ids.daon, &"raid")
	# 추모비 (첫 사망 뒤 열림).
	var stone := Colony.place_building(&"memorial", Vector2i(2, 8), 0, &"", false)
	Colony.complete_building(stone)
	Economy.set_cap_bonus(5000)  # completing a building recounts the storage cap
	# 전초기지: 북 가동 · 동 주둔 부족 · 남 부서짐 · 서 짓는 중 · 상가 입구 빈 노드.
	for n in [&"outpost_north", &"outpost_east", &"outpost_south"]:
		Economy.apply(OutpostRules.COST)
		Colony.build_outpost(n)
		Colony.outposts[n]["ready_day"] = GameState.day
	Economy.apply(OutpostRules.COST)
	Colony.build_outpost(&"outpost_west")
	Colony.assign_garrison(&"outpost_north", ids.doyun)
	Colony.assign_garrison(&"outpost_north", ids.haneul)
	Colony.assign_garrison(&"outpost_east", ids.jiho)
	Colony.outposts[&"outpost_south"]["damaged"] = true
	Colony.outposts_changed.emit()


func _scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("2a3340")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("a9b6c8")
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.8
	sun.light_color = Color("ffe9cc")
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 22
	add_child(cam)
	cam.position = Vector3(12, 14, 16)
	cam.look_at(Vector3(2, 0, 0))
	_box(Vector3(0, -0.1, 0), Vector3(40, 0.2, 40), "toon_concrete")
	_box(Vector3(-4, 3, -9), Vector3(18, 6, 4), "toon_concrete")
	for i in 9:
		_box(Vector3(-10 + i * 2.2, 0.9, -3), Vector3(0.35, 1.8, 2.0), "toon_wood")
	_box(Vector3(1, 0.8, 3), Vector3(1.0, 1.6, 0.5), "toon_concrete")  # memorial stone


func _box(pos: Vector3, size: Vector3, mat: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = load("res://art/materials/%s.tres" % mat)
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	if _shot != "" and _t > 1.0 and _t - delta <= 1.0:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
