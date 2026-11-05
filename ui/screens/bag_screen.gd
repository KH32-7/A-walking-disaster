extends MenuScreen
## Field bag (D-08). Owner: Lane D. Design 02 "루팅", 14 "가방". Rules: UI_RULES §5, 메뉴 스킨.
## Columns: [container being looted] [equipment] [bag grid + safe pocket].
## Bag changes go through Bag (A-08) API only; looting through LootContainer.take() (B-08).
## Keys: Esc / Tab close, Space take all, R rotate while dragging, right click = menu.
## open_with({"container": LootContainer})

var container: Node = null
var _tip: TooltipCard
var _ctx: PanelContainer
var _loot_box: GridContainer
var _loot_count: Label
var _bag: BagGrid
var _pocket: BagGrid
var _bag_count: Label
var _shimmer_t := 0.0


func _init() -> void:
	title_text = "가방"
	subtitle_text = "필드"
	header_resources = []
	footer_keys = [["Esc", "닫기"], ["끌기", "옮기기"], ["R", "돌리기"], ["우클릭", "메뉴"], ["Space", "모두 담기"]]


func open_with(args: Dictionary) -> void:
	var c: Variant = args.get("container", null)
	if c != container:
		_bind(c as Node)
	if _loot_box != null:
		_fill_loot()


func _bind(c: Node) -> void:
	if container != null and is_instance_valid(container):
		for pair in [[&"slot_revealed", _on_loot_changed3], [&"slot_taken", _on_loot_changed3],
				[&"reveal_finished", _fill_loot], [&"session_ended", close]]:
			if container.is_connected(pair[0], pair[1]):
				container.disconnect(pair[0], pair[1])
	container = c
	if c == null:
		return
	c.connect(&"slot_revealed", _on_loot_changed3)
	c.connect(&"slot_taken", _on_loot_changed3)
	c.connect(&"reveal_finished", _fill_loot)
	c.connect(&"session_ended", close)


func on_closing() -> void:
	if container != null and is_instance_valid(container) and container.has_method(&"cancel_open"):
		_bind(null)


func _build_body(b: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(row)
	if container != null:
		var lp := MenuScreen.panel(_container_name(), "")
		(lp[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_loot_count = (lp[2] as HBoxContainer).get_child(1)
		_loot_box = GridContainer.new()
		_loot_box.columns = 4
		_loot_box.add_theme_constant_override(&"h_separation", 8)
		_loot_box.add_theme_constant_override(&"v_separation", 8)
		(lp[1] as VBoxContainer).add_child(_loot_box)
		var all := MenuScreen.button("모두 담기  Space", &"ButtonSoft")
		all.pressed.connect(take_all)
		(lp[1] as VBoxContainer).add_child(all)
		row.add_child(lp[0])
	var ep := MenuScreen.panel("장비", "")
	(ep[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var eg := GridContainer.new()
	eg.columns = 3
	eg.add_theme_constant_override(&"h_separation", 8)
	eg.add_theme_constant_override(&"v_separation", 8)
	for s in ItemInfo.SLOT_NAMES.size():
		eg.add_child(_equip_cell(s))
	(ep[1] as VBoxContainer).add_child(eg)
	var sum: Dictionary = Armory.get_owner_summary(Armory.PLAYER_ID)
	(ep[1] as VBoxContainer).add_child(MenuScreen.label("방어 %d · 방어구 소음 %+.1fm" % [int(sum.get("defense", 0)),
		float(sum.get("armor_noise", 0.0))], &"LabelDim", 14))
	row.add_child(ep[0])
	var bp := MenuScreen.panel("가방", "")
	(bp[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_bag_count = (bp[2] as HBoxContainer).get_child(1)
	_bag = BagGrid.new()
	_bag.area = Bag.AREA_BAG
	(bp[1] as VBoxContainer).add_child(_bag)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override(&"separation", 12)
	ph.add_child(MenuScreen.label("안전 주머니", &"LabelSection", 16))
	ph.add_child(MenuScreen.label("쓰러져도 남아요", &"LabelDim", 13))
	(bp[1] as VBoxContainer).add_child(ph)
	_pocket = BagGrid.new()
	_pocket.area = Bag.AREA_POCKET
	(bp[1] as VBoxContainer).add_child(_pocket)
	row.add_child(bp[0])
	for g: BagGrid in [_bag, _pocket]:
		g.hovered.connect(_on_hover)
		g.unhovered.connect(func() -> void: _tip.visible = false)
		g.context_requested.connect(_on_context)
	_tip = TooltipCard.new()
	add_child(_tip)
	EventBus.bag_changed.connect(_update_counts)
	_update_counts()
	if container != null:
		_fill_loot()


func _container_name() -> String:
	var names := ["서랍", "약품장", "공구함", "보급 상자", "마물 둥지"]
	if container != null and &"def" in container and container.def != null:
		return names[clampi(int(container.def.type), 0, names.size() - 1)]
	return "상자"


func _update_counts() -> void:
	var used := 0
	for e: Dictionary in Bag.entries(Bag.AREA_BAG):
		used += int(e.size.x) * int(e.size.y)
	_bag_count.text = "%d / %d칸" % [used, Bag.cell_count(Bag.AREA_BAG)]


func _on_loot_changed3(_i: int, _id: StringName, _n: int) -> void:
	_fill_loot()


func _fill_loot() -> void:
	if _loot_box == null or container == null or not is_instance_valid(container):
		return
	MenuScreen.clear(_loot_box)
	var slots: Array = container.call(&"get_slots")
	var known := 0
	for i in slots.size():
		var s: Dictionary = slots[i]
		if bool(s.identified):
			known += 1
		_loot_box.add_child(_loot_cell(i, s))
	_loot_count.text = "확인 %d / %d" % [known, slots.size()]


func _loot_cell(i: int, s: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(84, 84)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.bg_color = Color(0.33, 0.43, 0.53, 0.55)
	for st in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		b.add_theme_stylebox_override(st, sb)
	if not bool(s.identified):
		var sh := Shimmer.new()
		sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sh)
		b.disabled = true
	elif int(s.count) <= 0:
		b.modulate.a = 0.35
		b.disabled = true
	else:
		var info := ItemInfo.for_resource(StringName(s.item_id))
		var tex := ItemInfo.icon(StringName(s.item_id))
		if tex != null:
			b.icon = tex
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.text = "%s ×%d" % [info.name, int(s.count)]
		else:
			b.text = "%s\n×%d" % [info.name, int(s.count)]
		b.add_theme_font_size_override(&"font_size", 13)
		b.add_theme_color_override(&"font_color", UiTokens.TEXT)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(func() -> void:
			if int(container.call(&"take", i)) <= 0:
				EventBus.notification_posted.emit("가방에 자리가 없어요", &"warn")
			_fill_loot())
		b.mouse_entered.connect(func() -> void:
			_tip.show_info(info.tooltip, b.global_position + Vector2(b.size.x + 10, 0)))
		b.mouse_exited.connect(func() -> void: _tip.visible = false)
	return b


func take_all() -> void:
	if container == null or not is_instance_valid(container):
		return
	var slots: Array = container.call(&"get_slots")
	for i in slots.size():
		if bool(slots[i].identified) and int(slots[i].count) > 0:
			container.call(&"take", i)
	_fill_loot()


func _equip_cell(slot: int) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 3)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(92, 92)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.bg_color = Color(0.33, 0.43, 0.53, 0.4)
	var uid := Armory.get_equipped(Armory.PLAYER_ID, slot)
	var text := ""
	var has_art := false
	if uid != &"":
		var info := ItemInfo.for_item(uid)
		text = String(info.name)
		var tex := ItemInfo.icon(StringName(info.get("icon", &"")))
		if tex != null:
			p.add_child(_icon_box(tex))
			has_art = true
		if int(info.rarity) > 0:
			sb.bg_color = Color(UiTokens.rarity_color(int(info.rarity)), 0.35)
		p.mouse_entered.connect(func() -> void:
			_tip.show_info(info.tooltip, p.global_position + Vector2(p.size.x + 10, 0)))
		p.mouse_exited.connect(func() -> void: _tip.visible = false)
	else:
		p.modulate.a = 0.6
	p.add_theme_stylebox_override(&"panel", sb)
	var l := MenuScreen.label(text, &"LabelHud", 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	if has_art:
		l.size_flags_vertical = Control.SIZE_SHRINK_END
	p.add_child(l)
	v.add_child(p)
	var cap := MenuScreen.label(ItemInfo.SLOT_NAMES[slot], &"LabelHud", 14)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	return v


## Item art inside a slot panel; the bottom strip stays free for the name label.
static func _icon_box(tex: Texture2D) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right"]:
		m.add_theme_constant_override("margin_" + side, 6)
	m.add_theme_constant_override(&"margin_bottom", 20)
	var ic := TextureRect.new()
	ic.texture = tex
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(ic)
	return m


func _on_hover(e: Dictionary, r: Rect2) -> void:
	var info := ItemInfo.for_entry(e)
	var tip: Dictionary = info.tooltip
	if StringName(e.kind) == &"item":
		var slot := int(info.get("slot", -1))
		var cur := Armory.get_equipped(Armory.PLAYER_ID, slot) if slot >= 0 else &""
		if cur != &"":
			tip = ItemInfo.for_item(StringName(e.ref), cur).tooltip
	var foot: Array = tip.get("foot", [])
	if foot.is_empty():
		tip["foot"] = ["×%d" % int(info.get("count", 1)), "%d×%d칸" % [e.size.x, e.size.y]]
	_tip.show_info(tip, r.position + Vector2(r.size.x + 12, 0))


func _on_context(e: Dictionary, at: Vector2) -> void:
	_tip.visible = false
	if _ctx != null:
		_ctx.queue_free()
	_ctx = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTokens.CREAM
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_ctx.add_theme_stylebox_override(&"panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	_ctx.add_child(v)
	var info := ItemInfo.for_entry(e)
	var head := MenuScreen.label("   " + String(info.name), &"LabelOnCreamDim", 12)
	v.add_child(head)
	var to_pocket := int(e.area) == Bag.AREA_BAG
	v.add_child(_ctx_row("안전 주머니로" if to_pocket else "가방으로", func() -> void:
		_move_area(e, Bag.AREA_POCKET if to_pocket else Bag.AREA_BAG)))
	v.add_child(_ctx_row("버리기", func() -> void: _confirm_drop(e)))
	add_child(_ctx)
	_ctx.position = at
	_ctx.z_index = 60


func _ctx_row(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "   " + text + "        "
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	var n := StyleBoxEmpty.new()
	var h := StyleBoxFlat.new()
	h.bg_color = UiTokens.ACCENT
	b.add_theme_stylebox_override(&"normal", n)
	b.add_theme_stylebox_override(&"hover", h)
	b.add_theme_stylebox_override(&"pressed", h)
	b.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
	b.add_theme_color_override(&"font_hover_color", UiTokens.TEXT_ON_CREAM)
	b.add_theme_font_size_override(&"font_size", 15)
	b.custom_minimum_size = Vector2(200, 34)
	b.pressed.connect(func() -> void:
		cb.call()
		if _ctx != null:
			_ctx.queue_free()
			_ctx = null)
	return b


func _move_area(e: Dictionary, to_area: int) -> void:
	var base: Vector2i = Vector2i(e.size.y, e.size.x) if bool(e.rotated) else Vector2i(e.size)
	var dims := Bag.POCKET_SIZE if to_area == Bag.AREA_POCKET else Vector2i(Bag.grid_size.x, Bag.grid_size.y + 1)
	for rot in [false, true]:
		for y in dims.y:
			for x in dims.x:
				if Bag.can_place(base, Vector2i(x, y), rot, to_area, int(e.id)):
					Bag.move(int(e.id), Vector2i(x, y), rot, to_area)
					return
	EventBus.notification_posted.emit("자리가 없어요", &"warn")


func _confirm_drop(e: Dictionary) -> void:
	var info := ItemInfo.for_entry(e)
	ConfirmDialog.ask(self, "%s을(를) 버릴까요?" % info.name, "버린 물건은 되찾을 수 없어요.", "버리기",
		func() -> void: Bag.remove(int(e.id)))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_SPACE:
			take_all()
			get_viewport().set_input_as_handled()
		elif k == KEY_TAB:
			# Mark handled first: close() removes this node, so get_viewport() is null afterwards (#86).
			get_viewport().set_input_as_handled()
			close()
	if event is InputEventMouseButton and event.pressed and _ctx != null and not _ctx.get_global_rect().has_point(get_global_mouse_position()):
		_ctx.queue_free()
		_ctx = null


## Unidentified loot slot (UI_RULES §5): iridescent sweep every second, solid when reduce_flash.
class Shimmer:
	extends Control
	var t := 0.0

	func _process(delta: float) -> void:
		t = fmod(t + delta, 1.0)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		if bool(Settings.get_value(&"reduce_flash")):
			draw_rect(r, Color(1, 1, 1, 0.15 + 0.1 * sin(t * TAU)))
			return
		var cols := [Color("2a2c38"), Color("9a6bd8"), Color("ffffff"), Color("5fd6e6"), Color("2a2c38")]
		var n := 24
		for i in n:
			var u := float(i) / n
			var p := fposmod(u - t, 1.0)
			var k := p * (cols.size() - 1)
			var c: Color = (cols[int(k)] as Color).lerp(cols[mini(int(k) + 1, cols.size() - 1)], k - int(k))
			draw_rect(Rect2(r.position.x + r.size.x * u, r.position.y, r.size.x / n + 1, r.size.y), Color(c, 0.85))
