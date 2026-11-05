class_name FieldHud
extends Control
## Field HUD (D-04). Owner: Lane D. Rules: ui/UI_RULES.md §4 "필드 HUD" (ARC Raiders base, no panels).
## No compass: the quarter view + minimap already show direction (design 14 has none).
## Design: docs/design/14-ui-controls-accessibility.md "필드 HUD".
##
## The HUD computes no game rules. It draws a state Dictionary that it pulls every frame from the
## first node in group "player" that has `hud_state() -> Dictionary` (Lane B, B-03/B-06/B-13).
## Until that exists, ui/_preview/ feeds fake state through set_state(). Keys (all optional):
##   hp, hp_max: float            armor: 0..1     armor_segments: int (4)
##   stamina: 0..1 (bar shows only while < 1)    xp: 0..1   level: int
##   player_name: String
##   weapons: [{name, ammo, reserve, melee: bool, rarity: int}]   weapon_index: int
##   reloading: bool
##   consumables: [{name, count, rarity}] (keys 3..6, null = empty)
##   skills: [{key: "Q", left: sec, max: sec}]   mana: 0..1
##   companions: [{name, hp: 0..1, command: String}]
##   objectives: [{text, progress: String, main: bool}]
##   heading_deg: float (minimap arrow when minimap.heading is missing)
##   minimap: {points: [{pos: Vector2, kind}], heading: float}
##   dusk_left_sec: float  (else counted down locally from sortie_started)
##   hold: {label: String, progress: 0..1} or {} ; prompt: {key, label} or {}
## Events it listens to on its own: sortie_started (region card), monster_killed / rescue_completed /
## extraction_completed / notification_posted (reward feed, hint card).

const FEED_MAX := 4
const FEED_SEC := 2.6
const REGION_SEC := 3.8
const DUSK_WARN_SEC := 180.0

var state: Dictionary = {}
var auto_bind := true

var _minimap: HudMinimap
var _timer: Label
var _timer_cap: Label
var _timer_icon: Label
var _objectives: VBoxContainer
var _feed: VBoxContainer
var _hint: PanelContainer
var _hint_title: Label
var _hint_body: Label
var _hint_key: KeyChip
var _hint_key_label: Label
var _region: Control
var _region_l1: Label
var _region_l2: Label
var _mates: VBoxContainer
var _name: Label
var _armor: SegBar
var _hp: SegBar
var _xp: SegBar
var _level: Label
var _stamina: SegBar
var _mana: SegBar
var _skills: HBoxContainer
var _quick: HBoxContainer
var _weapons: VBoxContainer
var _hold: VBoxContainer
var _hold_label: Label
var _hold_bar: SegBar
var _prompt: HBoxContainer
var _prompt_key: KeyChip
var _prompt_label: Label
var _dusk_local := -1.0
var _region_left := 0.0
var _shown_sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.sortie_started.connect(_on_sortie_started)
	EventBus.monster_killed.connect(func(_id: StringName, _e: Enums.Element, _p: Vector3) -> void:
		push_reward("마물 처치"))
	EventBus.rescue_completed.connect(func(r: Dictionary) -> void:
		push_reward("%s 구조" % String(r.get("name", "생존자"))))
	EventBus.extraction_completed.connect(func(_p: StringName) -> void: push_reward("탈출"))
	EventBus.notification_posted.connect(_on_notification)
	_apply({})


# ---------------- public ----------------

func set_state(next: Dictionary) -> void:
	state = next
	_apply(next)


func push_reward(text: String, xp: int = 0) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	if xp > 0:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override(&"panel", _flat(UiTokens.ACCENT, 0, 8, 2))
		var cl := _lbl("XP +%d" % xp, &"LabelNumber", 16)
		cl.add_theme_color_override(&"font_color", UiTokens.ACCENT_TEXT)
		cl.remove_theme_color_override(&"font_shadow_color")
		chip.add_child(cl)
		row.add_child(chip)
	row.add_child(_lbl(text, &"LabelHud", 19))
	_feed.add_child(row)
	while _feed.get_child_count() > FEED_MAX:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	row.modulate.a = 0.0
	row.position.x = -14
	var tw := create_tween()
	tw.tween_property(row, ^"modulate:a", 1.0, 0.25)
	tw.tween_interval(FEED_SEC)
	tw.tween_property(row, ^"modulate:a", 0.0, 0.3)
	tw.tween_callback(row.queue_free)


func show_hint(title: String, body: String, key := "", key_label := "", danger := false) -> void:
	_hint_title.text = title
	_hint_body.text = body
	_hint_key.visible = not key.is_empty()
	_hint_key.key_text = key
	_hint_key_label.text = key_label
	(_hint.get_child(0).get_child(0) as PanelContainer).add_theme_stylebox_override(&"panel",
		_flat(UiTokens.DANGER if danger else UiTokens.ACCENT, 0, 14, 7))
	_hint_title.add_theme_color_override(&"font_color", UiTokens.TEXT if danger else UiTokens.ACCENT_TEXT)
	_hint.visible = true
	_hint.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_hint, ^"modulate:a", 1.0, 0.3)


func hide_hint() -> void:
	_hint.visible = false


func show_region(line1: String, line2: String) -> void:
	_region_l1.text = line1
	_region_l2.text = line2
	_region.visible = true
	_region.modulate.a = 1.0
	_region_left = REGION_SEC


func feed_count() -> int:
	return _feed.get_child_count()


# ---------------- per frame ----------------

func _process(delta: float) -> void:
	if auto_bind:
		var p := get_tree().get_first_node_in_group(&"player")
		if p != null and p.has_method(&"hud_state"):
			set_state(p.call(&"hud_state"))
	if not state.has("dusk_left_sec") and _dusk_local >= 0.0:
		_dusk_local = maxf(0.0, _dusk_local - delta)
		_set_timer(_dusk_local)
	if _region_left > 0.0:
		_region_left -= delta
		if _region_left <= 0.5:
			_region.modulate.a = maxf(0.0, _region_left / 0.5)
		if _region_left <= 0.0:
			_region.visible = false


# ---------------- apply state ----------------

func _apply(s: Dictionary) -> void:
	var hp_max := maxf(1.0, float(s.get("hp_max", 100.0)))
	_hp.value = float(s.get("hp", hp_max)) / hp_max
	_hp.fill_color = UiTokens.DANGER if _hp.value < 0.25 else UiTokens.TEXT
	_armor.segments = int(s.get("armor_segments", 4))
	_armor.value = float(s.get("armor", 0.0))
	_armor.visible = s.has("armor")
	_xp.value = float(s.get("xp", 0.0))
	_level.text = "Lv %d" % int(s.get("level", 1))
	_name.text = String(s.get("player_name", "구조대원"))
	var sta := float(s.get("stamina", 1.0))
	_stamina.value = sta
	_stamina.visible = sta < 0.999
	_mana.value = float(s.get("mana", 0.0))
	_mana.fill_color = UiTokens.INFO if _mana.value < 1.0 else UiTokens.ACCENT
	var mm: Dictionary = s.get("minimap", {})
	_minimap.points = mm.get("points", [])
	_minimap.player_heading = float(mm.get("heading", s.get("heading_deg", 0.0)))
	if s.has("dusk_left_sec"):
		_set_timer(float(s.dusk_left_sec))
	_apply_hold(s.get("hold", {}))
	_apply_prompt(s.get("prompt", {}))
	# lists rebuild only when their content changes
	var sig := var_to_str([s.get("weapons", []), s.get("weapon_index", 0), s.get("reloading", false),
		s.get("consumables", []), s.get("skills", []), s.get("companions", []), s.get("objectives", [])])
	if sig == _shown_sig:
		return
	_shown_sig = sig
	_build_weapons(s.get("weapons", []), int(s.get("weapon_index", 0)), bool(s.get("reloading", false)))
	_build_quick(s.get("consumables", []))
	_build_skills(s.get("skills", []))
	_build_mates(s.get("companions", []))
	_build_objectives(s.get("objectives", []))


func _set_timer(left: float) -> void:
	var t := maxi(0, ceili(left))
	_timer.text = "%02d:%02d" % [t / 60, t % 60]
	var warn := left < DUSK_WARN_SEC
	_timer.add_theme_color_override(&"font_color", UiTokens.WARN if warn else UiTokens.TEXT)
	_timer_icon.visible = warn
	_timer_cap.text = "해질녘까지" if left > 0.0 else "해가 졌습니다"


func _apply_hold(h: Dictionary) -> void:
	_hold.visible = not h.is_empty()
	if _hold.visible:
		_hold_label.text = String(h.get("label", ""))
		_hold_bar.value = float(h.get("progress", 0.0))


func _apply_prompt(p: Dictionary) -> void:
	_prompt.visible = not p.is_empty() and not _hold.visible
	if _prompt.visible:
		_prompt_key.key_text = String(p.get("key", "F"))
		_prompt_label.text = String(p.get("label", ""))


# ---------------- build ----------------

func _build() -> void:
	var m := UiTokens.HUD_MARGIN
	_minimap = HudMinimap.new()
	_place(_minimap, Control.PRESET_TOP_LEFT, Vector2(m, 24))

	# top-right: sortie timer, then objectives (design 14: "목표 목록, 출격 타이머")
	var tr := VBoxContainer.new()
	tr.add_theme_constant_override(&"separation", 10)
	tr.custom_minimum_size = Vector2(380, 0)
	var trow := HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_END
	trow.add_theme_constant_override(&"separation", 10)
	_timer_icon = _lbl("▲", &"LabelHud", 16)
	_timer_icon.add_theme_color_override(&"font_color", UiTokens.WARN)
	_timer_icon.visible = false
	_timer_cap = _lbl("해질녘까지", &"LabelHud", 16)
	_timer = _lbl("--:--", &"LabelNumber", 26)
	trow.add_child(_timer_icon)
	trow.add_child(_timer_cap)
	trow.add_child(_timer)
	tr.add_child(trow)
	_objectives = VBoxContainer.new()
	_objectives.add_theme_constant_override(&"separation", 6)
	tr.add_child(_objectives)
	_place(tr, Control.PRESET_TOP_RIGHT, Vector2(-m, 28))

	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override(&"separation", 8)
	_place(_feed, Control.PRESET_CENTER_LEFT, Vector2(m, -80))

	_build_hint()
	_build_region()

	# bottom-left vitals
	var vit := VBoxContainer.new()
	vit.add_theme_constant_override(&"separation", 6)
	vit.custom_minimum_size = Vector2(440, 0)
	_mates = VBoxContainer.new()
	_mates.add_theme_constant_override(&"separation", 4)
	vit.add_child(_mates)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override(&"separation", 10)
	var stripe := ColorRect.new()
	stripe.color = UiTokens.INFO
	stripe.custom_minimum_size = Vector2(8, 26)
	nrow.add_child(stripe)
	_name = _lbl("구조대원", &"LabelHud", 22)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(_name)
	_level = _lbl("Lv 1", &"LabelNumber", 18)
	nrow.add_child(_level)
	vit.add_child(nrow)
	_armor = SegBar.new()
	_armor.segments = 4
	_armor.fill_color = UiTokens.INFO
	_armor.custom_minimum_size = Vector2(440, 22)
	vit.add_child(_armor)
	_hp = SegBar.new()
	_hp.custom_minimum_size = Vector2(440, 24)
	vit.add_child(_hp)
	_xp = SegBar.new()
	_xp.frame = false
	_xp.fill_color = UiTokens.ACCENT
	_xp.empty_color = Color(1, 1, 1, 0.15)
	_xp.custom_minimum_size = Vector2(440, 4)
	vit.add_child(_xp)
	_place(vit, Control.PRESET_BOTTOM_LEFT, Vector2(m, -m))

	# bottom-right arms
	var arms := VBoxContainer.new()
	arms.alignment = BoxContainer.ALIGNMENT_END
	arms.add_theme_constant_override(&"separation", 8)
	var mrow := HBoxContainer.new()
	mrow.alignment = BoxContainer.ALIGNMENT_END
	mrow.add_theme_constant_override(&"separation", 10)
	_skills = HBoxContainer.new()
	_skills.add_theme_constant_override(&"separation", 8)
	mrow.add_child(_skills)
	var mana_box := VBoxContainer.new()
	var mlab := HBoxContainer.new()
	mlab.add_theme_constant_override(&"separation", 8)
	mlab.add_child(_lbl("정수 해방", &"LabelHud", 17))
	mlab.add_child(KeyChip.new("X"))
	mana_box.add_child(mlab)
	_mana = SegBar.new()
	_mana.custom_minimum_size = Vector2(150, 12)
	_mana.frame = false
	_mana.empty_color = Color(1, 1, 1, 0.18)
	mana_box.add_child(_mana)
	mrow.add_child(mana_box)
	arms.add_child(mrow)
	var pack := HBoxContainer.new()
	pack.alignment = BoxContainer.ALIGNMENT_END
	pack.add_theme_constant_override(&"separation", 10)
	_quick = HBoxContainer.new()
	_quick.add_theme_constant_override(&"separation", 8)
	_quick.size_flags_vertical = Control.SIZE_SHRINK_END
	pack.add_child(_quick)
	_weapons = VBoxContainer.new()
	_weapons.add_theme_constant_override(&"separation", 4)
	_weapons.custom_minimum_size = Vector2(300, 0)
	pack.add_child(_weapons)
	arms.add_child(pack)
	_place(arms, Control.PRESET_BOTTOM_RIGHT, Vector2(-m, -m))

	# bottom-centre: stamina, hold bar, prompt
	var bc := VBoxContainer.new()
	bc.alignment = BoxContainer.ALIGNMENT_END
	bc.add_theme_constant_override(&"separation", 8)
	_prompt = HBoxContainer.new()
	_prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt.add_theme_constant_override(&"separation", 10)
	_prompt_key = KeyChip.new("F")
	_prompt.add_child(_prompt_key)
	_prompt_label = _lbl("", &"LabelHud", 19)
	_prompt.add_child(_prompt_label)
	bc.add_child(_prompt)
	_hold = VBoxContainer.new()
	_hold.alignment = BoxContainer.ALIGNMENT_CENTER
	_hold_label = _lbl("", &"LabelHud", 18)
	_hold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hold.add_child(_hold_label)
	_hold_bar = SegBar.new()
	_hold_bar.bracket = true
	_hold_bar.custom_minimum_size = Vector2(320, 14)
	_hold_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hold.add_child(_hold_bar)
	bc.add_child(_hold)
	_stamina = SegBar.new()
	_stamina.bracket = true
	_stamina.custom_minimum_size = Vector2(300, 12)
	_stamina.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bc.add_child(_stamina)
	_place(bc, Control.PRESET_CENTER_BOTTOM, Vector2(0, -56))


func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	_hint.custom_minimum_size = Vector2(340, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	_hint.add_child(v)
	var band := PanelContainer.new()
	band.add_theme_stylebox_override(&"panel", _flat(UiTokens.ACCENT, 0, 14, 7))
	_hint_title = _lbl("", &"LabelSection", 17)
	_hint_title.add_theme_color_override(&"font_color", UiTokens.ACCENT_TEXT)
	band.add_child(_hint_title)
	v.add_child(band)
	var body := PanelContainer.new()
	body.add_theme_stylebox_override(&"panel", _flat(UiTokens.CREAM, 0, 14, 10))
	var bv := VBoxContainer.new()
	_hint_body = _lbl("", &"LabelOnCream", 16)
	_hint_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_body.custom_minimum_size = Vector2(312, 0)
	bv.add_child(_hint_body)
	var kr := HBoxContainer.new()
	kr.alignment = BoxContainer.ALIGNMENT_END
	kr.add_theme_constant_override(&"separation", 8)
	_hint_key = KeyChip.new("F", KeyChip.Style.DARK)
	kr.add_child(_hint_key)
	_hint_key_label = _lbl("", &"LabelOnCream", 14)
	kr.add_child(_hint_key_label)
	bv.add_child(kr)
	body.add_child(bv)
	v.add_child(body)
	_hint.visible = false
	_place(_hint, Control.PRESET_CENTER_RIGHT, Vector2(-UiTokens.HUD_MARGIN, -160))


func _build_region() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	var pin := Label.new()
	pin.text = "◉"
	pin.theme_type_variation = &"LabelHud"
	pin.add_theme_font_size_override(&"font_size", 34)
	h.add_child(pin)
	var v := VBoxContainer.new()
	_region_l1 = _lbl("", &"LabelHud", 16)
	_region_l1.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	_region_l2 = _lbl("", &"LabelHud", 30)
	v.add_child(_region_l1)
	v.add_child(_region_l2)
	h.add_child(v)
	_region = h
	_region.visible = false
	_place(_region, Control.PRESET_TOP_LEFT, Vector2(UiTokens.HUD_MARGIN, 330))


func _build_weapons(list: Array, idx: int, reloading: bool) -> void:
	_clear(_weapons)
	for i in list.size():
		var w: Dictionary = list[i]
		var on := i == idx
		var row := PanelContainer.new()
		row.add_theme_stylebox_override(&"panel", _flat(UiTokens.TEXT if on else Color(0.08, 0.08, 0.1, 0.45),
			0, 14, 5, Color(1, 1, 1, 0.55), 2))
		var h := HBoxContainer.new()
		var n := _lbl(str(i + 1), &"LabelNumber", 20)
		var nm := _lbl(String(w.get("name", "")), &"LabelHud", 19)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for l: Label in [n, nm]:
			if on:
				l.add_theme_color_override(&"font_color", UiTokens.TEXT_ON_CREAM)
				l.add_theme_color_override(&"font_shadow_color", Color.TRANSPARENT)
		h.add_child(n)
		h.add_child(nm)
		row.add_child(h)
		_weapons.add_child(row)
		if on:
			var am := PanelContainer.new()
			am.add_theme_stylebox_override(&"panel", _flat(Color(0.08, 0.08, 0.1, 0.45), 0, 14, 6,
				Color(1, 1, 1, 0.55), 2))
			var ah := HBoxContainer.new()
			var big: Label
			if bool(w.get("melee", false)):
				big = _lbl("근접", &"LabelNumber", 30)
				ah.add_child(big)
			else:
				var col := VBoxContainer.new()
				col.add_theme_constant_override(&"separation", -4)
				big = _lbl("장전 중" if reloading else "%03d" % int(w.get("ammo", 0)), &"LabelNumber",
					30 if reloading else UiTokens.SIZE_HUD_AMMO)
				var low := not reloading and int(w.get("ammo", 0)) <= 5
				big.add_theme_color_override(&"font_color",
					UiTokens.ACCENT if reloading else (UiTokens.DANGER if low else UiTokens.TEXT))
				col.add_child(big)
				col.add_child(_lbl("≡ %d" % int(w.get("reserve", 0)), &"LabelNumber", 17))
				ah.add_child(col)
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ah.add_child(sp)
			var rb := ShapeBadge.new()
			rb.value = int(w.get("rarity", 0))
			rb.badge_size = 16
			rb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ah.add_child(rb)
			am.add_child(ah)
			_weapons.add_child(am)


func _build_quick(list: Array) -> void:
	_clear(_quick)
	for i in 4:
		var it: Variant = list[i] if i < list.size() else null
		var box := VBoxContainer.new()
		box.add_theme_constant_override(&"separation", 0)
		var head := PanelContainer.new()
		head.add_theme_stylebox_override(&"panel", _flat(Color(0.08, 0.08, 0.1, 0.45), 0, 4, 2,
			Color(1, 1, 1, 0.55), 2))
		var hk := _lbl(str(i + 3), &"LabelNumber", 18)
		hk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(hk)
		box.add_child(head)
		var body := PanelContainer.new()
		body.custom_minimum_size = Vector2(78, 62)
		body.add_theme_stylebox_override(&"panel", _flat(Color(0.08, 0.08, 0.1, 0.35), 0, 4, 4,
			Color(1, 1, 1, 0.55), 2))
		var bv := VBoxContainer.new()
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		if it is Dictionary:
			var d: Dictionary = it
			var nm := _lbl(String(d.get("name", "")), &"LabelHud", 14)
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm.clip_text = true
			nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			bv.add_child(nm)
			var c := _lbl("×%d" % int(d.get("count", 1)), &"LabelNumber", 16)
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bv.add_child(c)
		else:
			box.modulate.a = 0.5
		body.add_child(bv)
		box.add_child(body)
		_quick.add_child(box)


func _build_skills(list: Array) -> void:
	_clear(_skills)
	for sk: Dictionary in list:
		var left := float(sk.get("left", 0.0))
		var b := VBoxContainer.new()
		b.add_theme_constant_override(&"separation", 2)
		var k := KeyChip.new(String(sk.get("key", "Q")))
		k.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		k.modulate.a = 0.5 if left > 0.0 else 1.0
		b.add_child(k)
		var t := _lbl("%d" % ceili(left) if left > 0.0 else "준비", &"LabelNumber", 15)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(t)
		_skills.add_child(b)


func _build_mates(list: Array) -> void:
	_clear(_mates)
	for m: Dictionary in list:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 10)
		var l := _lbl("%s · %s" % [String(m.get("name", "")), String(m.get("command", ""))], &"LabelHud", 16)
		l.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
		h.add_child(l)
		var bar := SegBar.new()
		bar.frame = false
		bar.value = float(m.get("hp", 1.0))
		bar.fill_color = UiTokens.DANGER if bar.value < 0.3 else UiTokens.TEXT
		bar.empty_color = Color(1, 1, 1, 0.2)
		bar.custom_minimum_size = Vector2(140, 6)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
		_mates.add_child(h)


func _build_objectives(list: Array) -> void:
	_clear(_objectives)
	if list.is_empty():
		return
	var head := _lbl("목표", &"LabelHud", 15)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	_objectives.add_child(head)
	for o: Dictionary in list:
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_END
		h.add_theme_constant_override(&"separation", 10)
		var t := _lbl(String(o.get("text", "")), &"LabelHud", 18)
		h.add_child(t)
		var p := _lbl(String(o.get("progress", "")), &"LabelNumber", 17)
		p.add_theme_color_override(&"font_color", UiTokens.ACCENT if bool(o.get("main", false)) else UiTokens.TEXT_DIM)
		h.add_child(p)
		var mark := ColorRect.new()
		mark.custom_minimum_size = Vector2(4, 20)
		mark.color = UiTokens.ACCENT if bool(o.get("main", false)) else Color(1, 1, 1, 0.4)
		h.add_child(mark)
		_objectives.add_child(h)


# ---------------- events ----------------

func _on_sortie_started(loadout: Dictionary) -> void:
	_dusk_local = GameState.SORTIE_DUSK_SEC
	_set_timer(_dusk_local)
	var region := String(loadout.get("region_name", loadout.get("region_id", "")))
	var wx := "비" if GameState.is_raining() else "맑음"
	show_region("해솔시 · %d일차 · %s" % [GameState.day, wx], region)


func _on_notification(text: String, severity: StringName) -> void:
	if severity == &"info":
		push_reward(text)
	else:
		show_hint("주의" if severity == &"warn" else "위험", text, "", "", severity == &"danger")


# ---------------- helpers ----------------

func _place(c: Control, preset: Control.LayoutPreset, offset: Vector2) -> void:
	add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	match preset:
		Control.PRESET_TOP_RIGHT, Control.PRESET_CENTER_RIGHT, Control.PRESET_BOTTOM_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	match preset:
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM:
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT:
			c.grow_vertical = Control.GROW_DIRECTION_BOTH
	c.position += offset


func _lbl(text: String, variation: StringName, size_px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.add_theme_font_size_override(&"font_size", size_px)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _flat(bg: Color, radius: int, px: int, py: int, border := Color.TRANSPARENT, bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = px
	sb.content_margin_right = px
	sb.content_margin_top = py
	sb.content_margin_bottom = py
	return sb


func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
