class_name MenuScreen
extends Control
## Base for every Tab / base menu screen (UI_RULES §4 "메뉴" + "메뉴 스킨"). Owner: Lane D.
## Gives: blurred backdrop, header (back circle + "장소 — 부제"), resource summary on the right,
## footer key hints, and small builders for panels / bands / labels / buttons / slots.
## Subclasses override _build_body(body: Control) and may implement open_with(args).

const BLUR := preload("res://ui/theme/backdrop_blur.gdshader")

## false for flow screens that only continue (result, evening).
var show_back := true
var title_text := ""
var subtitle_text := ""
## [[key, label], ...] shown in the footer.
var footer_keys: Array = [["Esc", "뒤로"]]
## Resource ids in the header summary.
var header_resources: Array[StringName] = [&"wood", &"stone", &"scrap", &"food", &"parts", &"cloth"]

var body: Control
## Blurred backdrop. Scene-type screens (UI_RULES §4 "장면형 화면") narrow it to the right side.
var backdrop: ColorRect
var _header_res: HBoxContainer
var _subtitle_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bd := ColorRect.new()
	bd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = BLUR
	if bool(Settings.get_value(&"reduce_flash")):
		mat.set_shader_parameter(&"blur_lod", 0.0)
	bd.material = mat
	add_child(bd)
	backdrop = bd
	_build_header()
	body = Control.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 52
	body.offset_right = -52
	body.offset_top = 110
	body.offset_bottom = -90
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	_build_footer()
	_build_body(body)
	EventBus.resources_changed.connect(func(_c: Dictionary) -> void: refresh_header())


func _build_body(_b: Control) -> void:
	pass


func close() -> void:
	UI.close(StringName(name))


# ---------------- header / footer ----------------

func _build_header() -> void:
	var h := HBoxContainer.new()
	h.position = Vector2(40, 30)
	h.add_theme_constant_override(&"separation", 14)
	var back := Button.new()
	back.text = "‹"
	back.theme_type_variation = &"ButtonCancel"
	back.custom_minimum_size = Vector2(46, 46)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(close)
	back.visible = show_back
	h.add_child(back)
	var t := label(title_text, &"LabelTitle")
	h.add_child(t)
	_subtitle_label = label("—  " + subtitle_text, &"LabelSection")
	_subtitle_label.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	_subtitle_label.visible = not subtitle_text.is_empty()
	h.add_child(_subtitle_label)
	add_child(h)
	_header_res = HBoxContainer.new()
	_header_res.add_theme_constant_override(&"separation", 20)
	add_child(_header_res)
	_header_res.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	_header_res.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_header_res.position += Vector2(-52, 40)
	refresh_header()


## Changes "장소 — 부제" after the screen is built (e.g. switching facility in the craft screen).
func set_subtitle(text: String) -> void:
	subtitle_text = text
	if _subtitle_label != null:
		_subtitle_label.text = "—  " + text
		_subtitle_label.visible = not text.is_empty()


func refresh_header() -> void:
	if _header_res == null:
		return
	for c in _header_res.get_children():
		c.queue_free()
	for id in header_resources:
		_header_res.add_child(resource_chip(id))


func _build_footer() -> void:
	var f := HBoxContainer.new()
	f.add_theme_constant_override(&"separation", 26)
	for pair: Array in footer_keys:
		var p := HBoxContainer.new()
		p.add_theme_constant_override(&"separation", 10)
		p.add_child(KeyChip.new(String(pair[0]), KeyChip.Style.OUTLINE))
		p.add_child(label(String(pair[1]), &"LabelHud"))
		f.add_child(p)
	add_child(f)
	f.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	f.grow_vertical = Control.GROW_DIRECTION_BEGIN
	f.position += Vector2(52, -34)


# ---------------- builders ----------------

static func label(text: String, variation: StringName = &"Label", size_px := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if size_px > 0:
		l.add_theme_font_size_override(&"font_size", size_px)
	return l


## Rounded menu panel with a band header (Duckov accent). Returns [panel, content VBox, band HBox].
static func panel(title: String, count := "", min_size := Vector2.ZERO) -> Array:
	var p := PanelContainer.new()
	p.theme_type_variation = &"PanelMenu"
	p.custom_minimum_size = min_size
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 12)
	p.add_child(v)
	var band := PanelContainer.new()
	band.theme_type_variation = &"PanelBand"
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override(&"separation", 12)
	band.add_child(bh)
	bh.add_child(label(title, &"LabelSection"))
	var c := label(count, &"LabelDim", 16)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(c)
	v.add_child(band)
	return [p, v, bh]


static func button(text: String, variation: StringName = &"ButtonPrimary") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_ALL
	return b


static func cream_card(min_w := 330.0) -> Array:
	var c := PanelContainer.new()
	c.theme_type_variation = &"CardCream"
	c.custom_minimum_size = Vector2(min_w, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	c.add_child(v)
	return [c, v]


static func bar(value: float, color: Color, w := 120.0, h := 6.0) -> SegBar:
	var b := SegBar.new()
	b.frame = false
	b.value = value
	b.fill_color = color
	b.empty_color = Color(1, 1, 1, 0.15)
	b.custom_minimum_size = Vector2(w, h)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


static func resource_chip(id: StringName) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 6)
	var def: Variant = Economy.get_def(id)
	var nm := label(String(def.name) if def != null else String(id), &"LabelDim", 15)
	h.add_child(nm)
	h.add_child(label(str(Economy.get_amount(id)), &"LabelNumber", 20))
	return h


static func resource_name(id: StringName) -> String:
	var def: Variant = Economy.get_def(id)
	return String(def.name) if def != null else String(id)


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in cost:
		parts.append("%s %d" % [resource_name(id), int(cost[id])])
	return " · ".join(parts)


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
