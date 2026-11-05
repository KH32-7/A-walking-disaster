class_name WorldMarkers
extends Control
## World-anchored field markers (D-05). Owner: Lane D. Rules: ui/UI_RULES.md §7.
## - Noise rings from EventBus.noise_emitted: white < 6 m, orange < 15 m, red beyond; 2/4/6 px;
##   grow and fade over 0.7 s, drawn flat on the ground through the active Camera3D.
##   Settings.noise_rings turns them off.
## - Monster state marks above monsters in group "field_monsters": "?" yellow circle for
##   SUSPICIOUS / INVESTIGATE, "!" red triangle for CHASE / ATTACK (black outline on any background).
##   Updated from each monster's `state_changed` signal (B-07); the first value is read once.
## - Edge arrows: noises and alerted monsters outside the view leave an arrow on the screen edge
##   (Settings.sound_arrows). Shape + colour + a short label, never colour alone.
## Computes no game rules: radius and states come from Lane B.

const RING_SEC := 0.7
const ARROW_SEC := 1.6
const EDGE_PAD := 60.0
## Edge arrows stay inside this inset so they never sit on the timer/objectives (top) or the vitals (bottom).
const ARROW_INSET := {"left": 70.0, "right": 70.0, "top": 140.0, "bottom": 210.0}
const MARK_HEIGHT := 2.3
const RING_STEPS := 40

var _rings: Array[Dictionary] = []  # {pos: Vector3, radius: float, t: float}
var _arrows: Array[Dictionary] = []  # {pos: Vector3, t: float, kind: StringName, label: String}
var _states: Dictionary = {}  # instance_id -> Enums.AIState
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiThemeBuilder.font_num()
	EventBus.noise_emitted.connect(_on_noise)


## Public for previews/tests: same as receiving EventBus.noise_emitted.
func add_noise(pos: Vector3, radius: float) -> void:
	_on_noise(pos, radius, null)


func ring_count() -> int:
	return _rings.size()


static func ring_style(radius: float) -> Array:
	if radius < 6.0:
		return [Color(1, 1, 1, 0.9), 2.0]
	if radius < 15.0:
		return [Color("ffaa46"), 4.0]
	return [Color("ff5a4e"), 6.0]


static func mark_for(state: int) -> StringName:
	match state:
		Enums.AIState.SUSPICIOUS, Enums.AIState.INVESTIGATE:
			return &"suspicious"
		Enums.AIState.CHASE, Enums.AIState.ATTACK:
			return &"alert"
	return &""


func _on_noise(pos: Vector3, radius: float, _source: Node) -> void:
	if radius <= 0.0:
		return
	if bool(Settings.get_value(&"noise_rings")):
		_rings.append({"pos": pos, "radius": radius, "t": 0.0})
	if bool(Settings.get_value(&"sound_arrows")) and radius >= 6.0:
		_arrows.append({"pos": pos, "t": 0.0, "kind": &"noise", "label": "%dm" % roundi(radius)})


func _process(delta: float) -> void:
	for r in _rings:
		r.t += delta
	_rings = _rings.filter(func(r: Dictionary) -> bool: return r.t < RING_SEC)
	for a in _arrows:
		a.t += delta
	_arrows = _arrows.filter(func(a: Dictionary) -> bool: return a.t < ARROW_SEC)
	for m in get_tree().get_nodes_in_group(&"field_monsters"):
		var id := m.get_instance_id()
		if _states.has(id):
			continue
		_states[id] = int(m.get(&"state")) if &"state" in m else 0
		if m.has_signal(&"state_changed"):
			m.state_changed.connect(func(_o: int, n: int) -> void: _states[id] = n)
		m.tree_exiting.connect(func() -> void: _states.erase(id))
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var view := Rect2(Vector2.ZERO, size)
	for r in _rings:
		_draw_ring(cam, r)
	for m in get_tree().get_nodes_in_group(&"field_monsters"):
		var kind := mark_for(int(_states.get(m.get_instance_id(), 0)))
		if kind == &"" or not m is Node3D:
			continue
		var wp: Vector3 = (m as Node3D).global_position + Vector3.UP * MARK_HEIGHT
		if not cam.is_position_behind(wp) and view.grow(-EDGE_PAD).has_point(cam.unproject_position(wp)):
			_draw_mark(cam.unproject_position(wp), kind)
		elif bool(Settings.get_value(&"sound_arrows")):
			_draw_edge_arrow(cam, wp, kind, "!" if kind == &"alert" else "?", 1.0)
	for a in _arrows:
		var p: Vector3 = a.pos
		if cam.is_position_behind(p) or not view.grow(-EDGE_PAD).has_point(cam.unproject_position(p)):
			_draw_edge_arrow(cam, p, a.kind, a.label, 1.0 - a.t / ARROW_SEC)


func _draw_ring(cam: Camera3D, r: Dictionary) -> void:
	var k: float = r.t / RING_SEC
	var grow := minf(1.0, k * 1.6)
	var radius: float = r.radius * grow
	var style := ring_style(r.radius)
	var col: Color = style[0]
	col.a *= 1.0 - k
	var pts := PackedVector2Array()
	for i in RING_STEPS + 1:
		var a := TAU * i / RING_STEPS
		var wp: Vector3 = r.pos + Vector3(cos(a) * radius, 0.05, sin(a) * radius)
		if cam.is_position_behind(wp):
			return
		pts.append(cam.unproject_position(wp))
	draw_polyline(pts, Color(0, 0, 0, col.a * 0.35), float(style[1]) + 2.0, true)
	draw_polyline(pts, col, float(style[1]), true)


func _draw_mark(at: Vector2, kind: StringName) -> void:
	if kind == &"suspicious":
		draw_circle(at, 17.0, Color("ffc35a"))
		draw_arc(at, 17.0, 0, TAU, 32, Color("151515"), 3.0, true)
		_center_text(at + Vector2(0, 1), "?", 22, Color("151515"))
	else:
		var tri := PackedVector2Array([at + Vector2(0, -21), at + Vector2(20, 14), at + Vector2(-20, 14)])
		draw_colored_polygon(tri, Color("ff5b4d"))
		tri.append(tri[0])
		draw_polyline(tri, Color("151515"), 3.0, true)
		_center_text(at + Vector2(0, 3), "!", 22, Color.WHITE)


func _draw_edge_arrow(cam: Camera3D, wp: Vector3, kind: StringName, label: String, alpha: float) -> void:
	var box := Rect2(Vector2(ARROW_INSET.left, ARROW_INSET.top),
		size - Vector2(ARROW_INSET.left + ARROW_INSET.right, ARROW_INSET.top + ARROW_INSET.bottom))
	var c := box.get_center()
	var sp := cam.unproject_position(wp)
	var dir := (sp - c)
	if cam.is_position_behind(wp):
		dir = -dir
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var half := box.size * 0.5
	var t := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var at := c + dir * t
	var col := Color("ff5b4d") if kind == &"alert" else (Color("ffc35a") if kind == &"suspicious" else Color("ffaa46"))
	col.a *= alpha
	var side := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([at + dir * 18.0, at - dir * 10.0 + side * 14.0, at - dir * 10.0 - side * 14.0])
	draw_colored_polygon(tri, col)
	tri.append(tri[0])
	draw_polyline(tri, Color(0, 0, 0, 0.8 * alpha), 2.0, true)
	_center_text(at - dir * 34.0, label, 17, Color(1, 1, 1, alpha), true)


func _center_text(at: Vector2, text: String, fs: int, col: Color, shadow := false) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := at + Vector2(-w * 0.5, (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5)
	if shadow:
		draw_string(_font, base + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, col.a * 0.7))
	draw_string(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
