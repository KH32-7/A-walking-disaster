extends CanvasLayer
## Attached to main.tscn (child `FlowPrompts`). Owner: Lane A (A-05 integration).
## Stand-in prompts for the flow steps that no lane has a screen for yet, so the whole day can be
## played from main.tscn:
##   TITLE      new game / continue (slot) / resume suspended sortie / quit
##   BASE_STAY  "하루 마치기"  -> SceneRouter.end_stay()
##   NIGHT      "잠자기"       -> SceneRouter.finish_night()
##   Esc menu   (field and base, when no UI screen is open) resume / quit to title / quit game
## Every prompt hides itself as soon as a lane registers a real screen for that step
## (UI.has_screen(&"title") / &"stay" / &"night" / &"pause_menu"), so Lane D can replace these
## one at a time without touching this file.

const SCREEN_FOR_STATE := {
	Enums.FlowState.TITLE: &"title",
	Enums.FlowState.BASE_STAY: &"stay",
	Enums.FlowState.NIGHT: &"night",
}
const PAUSE_SCREEN := &"pause_menu"
const PLAY_STATES := [Enums.FlowState.FIELD, Enums.FlowState.BASE_MORNING, Enums.FlowState.BASE_STAY,
	Enums.FlowState.NIGHT]

var _root: Control
var _panel: Control
var _pause_open := false


func _ready() -> void:
	layer = 25  # above UI screens (20), below the overlay (30)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = &"Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	if UI.theme != null:
		_root.theme = UI.theme
	UI.theme_changed.connect(func(t: Theme) -> void: _root.theme = t)
	EventBus.flow_state_changed.connect(_on_flow_state_changed)
	_on_flow_state_changed(GameState.flow_state)


func _on_flow_state_changed(state: Enums.FlowState) -> void:
	_close_pause()
	_clear()
	var screen: StringName = SCREEN_FOR_STATE.get(state, &"")
	if screen != &"" and UI.has_screen(screen):
		if not UI.is_open(screen):
			UI.open(screen)
		return
	match state:
		Enums.FlowState.TITLE:
			_show_title()
		Enums.FlowState.BASE_STAY:
			_show_bar("기지에 머무는 중 · %d일차" % GameState.day, "하루 마치기", SceneRouter.end_stay)
		Enums.FlowState.NIGHT:
			_show_night()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if UI.cinematic != null and (UI.cinematic.skippable or UI.cinematic.is_talking()):
		return  # Esc is "hold to skip" in a cutscene
	if _pause_open:
		_close_pause()
		get_viewport().set_input_as_handled()
		return
	if not GameState.flow_state in PLAY_STATES or not UI.stack_ids().is_empty():
		return
	if UI.has_screen(PAUSE_SCREEN):
		UI.open(PAUSE_SCREEN)
	else:
		_show_pause()
	get_viewport().set_input_as_handled()


# --- Title ---

func _show_title() -> void:
	var box := _center_box("A walking disaster", "포스트 아포칼립스 생존기")
	box.add_child(_button("새 게임", func() -> void: SceneRouter.start_new_game(0)))
	var info := SaveSystem.slot_info(0)
	if info["exists"] and info["compatible"]:
		box.add_child(_button("이어하기 (%d일차)" % info["day"], func() -> void: SceneRouter.load_game(0)))
	if SaveSystem.has_suspend():
		box.add_child(_button("중단한 출격 이어하기", func() -> void: SceneRouter.load_suspended()))
	box.add_child(_button("종료", func() -> void: get_tree().quit()))
	_focus_first(box)


# --- Night ---

func _show_night() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = dim
	_root.add_child(dim)
	var box := _center_box("%d일차 밤" % GameState.day, "모두 잠자리에 든다", dim)
	box.add_child(_button("잠자기 (다음 날 아침)", SceneRouter.finish_night))
	_focus_first(box)


# --- Pause ---

func _show_pause() -> void:
	_pause_open = true
	# The field keeps running under the pause box (user decision 2026-11-06).
	get_tree().paused = GameState.flow_state != Enums.FlowState.FIELD
	var dim := ColorRect.new()
	dim.name = &"Pause"
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var in_field := GameState.flow_state == Enums.FlowState.FIELD
	var box := _center_box("일시정지", "출격 중에 나가면 이어서 할 수 있어요" if in_field else "아침마다 자동 저장돼요", dim)
	box.add_child(_button("계속하기", _close_pause))
	box.add_child(_button("타이틀로", func() -> void:
		_close_pause()
		SceneRouter.quit_to_title()))
	box.add_child(_button("게임 종료", func() -> void:
		if in_field:
			SaveSystem.save_suspend()
		get_tree().quit()))
	_focus_first(box)


func _close_pause() -> void:
	if not _pause_open:
		return
	_pause_open = false
	get_tree().paused = false
	var p := _root.get_node_or_null(^"Pause")
	if p != null:
		p.queue_free()


# --- Building blocks ---

func _clear() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null


## A small bar at the bottom centre with a label and one button (Enter presses it).
func _show_bar(text: String, button_text: String, action: Callable) -> void:
	var pc := PanelContainer.new()
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pc.offset_bottom = -120
	_panel = pc
	_root.add_child(pc)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 24)
	pc.add_child(h)
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	var b := _button(button_text + " (Enter)", action)
	b.shortcut = _enter_shortcut()
	h.add_child(b)


func _center_box(title: String, subtitle: String, parent: Control = null) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent == null:
		_panel = center
		_root.add_child(center)
	else:
		parent.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(520, 0)
	center.add_child(pc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 14)
	pc.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override(&"font_size", 40)
	box.add_child(t)
	var s := Label.new()
	s.text = subtitle
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.modulate = Color(1, 1, 1, 0.7)
	box.add_child(s)
	box.add_child(HSeparator.new())
	return box


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.pressed.connect(action)
	return b


func _focus_first(box: VBoxContainer) -> void:
	for c in box.get_children():
		if c is Button:
			(c as Button).call_deferred(&"grab_focus")
			return


func _enter_shortcut() -> Shortcut:
	var sc := Shortcut.new()
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	sc.events = [ev]
	return sc
