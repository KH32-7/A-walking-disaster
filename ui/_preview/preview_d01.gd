extends Control
## D-01 preview: tokens, type variations, badges, screen stack, subtitle. Run this scene (F6).
## Keys: 1/2/3 text size, H high contrast, O open sample screen, C open confirm overlay,
##       Esc close top, R radio line.  Fake data only.

var _info: Label


func _ready() -> void:
	theme = UI.theme
	UI.theme_changed.connect(func(t: Theme) -> void: theme = t)
	var bg := ColorRect.new()
	bg.color = Color("1f4e55")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.position = Vector2(40, 30)
	col.add_theme_constant_override(&"separation", 18)
	add_child(col)
	col.add_child(_label("D-01 미리보기", &"LabelTitle"))
	_info = _label("", &"LabelHud")
	col.add_child(_info)
	col.add_child(_row_badges())
	col.add_child(_row_buttons())
	col.add_child(_row_panels())
	_register_samples()
	_update_info()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1, KEY_2, KEY_3:
			Settings.set_value(&"text_size", (event as InputEventKey).keycode - KEY_1)
		KEY_H:
			Settings.set_value(&"high_contrast", not bool(Settings.get_value(&"high_contrast")))
		KEY_O:
			UI.open(&"_preview_bag", {"title": "가방"})
		KEY_C:
			UI.open(&"_preview_confirm")
		KEY_R:
			EventBus.radio_message.emit(&"broadcaster", "들리나? 상가 3층 승강기 쪽에서 누가 문을 두드린다더군.", 1)
	_update_info()


func _update_info() -> void:
	_info.text = "글자 %d · 고대비 %s · 열린 화면 %s   [1/2/3] 글자 [H] 고대비 [O] 화면 [C] 확인창 [Esc] 닫기 [R] 무전" % [
		int(Settings.get_value(&"text_size")), "켬" if Settings.get_value(&"high_contrast") else "끔", UI.stack_ids()]


func _label(text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


func _row_badges() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	for r in 5:
		var b := ShapeBadge.new()
		b.value = r
		b.badge_size = 18
		b.show_label = true
		row.add_child(b)
	for e in range(1, 5):
		var b := ShapeBadge.new()
		b.kind = ShapeBadge.Kind.ELEMENT
		b.value = e
		b.badge_size = 18
		b.show_label = true
		row.add_child(b)
	return row


func _row_buttons() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	for pair in [["수락", &"ButtonPrimary"], ["받기", &"ButtonSecondary"], ["취소", &"ButtonCancel"],
			["모두 담기", &"ButtonSoft"], ["훈련", &"ButtonSpecial"]]:
		var b := Button.new()
		b.text = pair[0]
		b.theme_type_variation = pair[1]
		row.add_child(b)
	for t in ["가방", "지도", "기록"]:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.button_pressed = t == "가방"
		b.theme_type_variation = &"TabText"
		row.add_child(b)
	return row


func _row_panels() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	var menu := PanelContainer.new()
	menu.theme_type_variation = &"PanelMenu"
	menu.custom_minimum_size = Vector2(420, 220)
	var mv := VBoxContainer.new()
	menu.add_child(mv)
	var band := PanelContainer.new()
	band.theme_type_variation = &"PanelBand"
	var bh := HBoxContainer.new()
	band.add_child(bh)
	bh.add_child(_label("가방", &"LabelSection"))
	var cnt := _label("13/30", &"LabelDim")
	cnt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(cnt)
	var all := Button.new()
	all.text = "모두 담기"
	all.theme_type_variation = &"ButtonSoft"
	bh.add_child(all)
	mv.add_child(band)
	mv.add_child(_label("판 머리띠 + 반투명 판 (메뉴 스킨)", &"LabelDim"))
	row.add_child(menu)

	var card := PanelContainer.new()
	card.theme_type_variation = &"CardCream"
	card.custom_minimum_size = Vector2(330, 0)
	var cv := VBoxContainer.new()
	card.add_child(cv)
	var tags := HBoxContainer.new()
	var rb := ShapeBadge.new()
	rb.value = 1
	rb.show_label = true
	rb.label_color = UiTokens.TEXT_ON_CREAM
	tags.add_child(rb)
	cv.add_child(tags)
	var title := _label("방탄 조끼 Lv2", &"LabelSection")
	title.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	cv.add_child(title)
	cv.add_child(_label("무겁지만 단단합니다.", &"LabelOnCream"))
	cv.add_child(_label("방어 9 → 18 · 이동 소음 4m → 5m", &"LabelOnCreamDim"))
	row.add_child(card)

	var hud := VBoxContainer.new()
	var ammo := _label("018", &"LabelNumber")
	ammo.add_theme_font_size_override(&"font_size", UiTokens.SIZE_HUD_AMMO)
	hud.add_child(ammo)
	hud.add_child(_label("개조 소총 · ≡ 64", &"LabelHud"))
	row.add_child(hud)
	return row


func _register_samples() -> void:
	UI.register_screen(&"_preview_bag", _pack(_sample_screen("가방 (샘플 화면) · Esc로 닫기", false)),
		{"pauses_game": true})
	UI.register_screen(&"_preview_confirm", _pack(_sample_screen("고철로 분해할까요?", true)),
		{"is_overlay": true})


func _pack(node: Control) -> PackedScene:
	var p := PackedScene.new()
	p.pack(node)
	node.free()
	return p


func _sample_screen(text: String, cream: bool) -> Control:
	var root := Control.new()
	var dim := ColorRect.new()
	dim.color = UiTokens.BACKDROP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	dim.owner = root
	var p := PanelContainer.new()
	p.theme_type_variation = &"CardCream" if cream else &"PanelMenu"
	p.position = Vector2(560, 300)
	p.custom_minimum_size = Vector2(520, 200)
	root.add_child(p)
	p.owner = root
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"LabelOnCream" if cream else &"LabelSection"
	p.add_child(l)
	l.owner = root
	return root
