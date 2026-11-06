class_name WorldMarkers
extends Control
## World-anchored field markers (D-05). Owner: Lane D. Rules: ui/UI_RULES.md §7.
## - No noise rings on the ground (user 2026-11-06: turn the circle under the character off for
##   good). Noise still works for monsters; off-screen noises keep only the edge arrow below.
## - Monster state marks above monsters in group "field_monsters": "?" yellow circle for
##   SUSPICIOUS / INVESTIGATE, "!" red triangle for CHASE / ATTACK (black outline on any background).
##   Updated from each monster's `state_changed` signal (B-07); the first value is read once.
## - Edge arrows: noises and alerted monsters outside the view leave an arrow on the screen edge
##   (Settings.sound_arrows). Shape + colour + a short label, never colour alone.
## - Map ping (FieldState.ping): pin on the spot when on screen, else a ground arrow at the
##   player's feet. Distance beside it.
## - Speech bubbles: a rescue target (group "field_rescue_targets") that hears the player calls
##   out (`called_out` signal, B-10). Cream bubble above the person for 3.5 s, also through walls;
##   off screen, a cream edge arrow "목소리". Companions (group "field_companions") use the same
##   signal for their signature skill line (B-29).
## - Quest objectives (Quests.active_field_objectives, node named `marker`): the double yellow
##   diamond of the minimap / M map floats over the spot with the distance under it; off screen, a
##   yellow edge arrow with the diamond. Hidden within OBJ_HIDE_M, where the place takes over.
##   The words (marker_label) come once per sortie only: a banner at the top centre, diamond +
##   words, for BANNER_SEC (사용자 요청 2026-11-06: explain briefly, then just the symbol).
## Computes no game rules: radius and states come from Lane B.

const ARROW_SEC := 1.6
const EDGE_PAD := 60.0
## Edge arrows stay inside this inset so they never sit on the timer/objectives (top) or the vitals (bottom).
const ARROW_INSET := {"left": 70.0, "right": 70.0, "top": 140.0, "bottom": 210.0}
const MARK_HEIGHT := 2.3
## Ping arrow: starts this far from the player's feet (m), 0.6 m long.
const PING_ARROW_M := 1.4
const RESCUE_GROUP := &"field_rescue_targets"
const COMPANION_GROUP := &"field_companions"
const BUBBLE_SEC := 3.5
const BUBBLE_FADE_SEC := 0.4
const BUBBLE_HEIGHT := 2.1
const BUBBLE_FS := 17
const BUBBLE_PAD := Vector2(12.0, 7.0)
const BUBBLE_TAIL := 10.0
const VOICE_LABEL := "목소리"
## Quest objective diamond: metres above the marker, hidden this close (flat metres).
const OBJ_HEIGHT := 4.5
const OBJ_HIDE_M := 9.0
## The one-time objective banner: seconds on screen, fade in / out, size, top of the banner (px,
## below the edge arrows' top inset so it never sits on an objective arrow).
const BANNER_SEC := 4.5
const BANNER_FADE := 0.4
const BANNER_FS := 22
const BANNER_TOP := 250.0

var _arrows: Array[Dictionary] = []  # {pos: Vector3, t: float, kind: StringName, label: String}
var _states: Dictionary = {}  # instance_id -> Enums.AIState
var _bubbles: Array[Dictionary] = []  # {node: Node3D, text: String, t: float}
var _voiced: Dictionary = {}  # instance_id of rescue targets already connected
var _font: Font
var _font_kr: Font
var _bubble_box := StyleBoxFlat.new()
var _marker_cache: Dictionary = {}  # marker name -> Node3D
var _banner_seen: Dictionary = {}  # "quest_id/objective_id" -> sortie_seed it was shown in
var _banners: Array[Dictionary] = []  # {text, t}; the first one is on screen
var _banner_ci: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiThemeBuilder.font_num()
	_font_kr = UiThemeBuilder.font_kr(500)
	_bubble_box.set_corner_radius_all(UiTokens.BAND_RADIUS)
	_bubble_box.set_border_width_all(2)
	EventBus.noise_emitted.connect(_on_noise)
	_banner_ci = Control.new()
	_banner_ci.name = "ObjectiveBanner"
	_banner_ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_ci.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner_ci.visible = false
	_banner_ci.draw.connect(_on_banner_draw)
	add_child(_banner_ci)


## Public for previews/tests: same as receiving EventBus.noise_emitted.
func add_noise(pos: Vector3, radius: float) -> void:
	_on_noise(pos, radius, null)


## Public for previews/tests: same as `node` emitting called_out(text). One bubble per person.
func add_bubble(node: Node3D, text: String) -> void:
	_bubbles = _bubbles.filter(func(b: Dictionary) -> bool: return b.node != node)
	_bubbles.append({"node": node, "text": text, "t": 0.0})


func bubble_texts() -> Array[String]:
	var out: Array[String] = []
	for b in _bubbles:
		out.append(String(b.text))
	return out


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
	if bool(Settings.get_value(&"sound_arrows")) and radius >= 6.0:
		_arrows.append({"pos": pos, "t": 0.0, "kind": &"noise", "label": "%dm" % roundi(radius)})


func _process(delta: float) -> void:
	for a in _arrows:
		a.t += delta
	_arrows = _arrows.filter(func(a: Dictionary) -> bool: return a.t < ARROW_SEC)
	if not _banners.is_empty() and get_tree().get_first_node_in_group(&"player") != null 			and not UI.is_open(&"loading"):
		_banners[0].t += delta
		if _banners[0].t >= BANNER_SEC:
			_banners.pop_front()
	for b in _bubbles:
		b.t += delta
	_bubbles = _bubbles.filter(func(b: Dictionary) -> bool:
		return b.t < BUBBLE_SEC and is_instance_valid(b.node) and (b.node as Node).is_inside_tree())
	for r in get_tree().get_nodes_in_group(RESCUE_GROUP) + get_tree().get_nodes_in_group(COMPANION_GROUP):
		var rid := r.get_instance_id()
		if _voiced.has(rid) or not r is Node3D or not r.has_signal(&"called_out"):
			continue
		_voiced[rid] = true
		r.connect(&"called_out", func(text: String, _near: bool) -> void: add_bubble(r, text))
		r.tree_exiting.connect(func() -> void: _voiced.erase(rid))
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
	_draw_ping(cam, view)
	_draw_objectives(cam, view)
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
	for b in _bubbles:
		var wp: Vector3 = (b.node as Node3D).global_position + Vector3.UP * BUBBLE_HEIGHT
		var alpha := clampf((BUBBLE_SEC - float(b.t)) / BUBBLE_FADE_SEC, 0.0, 1.0)
		if not cam.is_position_behind(wp) and view.grow(-EDGE_PAD).has_point(cam.unproject_position(wp)):
			_draw_bubble(cam.unproject_position(wp), String(b.text), alpha)
		else:
			_draw_edge_arrow(cam, wp, &"voice", VOICE_LABEL, alpha)


## Cream bubble whose tail points down at `at` (above the person's head).
func _draw_bubble(at: Vector2, text: String, alpha: float) -> void:
	var text_size := Vector2(_font_kr.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FS).x,
		_font_kr.get_height(BUBBLE_FS))
	var box_size := text_size + BUBBLE_PAD * 2.0
	var rect := Rect2(at - Vector2(box_size.x * 0.5, box_size.y + BUBBLE_TAIL), box_size)
	var bg := UiTokens.CREAM
	bg.a = alpha
	var edge := Color(0, 0, 0, 0.8 * alpha)
	var tail := PackedVector2Array([Vector2(at.x - 8.0, rect.end.y - 1.0), at, Vector2(at.x + 8.0, rect.end.y - 1.0)])
	draw_polyline(tail, edge, 4.0, true)
	_bubble_box.bg_color = bg
	_bubble_box.border_color = edge
	draw_style_box(_bubble_box, rect)
	draw_colored_polygon(tail, bg)
	var ink := UiTokens.TEXT_ON_CREAM
	ink.a = alpha
	draw_string(_font_kr, rect.position + BUBBLE_PAD + Vector2(0.0, _font_kr.get_ascent(BUBBLE_FS)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FS, ink)


## Map ping (FieldState, set on the M map). On screen: a pin on the spot. Off screen: an arrow on
## the ground at the player's feet pointing at it. The distance sits beside either.
func _draw_ping(cam: Camera3D, view: Rect2) -> void:
	if not FieldState.has_ping:
		return
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	if p == null:
		return
	var target := FieldState.ping
	var flat := Vector3(target.x - p.global_position.x, 0.0, target.z - p.global_position.z)
	var label := "%dm" % roundi(flat.length())
	var sp := cam.unproject_position(target)
	if not cam.is_position_behind(target) and view.grow(-EDGE_PAD).has_point(sp):
		MapView.draw_symbol(self, sp, &"ping")
		_center_text(sp + Vector2(0, 18), label, 17, UiTokens.TEXT, true)
		return
	# Built flat on the ground in world space, then projected, so it lies on the floor.
	var dir := flat.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	var back := p.global_position + Vector3.UP * 0.05 + dir * PING_ARROW_M
	var tip := back + dir * 0.6
	var tri: Array[Vector3] = [tip, back + side * 0.35, back - side * 0.35]
	for w in tri:
		if cam.is_position_behind(w):
			return
	var pts := PackedVector2Array()
	for w in tri:
		pts.append(cam.unproject_position(w))
	draw_colored_polygon(pts, UiTokens.PING)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.8), 2.0, true)
	_center_text(cam.unproject_position(tip + dir * 0.6), label, 17, UiTokens.TEXT, true)


## Quest objectives in this region: diamond + distance on screen, edge arrow off it. The first
## time an objective shows in a sortie its words go to the banner queue.
func _draw_objectives(cam: Camera3D, view: Rect2) -> void:
	if FieldState.region_id == &"":
		_banners.clear()
		_banner_ci.visible = false
		return
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	for o: Dictionary in Quests.active_field_objectives(FieldState.region_id):
		var node := _find_marker(StringName(o.get("marker", &"")))
		if node == null:
			continue
		var key := "%s/%s" % [o.get("quest_id", &""), o.get("objective_id", &"")]
		if int(_banner_seen.get(key, -1)) != FieldState.sortie_seed:
			_banner_seen[key] = FieldState.sortie_seed
			var words := String(o.get("marker_label", ""))
			show_banner(words if words != "" else String(o.get("text", "")))
		var wp := node.global_position + Vector3.UP * OBJ_HEIGHT
		var dist := ""
		if p != null:
			var flat := Vector2(wp.x - p.global_position.x, wp.z - p.global_position.z).length()
			if flat < OBJ_HIDE_M:
				continue
			dist = "%dm" % roundi(flat)
		var sp := cam.unproject_position(wp)
		if not cam.is_position_behind(wp) and view.grow(-EDGE_PAD).has_point(sp):
			MapView.draw_symbol(self, sp, &"objective")
			_center_text(sp + Vector2(0, 32), dist, 15, UiTokens.TEXT, true)
		else:
			_draw_edge_arrow(cam, wp, &"objective", dist, 1.0)
	_draw_banner()


## Public for previews/tests: queue a one-time objective banner (diamond + words, top centre).
func show_banner(text: String) -> void:
	if text != "":
		_banners.append({"text": text, "t": 0.0})


func banner_text() -> String:
	return String(_banners[0].text) if not _banners.is_empty() else ""


## The banner draws on its own child so the whole of it (diamond included) fades with modulate.
func _draw_banner() -> void:
	_banner_ci.visible = not _banners.is_empty()
	if _banners.is_empty():
		return
	var t: float = _banners[0].t
	_banner_ci.modulate.a = clampf(minf(t / BANNER_FADE, (BANNER_SEC - t) / BANNER_FADE), 0.0, 1.0)
	_banner_ci.queue_redraw()


func _on_banner_draw() -> void:
	if _banners.is_empty():
		return
	var ci := _banner_ci
	var text := String(_banners[0].text)
	var w := _font_kr.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FS).x
	var box := Rect2(Vector2((ci.size.x - (w + 76.0)) * 0.5, BANNER_TOP), Vector2(w + 76.0, 48.0))
	ci.draw_rect(box, Color(0, 0, 0, 0.5))
	var mid := Vector2(box.position.x + 28.0, box.get_center().y)
	MapView.draw_symbol(ci, mid, &"objective")
	var base := Vector2(box.position.x + 54.0,
		mid.y + (_font_kr.get_ascent(BANNER_FS) - _font_kr.get_descent(BANNER_FS)) * 0.5)
	ci.draw_string_outline(_font_kr, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FS, 5, Color(0, 0, 0, 0.8))
	ci.draw_string(_font_kr, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FS, UiTokens.ACCENT)


func _find_marker(marker: StringName) -> Node3D:
	if marker == &"":
		return null
	var hit: Node3D = _marker_cache.get(marker)
	if hit != null and is_instance_valid(hit) and hit.is_inside_tree():
		return hit
	_marker_cache.erase(marker)
	for n: Node in get_tree().get_nodes_in_group(FieldMarker.GROUP_ALL):
		if n.name == marker and n is Node3D:
			hit = n
	if hit != null:
		_marker_cache[marker] = hit
	return hit


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


## Where an off-screen point's edge arrow sits: [at, dir] (screen px, unit), or [] when centred.
func _edge(cam: Camera3D, wp: Vector3) -> Array:
	var box := Rect2(Vector2(ARROW_INSET.left, ARROW_INSET.top),
		size - Vector2(ARROW_INSET.left + ARROW_INSET.right, ARROW_INSET.top + ARROW_INSET.bottom))
	var c := box.get_center()
	var sp := cam.unproject_position(wp)
	var dir := (sp - c)
	if cam.is_position_behind(wp):
		dir = -dir
	if dir.length() < 1.0:
		return []
	dir = dir.normalized()
	var half := box.size * 0.5
	var t := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	return [c + dir * t, dir]


func _draw_edge_arrow(cam: Camera3D, wp: Vector3, kind: StringName, label: String, alpha: float) -> void:
	var e := _edge(cam, wp)
	if e.is_empty():
		return
	var at: Vector2 = e[0]
	var dir: Vector2 = e[1]
	var col := Color("ff5b4d") if kind == &"alert" else (Color("ffc35a") if kind == &"suspicious" else Color("ffaa46"))
	if kind == &"voice":
		col = UiTokens.CREAM
	elif kind == &"objective":
		col = UiTokens.ACCENT
	col.a *= alpha
	var side := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([at + dir * 18.0, at - dir * 10.0 + side * 14.0, at - dir * 10.0 - side * 14.0])
	draw_colored_polygon(tri, col)
	tri.append(tri[0])
	draw_polyline(tri, Color(0, 0, 0, 0.8 * alpha), 2.0, true)
	if kind == &"objective":
		# The diamond inside the arrow, the distance under it.
		var d := at - dir * 36.0
		MapView.draw_symbol(self, d, &"objective")
		_center_text(d + Vector2(0, 30), label, 15, Color(1, 1, 1, alpha), true)
		return
	_center_text(at - dir * 34.0, label, 17, Color(1, 1, 1, alpha), true)


func _center_text(at: Vector2, text: String, fs: int, col: Color, shadow := false) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := at + Vector2(-w * 0.5, (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5)
	if shadow:
		draw_string(_font, base + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, col.a * 0.7))
	draw_string(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
