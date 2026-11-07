class_name HelicopterWreck
extends StaticBody3D
## The broken helicopter on a HELICOPTER extract point (02 "헬기 탈출"). ExtractionManager makes one
## per active helicopter point. With a mechanic companion nearby the player holds F for
## TUNING.helicopter_repair_sec (loud noise meanwhile); once fixed, stepping into the point's zone
## extracts at once.

signal repaired()

const TUNING := FieldVehicle.TUNING
const SIZE := Vector3(2.6, 2.4, 8.0)
const REPAIR_LABEL := "헬기 고치기 (꾹 누르기)"
const REPAIR_HOLD_LABEL := "헬기 고치는 중"

var fixed := false

var _repairer: Node3D
var _repair_left := 0.0
var _repair_from := Vector3.ZERO
var _noise: NoiseEmitter


func _ready() -> void:
	collision_layer = (1 << (Enums.LAYER_WORLD - 1)) | (1 << (Enums.LAYER_INTERACTABLE - 1))
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	shape.position.y = SIZE.y * 0.5
	add_child(shape)
	add_child(_make_look())
	_noise = NoiseEmitter.new()
	add_child(_noise)


func _physics_process(delta: float) -> void:
	if _repairer == null:
		return
	if _repairer.get(&"interact_held") == false \
			or FieldVehicle.mechanic_near_point(get_tree(), global_position) == null \
			or _repairer.global_position.distance_to(_repair_from) > TUNING.repair_leave_m:
		_stop()
		return
	_repair_left -= delta
	if _repair_left <= 0.0:
		_stop()
		fixed = true
		repaired.emit()


func begin_open(interactor: Node3D) -> bool:
	if fixed or _repairer != null or not (interactor is Player) \
			or FieldVehicle.mechanic_near_point(get_tree(), global_position) == null:
		return false
	_repairer = interactor
	_repair_from = interactor.global_position
	_repair_left = TUNING.helicopter_repair_sec
	_noise.start_continuous(TUNING.helicopter_noise_action)
	return true


func interact_label() -> String:
	if fixed or _repairer != null:
		return ""
	return REPAIR_LABEL if FieldVehicle.mechanic_near_point(get_tree(), global_position) != null \
			else FieldVehicle.NEED_MECHANIC_LABEL


func hold_state() -> Dictionary:
	if _repairer == null:
		return {}
	return {"label": REPAIR_HOLD_LABEL,
		"progress": clampf(1.0 - _repair_left / TUNING.helicopter_repair_sec, 0.0, 1.0)}


func _stop() -> void:
	_repairer = null
	_noise.stop_continuous()


func _make_look() -> Node3D:
	if TUNING.helicopter_model != null:
		return FieldVehicle.fit_model(TUNING.helicopter_model.instantiate() as Node3D, SIZE.z, 0.0)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = SIZE
	mesh.mesh = box
	mesh.position.y = SIZE.y * 0.5
	return mesh
