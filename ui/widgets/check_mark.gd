class_name CheckMark
extends Control
## Small checkbox for quest goals (UI_RULES §5 "퀘스트 카드"). Owner: Lane D (D-16).
## Done = filled box + tick, open = empty outlined box. The tick shape carries the meaning, the
## colour only helps (never colour alone).

var done := false:
	set(v):
		done = v
		queue_redraw()
var box_size := 18.0
var ink := UiTokens.TEXT_ON_CREAM


func _init(is_done := false, on_cream := true) -> void:
	done = is_done
	ink = UiTokens.TEXT_ON_CREAM if on_cream else UiTokens.TEXT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _get_minimum_size() -> Vector2:
	return Vector2(box_size, box_size)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(box_size, box_size))
	if done:
		draw_rect(r, UiTokens.GOOD, true)
		draw_polyline(PackedVector2Array([Vector2(4, 9.5), Vector2(7.5, 13), Vector2(14, 5)]),
			UiTokens.TEXT_ON_CREAM, 2.4, true)
	else:
		draw_rect(r.grow(-1), ink, false, 2.0)
