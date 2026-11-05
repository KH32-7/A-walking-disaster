extends Node3D
## D-14 preview: raid warning · result · emergency return · direct defense HUD on a fake base.
## Fake state only: 3 guards on a guard post, palisades, spike traps, a warning bell, 2 civilians.
## The warning's expected outcome is the real Colony.predict_raid() over that fake base.
## Results and the defense HUD state are hand-written examples (C-17 is not merged).
## Optional: -- --view=warning|warning_day|result_win|result_loss|result_flawless|emergency|defense_prep|defense_fight
##           --shot=user://x.png

const Fake := preload("res://ui/_preview/fake_field_state.gd")

var _shot := ""
var _view := "warning"
var _t := 0.0
var _b := {}
var _guards: Array[StringName] = []
var _civ: Array[StringName] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # screens pause the tree
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
	_fake_state()
	_scene(_view == "emergency")
	match _view:
		"warning":
			UI.open(&"raid_warning", {"raid": night_raid()})
		"warning_day":
			UI.open(&"raid_warning", {"raid": day_raid()})
		"result_win":
			UI.open(&"raid_result", {"result": result_win()})
		"result_loss":
			Colony.threat = RaidRules.THREAT_AFTER_LOSS
			UI.open(&"raid_result", {"result": result_loss()})
		"result_flawless":
			UI.open(&"raid_result", {"result": result_flawless()})
		"emergency":
			UI.show_field_hud(true)
			UI.field_hud.auto_bind = false
			UI.field_hud.set_state(Fake.make(6.5))
			UI.open(&"emergency_return", {"raid": day_raid()})
		"defense_prep", "defense_fight":
			UI.show_raid_hud(true)
			UI.raid_hud.auto_bind = false
			UI.raid_hud.set_state(defense_state(_view == "defense_fight"))


func night_raid() -> Dictionary:
	return {"occurs": true, "raid_id": &"raid_d12_night", "time": Enums.RaidTime.NIGHT, "type": &"wave",
		"directions": [&"north", &"east"], "strength": 42.0, "target": &"base", "warning_sec": 0.0,
		"family": Enums.Element.NONE, "notice": &"morning", "small": false}


func day_raid() -> Dictionary:
	return {"occurs": true, "raid_id": &"raid_d12_day", "time": Enums.RaidTime.DAY, "type": &"vine",
		"directions": [&"west"], "strength": 31.0, "target": &"base", "warning_sec": 60.0,
		"family": Enums.Element.GREEN, "notice": &"none", "small": false}


func result_win() -> Dictionary:
	return {"raid_id": &"raid_d12_night", "day": 12, "time": Enums.RaidTime.NIGHT, "mode": Enums.RaidMode.AUTO,
		"ratio": 1.18, "outcome": Enums.RaidOutcome.WIN,
		"damage": {"damaged": [], "durability_loss": {_b.palisade_n: 14, _b.palisade_e: 19, _b.post: 31}, "resources_lost": {}},
		"used": {"decoys": 0, "traps": 2, "essence": {}},
		"casualties": [{"resident_id": _guards[1], "kind": &"injured"}], "loot": {},
		"summary": ["북쪽·동쪽에서 마물이 몰려왔다 (강도 42, 방어 49.6).",
			"동쪽 목책이 흔들렸지만 강도윤이 초소에서 버텼다.",
			"가시 함정 두 개가 첫 무리를 묶어 두었다.",
			"벽과 시설이 조금 상했지만 막아냈다.", "문소라 다침."]}


func result_loss() -> Dictionary:
	return {"raid_id": &"raid_d12_night", "day": 12, "time": Enums.RaidTime.NIGHT, "mode": Enums.RaidMode.AUTO,
		"ratio": 0.58, "outcome": Enums.RaidOutcome.LOSS,
		"damage": {"damaged": [_b.palisade_e, _b.trap_a], "durability_loss": {},
			"resources_lost": {&"wood": 24, &"scrap": 9, &"food": 6}},
		"used": {"decoys": 1, "traps": 2, "essence": {}},
		"casualties": [{"resident_id": _guards[0], "kind": &"serious"}, {"resident_id": _civ[0], "kind": &"dead"}],
		"loot": {},
		"summary": ["북쪽·동쪽에서 마물이 몰려왔다 (강도 64, 방어 37.1).",
			"동쪽 목책이 무너지고 마물이 마당까지 들어왔다.",
			"막지 못했다. 시설 2곳이 부서지고 창고가 털렸다.", "강도윤 크게 다침.", "윤하늘 목숨을 잃음."]}


func result_flawless() -> Dictionary:
	return {"raid_id": &"raid_d12_day", "day": 12, "time": Enums.RaidTime.DAY, "mode": Enums.RaidMode.PLAYED,
		"ratio": 1.74, "outcome": Enums.RaidOutcome.FLAWLESS,
		"damage": {"damaged": [], "durability_loss": {}, "resources_lost": {}},
		"used": {"decoys": 0, "traps": 1, "essence": {}},
		"casualties": [], "loot": {&"vine_fiber": 9},
		"summary": ["서쪽에서 마물이 몰려왔다 (강도 31, 방어 45.2).", "덩굴 마물이 목책 앞에서 멈췄다.", "피해 없이 막아냈다."]}


func defense_state(fight: bool) -> Dictionary:
	var names := {}
	for id in _guards:
		names[id] = RaidFlow.resident_name(id)
	return {"wave": 2, "waves": 3, "phase": &"fight" if fight else &"prep", "time_left": 14.0, "prep_sec": 20.0,
		"hold_left": 212.0, "monsters_left": 9,
		"shelter_door": {"hp": 520 if fight else 640, "max": 800}, "traps": {"ready": 1 if fight else 2, "total": 3},
		"guards": [
			{"id": _guards[0], "name": names[_guards[0]], "power": 6.4, "spot": &"post_north"},
			{"id": _guards[1], "name": names[_guards[1]], "power": 4.1, "spot": &"gate_east"},
			{"id": _guards[2], "name": names[_guards[2]], "power": 3.2, "spot": &"", "down": fight},
			{"id": &"preview_player_ally", "name": "한만석", "power": 2.7, "spot": &""}],
		"spots": [{"id": &"post_north", "name": "북쪽 경비 초소", "kind": &"post", "cap": 2},
			{"id": &"gate_east", "name": "동쪽 나무 문", "kind": &"gate", "cap": 2},
			{"id": &"shelter_front", "name": "대피소 앞", "kind": &"shelter", "cap": 3}]}


func _fake_state() -> void:
	GameState.day = 12
	Colony.threat = RaidRules.THREAT_AFTER_WIN
	Economy.set_cap_bonus(5000)
	Economy.apply({&"wood": 86, &"stone": 40, &"scrap": 33, &"food": 21, &"parts": 4})
	var people := [["preview_guard_a", "강도윤", 8], ["preview_guard_b", "문소라", 6], ["preview_guard_c", "한지호", 5]]
	for p: Array in people:
		_guards.append(Colony.add_resident({"id": StringName(p[0]), "name": p[1], "age_stage": Enums.AgeStage.ADULT,
			"stats": {&"str": 6, &"dex": 5, &"sense": p[2], &"heart": 4}, "access_needs": []}))
	for p: Array in [["preview_civ_a", "윤하늘"], ["preview_civ_b", "박서진"]]:
		_civ.append(Colony.add_resident({"id": StringName(p[0]), "name": p[1], "age_stage": Enums.AgeStage.ADULT,
			"stats": {}, "access_needs": []}))
	_b.post = _building(&"guard_post", Vector2i(2, 2))
	_b.post_b = _building(&"guard_post", Vector2i(10, 2))
	_b.palisade_n = _building(&"palisade", Vector2i(4, 0))
	_b.palisade_e = _building(&"palisade", Vector2i(12, 4))
	_b.trap_a = _building(&"spike_trap", Vector2i(6, 6))
	_b.trap_b = _building(&"spike_trap", Vector2i(8, 6))
	_b.bell = _building(&"warning_bell", Vector2i(0, 8))
	Colony.assign_job(_guards[0], &"guard", _b.post)
	Colony.assign_job(_guards[1], &"guard", _b.post)
	Colony.assign_job(_guards[2], &"guard", _b.post_b)
	var machete := Armory.create_item(&"machete", Enums.Rarity.UNCOMMON)
	Armory.equip(_guards[0], Enums.EquipSlot.MAIN, machete)


func _building(def_id: StringName, cell: Vector2i) -> StringName:
	var uid := Colony.place_building(def_id, cell, 0, &"", false)
	Colony.complete_building(uid)
	Economy.set_cap_bonus(5000)
	return uid


## A base yard at night (or the flooded field for the emergency view).
func _scene(field: bool) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("2f4a4c") if field else Color("1b2233")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b8c9c0") if field else Color("6f7fa8")
	env.environment.ambient_light_energy = 0.7 if field else 0.45
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.9 if field else 0.35
	sun.light_color = Color("fff2dc") if field else Color("9fb4ff")
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 22
	add_child(cam)
	cam.position = Vector3(12, 14, 16)
	cam.look_at(Vector3(2, 0, 0))
	if field:
		_box(Vector3(0, -0.1, 0), Vector3(40, 0.2, 40), "toon_concrete")
		_box(Vector3(-6, 3, -8), Vector3(10, 6, 4), "toon_concrete")
		_box(Vector3(7, 2, -7), Vector3(6, 4, 5), "toon_concrete")
		_box(Vector3(2, 0.4, 2), Vector3(1.4, 0.8, 1), "toon_wood")
		return
	_box(Vector3(0, -0.1, 0), Vector3(40, 0.2, 40), "toon_concrete")
	_box(Vector3(-4, 3, -9), Vector3(18, 6, 4), "toon_concrete")  # school wall
	for i in 9:  # palisade
		_box(Vector3(-10 + i * 2.2, 0.9, -3), Vector3(0.35, 1.8, 2.0), "toon_wood")
	_box(Vector3(9, 1.6, 2), Vector3(2.4, 3.2, 2.4), "toon_wood")  # guard post
	_box(Vector3(-2, 0.15, 4), Vector3(1.2, 0.3, 1.2), "toon_wood")  # traps
	_box(Vector3(1, 0.15, 5), Vector3(1.2, 0.3, 1.2), "toon_wood")


func _process(delta: float) -> void:
	_t += delta
	if _view == "emergency" and UI.field_hud != null:
		UI.field_hud.set_state(Fake.make(6.5))
	var wait := 2.2 if _view.begins_with("result") else 1.0  # let the count-up finish
	if _shot != "" and _t > wait and _t - delta <= wait:
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
