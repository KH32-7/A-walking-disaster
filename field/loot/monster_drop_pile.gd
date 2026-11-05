class_name MonsterDropPile
extends StaticBody3D
## What a killed monster left behind (B-18). Sits on physics layer 7 (interactable), so
## Player.interact() picks it up: everything that fits goes into the Bag at once, the rest
## stays here. Gear is created in Armory only when it goes into the bag.
## MonsterDrops.drop_for() makes these.

## What went into the bag this time. Lane D can show a notice.
signal picked_up(resources: Dictionary, item_uids: Array[StringName])

## {resource_id: count} still on the ground.
var resources: Dictionary = {}
## [{"def_id": StringName, "rarity": int}] still on the ground.
var gear: Array[Dictionary] = []
var monster_id: StringName = &""


func _ready() -> void:
	collision_layer = 1 << (Enums.LAYER_INTERACTABLE - 1)
	collision_mask = 0


## Prompt the HUD shows next to the interact key (#28).
func interact_label() -> String:
	return "전리품 줍기"


## Player.interact() calls begin_open on interactables (same name as LootContainer).
func begin_open(_interactor: Node3D) -> bool:
	var got: Dictionary = {}
	for id: StringName in resources.keys():
		var added := Bag.try_add(id, resources[id])
		if added > 0:
			got[id] = added
			resources[id] -= added
		if resources[id] <= 0:
			resources.erase(id)
	var uids: Array[StringName] = []
	var left: Array[Dictionary] = []
	for entry in gear:
		var uid := Armory.create_item(entry.def_id, entry.rarity)
		if uid != &"" and Bag.add_item(uid) >= 0:
			uids.append(uid)
		else:
			if uid != &"":
				Armory.remove_item(uid)  # no room: it stays on the ground
			left.append(entry)
	gear = left
	picked_up.emit(got, uids)
	if is_empty():
		queue_free()
	return true


func is_empty() -> bool:
	return resources.is_empty() and gear.is_empty()
