class_name RelationGraph
extends Control
## Relation map (D-13, design 14 "관계도": 주민은 점, 관계는 선). Owner: Lane D.
## Each stage has its own line *shape* (UI_RULES §1.6 — never colour alone):
##   앙숙 지그재그 · 서먹함 긴 점선 · 아는 사이 잔 점선 · 친구 실선 · 절친 굵은 실선 ·
##   연인 이중선 · 배우자 이중선 + 고리 두 개 · 헤어짐 끊긴 선
## Residents sit on an ellipse; the selected one is larger and its lines carry stage labels.
## Data comes from Colony.relations_of() through set_data(); nothing is computed here.

signal resident_selected(resident_id: StringName)

const STAGE_ORDER: Array[StringName] = [&"married", &"lover", &"best_friend", &"friend", &"acquainted",
	&"awkward", &"rival"]
const NODE_R := 30.0
const NODE_R_SEL := 40.0

## [{id, name, color}] and [{a, b, stage}]
var nodes: Array = []
var edges: Array = []
var selected: StringName = &""
var _pos: Dictionary = {}


func set_data(node_list: Array, edge_list: Array, sel: StringName = &"") -> void:
	nodes = node_list
	edges = edge_list
	selected = sel
	_layout()
	queue_redraw()


func node_position(id: StringName) -> Vector2:
	return _pos.get(id, Vector2.ZERO)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()


func _layout() -> void:
	_pos.clear()
	var n := nodes.size()
	var c := size / 2.0
	var rad := Vector2(maxf(size.x / 2.0 - 110.0, 60.0), maxf(size.y / 2.0 - 80.0, 60.0))
	for i in n:
		var a := -PI / 2.0 + TAU * float(i) / float(maxi(n, 1))
		_pos[StringName(nodes[i].id)] = c + Vector2(cos(a) * rad.x, sin(a) * rad.y) if n > 1 else c


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for id: StringName in _pos:
			if (event.position as Vector2).distance_to(_pos[id]) <= NODE_R_SEL:
				selected = id
				queue_redraw()
				resident_selected.emit(id)
				accept_event()
				return


func _draw() -> void:
	var font := UiThemeBuilder.font_kr(600)
	# Lines under the dots: unrelated ones dimmed while someone is selected.
	for e: Dictionary in edges:
		var a := StringName(e.a)
		var b := StringName(e.b)
		if not (_pos.has(a) and _pos.has(b)):
			continue
		var on := selected == &"" or a == selected or b == selected
		var p0: Vector2 = _pos[a]
		var p1: Vector2 = _pos[b]
		var dir := (p1 - p0).normalized()
		p0 += dir * NODE_R
		p1 -= dir * NODE_R
		draw_stage_line(self, p0, p1, StringName(e.stage), 1.0, 1.0 if on else 0.22)
		if on and selected != &"":
			var mid := (p0 + p1) / 2.0
			var text := stage_name(StringName(e.stage))
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18
			var r := Rect2(mid - Vector2(w / 2.0, 13), Vector2(w, 26))
			draw_style_box(_chip_box(stage_color(StringName(e.stage))), r)
			draw_string(font, r.position + Vector2(9, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTokens.TEXT)
	for nd: Dictionary in nodes:
		var id := StringName(nd.id)
		var p: Vector2 = _pos.get(id, Vector2.ZERO)
		var sel := id == selected
		var r := NODE_R_SEL if sel else NODE_R
		if sel:
			draw_circle(p, r + 8, Color(UiTokens.ACCENT, 0.25))
		draw_circle(p, r, Color(nd.get("color", Color("c98f52"))))
		draw_arc(p, r, 0, TAU, 48, UiTokens.ACCENT if sel else UiTokens.TEXT, 3.0 if sel else 2.0, true)
		var nm := String(nd.get("name", ""))
		var initial := nm.substr(0, 1) if nm != "" else "?"
		var isz := int(r * 0.8)
		var iw := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, isz).x
		draw_string(font, p + Vector2(-iw / 2.0, isz * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, isz, Color("1d1a17"))
		var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var np := p + Vector2(-nw / 2.0, r + 24)
		draw_string(font, np + Vector2(1, 2), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTokens.SHADOW)
		draw_string(font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTokens.ACCENT if sel else UiTokens.TEXT)


func _chip_box(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.INK, 0.85)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(99)
	return sb


static func stage_name(stage: StringName) -> String:
	return String(RelationRules.STAGE_NAMES.get(stage, stage))


static func stage_color(stage: StringName) -> Color:
	match stage:
		&"rival":
			return UiTokens.DANGER
		&"awkward":
			return UiTokens.WARN
		&"acquainted":
			return Color(UiTokens.TEXT_DIM, 0.8)
		&"friend":
			return UiTokens.TEXT
		&"best_friend":
			return UiTokens.INFO
		&"lover", &"married":
			return UiTokens.ACCENT
	return UiTokens.TEXT_DIM


## Draws one relation line in the stage's shape. Also used by the legend samples.
static func draw_stage_line(ci: CanvasItem, p0: Vector2, p1: Vector2, stage: StringName, k := 1.0, alpha := 1.0) -> void:
	var col := Color(stage_color(stage), stage_color(stage).a * alpha)
	var d := p1 - p0
	var dist := d.length()
	if dist < 1.0:
		return
	var dir := d / dist
	var nrm := Vector2(-dir.y, dir.x)
	match stage:
		&"rival":
			var pts := PackedVector2Array()
			var step := 12.0 * k
			var count := maxi(int(dist / step), 2)
			for i in count + 1:
				var t := float(i) / float(count)
				var off := 0.0 if i == 0 or i == count else (6.0 * k if i % 2 == 0 else -6.0 * k)
				pts.append(p0 + d * t + nrm * off)
			ci.draw_polyline(pts, col, 2.5 * k, true)
		&"awkward":
			ci.draw_dashed_line(p0, p1, col, 2.5 * k, 12.0 * k, true)
		&"acquainted":
			ci.draw_dashed_line(p0, p1, col, 2.0 * k, 3.0 * k, true)
		&"friend":
			ci.draw_line(p0, p1, col, 2.5 * k, true)
		&"best_friend":
			ci.draw_line(p0, p1, col, 6.0 * k, true)
		&"lover", &"married":
			ci.draw_line(p0 + nrm * 3.5 * k, p1 + nrm * 3.5 * k, col, 2.0 * k, true)
			ci.draw_line(p0 - nrm * 3.5 * k, p1 - nrm * 3.5 * k, col, 2.0 * k, true)
			if stage == &"married":
				var mid := (p0 + p1) / 2.0
				for s in [-1.0, 1.0]:
					var c: Vector2 = mid + dir * 6.0 * k * s
					ci.draw_circle(c, 7.0 * k, Color(UiTokens.INK, 0.9 * alpha))
					ci.draw_arc(c, 7.0 * k, 0, TAU, 24, col, 2.0 * k, true)
		_:
			# separated / unknown: a broken line with a gap in the middle.
			ci.draw_line(p0, p0 + d * 0.4, col, 2.0 * k, true)
			ci.draw_line(p0 + d * 0.6, p1, col, 2.0 * k, true)


## Legend sample: a short line in a stage's shape.
class LineSample extends Control:
	var stage: StringName

	func _init(s: StringName) -> void:
		stage = s
		custom_minimum_size = Vector2(72, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		RelationGraph.draw_stage_line(self, Vector2(4, size.y / 2.0), Vector2(size.x - 4, size.y / 2.0), stage, 0.85)
