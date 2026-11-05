class_name SegBar
extends Control
## HUD bar (UI_RULES §5): 2px frame box, inner fill, optional segments (armor = 4).
## Owner: Lane D. value is 0..1. `bracket` draws the hold-progress bracket style instead.

@export_range(0.0, 1.0) var value := 1.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var segments := 1:
	set(v):
		segments = maxi(1, v)
		queue_redraw()
@export var fill_color := UiTokens.TEXT:
	set(v):
		fill_color = v
		queue_redraw()
@export var empty_color := Color(1, 1, 1, 0.12)
@export var frame := true
@export var bracket := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if bracket:
		var c := Color(UiTokens.TEXT, 0.75)
		draw_line(Vector2(1, 0), Vector2(1, size.y), c, 2)
		draw_line(Vector2(1, 0), Vector2(6, 0), c, 2)
		draw_line(Vector2(1, size.y), Vector2(6, size.y), c, 2)
		draw_line(Vector2(size.x - 1, 0), Vector2(size.x - 1, size.y), c, 2)
		draw_line(Vector2(size.x - 6, 0), Vector2(size.x - 1, 0), c, 2)
		draw_line(Vector2(size.x - 6, size.y), Vector2(size.x - 1, size.y), c, 2)
		var inner := r.grow(-4)
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * value, inner.size.y)), fill_color)
		return
	if frame:
		draw_rect(r, Color(0, 0, 0, 0.25))
		draw_rect(r.grow(-1), Color(1, 1, 1, 0.35), false, 2.0)
	var inner := r.grow(-4.0 if frame else 0.0)
	if segments <= 1:
		draw_rect(inner, empty_color)
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * value, inner.size.y)), fill_color)
		return
	var gap := 4.0
	var w := (inner.size.x - gap * (segments - 1)) / segments
	var filled := value * segments
	for i in segments:
		var cell := Rect2(inner.position + Vector2(i * (w + gap), 0), Vector2(w, inner.size.y))
		draw_rect(cell, Color(fill_color, 0.18))
		var part := clampf(filled - i, 0.0, 1.0)
		if part > 0.0:
			draw_rect(Rect2(cell.position, Vector2(cell.size.x * part, cell.size.y)), fill_color)
