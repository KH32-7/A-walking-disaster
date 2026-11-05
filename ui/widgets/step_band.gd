class_name StepBand
extends PanelContainer
## Step band (UI 재설계 "순서가 있는 일은 순서를 보여 준다"). Owner: Lane D.
## A dark pill: done steps get a GOOD ✓ circle, the current step a white numbered circle on a lighter
## pill, later steps an outlined number with dim text. Shape + word, never colour alone.
##
##   var band := StepBand.new()
##   band.set_steps([{"label": "짓기", "state": &"done"}, {"label": "주둔 1/2", "state": &"now"},
##       {"label": "가동", "state": &"todo"}])

const DONE := &"done"
const NOW := &"now"
const TODO := &"todo"

var steps: Array = []
var _row: HBoxContainer


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.SLATE, 0.92)
	sb.set_corner_radius_all(99)
	sb.content_margin_left = 10
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override(&"panel", sb)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_row = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", 10)
	add_child(_row)


func set_steps(list: Array) -> void:
	steps = list.duplicate(true)
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	for i in steps.size():
		if i > 0:
			var dash := MenuScreen.label("—", &"LabelDim", 14)
			_row.add_child(dash)
		_row.add_child(_step(i, steps[i]))


## The label of the current step ("" when every step is done).
func current_label() -> String:
	for s: Dictionary in steps:
		if s.get("state", TODO) == NOW:
			return String(s.get("label", ""))
	return ""


func _step(i: int, s: Dictionary) -> Control:
	var st: StringName = s.get("state", TODO)
	var holder := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.12) if st == NOW else Color.TRANSPARENT
	sb.set_corner_radius_all(99)
	sb.content_margin_left = 6
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	holder.add_theme_stylebox_override(&"panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	holder.add_child(h)
	h.add_child(StepDot.new(i + 1, st))
	var l := MenuScreen.label(String(s.get("label", "")), &"LabelHud" if st != TODO else &"LabelDim", 15)
	if st == NOW:
		l.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	h.add_child(l)
	return holder


class StepDot extends Control:
	var n := 1
	var st: StringName = &"todo"

	func _init(num: int, state: StringName) -> void:
		n = num
		st = state
		custom_minimum_size = Vector2(24, 24)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := 11.0
		var font := UiThemeBuilder.font_num()
		match st:
			&"done":
				draw_circle(c, r, UiTokens.GOOD)
				draw_polyline(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(-1, 4), c + Vector2(6, -4)]),
					UiTokens.INK, 2.5, true)
			&"now":
				draw_circle(c, r, UiTokens.TEXT)
				draw_string(font, c + Vector2(-12, 5), str(n), HORIZONTAL_ALIGNMENT_CENTER, 24, 14, UiTokens.INK)
			_:
				draw_arc(c, r, 0, TAU, 28, UiTokens.TEXT_DIM, 1.5, true)
				draw_string(font, c + Vector2(-12, 5), str(n), HORIZONTAL_ALIGNMENT_CENTER, 24, 14, UiTokens.TEXT_DIM)
