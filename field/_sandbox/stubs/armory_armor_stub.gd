extends "res://field/_sandbox/stubs/armory_stub.gd"
## Sandbox-only: armory_stub.gd plus fake armor so B-05 can test the footstep noise bonus.
## Used by b05_noise_test.tscn and tests/field/test_noise.gd. Never edits systems/armory.gd.
## Numbers: docs/design/05-gear.md "방어구 기본형" (가안). Armor uses the "noise" stat key
## for its footstep bonus in meters.

const STUB_ARMOR := {
	&"stub_riot_helmet": {"base_id": &"riot_helmet", "defense": 14.0, "noise": 1.0},
	&"stub_scrap_armor": {"base_id": &"scrap_armor", "defense": 32.0, "noise": 3.0},
	&"stub_sneakers": {"base_id": &"sneakers", "defense": 3.0, "noise": -1.0},
}

## Heavy loadout: 1 + 3 = 4, so the +3 cap is visible.
const STUB_ARMOR_LOADOUT := {
	Enums.EquipSlot.HEAD: &"stub_riot_helmet",
	Enums.EquipSlot.BODY: &"stub_scrap_armor",
}


func get_equipped(owner_id: StringName, slot: Enums.EquipSlot) -> StringName:
	var found := super(owner_id, slot)
	if found != &"" or owner_id != PLAYER_ID:
		return found
	return STUB_ARMOR_LOADOUT.get(slot, &"")


func get_item_stats(item_uid: StringName) -> Dictionary:
	if STUB_ARMOR.has(item_uid):
		return STUB_ARMOR[item_uid].duplicate(true)
	return super(item_uid)
