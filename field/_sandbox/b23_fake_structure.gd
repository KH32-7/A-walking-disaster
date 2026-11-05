extends StaticBody3D
## B-23 sandbox stand-in for a Lane C raid structure (wall, palisade, door). Not the real thing:
## Lane C's building decides durability and what a hit does. Shows the contract only:
## world layer, group RaidMarch.STRUCTURE_GROUP (+ GATE_GROUP for doors), take_damage(amount, info),
## and leaving the groups when it breaks. Walls take info.structure_damage_mult (root crusher x3).

signal broken(structure: Node3D)

@export var durability := 100.0
@export var is_gate := false
## Size of the box body and mesh.
@export var size := Vector3(6.0, 3.0, 1.0)

var hp := 0.0


func _ready() -> void:
	hp = durability
	collision_layer = 1 << (Enums.LAYER_WORLD - 1)
	collision_mask = 0
	add_to_group(RaidMarch.STRUCTURE_GROUP)
	if is_gate:
		add_to_group(RaidMarch.GATE_GROUP)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.4, 0.25) if is_gate else Color(0.45, 0.42, 0.36)
	mesh.material_override = mat
	add_child(mesh)


func take_damage(amount: float, info: Dictionary = {}) -> void:
	if hp <= 0.0:
		return
	var mult := 1.0 if is_gate else float(info.get("structure_damage_mult", 1.0))
	hp -= amount * mult
	if hp <= 0.0:
		remove_from_group(RaidMarch.STRUCTURE_GROUP)
		remove_from_group(RaidMarch.GATE_GROUP)
		broken.emit(self)
		queue_free()
