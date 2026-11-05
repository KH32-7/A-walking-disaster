extends Control
## UI pass preview (2026-11-06): every UI changed in the loot and UI pass, one step at a time.
## Run this scene (F6). Keys: N or ] next, P or [ back, R replay this step. Or use the buttons on top.
## Fake data only: nothing is saved. Steps:
##   1 field HUD: bigger minimap, region card top centre, feed under the minimap, ∞ ammo,
##     skill names under Q / E, empty quick slots hidden, extract bar above the quick slots
##   2 bag: bigger cells, a container with rare gear and a blueprint (flash and chime on reveal)
##   3 sortie result: the "건진 것" cards come up one by one
##   4 new resident: the one-line greeting that replaced the 입주 의식 steps
##   5 a menu with a radio line: the subtitle sits right of the key footer

const Fake := preload("res://ui/_preview/fake_field_state.gd")
const CONTAINER_SCENE := preload("res://field/loot/loot_container.tscn")
const STEPS := ["필드 HUD", "가방과 상자 확인 연출", "출격 결과 보상 카드", "새 식구 인사", "메뉴 위 자막 위치"]

var _step := 0
var _t := 0.0
var _spawned: Array[Node] = []
var _bar_label: Label
var _resident := &""


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("4f5f52")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_bar()
	_show.call_deferred(0)


func _build_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.position.y = 6
	layer.add_child(row)
	var prev := Button.new()
	prev.text = "이전 (P)"
	prev.focus_mode = Control.FOCUS_NONE
	prev.pressed.connect(func() -> void: _show(_step - 1))
	row.add_child(prev)
	_bar_label = Label.new()
	_bar_label.add_theme_font_size_override(&"font_size", 18)
	_bar_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_bar_label.add_theme_constant_override(&"outline_size", 6)
	row.add_child(_bar_label)
	var again := Button.new()
	again.text = "다시 (R)"
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(func() -> void: _show(_step))
	row.add_child(again)
	var next := Button.new()
	next.text = "다음 (N)"
	next.focus_mode = Control.FOCUS_NONE
	next.pressed.connect(func() -> void: _show(_step + 1))
	row.add_child(next)


func _show(i: int) -> void:
	_clear()
	_step = wrapi(i, 0, STEPS.size())
	_t = 0.0
	_bar_label.text = "%d / %d  %s" % [_step + 1, STEPS.size(), STEPS[_step]]
	match _step:
		0:
			_field_hud()
		1:
			_bag()
		2:
			_result()
		3:
			_welcome()
		4:
			_menu_subtitle()


func _clear() -> void:
	UI.close_all()
	UI.show_field_hud(false)
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	if _resident != &"" and not Colony.get_resident(_resident).is_empty() \
			and Colony.get_resident(_resident).get("arrival_pending", false):
		Colony.complete_arrival(_resident)
	_resident = &""
	MenuScreen.clear(UI.notice_toast)


# ---------------- steps ----------------

func _field_hud() -> void:
	UI.show_field_hud(true)
	UI.field_hud.auto_bind = false
	EventBus.sortie_started.emit({"region_id": &"flooded_mall", "region_name": "침수 상가"})
	UI.field_hud.push_reward("새 의뢰: 상가 2층의 울음소리", 0)
	UI.field_hud.push_reward("숨은 길이 지도에 표시됐다", 0)
	UI.field_hud.push_reward("약품장 뒤짐", 25)
	EventBus.radio_message.emit(&"broadcaster", "아침 먹고 나가세요. 빈속으로 뛰면 금방 지칩니다.", 1)


func _field_state() -> Dictionary:
	var st: Dictionary = Fake.make(_t + 6.5)
	st["weapons"] = [{"name": "권총", "ammo": 12, "reserve": -1, "rarity": 0}]  # -1 = infinite: ≡ ∞
	st["weapon_index"] = 0
	st["reloading"] = false
	st["skills"] = [{"key": "Q", "name": "정조준", "left": maxf(0.0, 4.0 - fmod(_t, 10.0)), "max": 10.0},
		{"key": "E", "name": "제압 사격", "left": 0.0, "max": 15.0}]
	st["consumables"] = [{"name": "구급상자", "count": 2}, null, null, null]  # empty slots are not drawn
	st["prompt"] = {}
	st["hold"] = {"label": "탈출 대기 중", "progress": fmod(_t, 5.0) / 5.0}
	return st


func _bag() -> void:
	var table := LootTable.new()
	table.roll_min = 2
	table.roll_max = 2
	var e := LootEntry.new()
	e.item_id = &"scrap"
	e.min_count = 3
	e.max_count = 3
	table.entries = [e]
	table.gear_chance = 1.0
	table.gear_rarity_weights = [0.0, 0.0, 1.0]
	table.gear_pool = [&"rifle"]
	table.blueprint_chance = 1.0
	var c: LootContainer = CONTAINER_SCENE.instantiate()
	var def := LootData.container_def(LootSpot.ContainerType.SUPPLY_CRATE).duplicate() as LootContainerDef
	def.open_sec = 1.0  # quick open in the preview; no lock to pick
	def.locked = false
	c.def = def
	c.loot_table = table
	add_child(c)
	_spawned.append(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	c.roll_contents(rng)
	var looter := Node3D.new()
	add_child(looter)
	_spawned.append(looter)
	Bag.load_data({})
	c.begin_open(looter)
	UI.open(&"bag", {"container": c})


func _result() -> void:
	var items: Array = []
	for pair in [[&"club", 0], [&"pistol", 1], [&"rifle", 2], [&"riot_helmet", 2]]:
		items.append(Armory.create_item(pair[0], pair[1]))
	var unknown := LootTable.unknown_blueprints()
	var bps: Array = unknown.slice(0, 2).map(func(b: Dictionary) -> StringName: return b.output_id)
	UI.open(&"result", {"result": {"extracted": true, "region_id": &"flooded_mall", "duration_sec": 512.0,
		"xp": 120, "kills": 7, "rescued": [], "stranded": [], "blueprints": bps,
		"loot": {"resources": {&"scrap": 12, &"cloth": 3, &"parts": 2}, "items": items, "discarded": {}}}})


func _welcome() -> void:
	_resident = Colony.add_resident({"id": &"preview_newcomer", "name": "윤기철", "likes": [&"tea"],
		"arrival_pending": true, "story": {"background": "다리를 다친 60대 전직 목수. 대피 버스를 기다리다 혼자 남았다.",
		"first_line": "여기 사람 있어요?"}})
	UI.open(&"welcome", {"resident_id": _resident})


func _menu_subtitle() -> void:
	UI.open(&"sortie_prep")
	EventBus.radio_message.emit(&"broadcaster", "아침 먹고 나가세요. 빈속으로 뛰면 금방 지칩니다.", 1)


# ---------------- loop and keys ----------------

func _process(delta: float) -> void:
	_t += delta
	if _step == 0 and UI.field_hud != null and UI.field_hud.visible:
		UI.field_hud.set_state(_field_state())


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_N, KEY_BRACKETRIGHT:
			_show(_step + 1)
		KEY_P, KEY_BRACKETLEFT:
			_show(_step - 1)
		KEY_R:
			_show(_step)
		_:
			return
	get_viewport().set_input_as_handled()
