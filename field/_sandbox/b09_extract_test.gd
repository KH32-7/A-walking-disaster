extends Node3D
## B-09 extraction test scene: field sandbox + real player + 4 ExtractPoint candidates.
## Run alone (F6). Two candidates turn active (discs on the floor). Stand in one to extract.
## Sandbox only: debug keys use raw keycodes, not project input actions.

const DISC_HEIGHT := 0.05
const DISC_COLOR := Color(0.2, 0.75, 1.0, 0.35)
## Where the dummy companion goes when it is "far" (C key).
const COMPANION_FAR := Vector3(0, 0.1, 20)

@onready var _player: Player = $Player
@onready var _camera: Camera3D = $FieldSandbox/Camera3D
@onready var _manager: ExtractionManager = $ExtractionManager
@onready var _companion: Node3D = $Companion
@onready var _label: Label = $DebugLayer/HelpLabel

var _camera_offset := Vector3.ZERO
var _discs: Array[Node3D] = []
var _last := "없음"


func _ready() -> void:
	_camera_offset = _camera.global_position - _player.global_position
	Bag.load_data({})
	_manager.active_points_changed.connect(_on_active_changed)
	_manager.extraction_started.connect(func(id: StringName, wait: float) -> void: _last = "%s 대기 시작 (%.0f초)" % [id, wait])
	_manager.extraction_cancelled.connect(func(id: StringName) -> void: _last = "%s 취소" % id)
	_manager.extraction_blocked.connect(func(id: StringName, need: StringName) -> void: _last = "%s: %s 필요" % [id, need])
	_manager.leave_behind_requested.connect(_on_leave_behind)
	EventBus.extraction_completed.connect(func(id: StringName) -> void: _last = "%s 탈출 완료" % id)


func _process(_delta: float) -> void:
	_camera.global_position = _player.global_position + _camera_offset
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_K:
			Bag.try_add(&"key", 1)
		KEY_B:
			Bag.try_add(&"battery", 1)
		KEY_Y:
			_manager.answer_leave_behind(true)
		KEY_N:
			_manager.answer_leave_behind(false)
		KEY_C:
			var near := _companion.global_position.distance_to(_player.global_position) <= ExtractionManager.PARTY_RADIUS
			_companion.global_position = COMPANION_FAR if near else _player.global_position + Vector3(1.5, 0, 0)
		KEY_T:
			get_tree().reload_current_scene()
		_:
			return


func _on_active_changed(_ids: Array[StringName]) -> void:
	for d in _discs:
		d.queue_free()
	_discs.clear()
	for p in _manager.active_points():
		var disc := CSGCylinder3D.new()
		disc.radius = p.zone_radius
		disc.height = DISC_HEIGHT
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = DISC_COLOR
		disc.material = mat
		p.add_child(disc)
		_discs.append(disc)


func _on_leave_behind(id: StringName, people: Array) -> void:
	var names := []
	for person: Dictionary in people:
		names.append(person["name"])
	_last = "%s: %s 두고 갈까요? (Y 두고 감 / N 기다림)" % [id, ", ".join(names)]


func _refresh() -> void:
	var lines := [
		"B-09 탈출 테스트",
		"활성 지점: %s" % ", ".join(_manager.active_point_ids()),
		"상태: %s / 지점: %s / 진행: %d%%" % [
			ExtractionManager.State.keys()[_manager.state], _manager.current_point_id(), roundi(_manager.progress() * 100.0)],
		"가방: 열쇠 %d / 배터리 %d" % [Bag.count_of(&"key"), Bag.count_of(&"battery")],
		"K 열쇠 / B 배터리 / C 동행자 가까이, 멀리 / Y, N 확인창 답 / T 다시 시작",
		"마지막: %s" % _last,
	]
	var result := _manager.get_result()
	if not result.is_empty():
		lines.append("결과: 탈출 %s / 지점 %s / 처치 %d / 동행 %s / 고립 %s" % [
			result["extracted"], result["point_id"], result["kills"], result["companions"], result["stranded"]])
	_label.text = "\n".join(lines)
