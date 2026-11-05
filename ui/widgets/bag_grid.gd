class_name BagGrid
extends Control
## Grid view of one Bag area (bag or safe pocket) with drag & drop (UI_RULES §5 칸, 메뉴 스킨).
## Owner: Lane D (D-08). Moves go through Bag.move(); the grid never edits entries itself.
## Drag: press on an item, release on a cell. R rotates while dragging. Invalid targets show red.
## Signals let the screen show tooltips / context menus.

signal hovered(entry: Dictionary, global_rect: Rect2)
signal unhovered()
signal context_requested(entry: Dictionary, at: Vector2)

const CELL := 72.0
const GAP := 6.0

@export var area := Bag.AREA_BAG

var _entries: Array = []
var _hover_id := -1
var _drag: Dictionary = {}  # {entry, rotated, grab: Vector2i}
var _mouse := Vector2.ZERO
var _pop: Dictionary = {}  # entry id -> time left of the pop-in animation
var _known: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	EventBus.bag_changed.connect(refresh)
	refresh()


func grid_cells() -> Vector2i:
	if area == Bag.AREA_POCKET:
		return Bag.POCKET_SIZE
	return Vector2i(Bag.grid_size.x, Bag.grid_size.y + (1 if Bag.bonus_cells > 0 else 0))


func _get_minimum_size() -> Vector2:
	var g := grid_cells()
	return Vector2(g.x * (CELL + GAP) - GAP, g.y * (CELL + GAP) - GAP)


func refresh() -> void:
	_entries = Bag.entries(area)
	for e: Dictionary in _entries:
		if not _known.has(e.id):
			_pop[e.id] = 0.2
		_known[e.id] = true
	update_minimum_size()
	queue_redraw()


func cell_rect(c: Vector2i, s: Vector2i = Vector2i.ONE) -> Rect2:
	return Rect2(Vector2(c) * (CELL + GAP), Vector2(s) * (CELL + GAP) - Vector2(GAP, GAP))


func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / (CELL + GAP)), floori(p.y / (CELL + GAP)))


func entry_at_point(p: Vector2) -> Dictionary:
	for e: Dictionary in _entries:
		if cell_rect(e.pos, e.size).has_point(p):
			return e
	return {}


func _process(delta: float) -> void:
	if _pop.is_empty():
		return
	for k in _pop.keys():
		_pop[k] -= delta
		if _pop[k] <= 0.0:
			_pop.erase(k)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		var e := entry_at_point(_mouse)
		var id := int(e.get("id", -1))
		if id != _hover_id:
			_hover_id = id
			if id >= 0 and _drag.is_empty():
				hovered.emit(e, Rect2(global_position + cell_rect(e.pos, e.size).position, cell_rect(e.pos, e.size).size))
			else:
				unhovered.emit()
		queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var e := entry_at_point(mb.position)
			if not e.is_empty():
				_drag = {"entry": e, "rotated": bool(e.rotated), "grab": cell_at(mb.position) - Vector2i(e.pos)}
				unhovered.emit()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not _drag.is_empty():
			_drop(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var e := entry_at_point(mb.position)
			if not e.is_empty():
				context_requested.emit(e, get_global_mouse_position())
		queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _drag.is_empty() and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_R:
		_drag.rotated = not _drag.rotated
		queue_redraw()
		get_viewport().set_input_as_handled()


func _drag_target() -> Dictionary:
	var e: Dictionary = _drag.entry
	var base: Vector2i = e.size if bool(e.rotated) == bool(_drag.rotated) else Vector2i(e.size.y, e.size.x)
	var pos := cell_at(_mouse) - Vector2i(_drag.grab)
	var ok := Bag.can_place(_base_size(e), pos, bool(_drag.rotated), area, int(e.id))
	return {"pos": pos, "size": base, "ok": ok}


func _base_size(e: Dictionary) -> Vector2i:
	return Vector2i(e.size.y, e.size.x) if bool(e.rotated) else Vector2i(e.size)


func _drop(at: Vector2) -> void:
	_mouse = at
	var t := _drag_target()
	if t.ok:
		Bag.move(int(_drag.entry.id), t.pos, bool(_drag.rotated), area)
	_drag = {}
	refresh()


## Drop from another grid (pocket <-> bag) is handled by the screen via Bag.move with the other area.
func is_dragging() -> bool:
	return not _drag.is_empty()


func _draw() -> void:
	var g := grid_cells()
	for y in g.y:
		for x in g.x:
			var c := Vector2i(x, y)
			if area == Bag.AREA_BAG and not Bag.is_cell(c, area):
				continue
			_slot_box(cell_rect(c), Color(0, 0, 0, 0.22), Color(1, 1, 1, 0.08), 1.0)
	for e: Dictionary in _entries:
		if not _drag.is_empty() and int(_drag.entry.id) == int(e.id):
			continue
		_draw_entry(e, cell_rect(e.pos, e.size), int(e.id) == _hover_id)
	if not _drag.is_empty():
		var t := _drag_target()
		var r := cell_rect(t.pos, t.size)
		_slot_box(r, Color(UiTokens.GOOD if t.ok else UiTokens.DANGER, 0.25),
			UiTokens.GOOD if t.ok else UiTokens.DANGER, 2.0)
		var ghost := (_drag.entry as Dictionary).duplicate()
		ghost.size = t.size
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_entry(ghost, Rect2(_mouse - Vector2(_drag.grab) * (CELL + GAP) - Vector2(CELL, CELL) * 0.5, r.size), true, 0.8)


func _draw_entry(e: Dictionary, r: Rect2, hot: bool, alpha := 1.0) -> void:
	var info := ItemInfo.for_entry(e)
	var rar := int(info.rarity)
	var k := 1.0
	if _pop.has(e.id):
		var t := 1.0 - float(_pop[e.id]) / 0.2
		k = lerpf(0.6, 1.0, t) + sin(t * PI) * 0.08
	r = Rect2(r.get_center() - r.size * 0.5 * k, r.size * k)
	var base := Color(0.33, 0.43, 0.53, 0.55 * alpha)
	_slot_box(r, base, UiTokens.LINE_STRONG if hot else Color(1, 1, 1, 0.18), 2.0 if hot else 1.5)
	if rar > 0:
		# Duckov accent: rarity colour rises from the bottom of the slot.
		var rc := UiTokens.rarity_color(rar)
		var steps := 10
		for i in steps:
			var y0 := r.position.y + r.size.y * (0.35 + 0.65 * i / steps)
			var h := r.size.y * 0.65 / steps + 1.0
			draw_rect(Rect2(r.position.x + 2, y0, r.size.x - 4, minf(h, r.end.y - y0 - 2)), Color(rc, 0.42 * alpha * (float(i) / steps)))
		ShapeBadge.draw_shape(self, UiTokens.rarity_shape(rar), Rect2(r.position + Vector2(6, 6), Vector2(12, 12)), Color(rc, alpha))
	var f := UiThemeBuilder.font_kr(700)
	var fn := UiThemeBuilder.font_num()
	var name := String(info.name)
	var fs := 12
	var w := r.size.x - 8
	var nm := name
	while nm.length() > 1 and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		nm = nm.left(nm.length() - 1)
	if nm != name:
		nm = nm.left(maxi(1, nm.length() - 1)) + "…"
	var big := minf(r.size.x, r.size.y) * 0.34
	var glyph := name.left(1)
	var gw := f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, int(big)).x
	draw_string(f, Vector2(r.get_center().x - gw * 0.5, r.get_center().y + big * 0.25), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(big), Color(1, 1, 1, 0.35 * alpha))
	draw_string(f, Vector2(r.position.x + 4, r.end.y - 6), nm, HORIZONTAL_ALIGNMENT_LEFT, w, fs, Color(UiTokens.TEXT, alpha))
	var cnt := int(info.get("count", 1))
	if cnt > 1:
		var t := "×%d" % cnt
		var tw := fn.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(fn, Vector2(r.end.x - tw - 5, r.position.y + 18), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UiTokens.TEXT, alpha))


func _slot_box(r: Rect2, bg: Color, border: Color, bw: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(bw))
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	draw_style_box(sb, r)
