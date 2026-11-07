class_name StartKit
extends Resource
## Extra starting gear for a new game in one save slot (시연용, 사용자 요청 2026-11-06).
## Data: data/start_kits/<id>.tres. SceneRouter.start_new_game(slot) applies the kit whose `slot`
## matches, after the normal start (resources, intro or starter pistol). A slot with no kit starts
## as usual. Delete or move the .tres to turn a kit off.

## Equipped items go here; anything else is an error in validate().
const PLACES: Array[StringName] = [&"main", &"sub", &"storage", &"bag"]
## GameState flag set by infinite_ammo. WeaponHolder.ammo_reserve() reads it (every gun, this save).
const FLAG_INFINITE_AMMO := &"start_kit_infinite_ammo"

## Save slot index (0-based: the title screen's "슬롯 2" is 1).
@export var slot := 0
## One entry per item, in order:
##   {"def_id": StringName (data/items), "rarity": int (Enums.Rarity, default the def's minimum),
##    "place": "main" | "sub" | "storage" | "bag" (default "storage"),
##    "essences": [essence id per slot] (free engraving, needs enough slots for the rarity)}
## "sub" takes only light weapons (Armory.can_go_in_slot). "bag" goes in the field bag, where the
## bag's 장착 menu swaps it in during a sortie.
@export var items: Array[Dictionary] = []
## Added to base storage (Economy) on top of SceneRouter.STARTER_RESOURCES.
@export var resources: Dictionary = {}
## Guns never run out of reserve ammo in this save (like the starter pistol).
@export var infinite_ammo := false


## Problems with the data (unknown ids, wrong place, too many essences). Empty = fine.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if slot < 0 or slot >= SaveSystem.SLOT_COUNT:
		errors.append("slot %d is not a save slot" % slot)
	for entry: Dictionary in items:
		var def_id := StringName(entry.get("def_id", &""))
		var def := Armory.get_def(def_id)
		if def == null:
			errors.append("unknown item '%s'" % def_id)
			continue
		var place := StringName(entry.get("place", &"storage"))
		if place not in PLACES:
			errors.append("%s: unknown place '%s'" % [def_id, place])
		elif place == &"main" and not Armory.can_go_in_slot(def_id, def.slot):
			errors.append("%s: cannot be equipped" % def_id)
		elif place == &"sub" and not Armory.can_go_in_slot(def_id, Enums.EquipSlot.SUB):
			errors.append("%s: only light weapons go in sub" % def_id)
		for essence_id in entry.get("essences", []):
			if not EssenceRules.is_essence(StringName(essence_id)):
				errors.append("%s: unknown essence '%s'" % [def_id, essence_id])
	return errors


## Gives everything to the player. Call right after a new game started (SaveSystem.reset_all()).
## Returns false if any entry could not be given (the rest still is).
func apply() -> bool:
	var ok := true
	for entry: Dictionary in items:
		ok = _give(entry) and ok
	if not resources.is_empty():
		ok = Economy.apply(resources) and ok
	if infinite_ammo:
		GameState.set_flag(FLAG_INFINITE_AMMO)
	return ok


func _give(entry: Dictionary) -> bool:
	var def_id := StringName(entry.get("def_id", &""))
	var uid := Armory.create_item(def_id, int(entry.get("rarity", -1)))
	if uid == &"":
		return false
	var essences: Array = entry.get("essences", [])
	for i in essences.size():
		if not Armory.grant_engraving(uid, StringName(essences[i]), i):
			push_error("StartKit: could not engrave %s on %s (slot %d)" % [essences[i], def_id, i])
			return false
	match StringName(entry.get("place", &"storage")):
		&"main":
			return Armory.equip(Armory.PLAYER_ID, Armory.get_def(def_id).slot, uid)
		&"sub":
			return Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.SUB, uid)
		&"bag":
			return Bag.add_item(uid) >= 0
	return true
