class_name MapView
extends Control
## Field map canvas (D-16). Owner: Lane D. UI_RULES §2 shapes: every mark has its own shape and a
## text label, colour only helps.
##   extract   diamond (GOOD)          objective  square (ACCENT)      recording  tape (TEXT)
##   lost_gear ring (WARN)             companion  circle (INFO)        player     arrow (TEXT)
##   route     dashed line + arrow (INFO) "숨은 경로"
##   ping      pin (PING), FieldState.ping set by right click on the map
## The MapScreen feeds everything; this only converts world x/z to map pixels and draws.
## North (-Z) is up.

const FOG_SHADER := preload("res://ui/theme/map_fog.gdshader")

## World rectangle shown, in x/z metres (x = world x, y = world z).
var bounds := Rect2(-75, -75, 150, 150):
	set(v):
		bounds = v
		queue_redraw_all()
## Top-down render of the region (ViewportTexture or any texture). null = plain fog colour.
var texture: Texture2D:
	set(v):
		texture = v
		if _bg != null:
			_bg.texture = v if v != null else _blank()
## [{"pos": Vector3, "kind": StringName, "label": String}]
var marks: Array = []:
	set(v):
		marks = v
		queue_redraw_all()
## [{"from": Vector3, "to": Vector3, "label": String}]
var routes: Array = []:
	set(v):
		routes = v
		queue_redraw_all()
var player_pos := Vector3.ZERO
var player_dir := Vector2(0, -1)  # x/z forward
var has_player := false

var _bg: TextureRect
var _ink: Control
var _fog: ImageTexture


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = TextureRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = FOG_SHADER
	mat.set_shader_parameter(&"fog_color", UiTokens.INK.lerp(UiTokens.SLATE, 0.5))
	mat.set_shader_parameter(&"edge_color", UiTokens.LINE_STRONG)
	_bg.material = mat
	_bg.texture = _blank()
	add_child(_bg)
	_ink = Control.new()
	_ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.draw.connect(_draw_ink)
	add_child(_ink)


func queue_redraw_all() -> void:
	if _ink != null:
		_ink.queue_redraw()


func set_player(pos: Vector3, forward: Vector3) -> void:
	has_player = true
	player_pos = pos
	var f := Vector2(forward.x, forward.z)
	player_dir = f.normalized() if f.length() > 0.01 else Vector2(0, -1)
	_ink.queue_redraw()


## Painted region art (art/maps/) instead of a render: shown whole and as painted, no fog and no
## greybox tone-down. `rect` is the world x/z rectangle the picture covers.
func set_art(art: Texture2D, rect: Rect2) -> void:
	bounds = rect
	texture = art
	var mat := _bg.material as ShaderMaterial
	var white := Image.create(1, 1, false, Image.FORMAT_L8)
	white.fill(Color.WHITE)
	mat.set_shader_parameter(&"fog_tex", ImageTexture.create_from_image(white))
	mat.set_shader_parameter(&"desaturate", 0.0)
	mat.set_shader_parameter(&"exposure", 1.0)
	mat.set_shader_parameter(&"gamma", 1.0)
	art_mode = true


## True after set_art(): set_explored() is ignored so the whole picture stays visible.
var art_mode := false


## Builds the fog texture from FieldExplore cells (Vector2i -> true) for the current bounds.
func set_explored(cells: Dictionary, cell_size: float) -> void:
	if art_mode:
		return
	var w := maxi(1, ceili(bounds.size.x / cell_size))
	var h := maxi(1, ceili(bounds.size.y / cell_size))
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	var ox := floori(bounds.position.x / cell_size)
	var oz := floori(bounds.position.y / cell_size)
	for cell: Vector2i in cells:
		var x := cell.x - ox
		var y := cell.y - oz
		if x >= 0 and y >= 0 and x < w and y < h:
			img.set_pixel(x, y, Color.WHITE)
	if _fog == null or _fog.get_size() != Vector2(w, h):
		_fog = ImageTexture.create_from_image(img)
	else:
		_fog.update(img)
	(_bg.material as ShaderMaterial).set_shader_parameter(&"fog_tex", _fog)


## World position -> pixel inside this control.
func to_map(world: Vector3) -> Vector2:
	var u := (world.x - bounds.position.x) / bounds.size.x
	var v := (world.z - bounds.position.y) / bounds.size.y
	return Vector2(u * size.x, v * size.y)


## Pixel inside this control -> world x/z (y = 0). Inverse of to_map().
func from_map(px: Vector2) -> Vector3:
	return Vector3(bounds.position.x + px.x / maxf(size.x, 1.0) * bounds.size.x, 0.0,
		bounds.position.y + px.y / maxf(size.y, 1.0) * bounds.size.y)


func metres_per_px() -> float:
	return bounds.size.x / maxf(size.x, 1.0)


func _blank() -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(UiTokens.SLATE_2)
	return ImageTexture.create_from_image(img)


# ---------------- drawing ----------------

## Label rectangles placed this frame; a label that would cover another moves up or is skipped
## (the side panels list everything anyway).
var _labels: Array[Rect2] = []


func _draw_ink() -> void:
	_labels.clear()
	var font := UiThemeBuilder.font_kr(600)
	for r: Dictionary in routes:
		_draw_route(to_map(r.from), to_map(r.to), String(r.get("label", "숨은 경로")), font)
	for m: Dictionary in marks:
		_draw_mark(to_map(m.pos), StringName(m.kind), String(m.get("label", "")), font)
	if has_player:
		_draw_player(to_map(player_pos))
	# frame, north tick, scale bar
	_ink.draw_rect(Rect2(Vector2.ZERO, size), UiTokens.LINE_STRONG, false, 2.0)
	var n := Vector2(size.x - 30, 34)
	_ink.draw_circle(n + Vector2(0, 6), 22, Color(UiTokens.INK, 0.75))
	_ink.draw_colored_polygon(PackedVector2Array([n + Vector2(0, -16), n + Vector2(8, 4), n + Vector2(-8, 4)]),
		UiTokens.TEXT)
	_ink.draw_string(font, n + Vector2(-7, 22), "북", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTokens.TEXT)
	var metres := 10.0
	for m in [10.0, 20.0, 50.0, 100.0]:
		metres = m
		if m / metres_per_px() >= 80.0:
			break
	var px := metres / metres_per_px()
	var b := Vector2(20, size.y - 22)
	_ink.draw_line(b, b + Vector2(px, 0), UiTokens.TEXT, 2.0)
	_ink.draw_line(b + Vector2(0, -5), b + Vector2(0, 3), UiTokens.TEXT, 2.0)
	_ink.draw_line(b + Vector2(px, -5), b + Vector2(px, 3), UiTokens.TEXT, 2.0)
	_text(b + Vector2(px + 8, 5), "%dm" % metres, font, 13, UiTokens.TEXT)


func _draw_mark(at: Vector2, kind: StringName, label: String, font: Font) -> void:
	draw_symbol(_ink, at, kind)
	if label != "":
		_place_label(at, label, font, UiTokens.TEXT)


func _place_label(at: Vector2, label: String, font: Font, color: Color) -> void:
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	for dy in [30.0, -20.0]:
		var rect := Rect2(at.x - w * 0.5 - 2, at.y + dy - 15, w + 4, 20)
		if _labels.any(func(r: Rect2) -> bool: return r.intersects(rect)):
			continue
		_labels.append(rect)
		_text(Vector2(at.x - w * 0.5, at.y + dy), label, font, 15, color)
		return


## Draws one map symbol centred on `at`. Static so the legend draws the very same shapes.
static func draw_symbol(ci: CanvasItem, at: Vector2, kind: StringName) -> void:
	var out := Color(0, 0, 0, 0.85)
	match kind:
		&"extract":
			var d := PackedVector2Array([at + Vector2(0, -13), at + Vector2(13, 0), at + Vector2(0, 13), at + Vector2(-13, 0)])
			ci.draw_colored_polygon(_grow(d, at, 3.0), out)
			ci.draw_colored_polygon(d, UiTokens.GOOD)
			ci.draw_colored_polygon(_grow(d, at, -6.0), UiTokens.INK)
		&"objective":
			ci.draw_rect(Rect2(at - Vector2(11, 11), Vector2(22, 22)), out)
			ci.draw_rect(Rect2(at - Vector2(9, 9), Vector2(18, 18)), UiTokens.ACCENT)
		&"recording":
			ci.draw_rect(Rect2(at - Vector2(11, 8), Vector2(22, 16)), out)
			ci.draw_rect(Rect2(at - Vector2(9, 6), Vector2(18, 12)), UiTokens.TEXT)
			ci.draw_circle(at + Vector2(-4, 0), 2.4, UiTokens.INK)
			ci.draw_circle(at + Vector2(4, 0), 2.4, UiTokens.INK)
		&"lost_gear":
			ci.draw_arc(at, 10, 0, TAU, 32, out, 6.0, true)
			ci.draw_arc(at, 10, 0, TAU, 32, UiTokens.WARN, 3.5, true)
			ci.draw_line(at + Vector2(-4, -4), at + Vector2(4, 4), UiTokens.WARN, 2.5)
			ci.draw_line(at + Vector2(4, -4), at + Vector2(-4, 4), UiTokens.WARN, 2.5)
		&"companion":
			ci.draw_circle(at, 8.5, out)
			ci.draw_circle(at, 6.5, UiTokens.INFO)
		&"player":
			var arrow := PackedVector2Array([at + Vector2(0, -14), at + Vector2(10, 9), at + Vector2(0, 4), at + Vector2(-10, 9)])
			ci.draw_colored_polygon(_grow(arrow, at, 3.0), out)
			ci.draw_colored_polygon(arrow, UiTokens.TEXT)
		&"ping":
			# Map pin, its point on `at`.
			var head := at + Vector2(0, -16)
			var pin := PackedVector2Array([at, head + Vector2(8, 3), head + Vector2(-8, 3)])
			ci.draw_colored_polygon(_grow(pin, head, 3.0), out)
			ci.draw_circle(head, 11.0, out)
			ci.draw_colored_polygon(pin, UiTokens.PING)
			ci.draw_circle(head, 9.0, UiTokens.PING)
			ci.draw_circle(head, 3.5, UiTokens.INK)
		&"route":
			for i in 3:
				var x := at.x - 14 + i * 11
				ci.draw_line(Vector2(x, at.y), Vector2(x + 7, at.y), out, 6.0)
				ci.draw_line(Vector2(x, at.y), Vector2(x + 7, at.y), UiTokens.INFO, 3.5)


func _draw_route(a: Vector2, b: Vector2, label: String, font: Font) -> void:
	var dir := (b - a).normalized()
	var length := a.distance_to(b)
	var t := 0.0
	while t < length:
		var s := a + dir * t
		var e := a + dir * minf(t + 9.0, length)
		_ink.draw_line(s, e, Color(0, 0, 0, 0.8), 6.0)
		_ink.draw_line(s, e, UiTokens.INFO, 3.5)
		t += 15.0
	var side := Vector2(-dir.y, dir.x)
	var head := PackedVector2Array([b, b - dir * 14 + side * 8, b - dir * 14 - side * 8])
	_ink.draw_colored_polygon(head, UiTokens.INFO)
	_ink.draw_circle(a, 5, UiTokens.INFO)
	_place_label((a + b) * 0.5 + side * 40, label, font, UiTokens.INFO.lightened(0.35))


func _draw_player(at: Vector2) -> void:
	var f := player_dir
	var side := Vector2(-f.y, f.x)
	var arrow := PackedVector2Array([at + f * 16, at - f * 10 + side * 11, at - f * 4, at - f * 10 - side * 11])
	_ink.draw_colored_polygon(_grow(arrow, at, 3.0), Color(0, 0, 0, 0.85))
	_ink.draw_colored_polygon(arrow, UiTokens.TEXT)
	_ink.draw_arc(at, 24, 0, TAU, 40, Color(UiTokens.INFO, 0.8), 2.0, true)


func _text(pos: Vector2, text: String, font: Font, fs: int, color: Color) -> void:
	_ink.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
	_ink.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


static func _grow(poly: PackedVector2Array, centre: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		var d := p - centre
		out.append(centre + d + d.normalized() * by)
	return out
