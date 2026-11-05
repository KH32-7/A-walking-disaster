extends Node3D
## Lane C sandbox (run this scene alone with F6). Greybox school base with every marker type.
## Debug only: shows marker helpers in game, a quarter-view camera you can pan/zoom, and a
## debug panel. Nothing here ships (docs/dev/contracts.md "UI와 게임플레이의 경계").
##
## Controls: WASD / arrows = pan, wheel = zoom, F1 = toggle marker helpers.

const PAN_SPEED := 20.0
const ZOOM_MIN := 15.0
const ZOOM_MAX := 200.0
const PITCH_DEG := 55.0 ## quarter view, docs/dev/lane-b-field.md B-04

@export var show_markers := true

var _focus := Vector3(0.0, 0.0, 0.0)
var _distance := 150.0

@onready var _camera: Camera3D = $Camera3D
@onready var _info: Label = $Debug/Info


func _enter_tree() -> void:
	ColonyMarker.show_in_game = show_markers


func _ready() -> void:
	($Sun as DirectionalLight3D).rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	_update_camera()
	_update_info()


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
	if dir != Vector3.ZERO:
		_focus += dir.normalized() * PAN_SPEED * delta
		_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(ZOOM_MIN, _distance - 3.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(ZOOM_MAX, _distance + 3.0)
			_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		ColonyMarker.show_in_game = not ColonyMarker.show_in_game
		ColonyMarker.refresh_all(get_tree())
		_update_info()


func _update_camera() -> void:
	var pitch := deg_to_rad(PITCH_DEG)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * _distance
	_camera.position = _focus + offset
	_camera.look_at(_focus, Vector3.UP)


func _update_info() -> void:
	var tree := get_tree()
	var lines: PackedStringArray = [
		"Base sandbox (Lane C)  |  WASD 이동 · 휠 줌 · F1 마커 표시 %s" % ("켜짐" if ColonyMarker.show_in_game else "꺼짐"),
		"Colony: 주민 %d명, 위협도 %d, 단계 %s" % [
			Colony.active_resident_ids().size(), Colony.threat, Enums.BaseTier.keys()[Colony.tier]],
		"마커: Zone %d · BuildArea %d · Resource %d · RaidSpawn %d · Work %d · Outpost %d" % [
			tree.get_node_count_in_group(ZoneMarker.MARKER_GROUP),
			tree.get_node_count_in_group(BuildArea.MARKER_GROUP),
			tree.get_node_count_in_group(ResourceNode.MARKER_GROUP),
			tree.get_node_count_in_group(RaidSpawnPoint.MARKER_GROUP),
			tree.get_node_count_in_group(WorkSpot.MARKER_GROUP),
			tree.get_node_count_in_group(OutpostNode.MARKER_GROUP)],
	]
	_info.text = "\n".join(lines)
