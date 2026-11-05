class_name LostGearPoint
extends StaticBody3D
## Where the player went down last sortie (B-11). Interact (F) to take the gear back.
## Sits on physics layer 7 (interactable). LostGearSpawner makes these.
## Design: docs/design/02-field.md "고립과 유실물"

## The gear went back into the bag (or storage if the bag was full). D can show a notice.
signal recovered(item_uids: Array[StringName])

var item_uids: Array[StringName] = []


func _ready() -> void:
	collision_layer = 1 << (Enums.LAYER_INTERACTABLE - 1)
	collision_mask = 0


## Prompt the HUD shows next to the interact key (#28).
func interact_label() -> String:
	return "유실물 줍기"


## Player.interact() calls begin_open on interactables, so this keeps LootContainer's name.
## Picks everything up at once.
func begin_open(_interactor: Node3D) -> bool:
	var got: Array[StringName] = []
	for uid in item_uids:
		if FieldState.recover_gear(uid):
			got.append(uid)
	recovered.emit(got)
	queue_free()
	return true
