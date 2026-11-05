extends Node3D
## D-12 preview: crafting · upgrade · repair · engraving screen on a fake base.
## Fake state only: a workshop Lv2 with a dexterous worker, a sewing room with nobody assigned,
## an essence workshop Lv2, a few items (engraved, damaged, upgraded) and essences.
## Optional: -- --view=craft|upgrade|transfer|repair|engrave|refine|disassemble --shot=user://x.png

const VIEWS := {
	"craft": {"facility": &"workshop", "mode": &"craft"},
	"upgrade": {"facility": &"workshop", "mode": &"upgrade"},
	"transfer": {"facility": &"workshop", "mode": &"transfer"},
	"repair": {"facility": &"workshop", "mode": &"repair"},
	"sewing": {"facility": &"sewing_room", "mode": &"upgrade"},
	"engrave": {"facility": &"essence_workshop", "mode": &"engrave"},
	"refine": {"facility": &"essence_workshop", "mode": &"refine"},
	"disassemble": {"facility": &"essence_workshop", "mode": &"disassemble"},
}

var _shot := ""
var _view := "upgrade"
var _t := 0.0
var _uids := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # screens pause the tree
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
	_scene()
	_fake_state()
	var args: Dictionary = VIEWS.get(_view, VIEWS["upgrade"]).duplicate()
	match _view:
		"upgrade":
			args["uid"] = _uids.get("machete", &"")
		"repair":
			args["uid"] = _uids.get("pistol", &"")
		"engrave":
			args["uid"] = _uids.get("spear", &"")
	UI.open(&"craft", args)
	if _view == "engrave":
		var s := UI.get_screen(&"craft")
		s.set(&"_slot", 1)
		s.set(&"_essence", &"essence_water_mid")
		s.call(&"_refresh")


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
	# A workshop corner: floor, back wall, workbench, shelves, crates.
	_box(Vector3(0, -0.1, 0), Vector3(30, 0.2, 30), "toon_concrete")
	_box(Vector3(-3, 2, -5), Vector3(16, 4, 0.4), "toon_concrete")
	_box(Vector3(-1, 0.5, -2.5), Vector3(4, 1, 1.6), "toon_wood")
	_box(Vector3(-6, 1.2, -4.2), Vector3(2.5, 2.4, 0.8), "toon_wood")
	_box(Vector3(2.5, 0.4, -1), Vector3(1, 0.8, 1), "toon_wood")
	_box(Vector3(3.2, 0.35, 0.4), Vector3(0.8, 0.7, 0.8), "toon_wood")


func _fake_state() -> void:
	Economy.set_cap_bonus(5000)
	Economy.apply({&"scrap": 74, &"parts": 6, &"rare_parts": 1, &"wood": 40, &"cloth": 12, &"vine_fiber": 3,
		&"stone_shard": 5, &"water_moss": 8, &"neon_dust": 2,
		&"essence_green_low": 4, &"essence_stone_low": 7, &"essence_water_mid": 2, &"essence_light_low": 1})
	for flag in [&"blueprint_essence_workshop", &"blueprint_machete", &"blueprint_pistol", &"blueprint_spear"]:
		GameState.set_flag(flag)
	var smith := Colony.add_resident({"id": &"preview_smith", "name": "강도윤", "age_stage": Enums.AgeStage.ADULT,
		"stats": {&"str": 5, &"dex": 8, &"sense": 4, &"heart": 4}, "access_needs": []})
	var keeper := Colony.add_resident({"id": &"preview_keeper", "name": "문소라", "age_stage": Enums.AgeStage.ADULT,
		"stats": {&"dex": 5}, "access_needs": []})
	Colony.tier = Enums.BaseTier.SETTLEMENT  # allows Lv2 facilities
	var ws := _building(&"workshop", Vector2i(2, 2), 2)
	_building(&"sewing_room", Vector2i(8, 2), 1)
	var ew := _building(&"essence_workshop", Vector2i(2, 8), 2)
	if not Colony.assign_job(smith, &"maintenance", ws):
		push_warning("preview: maintenance job not assigned (%s)" % Colony.job_block_reason(smith, &"maintenance", ws))
	if not Colony.assign_job(keeper, &"essence_research", ew):
		push_warning("preview: essence job not assigned (%s)" % Colony.job_block_reason(keeper, &"essence_research", ew))
	var free := {"facility_level": 3, "worker": true, "dex": 10}
	var machete := Armory.create_item(&"machete", Enums.Rarity.RARE)
	Armory.get_item(machete).upgrade_level = 2
	Armory.engrave(machete, &"essence_green_low", 0, free)
	Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, machete)
	var pistol := Armory.create_item(&"pistol", Enums.Rarity.COMMON)
	Armory.wear(pistol, 64.0)
	Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.SUB, pistol)
	var rifle := Armory.create_item(&"rifle", Enums.Rarity.UNCOMMON)
	Armory.get_item(rifle).upgrade_level = 5
	var spear := Armory.create_item(&"spear", Enums.Rarity.EPIC)
	Armory.engrave(spear, &"essence_stone_low", 0, free)
	var club := Armory.create_item(&"club", Enums.Rarity.RARE)
	Armory.engrave(club, &"essence_light_low", 0, free)
	Armory.wear(Armory.create_item(&"hoodie", Enums.Rarity.UNCOMMON), 20.0)
	Armory.create_item(&"ring", Enums.Rarity.UNCOMMON)
	_uids = {"machete": machete, "pistol": pistol, "rifle": rifle, "spear": spear}
	GameState.day = 12


func _building(def_id: StringName, cell: Vector2i, level: int) -> StringName:
	var uid := Colony.place_building(def_id, cell, 0, &"", false)
	Colony.complete_building(uid)
	Economy.set_cap_bonus(5000)  # completing a building recomputes the warehouse bonus
	for i in level - 1:
		var check: Dictionary = Colony.can_upgrade(uid)
		Economy.apply(check.get("cost", {}))  # pay for it with fake resources
		if not Colony.upgrade_building(uid):
			push_warning("preview: %s not upgraded (%s)" % [def_id, Colony.can_upgrade(uid)])
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
