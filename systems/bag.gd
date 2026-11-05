extends Node
## Autoload `Bag`. Owner: Lane A (task A-08).
## The field bag: a grid inventory plus a 2-cell safe pocket. Lane B puts loot in it, Lane D draws it.
## Design reference: docs/design/02-field.md "루팅", 01-flow-time.md "실패 처리", 11-economy.md "보관".
##
## Grid: the equipped bag's grid (Armory.get_owner_summary(PLAYER_ID).bag_grid, default 4x5) plus
## bonus cells (work vest, perks) as a partial extra row under it. Call resize_for_player() in sortie prep.
## Entries hold either a stack of a resource id (size / stack from its ResourceDef) or one equipment
## item uid (size from its ItemDef). Items in the bag belong to Armory.BAG_ID until unloaded.
##
## Entry dictionaries (copies returned by entries()):
##   {"id": int, "kind": &"resource" | &"item", "ref": StringName, "amount": int,
##    "area": AREA_BAG | AREA_POCKET, "pos": Vector2i, "rotated": bool, "size": Vector2i (after rotation)}

const AREA_BAG := 0
const AREA_POCKET := 1
const POCKET_SIZE := Vector2i(2, 1)
const KIND_RESOURCE := &"resource"
const KIND_ITEM := &"item"
## Ids with no ResourceDef (ammo, consumables until A-09) take one cell and stack this high.
const DEFAULT_STACK := 20

var grid_size: Vector2i = Armory.DEFAULT_BAG_GRID
## Extra cells in a partial row under the grid (work vest +2, perks).
var bonus_cells := 0

## id -> entry Dictionary
var _entries: Dictionary = {}
var _next_id := 1


func _ready() -> void:
	SaveSystem.register_provider(&"bag", self)


# --- Grid ---

## Sortie prep: size the grid from what the player wears. Fails (returns false) if current contents
## would no longer fit; take things out first.
func resize_for_player() -> bool:
	var summary := Armory.get_owner_summary(Armory.PLAYER_ID)
	return resize(summary["bag_grid"], int(summary.get("bag_bonus_cells", 0)))


func resize(size: Vector2i, extra_cells: int = 0) -> bool:
	var old_size := grid_size
	var old_bonus := bonus_cells
	grid_size = size
	bonus_cells = clampi(extra_cells, 0, size.x)
	for id: int in _entries:
		var e: Dictionary = _entries[id]
		if e["area"] == AREA_BAG and not _fits(e["size"], e["pos"], AREA_BAG, id):
			grid_size = old_size
			bonus_cells = old_bonus
			return false
	_changed()
	return true


## True if `cell` exists in `area` (the bonus row is narrower than the grid).
func is_cell(cell: Vector2i, area: int = AREA_BAG) -> bool:
	if cell.x < 0 or cell.y < 0:
		return false
	if area == AREA_POCKET:
		return cell.x < POCKET_SIZE.x and cell.y < POCKET_SIZE.y
	if cell.x >= grid_size.x:
		return false
	return cell.y < grid_size.y or (cell.y == grid_size.y and cell.x < bonus_cells)


func cell_count(area: int = AREA_BAG) -> int:
	if area == AREA_POCKET:
		return POCKET_SIZE.x * POCKET_SIZE.y
	return grid_size.x * grid_size.y + bonus_cells


## Can something of `size` sit at `pos`? `ignore_id` lets an entry test its own new spot.
func can_place(size: Vector2i, pos: Vector2i, rotated: bool, area: int = AREA_BAG, ignore_id: int = -1) -> bool:
	return _fits(_rotated(size, rotated), pos, area, ignore_id)


# --- Reading ---

func entries(area: int = -1) -> Array:
	var out := []
	var ids := _entries.keys()
	ids.sort()
	for id: int in ids:
		if area < 0 or _entries[id]["area"] == area:
			out.append(_entries[id].duplicate())
	return out


func get_entry(entry_id: int) -> Dictionary:
	return _entries.get(entry_id, {}).duplicate()


## Entry covering `cell`, or {}.
func entry_at(cell: Vector2i, area: int = AREA_BAG) -> Dictionary:
	for id: int in _entries:
		var e: Dictionary = _entries[id]
		if e["area"] == area and Rect2i(e["pos"], e["size"]).has_point(cell):
			return e.duplicate()
	return {}


## Total of a resource id across the bag and pocket (ammo, medkits ...).
func count(resource_id: StringName) -> int:
	var total := 0
	for id: int in _entries:
		var e: Dictionary = _entries[id]
		if e["kind"] == KIND_RESOURCE and e["ref"] == resource_id:
			total += int(e["amount"])
	return total


func is_empty() -> bool:
	return _entries.is_empty()


# --- Adding (Lane B looting, sortie prep) ---

## Adds `amount` of a resource: tops up existing stacks first, then opens new stacks wherever they
## fit (upright first, then rotated). Returns how many did NOT fit.
func add_resource(resource_id: StringName, amount: int) -> int:
	var left := amount
	var stack := _stack_max(resource_id)
	for id: int in _sorted_ids():
		var e: Dictionary = _entries[id]
		if left <= 0:
			break
		if e["kind"] == KIND_RESOURCE and e["ref"] == resource_id and e["amount"] < stack:
			var moved := mini(stack - int(e["amount"]), left)
			e["amount"] += moved
			left -= moved
	while left > 0:
		var spot := _find_spot(_resource_size(resource_id))
		if spot.is_empty():
			break
		var moved := mini(stack, left)
		_insert(KIND_RESOURCE, resource_id, moved, AREA_BAG, spot["pos"], spot["rotated"])
		left -= moved
	if left != amount:
		_changed()
	return left


## Puts an equipment item (in storage or freshly created by loot) into the bag. Returns the entry id,
## or -1 if it does not fit or is not available.
func add_item(item_uid: StringName) -> int:
	var item := Armory.get_item(item_uid)
	if item == null or item.owner != Armory.STORAGE_ID:
		return -1
	var spot := _find_spot(Armory.get_def(item.def_id).size)
	if spot.is_empty():
		return -1
	Armory.set_carried(item_uid, true)
	var id := _insert(KIND_ITEM, item_uid, 1, AREA_BAG, spot["pos"], spot["rotated"])
	_changed()
	return id


## Sortie prep: move resources from base storage into the bag. Only what fits is taken.
## Returns the amount moved.
func take_from_storage(resource_id: StringName, amount: int) -> int:
	var available := mini(amount, Economy.get_amount(resource_id))
	if available <= 0:
		return 0
	var moved := available - add_resource(resource_id, available)
	if moved > 0:
		Economy.apply({resource_id: -moved})
	return moved


# --- Moving / removing (Lane D drag and drop, Lane B use and drop) ---

## Moves an entry to `pos` in `area` (AREA_POCKET for the safe pocket), optionally rotated.
func move(entry_id: int, pos: Vector2i, rotated: bool, area: int = AREA_BAG) -> bool:
	if not _entries.has(entry_id):
		return false
	var e: Dictionary = _entries[entry_id]
	var size := _rotated(_base_size(e), rotated)
	if not _fits(size, pos, area, entry_id):
		return false
	e["pos"] = pos
	e["rotated"] = rotated
	e["size"] = size
	e["area"] = area
	_changed()
	return true


## Takes `amount` (all if < 0) out of an entry and returns what was removed:
## {"kind", "ref", "amount"}. Removed items go back to Armory storage; the caller decides what
## happens next (Lane B drops it on the ground, Lane D's "버리기" deletes it with Armory.remove_item).
func remove(entry_id: int, amount: int = -1) -> Dictionary:
	if not _entries.has(entry_id):
		return {}
	var e: Dictionary = _entries[entry_id]
	var taken := int(e["amount"]) if amount < 0 else mini(amount, int(e["amount"]))
	e["amount"] -= taken
	if e["amount"] <= 0:
		_entries.erase(entry_id)
		if e["kind"] == KIND_ITEM:
			Armory.set_carried(e["ref"], false)
	_changed()
	return {"kind": e["kind"], "ref": e["ref"], "amount": taken}


## Uses up `amount` of a resource across stacks (ammo, medkit). False and no change if not enough.
func consume(resource_id: StringName, amount: int) -> bool:
	if count(resource_id) < amount:
		return false
	var left := amount
	for id: int in _sorted_ids():
		var e: Dictionary = _entries[id]
		if left > 0 and e["kind"] == KIND_RESOURCE and e["ref"] == resource_id:
			var used := mini(int(e["amount"]), left)
			e["amount"] -= used
			left -= used
			if e["amount"] <= 0:
				_entries.erase(id)
	_changed()
	return true


# --- End of sortie ---

## Extraction: resources go to Economy (storage cap applies), items to the Armory storage.
## Returns {"resources": {id: n}, "discarded": {id: n}, "items": [uid]} for the result screen.
func unload_to_base() -> Dictionary:
	var resources := {}
	var items: Array[StringName] = []
	for id: int in _entries:
		var e: Dictionary = _entries[id]
		if e["kind"] == KIND_RESOURCE:
			resources[e["ref"]] = resources.get(e["ref"], 0) + int(e["amount"])
		else:
			Armory.set_carried(e["ref"], false)
			items.append(e["ref"])
	_entries.clear()
	var result := Economy.apply_detailed(resources)
	_changed()
	return {"resources": result["applied"], "discarded": result["discarded"], "items": items}


## The player went down: everything outside the safe pocket is lost (items are deleted).
## Lane B calls this unless Settings "keep_bag_on_down" is on. Returns what was lost (same shape as
## unload_to_base without "discarded").
func lose_contents() -> Dictionary:
	var resources := {}
	var items: Array[StringName] = []
	for id: int in _entries.keys():
		var e: Dictionary = _entries[id]
		if e["area"] == AREA_POCKET:
			continue
		_entries.erase(id)
		if e["kind"] == KIND_RESOURCE:
			resources[e["ref"]] = resources.get(e["ref"], 0) + int(e["amount"])
		else:
			items.append(e["ref"])
			Armory.remove_item(e["ref"])
	_changed()
	return {"resources": resources, "items": items}


# --- Save provider ---

func save_data() -> Dictionary:
	var list := []
	for id: int in _sorted_ids():
		list.append(_entries[id])
	return {"grid_size": grid_size, "bonus_cells": bonus_cells, "next_id": _next_id, "entries": list}


func load_data(data: Dictionary) -> void:
	grid_size = data.get("grid_size", Armory.DEFAULT_BAG_GRID)
	bonus_cells = int(data.get("bonus_cells", 0))
	_next_id = int(data.get("next_id", 1))
	_entries.clear()
	for e: Dictionary in data.get("entries", []):
		_entries[int(e["id"])] = e.duplicate()
	_changed()


# --- Internals ---

func _insert(kind: StringName, ref: StringName, amount: int, area: int, pos: Vector2i, rotated: bool) -> int:
	var id := _next_id
	_next_id += 1
	var e := {"id": id, "kind": kind, "ref": ref, "amount": amount, "area": area, "pos": pos,
		"rotated": rotated, "size": Vector2i.ZERO}
	e["size"] = _rotated(_base_size(e), rotated)
	_entries[id] = e
	return id


## First free spot scanning rows top to bottom, upright before rotated. {} if none.
func _find_spot(size: Vector2i) -> Dictionary:
	for rotated in [false, true]:
		if rotated and size.x == size.y:
			continue
		var s := _rotated(size, rotated)
		for y in grid_size.y + 1:
			for x in grid_size.x:
				if _fits(s, Vector2i(x, y), AREA_BAG, -1):
					return {"pos": Vector2i(x, y), "rotated": rotated}
	return {}


func _fits(size: Vector2i, pos: Vector2i, area: int, ignore_id: int) -> bool:
	var rect := Rect2i(pos, size)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not is_cell(Vector2i(x, y), area):
				return false
	for id: int in _entries:
		var e: Dictionary = _entries[id]
		if id != ignore_id and e["area"] == area and rect.intersects(Rect2i(e["pos"], e["size"])):
			return false
	return true


func _base_size(e: Dictionary) -> Vector2i:
	if e["kind"] == KIND_ITEM:
		var item := Armory.get_item(e["ref"])
		return Armory.get_def(item.def_id).size if item != null else Vector2i.ONE
	return _resource_size(e["ref"])


func _resource_size(resource_id: StringName) -> Vector2i:
	var def := Economy.get_def(resource_id)
	return def.bag_size if def != null else Vector2i.ONE


func _stack_max(resource_id: StringName) -> int:
	var def := Economy.get_def(resource_id)
	return maxi(def.stack_max, 1) if def != null else DEFAULT_STACK


func _rotated(size: Vector2i, rotated: bool) -> Vector2i:
	return Vector2i(size.y, size.x) if rotated else size


func _sorted_ids() -> Array:
	var ids := _entries.keys()
	ids.sort()
	return ids


func _changed() -> void:
	EventBus.bag_changed.emit()
