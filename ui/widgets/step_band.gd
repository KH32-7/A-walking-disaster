class_name StepBand
extends PanelContainer
## Step band (UI redesign "순서가 있는 일은 순서를 보여 준다", #125). Owner: Lane D.
## A dark pill at the top centre of a screen: numbered steps joined by short lines. Done steps get a
## GOOD circle with ✓, the current step a light pill with a filled circle and bold words, later steps
## a thin outline. State reads by shape (✓ / filled / outline) and words, never colour only.
##
##   var band := StepBand.new()
##   band.set_steps(["바람", "맞이", "이름 짓기", "입주"], 2)   # 2 = 이름 짓기 now; steps.size() = all done

var steps: Array = []
var current := 0
var _row: HBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.078, 0.086, 0.114, 0.72)
	sb.set_corner_radius_all(99)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override(&"panel", sb)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", 10)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)


## Places the band at the top centre of `parent` (a full-screen Control).
func place_top_center(top := 30.0) -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	offset_top = top
	grow_horizontal = Control.GROW_DIRECTION_BOTH


func set_steps(names: Array, cur: int) -> void:
	steps = names
	current = cur
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	for i in names.size():
		if i > 0:
			var ar := ColorRect.new()
			ar.color = Color(UiTokens.TEXT, 0.3)
			ar.custom_minimum_size = Vector2(20, 2)
			ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_row.add_child(ar)
		_row.add_child(_step(i, String(names[i])))
	reset_size()


## "done" | "now" | "later" for step i.
func state_of(i: int) -> StringName:
	return &"done" if i < current else (&"now" if i == current else &"later")


func _step(i: int, text: String) -> Control:
	var st := state_of(i)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(99)
	sb.bg_color = Color(UiTokens.TEXT, 0.12) if st == &"now" else Color.TRANSPARENT
	sb.content_margin_left = 8
	sb.content_margin_right = 18
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override(&"panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	h.add_child(Dot.new("✓" if st == &"done" else str(i + 1), st))
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700 if st == &"now" else 500))
	l.add_theme_font_size_override(&"font_size", 19)
	l.add_theme_color_override(&"font_color", UiTokens.TEXT if st == &"now" else UiTokens.TEXT_DIM)
	h.add_child(l)
	return p


class Dot extends Control:
	var glyph := ""
	var state: StringName = &"later"

	func _init(g: String, s: StringName) -> void:
		glyph = g
		state = s
		custom_minimum_size = Vector2(30, 30)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := 14.0
		var ink := UiTokens.TEXT_DIM
		match state:
			&"done":
				draw_circle(c, r, UiTokens.GOOD, true, -1.0, true)
				ink = Color("14301a")
			&"now":
				draw_circle(c, r, UiTokens.TEXT, true, -1.0, true)
				ink = UiTokens.INK
			_:
				draw_arc(c, r - 1.0, 0, TAU, 32, Color(UiTokens.TEXT, 0.45), 2.0, true)
		var font := UiThemeBuilder.font_num() if glyph != "✓" else UiThemeBuilder.font_kr(700)
		var fs := 17
		var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
