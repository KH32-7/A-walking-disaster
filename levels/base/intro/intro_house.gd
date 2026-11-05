class_name IntroHouse
extends Node3D
## Inside of the 낡은 집 for the new-game intro (사용자 요청 2026-11-06). Built in code from the suburb
## house modules and furniture (assets/, private) with greybox boxes when they are missing; placed far
## from the base map so the base never shows through. A cut-away room: the two walls on the camera's
## side (+X, +Z for the field camera's 45° view) are half height.
##
## What is in it: the hard case with the 권총 (a LootContainer, gear slot), the injured 한도윤 on the
## bed and the front door. IntroCutscene drives the order; this only builds and reports:
##   chest: LootContainer          patient: Interactable (talk_requested)   door: Interactable
##   spawn_point() / door_point() / patient_point() world positions.

signal talk_requested
signal exit_requested

const Models := preload("res://base/building/building_models.gd")
const CONTAINER_SCENE := preload("res://field/loot/loot_container.tscn")
const CONTAINER_DEF := preload("res://data/loot/containers/supply_crate.tres")
## Room size (m). Floor tiles are 4×4.
const W := 12.0
const D := 8.0
const WALL_H := 3.0
const LOW_H := 1.5
const DOOR_X := 3.6
## Day-1 light: warm lamp, a candle by the bed and cold light through the window.
const LAMP_COLOR := Color(1.0, 0.72, 0.45)
const CANDLE_COLOR := Color(1.0, 0.55, 0.25)
const WINDOW_COLOR := Color(0.55, 0.7, 1.0)

var chest: LootContainer
var patient: Interactable
var door: Interactable
var patient_model: Node3D
var _candle: OmniLight3D
var _t := 0.0


## Something on the interact layer with a label; Player.interact() calls begin_open().
class Interactable extends StaticBody3D:
	signal used
	var label := ""
	var enabled := true

	func _init(p_label: String, size: Vector3) -> void:
		label = p_label
		collision_layer = 1 << (Enums.LAYER_INTERACTABLE - 1)
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position.y = size.y * 0.5
		add_child(cs)

	func interact_label() -> String:
		return label if enabled else ""

	func begin_open(_interactor: Node3D) -> bool:
		if not enabled:
			return false
		used.emit()
		return true


func _ready() -> void:
	_build_floor()
	_build_walls()
	_build_furniture()
	_build_lights()
	_build_void()
	chest = CONTAINER_SCENE.instantiate()
	var quick := CONTAINER_DEF.duplicate() as LootContainerDef
	quick.open_sec = 1.2  # the first chest opens fast: the tutorial is about the gun, not waiting
	chest.def = quick
	chest.name = "GunCase"
	add_child(chest)
	chest.position = Vector3(3.2, 0, -2.6)
	chest.add_gear(&"pistol")
	var case := Models.prop("long_hard_case", Vector3.ZERO, 90.0, 0.55, 1.1)
	if case != null:
		chest.add_child(case)
		var grey := chest.get_node_or_null(^"Greybox") as Node3D
		if grey:
			grey.visible = false
	patient = Interactable.new("이야기하기", Vector3(1.4, 1.2, 2.2))
	patient.name = "Patient"
	add_child(patient)
	patient.position = Vector3(-4.6, 0, -2.2)
	patient.used.connect(func() -> void: talk_requested.emit())
	door = Interactable.new("밖으로 나가기", Vector3(1.4, 2.2, 0.6))
	door.name = "FrontDoor"
	door.enabled = false
	add_child(door)
	door.position = Vector3(DOOR_X, 0, D * 0.5 - 0.3)
	door.used.connect(func() -> void: exit_requested.emit())


## Where the hero stands after slamming the door: just inside it.
func spawn_point() -> Vector3:
	return to_global(Vector3(DOOR_X, 0, D * 0.5 - 1.3))


func door_point() -> Vector3:
	return to_global(Vector3(DOOR_X, 0, D * 0.5 - 0.3))


func patient_point() -> Vector3:
	return patient.global_position


## The injured resident lying on the bed (ResidentModel from his data; a capsule without assets/).
func show_patient(profile: Dictionary) -> void:
	patient_model = Node3D.new()
	patient_model.name = "PatientModel"
	add_child(patient_model)
	# Lying on his back on the bed: feet toward the room, head on the pillow by the north wall.
	patient_model.position = Vector3(-4.65, 0.62, -1.25)
	patient_model.rotation_degrees = Vector3(-90, 0, 0)
	var grey := MeshInstance3D.new()
	grey.name = "Greybox"
	var cap := CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = 1.7
	grey.mesh = cap
	grey.position.y = 0.85
	patient_model.add_child(grey)
	var model := ResidentModel.new()
	model.name = "Model"
	patient_model.add_child(model)
	model.show_resident(profile)


func _process(delta: float) -> void:
	_t += delta
	if _candle:  # a candle that breathes, never a strobe
		_candle.light_energy = 1.6 + sin(_t * 7.3) * 0.12 + sin(_t * 13.1) * 0.08


# ---------------- building ----------------

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	add_child(body)
	_box_shape(body, Vector3(0, -0.1, 0), Vector3(W, 0.2, D))
	# Walls block everyone (layer world), the half walls too.
	_box_shape(body, Vector3(0, WALL_H * 0.5, -D * 0.5 - 0.1), Vector3(W, WALL_H, 0.2))
	_box_shape(body, Vector3(-W * 0.5 - 0.1, WALL_H * 0.5, 0), Vector3(0.2, WALL_H, D))
	_box_shape(body, Vector3(W * 0.5 + 0.1, WALL_H * 0.5, 0), Vector3(0.2, WALL_H, D))
	_box_shape(body, Vector3(-1.0, WALL_H * 0.5, D * 0.5 + 0.1), Vector3(W - 2.0, WALL_H, 0.2))
	_box_shape(body, Vector3(DOOR_X, WALL_H * 0.5, D * 0.5 + 0.1), Vector3(1.6, WALL_H, 0.2))  # shut door
	_box_shape(body, Vector3(-4.65, 0.3, -2.2), Vector3(1.3, 0.6, 2.2))  # bed
	var placed := 0
	for ix in 3:
		for iz in 2:
			var at := Vector3(-W * 0.5 + 2.0 + ix * 4.0, 0, -D * 0.5 + 2.0 + iz * 4.0)
			placed += _prop("house_floor_b_4x4m", at, 0.0, 4.0, 4.0, true)
	if placed == 0:
		_grey_box(Vector3(0, -0.05, 0), Vector3(W, 0.1, D), Color(0.36, 0.3, 0.24))


func _build_walls() -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	# The wall modules stand along Z in their own files (0.2 × 4 m): along X they turn 90°.
	# Back walls, full height: north (with the window in the middle) and west.
	_wall("house_a_interior_wall_4x3m", Vector3(-4, 0, -hd), true, 4.0, WALL_H)
	_wall("house_a_windows_4x3m_01", Vector3(0, 0, -hd), true, 4.0, WALL_H)
	_wall("house_a_interior_wall_4x3m", Vector3(4, 0, -hd), true, 4.0, WALL_H)
	_wall("house_a_interior_wall_4x3m", Vector3(-hw, 0, -2), false, 4.0, WALL_H)
	_wall("house_a_interior_wall_4x3m", Vector3(-hw, 0, 2), false, 4.0, WALL_H)
	# Camera side, half height: east and south (the door in it).
	_wall("house_a_interior_wall_4x1_5m", Vector3(hw, 0, -2), false, 4.0, LOW_H)
	_wall("house_a_interior_wall_4x1_5m", Vector3(hw, 0, 2), false, 4.0, LOW_H)
	_wall("house_a_interior_wall_4x1_5m", Vector3(-4, 0, hd), true, 4.0, LOW_H)
	_wall("house_a_interior_wall_4x1_5m", Vector3(0, 0, hd), true, 4.0, LOW_H)
	if _prop("house_door_01", Vector3(DOOR_X, 0, hd), 90.0) == 0:
		_grey_box(Vector3(DOOR_X, 1.05, hd), Vector3(1.0, 2.1, 0.12), Color(0.35, 0.22, 0.14))
	# A roof that only throws shadow: the morning sun stays outside, the room is lit by its lamps.
	var roof := MeshInstance3D.new()
	roof.name = "ShadowRoof"
	var pm := BoxMesh.new()
	pm.size = Vector3(W + 1.0, 0.2, D + 1.0)
	roof.mesh = pm
	roof.position = Vector3(0, WALL_H + 0.1, 0)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(roof)


func _build_furniture() -> void:
	_prop("carpet_big_01", Vector3(0.4, 0.01, 0.6), 0.0, 4.0, 3.0)
	_prop("bed_01", Vector3(-4.65, 0, -2.2), 90.0, 1.4, 2.3)
	_prop("nightstand_01", Vector3(-5.4, 0, -0.5), 90.0, 0.5, 0.5)
	_prop("wardrobe_01", Vector3(-1.8, 0, -3.6), 0.0, 1.4, 0.6)
	_prop("bookcase_01", Vector3(1.2, 0, -3.65), 0.0, 1.2, 0.45)
	_prop("table_01", Vector3(0.6, 0, 1.0), 0.0, 1.6, 1.0)
	_prop("chair_01", Vector3(-0.5, 0, 1.2), 70.0, 0.55, 0.55)
	_prop("chair_02", Vector3(1.5, 0, 0.3), -120.0, 0.55, 0.55)
	_prop("medical_supplies_crate", Vector3(-3.4, 0, -3.5), 15.0, 0.7, 0.5)
	_prop("cardboard_box_01", Vector3(5.2, 0, 3.0), 20.0, 0.7, 0.7)
	_prop("cardboard_box_02", Vector3(4.6, 0, 3.3), -10.0, 0.6, 0.6)
	_prop("handheld_radio", Vector3(0.6, 0.78, 1.0), 30.0, 0.25, 0.15)
	_prop("tactical_flashlight", Vector3(1.0, 0.78, 0.8), 80.0, 0.25, 0.1)
	_prop("fireplace", Vector3(4.6, 0, -3.55), 0.0, 1.6, 0.6)


func _build_lights() -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = LAMP_COLOR
	lamp.light_energy = 2.2
	lamp.omni_range = 9.0
	lamp.shadow_enabled = true
	lamp.position = Vector3(0.6, 2.5, 0.6)
	add_child(lamp)
	_candle = OmniLight3D.new()
	_candle.name = "Candle"
	_candle.light_color = CANDLE_COLOR
	_candle.omni_range = 3.5
	_candle.position = Vector3(-5.3, 0.95, -0.5)
	add_child(_candle)
	var window := SpotLight3D.new()
	window.name = "WindowLight"
	window.light_color = WINDOW_COLOR
	window.light_energy = 3.0
	window.spot_range = 9.0
	window.spot_angle = 28.0
	window.shadow_enabled = true
	window.position = Vector3(0, 2.6, -D * 0.5 - 0.6)
	window.rotation_degrees = Vector3(-38, 0, 0)
	add_child(window)


## Black ground around the cut-away room: the camera sees past the half walls.
func _build_void() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Void"
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.02, 0.02, 0.03)
	mi.material_override = m
	mi.position.y = -0.25
	add_child(mi)


# ---------------- helpers ----------------

## Places a model; returns 1 if it loaded, 0 if not (greybox decides).
func _prop(model: String, at: Vector3, rot := 0.0, w := 0.0, d := 0.0, fill := false) -> int:
	var n := Models.prop(model, at, rot, w, d, fill)
	if n == null:
		return 0
	add_child(n)
	return 1


## A wall module `len` long at `at` (its centre line), running along X or along Z, at its own size.
## Grey box if the model is missing.
func _wall(model: String, at: Vector3, along_x: bool, len: float, h: float) -> void:
	if _prop(model, at, 90.0 if along_x else 0.0) == 0:
		var sz := Vector3(len, h, 0.15) if along_x else Vector3(0.15, h, len)
		_grey_box(at + Vector3(0, h * 0.5, 0), sz, Color(0.62, 0.58, 0.5))


func _box_shape(body: StaticBody3D, at: Vector3, sz: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = sz
	cs.shape = box
	cs.position = at
	body.add_child(cs)


func _grey_box(at: Vector3, sz: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	bm.material = m
	mi.mesh = bm
	mi.position = at
	add_child(mi)
