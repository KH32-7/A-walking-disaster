class_name UpgradeRules
## Pure upgrade / repair / crafting numbers (task A-09). No state: Armory calls these.
## Design reference: docs/design/05-gear.md "강화", "내구도", "제작". All numbers are 가안 and live here.

## Upgrade cost for target level n: scrap 10n + parts n.
const SCRAP_PER_LEVEL := 10
const PARTS_PER_LEVEL := 1
## n >= 6: rare parts (n - 5).
const RARE_PARTS_FROM := 6
## n >= 9: 2 family materials (계열 재료).
const FAMILY_FROM := 9
const FAMILY_QTY := 2
## Family materials (11 "계열 재료 4종"), indexed by Enums.Element - 1 (GREEN, STONE, WATER, LIGHT).
const FAMILY_MATERIALS: Array[StringName] = [&"vine_fiber", &"stone_shard", &"water_moss", &"neon_dust"]

## Worker (담당 주민) dexterity at or above this: upgrade cost -20% (each amount rounded up).
const DEX_DISCOUNT_MIN := 8
const DEX_DISCOUNT_PCT := 20

## Highest upgrade level allowed by facility level (index = level; 0 = not built).
const FACILITY_CAPS: Array[int] = [0, 3, 6, 10]
## Weapons are upgraded / repaired in the workshop, armor / accessories / bags in the sewing room.
const WEAPON_FACILITY := &"workshop"
const GEAR_FACILITY := &"sewing_room"

## Moving an upgrade to another item of the same slot loses 2 levels and costs 20 scrap.
const TRANSFER_LOSS := 2
const TRANSFER_SCRAP := 20

## Repair: 1 scrap per 10 lost durability (rounded up, so any damage costs at least 1).
const REPAIR_DURABILITY_PER_SCRAP := 10.0

## Crafted equipment: chance of Uncommon or better = 5% + dex x 3.5% (dex 10 -> 40%).
const CRAFT_HIGHER_BASE := 0.05
const CRAFT_HIGHER_PER_DEX := 0.035
## Rarity given when the roll succeeds (the design gives no split above Uncommon; 가안).
const CRAFT_HIGHER_RARITY := Enums.Rarity.UNCOMMON

const SCRAP := &"scrap"
const PARTS := &"parts"
const RARE_PARTS := &"rare_parts"


## Cost of upgrading to `level` (= current + 1). `family_mat` is used from FAMILY_FROM on.
## `family_mat` &"" = the first family material.
static func upgrade_cost(level: int, dex: int = 0, family_mat: StringName = &"") -> Dictionary:
	if family_mat == &"":
		family_mat = FAMILY_MATERIALS[0]
	var cost := {SCRAP: SCRAP_PER_LEVEL * level, PARTS: PARTS_PER_LEVEL * level}
	if level >= RARE_PARTS_FROM:
		cost[RARE_PARTS] = level - RARE_PARTS_FROM + 1
	if level >= FAMILY_FROM:
		cost[family_mat] = FAMILY_QTY
	if dex >= DEX_DISCOUNT_MIN:
		for id: StringName in cost:
			cost[id] = discounted(cost[id])
	return cost


## Amount after the dexterity discount, rounded up (integer math: no float drift).
static func discounted(amount: int) -> int:
	var keep := 100 - DEX_DISCOUNT_PCT
	return (amount * keep + 99) / 100


static func has_discount(dex: int) -> bool:
	return dex >= DEX_DISCOUNT_MIN


## Highest upgrade level a facility of `facility_level` allows.
static func facility_cap(facility_level: int) -> int:
	return FACILITY_CAPS[clampi(facility_level, 0, FACILITY_CAPS.size() - 1)]


## Building def id where an item of `slot` is upgraded and repaired.
static func facility_for_slot(slot: int) -> StringName:
	return WEAPON_FACILITY if slot == Enums.EquipSlot.MAIN or slot == Enums.EquipSlot.SUB else GEAR_FACILITY


## Family material of an element (Enums.Element), or &"" for NONE.
static func family_material(element: int) -> StringName:
	if element <= Enums.Element.NONE or element > FAMILY_MATERIALS.size():
		return &""
	return FAMILY_MATERIALS[element - 1]


## Scrap needed to repair `lost` durability.
static func repair_cost(lost: float) -> int:
	if lost <= 0.0:
		return 0
	return ceili(lost / REPAIR_DURABILITY_PER_SCRAP - 0.0001)


## Durability that `scrap` repairs.
static func repair_amount(scrap: int) -> float:
	return scrap * REPAIR_DURABILITY_PER_SCRAP


## Chance that crafted equipment comes out Uncommon or better.
static func craft_higher_chance(dex: int) -> float:
	return clampf(CRAFT_HIGHER_BASE + CRAFT_HIGHER_PER_DEX * dex, 0.0, 1.0)


## Rarity of a crafted item: `base` (the def's rarity_min) or CRAFT_HIGHER_RARITY.
static func roll_craft_rarity(dex: int, rng: RandomNumberGenerator, base: int = Enums.Rarity.COMMON) -> int:
	if rng.randf() < craft_higher_chance(dex):
		return maxi(base, CRAFT_HIGHER_RARITY)
	return base
