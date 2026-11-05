extends Node3D
## D-08 preview: bag + loot container, and the base armory. Fake state only.
## Optional: -- --view=bag|armory|tip --shot=user://x.png

class FakeContainer:
	extends Node
	signal opened(slot_count: int)
	signal slot_revealed(index: int, item_id: StringName, count: int)
	signal reveal_finished()
	signal session_ended()
	signal slot_taken(index: int, item_id: StringName, count: int)
	var def := {"type": 1}
	var _slots := [{"item_id": &"medicine", "count": 2, "identified": true},
		{"item_id": &"bandage", "count": 3, "identified": true}, {"item_id": &"first_aid_kit", "count": 1, "identified": true},
		{"item_id": &"herbs", "count": 2, "identified": true}, {"item_id": &"", "count": 0, "identified": false},
		{"item_id": &"", "count": 0, "identified": false}]
	var _t := 0.0

	func get_slots() -> Array:
		return _slots.duplicate(true)

	func take(i: int) -> int:
		var s: Dictionary = _slots[i]
		var n := Bag.try_add(s.item_id, s.count)
		s.count -= n
		slot_taken.emit(i, s.item_id, n)
		return n

	func cancel_open() -> void:
		pass

var _shot := ""
var _view := "bag"
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("2f6f74")
	add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 24
	add_child(cam)
	cam.position = Vector3(16, 20, 16)
	cam.look_at(Vector3.ZERO)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 0.2, 40)
	mi.mesh = bm
	mi.material_override = load("res://art/materials/toon_concrete.tres")
	add_child(mi)
	_fake()
	match _view:
		"armory":
			UI.open(&"armory")
		_:
			var c := FakeContainer.new()
			add_child(c)
			UI.open(&"bag", {"container": c})


func _fake() -> void:
	if Colony.population() == 0:
		for p: Dictionary in DemoProfiles.PROFILES:
			Colony.add_resident(p)
	Economy.set_cap_bonus(300)
	Economy.apply({&"wood": 128, &"stone": 64, &"scrap": 41, &"food": 22, &"parts": 9, &"cloth": 14, &"rare_parts": 2, &"fuel": 6})
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for pair in [[&"rifle", 2, Enums.EquipSlot.MAIN], [&"pipe_wrench", 0, Enums.EquipSlot.SUB], [&"work_helmet", 0, Enums.EquipSlot.HEAD],
			[&"hoodie", 1, Enums.EquipSlot.BODY], [&"sneakers", 0, Enums.EquipSlot.LEGS], [&"school_bag", 1, Enums.EquipSlot.BAG]]:
		var uid := Armory.create_item(pair[0], pair[1], rng)
		Armory.equip(Armory.PLAYER_ID, pair[2], uid)
	for pair in [[&"shotgun", 2], [&"flak_vest", 1], [&"machete", 0], [&"riot_helmet", 3], [&"necklace", 4], [&"smg", 1], [&"work_boots", 0]]:
		Armory.create_item(pair[0], pair[1], rng)
	Bag.resize_for_player()
	for pair in [[&"scrap", 12], [&"parts", 3], [&"ammo_rifle", 40], [&"cloth", 4], [&"food", 3], [&"paint", 2]]:
		Bag.add_resource(pair[0], pair[1])
	Bag.add_item(Armory.create_item(&"flak_vest", 1, rng))
	Bag.add_item(Armory.create_item(&"baseball_bat", 2, rng))


func _process(delta: float) -> void:
	_t += delta
	if _view == "tip" and _t > 0.5 and _t - delta <= 0.5:
		var s = UI.get_screen(&"bag")
		var e: Dictionary = {}
		for x: Dictionary in Bag.entries(Bag.AREA_BAG):
			if StringName(x.kind) == &"item":
				e = x
		if not e.is_empty():
			s._on_hover(e, Rect2(Vector2(1300, 300), Vector2(80, 80)))
	if _shot != "" and _t > 1.0 and _t - delta <= 1.0:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
