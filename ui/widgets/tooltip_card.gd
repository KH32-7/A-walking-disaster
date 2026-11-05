class_name TooltipCard
extends PanelContainer
## Cream item tooltip (UI_RULES §5): action tab, tag chips (kind grey + rarity colour+shape),
## title, description, stat rows with dividers, foot row (count · size · weight/price). Owner: Lane D.
## show_info(info) with keys: title, rarity (int, -1 none), tags (Array[String]), desc,
## stats ([[label, value, "up"|"dn"|""]]), foot (Array[String]), action (String).

var _v: VBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	custom_minimum_size = Vector2(330, 0)
	_v = VBoxContainer.new()
	_v.add_theme_constant_override(&"separation", 0)
	_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_v)
	visible = false
	z_index = 50


func show_info(info: Dictionary, at: Vector2) -> void:
	MenuScreen.clear(_v)
	if not String(info.get("action", "")).is_empty():
		var tab := PanelContainer.new()
		tab.add_theme_stylebox_override(&"panel", _box(UiTokens.CREAM, 12, 6, [4, 4, 0, 0]))
		tab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tab.add_child(_l("◉  " + String(info.action), 14, UiTokens.TEXT_ON_CREAM, 700))
		_v.add_child(tab)
	var body := PanelContainer.new()
	body.add_theme_stylebox_override(&"panel", _box(UiTokens.CREAM, 14, 12, [0, 4, 4, 4]))
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override(&"separation", 6)
	body.add_child(bv)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override(&"separation", 4)
	for t: String in info.get("tags", []):
		tags.add_child(_chip(t, UiTokens.GREY_BTN, null))
	var r := int(info.get("rarity", -1))
	if r >= 0:
		tags.add_child(_chip(UiTokens.RARITY_NAMES[clampi(r, 0, 4)], UiTokens.rarity_color(r), r))
	bv.add_child(tags)
	bv.add_child(_l(String(info.get("title", "")), 21, UiTokens.TEXT_ON_CREAM, 700))
	var desc := String(info.get("desc", ""))
	if not desc.is_empty():
		var d := _l(desc, 14, Color("3b3b42"), 500)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(300, 0)
		bv.add_child(d)
	for row: Array in info.get("stats", []):
		var line := ColorRect.new()
		line.color = Color(0, 0, 0, 0.1)
		line.custom_minimum_size = Vector2(0, 1)
		bv.add_child(line)
		var h := HBoxContainer.new()
		var a := _l(String(row[0]), 14, UiTokens.TEXT_ON_CREAM, 500)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		var mark := String(row[2]) if row.size() > 2 else ""
		var col := UiTokens.TEXT_ON_CREAM
		if mark == "up":
			col = Color("2f8f3a")
		elif mark == "dn":
			col = UiTokens.DANGER
		h.add_child(_l(String(row[1]) + (" ▲" if mark == "up" else (" ▼" if mark == "dn" else "")), 14, col, 700))
		bv.add_child(h)
	_v.add_child(body)
	var foot: Array = info.get("foot", [])
	if not foot.is_empty():
		var f := PanelContainer.new()
		f.add_theme_stylebox_override(&"panel", _box(UiTokens.CREAM_2, 14, 7, [0, 0, 4, 4]))
		var fh := HBoxContainer.new()
		for t: String in foot:
			var l := _l(t, 13, UiTokens.TEXT_ON_CREAM, 600)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			fh.add_child(l)
		f.add_child(fh)
		_v.add_child(f)
	visible = true
	reset_size()
	var vp := get_viewport_rect().size
	position = Vector2(minf(at.x, vp.x - size.x - 16), minf(at.y, vp.y - size.y - 16))


func _l(t: String, s: int, c: Color, w: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override(&"font", UiThemeBuilder.font_kr(w))
	l.add_theme_font_size_override(&"font_size", s)
	l.add_theme_color_override(&"font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _chip(t: String, bg: Color, rarity: Variant) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override(&"panel", _box(bg, 7, 2, [0, 0, 0, 0]))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 4)
	if rarity != null:
		var b := ShapeBadge.new()
		b.value = int(rarity)
		b.badge_size = 11
		b.modulate = Color(0, 0, 0, 0.55)
		h.add_child(b)
	h.add_child(_l(t, 11, Color.WHITE, 700))
	p.add_child(h)
	return p


func _box(bg: Color, px: int, py: int, r: Array) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = r[0]
	sb.corner_radius_top_right = r[1]
	sb.corner_radius_bottom_right = r[2]
	sb.corner_radius_bottom_left = r[3]
	sb.content_margin_left = px
	sb.content_margin_right = px
	sb.content_margin_top = py
	sb.content_margin_bottom = py
	return sb
