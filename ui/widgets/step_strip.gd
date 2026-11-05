class_name StepStrip
extends PanelContainer
## ① ② ③ step strip at the top centre of a screen (UI_RULES §5 "단계 띠", D-06 재설계). Owner: Lane D.
## Done steps get a green circle with a tick, the current one a white circle and white words,
## the rest an outline and dim words — the number shape carries it, not the colour.
##
##   var s := StepStrip.new(["건물 고르기", "놓을 곳 정하기", "주민이 짓기"], 1)
##   parent.add_child(s); s.place_top_center()

var steps: Array = []
## 1-based current step.
var current := 1

var _row: HBoxContainer


func _init(step_names: Array = [], now := 1) -> void:
	steps = step_names
	current = now
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.INK, 0.72)
	sb.set_corner_radius_all(99)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	add_theme_stylebox_override(&"panel", sb)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", 10)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_build()


## Anchors to the top centre, `top` px down.
func place_top_center(top := 34.0) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	position.y = top


func set_current(n: int) -> void:
	current = n
	_build()


func _build() -> void:
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	for i in steps.size():
		if i > 0:
			var ar := ColorRect.new()
			ar.color = Color(UiTokens.TEXT, 0.3)
			ar.custom_minimum_size = Vector2(18, 2)
			ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_row.add_child(ar)
		_row.add_child(_pill(i + 1, String(steps[i])))


func _pill(n: int, text: String) -> Control:
	var on := n == current
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.TEXT, 0.12) if on else Color.TRANSPARENT
	sb.set_corner_radius_all(99)
	sb.content_margin_left = 6
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override(&"panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	h.add_child(Num.new(n, 0 if n < current else (1 if on else 2)))
	var l := MenuScreen.label(text, &"LabelHud", 16)
	l.add_theme_color_override(&"font_color", UiTokens.TEXT if on else UiTokens.TEXT_DIM)
	h.add_child(l)
	return p


## Step number circle. state 0 = done (green + tick), 1 = now (white), 2 = later (outline).
class Num extends Control:
	var n := 1
	var state := 2

	func _init(num: int, st: int) -> void:
		n = num
		state = st
		custom_minimum_size = Vector2(26, 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		if state == 0:
			draw_circle(c, 12.0, UiTokens.GOOD, true, -1.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(-1.5, 4), c + Vector2(5.5, -4.5)]),
				UiTokens.INK, 2.4, true)
			return
		if state == 1:
			draw_circle(c, 12.0, UiTokens.TEXT, true, -1.0, true)
		else:
			draw_arc(c, 11.5, 0.0, TAU, 32, Color(UiTokens.TEXT, 0.5), 1.6, true)
		var font := get_theme_default_font()
		var s := str(n)
		var fs := 14
		var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - tw * 0.5, c.y + fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			UiTokens.INK if state == 1 else UiTokens.TEXT_DIM)
