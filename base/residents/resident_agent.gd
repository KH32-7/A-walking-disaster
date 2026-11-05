class_name ResidentAgent
extends CharacterBody3D
## One resident walking around the base map (C-07). ResidentCrowd creates one per active resident
## and tells it where to go (set_target). Greybox body + name label; Lane D's character model
## (D-09) goes in via set_model(). Group GROUP, metadata resident_id.
## Needs above the head (07 "상태와 필요") are exposed as needs_state() / needs_changed for D's
## icons; the greybox label shows them as text meanwhile.

signal needs_changed(resident_id: StringName, states: Array)
signal arrived(resident_id: StringName)

const GROUP := &"base_resident"
const SPEED := 2.5
const SPEED_MOBILITY := 2.0   # 휠체어·거동 불편 (참여 조건 이동)
const ARRIVE_DISTANCE := 0.8
const BODY_RADIUS := 0.3
const BODY_HEIGHT := 1.6
const CHILD_SCALE := 0.65

var resident_id: StringName = &""
## What the crowd asked for: &"work", &"gather", &"sleep", &"idle".
var activity: StringName = &"idle"
var at_target := true

var _agent: NavigationAgent3D
var _label: Label3D
var _model_root: Node3D
var _look: Node3D  # CharacterLook (art/characters/character.tscn), or null → greybox capsule
var _applied_look: Dictionary = {}
var _last_states: Array = []

const CHARACTER_SCENE := "res://art/characters/character.tscn"
## Appearance presets (data/ui/appearance, Lane D) used until 입주 의식 (C-13 / D-13) sets one.
const CHILD_PRESET := &"child_yellow"
const ELDER_PRESET := &"elder_grey"
const ADULT_PRESETS: Array[StringName] = [&"worker_short", &"bob_teal", &"long_rain", &"tied_nurse"]


## Preset for a resident without a chosen look: by age, adults spread by id so they differ.
static func default_preset(r: Dictionary) -> StringName:
	match int(r.get("age_stage", Enums.AgeStage.ADULT)):
		Enums.AgeStage.BABY, Enums.AgeStage.CHILD:
			return CHILD_PRESET
		Enums.AgeStage.ELDER:
			return ELDER_PRESET
	return ADULT_PRESETS[absi(hash(StringName(r.get("id", &"")))) % ADULT_PRESETS.size()]


func setup(id: StringName) -> void:
	resident_id = id
	name = String(id)
	set_meta(&"resident_id", id)


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 1 << (Enums.LAYER_ALLY - 1)
	collision_mask = 1 << (Enums.LAYER_WORLD - 1)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	shape.shape = capsule
	shape.position.y = BODY_HEIGHT * 0.5
	add_child(shape)
	_model_root = Node3D.new()
	_model_root.name = "Model"
	add_child(_model_root)
	if ResourceLoader.exists(CHARACTER_SCENE):
		# Lane D's character (D-09): one scene for everyone, looks set by CharacterLook.apply().
		_look = (load(CHARACTER_SCENE) as PackedScene).instantiate()
		_model_root.add_child(_look)
	else:
		var mesh := MeshInstance3D.new()
		var capsule_mesh := CapsuleMesh.new()
		capsule_mesh.radius = BODY_RADIUS
		capsule_mesh.height = BODY_HEIGHT
		mesh.mesh = capsule_mesh
		mesh.position.y = BODY_HEIGHT * 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.6, 0.45)
		mesh.material_override = mat
		_model_root.add_child(mesh)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 36
	_label.outline_size = 10
	_label.pixel_size = 0.01
	_label.position.y = BODY_HEIGHT + 0.5
	add_child(_label)
	_agent = NavigationAgent3D.new()
	# The baked navmesh sits ~0.5 m above the floor (voxel rounding); a smaller value never
	# reaches the first path point from feet height.
	_agent.path_desired_distance = 1.0
	_agent.target_desired_distance = ARRIVE_DISTANCE
	_agent.radius = BODY_RADIUS
	add_child(_agent)
	refresh_from_colony()


## Replaces the greybox body with Lane D's character scene instance (D-09).
func set_model(model: Node3D) -> void:
	for child in _model_root.get_children():
		child.queue_free()
	_model_root.add_child(model)


func set_target(world_pos: Vector3, new_activity: StringName) -> void:
	activity = new_activity
	at_target = false
	_agent.target_position = world_pos


func target_position() -> Vector3:
	return _agent.target_position


## Reads the resident again (name, size, needs). Called by the crowd after each change.
func refresh_from_colony() -> void:
	var r := Colony.get_resident(resident_id)
	if r.is_empty():
		return
	var age := int(r["age_stage"])
	if _look != null:
		_look.set(&"age_stage", age)  # CharacterLook sizes the body by age (D-09)
		var appearance: Dictionary = r["appearance"].duplicate()
		if not appearance.has("preset"):
			appearance["preset"] = default_preset(r)
		if appearance != _applied_look:
			_applied_look = appearance
			_look.call(&"apply", appearance)
	else:
		var small := age == Enums.AgeStage.CHILD or age == Enums.AgeStage.BABY
		_model_root.scale = Vector3.ONE * (CHILD_SCALE if small else 1.0)
	var states := needs_state()
	var text := String(r["nickname"]) if r["nickname"] != "" else String(r["name"])
	if not states.is_empty():
		text += "\n" + " · ".join(PackedStringArray(states.map(func(s): return NEED_TEXT.get(s, String(s)))))
	_label.text = text
	if states != _last_states:
		_last_states = states
		needs_changed.emit(resident_id, states)


const NEED_TEXT := {
	&"hungry": "배고픔", &"tired": "피곤", &"sick": "아픔", &"injured": "다침",
	&"low_morale": "울적", &"leave_crisis": "떠나려 함", &"no_bed": "잘 곳 없음",
}


## Needs to show above the head (D draws icons): hungry, tired, sick, injured, low_morale,
## leave_crisis, no_bed. Thresholds are the work-efficiency ones (WorkRules / NeedsRules).
func needs_state() -> Array:
	var r := Colony.get_resident(resident_id)
	var out: Array = []
	if r.is_empty():
		return out
	if int(r["hunger"]) < WorkRules.HUNGRY_BELOW:
		out.append(&"hungry")
	if int(r["fatigue"]) > WorkRules.TIRED_ABOVE:
		out.append(&"tired")
	match int(r["health"]):
		Enums.HealthState.SICK:
			out.append(&"sick")
		Enums.HealthState.INJURED:
			out.append(&"injured")
	if r["leave_crisis"]:
		out.append(&"leave_crisis")
	elif int(r["morale"]) < NeedsRules.CRISIS_MORALE:
		out.append(&"low_morale")
	if r["bed_id"] == &"":
		out.append(&"no_bed")
	return out


func _physics_process(_delta: float) -> void:
	if at_target or _agent == null:
		return
	if NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) == 0:
		return  # map not ready yet
	if _agent.is_navigation_finished():
		at_target = true
		velocity = Vector3.ZERO
		arrived.emit(resident_id)
		return
	var next := _agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var r := Colony.get_resident(resident_id)
	var mobility: bool = not r.is_empty() and Enums.AccessNeed.MOBILITY in r["access_needs"]
	velocity = dir.normalized() * (SPEED_MOBILITY if mobility else SPEED)
	move_and_slide()
	look_at(global_position + velocity.normalized(), Vector3.UP)
