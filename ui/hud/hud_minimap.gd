class_name HudMinimap
extends Control
## Top-left minimap (design 14 "필드 HUD"; UI_RULES §4): line-only frame, no fill panel.
## Points are in minimap space -1..1 around the player (B or the binder converts world → map).
## Kinds and their shape (never colour only): player=arrow, extract=diamond(GOOD),
## objective=square(ACCENT), companion=circle(INFO), monster_heard=triangle(DANGER). Owner: Lane D (D-04).

var player_heading := 0.0:
	set(v):
		player_heading = v
		queue_redraw()
## [{"pos": Vector2(-1..1), "kind": StringName}]
var points: Array = []:
	set(v):
		points = v
		queue_redraw()
var region_name := "":
	set(v):
		region_name = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 250)


func _draw() -> void:
	var map := Rect2(0, 0, size.x, size.x)
	var c := map.get_center()
	var r := map.size.x * 0.5 - 6.0
	draw_circle(c, r, Color(0, 0, 0, 0.22))
	draw_arc(c, r, 0, TAU, 64, Color(UiTokens.TEXT, 0.55), 2.0, true)
	draw_arc(c, r * 0.5, 0, TAU, 48, Color(UiTokens.TEXT, 0.15), 1.0, true)
	for p: Dictionary in points:
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		if pos.length() > 1.0:
			pos = pos.normalized()  # pin to the rim
		var at := c + pos * r
		match StringName(p.get("kind", &"")):
			&"extract":
				draw_colored_polygon(PackedVector2Array([at + Vector2(0, -7), at + Vector2(7, 0),
					at + Vector2(0, 7), at + Vector2(-7, 0)]), UiTokens.GOOD)
			&"objective":
				draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), UiTokens.ACCENT)
			&"companion":
				draw_circle(at, 5.0, UiTokens.INFO)
			&"monster_heard":
				draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(6, 5),
					at + Vector2(-6, 5)]), UiTokens.DANGER)
	var a := deg_to_rad(player_heading)
	var fwd := Vector2(sin(a), -cos(a))
	var side := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([c + fwd * 10, c - fwd * 6 + side * 6, c - fwd * 3,
		c - fwd * 6 - side * 6]), UiTokens.TEXT)
	if not region_name.is_empty():
		var f := UiThemeBuilder.font_kr(600)
		draw_string(f, Vector2(4, size.x + 26), region_name, HORIZONTAL_ALIGNMENT_LEFT, size.x, 17,
			UiTokens.TEXT)
