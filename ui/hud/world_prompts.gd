class_name WorldPrompts
extends Control
## Things drawn next to their place in the world, field and base alike (QA 플레이 준비).
## Owner: Lane D. UI_RULES §4 "월드 위": `[키] 행동` one line, 거리 표시 `◆ 탈출 42m`.
##   - [F] 열기 / [F] 이야기하기 …: a chip beside whatever the player can use right now
##     (Player.interact_target() + its interact_label(), Lane B / C).
##   - 탈출 지점: green diamond above every active ExtractPoint with its kind and distance, e.g.
##     "탈출 · 42m", "열쇠 필요 · 120m". Off screen it stays on the screen edge.
## Reads only; the rules (reach, which points are active, what each needs) are the field's.

const CHIP_HEIGHT := 1.9  # m above the interactable's origin
const EXIT_HEIGHT := 3.2
## Edge marks stay clear of the minimap (top left) and the weapon / skill stack (bottom right).
const EDGE := {"left": 70.0, "right": 110.0, "top": 280.0, "bottom": 280.0}
const NEEDS := {ExtractPoint.Type.KEY: "열쇠 필요", ExtractPoint.Type.BATTERY: "배터리 필요"}

var _chip: PanelContainer
var _chip_label: Label
var _chip_key: KeyChip
var _chip_sub: Label
var _font: Font
## Hold progress (0..1) drawn as a ring around the [F] key while opening / helping, -1 = none.
var _hold_progress := -1.0
var _ring: Control  # drawn above the chip


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiThemeBuilder.font_kr(600)
	_chip = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.INK, 0.78)
	sb.set_corner_radius_all(99)
	sb.content_margin_left = 6
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_chip.add_theme_stylebox_override(&"panel", sb)
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_key = KeyChip.new("F")
	h.add_child(_chip_key)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override(&"separation", 0)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_label = MenuScreen.label("", &"LabelHud", 17)
	lines.add_child(_chip_label)
	_chip_sub = MenuScreen.label("", &"LabelHud", 14)
	_chip_sub.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	_chip_sub.visible = false
	lines.add_child(_chip_sub)
	h.add_child(lines)
	_chip.add_child(h)
	add_child(_chip)
	_chip.visible = false
	_ring = Control.new()
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	add_child(_ring)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var menu := not UI.stack_ids().is_empty()
	var base_cam := cam as BaseCamera
	visible = cam != null and (player != null or base_cam != null) and not menu and GameState.flow_state != Enums.FlowState.TITLE
	if not visible:
		return
	if base_cam != null:
		_update_click_chip(base_cam)
	else:
		_update_chip(cam, player)
	queue_redraw()
	_ring.queue_redraw()


## Base: no player — "[클릭] 서하은 · 이야기하기" beside whatever is under the mouse (BaseCamera.hover).
func _update_click_chip(cam: BaseCamera) -> void:
	_hold_progress = -1.0
	var h := cam.hover
	_chip.visible = not h.is_empty()
	if not _chip.visible:
		return
	_chip_key.key_text = "클릭"
	_chip_label.text = String(h["text"])
	_chip_sub.text = String(h.get("sub", ""))
	_chip_sub.visible = _chip_sub.text != ""
	var p := cam.unproject_position(Vector3(h["pos"]) + Vector3.UP * CHIP_HEIGHT)
	var sz := _chip.get_combined_minimum_size()
	_chip.size = sz
	_chip.position = Vector2(p.x + 18.0, p.y - sz.y * 0.5)


func _update_chip(cam: Camera3D, player: Node3D) -> void:
	var target: Node3D = player.call(&"interact_target") if player.has_method(&"interact_target") else null
	var text := String(target.call(&"interact_label")) if target != null and target.has_method(&"interact_label") else ""
	# Hidden only while something is being held / channelled (open bar, revive): interacting() keeps
	# the last thing used, so it alone would hide every prompt after the first chest.
	var using: Node = player.call(&"interacting") if player.has_method(&"interacting") else null
	var hold := using != null and using.has_method(&"hold_state") and not (using.call(&"hold_state") as Dictionary).is_empty()
	# While holding (opening a lock or door, helping someone up): the chip stays on that thing with
	# the label and percent, and a ring fills around the [F] key (user request 2026-11-06: the head
	# bar was hard to see). Field and intro house alike.
	_hold_progress = -1.0
	if hold:
		var hs: Dictionary = using.call(&"hold_state")
		_hold_progress = clampf(float(hs.get("progress", 0.0)), 0.0, 1.0)
		text = "%s %d%%" % [String(hs.get("label", "")), roundi(_hold_progress * 100.0)]
		target = using as Node3D
	_chip.visible = text != "" and target != null
	if not _chip.visible:
		return
	_chip_key.key_text = "F"
	_chip_label.text = text
	_chip_sub.visible = false
	var at := target.global_position + Vector3.UP * CHIP_HEIGHT
	if cam.is_position_behind(at):
		_chip.visible = false
		return
	var p := cam.unproject_position(at)
	var sz := _chip.get_combined_minimum_size()
	_chip.size = sz
	_chip.position = Vector2(p.x + 18.0, p.y - sz.y * 0.5)  # just right of the thing, at its height


## Ring around the [F] key: dark track, accent arc from 12 o'clock clockwise.
const RING_GAP := 6.0
const RING_WIDTH := 4.0

func _draw_ring() -> void:
	if _hold_progress < 0.0 or not _chip.visible:
		return
	var key := _chip_key.get_global_rect()
	var c := get_global_transform().affine_inverse() * key.get_center()
	var r := maxf(key.size.x, key.size.y) * 0.5 + RING_GAP
	_ring.draw_arc(c, r, 0.0, TAU, 48, Color(0, 0, 0, 0.7), RING_WIDTH + 3.0, true)
	if _hold_progress > 0.0:
		_ring.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * _hold_progress, 48, UiTokens.ACCENT, RING_WIDTH, true)


## Closer than this (m) the player is on the exit: its marker would sit on the hold bar, so it hides.
const ON_EXIT_M := 3.0

func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if cam == null or player == null:
		return
	var em := get_tree().get_first_node_in_group(&"field_extraction")
	if em == null or not em.has_method(&"active_points"):
		return
	var vp := get_viewport_rect().size
	for point: ExtractPoint in em.call(&"active_points"):
		var need := String(NEEDS.get(point.type, ""))
		if need != "" and Bag.count_of(ExtractionManager.REQUIRED_ITEM[point.type]) > 0:
			need = ""  # the bag has it now
		var dist := Vector2(point.global_position.x - player.global_position.x,
			point.global_position.z - player.global_position.z).length()
		if dist < ON_EXIT_M:
			continue  # standing on it: the hold bar over the head says 탈출 대기 중 (2026-11-06)
		var label := "%s / %dm" % [need if need != "" else "탈출", roundi(dist)]
		var at := point.global_position + Vector3.UP * EXIT_HEIGHT
		var behind := cam.is_position_behind(at)
		var p := cam.unproject_position(at)
		var inside := not behind and p.x > EDGE.left and p.x < vp.x - EDGE.right and p.y > EDGE.top and p.y < vp.y - EDGE.bottom
		if not inside:
			if behind:
				p = vp - p
			p = Vector2(clampf(p.x, EDGE.left, vp.x - EDGE.right), clampf(p.y, EDGE.top, vp.y - EDGE.bottom))
		_diamond(p, 18.0 if inside else 12.0, need != "")
		var fs := 16
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := Vector2(p.x - w * 0.5, p.y + 40.0)
		draw_string_outline(_font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
		draw_string(_font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTokens.WARN if need != "" else UiTokens.TEXT)


## Green diamond (UI_RULES §4 탈출 마름모: GOOD). A locked one gets a WARN rim: colour plus the words.
func _diamond(at: Vector2, r: float, locked: bool) -> void:
	var pts := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	var outer := PackedVector2Array()
	for q in pts:
		outer.append(at + (q - at) * ((r + 3.0) / r))
	draw_colored_polygon(outer, Color(0, 0, 0, 0.85))
	draw_colored_polygon(pts, UiTokens.WARN if locked else UiTokens.GOOD)
	var inner := PackedVector2Array()
	for q in pts:
		inner.append(at + (q - at) * 0.45)
	draw_colored_polygon(inner, UiTokens.INK)
