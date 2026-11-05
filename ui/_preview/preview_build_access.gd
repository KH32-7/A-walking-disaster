extends Node3D
## Issue #125 part 6 preview: build screen views 개간 · 수리·레벨업 · 접근성 보기 on a fake base.
## Fake state only: 6 residents (one wheelchair user, one learning Korean, one guardian), 체육관 being
## cleared, a damaged 작업장, a 모닥불 under repair, a worn 목책, a ramp and a picture sign.
## Optional: -- --view=build|clear|clear_start|repair|repairing|upgrade|wall|access --shot=user://x.png

const VIEWS := {
	"build": {"mode": &"build"},
	"clear": {"mode": &"clear", "zone": &"gym"},
	"clear_start": {"mode": &"clear", "zone": &"roof"},
	"repair": {"mode": &"repair", "uid": "workshop"},
	"repairing": {"mode": &"repair", "uid": "bonfire"},
	"upgrade": {"mode": &"repair", "uid": "kitchen"},
	"wall": {"mode": &"repair", "uid": "palisade"},
	"access": {"mode": &"access"},
}

var _shot := ""
var _view := "access"
var _t := 0.0
var _uids := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # screens pause the tree
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
	UI.close_all()  # the title screen opens on boot
	_scene()
	_fake_state()
	var args: Dictionary = VIEWS.get(_view, VIEWS["access"]).duplicate()
	if args.has("uid"):
		args["uid"] = _uids.get(args["uid"], &"")
	UI.open(&"build", args)


func _scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("5d8b4a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c9d6c0")
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 26
	add_child(cam)
	cam.position = Vector3(18, 22, 18)
	cam.look_at(Vector3.ZERO)
	_box(Vector3(0, -0.1, 0), Vector3(40, 0.2, 40), "toon_foliage")
	_box(Vector3(-2, 2, -6), Vector3(14, 4, 5), "toon_concrete")
	_box(Vector3(6, 0.7, 2), Vector3(3, 1.4, 3), "toon_wood")
	_box(Vector3(-6, 0.6, 4), Vector3(2.5, 1.2, 2.5), "toon_wood")


func _fake_state() -> void:
	Economy.set_cap_bonus(5000)
	Economy.apply({&"wood": 46, &"stone": 22, &"scrap": 38, &"food": 30, &"parts": 7, &"cloth": 9, &"plank": 4})
	Colony.tier = Enums.BaseTier.SETTLEMENT  # Lv2 facilities, 공원 숲 B
	var ids := []
	for p: Dictionary in [
		{"id": &"pv_haeun", "name": "서하은", "nickname": "렌치", "stats": {&"str": 7}},
		{"id": &"pv_doyun", "name": "강도윤", "stats": {&"str": 6}},
		{"id": &"pv_sora", "name": "문소라", "stats": {&"heart": 6}},
		{"id": &"pv_lin", "name": "린", "stats": {&"str": 5}, "access_needs": [Enums.AccessNeed.LANGUAGE]},
		{"id": &"pv_okja", "name": "박옥자", "age_stage": Enums.AgeStage.ELDER, "stats": {&"heart": 7},
			"access_needs": [Enums.AccessNeed.MOBILITY]},
		{"id": &"pv_jun", "name": "한준", "stats": {&"str": 4}, "access_needs": [Enums.AccessNeed.CARE]},
	]:
		var prof := p.duplicate()
		if not prof.has("age_stage"):
			prof["age_stage"] = Enums.AgeStage.ADULT
		if not prof.has("access_needs"):
			prof["access_needs"] = []
		ids.append(Colony.add_resident(prof))
	Colony.clear_zone(&"playground")
	_uids["ramp"] = _building(&"ramp", &"front_yard")
	_uids["sign"] = _building(&"picture_sign", &"main_hall")
	_uids["light"] = _building(&"warning_light", &"main_hall")
	_uids["workshop"] = _building(&"workshop", &"main_hall")
	_uids["kitchen"] = _building(&"kitchen", &"main_hall")
	_uids["bonfire"] = _building(&"bonfire", &"front_yard")
	_uids["palisade"] = _building(&"palisade", &"playground")
	_uids["lumber"] = _building(&"lumber_yard", &"playground")
	Colony.damage_building(_uids["workshop"], 999)
	Colony.damage_building(_uids["bonfire"], 999)
	Economy.apply(Colony.repair_cost(_uids["bonfire"]))  # pay for it with fake resources
	Colony.start_repair(_uids["bonfire"])
	Colony.damage_building(_uids["palisade"], 18)
	if not Colony.assign_job(ids[1], &"construction", _uids["bonfire"]):
		push_warning("preview: repair job (%s)" % Colony.job_block_reason(ids[1], &"construction", _uids["bonfire"]))
	if not Colony.assign_job(ids[0], &"construction", &"gym"):
		push_warning("preview: clearing job (%s)" % Colony.job_block_reason(ids[0], &"construction", &"gym"))
	Colony.assign_job(ids[2], &"cooking", _uids["kitchen"])
	Colony.clear_progress[&"gym"] = 12  # preview only: as if two evenings of work were done
	GameState.day = 14


func _building(def_id: StringName, zone_id: StringName) -> StringName:
	var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, zone_id, false)
	Colony.complete_building(uid)
	Economy.set_cap_bonus(5000)  # completing a building recomputes the warehouse bonus
	return uid


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
