extends Node
## Autoload `Armory`. Owner: Lane A (tasks A-07 .. A-09).
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


# --- Save provider ---

func save_data() -> Dictionary:
	var items := []
	for uid: StringName in _items:
		items.append(_items[uid].to_dict())
	return {"next_id": _next_id, "items": items}


func load_data(data: Dictionary) -> void:
	_items.clear()
	_next_id = int(data.get("next_id", 1))
	for entry: Dictionary in data.get("items", []):
		var item := ItemInstance.from_dict(entry)
		if get_def(item.def_id) == null:
			push_warning("Armory: dropping saved item %s with unknown def '%s'" % [item.uid, item.def_id])
			continue
		_items[item.uid] = item


# --- Internals ---

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
