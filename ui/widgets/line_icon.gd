class_name LineIcon
extends Control
## Small line icons drawn in code (UI 재설계, ui/_mockups/ui-redesign.html). Owner: Lane D.
## 24×24 design grid, round caps, one colour. Always put words next to an icon or in its tooltip
## (UI_RULES §1.6: 색·모양만으로 구분하지 않는다).
##
##   LineIcon.new(&"wood", 18)                 resource / category / state icons, see KINDS
##   LineIcon.for_resource(&"plank", 16)       resource id → icon (unknown ids draw a dot)

## Resource id → icon kind. Ids without an icon fall back to &"dot".
const RESOURCE_KINDS := {
	&"wood": &"wood", &"stone": &"stone", &"scrap": &"scrap", &"food": &"food", &"parts": &"parts",
	&"cloth": &"cloth", &"plank": &"plank", &"seeds": &"seed", &"rare_parts": &"parts",
	&"electronics": &"bolt", &"motor": &"parts", &"generator_core": &"bolt", &"paint": &"drop",
	&"medicine": &"cross", &"textbook": &"book", &"radio_parts": &"radio", &"fuel": &"drop",
	&"stone_shard": &"stone", &"debris": &"stone",
}
const KINDS: Array[StringName] = [&"wood", &"stone", &"scrap", &"food", &"parts", &"cloth", &"plank", &"seed",
	&"star", &"home", &"sprout", &"anvil", &"access", &"box", &"shield", &"check", &"warn", &"lock", &"flag",
	&"tree", &"people", &"hammer", &"bolt", &"noise", &"drop", &"cross", &"book", &"radio", &"gem", &"dot", &"back"]

var kind: StringName = &"dot"
var px := 18.0
var color := UiTokens.TEXT
var line_width := 1.8


func _init(k: StringName = &"dot", size_px := 18.0, col := UiTokens.TEXT) -> void:
	kind = k
	px = size_px
	color = col
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


static func for_resource(id: StringName, size_px := 18.0, col := UiTokens.TEXT) -> LineIcon:
	var ic := LineIcon.new(RESOURCE_KINDS.get(id, &"dot"), size_px, col)
	ic.tooltip_text = MenuScreen.resource_name(id)
	return ic


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


func _get_minimum_size() -> Vector2:
	return Vector2(px, px)


func _draw() -> void:
	_s = px / 24.0
	_w = maxf(1.2, line_width * _s * 1.15)
	_o = (size - Vector2(px, px)) * 0.5
	match kind:
		&"wood":
			_line([Vector2(6.5, 8), Vector2(17.5, 8)])
			_line([Vector2(6.5, 16), Vector2(17.5, 16)])
			_arc(6.5, 12, 4, 90, 270)
			_ring(17.5, 12, 3.8)
			_line([Vector2(17.5, 10.6), Vector2(17.5, 13.4)])
		&"stone":
			_line([Vector2(3.5, 17.5), Vector2(6.5, 9), Vector2(13, 5.5), Vector2(19.5, 10), Vector2(18.5, 18)], true)
			_line([Vector2(6.5, 9), Vector2(12.5, 12), Vector2(18.5, 9.8)])
			_line([Vector2(12.5, 12), Vector2(12.5, 17.8)])
		&"scrap":
			_line([Vector2(12, 3.5), Vector2(19.4, 7.75), Vector2(19.4, 16.25), Vector2(12, 20.5),
				Vector2(4.6, 16.25), Vector2(4.6, 7.75)], true)
			_ring(12, 12, 3)
		&"food":
			_line([Vector2(5, 9), Vector2(19, 9), Vector2(19, 19), Vector2(5, 19)], true)
			_line([Vector2(5, 12.5), Vector2(19, 12.5)])
			_line([Vector2(8, 9), Vector2(8, 6.5), Vector2(16, 6.5), Vector2(16, 9)])
		&"parts":
			_ring(12, 12, 3.2)
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				_line([Vector2(12, 12) + d * 5.6, Vector2(12, 12) + d * 8.6])
		&"cloth":
			_line([Vector2(8, 4), Vector2(4, 7), Vector2(6, 10), Vector2(8, 9), Vector2(8, 20), Vector2(16, 20),
				Vector2(16, 9), Vector2(18, 10), Vector2(20, 7), Vector2(16, 4), Vector2(12, 6.5)], true)
		&"plank":
			_line([Vector2(3, 9.5), Vector2(21, 9.5), Vector2(21, 14.5), Vector2(3, 14.5)], true)
			_line([Vector2(8, 9.5), Vector2(8, 14.5)])
			_line([Vector2(14, 9.5), Vector2(14, 14.5)])
		&"seed":
			_line([Vector2(12, 20), Vector2(12, 12)])
			_line([Vector2(12, 14), Vector2(8, 12.5), Vector2(6, 9), Vector2(9.5, 9.5), Vector2(12, 12)])
			_line([Vector2(12, 12.5), Vector2(14.5, 8.5), Vector2(18.5, 6.5), Vector2(17.5, 10.5), Vector2(12, 14.5)])
		&"star":
			var pts := []
			for i in 10:
				var a := -PI / 2 + PI * i / 5.0
				var r := 8.5 if i % 2 == 0 else 3.8
				pts.append(Vector2(12, 12.5) + Vector2(cos(a), sin(a)) * r)
			_line(pts, true)
		&"home":
			_line([Vector2(4, 11), Vector2(12, 4), Vector2(20, 11)])
			_line([Vector2(6.5, 9.5), Vector2(6.5, 20), Vector2(17.5, 20), Vector2(17.5, 9.5)])
			_line([Vector2(10, 20), Vector2(10, 15), Vector2(14, 15), Vector2(14, 20)])
		&"sprout":
			_line([Vector2(12, 20), Vector2(12, 12)])
			_line([Vector2(12, 13), Vector2(8, 12), Vector2(5, 7.5), Vector2(9, 8), Vector2(12, 13)])
			_line([Vector2(12, 11), Vector2(14.5, 6.5), Vector2(19, 5), Vector2(17.5, 9.5), Vector2(12, 11)])
		&"anvil":
			_line([Vector2(4, 7), Vector2(16, 7), Vector2(17.5, 9.8), Vector2(20, 11), Vector2(14, 13),
				Vector2(15, 16), Vector2(8, 16), Vector2(9, 13), Vector2(5.5, 11)], true)
			_line([Vector2(7, 20), Vector2(17, 20)])
		&"access":
			_dot(12, 4.5, 1.9)
			_line([Vector2(12, 7), Vector2(12, 13), Vector2(17, 13), Vector2(19, 18)])
			_arc(12, 15.5, 5.5, 200, 400)
		&"box":
			_line([Vector2(3.5, 8), Vector2(12, 4), Vector2(20.5, 8), Vector2(20.5, 16), Vector2(12, 20), Vector2(3.5, 16)], true)
			_line([Vector2(3.5, 8), Vector2(12, 12), Vector2(20.5, 8)])
			_line([Vector2(12, 12), Vector2(12, 20)])
		&"shield":
			_line([Vector2(12, 3), Vector2(19, 6), Vector2(19, 11.5), Vector2(16.5, 17), Vector2(12, 21),
				Vector2(7.5, 17), Vector2(5, 11.5), Vector2(5, 6)], true)
		&"check":
			_line([Vector2(5, 12.5), Vector2(9.5, 17), Vector2(19, 7.5)])
		&"warn":
			_line([Vector2(12, 4), Vector2(21, 19.5), Vector2(3, 19.5)], true)
			_line([Vector2(12, 10), Vector2(12, 14.5)])
			_dot(12, 17, 1.1)
		&"lock":
			_line([Vector2(5, 10.5), Vector2(19, 10.5), Vector2(19, 20.5), Vector2(5, 20.5)], true)
			_arc(12, 8, 4, 180, 360)
			_line([Vector2(8, 8), Vector2(8, 10.5)])
			_line([Vector2(16, 8), Vector2(16, 10.5)])
		&"flag":
			_line([Vector2(6, 21), Vector2(6, 4)])
			_line([Vector2(6, 4), Vector2(17, 4), Vector2(14.5, 8), Vector2(17, 12), Vector2(6, 12)])
		&"tree":
			_line([Vector2(12, 3), Vector2(6, 12), Vector2(9, 12), Vector2(5, 18), Vector2(19, 18), Vector2(15, 12),
				Vector2(18, 12)], true)
			_line([Vector2(12, 18), Vector2(12, 21)])
		&"people":
			_ring(12, 8, 3.5)
			_arc(12, 20.5, 7, 180, 360)
		&"hammer":
			_line([Vector2(9, 4.5), Vector2(16, 4.5), Vector2(19, 7.5), Vector2(17, 9.5), Vector2(14.5, 7), Vector2(12, 7)], true)
			_line([Vector2(13.5, 8.5), Vector2(5, 17), Vector2(7, 19), Vector2(15.5, 10.5)])
		&"bolt":
			_line([Vector2(13.5, 3), Vector2(5.5, 13.5), Vector2(11, 13.5), Vector2(10, 21), Vector2(18, 10.5),
				Vector2(12.5, 10.5)], true)
		&"noise":
			_line([Vector2(4, 9.5), Vector2(7.5, 9.5), Vector2(12, 6), Vector2(12, 18), Vector2(7.5, 14.5), Vector2(4, 14.5)], true)
			_arc(13.5, 12, 4, -50, 50)
			_arc(13.5, 12, 7.5, -50, 50)
		&"drop":
			_line([Vector2(12, 3.5), Vector2(17.5, 12), Vector2(17, 16.5), Vector2(12, 20.5), Vector2(7, 16.5),
				Vector2(6.5, 12)], true)
		&"cross":
			_line([Vector2(3.5, 6.5), Vector2(20.5, 6.5), Vector2(20.5, 19.5), Vector2(3.5, 19.5)], true)
			_line([Vector2(12, 10), Vector2(12, 16)])
			_line([Vector2(9, 13), Vector2(15, 13)])
		&"book":
			_line([Vector2(4, 5.5), Vector2(8, 4.8), Vector2(12, 6), Vector2(16, 4.8), Vector2(20, 5.5),
				Vector2(20, 18.5), Vector2(16, 17.8), Vector2(12, 19), Vector2(8, 17.8), Vector2(4, 18.5)], true)
			_line([Vector2(12, 6), Vector2(12, 19)])
		&"radio":
			_line([Vector2(4, 8), Vector2(20, 8), Vector2(20, 20), Vector2(4, 20)], true)
			_line([Vector2(7, 8), Vector2(16, 3.5)])
			_ring(9, 14, 2.5)
			_line([Vector2(14, 12.5), Vector2(17, 12.5)])
			_line([Vector2(14, 15.5), Vector2(17, 15.5)])
		&"gem":
			_line([Vector2(12, 3), Vector2(18, 9), Vector2(12, 21), Vector2(6, 9)], true)
			_line([Vector2(6, 9), Vector2(18, 9)])
		&"back":
			_line([Vector2(14.5, 5.5), Vector2(8, 12), Vector2(14.5, 18.5)])
		_:
			_dot(12, 12, 3.5)


var _s := 1.0
var _w := 1.8
var _o := Vector2.ZERO


func _p(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _s


func _line(pts: Array, closed := false) -> void:
	var arr := PackedVector2Array()
	for p: Vector2 in pts:
		arr.append(_p(p.x, p.y))
	if closed:
		arr.append(arr[0])
	draw_polyline(arr, color, _w, true)


func _ring(cx: float, cy: float, r: float) -> void:
	draw_arc(_p(cx, cy), r * _s, 0.0, TAU, 32, color, _w, true)


func _dot(cx: float, cy: float, r: float) -> void:
	draw_circle(_p(cx, cy), r * _s, color, true, -1.0, true)


func _arc(cx: float, cy: float, r: float, a0: float, a1: float) -> void:
	draw_arc(_p(cx, cy), r * _s, deg_to_rad(a0), deg_to_rad(a1), 16, color, _w, true)