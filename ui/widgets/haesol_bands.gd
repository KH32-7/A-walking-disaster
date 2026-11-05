class_name HaesolBands
extends Control
## The Haesol city stripe (UI_RULES §6 "장면 전환"): a teal band slides in from the left and a
## yellow band from the right, one above the other. Owner: Lane D (D-19).
## Used by the loading / transition card, the title and the ending card.
## `progress` 0..1 is how far each band has come in; play() animates it.

const IN_TIME := 0.4

## 0 = nothing, 1 = both bands fully in.
@export_range(0.0, 1.0) var progress := 1.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		queue_redraw()
## Band thickness in px (teal, yellow) and the gap between them.
@export var teal_width := 6.0
@export var yellow_width := 3.0
@export var gap := 7.0
## Fraction of the width each band covers when fully in (1 = edge to edge).
@export_range(0.1, 1.0) var reach := 1.0
## Bands meet in the middle and stop there instead of crossing the whole width.
@export var meet_in_middle := false

var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	return Vector2(0, teal_width + gap + yellow_width)


## Slides the bands in (ease-out). Returns the tween so callers can await it.
func play(duration := IN_TIME) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	progress = 0.0
	_tween = create_tween()
	_tween.tween_property(self, ^"progress", 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return _tween


func _draw() -> void:
	var w := size.x
	var full := w * (0.5 if meet_in_middle else reach)
	var len := full * progress
	var y_teal := 0.0
	var y_yellow := teal_width + gap
	# Teal from the left edge.
	draw_rect(Rect2(0, y_teal, len, teal_width), UiTokens.INFO)
	# Yellow from the right edge.
	draw_rect(Rect2(w - len, y_yellow, len, yellow_width), UiTokens.ACCENT)
