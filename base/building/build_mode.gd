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
signal placed(uid: StringName)
signal moved(uid: StringName)
signal cancelled

const GROUND_Y := 0.0
const PREVIEW_HEIGHT := 0.6
const LABEL_HEIGHT := 2.2

var grid: BaseGrid
var active := false
var def_id: StringName = &""
var move_uid: StringName = &""
var rotation_index := 0
## Last preview: {"zone_id", "cell", "ok", "reasons"} ({} when the cursor is off every area).
var last := {}

var _box: MeshInstance3D
var _label: Label3D
var _ok_material := StandardMaterial3D.new()
var _bad_material := StandardMaterial3D.new()


func _ready() -> void:
	for m in [_ok_material, _bad_material]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ok_material.albedo_color = Color(0.3, 0.9, 0.4, 0.45)
	_bad_material.albedo_color = Color(0.95, 0.3, 0.25, 0.45)
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


func cancel() -> void:
	if not active:
		return
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
		_show(world_pos, Vector2i.ONE, false, ["건설 부지 밖"])
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
	_show(grid.footprint_center(zone_id, origin, size), size, result["ok"], result["reasons"])
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
		cancel()
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
