class_name HudMinimap
extends Control
## Top-left minimap (design 14 "필드 HUD"; UI_RULES §4): line-only frame, no fill panel.
## Heading-up: the player is the centre, the arrow always points up, and the map (a live top-down
## render around the player) plus every mark turn and scroll as the player moves and turns.
## Kinds and their shape (never colour only): player=arrow, extract=diamond(GOOD),
## objective=square(ACCENT), companion=circle(INFO), monster_heard=triangle(DANGER),
## lost_gear=ring(TEXT). Owner: Lane D (D-04).
##
## Reads only (no game rules here), like MapScreen:
##   player: group "player", Player.facing() (falls back to the node's -Z)
##   ExtractionManager.active_points() (B-09), ExtractionManager.PARTY_GROUP (B-17, B-10)
##   Quests.active_field_objectives(region_id) (A-13) -> node named `marker`
##   FieldState.recoverable_gear() (B)
## Without a player in the tree (previews) it draws `points` / `player_heading` from the field HUD
## state instead: points are north-up in -1..1 around the player and get turned to heading-up.

## Metres from the centre to the rim.
const RANGE_M := 32.0
const RENDER_PX := 256
## Render layer (1-based) the map camera skips (same as MapScreen: B keeps monsters off the map).
const MAP_HIDDEN_LAYER := 20
const CAMERA_HEIGHT := 60.0
## How fast the map turns after the player (1/s). Damps the jitter of facing the cursor.
const TURN_SMOOTH := 12.0
const RIM_SEGMENTS := 64

## Preview / fallback bearing (0 = world -Z, clockwise). With a player the map follows
## Player.facing() instead and ignores this.
var player_heading := 0.0:
	set(v):
		player_heading = v
		queue_redraw()
## Preview / fallback marks: [{"pos": Vector2(-1..1, north-up), "kind": StringName}]
var points: Array = []:
	set(v):
		points = v
		queue_redraw()
var region_name := "":
	set(v):
		region_name = v
		queue_redraw()

## Marks collected from the world this frame, already heading-up in -1..1.
var _live_points: Array = []
var _live := false
var _live_heading := 0.0
var _sub: SubViewport
var _cam: Camera3D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 250)


func _process(delta: float) -> void:
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	_live = p != null and is_visible_in_tree()
	if not _live:
		_set_render(false)
		return
	var f: Vector3 = p.call(&"facing") if p.has_method(&"facing") else -p.global_basis.z
	if Vector2(f.x, f.z).length_squared() > 0.0001:
		var target := deg_to_rad(bearing(f))
		var h := lerp_angle(deg_to_rad(_live_heading), target, minf(1.0, delta * TURN_SMOOTH))
		_live_heading = fposmod(rad_to_deg(h), 360.0)
	_collect(p)
	_update_camera(p)
	queue_redraw()


## World direction -> bearing in degrees (0 = -Z, clockwise), the convention of PlayerHudState.
static func bearing(direction: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(direction.x, -direction.z)), 360.0)


## World x/z offset from the player -> heading-up minimap space (-1..1 at RANGE_M).
static func to_map(offset: Vector3, heading_deg: float) -> Vector2:
	return (Vector2(offset.x, offset.z) / RANGE_M).rotated(-deg_to_rad(heading_deg))


func _collect(p: Node3D) -> void:
	var out: Array = []
	var add := func(pos: Vector3, kind: StringName) -> void:
		out.append({"pos": to_map(pos - p.global_position, _live_heading), "kind": kind})
	var em := get_tree().get_first_node_in_group(ExtractionManager.GROUP)
	if em != null and em.has_method(&"active_points"):
		for e: Node3D in em.call(&"active_points"):
			add.call(e.global_position, &"extract")
	for o: Dictionary in Quests.active_field_objectives(FieldState.region_id):
		var node := _find_marker(StringName(o.get("marker", &"")))
		if node != null:
			add.call(node.global_position, &"objective")
	for g: Dictionary in FieldState.recoverable_gear():
		add.call(g.position, &"lost_gear")
	for n: Node in get_tree().get_nodes_in_group(ExtractionManager.PARTY_GROUP):
		if n is Node3D:
			add.call((n as Node3D).global_position, &"companion")
	_live_points = out


func _find_marker(marker: StringName) -> Node3D:
	if marker == &"":
		return null
	for n: Node in get_tree().get_nodes_in_group(FieldMarker.GROUP_ALL):
		if n.name == marker and n is Node3D:
			return n
	return null


# ---------------- live map render ----------------

func _update_camera(p: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_set_render(true)
	_cam.global_position = p.global_position + Vector3.UP * CAMERA_HEIGHT
	# Looking straight down; yaw so that screen-up is the heading (same as Player.rotation.y).
	_cam.rotation = Vector3(-PI * 0.5, -deg_to_rad(_live_heading), 0.0)


func _set_render(on: bool) -> void:
	if on and _sub == null:
		_sub = SubViewport.new()
		_sub.name = &"MinimapRender"
		_sub.size = Vector2i(RENDER_PX, RENDER_PX)
		_sub.world_3d = get_viewport().world_3d
		_sub.positional_shadow_atlas_size = 0
		add_child(_sub)
		_cam = Camera3D.new()
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.keep_aspect = Camera3D.KEEP_WIDTH
		_cam.size = RANGE_M * 2.0
		_cam.near = 0.5
		_cam.far = CAMERA_HEIGHT + 40.0
		_cam.cull_mask = 0xFFFFF & ~(1 << (MAP_HIDDEN_LAYER - 1))
		_cam.rotation_order = EULER_ORDER_YXZ
		_sub.add_child(_cam)
		_cam.current = true
	if _sub != null:
		_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


# ---------------- drawing ----------------

func _draw() -> void:
	var map := Rect2(0, 0, size.x, size.x)
	var c := map.get_center()
	var r := map.size.x * 0.5 - 6.0
	draw_circle(c, r, Color(0, 0, 0, 0.22))
	if _live and _sub != null:
		_draw_map_disc(c, r)
	draw_arc(c, r, 0, TAU, RIM_SEGMENTS, Color(UiTokens.TEXT, 0.55), 2.0, true)
	draw_arc(c, r * 0.5, 0, TAU, 48, Color(UiTokens.TEXT, 0.15), 1.0, true)
	# North tick on the rim so the player can still tell where north went.
	var north := Vector2(0, -1).rotated(-deg_to_rad(heading()))
	draw_string(UiThemeBuilder.font_kr(600), c + north * (r - 12.0) + Vector2(-5, 6), "N",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(UiTokens.TEXT, 0.7))
	for p: Dictionary in (_live_points if _live else _preview_points()):
		_draw_mark(c + _pin(p.get("pos", Vector2.ZERO)) * r, StringName(p.get("kind", &"")))
	# The player: always at the centre, always pointing up.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -10), c + Vector2(6, 6), c + Vector2(0, 3),
		c + Vector2(-6, 6)]), UiTokens.TEXT)
	if not region_name.is_empty():
		var f := UiThemeBuilder.font_kr(600)
		draw_string(f, Vector2(4, size.x + 26), region_name, HORIZONTAL_ALIGNMENT_LEFT, size.x, 17,
			UiTokens.TEXT)


## Bearing the map is turned to right now.
func heading() -> float:
	return _live_heading if _live else player_heading


## The top-down render clipped to the disc. The render is already turned by the camera.
func _draw_map_disc(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in RIM_SEGMENTS:
		var d := Vector2.from_angle(TAU * i / RIM_SEGMENTS)
		pts.append(c + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	draw_polygon(pts, PackedColorArray([Color(1, 1, 1, 0.85)]), uvs, _sub.get_texture())


## Preview points are north-up: turn them to heading-up.
func _preview_points() -> Array:
	var out: Array = []
	for p: Dictionary in points:
		var q := p.duplicate()
		q["pos"] = (p.get("pos", Vector2.ZERO) as Vector2).rotated(-deg_to_rad(player_heading))
		out.append(q)
	return out


## Outside the range: pinned to the rim.
static func _pin(pos: Vector2) -> Vector2:
	return pos.normalized() if pos.length() > 1.0 else pos


func _draw_mark(at: Vector2, kind: StringName) -> void:
	match kind:
		&"extract":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -7), at + Vector2(7, 0),
				at + Vector2(0, 7), at + Vector2(-7, 0)]), UiTokens.GOOD)
		&"objective":
			draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), UiTokens.ACCENT)
		&"companion":
			draw_circle(at, 5.0, UiTokens.INFO)
		&"monster_heard":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(6, 5),
				at + Vector2(-6, 5)]), UiTokens.DANGER)
		&"lost_gear":
			draw_arc(at, 5.0, 0, TAU, 16, UiTokens.TEXT, 2.0, true)
