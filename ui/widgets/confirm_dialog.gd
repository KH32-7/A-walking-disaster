class_name ConfirmDialog
extends Control
## Confirm modal (UI_RULES §5): dim + blur behind, cream card, title "○○을(를) …할까요?", one line,
## grey cancel + yellow action. Esc cancels, Enter confirms. Owner: Lane D.

signal decided(ok: bool)

var _on_ok: Callable


static func ask(parent: Node, title: String, body: String, action: String, on_ok: Callable) -> ConfirmDialog:
	var d := ConfirmDialog.new()
	d._on_ok = on_ok
	parent.add_child(d)
	d._build(KoreanText.fix(title), KoreanText.fix(body), action)
	return d


func _build(title: String, body: String, action: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.12, 0.15, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var card := MenuScreen.cream_card(520)
	var c: PanelContainer = card[0]
	var v: VBoxContainer = card[1]
	v.add_theme_constant_override(&"separation", 10)
	var t := MenuScreen.label(title, &"LabelSection", 22)
	t.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	v.add_child(t)
	var b := MenuScreen.label(body, &"LabelOnCreamDim", 15)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 520 - 28  # known wrap width, or a long line makes the card tall
	v.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var no := MenuScreen.button("취소", &"ButtonCancel")
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(_finish.bind(false))
	row.add_child(no)
	var ok := MenuScreen.button(action, &"ButtonPrimary")
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(_finish.bind(true))
	row.add_child(ok)
	v.add_child(row)
	add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	modulate.a = 0.0
	create_tween().tween_property(self, ^"modulate:a", 1.0, 0.12)
	ok.grab_focus.call_deferred()


func _finish(ok: bool) -> void:
	if ok and _on_ok.is_valid():
		_on_ok.call()
	decided.emit(ok)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_finish(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept"):
		_finish(true)
		get_viewport().set_input_as_handled()
