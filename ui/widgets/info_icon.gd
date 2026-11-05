class_name InfoIcon
extends Control
## Inclusion-facility mark (UI_RULES §7 "포함 시설": `INFO` 아이콘 + 글). Owner: Lane D.
## A filled `INFO` circle with an "i" (dot + stem). Always placed next to words, never alone.

var icon_size := 18.0


func _init(px := 18.0) -> void:
	icon_size = px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _get_minimum_size() -> Vector2:
	return Vector2(icon_size, icon_size)


func _draw() -> void:
	var c := Vector2(icon_size, icon_size) * 0.5
	draw_circle(c, icon_size * 0.5, UiTokens.INFO, true, -1.0, true)
	var ink := UiTokens.TEXT_ON_CREAM
	draw_circle(c + Vector2(0, -icon_size * 0.22), icon_size * 0.08, ink, true, -1.0, true)
	draw_line(c + Vector2(0, -icon_size * 0.06), c + Vector2(0, icon_size * 0.28), ink, icon_size * 0.14, true)
