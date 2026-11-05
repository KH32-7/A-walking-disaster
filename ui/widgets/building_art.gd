class_name BuildingArt
extends Control
## Mini model of a building for the build cards (UI 재설계, 컬트 오브 더 램 Build 메뉴 + 칸 크기).
## Owner: Lane D. Draws the footprint cells as an iso grid and a shaded box on top, so a 1×2 bed and
## a 3×3 workshop read differently before any text. Display only: size and look come from BuildingDef.

## Look per display group (BuildScreen.GROUPS).
enum Look { BOX, ROOF, FLAT, RAMP, WALL, LOGS, FIRE }

var cells := Vector2i.ONE
var height := 16.0
var tint := Color("8fa35a")
var look := Look.BOX
## Locked cards draw grey.
var dim := false


func _init(w_cells := 1, d_cells := 1, h := 16.0, col := Color("8fa35a"), lk := Look.BOX) -> void:
	cells = Vector2i(maxi(w_cells, 1), maxi(d_cells, 1))
	height = h
	tint = col
	look = lk
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Builds the art for a BuildingDef. Heights and looks are picked here for display only.
static func for_def(def: BuildingDef, col: Color) -> BuildingArt:
	var sz := def.size if def.size.x > 0 and def.size.y > 0 else Vector2i.ONE
	var longest := maxi(sz.x, sz.y)
	var lk := Look.ROOF if longest >= 3 else Look.BOX
	var h := 10.0 + 7.0 * longest
	match def.id:
		&"vegetable_garden", &"rain_tank":
			lk = Look.FLAT
			h = 5.0
		&"bed":
			h = 8.0
		&"ramp":
			lk = Look.RAMP
			h = 16.0
		&"lumber_yard", &"salvage_yard", &"quarry":
			lk = Look.LOGS
			h = 14.0
		&"bonfire", &"essence_lamp", &"light_tower":
			lk = Look.FIRE
			h = 8.0
	if def.category == BuildingDef.Category.DEFENSE and longest <= 2 and lk == Look.BOX:
		lk = Look.WALL
		h = 22.0
	return BuildingArt.new(sz.x, sz.y, h, col, lk)


func set_dim(v: bool) -> void:
	dim = v
	queue_redraw()


func _draw() -> void:
	var w := float(cells.x)
	var d := float(cells.y)
	var W := size.x
	var H := size.y
	if W <= 0.0 or H <= 0.0:
		return
	# Footprint is (w + d)·tw/2 wide and (w + d)·tw/4 + height tall: fit both with a margin.
	var tw := minf(W * 1.6 / (w + d), H * 0.8 / ((w + d) / 4.0 + height / 32.0))
	tw = minf(tw, H * 0.6)
	var th := tw / 2.0
	var hh := height * tw / 32.0
	var total_h := (w + d) * th / 2.0 + hh
	var oy := (H - total_h) / 2.0 + hh
	var ox := W / 2.0 - (w - d) * tw / 4.0
	var P := func(x: float, y: float) -> Vector2: return Vector2(ox + (x - y) * tw / 2.0, oy + (x + y) * th / 2.0)
	var base := tint
	if dim:
		var g := base.get_luminance()
		base = Color(g, g, g).darkened(0.35)
	var grid_line := Color(1, 1, 1, 0.35)
	for x in cells.x:
		for y in cells.y:
			var q := PackedVector2Array([P.call(x, y), P.call(x + 1, y), P.call(x + 1, y + 1), P.call(x, y + 1)])
			draw_colored_polygon(q, Color(0, 0, 0, 0.18))
			q.append(q[0])
			draw_polyline(q, grid_line, 1.0, true)
	var up := func(v: Vector2) -> Vector2: return v - Vector2(0, hh)
	if look == Look.RAMP:
		var r1: Vector2 = P.call(0, 0)
		var r2: Vector2 = P.call(w, 0)
		var r3: Vector2 = P.call(w, d)
		var r4: Vector2 = P.call(0, d)
		draw_colored_polygon(PackedVector2Array([r4, r3, up.call(r2), up.call(r1)]), base.lightened(0.08))
		draw_colored_polygon(PackedVector2Array([r2, r3, up.call(r2)]), base.darkened(0.4))
		return
	var i := 0.12 if look != Look.WALL else 0.32
	var a: Vector2 = P.call(i, i)
	var b: Vector2 = P.call(w - i, i)
	var c: Vector2 = P.call(w - i, d - i)
	var e: Vector2 = P.call(i, d - i)
	draw_colored_polygon(PackedVector2Array([e, c, up.call(c), up.call(e)]), base.darkened(0.22))
	draw_colored_polygon(PackedVector2Array([b, c, up.call(c), up.call(b)]), base.darkened(0.4))
	draw_colored_polygon(PackedVector2Array([up.call(a), up.call(b), up.call(c), up.call(e)]), base.lightened(0.12))
	match look:
		Look.ROOF:
			var m1: Vector2 = (up.call(a) + up.call(e)) / 2.0 - Vector2(0, hh * 0.45)
			var m2: Vector2 = (up.call(b) + up.call(c)) / 2.0 - Vector2(0, hh * 0.45)
			draw_colored_polygon(PackedVector2Array([up.call(e), up.call(c), m2, m1]), base.darkened(0.45))
			draw_colored_polygon(PackedVector2Array([up.call(a), up.call(b), m2, m1]), base.darkened(0.2))
		Look.LOGS:
			var l: Vector2 = up.call(P.call(w * 0.5, d * 0.62))
			var log_col := Color("7a5532") if not dim else Color(0.35, 0.35, 0.35)
			for k in 2:
				var r := Rect2(l + Vector2(-tw * 0.42 + k * tw * 0.08, -tw * 0.12 - k * tw * 0.16), Vector2(tw * 0.7, tw * 0.16))
				draw_rect(r, log_col)
		Look.FIRE:
			var f: Vector2 = up.call(P.call(w * 0.5, d * 0.5))
			var flame := Color("ffb347") if not dim else Color(0.6, 0.6, 0.6)
			draw_colored_polygon(PackedVector2Array([f + Vector2(0, -tw * 0.7), f + Vector2(tw * 0.18, -tw * 0.15),
				f + Vector2(0, 0), f + Vector2(-tw * 0.18, -tw * 0.15)]), flame)
