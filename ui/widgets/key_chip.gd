class_name KeyChip
extends Control
## Key hint chip (UI_RULES §5). Field: white square + dark text. Menu footer: outlined pill.
## Owner: Lane D.

## FIELD: cream chip on the world. DARK: dark chip on cream cards. OUTLINE: menu footer pill.
enum Style { FIELD, OUTLINE, DARK }

@export var key_text := "F":
	set(v):
		key_text = v
		update_minimum_size()
		queue_redraw()
@export var style: Style = Style.FIELD:
	set(v):
		style = v
		update_minimum_size()
		queue_redraw()
@export var font_size := 15:
	set(v):
		font_size = v
		update_minimum_size()
		queue_redraw()


func _init(text := "F", chip_style := Style.FIELD) -> void:
	key_text = text
	style = chip_style
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _font() -> Font:
	for ch in key_text:
		if ch.unicode_at(0) > 127:
			return UiThemeBuilder.font_kr(700)
	return UiThemeBuilder.font_num()


func _get_minimum_size() -> Vector2:
	var w := _font().get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var h := font_size + 11.0
	return Vector2(maxf(h, w + (22.0 if style == Style.OUTLINE else 14.0)), h)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var f := _font()
	var fg := UiTokens.TEXT_ON_CREAM
	if style == Style.FIELD or style == Style.DARK:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTokens.CREAM if style == Style.FIELD else UiTokens.TEXT_ON_CREAM
		if style == Style.DARK:
			fg = UiTokens.CREAM
		sb.set_corner_radius_all(4)
		draw_style_box(sb, r)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.TRANSPARENT
		sb.border_color = UiTokens.LINE_STRONG
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(size.y * 0.5))
		draw_style_box(sb, r)
		fg = UiTokens.TEXT
	var ts := f.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var y := (size.y + f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
	draw_string(f, Vector2((size.x - ts.x) * 0.5, y), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fg)
