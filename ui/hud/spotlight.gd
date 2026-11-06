class_name Spotlight
extends Control
## Tutorial focus (사용자 요청 2026-11-06): the whole screen goes dark except a hole over the one thing
## to use now — a chest in the world (round hole) or a slot on a menu (rounded box) — with a short card
## beside it: "[F] 열기". Owner: Lane D. Sits on UI.overlay, above menus, and never takes the mouse:
## the player still clicks / presses keys on what is under the hole (and anywhere else).
##
## focus_world(node, ...) follows a Node3D through the active camera; focus_control(control, ...) and
## focus_rect(rect, ...) follow UI. clear() fades it away. Each new focus irises in from wide.

const DIM := 0.6  # 사용자 요청: 조금 더 비쳐 보이게
const FEATHER := 26.0
const IRIS_SEC := 0.55
const FADE_SEC := 0.25
const RING_COLOR := Color("f6c744")  # UiTokens.ACCENT
const CARD_GAP := 22.0
const CARD_W := 360.0
## Card-only at the bottom (focus_card(..., true)): its bottom edge this far above the screen bottom,
## clear of the field HUD's bottom-centre vitals.
const CARD_BOTTOM_Y := 140.0

const SHADER := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform vec4 hole = vec4(960.0, 540.0, 0.0, 0.0); // centre x, y, half w, half h
uniform float corner = 120.0;
uniform float feather = 26.0;
uniform float dim = 0.8;
void fragment() {
	vec2 p = UV * rect_size;
	vec2 q = abs(p - hole.xy) - hole.zw;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
	float a = smoothstep(-feather * 0.5, feather * 0.5, d);
	COLOR = vec4(0.0, 0.0, 0.0, a * dim);
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial
var _card: PanelContainer
var _text: Label
var _keys: HBoxContainer
var _target_node: Node3D
var _hole_on := false  # this frame has a hole (false = card only: no dark screen, no ring)
var _target_control: Control
var _target_rect := Rect2()
var _world_radius := 90.0
var _world_lift := 0.6
var _pad := 10.0
var _card_bottom := false  # card-only placement: bottom centre instead of top centre
var _card_above := false  # card above the hole (left of it when there is no room), not below
var _iris := 1.0  # 1 = hole wide open (just started), 0 = at its size
var _alpha := 0.0
var _alpha_to := 0.0
var _t := 0.0
## Hole on screen right now: centre and half size (+ corner radius).
var _hole := Rect2()
var _corner := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTokens.CREAM
	sb.set_corner_radius_all(10)
	sb.border_color = UiTokens.ACCENT
	sb.border_width_left = 6
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	_card.add_theme_stylebox_override(&"panel", sb)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text = MenuScreen.label("", &"LabelOnCream", 18)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(CARD_W - 36, 0)
	v.add_child(_text)
	_keys = HBoxContainer.new()
	_keys.add_theme_constant_override(&"separation", 14)
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_keys)
	_card.add_child(v)
	add_child(_card)
	visible = false


## Round hole over `node` (radius in px at 1080p), `lift` m above its origin.
func focus_world(node: Node3D, text: String, keys: Array = [], radius := 95.0, lift := 0.6) -> void:
	_begin(text, keys)
	_target_node = node
	_world_radius = radius
	_world_lift = lift


## Rounded box hole around a Control (menu slot, button), `pad` px bigger.
func focus_control(control: Control, text: String, keys: Array = [], pad := 10.0) -> void:
	_begin(text, keys)
	_target_control = control
	_pad = pad


## Rounded box hole over a fixed screen rect (a bag grid entry). above: the card goes above the
## hole (or to its left) instead of below, clear of a right-click menu that opens below the entry.
func focus_rect(rect: Rect2, text: String, keys: Array = [], pad := 10.0, above := false) -> void:
	_begin(text, keys)
	_target_rect = rect
	_pad = pad
	_card_above = above


## Card only, nothing to point at. at_bottom: bottom centre (monsters come from the top of the
## screen, user request 2026-11-06) instead of top centre under the top bar.
func focus_card(text: String, keys: Array = [], at_bottom := false) -> void:
	_begin(text, keys)
	_card_bottom = at_bottom


## Updates the rect of focus_rect() without restarting the iris (the menu moved).
func move_rect(rect: Rect2) -> void:
	_target_rect = rect


func clear() -> void:
	_alpha_to = 0.0
	_target_node = null
	_target_control = null
	_target_rect = Rect2()


func is_focusing() -> bool:
	return _alpha_to > 0.0


## Current focus text ("" = none). For tests and the playthrough bot.
func current_text() -> String:
	return _text.text if is_focusing() else ""


func _begin(text: String, keys: Array) -> void:
	_target_node = null
	_target_control = null
	_target_rect = Rect2()
	_card_bottom = false
	_card_above = false
	if _text.text != text or _alpha_to <= 0.0:
		_iris = 1.0
	_text.text = text
	for c in _keys.get_children():
		_keys.remove_child(c)
		c.queue_free()
	for k: Array in keys:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 6)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(KeyChip.new(String(k[0]), KeyChip.Style.DARK))
		h.add_child(MenuScreen.label(String(k[1]), &"LabelOnCreamDim", 15))
		_keys.add_child(h)
	_keys.visible = not keys.is_empty()
	_alpha_to = 1.0
	visible = true


func _process(delta: float) -> void:
	_t += delta
	_alpha = move_toward(_alpha, _alpha_to, delta / FADE_SEC)
	if _alpha <= 0.0 and _alpha_to <= 0.0:
		visible = false
		return
	_iris = move_toward(_iris, 0.0, delta / IRIS_SEC)
	var on := _find_hole()
	_hole_on = on
	var vp := size
	var ease_out := 1.0 - pow(1.0 - _iris, 3.0)  # big while starting, then settles
	var grow := ease_out * vp.length() * 0.6
	var pulse := sin(_t * 3.2) * 3.0
	var half := _hole.size * 0.5
	_mat.set_shader_parameter(&"rect_size", vp)
	_mat.set_shader_parameter(&"hole", Vector4(_hole.position.x, _hole.position.y, half.x, half.y))
	_mat.set_shader_parameter(&"corner", _corner + grow + pulse)
	_mat.set_shader_parameter(&"feather", FEATHER)
	# Target off screen (behind the camera, not built yet): only the card, no dark screen.
	_mat.set_shader_parameter(&"dim", DIM * _alpha if on else 0.0)
	_card.modulate.a = _alpha
	_place_card(on)
	queue_redraw()


func _draw() -> void:
	# Card only (a goal with nothing to point at): no ring. Without this the ring stayed on the last
	# hole's screen spot (user report 2026-11-06: a yellow circle around the player after the doctor).
	if _alpha <= 0.0 or _iris > 0.35 or not _hole_on:
		return
	# A thin yellow ring on the hole's rim: "here".
	var a := _alpha * (1.0 - _iris / 0.35) * (0.55 + 0.25 * sin(_t * 3.2))
	var c := Color(RING_COLOR, a)
	var half := _hole.size * 0.5
	var r := _corner + 2.0 + sin(_t * 3.2) * 3.0
	if half.length() < 1.0:
		draw_arc(_hole.position, r, 0.0, TAU, 64, c, 3.0, true)
	else:
		var box := Rect2(_hole.position - half - Vector2(r, r), (half + Vector2(r, r)) * 2.0)
		draw_rect(box, c, false, 3.0)


## Centre / half size of the hole this frame. False when the target cannot be seen.
func _find_hole() -> bool:
	if _target_node != null:
		if not is_instance_valid(_target_node):
			_target_node = null
			return false
		var cam := get_viewport().get_camera_3d()
		var at := _target_node.global_position + Vector3.UP * _world_lift
		if cam == null or cam.is_position_behind(at):
			return false
		# Canvas coordinates (the overlay layer is not scaled with the 3D view).
		var p := cam.unproject_position(at) / get_viewport().get_visible_rect().size * size
		_hole = Rect2(p, Vector2.ZERO)
		_corner = _world_radius * size.y / 1080.0
		return true
	var r := Rect2()
	if _target_control != null:
		if not is_instance_valid(_target_control) or not _target_control.is_visible_in_tree():
			return false
		r = _target_control.get_global_rect()
	elif _target_rect.size != Vector2.ZERO:
		r = _target_rect
	else:
		return false
	r = r.grow(_pad)
	_hole = Rect2(r.get_center(), r.size - Vector2(16, 16))
	_corner = 8.0
	return true


## The card goes below the hole, or above it near the bottom; never off screen.
func _place_card(on: bool) -> void:
	var sz := _card.get_combined_minimum_size()
	_card.size = sz
	var vp := size
	if not on:  # card only (a goal, no thing to point at): top centre under the top bar, or bottom
		_card.position = Vector2((vp.x - sz.x) * 0.5, vp.y - CARD_BOTTOM_Y - sz.y if _card_bottom else 96.0)
		return
	var half := _hole.size * 0.5 + Vector2(_corner, _corner)
	var pos := Vector2(_hole.position.x - sz.x * 0.5, _hole.position.y + half.y + CARD_GAP)
	if _card_above:  # above, else left of the hole (the bag's right-click menu opens below / right)
		pos.y = _hole.position.y - half.y - CARD_GAP - sz.y
		if pos.y < 24.0:
			pos = Vector2(_hole.position.x - half.x - CARD_GAP - sz.x, _hole.position.y - sz.y * 0.5)
		pos.x = clampf(pos.x, 24.0, vp.x - sz.x - 24.0)
		pos.y = clampf(pos.y, 24.0, vp.y - sz.y - 24.0)
		_card.position = pos
		return
	if pos.y + sz.y > vp.y - 24.0:
		pos.y = _hole.position.y - half.y - CARD_GAP - sz.y
	if pos.y < 24.0:  # tall hole (a whole panel): put it to the side
		pos = Vector2(_hole.position.x + half.x + CARD_GAP, _hole.position.y - sz.y * 0.5)
		if pos.x + sz.x > vp.x - 24.0:
			pos.x = _hole.position.x - half.x - CARD_GAP - sz.x
	pos.x = clampf(pos.x, 24.0, vp.x - sz.x - 24.0)
	pos.y = clampf(pos.y, 24.0, vp.y - sz.y - 24.0)
	_card.position = pos
