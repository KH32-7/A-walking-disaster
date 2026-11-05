extends MenuScreen
## Crafting · upgrade · repair · engraving (D-12). Owner: Lane D.
## Design 05 "강화", "내구도", "제작" · 06 "각인 규칙", "정제", "분해" · 14 "제작·강화·각인".
## UI_RULES §9: scene-type screen — the base stays visible on the left, the facility's slot row
## runs along the bottom, the right side has the before/after comparison and a cream card with
## the materials, the worker and the yellow action button.
##
## Every number comes from the Armory previews (A-09, A-10): preview_craft / upgrade / transfer /
## repair / engrave / remove_engraving / open_slot / refine / disassemble. This screen only picks
## what to preview and calls the matching action when the preview says ok.
##
## open_with({"facility": &"workshop" | &"sewing_room" | &"essence_workshop", "mode": StringName,
##   "uid": item uid}) — all optional.

const FACILITIES: Array[StringName] = [&"workshop", &"sewing_room", &"essence_workshop"]
const GEAR_MODES := [[&"craft", "제작"], [&"upgrade", "강화"], [&"transfer", "강화 옮기기"], [&"repair", "수리"]]
const ESSENCE_MODES := [[&"engrave", "각인"], [&"refine", "정제"], [&"disassemble", "분해"]]
const GRADE_NAMES := ["하급", "중급", "상급"]
const STRIP_HEADS := {&"craft": "만들 것", &"upgrade": "강화할 장비", &"transfer": "단계를 넘길 장비",
	&"repair": "고칠 장비", &"engrave": "각인할 장비", &"refine": "정제할 정수", &"disassemble": "분해할 장비"}

## Blocked reasons from the Armory previews → one line for the player.
const REASONS := {
	&"no_item": "장비를 골라 주세요.",
	&"no_recipe": "만들 것을 골라 주세요.",
	&"lost": "잃어버린 장비예요. 먼저 필드에서 찾아와야 해요.",
	&"max_level": "이미 +10이에요.",
	&"no_facility": "%s이(가) 아직 없어요. 건설에서 지을 수 있어요.",
	&"facility_level": "%s 레벨이 모자라요.",
	&"no_worker": "담당 주민이 없어요. 주민 화면에서 일을 맡겨 주세요.",
	&"cost": "재료가 모자라요.",
	&"worker_only": "주민이 하루 작업으로 만들어요. 저녁 정산 때 창고에 들어와요.",
	&"blueprint": "설계도가 있어야 만들 수 있어요.",
	&"same_item": "넘길 장비와 다른 장비를 골라 주세요.",
	&"slot_mismatch": "같은 부위 장비끼리만 옮길 수 있어요.",
	&"no_gain": "옮겨도 단계가 오르지 않아요.",
	&"full": "내구도가 가득 차 있어요.",
	&"unknown_essence": "넣을 정수를 골라 주세요.",
	&"not_engravable": "무기와 장신구에만 각인할 수 있어요.",
	&"no_slots": "정수 칸이 없어요.",
	&"bad_slot": "정수 칸을 골라 주세요.",
	&"same_essence": "이미 같은 정수가 들어 있어요.",
	&"empty_slot": "빈 칸이에요.",
	&"not_weapon": "슬롯 열기는 무기만 할 수 있어요.",
	&"has_slots": "이미 정수 칸이 있어요.",
	&"already_open": "이미 칸을 열었어요.",
	&"max_grade": "상급 정수는 더 정제할 수 없어요.",
	&"bad_times": "횟수를 정해 주세요.",
	&"not_in_storage": "무기고에 보관 중인 장비만 분해할 수 있어요. 먼저 벗겨 주세요.",
	&"no_engraving": "각인된 정수가 없어요.",
}

var _facility: StringName = &"workshop"
var _mode: StringName = &"craft"
## Selected thing in the strip: item uid, recipe id or essence id.
var _sel: StringName = &""
var _target: StringName = &""  # transfer: item that receives the level
var _slot := 0  # engrave: essence slot
var _essence: StringName = &""  # engrave: essence to put in
var _times := 1  # refine
var _family: StringName = &""  # upgrade +9 and up: family material choice
var _last := ""  # result line after an action

var _fac_tabs: HBoxContainer
var _mode_tabs: HBoxContainer
var _place: Label
var _place_sub: Label
var _strip_head: Label
var _strip_count: Label
var _strip: HBoxContainer
var _title: Label
var _title_badge: ShapeBadge
var _title_sub: Label
var _detail: VBoxContainer
var _card: VBoxContainer
var _do_button: Button
var _tip: TooltipCard


func _init() -> void:
	title_text = "제작"
	subtitle_text = "정비소"
	footer_keys = [["Esc", "뒤로"], ["Q / E", "시설"], ["1~4", "작업"], ["Enter", "실행"]]
	header_resources = [&"scrap", &"parts", &"rare_parts", &"wood", &"cloth"]


func open_with(args: Dictionary) -> void:
	if args.has("facility") and StringName(args.facility) in FACILITIES:
		_facility = StringName(args.facility)
		_mode = _modes()[0][0]
	if args.has("mode") and _has_mode(StringName(args.mode)):
		_mode = StringName(args.mode)
	if args.has("uid"):
		_sel = StringName(args.uid)
	if _detail != null:
		_refresh()


func _build_body(b: Control) -> void:
	# Scene-type screen: only the right part is blurred, the base shows on the left.
	backdrop.anchor_left = 0.55
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.62, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.6)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.anchor_right = 0.55
	add_child(shade)
	move_child(shade, backdrop.get_index() + 1)

	var left := Control.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left.anchor_right = 0.53
	b.add_child(left)
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 12)
	_fac_tabs = HBoxContainer.new()
	_fac_tabs.add_theme_constant_override(&"separation", 8)
	tabs.add_child(_fac_tabs)
	_mode_tabs = HBoxContainer.new()
	_mode_tabs.add_theme_constant_override(&"separation", 4)
	tabs.add_child(_mode_tabs)
	# Dark chip so the tabs read over any base scene.
	var tab_chip := PanelContainer.new()
	tab_chip.theme_type_variation = &"PanelSlate"
	tab_chip.add_child(tabs)
	left.add_child(tab_chip)
	# Place marker (UI_RULES §4 "지점 표지"): dark two-line chip + thin line + white dot.
	var marker := VBoxContainer.new()
	marker.add_theme_constant_override(&"separation", 0)
	marker.position = Vector2(0, 176)
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"PanelSlate"
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override(&"separation", 0)
	_place_sub = MenuScreen.label("", &"LabelDim", 13)
	cv.add_child(_place_sub)
	_place = MenuScreen.label("", &"LabelSection", 20)
	cv.add_child(_place)
	chip.add_child(cv)
	marker.add_child(chip)
	var stem := ColorRect.new()
	stem.color = UiTokens.LINE_STRONG
	stem.custom_minimum_size = Vector2(1.5, 46)
	stem.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	marker.add_child(stem)
	var dot := Panel.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = UiTokens.TEXT
	ds.set_corner_radius_all(5)
	dot.add_theme_stylebox_override(&"panel", ds)
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	marker.add_child(dot)
	left.add_child(marker)

	# Facility slot row along the bottom.
	var sp := MenuScreen.panel("", "")
	var strip_panel: PanelContainer = sp[0]
	var band: HBoxContainer = sp[2]
	_strip_head = band.get_child(0)
	_strip_count = band.get_child(1)
	left.add_child(strip_panel)
	strip_panel.anchor_left = 0.0
	strip_panel.anchor_right = 1.0
	strip_panel.anchor_top = 1.0
	strip_panel.anchor_bottom = 1.0
	strip_panel.offset_top = -204
	strip_panel.offset_bottom = 0
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override(&"separation", 10)
	sc.add_child(_strip)
	(sp[1] as VBoxContainer).add_child(sc)

	# Right: comparison + cream card.
	var rp := MenuScreen.panel("", "")
	var right: PanelContainer = rp[0]
	b.add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	right.anchor_left = 0.565
	var rband: HBoxContainer = rp[2]
	MenuScreen.clear(rband)
	_title_badge = ShapeBadge.new()
	_title_badge.badge_size = 16
	_title_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rband.add_child(_title_badge)
	_title = MenuScreen.label("", &"LabelSection", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rband.add_child(_title)
	_title_sub = MenuScreen.label("", &"LabelDim", 15)
	rband.add_child(_title_sub)
	var dsc := ScrollContainer.new()
	dsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override(&"separation", 10)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dsc.add_child(_detail)
	(rp[1] as VBoxContainer).add_child(dsc)
	var cc := MenuScreen.cream_card(0)
	_card = cc[1]
	_card.add_theme_constant_override(&"separation", 8)
	(rp[1] as VBoxContainer).add_child(cc[0])

	_tip = TooltipCard.new()
	add_child(_tip)
	EventBus.equipment_changed.connect(func(_o: StringName, _s: int) -> void: _refresh.call_deferred())
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not is_visible_in_tree():
		return
	if get_children().any(func(c: Node) -> bool: return c is ConfirmDialog):
		return
	match k.keycode:
		KEY_Q, KEY_E:
			var i := FACILITIES.find(_facility) + (1 if k.keycode == KEY_E else -1)
			_set_facility(FACILITIES[posmod(i, FACILITIES.size())])
		KEY_1, KEY_2, KEY_3, KEY_4:
			var m := _modes()
			var i := int(k.keycode - KEY_1)
			if i < m.size():
				_set_mode(m[i][0])
		KEY_ENTER, KEY_KP_ENTER:
			if _do_button != null and not _do_button.disabled:
				_do_button.pressed.emit()
		_:
			return
	get_viewport().set_input_as_handled()


# ---------------- state ----------------

func _modes() -> Array:
	return ESSENCE_MODES if _facility == EssenceRules.FACILITY else GEAR_MODES


func _has_mode(mode: StringName) -> bool:
	return _modes().any(func(m: Array) -> bool: return m[0] == mode)


func _set_facility(f: StringName) -> void:
	if f == _facility:
		return
	_facility = f
	_mode = _modes()[0][0]
	_reset_pick()
	Audio.play(&"ui_click")
	_refresh()


func _set_mode(m: StringName) -> void:
	if m == _mode:
		return
	_mode = m
	_reset_pick()
	Audio.play(&"ui_click")
	_refresh()


func _reset_pick() -> void:
	_sel = &""
	_target = &""
	_slot = 0
	_essence = &""
	_times = 1
	_family = &""
	_last = ""


func _facility_name(f: StringName = _facility) -> String:
	var def: Variant = BaseDB.get_building(f)
	return String(def.display_name) if def != null and String(def.display_name) != "" else String(f)


func _refresh() -> void:
	_fill_tabs()
	_fill_place()
	_fill_strip()
	_fill_detail()


# ---------------- left side ----------------

func _fill_tabs() -> void:
	MenuScreen.clear(_fac_tabs)
	for f: StringName in FACILITIES:
		var lv := Colony.facility_level(f)
		var t := MenuScreen.button("%s  %s" % [_facility_name(f), ("Lv %d" % lv) if lv > 0 else "없음"], &"TabText")
		t.toggle_mode = true
		t.button_pressed = f == _facility
		if lv <= 0 and f != _facility:
			t.modulate.a = 0.6
		t.pressed.connect(_set_facility.bind(f))
		_fac_tabs.add_child(t)
	MenuScreen.clear(_mode_tabs)
	var i := 1
	for m: Array in _modes():
		var t := MenuScreen.button("%d  %s" % [i, m[1]], &"TabText")
		t.toggle_mode = true
		t.button_pressed = m[0] == _mode
		t.add_theme_font_size_override(&"font_size", 17)
		t.pressed.connect(_set_mode.bind(m[0]))
		_mode_tabs.add_child(t)
		i += 1
	set_subtitle(_facility_name())


func _fill_place() -> void:
	var lv := Colony.facility_level(_facility)
	_place_sub.text = "Lv %d" % lv if lv > 0 else "아직 짓지 않았어요"
	var names: PackedStringArray = []
	for id in Colony.facility_workers(_facility):
		names.append(_resident_name(id))
	_place.text = _facility_name() + ("  ·  " + ", ".join(names) if not names.is_empty() else "  ·  담당 없음")


func _fill_strip() -> void:
	MenuScreen.clear(_strip)
	_strip_head.text = STRIP_HEADS.get(_mode, "")
	var ids := _strip_ids()
	_strip_count.text = str(ids.size())
	if _sel == &"" or not _sel in ids:
		_sel = ids[0] if not ids.is_empty() else &""
	for id: StringName in ids:
		_strip.add_child(_strip_cell(id))
	if ids.is_empty():
		var msg := {&"craft": "만들 수 있는 것이 없어요.", &"refine": "정수가 없어요.",
			&"disassemble": "무기고에 각인된 장비가 없어요.", &"transfer": "강화된 장비가 없어요."}
		_strip.add_child(MenuScreen.label(String(msg.get(_mode, "여기서 다룰 장비가 없어요.")), &"LabelDim", 15))


## What the bottom row lists for the current mode.
func _strip_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	match _mode:
		&"craft":
			# Unlocked first, then the ones waiting for a blueprint, then the residents' daily work.
			var unlocked: Array[StringName] = []
			var locked: Array[StringName] = []
			for id in Armory.list_recipes(_facility, 0):
				if Armory.preview_craft(id).reason == &"blueprint":
					locked.append(id)
				else:
					unlocked.append(id)
			out.append_array(unlocked)
			out.append_array(locked)
			out.append_array(Armory.list_recipes(_facility, 1))
		&"refine":
			for id in _essences_ordered():
				if Economy.get_amount(id) > 0:
					out.append(id)
		_:
			for uid in _owned_items():
				var it := Armory.get_item(uid)
				var def := Armory.get_def(it.def_id)
				match _mode:
					&"upgrade", &"repair":
						if UpgradeRules.facility_for_slot(def.slot) == _facility:
							out.append(uid)
					&"transfer":
						if UpgradeRules.facility_for_slot(def.slot) == _facility and it.upgrade_level > 0:
							out.append(uid)
					&"engrave":
						if Armory.is_engravable(uid):
							out.append(uid)
					&"disassemble":
						if it.owner == Armory.STORAGE_ID and Armory.get_engravings(uid).any(
								func(e: StringName) -> bool: return e != &""):
							out.append(uid)
	if _mode == &"transfer":
		# Highest level first: that is the one worth passing on.
		out.sort_custom(func(a: StringName, b: StringName) -> bool:
			return Armory.get_item(a).upgrade_level > Armory.get_item(b).upgrade_level)
	return out


## Gear at the base: what the player and the residents wear, then storage. Lost gear is left out.
func _owned_items() -> Array[StringName]:
	var out: Array[StringName] = []
	var owners: Array = [Armory.PLAYER_ID]
	owners.append_array(Colony.active_resident_ids())
	for o: StringName in owners:
		var eq: Dictionary = Armory.list_equipped(o)
		for s: int in eq:
			if eq[s] != &"" and not eq[s] in out:
				out.append(eq[s])
	for uid in Armory.list_storage(-1):
		if not uid in out:
			out.append(uid)
	return out


func _strip_cell(id: StringName) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 3)
	var text := ""
	var rarity := -1
	var element := -1
	var caption := ""
	var corner := ""
	var dim := false
	var bar := -1.0
	match _mode:
		&"craft":
			var r := Armory.get_recipe(id)
			text = _output_name(r.output_id)
			if r.output_qty > 1:
				corner = "×%d" % r.output_qty
			var p := Armory.preview_craft(id)
			if r.by_worker:
				caption = "주민 작업"
				dim = true
			elif p.reason == &"blueprint":
				caption = "설계도 없음"
				dim = true
			else:
				caption = "Lv %d" % r.facility_level
		&"refine":
			var e := EssenceRules.get_essence(id)
			text = e.name
			element = int(e.element)
			corner = "×%d" % Economy.get_amount(id)
		_:
			var it := Armory.get_item(id)
			var st := Armory.get_item_stats(id)
			text = String(st.get("display_name", Armory.get_def(it.def_id).name))
			rarity = int(it.rarity)
			if it.upgrade_level > 0:
				corner = "+%d" % it.upgrade_level
			caption = _owner_name(it.owner)
			if _mode == &"repair":
				bar = it.durability / maxf(Armory.get_def(it.def_id).durability_max, 1.0)
				caption = "%d/%d" % [roundi(it.durability), roundi(Armory.get_def(it.def_id).durability_max)]
			if _mode == &"engrave":
				element = int(st.get("element", 0))
				if element == 0:
					element = -1
	var b := Button.new()
	b.custom_minimum_size = Vector2(108, 92)
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override(&"font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.bg_color = Color(0.33, 0.43, 0.53, 0.45)
	if rarity > 0:
		sb.bg_color = Color(UiTokens.rarity_color(rarity), 0.38)
	var hb := sb.duplicate() as StyleBoxFlat
	hb.border_color = UiTokens.LINE_STRONG
	hb.set_border_width_all(2)
	if id == _sel:
		sb = sb.duplicate()
		sb.border_color = UiTokens.ACCENT
		sb.set_border_width_all(3)
		hb = sb
	for s in [&"normal", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_stylebox_override(&"hover", hb)
	b.add_theme_stylebox_override(&"pressed", hb)
	if dim:
		b.modulate.a = 0.6
	if rarity >= 0 or element >= 0:
		var badge := ShapeBadge.new()
		badge.kind = ShapeBadge.Kind.ELEMENT if element >= 0 else ShapeBadge.Kind.RARITY
		badge.value = element if element >= 0 else rarity
		badge.badge_size = 14
		badge.position = Vector2(7, 7)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(badge)
	if corner != "":
		var c := MenuScreen.label(corner, &"LabelNumber", 15)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(c)
		c.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
		c.position += Vector2(-8, 4)
	if bar >= 0.0:
		var sbar := MenuScreen.bar(bar, UiTokens.DANGER if bar < 0.3 else UiTokens.TEXT, 92, 4)
		sbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sbar)
		sbar.position = Vector2(8, 82)
	b.pressed.connect(func() -> void:
		_sel = id
		_target = &""
		_slot = 0
		_essence = &""
		_times = 1
		_family = &""
		_last = ""
		Audio.play(&"ui_click")
		_refresh())
	if _mode not in [&"craft", &"refine"]:
		b.mouse_entered.connect(func() -> void:
			_tip.show_info(ItemInfo.for_item(id).tooltip, b.global_position + Vector2(0, -12) - Vector2(0, 330)))
		b.mouse_exited.connect(func() -> void: _tip.visible = false)
	v.add_child(b)
	var cap := MenuScreen.label(caption, &"LabelHud", 12)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.custom_minimum_size = Vector2(108, 0)
	cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(cap)
	return v


# ---------------- right side ----------------

func _fill_detail() -> void:
	MenuScreen.clear(_detail)
	MenuScreen.clear(_card)
	_do_button = null
	_title_badge.visible = false
	_title_sub.text = ""
	if _sel == &"":
		_title.text = STRIP_HEADS.get(_mode, "")
		_card_reason(&"no_recipe" if _mode == &"craft" else (&"unknown_essence" if _mode == &"refine" else &"no_item"))
		_card_worker()
		return
	match _mode:
		&"craft":
			_detail_craft()
		&"upgrade":
			_detail_upgrade()
		&"transfer":
			_detail_transfer()
		&"repair":
			_detail_repair()
		&"engrave":
			_detail_engrave()
		&"refine":
			_detail_refine()
		&"disassemble":
			_detail_disassemble()


func _title_item(uid: StringName) -> void:
	var it := Armory.get_item(uid)
	var st := Armory.get_item_stats(uid)
	_title.text = String(st.get("display_name", "")) + ("  +%d" % it.upgrade_level if it.upgrade_level > 0 else "")
	_title_badge.kind = ShapeBadge.Kind.RARITY
	_title_badge.value = int(it.rarity)
	_title_badge.visible = true
	_title_sub.text = "%s · %s" % [UiTokens.RARITY_NAMES[clampi(int(it.rarity), 0, 4)], _owner_name(it.owner)]


func _detail_craft() -> void:
	var r := Armory.get_recipe(_sel)
	var p := Armory.preview_craft(_sel)
	_title.text = _output_name(r.output_id) + ("  ×%d" % r.output_qty if r.output_qty > 1 else "")
	var def := Armory.get_def(r.output_id)
	if def != null:
		_title_sub.text = ItemInfo.SLOT_NAMES[clampi(int(def.slot), 0, 6)]
		_section("기본 성능")
		_rows(ItemInfo.compare_rows(def.base_stats, {}))
		if p.get("equipment", false):
			var line := _info_line("고급 이상이 나올 확률", "%d%%" % roundi(float(p.get("higher_chance", 0.0)) * 100.0))
			_detail.add_child(line)
			_detail.add_child(_dim("등급은 담당 주민의 손재주로 정해져요. 만든 장비는 무기고로 들어가요."))
	else:
		_title_sub.text = "창고로"
		_detail.add_child(_dim("%s ×%d을(를) 만들어 창고에 넣어요." % [_output_name(r.output_id), r.output_qty]))
	if r.blueprint_required:
		_detail.add_child(_info_line("설계도", "있음" if p.reason != &"blueprint" else "없음 — 루팅·보스·퀘스트에서 얻어요",
			p.reason == &"blueprint"))
	if r.by_worker:
		_card_reason(&"worker_only")
		_card_worker()
		return
	_card_cost(p)
	_card_reason(p.reason, r.facility_level)
	_card_worker(p)
	_card_action("제작", p.ok, func() -> void:
		var out := Armory.craft(_sel)
		if out.ok:
			if StringName(out.get("uid", &"")) != &"":
				var nm := String(Armory.get_item_stats(out.uid).get("display_name", ""))
				_done("%s (%s)을(를) 만들었어요. 무기고에 들어갔어요." % [nm, UiTokens.RARITY_NAMES[clampi(int(out.rarity), 0, 4)]])
			else:
				_done("%s ×%d을(를) 만들었어요." % [_output_name(r.output_id), r.output_qty])
		else:
			_fail(out.reason))


func _detail_upgrade() -> void:
	_title_item(_sel)
	var p := Armory.preview_upgrade(_sel, {"family_mat": _family} if _family != &"" else {})
	_section("강화 +%d → +%d" % [int(p.get("current_level", 0)), mini(int(p.get("next_level", 0)), Armory.MAX_UPGRADE)])
	_rows(ItemInfo.compare_rows(p.stats, p.stats_after))
	_detail.add_child(_dim("%s Lv %d에서는 +%d까지 올릴 수 있어요. 실패는 없어요." % [_facility_name(),
		int(p.get("facility_level", 0)), int(p.get("max_level", 0))]))
	var options: Array = p.get("family_options", [])
	if options.size() > 1:
		_card.add_child(_on_cream("계열 재료", &"LabelOnCreamDim", 13))
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 6)
		for id: StringName in options:
			var bt := MenuScreen.button(MenuScreen.resource_name(id), &"ButtonSoft" if id != p.family_mat else &"ButtonPrimary")
			bt.add_theme_font_size_override(&"font_size", 14)
			bt.pressed.connect(func() -> void:
				_family = id
				_fill_detail())
			h.add_child(bt)
		_card.add_child(h)
	_card_cost(p)
	var reason_arg := 0
	if p.reason == &"facility_level":
		_card_line("⚠  %s Lv %d은(는) +%d까지예요. 시설을 올려 주세요." % [_facility_name(), int(p.facility_level),
			int(p.max_level)], UiTokens.DANGER)
	else:
		_card_reason(p.reason, reason_arg)
	_card_worker(p)
	_card_action("강화  +%d" % mini(int(p.get("next_level", 0)), Armory.MAX_UPGRADE), p.ok, func() -> void:
		if Armory.upgrade(_sel, {"family_mat": p.family_mat} if p.family_mat != &"" else {}):
			_done("+%d이 되었어요." % int(p.next_level))
		else:
			_fail(&"cost"))


func _detail_transfer() -> void:
	_title_item(_sel)
	var from := Armory.get_item(_sel)
	var slot := int(Armory.get_def(from.def_id).slot)
	_section("받을 장비 (같은 부위)")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	var any := false
	for uid in _owned_items():
		if uid == _sel:
			continue
		var it := Armory.get_item(uid)
		if int(Armory.get_def(it.def_id).slot) != slot:
			continue
		any = true
		# Default target: the first one that actually gains a level.
		if _target == &"" and Armory.preview_transfer(_sel, uid).reason != &"no_gain":
			_target = uid
		var st := Armory.get_item_stats(uid)
		var label := "%s%s · %s" % [String(st.get("display_name", "")), "  +%d" % it.upgrade_level if it.upgrade_level > 0 else "",
			_owner_name(it.owner)]
		var pick := _pick_button(label, uid == _target, ShapeBadge.Kind.RARITY, int(it.rarity), func() -> void:
			_target = uid
			_fill_detail())
		pick.set_meta(&"uid", uid)
		grid.add_child(pick)
	if _target == &"" and grid.get_child_count() > 0:
		_target = StringName(grid.get_child(0).get_meta(&"uid", &""))
		_fill_detail()
		return
	if not any:
		_detail.add_child(_dim("같은 부위 장비가 하나뿐이에요."))
	else:
		_detail.add_child(grid)
	if _target == &"":
		_card_reason(&"no_item")
		_card_worker()
		return
	var p := Armory.preview_transfer(_sel, _target)
	_section("단계 변화")
	_rows([["넘기는 장비", "+%d" % int(p.get("from_level", 0)), "+0", "dn"],
		["받는 장비", "+%d" % int(p.get("to_level", 0)), "+%d" % int(p.get("result_level", 0)),
			"up" if int(p.get("result_level", 0)) > int(p.get("to_level", 0)) else ""]])
	_detail.add_child(_dim("옮기면 %d단계가 줄어들어요. 넘기는 장비는 +0이 돼요." % UpgradeRules.TRANSFER_LOSS))
	_card_cost(p)
	_card_reason(p.reason)
	_card_worker(p)
	_card_action("옮기기", p.ok, func() -> void:
		var to_name := String(Armory.get_item_stats(_target).get("display_name", ""))
		ConfirmDialog.ask(self, "강화를 %s(으)로 옮길까요?" % to_name,
			"%s은(는) +0이 되고, %s은(는) +%d이 돼요." % [String(Armory.get_item_stats(_sel).get("display_name", "")),
				to_name, int(p.result_level)], "옮기기", func() -> void:
				if Armory.transfer_upgrade(_sel, _target):
					var t := _target
					_mode = &"upgrade"
					_sel = t
					_target = &""
					_done("%s이(가) +%d이 되었어요." % [to_name, int(p.result_level)])
				else:
					_fail(&"cost")))


func _detail_repair() -> void:
	_title_item(_sel)
	var p := Armory.preview_repair(_sel)
	var it := Armory.get_item(_sel)
	var max_d := Armory.get_def(it.def_id).durability_max
	var before := Armory.get_item_stats(_sel)
	var after := before.duplicate()
	after["durability"] = max_d
	_section("수리")
	_rows([["내구도", "%d/%d" % [roundi(it.durability), roundi(max_d)], "%d/%d" % [roundi(max_d), roundi(max_d)],
		"up" if p.lost > 0.0 else ""]])
	if bool(before.get("broken", false)):
		_rows([["성능", "50% (망가짐)", "100%", "up"]])
		_detail.add_child(_dim("내구도가 0이면 성능이 절반으로 떨어져요. 고치면 원래대로 돌아와요."))
	# Auto repair toggle (design 05 "자동 수리", saved by Armory).
	var auto := CheckButton.new()
	auto.text = "자동 수리 — 저녁 정산 때 담당 주민이 고쳐요"
	auto.button_pressed = Armory.auto_repair_enabled
	auto.add_theme_font_size_override(&"font_size", 15)
	auto.toggled.connect(func(on: bool) -> void: Armory.set_auto_repair(on))
	_detail.add_child(auto)
	_card_cost(p)
	_card_reason(p.reason)
	_card_worker(p)
	_card_action("수리", p.ok, func() -> void:
		if Armory.repair(_sel):
			_done("다 고쳤어요.")
		else:
			_fail(&"cost"))


func _detail_engrave() -> void:
	_title_item(_sel)
	var slots := Armory.get_engravings(_sel)
	_section("정수 칸  %d" % slots.size())
	if slots.is_empty():
		var po := Armory.preview_open_slot(_sel)
		if po.reason in [&"not_weapon", &"has_slots", &"already_open"]:
			_detail.add_child(_dim(REASONS.get(po.reason, "") + " 장신구는 고급 등급부터 칸이 있어요."))
			_card_reason(&"no_slots")
			_card_worker()
			return
		_detail.add_child(_dim("일반 등급 무기는 정수 칸이 없어요. 칸을 하나 열면 마법 무기로 키울 수 있어요."))
		_rows(ItemInfo.compare_rows(po.stats, po.stats_after) if not po.stats_after.is_empty() else [])
		_rows([["정수 칸", "0", "%d" % EssenceRules.OPEN_SLOT_COUNT, "up"]])
		_card_cost(po)
		_card_reason(po.reason)
		_card_worker(po)
		_card_action("슬롯 열기", po.ok, func() -> void:
			if Armory.open_slot(_sel):
				_done("정수 칸이 생겼어요.")
			else:
				_fail(&"cost"))
		return
	_slot = clampi(_slot, 0, slots.size() - 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	for i in slots.size():
		var e: EssenceDef = EssenceRules.get_essence(slots[i]) if slots[i] != &"" else null
		var label := "%d번 칸 · %s" % [i + 1, e.name if e != null else "비어 있음"]
		if i == 0 and slots.size() > 1:
			label += " (주 속성)"
		row.add_child(_pick_button(label, i == _slot, ShapeBadge.Kind.ELEMENT, int(e.element) if e != null else 0,
			func() -> void:
				_slot = i
				_essence = &""
				_fill_detail()))
	_detail.add_child(row)
	_section("넣을 정수")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	for id in _essences_ordered():
		var e := EssenceRules.get_essence(id)
		var n := Economy.get_amount(id)
		var bt := _pick_button("%s  ×%d" % [e.name, n], id == _essence, ShapeBadge.Kind.ELEMENT, int(e.element), func() -> void:
			_essence = id
			_fill_detail())
		if n <= 0:
			bt.modulate.a = 0.5
		grid.add_child(bt)
	_detail.add_child(grid)
	var current := slots[_slot]
	if _essence == &"":
		if current != &"":
			var pr := Armory.preview_remove_engraving(_sel, _slot)
			_section("지금 정수 효과")
			_effects(pr.stats)
			_card_reason(&"unknown_essence")
			_card_worker(pr)
			_card_remove(pr)
		else:
			_card_reason(&"unknown_essence")
			_card_worker()
		return
	var p := Armory.preview_engrave(_sel, _essence, _slot)
	_section("각인 전후")
	_rows(ItemInfo.compare_rows(p.stats, p.stats_after), true)
	if not p.stats_after.is_empty():
		_section("각인 후 정수 효과")
		_effects(p.stats_after)
	var combo: Variant = p.stats_after.get("combo")
	if combo is Dictionary:
		var cd: ComboDef = EssenceRules.combos().get(StringName(combo.get("id", &"")))
		var desc := String(cd.description) if cd != null else ""
		_detail.add_child(_info_line("조합 마법  " + String(combo.get("name", "")),
			"적중 시 %d%%" % roundi(float(combo.get("proc_rate", 0.0)) * 100.0)))
		if desc != "":
			_detail.add_child(_dim(desc))
	_card_cost(p)
	_card_reason(p.reason)
	if StringName(p.get("replaces", &"")) != &"" and p.reason != &"same_essence":
		_card_line("⚠  %s이(가) 사라지고 새 정수로 바뀌어요." % EssenceRules.get_essence(p.replaces).name, UiTokens.WARN.darkened(0.35))
	_card_worker(p)
	_card_action("각인", p.ok, func() -> void:
		var go := func() -> void:
			if Armory.engrave(_sel, _essence, _slot):
				_essence = &""
				_done("%s이(가) 되었어요." % String(Armory.get_item_stats(_sel).get("display_name", "")))
			else:
				_fail(&"cost")
		if StringName(p.replaces) != &"":
			ConfirmDialog.ask(self, "%s을(를) 덮어쓸까요?" % EssenceRules.get_essence(p.replaces).name,
				"기존 정수는 돌려받지 못해요.", "덮어쓰기", go)
		else:
			go.call())
	if current != &"":
		_card_remove(Armory.preview_remove_engraving(_sel, _slot))


func _detail_refine() -> void:
	var e := EssenceRules.get_essence(_sel)
	_title.text = e.name
	_title_badge.kind = ShapeBadge.Kind.ELEMENT
	_title_badge.value = int(e.element)
	_title_badge.visible = true
	_title_sub.text = "보유 %d" % Economy.get_amount(_sel)
	var p := Armory.preview_refine(_sel, _times)
	_section("정제")
	var out_name := EssenceRules.get_essence(p.output_id).name if p.output_id != &"" else "—"
	var take := "%s ×%d" % [e.name, int(p.input_qty) * _times]
	var give := "%s ×%d" % [out_name, _times] if p.output_id != &"" else "—"
	_rows([["넣는 정수", take, take, ""], ["나오는 정수", give, give, ""]])
	_detail.add_child(_dim("같은 속성 %d개를 한 단계 높은 정수 1개로 바꿔요." % int(p.input_qty)))
	if bool(p.get("mark", false)):
		_detail.add_child(_info_line("마물 흔적이 남은 주민이 함께해요", "정수 1개 덜 씀"))
	var step := HBoxContainer.new()
	step.add_theme_constant_override(&"separation", 10)
	step.add_child(MenuScreen.label("횟수", &"LabelHud", 16))
	var most := maxi(Economy.get_amount(_sel) / maxi(int(p.input_qty), 1), 1)
	var minus := MenuScreen.button("−", &"ButtonCancel")
	minus.disabled = _times <= 1
	minus.pressed.connect(func() -> void:
		_times = maxi(_times - 1, 1)
		_fill_detail())
	step.add_child(minus)
	step.add_child(MenuScreen.label(str(_times), &"LabelNumber", 22))
	var plus := MenuScreen.button("+", &"ButtonCancel")
	plus.disabled = _times >= most
	plus.pressed.connect(func() -> void:
		_times = mini(_times + 1, most)
		_fill_detail())
	step.add_child(plus)
	_detail.add_child(step)
	_card_cost(p)
	if p.reason == &"facility_level":
		_card_line("⚠  정제는 %s Lv %d부터 할 수 있어요." % [_facility_name(), EssenceRules.REFINE_FACILITY_LEVEL], UiTokens.DANGER)
	else:
		_card_reason(p.reason)
	_card_worker(p)
	_card_action("정제  ×%d" % _times, p.ok, func() -> void:
		if Armory.refine(_sel, _times):
			_done("%s %d개를 얻었어요." % [out_name, _times])
		else:
			_fail(&"cost"))


func _detail_disassemble() -> void:
	_title_item(_sel)
	var p := Armory.preview_disassemble(_sel)
	_section("돌려받을 수 있는 정수")
	for id: StringName in p.get("essences", []):
		var e := EssenceRules.get_essence(id)
		_detail.add_child(_pick_button(e.name, false, ShapeBadge.Kind.ELEMENT, int(e.element), Callable()))
	_detail.add_child(_dim("장비는 사라지고, 정수는 하나마다 %d%% 확률로 돌아와요." % roundi(float(p.return_chance) * 100.0)))
	_card_reason(p.reason)
	_card_worker(p)
	_card_action("분해", p.ok, func() -> void:
		var nm := String(Armory.get_item_stats(_sel).get("display_name", ""))
		ConfirmDialog.ask(self, "%s을(를) 분해할까요?" % nm, "장비는 사라지고 되돌릴 수 없어요.", "분해", func() -> void:
			var out := Armory.disassemble(_sel)
			if out.ok:
				var got: PackedStringArray = []
				for id: StringName in out.returned:
					got.append("%s ×%d" % [EssenceRules.get_essence(id).name, int(out.returned[id])])
				_sel = &""
				_done("분해했어요. " + ("돌려받은 정수: " + ", ".join(got) if not got.is_empty() else "돌아온 정수가 없어요."))
			else:
				_fail(out.reason)))


# ---------------- card ----------------

func _card_cost(p: Dictionary) -> void:
	var cost: Dictionary = p.get("cost", {})
	if cost.is_empty():
		return
	var head := HBoxContainer.new()
	head.add_child(_on_cream("필요 재료", &"LabelOnCream", 17, true))
	if bool(p.get("discount", false)):
		var d := _on_cream("  손재주 할인 −%d%%" % UpgradeRules.DEX_DISCOUNT_PCT, &"LabelOnCreamDim", 13)
		head.add_child(d)
	_card.add_child(head)
	var missing: Dictionary = p.get("missing", {})
	for id: StringName in cost:
		var h := HBoxContainer.new()
		var nm := _on_cream(_res_name(id), &"LabelOnCream", 15)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		if missing.has(id):
			var m := _on_cream("부족 %d  " % int(missing[id]), &"LabelOnCream", 14, true)
			m.add_theme_color_override(&"font_color", UiTokens.DANGER)
			h.add_child(m)
		var have := _on_cream("보유 %d" % Economy.get_amount(id), &"LabelOnCreamDim", 13)
		have.custom_minimum_size = Vector2(84, 0)
		have.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(have)
		var need := _on_cream("×%d" % int(cost[id]), &"LabelOnCream", 16, true)
		need.custom_minimum_size = Vector2(52, 0)
		need.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if missing.has(id):
			need.add_theme_color_override(&"font_color", UiTokens.DANGER)
		h.add_child(need)
		_card.add_child(h)
	var gain: Dictionary = p.get("gain", {})
	for id: StringName in gain:
		var h := HBoxContainer.new()
		var nm := _on_cream("얻는 것  " + _res_name(id), &"LabelOnCream", 15)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var v := _on_cream("+%d" % int(gain[id]), &"LabelOnCream", 15, true)
		v.add_theme_color_override(&"font_color", Color("2f8f3a"))
		h.add_child(v)
		_card.add_child(h)
	_card_divider()


func _card_reason(reason: StringName, level_needed := 0) -> void:
	if not _last.is_empty():
		_card_line("✓  " + _last, Color("2f8f3a"))
	if reason == &"" or not REASONS.has(reason):
		return
	var text := String(REASONS[reason])
	if reason == &"no_facility":
		text = text % _facility_name()
	elif reason == &"facility_level":
		text = "%s Lv %d이(가) 필요해요." % [_facility_name(), level_needed] if level_needed > 0 else text % _facility_name()
	_card_line("⚠  " + text, UiTokens.DANGER)


func _card_line(text: String, color: Color) -> void:
	var l := _on_cream(text, &"LabelOnCream", 14, true)
	l.add_theme_color_override(&"font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(l)


## Who works here (design 05/06: a worker must be assigned). Facility level and dexterity come from
## the preview when there is one; names from Colony.
func _card_worker(p: Dictionary = {}) -> void:
	var foot := PanelContainer.new()
	foot.theme_type_variation = &"CardCreamFoot"
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	foot.add_child(h)
	var ids := Colony.facility_workers(_facility)
	var who: PackedStringArray = []
	for id in ids:
		var r := Colony.get_resident(id)
		var dex := int((r.get("stats", {}) as Dictionary).get(&"dex", 0))
		who.append("%s (손재주 %d)" % [_resident_name(id), dex] if _facility != EssenceRules.FACILITY else _resident_name(id))
	var l := _on_cream("담당  " + (", ".join(who) if not who.is_empty() else "없음"), &"LabelOnCream", 14, true)
	if who.is_empty():
		l.add_theme_color_override(&"font_color", UiTokens.DANGER)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	var lv := int(p.get("facility_level", Colony.facility_level(_facility)))
	h.add_child(_on_cream("%s Lv %d" % [_facility_name(), lv] if lv > 0 else "%s 없음" % _facility_name(), &"LabelOnCreamDim", 13))
	_card.add_child(foot)


func _card_action(text: String, ok: bool, on_do: Callable) -> void:
	var b := MenuScreen.button(text, &"ButtonPrimary" if ok else &"ButtonCancel")
	b.disabled = not ok
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_size_override(&"font_size", 19)
	b.pressed.connect(on_do)
	_card.add_child(b)
	_do_button = b


func _card_remove(p: Dictionary) -> void:
	var b := MenuScreen.button("이 칸 비우기", &"ButtonSecondary")
	b.disabled = not p.ok
	b.pressed.connect(func() -> void:
		var nm := EssenceRules.get_essence(p.removed).name
		ConfirmDialog.ask(self, "%s을(를) 뺄까요?" % nm, "뺀 정수는 사라져요.", "빼기", func() -> void:
			if Armory.remove_engraving(_sel, _slot):
				_done("%s을(를) 뺐어요." % nm)
			else:
				_fail(p.reason)))
	_card.add_child(b)


func _card_divider() -> void:
	var line := ColorRect.new()
	line.color = Color(0, 0, 0, 0.1)
	line.custom_minimum_size = Vector2(0, 1)
	_card.add_child(line)


func _done(text: String) -> void:
	_last = text
	Audio.play(&"ui_confirm")
	EventBus.notification_posted.emit(text, &"info")
	_refresh()


func _fail(reason: StringName) -> void:
	Audio.play(&"ui_error")
	_last = ""
	_refresh()
	if REASONS.has(reason) and reason != &"no_facility":
		EventBus.notification_posted.emit(String(REASONS[reason]), &"warn")


# ---------------- small builders ----------------

func _section(text: String) -> void:
	var l := MenuScreen.label(text, &"LabelHud", 17)
	l.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	_detail.add_child(l)


## Comparison rows in fixed columns: label | before | → | after (▲ better / ▼ worse: arrow + colour,
## never colour alone). Unchanged rows show the value in the after column only.
## changed_only: skip rows whose value stays the same (engraving mostly changes effects, not numbers).
func _rows(rows: Array, changed_only := false) -> void:
	for r: Array in rows:
		var mark := String(r[3]) if r.size() > 3 else ""
		var changed := String(r[1]) != String(r[2]) or mark != ""
		if changed_only and not changed:
			continue
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 10)
		var a := MenuScreen.label(String(r[0]), &"LabelHud", 16)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		var before := MenuScreen.label(String(r[1]) if changed else "", &"LabelNumber", 18)
		before.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
		before.custom_minimum_size = Vector2(170, 0)
		before.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(before)
		var arrow := MenuScreen.label("→" if changed else "", &"LabelDim", 16)
		arrow.custom_minimum_size = Vector2(22, 0)
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(arrow)
		var after := MenuScreen.label(String(r[2]) + ("  ▲" if mark == "up" else ("  ▼" if mark == "dn" else "")),
			&"LabelNumber", 18)
		after.custom_minimum_size = Vector2(190, 0)
		after.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if mark == "up":
			after.add_theme_color_override(&"font_color", UiTokens.GOOD)
		elif mark == "dn":
			after.add_theme_color_override(&"font_color", UiTokens.DANGER)
		h.add_child(after)
		_detail.add_child(h)
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.08)
		line.custom_minimum_size = Vector2(0, 1)
		_detail.add_child(line)


func _info_line(label: String, value: String, warn := false) -> Control:
	var h := HBoxContainer.new()
	var a := MenuScreen.label(label, &"LabelHud", 15)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var v := MenuScreen.label(value, &"LabelHud", 15)
	v.add_theme_color_override(&"font_color", UiTokens.WARN if warn else UiTokens.ACCENT)
	h.add_child(v)
	return h


func _dim(text: String) -> Label:
	var l := MenuScreen.label(text, &"LabelDim", 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _on_cream(text: String, variation: StringName, size_px: int, bold := false) -> Label:
	var l := MenuScreen.label(text, variation, size_px)
	if bold:
		l.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	return l


## Toggle-looking pick button with a shape badge (slot, essence, target item).
func _pick_button(text: String, selected: bool, kind: ShapeBadge.Kind, value: int, on_pick: Callable) -> Button:
	var b := Button.new()
	b.text = "      " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override(&"font_size", 15)
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTokens.SLATE_2
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	sb.border_color = UiTokens.ACCENT if selected else Color(1, 1, 1, 0.16)
	sb.set_border_width_all(2 if selected else 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	var hb := sb.duplicate() as StyleBoxFlat
	if not selected:
		hb.border_color = UiTokens.LINE_STRONG
	for s in [&"normal", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_stylebox_override(&"hover", hb)
	b.add_theme_stylebox_override(&"pressed", hb)
	var badge := ShapeBadge.new()
	badge.kind = kind
	badge.value = value
	badge.badge_size = 16
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(12, 13)
	b.add_child(badge)
	if on_pick.is_valid():
		b.pressed.connect(func() -> void:
			Audio.play(&"ui_click")
			on_pick.call())
	else:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## Essence effects, one line each with the element badge.
func _effects(stats: Dictionary) -> void:
	var lines := ItemInfo.essence_lines(stats)
	if lines.is_empty():
		_detail.add_child(_dim("정수 효과가 없어요."))
	for line: Array in lines:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 10)
		var badge := ShapeBadge.new()
		badge.kind = ShapeBadge.Kind.ELEMENT
		badge.value = int(line[0])
		badge.badge_size = 16
		badge.show_label = true
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(badge)
		var l := MenuScreen.label(String(line[1]), &"LabelHud", 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		_detail.add_child(h)


## Essences by element (풀 돌 물 번개), then grade (하급 중급 상급): one row per element in a 3-column grid.
func _essences_ordered() -> Array[StringName]:
	var out := EssenceRules.list_essences()
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ea := EssenceRules.get_essence(a)
		var eb := EssenceRules.get_essence(b)
		return ea.element * 3 + ea.grade < eb.element * 3 + eb.grade)
	return out


func _output_name(id: StringName) -> String:
	var def := Armory.get_def(id)
	return def.name if def != null else MenuScreen.resource_name(id)


func _res_name(id: StringName) -> String:
	if EssenceRules.is_essence(id):
		return EssenceRules.get_essence(id).name
	return MenuScreen.resource_name(id)


func _owner_name(owner: StringName) -> String:
	match owner:
		Armory.PLAYER_ID:
			return "내가 착용"
		Armory.STORAGE_ID:
			return "무기고"
		Armory.LOST_ID:
			return "유실물"
		Armory.BAG_ID:
			return "가방"
	return _resident_name(owner) + " 착용"


func _resident_name(id: StringName) -> String:
	return String(Colony.get_resident(id).get("name", id))
