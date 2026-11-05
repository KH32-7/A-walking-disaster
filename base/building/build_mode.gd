class_name BuildMode
extends Node3D
## Build mode on the base map (C-03): pick a cell with the mouse, rotate, place or move a building.
## Lane D's building panel (D-06) calls start(def_id) / start_move(uid) and listens to the signals;
## this node draws only the in-world preview (a footprint box + a label), no Control UI.
##
## Input while active (existing InputSetup actions, reused only in build mode):
##   attack (LMB) = place, reload (R) = rotate 90°, aim (RMB) / pause (Esc) = cancel.
## TODO: dedicated build_place / build_rotate / build_cancel actions (request to Lane A).

signal preview_changed(ok: bool, reasons: Array)
## Same moment as preview_changed, with what the UI needs for its cursor card (D-06 재설계):
## {"ok", "reasons", "def_id", "move", "on_grid", "node_kind" ("나무" / "잔해 더미" / ""), "nodes", "radius",
##  "center" (world position of the footprint centre)}.
signal preview_info(info: Dictionary)
signal placed(uid: StringName)
signal moved(uid: StringName)
signal cancelled

const GROUND_Y := 0.0
const PREVIEW_HEIGHT := 0.6
const LABEL_HEIGHT := 2.2
## Ground overlay (컬트 오브 더 램 배치 화면 + 덕코프 청록 격자): grid lines on cleared areas, a dark
## veil on uncleared ones, existing buildings' cells in red, the new footprint in green / red.
const GRID_COLOR := Color(0.42, 0.78, 1.0, 0.55)
## Line width on the ground (m): 1-pixel lines vanish in the grass from the base camera.
const LINE_W := 0.07
const UNCLEARED_COLOR := Color(0.05, 0.06, 0.1, 0.42)
const TAKEN_FILL := Color(0.85, 0.27, 0.23, 0.16)
const TAKEN_LINE := Color(1.0, 0.47, 0.43, 0.8)
const OK_FILL := Color(0.37, 0.77, 0.42, 0.5)
const OK_LINE := Color(0.62, 0.96, 0.66, 1.0)
const BAD_FILL := Color(0.85, 0.27, 0.23, 0.5)
const BAD_LINE := Color(1.0, 0.6, 0.55, 1.0)
const RING_COLOR := Color(0.34, 0.76, 0.79, 0.95)
const Y_BOARD := 0.04
const Y_CELLS := 0.07

var grid: BaseGrid
var active := false
var def_id: StringName = &""
var move_uid: StringName = &""
var rotation_index := 0
## Last preview: {"zone_id", "cell", "ok", "reasons"} ({} when the cursor is off every area).
var last := {}

var _box: MeshInstance3D
var _label: Label3D
## Grid + taken cells (drawn when build mode starts) and the footprint + range ring (every preview).
var _board: MeshInstance3D
var _cells: MeshInstance3D
var _overlay_material := StandardMaterial3D.new()
## The in-world text label. Off when a UI card shows the same words (BuildPlaceHud).
var show_label := false
## Whether the last cancel() came from the player (see cancel()).
var cancelled_by_player := false
## Ghost of the real model (BuildingModels, D-06 재설계) while placing; the box stays when there is none.
var _ghost: Node3D
var _ghost_key := ""
var _ok_material := StandardMaterial3D.new()
var _bad_material := StandardMaterial3D.new()


func _ready() -> void:
	for m in [_ok_material, _bad_material]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ok_material.albedo_color = Color(0.3, 0.9, 0.4, 0.3)
	_bad_material.albedo_color = Color(0.95, 0.3, 0.25, 0.3)
	_overlay_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay_material.vertex_color_use_as_albedo = true
	_overlay_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The forest clearing's grass and ground props stand above y = 0: draw the grid on top of them.
	_overlay_material.no_depth_test = true
	_overlay_material.render_priority = 10
	_box = MeshInstance3D.new()
	_box.mesh = BoxMesh.new()
	_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_box)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 48
	_label.outline_size = 12
	_label.pixel_size = 0.01
	add_child(_label)
	visible = false
	_register_debug_commands.call_deferred()


## Starts placing a new `def_id` (D-06 건설 패널). Returns false if it cannot go on the grid.
func start(new_def_id: StringName) -> bool:
	var def := BaseDB.get_building(new_def_id)
	if grid == null or def == null or def.size == Vector2i.ZERO or def.prebuilt:
		return false
	def_id = new_def_id
	move_uid = &""
	rotation_index = 0
	_begin()
	return true


## Starts moving an existing building (이동은 무료, 진행도 유지).
func start_move(uid: StringName) -> bool:
	var b := Colony.get_building(uid)
	if grid == null or b.is_empty() or BaseDB.get_building(b["def_id"]).prebuilt:
		return false
	def_id = b["def_id"]
	move_uid = uid
	rotation_index = int(b["rotation"])
	_begin()
	return true


## by_player: Esc / RMB / the overlay's Q. The UI goes back to the build list only then, so a
## cancel from code (tests, leaving the base) leaves no menu open.
func cancel(by_player := false) -> void:
	if not active:
		return
	cancelled_by_player = by_player
	active = false
	visible = false
	cancelled.emit()


func rotate_footprint() -> void:
	rotation_index = (rotation_index + 1) % 4
	if not last.is_empty():
		preview_cell(last["zone_id"], last["cell"])


## Preview at a world point (mouse ray hit). Returns the check result (see BaseGrid.check).
func preview_at(world_pos: Vector3) -> Dictionary:
	var hit := grid.pick(world_pos)
	if hit.is_empty():
		last = {}
		if _cells != null:
			(_cells.mesh as ImmediateMesh).clear_surfaces()
		_show(world_pos, Vector2i.ONE, false, ["건설 부지 밖"])
		preview_info.emit(_info(false, ["건설 부지 밖"], world_pos, false))
		return {"ok": false, "reasons": ["건설 부지 밖"]}
	# The cursor is the footprint's center cell, so the box sits under the mouse.
	var size := BaseGrid.footprint(BaseDB.get_building(def_id), rotation_index)
	return preview_cell(hit["zone_id"], hit["cell"] - (size - Vector2i.ONE) / 2)


## Preview with `origin` as the footprint's top-left cell.
func preview_cell(zone_id: StringName, origin: Vector2i) -> Dictionary:
	var result := grid.check(def_id, zone_id, origin, rotation_index, move_uid)
	if result["ok"] and move_uid == &"":
		var can := Colony.can_build(def_id)
		if not can["ok"]:
			result = {"ok": false, "reasons": can["reasons"]}
	last = {"zone_id": zone_id, "cell": origin, "ok": result["ok"], "reasons": result["reasons"]}
	var size := BaseGrid.footprint(BaseDB.get_building(def_id), rotation_index)
	var center := grid.footprint_center(zone_id, origin, size)
	_ensure_overlay()
	_draw_cells(zone_id, origin, size, result["ok"], center)
	_show(center, size, result["ok"], result["reasons"])
	preview_info.emit(_info(result["ok"], result["reasons"], center, true))
	return result


## Places (or moves) at the last preview. Returns the uid, or &"" when the spot is not valid.
func confirm() -> StringName:
	if not active or last.is_empty() or not last["ok"]:
		return &""
	var cell: Vector2i = last["cell"]
	var zone_id: StringName = last["zone_id"]
	if move_uid != &"":
		var uid := move_uid
		Colony.move_building(uid, cell, rotation_index, zone_id)
		active = false
		visible = false
		moved.emit(uid)
		return uid
	var new_uid := Colony.place_building(def_id, cell, rotation_index, zone_id, true)
	if new_uid == &"":
		return &""
	active = false
	visible = false
	placed.emit(new_uid)
	return new_uid


func _begin() -> void:
	active = true
	visible = true
	last = {}
	_label.visible = show_label
	_ensure_overlay()
	_draw_board()
	(_cells.mesh as ImmediateMesh).clear_surfaces()


## Overlay meshes are made the first time build mode starts, not in _ready: an empty ImmediateMesh in
## the scene while the base navmesh bakes leaves residents with no path (test_resident_agents).
func _ensure_overlay() -> void:
	if _board != null:
		return
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		if i == 0:
			_board = mi
		else:
			_cells = mi


func _info(ok: bool, reasons: Array, center: Vector3, on_grid: bool) -> Dictionary:
	var info := {"ok": ok, "reasons": reasons, "def_id": def_id, "move": move_uid != &"", "on_grid": on_grid,
		"node_kind": "", "nodes": 0, "radius": 0.0, "center": center}
	if BaseGrid.NEEDS_NODE.has(def_id) and grid != null:
		var kind: ResourceNode.Kind = BaseGrid.NEEDS_NODE[def_id]
		var radius := BaseDB.get_building(def_id).effect(&"resource_node_radius", 10.0)
		info["node_kind"] = "나무" if kind == ResourceNode.Kind.TREE else "잔해 더미"
		info["radius"] = radius
		info["nodes"] = grid.nodes_in_range(kind, center, radius).size() if on_grid else 0
	return info


# --- ground overlay ------------------------------------------------------------

## World position of a cell corner (x, y in cells from the area's top-left) on `area`.
func _corner(area: BuildArea, x: float, y: float, lift: float) -> Vector3:
	var half := area.size_m() * 0.5
	return area.to_global(Vector3(-half.x + x * ColonyMarker.CELL_SIZE, lift, -half.y + y * ColonyMarker.CELL_SIZE))


func _quad(tris: Array, area: BuildArea, c: Vector2i, lift: float, col: Color) -> void:
	var a := _corner(area, c.x, c.y, lift)
	var b := _corner(area, c.x + 1, c.y, lift)
	var d := _corner(area, c.x + 1, c.y + 1, lift)
	var e := _corner(area, c.x, c.y + 1, lift)
	tris.append_array([[a, col], [b, col], [d, col], [a, col], [d, col], [e, col]])


func _outline(lines: Array, area: BuildArea, c: Vector2i, lift: float, col: Color) -> void:
	var p := [_corner(area, c.x, c.y, lift), _corner(area, c.x + 1, c.y, lift),
		_corner(area, c.x + 1, c.y + 1, lift), _corner(area, c.x, c.y + 1, lift)]
	for i in 4:
		lines.append_array([[p[i], col], [p[(i + 1) % 4], col]])


func _flush(im: ImmediateMesh, tris: Array, lines: Array) -> void:
	im.clear_surfaces()
	# Lines become thin ground quads (LINE_W wide) so they keep a real width at any zoom.
	for i in range(0, lines.size() - 1, 2):
		var a: Vector3 = lines[i][0]
		var b: Vector3 = lines[i + 1][0]
		var col: Color = lines[i][1]
		var d := b - a
		d.y = 0.0
		if d.length() < 0.001:
			continue
		var side := Vector3(-d.z, 0.0, d.x).normalized() * (LINE_W * 0.5)
		tris.append_array([[a - side, col], [a + side, col], [b + side, col], [a - side, col], [b + side, col], [b - side, col]])
	lines = []
	for pair: Array in [[Mesh.PRIMITIVE_TRIANGLES, tris], [Mesh.PRIMITIVE_LINES, lines]]:
		var verts: Array = pair[1]
		if verts.is_empty():
			continue
		im.surface_begin(pair[0], _overlay_material)
		for v: Array in verts:
			im.surface_set_color(v[1])
			im.surface_add_vertex(v[0])
		im.surface_end()


## Every build area: grid lines when cleared, a veil when not; cells other buildings take in red.
func _draw_board() -> void:
	var tris := []
	var lines := []
	if grid != null:
		for zone_id: StringName in grid.areas:
			var area: BuildArea = grid.areas[zone_id]
			if not grid.is_zone_cleared(zone_id):
				for x in area.size_cells.x:
					for y in area.size_cells.y:
						_quad(tris, area, Vector2i(x, y), Y_BOARD, UNCLEARED_COLOR)
				continue
			for x in area.size_cells.x + 1:
				lines.append_array([[_corner(area, x, 0, Y_BOARD), GRID_COLOR], [_corner(area, x, area.size_cells.y, Y_BOARD), GRID_COLOR]])
			for y in area.size_cells.y + 1:
				lines.append_array([[_corner(area, 0, y, Y_BOARD), GRID_COLOR], [_corner(area, area.size_cells.x, y, Y_BOARD), GRID_COLOR]])
			for c: Vector2i in grid.occupied(zone_id, move_uid):
				_quad(tris, area, c, Y_BOARD + 0.01, TAKEN_FILL)
				_outline(lines, area, c, Y_BOARD + 0.01, TAKEN_LINE)
	_flush(_board.mesh as ImmediateMesh, tris, lines)


## The footprint cells (green = ok, red = not) and, for 벌목장·채석장, the node range ring with a
## small ring under every node inside it.
func _draw_cells(zone_id: StringName, origin: Vector2i, size: Vector2i, ok: bool, center: Vector3) -> void:
	var tris := []
	var lines := []
	var area: BuildArea = grid.areas.get(zone_id)
	if area != null:
		for c in BaseGrid.cells(origin, size):
			if area.has_cell(c):
				_quad(tris, area, c, Y_CELLS, OK_FILL if ok else BAD_FILL)
				_outline(lines, area, c, Y_CELLS, OK_LINE if ok else BAD_LINE)
	if BaseGrid.NEEDS_NODE.has(def_id):
		var radius := BaseDB.get_building(def_id).effect(&"resource_node_radius", 10.0)
		_circle(lines, center, radius, RING_COLOR, 72, true)
		for node in grid.nodes_in_range(BaseGrid.NEEDS_NODE[def_id], center, radius):
			_circle(lines, node.global_position, 0.9, RING_COLOR, 20, false)
	_flush(_cells.mesh as ImmediateMesh, tris, lines)


func _circle(lines: Array, center: Vector3, radius: float, col: Color, segments: int, dashed: bool) -> void:
	for i in segments:
		if dashed and i % 2 == 1:
			continue
		var a := TAU * i / segments
		var b := TAU * (i + 1) / segments
		lines.append_array([[Vector3(center.x + cos(a) * radius, Y_CELLS, center.z + sin(a) * radius), col],
			[Vector3(center.x + cos(b) * radius, Y_CELLS, center.z + sin(b) * radius), col]])


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		var hit = _mouse_ground(event.position)
		if hit != null:
			preview_at(hit)
	elif event.is_action_pressed(&"reload"):
		rotate_footprint()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"attack"):
		confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"aim") or event.is_action_pressed(&"pause"):
		cancel(true)
		get_viewport().set_input_as_handled()


## Mouse ray → ground plane (y = 0). null when the camera looks away from the ground.
func _mouse_ground(screen_pos: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	return Plane(Vector3.UP, GROUND_Y).intersects_ray(origin, dir)


func _show(center: Vector3, size: Vector2i, ok: bool, reasons: Array) -> void:
	var m := Vector3(size.x, 0.0, size.y) * ColonyMarker.CELL_SIZE
	(_box.mesh as BoxMesh).size = Vector3(m.x, PREVIEW_HEIGHT, m.z)
	_box.global_position = center + Vector3(0, PREVIEW_HEIGHT * 0.5, 0)
	_box.material_override = _ok_material if ok else _bad_material
	_update_ghost(center, size)
	var def := BaseDB.get_building(def_id)
	# Text says it too: colour is never the only signal (14 "UI 규칙").
	_label.text = "%s\n%s" % [def.display_name if def else String(def_id),
		"○ 놓을 수 있음" if ok else "✕ " + ", ".join(PackedStringArray(reasons))]
	_label.modulate = Color(0.75, 1.0, 0.8) if ok else Color(1.0, 0.75, 0.7)
	_label.global_position = center + Vector3(0, LABEL_HEIGHT, 0)
	preview_changed.emit(ok, reasons)


# --- Debug console ---------------------------------------------------------------

func _register_debug_commands() -> void:
	DebugConsole.register(&"place", _cmd_place,
		"place <building_id> (마우스로 놓기, R 회전, 우클릭 취소) | place at <id> <zone> <x> <y> [rot] | place move <uid>")


func _cmd_place(args: PackedStringArray) -> String:
	if not is_inside_tree():
		return "기지 맵이 아님"
	if args.is_empty():
		return "사용법: place <building_id> | place at <id> <zone> <x> <y> [rot] | place move <uid>"
	if args[0] == "at" and args.size() >= 5:
		def_id = StringName(args[1])
		move_uid = &""
		rotation_index = int(args[5]) if args.size() > 5 else 0
		_begin()
		var result := preview_cell(StringName(args[2]), Vector2i(int(args[3]), int(args[4])))
		if not result["ok"]:
			cancel()
			return "못 놓음: " + ", ".join(PackedStringArray(result["reasons"]))
		return "건설 현장: %s" % confirm()
	if args[0] == "move" and args.size() >= 2:
		return "이동 모드: %s" % args[1] if start_move(StringName(args[1])) else "옮길 수 없음"
	return "건설 모드: %s (콘솔을 닫고 마우스로)" % args[0] if start(StringName(args[0])) else "격자에 놓을 수 없는 건물"


## Half see-through real model on the footprint (BuildingViews uses the same BuildingModels.build).
func _update_ghost(center: Vector3, size: Vector2i) -> void:
	var models := BuildingViews.Models
	var key := "%s_%d_%d" % [def_id, size.x, size.y]
	if key != _ghost_key:
		_ghost_key = key
		if _ghost != null:
			_ghost.queue_free()
			_ghost = null
		if models.has_assets() and models.MODELS.has(def_id):
			_ghost = models.build(def_id, size)
			add_child(_ghost)
			for n in _ghost.find_children("*", "GeometryInstance3D", true, false):
				(n as GeometryInstance3D).transparency = 0.45
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box.visible = _ghost == null
	if _ghost != null:
		_ghost.global_position = center + Vector3(0, 0.05, 0)
