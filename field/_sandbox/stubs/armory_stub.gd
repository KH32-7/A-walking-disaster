extends "res://systems/armory.gd"
## Sandbox-only stand-in for the `Armory` autoload until A-07 lands.
## field_sandbox.gd swaps it onto the Armory node with set_script(); the real
## systems/armory.gd file is never edited. Stub uids are answered here, anything
## else falls through to the real implementation, so this keeps working after A-07.
## Numbers: docs/design/05-gear.md "무기 기본형" (가안).

const STUB_ITEMS := {
	&"stub_pistol": {
		"base_id": &"pistol", "combat_class": Enums.CombatClass.GUN, "light": true,
		"damage": 18.0, "attack_interval": 0.35, "range": 18.0, "noise": 15.0, "magazine": 12,
	},
	&"stub_rifle": {
		"base_id": &"rifle", "combat_class": Enums.CombatClass.GUN, "light": false,
		"damage": 35.0, "attack_interval": 0.50, "range": 28.0, "noise": 20.0, "magazine": 20,
	},
	&"stub_dagger": {
		"base_id": &"dagger", "combat_class": Enums.CombatClass.BLADE, "light": true,
		"damage": 14.0, "attack_interval": 0.30, "range": 1.2, "noise": 3.0, "backstab_mult": 2.5,
	},
	&"stub_machete": {
		"base_id": &"machete", "combat_class": Enums.CombatClass.BLADE, "light": false,
		"damage": 22.0, "attack_interval": 0.40, "range": 1.6, "noise": 3.0,
	},
	&"stub_club": {
		"base_id": &"club", "combat_class": Enums.CombatClass.BLUNT, "light": true,
		"damage": 16.0, "attack_interval": 0.50, "range": 1.3, "noise": 5.0,
	},
	&"stub_pipe": {
		"base_id": &"pipe", "combat_class": Enums.CombatClass.BLUNT, "light": false,
		"damage": 24.0, "attack_interval": 0.60, "range": 1.5, "noise": 6.0,
	},
}

## Keys every stub item shares (no magic, no engravings yet).
const STUB_COMMON := {"element": Enums.Element.NONE, "essence_effects": [], "defense": 0.0}

## What the player wears in the sandbox when the real Armory has nothing equipped.
const STUB_LOADOUT := {
	Enums.EquipSlot.MAIN: &"stub_pistol",
	Enums.EquipSlot.SUB: &"stub_dagger",
}


func get_equipped(owner_id: StringName, slot: Enums.EquipSlot) -> StringName:
	var real := super(owner_id, slot)
	if real != &"" or owner_id != PLAYER_ID:
		return real
	return STUB_LOADOUT.get(slot, &"")


func get_item_stats(item_uid: StringName) -> Dictionary:
	if STUB_ITEMS.has(item_uid):
		var stats: Dictionary = STUB_COMMON.duplicate(true)
		stats.merge(STUB_ITEMS[item_uid], true)
		return stats
	return super(item_uid)
