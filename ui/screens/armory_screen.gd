extends MenuScreen
## Armory + storage (D-08). Owner: Lane D. Design 05 "장비 슬롯", 11 "보관", 14 "무기고·창고".
## Pick who to dress (player or a resident), see their 7 slots, click a stored item to equip it
## (Armory.equip), click a worn slot to take it off (Armory.unequip → storage). Hover compares with
## what that person wears. Right column: base storage resources (Economy) and the storage cap.
## open_with({"resident_id": id}) preselects a resident.

var _owner: StringName = Armory.PLAYER_ID
var _slot := -1
var _owners: HBoxContainer
var _equip: GridContainer
var _list: GridContainer
var _tabs: HBoxContainer
var _store: VBoxContainer
var _tip: TooltipCard
var _sum: Label


func _init() -> void:
	title_text = "무기고"
	subtitle_text = "기지"
	footer_keys = [["Esc", "뒤로"], ["클릭", "입히기 / 벗기기"]]


func open_with(args: Dictionary) -> void:
	if args.has("resident_id"):
		_owner = StringName(args.resident_id)
		if _equip != null:
			_refresh()


func _build_body(b: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 22)
	b.add_child(row)
	var lp := MenuScreen.panel("입을 사람", "", Vector2(440, 0))
	(lp[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	_owners = HBoxContainer.new()
	_owners.add_theme_constant_override(&"separation", 8)
	var osc := ScrollContainer.new()
	osc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	osc.custom_minimum_size = Vector2(0, 48)
	osc.add_child(_owners)
	(lp[1] as VBoxContainer).add_child(osc)
	_equip = GridContainer.new()
	_equip.columns = 3
	_equip.add_theme_constant_override(&"h_separation", 10)
	_equip.add_theme_constant_override(&"v_separation", 10)
	(lp[1] as VBoxContainer).add_child(_equip)
	_sum = MenuScreen.label("", &"LabelDim", 14)
	(lp[1] as VBoxContainer).add_child(_sum)
	row.add_child(lp[0])
	var mp := MenuScreen.panel("보관 중인 장비", "", Vector2(0, 0))
	(mp[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(mp[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override(&"separation", 8)
	(mp[1] as VBoxContainer).add_child(_tabs)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = GridContainer.new()
	_list.columns = 6
	_list.add_theme_constant_override(&"h_separation", 8)
	_list.add_theme_constant_override(&"v_separation", 8)
	sc.add_child(_list)
	(mp[1] as VBoxContainer).add_child(sc)
	row.add_child(mp[0])
	var rp := MenuScreen.panel("창고", "", Vector2(360, 0))
	(rp[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	_store = rp[1]
	row.add_child(rp[0])
	_tip = TooltipCard.new()
	add_child(_tip)
	EventBus.equipment_changed.connect(func(_o: StringName, _s: int) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	_fill_owners()
	_fill_equip()
	_fill_tabs()
	_fill_list()
	_fill_store()


func _fill_owners() -> void:
	MenuScreen.clear(_owners)
	var ids: Array = [Armory.PLAYER_ID]
	ids.append_array(Colony.active_resident_ids())
	for id: StringName in ids:
		var name := "나" if id == Armory.PLAYER_ID else String(Colony.get_resident(id).get("name", id))
		var t := MenuScreen.button(name, &"TabText")
		t.toggle_mode = true
		t.button_pressed = id == _owner
		t.pressed.connect(func() -> void:
			_owner = id
			_refresh())
		_owners.add_child(t)


func _fill_equip() -> void:
	MenuScreen.clear(_equip)
	for s in ItemInfo.SLOT_NAMES.size():
		var uid := Armory.get_equipped(_owner, s)
		var cell := _cell(uid, 108, ItemInfo.SLOT_NAMES[s])
		var bt: Button = cell.get_child(0)
		if uid != &"":
			bt.pressed.connect(func() -> void: Armory.unequip(_owner, s))
		else:
			bt.pressed.connect(func() -> void:
				_slot = s
				_fill_tabs()
				_fill_list())
		_equip.add_child(cell)
	var sum: Dictionary = Armory.get_owner_summary(_owner)
	_sum.text = "방어 %d / 방어구 소음 %+.1fm / 최대 체력 +%d" % [int(sum.get("defense", 0)), float(sum.get("armor_noise", 0.0)),
		int(sum.get("max_hp", 0))]


func _fill_tabs() -> void:
	MenuScreen.clear(_tabs)
	var all := MenuScreen.button("전체", &"TabText")
	all.toggle_mode = true
	all.button_pressed = _slot == -1
	all.pressed.connect(func() -> void:
		_slot = -1
		_fill_tabs()
		_fill_list())
	_tabs.add_child(all)
	for s in ItemInfo.SLOT_NAMES.size():
		var t := MenuScreen.button(ItemInfo.SLOT_NAMES[s], &"TabText")
		t.toggle_mode = true
		t.button_pressed = _slot == s
		t.pressed.connect(func() -> void:
			_slot = s
			_fill_tabs()
			_fill_list())
		_tabs.add_child(t)


func _fill_list() -> void:
	MenuScreen.clear(_list)
	var uids := Armory.list_storage(_slot)
	for uid: StringName in uids:
		var cell := _cell(uid, 112, "")
		var bt: Button = cell.get_child(0)
		var it: ItemInstance = Armory.get_item(uid)
		var def: ItemDef = Armory.get_def(it.def_id) if it != null else null
		if def != null:
			var slot := int(def.slot)
			var ok := Armory.can_go_in_slot(it.def_id, slot)
			bt.disabled = not ok
			bt.pressed.connect(func() -> void:
				if not Armory.equip(_owner, slot, uid):
					EventBus.notification_posted.emit("이 사람은 그 장비를 쓸 수 없어요", &"warn"))
			bt.mouse_entered.connect(func() -> void:
				var cur := Armory.get_equipped(_owner, slot)
				_tip.show_info(ItemInfo.for_item(uid, cur).tooltip, bt.global_position + Vector2(bt.size.x + 10, 0)))
			bt.mouse_exited.connect(func() -> void: _tip.visible = false)
		_list.add_child(cell)
	if uids.is_empty():
		_list.add_child(MenuScreen.label("보관 중인 장비가 없어요.", &"LabelDim", 15))


func _fill_store() -> void:
	while _store.get_child_count() > 1:
		var c := _store.get_child(1)
		_store.remove_child(c)
		c.queue_free()
	var cap := Economy.storage_cap()
	var used := Economy.capped_total()
	var head := MenuScreen.label("한도 %d / %d" % [used, cap], &"LabelHud", 16)
	if Economy.free_space() <= 0:
		head.add_theme_color_override(&"font_color", UiTokens.WARN)
	_store.add_child(head)
	_store.add_child(MenuScreen.bar(clampf(float(used) / maxf(1.0, cap), 0.0, 1.0),
		UiTokens.WARN if Economy.free_space() <= 0 else UiTokens.TEXT, 330, 6))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ids: Array = Economy.amounts.keys() if &"amounts" in Economy else []
	ids.sort()
	for id: StringName in ids:
		var n := Economy.get_amount(id)
		if n <= 0:
			continue
		var h := HBoxContainer.new()
		var nm := MenuScreen.label(MenuScreen.resource_name(id), &"LabelHud", 15)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		if not Economy.uses_cap(id):
			h.add_child(MenuScreen.label("한도 밖", &"LabelDim", 12))
		h.add_child(MenuScreen.label(str(n), &"LabelNumber", 17))
		v.add_child(h)
	sc.add_child(v)
	_store.add_child(sc)


func _cell(uid: StringName, s: int, caption: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 3)
	var b := Button.new()
	b.custom_minimum_size = Vector2(s, s * 0.8)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.bg_color = Color(0.33, 0.43, 0.53, 0.45)
	var hb := sb.duplicate() as StyleBoxFlat
	hb.border_color = UiTokens.LINE_STRONG
	hb.set_border_width_all(2)
	if uid != &"":
		var info := ItemInfo.for_item(uid)
		b.text = String(info.name)
		var r := int(info.rarity)
		if r > 0:
			sb.bg_color = Color(UiTokens.rarity_color(r), 0.38)
			hb.bg_color = sb.bg_color
		if caption != "":
			b.mouse_entered.connect(func() -> void:
				_tip.show_info(info.tooltip, b.global_position + Vector2(b.size.x + 10, 0)))
			b.mouse_exited.connect(func() -> void: _tip.visible = false)
	else:
		b.text = "비어 있음"
		b.modulate.a = 0.65
	for st in [&"normal", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override(&"hover", hb)
	b.add_theme_stylebox_override(&"pressed", hb)
	b.add_theme_font_size_override(&"font_size", 15)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(b)
	if caption != "":
		var c := MenuScreen.label(caption, &"LabelHud", 13)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(c)
	return v
