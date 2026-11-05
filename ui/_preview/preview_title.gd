extends Node3D
## D-19 preview: title, pause, loading / transition and ending card.
## Fake state only: saves go to a throwaway folder (slot 1: day 12, slot 3: day 3), a few residents
## join so Journal.epilogue() has real template lines.
##   -- --view=title|title_new|title_load|pause|pause_field|loading|loading_down|ending --shot=user://x.png
##   --at=0.25 takes the shot earlier (e.g. the Haesol stripe mid-slide).

const SAVE_DIR := "user://preview_title_saves"

var _shot := ""
var _view := "title"
var _t := 0.0
var _at := 1.2


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # pause screens stop the tree
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
		if a.begins_with("--at="):
			_at = float(a.trim_prefix("--at="))
	UI.close_all()
	_fake_saves()
	match _view:
		"title", "title_new", "title_load":
			UI.open(&"title")
			var s := UI.get_screen(&"title") as TitleScreen
			if _view == "title_new":
				s.list.focus_row(&"new")
				s.call_deferred(&"_enter_detail")
			elif _view == "title_load":
				s.list.focus_row(&"load")
				s.call_deferred(&"_enter_detail")
		"pause", "pause_field":
			_scene()
			GameState.day = 12
			if _view == "pause_field":
				GameState.flow_state = Enums.FlowState.FIELD
				FieldState.set(&"region_id", &"flooded_mall")
				GameState.weather = Enums.Weather.RAIN
			else:
				GameState.flow_state = Enums.FlowState.BASE_MORNING
			UI.open(&"pause")
		"loading", "loading_down":
			GameState.day = 12
			UI.open(&"loading", {"kind": &"sortie" if _view == "loading" else &"down", "region_id": &"flooded_mall",
				"auto_close": false})
		"ending":
			GameState.day = 31
			var cards := _fake_journal()
			# Hand-written preview cards so every status shape shows (실종 · 떠남 · 잃음).
			cards.append({"resident_id": &"pv_min", "name": "민서", "status": &"missing",
				"lines": ["민서는 침수 상가에서 돌아오지 못했다.", "공터 게시판에는 아직 민서의 이름이 붙어 있다."]})
			cards.append({"resident_id": &"pv_tae", "name": "태오", "status": &"left",
				"lines": ["태오는 가족을 찾아 대피선 쪽으로 떠났다."]})
			cards.append({"resident_id": &"pv_gu", "name": "구 씨", "status": &"dead",
				"lines": ["구 씨는 셋째 날 밤 습격 때 아이들을 지키다 쓰러졌다."]})
			UI.open(&"ending", {"ending": Enums.EndingChoice.STAY, "cards": cards, "index": 4})


func _fake_saves() -> void:
	SaveSystem.save_dir = SAVE_DIR
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	for s in SaveSystem.SLOT_COUNT:
		SaveSystem.delete_slot(s)
	var day := GameState.day
	GameState.day = 12
	SaveSystem.save_slot(0)
	GameState.day = 3
	SaveSystem.save_slot(2)
	GameState.day = day
	SaveSystem.current_slot = 0


func _fake_journal() -> Array:
	for r: Array in [[&"pv_dami", "정다미"], [&"pv_hyun", "서현"], [&"pv_ok", "옥순 할머니"], [&"pv_jun", "준"]]:
		Colony.add_resident({"id": r[0], "name": r[1], "age_stage": Enums.AgeStage.ADULT, "access_needs": []})
	Journal.call(&"_flush_arrivals")
	Journal.record(&"prejudice_resolved", {"resident_id": &"pv_jun", "other_id": &"pv_ok"})
	return Journal.epilogue(Enums.EndingChoice.STAY)


func _scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("4f6b55")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c9d6c0")
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16
	add_child(cam)
	cam.position = Vector3(10, 12, 14)
	cam.look_at(Vector3(4, 0, 0))
	_box(Vector3(0, -0.1, 0), Vector3(30, 0.2, 30), "toon_concrete")
	_box(Vector3(-3, 2, -5), Vector3(16, 4, 0.4), "toon_concrete")
	_box(Vector3(-1, 0.5, -2.5), Vector3(4, 1, 1.6), "toon_wood")
	_box(Vector3(2.5, 0.4, -1), Vector3(1, 0.8, 1), "toon_wood")
	_box(Vector3(5, 0.6, 2), Vector3(1.2, 1.2, 1.2), "toon_wood")


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
	if _shot != "" and _t > _at and _t - delta <= _at:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
