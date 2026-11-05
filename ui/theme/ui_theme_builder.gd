class_name UiThemeBuilder
extends RefCounted
## Builds the Godot Theme from UiTokens. Owner: Lane D (D-01). Rules: ui/UI_RULES.md §8.
## UI calls build() at start and again when Settings.text_size / high_contrast change.
## Scenes use only the type variation names in VARIATIONS.

const VARIATIONS: Array[StringName] = [
	&"PanelSlate", &"PanelMenu", &"PanelSlateInner", &"PanelBand", &"CardCream", &"CardCreamFoot",
	&"ButtonPrimary", &"ButtonSecondary", &"ButtonCancel", &"ButtonSoft", &"ButtonSpecial", &"TabText",
	&"LabelTitle", &"LabelSection", &"LabelDim", &"LabelOnCream", &"LabelOnCreamDim", &"LabelNumber",
	&"LabelHud", &"LabelSubtitle", &"LabelSpeaker",
]

static var _font_cache: Dictionary = {}


static func build(text_size: int = 1, high_contrast: bool = false) -> Theme:
	var k := UiTokens.text_scale(text_size)
	var t := Theme.new()
	var regular := font_kr(500)
	t.default_font = regular
	t.default_font_size = roundi(UiTokens.SIZE_BODY * k)

	var dim := UiTokens.text_dim(high_contrast)
	var line := UiTokens.line(high_contrast)

	# --- base Label / Button ---
	t.set_color(&"font_color", &"Label", UiTokens.TEXT)
	t.set_color(&"font_shadow_color", &"Label", Color(0, 0, 0, 0))

	# --- panels ---
	# Roomier padding (사용자 피드백 2026-11-06: 칸과 글자 사이가 좁음).
	_panel(t, &"PanelSlate", &"PanelContainer", UiTokens.slate(high_contrast), 0, Color.TRANSPARENT, 0, 20)
	_panel(t, &"PanelMenu", &"PanelContainer", UiTokens.slate_menu(high_contrast), UiTokens.PANEL_RADIUS,
		Color.TRANSPARENT, 0, 22)
	_panel(t, &"PanelSlateInner", &"PanelContainer", UiTokens.SLATE_2, UiTokens.CARD_RADIUS, line, 1, 16)
	_panel(t, &"PanelBand", &"PanelContainer", Color(1, 1, 1, 0.08), UiTokens.BAND_RADIUS,
		Color.TRANSPARENT, 0, 14)
	_panel(t, &"CardCream", &"PanelContainer", UiTokens.CREAM, UiTokens.CARD_RADIUS, Color.TRANSPARENT, 0, 20)
	_panel(t, &"CardCreamFoot", &"PanelContainer", UiTokens.CREAM_2, 0, Color.TRANSPARENT, 0, 12)
	t.set_constant(&"line_spacing", &"Label", 4)
	t.set_constant(&"separation", &"VBoxContainer", 8)
	t.set_constant(&"separation", &"HBoxContainer", 10)

	# --- buttons: pill shapes (§5) ---
	_button(t, &"ButtonPrimary", UiTokens.ACCENT, UiTokens.ACCENT_TEXT, k, Color.TRANSPARENT)
	_button(t, &"ButtonSecondary", UiTokens.CREAM, UiTokens.TEXT_ON_CREAM, k, Color.TRANSPARENT)
	_button(t, &"ButtonCancel", UiTokens.GREY_BTN, UiTokens.TEXT, k, Color.TRANSPARENT)
	_button(t, &"ButtonSoft", UiTokens.PILL_SOFT, UiTokens.PILL_SOFT_TEXT, k, Color.TRANSPARENT)
	_button(t, &"ButtonSpecial", UiTokens.SLATE_2, UiTokens.TEXT, k, UiTokens.TAB_GLOW)
	# text tab: transparent, selected = outline pill
	t.set_type_variation(&"TabText", &"Button")
	var tab_n := _box(Color.TRANSPARENT, 99, Color.TRANSPARENT, 0, 18, 6)
	var tab_p := _box(Color.TRANSPARENT, 99, UiTokens.LINE_STRONG, UiTokens.LINE_WIDTH, 18, 6)
	for s in [&"normal", &"hover", &"focus", &"disabled"]:
		t.set_stylebox(s, &"TabText", tab_n)
	t.set_stylebox(&"pressed", &"TabText", tab_p)
	t.set_stylebox(&"hover_pressed", &"TabText", tab_p)
	t.set_color(&"font_color", &"TabText", dim)
	t.set_color(&"font_hover_color", &"TabText", UiTokens.TEXT)
	t.set_color(&"font_pressed_color", &"TabText", UiTokens.TEXT)
	t.set_font(&"font", &"TabText", font_kr(600))
	t.set_font_size(&"font_size", &"TabText", roundi(UiTokens.SIZE_TAB * k))

	# --- labels ---
	_label(t, &"LabelTitle", font_kr(700), UiTokens.SIZE_TITLE * k, UiTokens.TEXT)
	_label(t, &"LabelSection", font_kr(700), UiTokens.SIZE_SECTION * k, UiTokens.TEXT)
	_label(t, &"LabelDim", regular, UiTokens.SIZE_SMALL * k, dim)
	_label(t, &"LabelOnCream", regular, UiTokens.SIZE_BODY * k, UiTokens.TEXT_ON_CREAM)
	_label(t, &"LabelOnCreamDim", regular, UiTokens.SIZE_SMALL * k, UiTokens.TEXT_ON_CREAM_DIM)
	_label(t, &"LabelNumber", font_num(), UiTokens.SIZE_HUD_NUMBER * k, UiTokens.TEXT)
	_label(t, &"LabelHud", font_kr(600), UiTokens.SIZE_BODY * k, UiTokens.TEXT)
	_hud_shadow(t, &"LabelHud", high_contrast)
	_hud_shadow(t, &"LabelNumber", high_contrast)
	_label(t, &"LabelSubtitle", regular, UiTokens.SIZE_SUBTITLE * k, UiTokens.TEXT)
	_hud_shadow(t, &"LabelSubtitle", high_contrast)
	_label(t, &"LabelSpeaker", font_kr(700), UiTokens.SIZE_SUBTITLE * k, UiTokens.ACCENT)
	_hud_shadow(t, &"LabelSpeaker", high_contrast)
	return t


## Pretendard at a given weight (variable font). Cached per weight.
static func font_kr(weight: int = 500) -> Font:
	var key := "kr%d" % weight
	if _font_cache.has(key):
		return _font_cache[key]
	var base := load(UiTokens.FONT_KR) as Font
	var f: Font = base
	if base != null:
		var v := FontVariation.new()
		v.base_font = base
		var ts := TextServerManager.get_primary_interface()
		v.variation_opentype = {ts.name_to_tag("wght"): weight}
		f = v
	else:
		f = ThemeDB.fallback_font
	_font_cache[key] = f
	return f


static func font_num() -> Font:
	if not _font_cache.has("num"):
		var f := load(UiTokens.FONT_NUM) as Font
		_font_cache["num"] = f if f != null else ThemeDB.fallback_font
	return _font_cache["num"]


static func _box(bg: Color, radius: int, border: Color, border_w: int, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	sb.anti_aliasing = true
	return sb


static func _panel(t: Theme, name: StringName, base: StringName, bg: Color, radius: int,
		border: Color, border_w: int, pad: int) -> void:
	t.set_type_variation(name, base)
	t.set_stylebox(&"panel", name, _box(bg, radius, border, border_w, pad, pad))


static func _button(t: Theme, name: StringName, bg: Color, fg: Color, k: float, ring: Color) -> void:
	t.set_type_variation(name, &"Button")
	var ring_w := 2 if ring.a > 0.0 else 0
	var n := _box(bg, 99, ring, ring_w, 22, 9)
	var h := _box(bg.lightened(0.08), 99, ring, ring_w, 22, 9)
	var p := _box(bg.darkened(0.1), 99, ring, ring_w, 22, 9)
	var d := _box(Color(bg, bg.a * 0.45), 99, Color.TRANSPARENT, 0, 22, 9)
	var f := _box(bg, 99, UiTokens.TEXT, 2, 22, 9)
	t.set_stylebox(&"normal", name, n)
	t.set_stylebox(&"hover", name, h)
	t.set_stylebox(&"pressed", name, p)
	t.set_stylebox(&"disabled", name, d)
	t.set_stylebox(&"focus", name, f)
	for c in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		t.set_color(c, name, fg)
	t.set_color(&"font_disabled_color", name, Color(fg, 0.5))
	t.set_font(&"font", name, font_kr(700))
	t.set_font_size(&"font_size", name, roundi(17 * k))


static func _label(t: Theme, name: StringName, font: Font, size: float, color: Color) -> void:
	t.set_type_variation(name, &"Label")
	t.set_font(&"font", name, font)
	t.set_font_size(&"font_size", name, roundi(size))
	t.set_color(&"font_color", name, color)


static func _hud_shadow(t: Theme, name: StringName, high_contrast: bool) -> void:
	if high_contrast:
		t.set_color(&"font_outline_color", name, Color.BLACK)
		t.set_constant(&"outline_size", name, 4)
	else:
		t.set_color(&"font_shadow_color", name, UiTokens.SHADOW)
		t.set_constant(&"shadow_offset_x", name, 0)
		t.set_constant(&"shadow_offset_y", name, 2)
		t.set_constant(&"shadow_outline_size", name, 3)
