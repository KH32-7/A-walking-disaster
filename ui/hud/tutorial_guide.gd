class_name TutorialGuide
extends Control
## First-day guide (QA 플레이 준비): the 방송실 지기 walks a new player through one whole day by doing it —
## open 건설, pick and place a 모닥불, see the site card, sortie to the park, walk / loot / bag / map,
## extract, evening, sleep. Owner: Lane D. UI_RULES §5 "안내 카드": yellow band + cream body + key chips.
##
## Each step has a check run every frame; when it holds the next step shows. Steps never block input
## and never pause. F1 hides the guide for this game (GameState flag). On day 1 the first site is
## finished by the 방송실 지기 ("오늘은 제가 같이 지을게요"), since there is no resident yet.

const FLAG_DONE := &"tutorial_done"
const FLAG_STEP := &"tutorial_step"
const SPEAKER := "방송실 지기"
const CARD_W := 430.0

## [id, text, [[key, label], ...]]
const STEPS := [
	[&"hello", "어서 와요. 여기가 우리 공터예요. 밤에 둘러앉을 모닥불부터 같이 지어 볼까요? 아래 '건설'을 눌러요.",
		[["B", "건설 열기"]]],
	[&"pick", "'추천' 탭에서 모닥불을 고르고 '놓을 곳 고르기'를 눌러요. 카드마다 필요한 재료가 보여요.",
		[["← →", "고르기"], ["Enter", "놓을 곳 고르기"]]],
	[&"place", "초록 칸이 놓을 수 있는 자리예요. 빨강이면 왜 안 되는지 옆에 떠요.",
		[["클릭", "놓기"], ["R", "돌리기"], ["Esc", "다시 고르기"]]],
	[&"site", "건설 현장이 생겼어요. 보통은 주민을 보내야 지어지는데, 오늘은 사람이 없으니 제가 같이 지을게요.",
		[["Enter", "이대로 짓기"]]],
	[&"sortie", "이제 숲이 된 공원으로 나가 봐요. 나무랑 쓸 만한 걸 모으고, 남겨진 사람이 있으면 데려와요.",
		[["Enter", "출격 준비"]]],
	[&"sortie_go", "갈 곳을 고르고 '출격'을 눌러요. 해가 지기 전에는 돌아와야 해요.",
		[["클릭", "지역 고르기"], ["Enter", "출격"]]],
	[&"move", "걸어서 둘러봐요. 마물은 소리에 끌리니까 뛰면 조심해요.",
		[["WASD", "이동"], ["마우스", "조준"], ["클릭", "사격"], ["Shift", "달리기"], ["Space", "구르기"]]],
	[&"loot", "상자나 쓰레기 더미 앞에서 뒤져 봐요. 챙긴 건 가방에서 볼 수 있어요.",
		[["F", "뒤지기"], ["Tab", "가방"], ["M", "지도"]]],
	[&"extract", "지도의 초록 마름모가 탈출 지점이에요. 그 안에 잠깐 서 있으면 기지로 돌아와요.",
		[["M", "지도에서 찾기"]]],
	[&"evening", "돌아왔네요. 저녁엔 오늘 모아 온 것과 쓴 것을 정산해요.",
		[["Enter", "밤으로"]]],
	[&"night", "하루가 끝났어요. 밤엔 주민들 사이에 이야기가 생기기도 해요. 푹 자고, 내일 또 방송할게요.",
		[["잠자기", "다음 날"]]],
]

var _step := -1
var _card: PanelContainer
var _band_label: Label
var _body: Label
var _keys: HFlowContainer
var _site_uid: StringName = &""
var _walk_from := Vector3.INF
var _walk_t := 0.0
var _loot_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	EventBus.flow_state_changed.connect(func(_s: Enums.FlowState) -> void: _sync())
	EventBus.game_loaded.connect(func(_slot: int) -> void: _sync())


func active() -> bool:
	return GameState.flow_state != Enums.FlowState.TITLE and not GameState.has_flag(FLAG_DONE) and GameState.day <= 1


func current_step() -> StringName:
	return STEPS[_step][0] if _step >= 0 and _step < STEPS.size() else &""


func skip() -> void:
	GameState.set_flag(FLAG_DONE)
	_show(-1)


func _sync() -> void:
	if not active():
		_show(-1)
		return
	var saved := int(GameState.flags.get(FLAG_STEP, 0))
	if _step < 0:
		_show(clampi(saved, 0, STEPS.size() - 1))


func _process(delta: float) -> void:
	if not active():
		if _step >= 0:
			_show(-1)
		if GameState.flow_state == Enums.FlowState.BASE_MORNING and GameState.day >= 2 and GameState.flags.has(FLAG_STEP) \
				and not GameState.has_flag(FLAG_DONE):
			GameState.set_flag(FLAG_DONE)  # slept through the first night
		return
	if _step < 0:
		_sync()
		return
	_card.visible = not _off_topic()
	_place_card()
	if _done(current_step(), delta):
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if _step >= 0 and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F1:
		skip()
		get_viewport().set_input_as_handled()


func _advance() -> void:
	_show(_step + 1 if _step + 1 < STEPS.size() else -1)
	if _step < 0:
		GameState.set_flag(FLAG_DONE)


## Whether `id` is done. Checks read UI / flow / Colony state only; the one rule-side act is the
## day-1 site the 방송실 지기 finishes.
func _done(id: StringName, delta: float) -> bool:
	var s := GameState.flow_state
	match id:
		&"hello":
			return UI.is_open(&"build")
		&"pick":
			return is_instance_valid(UI.build_place_hud) or _site_open()
		&"place":
			if _site_open():
				_site_uid = UI.get_screen(&"build").get(&"_sel_uid")
				return true
			return false
		&"site":
			if _site_open():
				_site_uid = UI.get_screen(&"build").get(&"_sel_uid")
				return false
			if _site_uid != &"" and not UI.is_open(&"build") and not is_instance_valid(UI.build_place_hud):
				_finish_tutorial_site()
				return true
			return false
		&"sortie":
			return UI.is_open(&"sortie_prep") or s == Enums.FlowState.FIELD
		&"sortie_go":
			return s == Enums.FlowState.FIELD
		&"move":
			if s != Enums.FlowState.FIELD:
				return s == Enums.FlowState.RESULT
			var p := get_tree().get_first_node_in_group(&"player") as Node3D
			if p == null:
				return false
			if _walk_from == Vector3.INF:
				_walk_from = p.global_position
			_walk_t += delta
			return p.global_position.distance_to(_walk_from) > 6.0 or _walk_t > 12.0
		&"loot":
			if s != Enums.FlowState.FIELD:
				return s == Enums.FlowState.RESULT
			_loot_t += delta
			return UI.is_open(&"bag") or UI.is_open(&"map") or _loot_t > 20.0
		&"extract":
			return s == Enums.FlowState.RESULT or s == Enums.FlowState.EVENING
		&"evening":
			return s == Enums.FlowState.NIGHT or s == Enums.FlowState.NIGHT_EVENT
		&"night":
			return s == Enums.FlowState.BASE_MORNING and GameState.day >= 2
	return false


## A menu the current step is not about (제작, 무기고, 일지 ...) is open: get out of its way.
func _off_topic() -> bool:
	var ok_screens: Array[StringName] = [&"build", &"sortie_prep", &"bag", &"map", &"result", &"evening", &"loading"]
	for id: StringName in UI.stack_ids():
		if not id in ok_screens:
			return true
	return false


func _site_open() -> bool:
	return UI.is_open(&"build") and UI.get_screen(&"build").get(&"_mode") == &"site"


## Day 1 has nobody to build: the 방송실 지기 helps finish the first site.
func _finish_tutorial_site() -> void:
	var b := Colony.get_building(_site_uid)
	if b.is_empty() or b["completed"]:
		return
	Colony.complete_building(_site_uid)
	var def := BaseDB.get_building(b["def_id"])
	EventBus.notification_posted.emit("%s이(가) 같이 지어 줬어요 · %s 완성" % [SPEAKER, def.display_name if def else ""], &"info")


# ---------------- card ----------------

func _show(i: int) -> void:
	_step = i
	_walk_from = Vector3.INF
	_walk_t = 0.0
	_loot_t = 0.0
	_card.visible = i >= 0
	if i < 0:
		return
	GameState.set_flag(FLAG_STEP, i)
	var st: Array = STEPS[i]
	_band_label.text = "%s · 첫날 안내 %d/%d" % [SPEAKER, i + 1, STEPS.size()]
	_body.text = String(st[1])
	for c in _keys.get_children():
		_keys.remove_child(c)
		c.queue_free()
	for pair: Array in st[2]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 5)
		h.add_child(KeyChip.new(String(pair[0]), KeyChip.Style.DARK))
		if String(pair[1]) != "":
			h.add_child(MenuScreen.label(String(pair[1]), &"LabelOnCream", 14))
		_keys.add_child(h)
	_card.reset_size()


func _build() -> void:
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTokens.CREAM
	sb.set_corner_radius_all(UiTokens.BAND_RADIUS)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	_card.add_theme_stylebox_override(&"panel", sb)
	add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	_card.add_child(v)
	var band := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = UiTokens.ACCENT
	bsb.corner_radius_top_left = UiTokens.BAND_RADIUS
	bsb.corner_radius_top_right = UiTokens.BAND_RADIUS
	bsb.content_margin_left = 16
	bsb.content_margin_right = 16
	bsb.content_margin_top = 7
	bsb.content_margin_bottom = 7
	band.add_theme_stylebox_override(&"panel", bsb)
	v.add_child(band)
	_band_label = MenuScreen.label("", &"LabelOnCream", 14)
	_band_label.add_theme_color_override(&"font_color", UiTokens.ACCENT_TEXT)
	band.add_child(_band_label)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16 if side != "top" else 12)
	v.add_child(m)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override(&"separation", 10)
	m.add_child(inner)
	_body = MenuScreen.label("", &"LabelOnCream", 16)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(CARD_W - 32, 0)
	inner.add_child(_body)
	_keys = HFlowContainer.new()
	_keys.add_theme_constant_override(&"h_separation", 14)
	_keys.add_theme_constant_override(&"v_separation", 6)
	inner.add_child(_keys)
	var skip_row := HBoxContainer.new()
	skip_row.alignment = BoxContainer.ALIGNMENT_END
	skip_row.add_theme_constant_override(&"separation", 6)
	skip_row.add_child(KeyChip.new("F1", KeyChip.Style.DARK))
	skip_row.add_child(MenuScreen.label("안내 끄기", &"LabelOnCreamDim", 13))
	inner.add_child(skip_row)
	_card.visible = false


## Right middle in the field, on the base map and while placing (UI_RULES §4); bottom right, above
## the key footer, when a menu screen is open.
func _place_card() -> void:
	var vp := get_viewport_rect().size
	var sz := _card.get_combined_minimum_size()
	# Menus keep their cream card at the top right: sit in the bottom right corner under it.
	if not UI.stack_ids().is_empty() and not is_instance_valid(UI.build_place_hud):
		_card.position = Vector2(vp.x - sz.x - 52.0, vp.y - sz.y - 96.0)
	else:
		_card.position = Vector2(vp.x - sz.x - UiTokens.HUD_MARGIN, (vp.y - sz.y) * 0.42)
