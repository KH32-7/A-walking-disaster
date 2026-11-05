class_name RaidWidgets
## Small drawn widgets for the raid screens (D-14). Owner: Lane D.
##   Compass   - base in the middle, the four directions; incoming ones get a filled arrow + bold name.
##   OddsBar   - defense ratio axis cut into 패배 / 신승 / 승리 / 완승 (band names written in each band),
##               a bracket for the predicted range and a marker for the likely value.
## Band edges come from RaidRules' outcome thresholds (read only; no rule is computed here).


static func danger_card(title: String, min_w := 560.0) -> Array:
	## Guide card, DANGER variant (UI_RULES §5 안내 카드 + §9 D-14): red band + cream body.
	## Returns [root, body VBox (on cream), band HBox].
	var root := PanelContainer.new()
	root.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	root.custom_minimum_size = Vector2(min_w, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	root.add_child(v)
	var band := PanelContainer.new()
	band.add_theme_stylebox_override(&"panel", flat(UiTokens.DANGER, [UiTokens.CARD_RADIUS, UiTokens.CARD_RADIUS, 0, 0], 20, 10))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override(&"separation", 12)
	var icon := Label.new()
	icon.text = "▲"
	icon.add_theme_font_size_override(&"font_size", 20)
	icon.add_theme_color_override(&"font_color", UiTokens.TEXT)
	bh.add_child(icon)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = &"LabelSection"
	t.add_theme_color_override(&"font_color", UiTokens.TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(t)
	band.add_child(bh)
	v.add_child(band)
	var body := PanelContainer.new()
	body.add_theme_stylebox_override(&"panel", flat(UiTokens.CREAM, [0, 0, UiTokens.CARD_RADIUS, UiTokens.CARD_RADIUS], 22, 18))
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override(&"separation", 12)
	body.add_child(bv)
	v.add_child(body)
	return [root, bv, bh]


## [top-left, top-right, bottom-right, bottom-left] radii.
static func flat(bg: Color, radii: Array, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radii[0]
	sb.corner_radius_top_right = radii[1]
	sb.corner_radius_bottom_right = radii[2]
	sb.corner_radius_bottom_left = radii[3]
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


## One "이름 ........ 값" row on the cream card.
static func cream_row(name_text: String, value: String, value_color := UiTokens.TEXT_ON_CREAM) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	var a := Label.new()
	a.text = name_text
	a.theme_type_variation = &"LabelOnCreamDim"
	a.add_theme_font_size_override(&"font_size", 15)
	a.custom_minimum_size = Vector2(96, 0)
	h.add_child(a)
	var b := Label.new()
	b.text = value
	b.theme_type_variation = &"LabelOnCream"
	b.add_theme_font_size_override(&"font_size", 18)
	b.add_theme_color_override(&"font_color", value_color)
	b.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(b)
	return h


class Compass:
	extends Control
	## Directions the raid comes from (&"north" ...). On cream by default.
	var directions: Array = []:
		set(v):
			directions = v
			queue_redraw()
	var on_cream := true

	const DIRS := [[&"north", Vector2(0, -1), "북"], [&"east", Vector2(1, 0), "동"],
		[&"south", Vector2(0, 1), "남"], [&"west", Vector2(-1, 0), "서"]]

	func _get_minimum_size() -> Vector2:
		return Vector2(150, 150)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 18.0
		var ink := UiTokens.TEXT_ON_CREAM if on_cream else UiTokens.TEXT
		var dim := UiTokens.TEXT_ON_CREAM_DIM if on_cream else UiTokens.TEXT_DIM
		draw_arc(c, r, 0, TAU, 48, Color(dim, 0.5), 1.5, true)
		# the base: a small house square in the middle
		draw_rect(Rect2(c - Vector2(9, 7), Vector2(18, 14)), ink)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -7), c + Vector2(0, -17), c + Vector2(12, -7)]), ink)
		var f := UiThemeBuilder.font_kr(700)
		var wanted := directions.map(func(d): return StringName(d))
		for d: Array in DIRS:
			var dir: Vector2 = d[1]
			var hit: bool = d[0] in wanted
			var tip := c + dir * (r * 0.42)
			var tail := c + dir * (r - 4.0)
			if hit:
				# filled arrow pointing at the base
				draw_line(tail, tip + dir * 10.0, UiTokens.DANGER, 5.0, true)
				var side := Vector2(-dir.y, dir.x)
				draw_colored_polygon(PackedVector2Array([tip, tip + dir * 16.0 + side * 10.0, tip + dir * 16.0 - side * 10.0]), UiTokens.DANGER)
			else:
				draw_line(tail, tail - dir * 8.0, Color(dim, 0.6), 2.0, true)
			var t: String = d[2]
			var fs := 17 if hit else 14
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var lp := c + dir * (r + 11.0) - Vector2(tw.x * 0.5, -fs * 0.36)
			draw_string(f, lp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTokens.DANGER if hit else dim)


class OddsBar:
	extends Control
	## predict_raid(): {"ratio_min", "ratio_max", "likely"}. Empty = nothing drawn but the axis.
	var prediction: Dictionary = {}:
		set(v):
			prediction = v
			queue_redraw()
	## Actual ratio (result screen); < 0 = none. `reveal` 0..1 animates its marker in.
	var actual := -1.0:
		set(v):
			actual = v
			queue_redraw()
	var reveal := 1.0:
		set(v):
			reveal = v
			queue_redraw()
	var on_cream := true
	const AXIS_MAX := 2.0

	func _get_minimum_size() -> Vector2:
		return Vector2(420, 58)

	func _x(ratio: float) -> float:
		return size.x * clampf(ratio / AXIS_MAX, 0.0, 1.0)

	func _draw() -> void:
		var ink := UiTokens.TEXT_ON_CREAM if on_cream else UiTokens.TEXT
		var h := 22.0
		var y0 := 16.0
		var edges := [0.0, RaidRules.RATIO_NARROW, RaidRules.RATIO_WIN, RaidRules.RATIO_FLAWLESS, AXIS_MAX]
		var outcomes := [Enums.RaidOutcome.LOSS, Enums.RaidOutcome.NARROW, Enums.RaidOutcome.WIN, Enums.RaidOutcome.FLAWLESS]
		var f := UiThemeBuilder.font_kr(700)
		for i in 4:
			var a := _x(edges[i])
			var b := _x(edges[i + 1])
			var col := RaidFlow.outcome_color(outcomes[i])
			draw_rect(Rect2(a, y0, b - a - 2.0, h), Color(col, 0.35))
			if outcomes[i] == Enums.RaidOutcome.LOSS:  # hatch the loss band (위험 구간 빗금, §7)
				var x := a + 3.0
				while x < b - 2.0:
					draw_line(Vector2(x, y0 + h), Vector2(minf(x + 7.0, b - 2.0), y0), Color(0, 0, 0, 0.18), 2.0)
					x += 8.0
			var t := RaidFlow.outcome_name(outcomes[i])
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(f, Vector2((a + b) * 0.5 - tw * 0.5, y0 + h - 6.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
		var nf := UiThemeBuilder.font_num()
		for e in [RaidRules.RATIO_NARROW, RaidRules.RATIO_WIN, RaidRules.RATIO_FLAWLESS]:
			var t := "%.1f" % e
			draw_string(nf, Vector2(_x(e) - 9.0, y0 + h + 16.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(ink, 0.7))
		if not prediction.is_empty():
			var a := _x(float(prediction.get("ratio_min", 0.0)))
			var b := _x(float(prediction.get("ratio_max", 0.0)))
			# bracket above the bar: ⌐ ... ¬
			draw_rect(Rect2(a, y0, b - a, h), Color(ink, 0.12))
			draw_line(Vector2(a, y0 - 7.0), Vector2(b, y0 - 7.0), ink, 3.0)
			draw_line(Vector2(a, y0 - 7.0), Vector2(a, y0 + 3.0), ink, 3.0)
			draw_line(Vector2(b, y0 - 7.0), Vector2(b, y0 + 3.0), ink, 3.0)
		if actual >= 0.0:
			var x := _x(actual * reveal)
			draw_rect(Rect2(x - 2.5, y0 - 10.0, 5.0, h + 14.0), ink)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 8, y0 - 14), Vector2(x + 8, y0 - 14), Vector2(x, y0 - 4)]), ink)
