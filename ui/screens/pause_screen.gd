class_name PauseScreen
extends MenuScreen
## Pause / system menu (D-19). Owner: Lane D. Screen ids `pause` and `pause_menu` (the id A's
## core/flow_prompts.gd opens on Esc in the field and the base; both point at this scene).
## UI_RULES §9 D-19 "시스템 탭 목록": blurred backdrop, a slate list on the left (계속, 설정, 생존 일지,
## 타이틀로, 게임 종료), a cream card on the right that says what leaving does right now.
## Leaving follows contracts.md "저장": in the field, quitting writes the suspend save
## (SceneRouter.quit_to_title / SaveSystem.save_suspend) so the sortie can be continued; in the base
## the game keeps the router's autosaves only, so leaving asks first.

const SEASONS := ["봄", "여름", "가을", "겨울"]
const WEATHER := ["맑음", "비"]

var list: MenuList
var _card_box: VBoxContainer


func _init() -> void:
	title_text = "일시정지"
	subtitle_text = _where()
	footer_keys = [["Esc", "계속"], ["↑ ↓", "고르기"], ["Enter", "확인"]]
	header_resources = []


func in_field() -> bool:
	return GameState.flow_state == Enums.FlowState.FIELD


func _where() -> String:
	return "%d일차 / %s" % [GameState.day, _region() if in_field() else "기지"]


## Field region name (FieldState.region_id, read only), "필드" when unknown.
func _region() -> String:
	var reg: Variant = FieldState.get(&"region_id")
	var nm := LoadingScreen.region_name(StringName(reg)) if reg != null else ""
	return nm if nm != "" else "필드"


func _build_body(b: Control) -> void:
	var p := MenuScreen.panel("시스템", "", Vector2(560, 0))
	var pc: PanelContainer = p[0]
	var v: VBoxContainer = p[1]
	pc.position = Vector2(0, 40)
	b.add_child(pc)
	list = MenuList.new()
	v.add_child(list)
	list.add_row(&"resume", "계속하기", close, "Esc")
	list.add_row(&"settings", "설정", _open_screen.bind(&"settings"),
		"" if UI.has_screen(&"settings") else "준비 중", UI.has_screen(&"settings"))
	list.add_row(&"journal", "생존 일지", _open_screen.bind(&"journal"),
		"" if UI.has_screen(&"journal") else "준비 중", UI.has_screen(&"journal"))
	list.add_row(&"title", "중단 저장 후 타이틀로" if in_field() else "타이틀로", _to_title)
	list.add_row(&"quit", "중단 저장 후 게임 종료" if in_field() else "게임 종료", _quit)

	var card := MenuScreen.cream_card(460)
	var c: PanelContainer = card[0]
	_card_box = card[1]
	c.position = Vector2(620, 40)
	b.add_child(c)
	_fill_card()
	list.call_deferred(&"focus_first")


func _fill_card() -> void:
	MenuScreen.clear(_card_box)
	var head := MenuScreen.label("%d일차 / %s / %s" % [GameState.day, SEASONS[int(GameState.season()) % 4],
		WEATHER[clampi(int(GameState.weather), 0, WEATHER.size() - 1)]], &"LabelSection", 22)
	head.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	_card_box.add_child(head)
	for row: Array in info_rows():
		_card_box.add_child(_info_row(String(row[0]), String(row[1])))
	var foot := PanelContainer.new()
	foot.theme_type_variation = &"CardCreamFoot"
	var fl := MenuScreen.label(leave_note(), &"LabelOnCreamDim", 14)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.custom_minimum_size = Vector2(420, 0)
	foot.add_child(fl)
	_card_box.add_child(foot)


## [[label, value], ...] for the cream card. Values come from GameState / SaveSystem / Settings.
func info_rows() -> Array:
	var rows: Array = []
	rows.append(["장소", "%s: 출격 중" % _region() if in_field() else "기지"])
	var diff := String(Settings.get_value(&"difficulty"))
	rows.append(["난이도", TitleScreen.DIFFICULTY_NAMES.get(StringName(diff), diff)])
	rows.append(["저장 슬롯", "슬롯 %d" % (SaveSystem.current_slot + 1)])
	var info := SaveSystem.slot_info(SaveSystem.current_slot)
	rows.append(["마지막 자동 저장", TitleScreen.saved_text(info) if info["exists"] else "없음"])
	return rows


func leave_note() -> String:
	if in_field():
		return "지금 나가면 이 출격을 중단 저장해요. 타이틀의 이어하기로 이 자리부터 다시 할 수 있어요."
	return "기지에서는 아침, 출격 직전, 탈출 직후에 자동 저장돼요. 나가면 마지막 자동 저장 뒤의 진행은 남지 않아요."


func _info_row(k: String, val: String) -> Control:
	var h := HBoxContainer.new()
	var a := MenuScreen.label(k, &"LabelOnCreamDim", 15)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var b := MenuScreen.label(val, &"LabelOnCream", 16)
	h.add_child(b)
	return h


func _open_screen(id: StringName) -> void:
	if UI.has_screen(id):
		UI.open(id)


func _to_title() -> void:
	if in_field():
		_leave_to_title()
		return
	ConfirmDialog.ask(self, "타이틀로 나갈까요?", leave_note(), "타이틀로", _leave_to_title)


func _leave_to_title() -> void:
	UI.close(StringName(name))
	SceneRouter.quit_to_title()  # writes the suspend save in the field


func _quit() -> void:
	if in_field():
		SaveSystem.save_suspend()
		get_tree().quit()
		return
	ConfirmDialog.ask(self, "게임을 끝낼까요?", leave_note(), "게임 종료", func() -> void: get_tree().quit())
