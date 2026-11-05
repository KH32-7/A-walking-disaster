class_name FaceDot
extends Control
## Light face circle for lists (UI 재설계 "그림 먼저, 글은 다음"). Owner: Lane D.
## The last letter of the name on a warm circle; `dim` greys it (absent / lost residents) and `mark`
## adds a small shape badge at the top left (◇ grief, △ stranded, ◆ missing, † lost, ■ blocked).
## For a real rendered face use ResidentPortrait (heavier: one SubViewport each).

var letter := "?"
var dim := false
var mark := ""


func _init(name_text: String, d := 44, is_dim := false, badge := "") -> void:
	letter = name_text.substr(name_text.length() - 1, 1) if name_text.length() > 0 else "?"
	dim = is_dim
	mark = badge
	custom_minimum_size = Vector2(d, d)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var d := minf(size.x, size.y)
	var c := size * 0.5
	var r := d * 0.5 - 1.0
	draw_circle(c, r, Color("8a8780") if dim else Color("c98f52"))
	draw_arc(c, r, 0, TAU, 40, UiTokens.TEXT_DIM if dim else UiTokens.TEXT, 2.0, true)
	var font := UiThemeBuilder.font_kr(700)
	var fs := int(d * 0.42)
	draw_string(font, Vector2(0, c.y + fs * 0.36), letter, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color("2a1a0a"))
	if mark != "":
		var ms := maxi(int(d * 0.32), 12)
		var p := Vector2(-3, ms * 0.8)
		draw_string_outline(font, p, mark, HORIZONTAL_ALIGNMENT_LEFT, -1, ms, 4, UiTokens.INK)
		draw_string(font, p, mark, HORIZONTAL_ALIGNMENT_LEFT, -1, ms, UiTokens.TEXT if dim else UiTokens.WARN)
