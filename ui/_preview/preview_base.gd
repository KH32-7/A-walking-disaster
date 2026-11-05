extends Node3D
## D-06 preview: base HUD, build panel, residents. Fake state only (demo residents, resources).
## Keys: B build, R residents, N notification. Optional: -- --view=hud|build|residents --shot=user://x.png

var _shot := ""
var _view := "hud"
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # screens pause the tree
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
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
	_fake_state()
	UI.show_base_hud(true)
	UI.base_hud.push_note("@residents 서하은이 배고파요", &"warn")
	UI.base_hud.push_note("@build 벌목장 일손 부족 (1/2명)", &"info")
	UI.base_hud.push_note("린이 할 말이 있대요", &"info")
	if _view == "build":
		UI.open(&"build")
	elif _view == "residents":
		UI.open(&"residents")


func _fake_state() -> void:
	if Colony.population() == 0:
		for p: Dictionary in DemoProfiles.PROFILES:
			Colony.add_resident(p)
	Economy.set_cap_bonus(300)
	Economy.apply({&"wood": 128, &"stone": 64, &"scrap": 41, &"food": 22, &"parts": 9, &"cloth": 14})
	Colony.threat = 46
	GameState.day = 12


func _process(delta: float) -> void:
	_t += delta
	if _shot != "" and _t > 1.0 and _t - delta <= 1.0:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_N:
		UI.base_hud.push_note("@build 창고가 가득 찼어요", &"danger")


func _box(pos: Vector3, size: Vector3, mat: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = load("res://art/materials/%s.tres" % mat)
	add_child(mi)
