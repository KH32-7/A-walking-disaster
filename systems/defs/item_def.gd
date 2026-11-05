class_name ItemDef
extends Resource
## Equipment base type (weapon, armor, accessory, bag). Owner: Lane A (task A-07).
## Data: data/items/<id>.tres. Design reference: docs/design/05-gear.md "데이터 정의".
## One ItemDef -> many ItemInstances (rarity, upgrade, affixes) kept by Armory.

## Lowercase snake case, same as the file name.
@export var id: StringName
## Display name shown by Lane D.
@export var name: String
## Weapons use MAIN (light weapons may also go in SUB). Armor uses HEAD/BODY/LEGS/ACCESSORY.
@export var slot: Enums.EquipSlot = Enums.EquipSlot.MAIN
## Weapon family (= the player's class while it is the main weapon). Ignored for non-weapons.
@export var combat_class: Enums.CombatClass = Enums.CombatClass.GUN
## Light weapons (pistol, dagger, club) fit the SUB slot.
@export var light := false
@export var rarity_min: Enums.Rarity = Enums.Rarity.COMMON
## Stats at Common +0. Weapons: damage, pellets, attack_interval, range, noise, magazine (+ special
## keys Lane B reads, e.g. backstab_mult). Armor: defense, noise_mod, weight. Bags: grid_w, grid_h.
@export var base_stats: Dictionary = {}
@export var durability_max := 100.0
## Guns take one attachment (silencer, extended magazine, scope).
@export var attachment_slot := false
## Empty: every affix whose allowed_slots include this slot can roll.
@export var affix_pool_id: StringName
## Blueprint needed to craft it (A-09). Empty: not craftable.
@export var blueprint_id: StringName
## Footprint in the field bag grid (A-08).
@export var size := Vector2i(1, 1)


func is_weapon() -> bool:
	return slot == Enums.EquipSlot.MAIN
