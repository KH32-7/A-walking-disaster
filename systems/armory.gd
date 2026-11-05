extends Node
## Autoload `Armory`. Owner: Lane A (tasks A-07 .. A-09).
## A-09: upgrade (preview_upgrade / upgrade), upgrade transfer, repair, auto repair, crafting.
## Formulas live in UpgradeRules (systems/upgrade_rules.gd), recipes in data/recipes/.
## Owns every equipment ItemInstance (player's and residents') and who wears what.
## Lane B reads the player's equipped stats; Lane C reads residents' equipped stats.
## Player and residents use the same API: owner_id is PLAYER_ID or a resident id.
## Design reference: docs/design/05-gear.md, 06-magic-essence.md

const PLAYER_ID := &"player"
## Owner of items sitting in the base armory.
const STORAGE_ID := &"storage"
## Owner of gear dropped where the player went down (FieldState.lost_gear tracks where).
const LOST_ID := &"lost"
## Owner of gear carried in the field bag (Bag). Goes back to storage on extraction.
const BAG_ID := &"bag"

const ITEMS_DIR := "res://data/items"
const AFFIXES_DIR := "res://data/items/affixes"
const RECIPES_DIR := "res://data/recipes"

## Per rarity (design 05 "등급"): stat multiplier, affix count, essence slots.
const RARITY_MULT := [1.0, 1.15, 1.3, 1.5, 1.75]
const RARITY_AFFIXES := [0, 1, 2, 3, 3]
const RARITY_ESSENCE_SLOTS := [0, 1, 1, 2, 2]
## Upgrade bonus per level: weapon damage, armor defense.
const UPGRADE_DAMAGE_PER_LEVEL := 0.06
const UPGRADE_DEFENSE_PER_LEVEL := 0.08
const MAX_UPGRADE := 10
## Performance multiplier at 0 durability.
const BROKEN_MULT := 0.5
## Sum of armor noise_mod is capped at this (design 05 "방어구 기본형").
const ARMOR_NOISE_CAP := 3.0
## Bag grid when nothing is in the BAG slot.
const DEFAULT_BAG_GRID := Vector2i(4, 5)

const ARMOR_SLOTS := [Enums.EquipSlot.HEAD, Enums.EquipSlot.BODY, Enums.EquipSlot.LEGS,
	Enums.EquipSlot.ACCESSORY]

## def_id -> ItemDef
var defs: Dictionary = {}
## affix id -> Affix
var affixes: Dictionary = {}
## recipe id -> Recipe (A-09)
var recipes: Dictionary = {}
## Design 05 "자동 수리": repair gear at the evening settlement (run_auto_repair). Saved.
var auto_repair_enabled := false

## uid -> ItemInstance
var _items: Dictionary = {}
var _next_id := 1


func _ready() -> void:
	_load_defs()
	SaveSystem.register_provider(&"armory", self)


# --- Definitions ---

func get_def(def_id: StringName) -> ItemDef:
	return defs.get(def_id)


# --- Instances ---

## Makes a new item in storage. rarity < 0 uses the def's rarity_min. Affixes are rolled for the
## rarity (pass an rng for repeatable rolls). Returns the uid, or &"" for an unknown def.
func create_item(def_id: StringName, rarity: int = -1, rng: RandomNumberGenerator = null) -> StringName:
	var def := get_def(def_id)
	if def == null:
		push_error("Armory: unknown item def '%s'" % def_id)
		return &""
	if rng == null:
		rng = RandomNumberGenerator.new()
	var item := ItemInstance.new()
	item.uid = StringName("it_%06d" % _next_id)
	_next_id += 1
	item.def_id = def_id
	item.rarity = clampi(rarity if rarity >= 0 else def.rarity_min, 0, RARITY_MULT.size() - 1) as Enums.Rarity
	item.durability = def.durability_max
	item.affixes = _roll_affixes(def, item.rarity, rng)
	item.owner = STORAGE_ID
	_items[item.uid] = item
	EventBus.item_added.emit(item.uid)
	return item.uid


func remove_item(item_uid: StringName) -> void:
	var item := get_item(item_uid)
	if item == null:
		return
	if item.slot >= 0:
		unequip(item.owner, item.slot)
	_items.erase(item_uid)
	EventBus.item_removed.emit(item_uid)


## Read only. Change items through Armory functions.
func get_item(item_uid: StringName) -> ItemInstance:
	return _items.get(item_uid)


func has_item(item_uid: StringName) -> bool:
	return _items.has(item_uid)


## Items in the base armory (not worn, not lost). slot >= 0 keeps only items that fit that slot.
func list_storage(slot: int = -1) -> Array[StringName]:
	var out: Array[StringName] = []
	for uid: StringName in _items:
		var item: ItemInstance = _items[uid]
		if item.owner == STORAGE_ID and (slot < 0 or can_go_in_slot(item.def_id, slot)):
			out.append(uid)
	out.sort()
	return out


## Every item `owner_id` is wearing: {Enums.EquipSlot: uid}.
func list_equipped(owner_id: StringName) -> Dictionary:
	var out := {}
	for uid: StringName in _items:
		var item: ItemInstance = _items[uid]
		if item.owner == owner_id and item.slot >= 0:
			out[item.slot] = uid
	return out


## Wear: lose durability (melee hit 0.2, gun shot 0.1, armor per hit 0.5 - Lane B decides when).
func wear(item_uid: StringName, amount: float) -> void:
	var item := get_item(item_uid)
	if item != null:
		item.durability = maxf(item.durability - amount, 0.0)


## Lane B: the player went down. Worn gear becomes lost; set lost=false when it is recovered
## (it goes back to storage).
func set_lost(item_uid: StringName, lost: bool) -> void:
	var item := get_item(item_uid)
	if item == null:
		return
	if lost:
		if item.slot >= 0:
			var old_owner := item.owner
			var old_slot := item.slot
			item.slot = -1
			EventBus.equipment_changed.emit(old_owner, old_slot)
		item.owner = LOST_ID
	elif item.owner == LOST_ID:
		item.owner = STORAGE_ID


## Bag only: a stored item goes into the field bag (true) or back to storage (false).
func set_carried(item_uid: StringName, carried: bool) -> void:
	var item := get_item(item_uid)
	if item == null:
		return
	if carried and item.owner == STORAGE_ID:
		item.owner = BAG_ID
	elif not carried and item.owner == BAG_ID:
		item.owner = STORAGE_ID


# --- Equipping ---

## True if an item of this def may go in `slot`: weapons in MAIN, light weapons also in SUB,
## armor and bags only in their own slot.
func can_go_in_slot(def_id: StringName, slot: int) -> bool:
	var def := get_def(def_id)
	if def == null:
		return false
	if slot == Enums.EquipSlot.SUB:
		return def.is_weapon() and def.light
	return def.slot == slot


## Returns the item uid in `slot` for `owner_id` (PLAYER_ID or a resident id), or &"".
func get_equipped(owner_id: StringName, slot: Enums.EquipSlot) -> StringName:
	for uid: StringName in _items:
		var item: ItemInstance = _items[uid]
		if item.owner == owner_id and item.slot == slot:
			return uid
	return &""


## Puts a stored item on `owner_id`. Whatever was in that slot goes back to storage.
## Fails for lost items, items someone else is wearing (unequip them first) and slot mismatches.
func equip(owner_id: StringName, slot: Enums.EquipSlot, item_uid: StringName) -> bool:
	var item := get_item(item_uid)
	if item == null or owner_id in [STORAGE_ID, LOST_ID, BAG_ID, &""]:
		return false
	if item.owner == owner_id and item.slot == slot:
		return true
	if item.owner != STORAGE_ID and item.owner != owner_id:
		return false
	if not can_go_in_slot(item.def_id, slot):
		return false
	var previous := get_equipped(owner_id, slot)
	if previous != &"":
		_to_storage(previous)
	if item.owner == owner_id and item.slot >= 0:
		# Moving between this owner's slots (light weapon MAIN <-> SUB).
		var from_slot := item.slot
		item.slot = slot
		EventBus.equipment_changed.emit(owner_id, from_slot)
	item.owner = owner_id
	item.slot = slot
	EventBus.equipment_changed.emit(owner_id, slot)
	return true


func unequip(owner_id: StringName, slot: Enums.EquipSlot) -> bool:
	var uid := get_equipped(owner_id, slot)
	if uid == &"":
		return false
	_to_storage(uid)
	EventBus.equipment_changed.emit(owner_id, slot)
	return true


## Weapon family of the main weapon (= the player's class), or -1 with no main weapon.
func get_combat_class(owner_id: StringName) -> int:
	var uid := get_equipped(owner_id, Enums.EquipSlot.MAIN)
	if uid == &"":
		return -1
	return get_def(get_item(uid).def_id).combat_class


# --- Stats ---

## Final stats of an item instance after rarity, upgrade level, affixes and durability.
## Weapons: damage, pellets, attack_interval, range, noise, magazine (+ special keys from the def).
## Armor: defense, noise_mod, weight. Bags: grid_w, grid_h. Affix stats are added under their own
## key (attack_pct, crit_pctp, reload_pct, stamina_pct, max_hp, rescuer_guard_pct ...).
## `damage` already includes rarity, upgrade and attack_pct: do not apply the upgrade factor again.
## Also: def_id, slot, combat_class, light, rarity, upgrade_level, durability, broken,
## essence_slots, element, essence_effects, combo (the last three are filled by A-10).
func get_item_stats(item_uid: StringName) -> Dictionary:
	var item := get_item(item_uid)
	if item == null:
		return {}
	var def := get_def(item.def_id)
	if def == null:
		return {}
	var stats := def.base_stats.duplicate(true)
	var bonus := _affix_totals(item)
	stats.merge(bonus)  # affix keys that are not base stats
	var broken := item.durability <= 0.0
	var condition := BROKEN_MULT if broken else 1.0
	var rarity_mult: float = RARITY_MULT[item.rarity]

	if stats.has("damage"):
		stats["damage"] = float(stats["damage"]) * rarity_mult \
			* (1.0 + UPGRADE_DAMAGE_PER_LEVEL * item.upgrade_level) \
			* (1.0 + bonus.get("attack_pct", 0) / 100.0) * condition
	if stats.has("attack_interval"):
		stats["attack_interval"] = float(stats["attack_interval"]) \
			/ (1.0 + bonus.get("attack_speed_pct", 0) / 100.0)
	if stats.has("noise"):
		stats["noise"] = maxf(float(stats["noise"]) + bonus.get("noise_m", 0), 0.0)
	if stats.has("defense"):
		stats["defense"] = float(stats["defense"]) * rarity_mult \
			* (1.0 + UPGRADE_DEFENSE_PER_LEVEL * item.upgrade_level) \
			* (1.0 + bonus.get("defense_pct", 0) / 100.0) * condition
	if stats.has("noise_mod"):
		stats["noise_mod"] = float(stats["noise_mod"]) + bonus.get("noise_m", 0)

	stats["def_id"] = item.def_id
	stats["slot"] = def.slot
	stats["combat_class"] = def.combat_class if def.is_weapon() else -1
	stats["light"] = def.light
	stats["rarity"] = item.rarity
	stats["upgrade_level"] = item.upgrade_level
	stats["durability"] = item.durability
	stats["broken"] = broken
	stats["essence_slots"] = RARITY_ESSENCE_SLOTS[item.rarity]
	stats["element"] = Enums.Element.NONE  # TODO(A-10)
	stats["essence_effects"] = []  # TODO(A-10)
	stats["combo"] = null  # TODO(A-10)
	return stats


## Totals over everything `owner_id` wears, for movement / health / bag (Lane B, Lane C):
## defense (armor only), armor_noise (sum of armor noise_mod, capped at ARMOR_NOISE_CAP),
## max_hp, stamina_pct, crit_pctp, rescuer_guard_pct, move_speed_mult, bag_grid (Vector2i).
func get_owner_summary(owner_id: StringName) -> Dictionary:
	var summary := {"defense": 0.0, "armor_noise": 0.0, "max_hp": 0, "stamina_pct": 0,
		"crit_pctp": 0, "rescuer_guard_pct": 0, "move_speed_mult": 1.0, "bag_grid": DEFAULT_BAG_GRID}
	var equipped := list_equipped(owner_id)
	var bag_bonus := 0
	for slot: int in equipped:
		var stats := get_item_stats(equipped[slot])
		for key in ["max_hp", "stamina_pct", "crit_pctp", "rescuer_guard_pct"]:
			summary[key] += stats.get(key, 0)
		if slot in ARMOR_SLOTS:
			summary["defense"] += stats.get("defense", 0.0)
			summary["armor_noise"] += stats.get("noise_mod", 0.0)
			summary["move_speed_mult"] *= stats.get("move_speed_mult", 1.0)
			bag_bonus += int(stats.get("bag_bonus_cells", 0))
		elif slot == Enums.EquipSlot.BAG:
			summary["bag_grid"] = Vector2i(int(stats["grid_w"]), int(stats["grid_h"]))
	summary["armor_noise"] = minf(summary["armor_noise"], ARMOR_NOISE_CAP)
	summary["bag_bonus_cells"] = bag_bonus
	return summary


# --- Facilities (A-09) ---

## Facility state for upgrades, repair and crafting, read from Colony:
## {"level": highest level among completed buildings of `facility` (0 = none built),
##  "dex": best dexterity among its active workers (0 = nobody assigned)}.
## Every A-09 function that takes `ctx` accepts overrides {"facility_level": int, "dex": int}
## (previews of "what if", tests, debug). Upgrade previews also accept {"family_mat": id}.
func facility_context(facility: StringName, ctx: Dictionary = {}) -> Dictionary:
	if ctx.has("facility_level") and ctx.has("dex"):
		return {"level": int(ctx["facility_level"]), "dex": int(ctx["dex"])}
	var level := 0
	var dex := 0
	for building_uid: StringName in Colony.building_ids(facility):
		var b: Dictionary = Colony.get_building(building_uid)
		level = maxi(level, int(b.get("level", 1)))
		for worker in b.get("workers", []):
			var r: Dictionary = Colony.get_resident(StringName(worker))
			if r.is_empty() or int(r.get("status", Enums.ResidentStatus.ACTIVE)) != Enums.ResidentStatus.ACTIVE:
				continue
			var stats: Dictionary = r.get("stats", {})
			dex = maxi(dex, int(stats.get(&"dex", 0)))
	return {"level": int(ctx.get("facility_level", level)), "dex": int(ctx.get("dex", dex))}


# --- Upgrade (A-09) ---

## For the upgrade screen (D-12). Always returns:
##   ok, reason (&"" when ok; else no_item, lost, max_level, no_facility, facility_level,
##   no_worker, cost), uid, current_level, next_level, max_level (facility cap), facility,
##   facility_level, dex, discount (dex >= 8: -20%), cost {res: n} (empty at +10),
##   missing {res: shortfall}, family_options (Array of ids; non-empty from +9), family_mat,
##   stats (now), stats_after (at next_level; empty at +10).
func preview_upgrade(item_uid: StringName, ctx: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": &"", "uid": item_uid, "cost": {}, "missing": {},
		"family_options": [], "family_mat": &"", "stats": {}, "stats_after": {}}
	var item := get_item(item_uid)
	if item == null:
		out["reason"] = &"no_item"
		return out
	var def := get_def(item.def_id)
	var facility := UpgradeRules.facility_for_slot(def.slot)
	var fac := facility_context(facility, ctx)
	var next := item.upgrade_level + 1
	out["current_level"] = item.upgrade_level
	out["next_level"] = next
	out["facility"] = facility
	out["facility_level"] = fac["level"]
	out["max_level"] = UpgradeRules.facility_cap(fac["level"])
	out["dex"] = fac["dex"]
	out["discount"] = UpgradeRules.has_discount(fac["dex"])
	out["stats"] = get_item_stats(item_uid)
	if next <= MAX_UPGRADE:
		if next >= UpgradeRules.FAMILY_FROM:
			var options := _family_options(item)
			var chosen := StringName(ctx.get("family_mat", &""))
			out["family_options"] = options
			out["family_mat"] = chosen if chosen in options else options[0]
		out["cost"] = UpgradeRules.upgrade_cost(next, fac["dex"], out["family_mat"])
		out["missing"] = _missing(out["cost"])
		out["stats_after"] = _stats_at_level(item, next)

	if item.owner == LOST_ID:
		out["reason"] = &"lost"
	elif next > MAX_UPGRADE:
		out["reason"] = &"max_level"
	elif fac["level"] <= 0:
		out["reason"] = &"no_facility"
	elif next > out["max_level"]:
		out["reason"] = &"facility_level"
	elif fac["dex"] <= 0:
		out["reason"] = &"no_worker"
	elif not out["missing"].is_empty():
		out["reason"] = &"cost"
	out["ok"] = out["reason"] == &""
	return out


## Raises the item one level and pays through Economy. False (nothing changes) when
## preview_upgrade() says it is not possible.
func upgrade(item_uid: StringName, ctx: Dictionary = {}) -> bool:
	var preview := preview_upgrade(item_uid, ctx)
	if not preview["ok"] or not Economy.apply(_negated(preview["cost"])):
		return false
	var item := get_item(item_uid)
	item.upgrade_level = preview["next_level"]
	_emit_changed(item)
	return true


## Moving an upgrade to another item of the same slot (design 05 "강화 옮기기"):
## the target gets source level - 2, the source drops to +0, costs scrap 20.
## Returns ok, reason (&"" or no_item, same_item, lost, slot_mismatch, no_facility, no_worker,
## no_gain, cost), from_level, to_level, result_level, facility, facility_level, cost, missing.
func preview_transfer(from_uid: StringName, to_uid: StringName, ctx: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": &"", "cost": {UpgradeRules.SCRAP: UpgradeRules.TRANSFER_SCRAP},
		"missing": {}}
	var from := get_item(from_uid)
	var to := get_item(to_uid)
	if from == null or to == null:
		out["reason"] = &"no_item"
		return out
	var from_def := get_def(from.def_id)
	var to_def := get_def(to.def_id)
	var facility := UpgradeRules.facility_for_slot(to_def.slot)
	var fac := facility_context(facility, ctx)
	out["from_level"] = from.upgrade_level
	out["to_level"] = to.upgrade_level
	out["result_level"] = maxi(from.upgrade_level - UpgradeRules.TRANSFER_LOSS, 0)
	out["facility"] = facility
	out["facility_level"] = fac["level"]
	out["missing"] = _missing(out["cost"])
	if from_uid == to_uid:
		out["reason"] = &"same_item"
	elif from.owner == LOST_ID or to.owner == LOST_ID:
		out["reason"] = &"lost"
	elif from_def.slot != to_def.slot:
		out["reason"] = &"slot_mismatch"
	elif fac["level"] <= 0:
		out["reason"] = &"no_facility"
	elif fac["dex"] <= 0:
		out["reason"] = &"no_worker"
	elif out["result_level"] <= to.upgrade_level:
		out["reason"] = &"no_gain"
	elif not out["missing"].is_empty():
		out["reason"] = &"cost"
	out["ok"] = out["reason"] == &""
	return out


func transfer_upgrade(from_uid: StringName, to_uid: StringName, ctx: Dictionary = {}) -> bool:
	var preview := preview_transfer(from_uid, to_uid, ctx)
	if not preview["ok"] or not Economy.apply(_negated(preview["cost"])):
		return false
	var from := get_item(from_uid)
	var to := get_item(to_uid)
	to.upgrade_level = preview["result_level"]
	from.upgrade_level = 0
	_emit_changed(from)
	_emit_changed(to)
	return true


# --- Repair (A-09) ---

## 1 scrap per 10 lost durability, at the workshop (weapons) or sewing room (armor, bags).
## Returns ok, reason (&"" or no_item, lost, full, no_facility, cost), lost, facility, cost, missing.
func preview_repair(item_uid: StringName, ctx: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": &"", "lost": 0.0, "cost": {}, "missing": {}}
	var item := get_item(item_uid)
	if item == null:
		out["reason"] = &"no_item"
		return out
	var def := get_def(item.def_id)
	var facility := UpgradeRules.facility_for_slot(def.slot)
	var lost := maxf(def.durability_max - item.durability, 0.0)
	out["lost"] = lost
	out["facility"] = facility
	if lost > 0.0:
		out["cost"] = {UpgradeRules.SCRAP: UpgradeRules.repair_cost(lost)}
		out["missing"] = _missing(out["cost"])
	if item.owner == LOST_ID:
		out["reason"] = &"lost"
	elif lost <= 0.0:
		out["reason"] = &"full"
	elif facility_context(facility, ctx)["level"] <= 0:
		out["reason"] = &"no_facility"
	elif not out["missing"].is_empty():
		out["reason"] = &"cost"
	out["ok"] = out["reason"] == &""
	return out


## Restores full durability and pays the scrap.
func repair(item_uid: StringName, ctx: Dictionary = {}) -> bool:
	var preview := preview_repair(item_uid, ctx)
	if not preview["ok"] or not Economy.apply(_negated(preview["cost"])):
		return false
	var item := get_item(item_uid)
	item.durability = get_def(item.def_id).durability_max
	_emit_changed(item)
	return true


## Player toggle (design 05 "자동 수리"). Saved with the armory.
func set_auto_repair(enabled: bool) -> void:
	auto_repair_enabled = enabled


## Evening settlement: repairs damaged gear that belongs to `facility` (UpgradeRules.WEAPON_FACILITY
## or GEAR_FACILITY), worn gear first, then most damaged. Needs auto repair on, the facility built and
## someone working there (maintenance / tailoring). Spends scrap through Economy itself (do not add it
## to the settlement "changes" again); runs out gracefully with partial repairs.
## scrap_budget < 0 = whatever is in storage. Returns {"reason": &"" or disabled / no_facility /
## no_worker, "repaired": {uid: durability restored}, "scrap": spent}.
func run_auto_repair(facility: StringName, scrap_budget: int = -1, ctx: Dictionary = {}) -> Dictionary:
	var result := {"reason": &"", "repaired": {}, "scrap": 0}
	var fac := facility_context(facility, ctx)
	if not auto_repair_enabled:
		result["reason"] = &"disabled"
	elif fac["level"] <= 0:
		result["reason"] = &"no_facility"
	elif fac["dex"] <= 0:
		result["reason"] = &"no_worker"
	if result["reason"] != &"":
		return result
	var budget := Economy.get_amount(UpgradeRules.SCRAP)
	if scrap_budget >= 0:
		budget = mini(budget, scrap_budget)

	var damaged: Array[ItemInstance] = []
	for uid: StringName in _items:
		var item: ItemInstance = _items[uid]
		var def := get_def(item.def_id)
		if item.owner != LOST_ID and item.durability < def.durability_max \
				and UpgradeRules.facility_for_slot(def.slot) == facility:
			damaged.append(item)
	damaged.sort_custom(_repair_order)

	var plan := {}
	var spent := 0
	for item in damaged:
		var lost := get_def(item.def_id).durability_max - item.durability
		var pay := mini(UpgradeRules.repair_cost(lost), budget - spent)
		if pay <= 0:
			break
		plan[item.uid] = minf(lost, UpgradeRules.repair_amount(pay))
		spent += pay
	if spent == 0 or not Economy.apply({UpgradeRules.SCRAP: -spent}):
		return result
	for uid: StringName in plan:
		var item := get_item(uid)
		item.durability = minf(item.durability + plan[uid], get_def(item.def_id).durability_max)
		_emit_changed(item)
	result["repaired"] = plan
	result["scrap"] = spent
	return result


# --- Crafting (A-09) ---

func get_recipe(recipe_id: StringName) -> Recipe:
	return recipes.get(recipe_id)


## Recipe ids, sorted. facility &"" = all; by_worker: -1 all, 0 player-crafted only, 1 worker only.
func list_recipes(facility: StringName = &"", by_worker: int = -1) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in recipes:
		var recipe: Recipe = recipes[id]
		if (facility == &"" or recipe.facility == facility) \
				and (by_worker < 0 or recipe.by_worker == (by_worker == 1)):
			out.append(id)
	out.sort()
	return out


## GameState flag that unlocks a blueprint recipe: blueprint_<ItemDef.blueprint_id>, or
## blueprint_<output_id> when the def has no blueprint_id.
func blueprint_flag(recipe_id: StringName) -> StringName:
	var recipe := get_recipe(recipe_id)
	if recipe == null:
		return &""
	var def := get_def(recipe.output_id)
	var key := def.blueprint_id if def != null and def.blueprint_id != &"" else recipe.output_id
	return StringName("blueprint_%s" % key)


## Morning crafting by the player (equipment). Returns ok, reason (&"" or no_recipe, worker_only,
## blueprint, no_facility, facility_level, no_worker, cost), recipe_id, output_id, output_qty,
## equipment (bool), facility, facility_level, dex, cost, missing, blueprint_flag,
## higher_chance (equipment: chance of Uncommon or better).
func preview_craft(recipe_id: StringName, ctx: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": &"", "recipe_id": recipe_id, "cost": {}, "missing": {}}
	var recipe := get_recipe(recipe_id)
	if recipe == null:
		out["reason"] = &"no_recipe"
		return out
	var fac := facility_context(recipe.facility, ctx)
	var equipment := get_def(recipe.output_id) != null
	out["output_id"] = recipe.output_id
	out["output_qty"] = recipe.output_qty
	out["equipment"] = equipment
	out["facility"] = recipe.facility
	out["facility_level"] = fac["level"]
	out["dex"] = fac["dex"]
	out["cost"] = Dictionary(recipe.inputs).duplicate()
	out["missing"] = _missing(out["cost"])
	out["blueprint_flag"] = blueprint_flag(recipe_id) if recipe.blueprint_required else &""
	out["higher_chance"] = UpgradeRules.craft_higher_chance(fac["dex"]) if equipment else 0.0
	if recipe.by_worker:
		out["reason"] = &"worker_only"
	elif recipe.blueprint_required and not GameState.has_flag(out["blueprint_flag"]):
		out["reason"] = &"blueprint"
	elif fac["level"] <= 0:
		out["reason"] = &"no_facility"
	elif fac["level"] < recipe.facility_level:
		out["reason"] = &"facility_level"
	elif fac["dex"] <= 0:
		out["reason"] = &"no_worker"
	elif not out["missing"].is_empty():
		out["reason"] = &"cost"
	out["ok"] = out["reason"] == &""
	return out


## Crafts once and pays through Economy. Equipment goes to storage with a rarity rolled from the
## worker's dexterity (pass an rng for repeatable rolls). Returns {"ok", "reason", "uid" (equipment),
## "rarity", "resources" {id: n} (resource outputs)}.
func craft(recipe_id: StringName, ctx: Dictionary = {}, rng: RandomNumberGenerator = null) -> Dictionary:
	var preview := preview_craft(recipe_id, ctx)
	var out := {"ok": false, "reason": preview["reason"], "uid": &"", "rarity": -1, "resources": {}}
	if not preview["ok"]:
		return out
	if not Economy.apply(_negated(preview["cost"])):
		out["reason"] = &"cost"
		return out
	var recipe := get_recipe(recipe_id)
	if preview["equipment"]:
		if rng == null:
			rng = RandomNumberGenerator.new()
		var def := get_def(recipe.output_id)
		var rarity := UpgradeRules.roll_craft_rarity(preview["dex"], rng, def.rarity_min)
		out["uid"] = create_item(recipe.output_id, rarity, rng)
		out["rarity"] = rarity
	else:
		Economy.apply({recipe.output_id: recipe.output_qty})
		out["resources"] = {recipe.output_id: recipe.output_qty}
	out["ok"] = true
	return out


## Lane C's evening settlement: what `count` crafts of a worker recipe (ammo, consumables) would use
## and make, limited by `stock` (resource_id -> amount; empty = current Economy amounts).
## Does NOT change Economy: add "changes" to the settlement report and A applies it.
## Returns {"ok", "reason" (&"" or no_recipe, not_worker_recipe), "count" (crafts possible),
## "consumed" {id: n}, "produced" {id: n}, "changes" {id: net}}.
func craft_by_worker(recipe_id: StringName, count: int, stock: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": &"", "count": 0, "consumed": {}, "produced": {}, "changes": {}}
	var recipe := get_recipe(recipe_id)
	if recipe == null:
		out["reason"] = &"no_recipe"
		return out
	if not recipe.by_worker:
		out["reason"] = &"not_worker_recipe"
		return out
	var made := maxi(count, 0)
	for id: StringName in recipe.inputs:
		var have := int(stock.get(id, 0)) if not stock.is_empty() else Economy.get_amount(id)
		made = mini(made, have / maxi(recipe.inputs[id], 1))
	out["ok"] = true
	out["count"] = made
	if made == 0:
		return out
	var consumed: Dictionary = out["consumed"]
	var produced: Dictionary = out["produced"]
	var changes: Dictionary = out["changes"]
	for id: StringName in recipe.inputs:
		consumed[id] = recipe.inputs[id] * made
		changes[id] = changes.get(id, 0) - recipe.inputs[id] * made
	produced[recipe.output_id] = recipe.output_qty * made
	changes[recipe.output_id] = changes.get(recipe.output_id, 0) + recipe.output_qty * made
	return out


# --- Save provider ---

func save_data() -> Dictionary:
	var items := []
	for uid: StringName in _items:
		items.append(_items[uid].to_dict())
	return {"next_id": _next_id, "items": items, "auto_repair": auto_repair_enabled}


func load_data(data: Dictionary) -> void:
	_items.clear()
	_next_id = int(data.get("next_id", 1))
	auto_repair_enabled = bool(data.get("auto_repair", false))
	for entry: Dictionary in data.get("items", []):
		var item := ItemInstance.from_dict(entry)
		if get_def(item.def_id) == null:
			push_warning("Armory: dropping saved item %s with unknown def '%s'" % [item.uid, item.def_id])
			continue
		_items[item.uid] = item


# --- Internals ---

## Equipped items changed stats: tell whoever shows that owner.
func _emit_changed(item: ItemInstance) -> void:
	if item.slot >= 0:
		EventBus.equipment_changed.emit(item.owner, item.slot)


## {id: shortfall} for everything in `cost` that Economy does not have enough of.
func _missing(cost: Dictionary) -> Dictionary:
	var missing := {}
	for id: StringName in cost:
		var short := int(cost[id]) - Economy.get_amount(id)
		if short > 0:
			missing[id] = short
	return missing


func _negated(cost: Dictionary) -> Dictionary:
	var out := {}
	for id: StringName in cost:
		out[id] = -int(cost[id])
	return out


## get_item_stats() as if the item were at `level`.
func _stats_at_level(item: ItemInstance, level: int) -> Dictionary:
	var saved := item.upgrade_level
	item.upgrade_level = level
	var stats := get_item_stats(item.uid)
	item.upgrade_level = saved
	return stats


## Auto repair order: worn gear first, then lowest durability, then uid.
func _repair_order(a: ItemInstance, b: ItemInstance) -> bool:
	if (a.slot >= 0) != (b.slot >= 0):
		return a.slot >= 0
	if a.durability != b.durability:
		return a.durability < b.durability
	return String(a.uid) < String(b.uid)


## Family materials allowed for the +9/+10 cost: the item's element material once it has one
## (A-10), otherwise any of the four, the one with the most in storage first.
func _family_options(item: ItemInstance) -> Array:
	var element: int = get_item_stats(item.uid).get("element", Enums.Element.NONE)
	var own := UpgradeRules.family_material(element)
	if own != &"":
		return [own]
	var options: Array = []
	for i in UpgradeRules.FAMILY_MATERIALS.size():
		options.append([UpgradeRules.FAMILY_MATERIALS[i], Economy.get_amount(UpgradeRules.FAMILY_MATERIALS[i]), i])
	options.sort_custom(func(a: Array, b: Array) -> bool:
		return a[1] > b[1] if a[1] != b[1] else a[2] < b[2])
	return options.map(func(entry: Array) -> StringName: return entry[0])


func _to_storage(item_uid: StringName) -> void:
	var item := get_item(item_uid)
	item.owner = STORAGE_ID
	item.slot = -1


func _roll_affixes(def: ItemDef, rarity: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array[Affix] = []
	for id: StringName in affixes:
		var affix: Affix = affixes[id]
		if def.slot in affix.allowed_slots or (def.light and Enums.EquipSlot.SUB in affix.allowed_slots):
			pool.append(affix)
	pool.sort_custom(func(a: Affix, b: Affix): return String(a.id) < String(b.id))
	var rolled := []
	for i in mini(RARITY_AFFIXES[rarity], pool.size()):
		var affix: Affix = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		rolled.append({"id": affix.id, "value": rng.randi_range(affix.min_value, affix.max_value)})
	return rolled


func _affix_totals(item: ItemInstance) -> Dictionary:
	var totals := {}
	for entry: Dictionary in item.affixes:
		var affix: Affix = affixes.get(StringName(entry["id"]))
		if affix == null:
			continue
		totals[affix.stat] = totals.get(affix.stat, 0) + int(entry["value"])
	return totals


func _load_defs() -> void:
	defs.clear()
	affixes.clear()
	for file in ResourceLoader.list_directory(ITEMS_DIR):
		if file.ends_with(".tres"):
			var def := load(ITEMS_DIR.path_join(file)) as ItemDef
			if def == null or def.id == &"":
				push_error("Armory: %s is not an ItemDef with an id" % file)
				continue
			defs[def.id] = def
	for file in ResourceLoader.list_directory(AFFIXES_DIR):
		if file.ends_with(".tres"):
			var affix := load(AFFIXES_DIR.path_join(file)) as Affix
			if affix == null or affix.id == &"":
				push_error("Armory: %s is not an Affix with an id" % file)
				continue
			affixes[affix.id] = affix
	recipes.clear()
	for file in ResourceLoader.list_directory(RECIPES_DIR):
		if file.ends_with(".tres"):
			var recipe := load(RECIPES_DIR.path_join(file)) as Recipe
			if recipe == null or recipe.id == &"":
				push_error("Armory: %s is not a Recipe with an id" % file)
				continue
			recipes[recipe.id] = recipe
