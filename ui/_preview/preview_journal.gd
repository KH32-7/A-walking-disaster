extends Node3D
## D-16 preview: survival journal (days / people / recordings / quests), field map, notice toast.
## Fake state only: twelve days of journal lines, three quests, two recordings; for the map the
## flooded mall layout + dressing with a fake player, a companion, explored fog along the demo
## route of sortie 2, the hidden ramp revealed and fake quest marker nodes.
## Optional: -- --view=days|people|recordings|quests|map|toast --shot=user://x.png

const LAYOUT := "res://levels/field/flooded_mall/layout.tscn"
const DRESSING := "res://levels/field/flooded_mall/dressing.tscn"
const PARTY := preload("res://ui/_preview/fake_party_member.gd")
const RECORDINGS := [
	{"id": &"rec_mall_01", "speaker": "차고지 경비원", "place": "침수 상가 · 버스 차고지 경비실", "day": 6,
		"text": "물이 정문까지 올라왔다. 마지막 버스는 이미 떠났고, 나는 열쇠를 들고 여기 남았다. 누가 오면 이 테이프를 들려줘. 남쪽 하역장으로 가면 길이 있다고."},
	{"id": &"rec_mall_02", "speaker": "해솔마트 점장", "place": "침수 상가 · 하역장 사무실", "day": 11,
		"text": "트럭은 옥상 데크에서 경사로로 내려와요. 덩굴이 덮어도 길은 아직 단단할 거예요. 휠체어도 지나갈 수 있어요."},
]
## Demo route points of sortie 2 (levels/field/flooded_mall/build/flooded_mall_map.json r2a..r2c),
## in plan metres. The built layout is twice the plan size: use _w() for world positions.
const ROUTE := [Vector3(71, 0, -68), Vector3(61, 0, -55), Vector3(49, 0, -43), Vector3(35, 0, -33),
	Vector3(24, 0, -27), Vector3(24, 0, -13), Vector3(25, 0, 5), Vector3(27, 0, 17), Vector3(17, 0, 25),
	Vector3(11, 0, 37), Vector3(18, 0, 33), Vector3(27, 4.5, 26), Vector3(45, 4.5, 29), Vector3(38, 4.5, 26),
	Vector3(41, 4.5, 35), Vector3(49, 4.5, 39), Vector3(45, 0, 61), Vector3(37, 0, 65)]

var _shot := ""
var _view := "days"
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the journal pauses the tree
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
	_fake_journal()
	_fake_quests()
	if _view in ["map", "toast"]:
		_field_scene()
		_open_map.call_deferred()
	else:
		_base_scene()
		UI.open(&"journal", {"tab": StringName(_view), "recordings": RECORDINGS})


func _fake_journal() -> void:
	Journal.load_data({})
	GameState.day = 12
	var lines := [
		[1, &"quiet_day", {}],
		[2, &"rescued", {"resident_id": &"p_elder", "name": "박순자"}],
		[3, &"building_completed", {"building": "침상"}],
		[4, &"joined", {"resident_id": &"demo_carpenter", "name": "한석진"}],
		[5, &"raid_win", {}],
		[6, &"sortie_extracted", {"region": "침수 상가"}],
		[7, &"friend", {"resident_id": &"p_elder", "name": "박순자", "other_id": &"demo_carpenter", "other": "한석진"}],
		[8, &"rescued", {"resident_id": &"p_child", "name": "아마라"}],
		[9, &"night_campfire", {"resident_id": &"p_child", "name": "아마라", "other_id": &"p_elder", "other": "박순자"}],
		[10, &"rescued", {"resident_id": &"p_wheel", "name": "윤지은"}],
		[11, &"request_completed", {"resident_id": &"demo_carpenter", "name": "한석진"}],
		[11, &"sortie_extracted", {"region": "침수 상가"}],
		[12, &"lover", {"resident_id": &"p_wheel", "name": "윤지은", "other_id": &"demo_carpenter", "other": "한석진"}],
		[12, &"building_completed", {"building": "정비소"}],
	]
	for l: Array in lines:
		var ctx: Dictionary = l[2].duplicate()
		ctx["day"] = l[0]
		Journal.record(l[1], ctx)
	# Someone left behind in the field (fate: missing).
	GameState.day = 9
	Journal.record(&"joined", {"resident_id": &"p_spare", "name": "도현우", "day": 3})
	EventBus.companion_stranded.emit(&"p_spare", &"flooded_mall")
	GameState.day = 12


func _fake_quests() -> void:
	Quests.load_data({})
	GameState.day = 11
	Quests.start(&"rumor_bus_stop_supplies")
	GameState.day = 12
	Quests.start(&"main_01_left_behind")
	Quests.advance(&"main_01_left_behind", &"visit_mall", 1)
	Quests.start(&"personal_carpenter_plane", &"demo_carpenter")
	Quests.start(&"rumor_mall_crying")
	UI.subtitle.clear()
	MenuScreen.clear(UI.notice_toast)  # the "새 의뢰" toasts from starting the fake quests


# ---------------- scenes ----------------

func _base_scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("5a5248")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d8c9b0")
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
	cam.look_at(Vector3(2, 0, 0))
	# A classroom corner of the school base: floor, wall, desks, a shelf of notebooks.
	_box(Vector3(0, -0.1, 0), Vector3(30, 0.2, 30), "toon_concrete")
	_box(Vector3(-3, 2, -5), Vector3(16, 4, 0.4), "toon_concrete")
	for x in [-4.0, -1.0, 2.0]:
		_box(Vector3(x, 0.4, -1.5), Vector3(2, 0.8, 1.2), "toon_wood")
	_box(Vector3(-6, 1.2, -4.2), Vector3(2.5, 2.4, 0.8), "toon_wood")


func _field_scene() -> void:
	var layout := (load(LAYOUT) as PackedScene).instantiate()
	layout.name = "Layout"  # RegionDressing looks for a sibling named Layout
	add_child(layout)
	if ResourceLoader.exists(DRESSING):
		add_child((load(DRESSING) as PackedScene).instantiate())
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.68, 0.72)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var player := Node3D.new()
	player.name = "FakePlayer"
	player.add_to_group(&"player")
	add_child(player)
	player.position = _w(Vector3(41, 4.5, 35))
	player.rotation_degrees.y = -25  # facing the ramp (north-east)
	var cam := Camera3D.new()
	cam.fov = 60
	add_child(cam)
	cam.position = player.position + Vector3(12, 16, 12)
	cam.look_at(player.position)
	var mate := PARTY.new()
	mate.display_name = "윤지은"
	add_child(mate)
	mate.position = _w(Vector3(38, 4.5, 30))
	# Quest marker spots the layout does not have yet (asked from Lane B).
	for m: Array in [["bus_stop", Vector3(-6, 0, -44)], ["mall_2f", Vector3(45, 4.5, 29)],
			["hardware_store", Vector3(27, 0, 40)]]:
		var node := Marker3D.new()
		node.name = m[0]
		add_child(node)
		node.position = _w(m[1])
	FieldState.region_id = &"flooded_mall"
	FieldState.lost_gear = [{"item_uid": &"preview_lost", "region_id": &"flooded_mall",
		"position": _w(Vector3(-24, 0, -48)), "offered": true}]
	var em := ExtractionManager.new()
	em.auto_activate = false
	em.region_id = &"flooded_mall"
	add_child(em)


func _open_map() -> void:
	var em := get_tree().get_first_node_in_group(ExtractionManager.GROUP) as ExtractionManager
	for seed_value in 64:
		em.activate(seed_value)
		var ids := em.active_point_ids()
		if &"mall_dock" in ids and &"mall_gas_station" in ids:
			break
	var explore := FieldExplore.new()
	add_child(explore)
	for i in ROUTE.size() - 1:
		var a: Vector3 = ROUTE[i]
		var b: Vector3 = ROUTE[i + 1]
		var steps := maxi(1, ceili(a.distance_to(b) / 3.0))
		for s in steps + 1:
			explore.reveal(_w(a.lerp(b, float(s) / steps)), 24.0)
	explore.reveal(_w(Vector3(-15, 0, -62)), 40.0)  # sortie 1 around the north gate
	UI.open(&"map", {"region_id": &"flooded_mall", "revealed_routes": [&"mall_loading_ramp"], "explore": explore})
	if _view == "toast":
		EventBus.notification_posted.emit("가방이 거의 찼어요 (27/30칸)", &"warn")
		EventBus.notification_posted.emit("윤지은의 체력이 낮아요", &"danger")
		EventBus.notification_posted.emit("녹음기를 찾았어요: 차고지 경비원", &"info")


## Plan metres (map json) -> world metres of the built layout.
static func _w(plan: Vector3) -> Vector3:
	return Vector3(plan.x * 2.0, plan.y, plan.z * 2.0)


func _process(delta: float) -> void:
	_t += delta
	if _shot != "" and _t > 1.5 and _t - delta <= 1.5:
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
