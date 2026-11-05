class_name HudCompass
extends Control
## Top-centre compass tape (UI_RULES §4): 5° ticks, cardinal letters, current heading box,
## optional markers (extract, objective) as small diamonds with distance. Owner: Lane D (D-04).

const PX_PER_DEG := 4.0
const LETTERS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var heading_deg := 0.0:
	set(v):
		heading_deg = fposmod(v, 360.0)
		queue_redraw()
## [{"bearing": deg, "kind": &"extract"|&"objective", "dist": metres}]
var markers: Array = []:
	set(v):
		markers = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(820, 62)


func _draw() -> void:
	var cx := size.x * 0.5
	var f := UiThemeBuilder.font_num()
	var half := size.x * 0.5
	for d in range(0, 360, 5):
		var delta := wrapf(d - heading_deg, -180.0, 180.0)
		var x := cx + delta * PX_PER_DEG
		if absf(x - cx) > half:
			continue
		var fade := 1.0 - smoothstep(half * 0.6, half, absf(x - cx))
		var c := Color(UiTokens.TEXT, 0.55 * fade)
		var major := d % 45 == 0
		draw_line(Vector2(x, 34 if not major else 30), Vector2(x, 44 if not major else 47),
			Color(UiTokens.TEXT, (0.95 if major else 0.55) * fade), 2)
		if major:
			var t: String = LETTERS[d / 45]
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(f, Vector2(x - w * 0.5, 24), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(UiTokens.TEXT, fade))
		elif c.a <= 0.0:
			pass
	for m: Dictionary in markers:
		var delta := wrapf(float(m.get("bearing", 0.0)) - heading_deg, -180.0, 180.0)
		var x := clampf(cx + delta * PX_PER_DEG, 8.0, size.x - 8.0)
		var col := UiTokens.GOOD if m.get("kind", &"") == &"extract" else UiTokens.ACCENT
		var y := 54.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, y - 6), Vector2(x + 6, y), Vector2(x, y + 6),
			Vector2(x - 6, y)]), col)
	# heading box
	var hs := str(roundi(heading_deg) % 360)
	var hw := f.get_string_size(hs, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 16
	draw_rect(Rect2(cx - hw * 0.5, 4, hw, 26), Color(0.47, 0.47, 0.5, 0.55))
	draw_string(f, Vector2(cx - hw * 0.5 + 8, 24), hs, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTokens.TEXT)
