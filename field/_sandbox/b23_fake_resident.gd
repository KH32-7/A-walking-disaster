extends CharacterBody3D
## B-23 sandbox stand-in for a Lane C base resident: what raiders need to go after one.
## Layer 3 (ally) body with take_damage(amount, info). Leaves layer 3 when down so raiders let go.

signal hurt(hp: float)
signal down()

@export var max_hp := 60.0

var hp := 0.0


func _ready() -> void:
	hp = max_hp
	collision_layer = 1 << (Enums.LAYER_ALLY - 1)
	collision_mask = 1 << (Enums.LAYER_WORLD - 1)
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position.y = 0.9
	add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = CapsuleMesh.new()
	mesh.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.75, 0.5)
	mesh.material_override = mat
	add_child(mesh)


func take_damage(amount: float, _info: Dictionary = {}) -> void:
	if hp <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	hurt.emit(hp)
	if hp == 0.0:
		set_collision_layer_value(Enums.LAYER_ALLY, false)
		rotation.z = PI * 0.5
		down.emit()
