extends Node3D
## Lane C sandbox (run alone with F6): the real base map (layout + forest dressing) with every
## building of data/buildings shown finished in the clearing (공터), made of American Suburb models.
## Debug only, nothing here ships. Without the private assets/ submodule you see grey boxes.
##
## Controls: WASD / arrows = pan, wheel = zoom, Q / E = turn, B = show/hide buildings, L = names.

const Models := preload("res://base/building/building_models.gd")
const CLEARING_ZONE := &"front_yard"

const PAN_SPEED := 24.0
const ZOOM_MIN := 12.0
const ZOOM_MAX := 260.0
const PITCH_DEG := 55.0

@export var show_buildings := true
@export var show_labels := true

var _focus := Vector3(0.0, 0.0, 2.0)
var _distance := 90.0
var _yaw := 0.0
var _buildings_root: Node3D
var _labels: Array[Label3D] = []

@onready var _camera: Camera3D = $Camera3D
@onready var _info: Label = $Debug/Info
@onready var _layout: Node3D = $Layout
@onready var _dressing: Node3D = $Dressing


func _ready() -> void:
	if show_buildings:
		_place_buildings()
	_update_camera()
	# The dressing fills in a frame after the layout's markers are ready.
	await get_tree().process_frame
	await get_tree().process_frame
	_update_info()
	if DisplayServer.get_name() == "headless":
		print(_info.text)


## Every building laid out in rows inside the clearing's build area (shelf packing).
func _place_buildings() -> void:
	var area: BuildArea
	for node in _layout.find_children("*", "Marker3D", true, false):
		if node is BuildArea and (node as BuildArea).zone_id == CLEARING_ZONE:
			area = node
	if area == null:
		push_warning("forest_clearing: no %s build area in the layout" % CLEARING_ZONE)
		return
	_buildings_root = Node3D.new()
	_buildings_root.name = "Buildings"
	add_child(_buildings_root)
	var items: Array = []
	for id: StringName in Models.MODELS:
		var def := BaseDB.get_building(id)
		var size: Vector2i = Models.SIZE_OVERRIDE.get(id, def.size if def else Vector2i.ONE)
		var title: String = Models.NAME_OVERRIDE.get(id, def.display_name if def else String(id))
		items.append({"id": id, "size": size, "name": title})
	items.sort_custom(_bigger_first)
	var cols := area.size_cells.x
	var rows := area.size_cells.y
	var col := 0
	var row := 0
	var row_h := 0
	for it: Dictionary in items:
		var s: Vector2i = it["size"]
		if col + s.x > cols:
			col = 0
			row += row_h + 1
			row_h = 0
		if row + s.y > rows:
			push_warning("forest_clearing: clearing is full, %s not shown" % it["id"])
			continue
		var a := area.cell_to_world(Vector2i(col, row)) - Vector3(1, 0, 1)
		var centre := a + Vector3(s.x, 0, s.y)
		var node := Models.build(it["id"], s)
		node.position = centre + Vector3(0, 0.05, 0)
		_buildings_root.add_child(node)
		var label := Label3D.new()
		label.text = it["name"]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		label.outline_size = 12
		label.pixel_size = 0.012
		label.no_depth_test = true
		label.position = centre + Vector3(0, 5.0, 0)
		label.visible = show_labels
		_buildings_root.add_child(label)
		_labels.append(label)
		col += s.x + 1
		row_h = maxi(row_h, s.y)


static func _bigger_first(a: Dictionary, b: Dictionary) -> bool:
	return a["size"].x * a["size"].y > b["size"].x * b["size"].y


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		turn += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		turn -= 1.0
	if dir != Vector3.ZERO or turn != 0.0:
		_yaw += turn * delta * 1.2
		_focus += dir.normalized().rotated(Vector3.UP, _yaw) * PAN_SPEED * delta * (_distance / 80.0)
		_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(ZOOM_MIN, _distance * 0.9)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(ZOOM_MAX, _distance * 1.1)
			_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_B and _buildings_root:
			_buildings_root.visible = not _buildings_root.visible
		elif event.physical_keycode == KEY_L:
			show_labels = not show_labels
			for l in _labels:
				l.visible = show_labels


func _update_camera() -> void:
	var pitch := deg_to_rad(PITCH_DEG)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, _yaw) * _distance
	_camera.position = _focus + offset
	_camera.look_at(_focus, Vector3.UP)


func _update_info() -> void:
	var counts: Dictionary = _dressing.call(&"instance_counts") if _dressing.has_method(&"instance_counts") else {}
	var total := 0
	for k in counts:
		total += counts[k]
	_info.text = "\n".join([
		"Forest clearing sandbox (Lane C)  |  WASD 이동 · 휠 줌 · Q/E 회전 · B 건물 · L 이름",
		"자연물 %d개 (모델 %d종) · 건물 %d종 · 없는 모델 %d" % [total, counts.size(), _labels.size(),
			Models.missing_models().size()],
		"" if Models.has_assets() else "assets/ 서브모듈이 없어 회색 상자로 표시합니다 (git submodule update --init)",
	])
