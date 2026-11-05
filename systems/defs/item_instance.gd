class_name ItemInstance
extends RefCounted
## One concrete piece of equipment. Owner: Lane A (task A-07). Created and owned by Armory only;
## other lanes read it through Armory.get_item() / get_item_stats() and never change fields directly.
## Design reference: docs/design/05-gear.md "데이터 정의" (ItemInstance).

var uid: StringName
var def_id: StringName
var rarity: Enums.Rarity = Enums.Rarity.COMMON
## +0 .. +10 (A-09 changes it).
var upgrade_level := 0
var durability := 100.0
## [{"id": StringName, "value": int}]
var affixes: Array = []
## Essence engravings (A-10).
var engravings: Array = []
var attachment_id: StringName
## Armory.PLAYER_ID, a resident id, Armory.STORAGE_ID or Armory.LOST_ID.
var owner: StringName
## Enums.EquipSlot while equipped, -1 in storage or lost.
var slot := -1


func to_dict() -> Dictionary:
	return {
		"uid": uid, "def_id": def_id, "rarity": rarity, "upgrade_level": upgrade_level,
		"durability": durability, "affixes": affixes, "engravings": engravings,
		"attachment_id": attachment_id, "owner": owner, "slot": slot,
	}


static func from_dict(data: Dictionary) -> ItemInstance:
	var item := ItemInstance.new()
	item.uid = StringName(data.get("uid", ""))
	item.def_id = StringName(data.get("def_id", ""))
	item.rarity = int(data.get("rarity", 0)) as Enums.Rarity
	item.upgrade_level = int(data.get("upgrade_level", 0))
	item.durability = float(data.get("durability", 100.0))
	item.affixes = data.get("affixes", [])
	item.engravings = data.get("engravings", [])
	item.attachment_id = StringName(data.get("attachment_id", ""))
	item.owner = StringName(data.get("owner", ""))
	item.slot = int(data.get("slot", -1))
	return item
