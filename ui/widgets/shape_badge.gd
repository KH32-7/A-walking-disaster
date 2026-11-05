@tool
class_name ShapeBadge
extends Control
## Colour + shape badge for rarity and element (UI_RULES §2, §5). Owner: Lane D (D-01).
## Never colour alone: the shape always differs, and `show_label` adds the name.
##   rarity: circle, square, triangle, diamond, star
##   element: circle(none), petal, square, drop, bolt

enum Kind { RARITY, ELEMENT }

@export var kind: Kind = Kind.RARITY:
	set(v):
		kind = v
		_refresh()
@export_range(0, 4) var value: int = 0:
	set(v):
		value = v
		_refresh()
@export_range(8, 64) var badge_size: int = 14:
	set(v):
		badge_size = v
		_refresh()
@export var show_label := false:
	set(v):
		show_label = v
		_refresh()
@export var label_color := UiTokens.TEXT:
	set(v):
		label_color = v
		queue_redraw()


func get_shape() -> UiTokens.Shape:
	return UiTokens.rarity_shape(value) if kind == Kind.RARITY else UiTokens.element_shape(value)


func get_color() -> Color:
	return UiTokens.rarity_color(value) if kind == Kind.RARITY else UiTokens.element_color(value)


func get_label_text() -> String:
	return UiTokens.RARITY_NAMES[clampi(value, 0, 4)] if kind == Kind.RARITY \
		else UiTokens.ELEMENT_NAMES[clampi(value, 0, 4)]


func _refresh() -> void:
	tooltip_text = get_label_text()
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var w := float(badge_size)
	if show_label:
		var f := get_theme_default_font()
		w += 4.0 + f.get_string_size(get_label_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, _label_size()).x
	return Vector2(w, badge_size)


func _label_size() -> int:
	return maxi(10, roundi(badge_size * 0.9))


func _draw() -> void:
	var s := float(badge_size)
	draw_shape(self, get_shape(), Rect2(0, (size.y - s) * 0.5, s, s), get_color())
	if show_label:
		var f := get_theme_default_font()
		var fs := _label_size()
		var y := (size.y + f.get_ascent(fs) - f.get_descent(fs)) * 0.5
		draw_string(f, Vector2(s + 4.0, y), get_label_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label_color)


## Draws one of the token shapes into `rect`. Static so slots and HUD can reuse it.
static func draw_shape(ci: CanvasItem, shape: UiTokens.Shape, rect: Rect2, color: Color) -> void:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5
	match shape:
		UiTokens.Shape.CIRCLE:
			ci.draw_circle(c, r * 0.9, color)
		UiTokens.Shape.SQUARE:
			ci.draw_rect(Rect2(c - Vector2.ONE * r * 0.78, Vector2.ONE * r * 1.56), color)
		UiTokens.Shape.TRIANGLE:
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.92), c + Vector2(r * 0.92, r * 0.8), c + Vector2(-r * 0.92, r * 0.8)]), color)
		UiTokens.Shape.DIAMOND:
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)
		UiTokens.Shape.STAR:
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2.0 + i * PI / 5.0
				var rr := r if i % 2 == 0 else r * 0.45
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, color)
		UiTokens.Shape.PETAL:
			ci.draw_colored_polygon(_petal(c, r), color)
		UiTokens.Shape.DROP:
			var pts := PackedVector2Array([c + Vector2(0, -r)])
			for i in 13:
				var a := -PI * 0.15 + i * PI * 1.3 / 12.0
				pts.append(c + Vector2(0, r * 0.3) + Vector2(cos(a), sin(a)) * r * 0.62)
			ci.draw_colored_polygon(pts, color)
		UiTokens.Shape.BOLT:
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(r * 0.2, -r), c + Vector2(-r * 0.6, r * 0.15), c + Vector2(-r * 0.02, r * 0.15),
				c + Vector2(-r * 0.25, r), c + Vector2(r * 0.6, -r * 0.2), c + Vector2(r * 0.05, -r * 0.2)]), color)


static func _petal(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		var a := lerpf(-PI / 2.0, PI * 1.5, t)
		var rr := r * (0.55 + 0.45 * absf(cos(a * 2.0)))
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts
