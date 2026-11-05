class_name RescueDoor
extends StaticBody3D
## The stuck door in front of a TRAPPED rescue target (B-10). RescueTarget makes it.
## Layer 7: Player.interact() starts the lock picking (begin_open).
## Layer 3 (ally): monsters (B-07) treat it like a person to attack and call take_damage();
## at 0 health it breaks and the rescue turns into a defend event.
## Design reference: docs/design/02-field.md "구조 이벤트" (갇힘).

signal broken()

const SIZE := Vector3(1.4, 2.2, 0.15)
## In front of the person (their local -Z).
const OFFSET := Vector3(0.0, 1.1, -0.8)

var target: RescueTarget
var health := 1.0


func _ready() -> void:
	collision_layer = (1 << (Enums.LAYER_ALLY - 1)) | (1 << (Enums.LAYER_INTERACTABLE - 1))
	collision_mask = 0
	position = OFFSET
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = SIZE
	mesh.mesh = box_mesh
	add_child(mesh)


func begin_open(interactor: Node3D) -> bool:
	return target != null and target.begin_lockpick(interactor)


func take_damage(amount: float, _info: Dictionary = {}) -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if health == 0.0:
		broken.emit()


## [F] prompt words: pick the lock while standing still (B-10 갇힘).
func interact_label() -> String:
	if target == null or target.state != RescueTarget.State.WAITING:
		return ""
	return "문 따기"
