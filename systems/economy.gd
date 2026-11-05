extends Node
## Autoload `Economy`. Owner: Lane A (task A-06).
## Base storage of bulk resources (wood, stone, scrap, food, parts ...).
## Equipment instances live in `Armory`, not here.
## Design reference: docs/design/11-economy.md
##
## Storage cap: resources whose ResourceDef has `uses_storage_cap` (basic + processed goods) share
## one cap = BASE_STORAGE_CAP + bonus from buildings (Lane C calls set_cap_bonus). Anything over the
## cap is thrown away. Rare field goods, monster materials and special items are unlimited.
## Ids without a ResourceDef (e.g. essences until A-10) are unlimited too.

const DEFS_DIR := "res://data/resources"
## Main building's storage (design 11 "보관").
const BASE_STORAGE_CAP := 200

## resource_id -> amount
var amounts: Dictionary = {}
## Extra capacity from storage buildings. Lane C sets it; saved with the economy.
var cap_bonus := 0
## resource_id -> ResourceDef
var defs: Dictionary = {}


func _ready() -> void:
	_load_defs()
	SaveSystem.register_provider(&"economy", self)


func get_def(resource_id: StringName) -> ResourceDef:
	return defs.get(resource_id)


func get_amount(resource_id: StringName) -> int:
	return int(amounts.get(resource_id, 0))


func storage_cap() -> int:
	return BASE_STORAGE_CAP + cap_bonus


## Lane C: total capacity added by storage buildings (300 per warehouse in the design).
func set_cap_bonus(bonus: int) -> void:
	cap_bonus = maxi(bonus, 0)


## Sum of every resource that counts against the storage cap.
func capped_total() -> int:
	var total := 0
	for id: StringName in amounts:
		if uses_cap(id):
			total += get_amount(id)
	return total


func free_space() -> int:
	return maxi(storage_cap() - capped_total(), 0)


func uses_cap(resource_id: StringName) -> bool:
	var def := get_def(resource_id)
	return def != null and def.uses_storage_cap


func can_afford(cost: Dictionary) -> bool:
	for id: StringName in cost:
		if get_amount(id) < int(cost[id]):
			return false
	return true


## Positive values add, negative values spend. Returns false (and changes nothing)
## if any amount would drop below zero. Overflow past the storage cap is discarded silently;
## use apply_detailed() when the caller needs to report it.
func apply(changes: Dictionary) -> bool:
	return apply_detailed(changes)["ok"]


## Same as apply() but returns {"ok": bool, "applied": {id: n}, "discarded": {id: n}}.
## Spending happens first, then gains in the order given, so freed space can be refilled.
## Lane C uses this for the evening settlement report.
func apply_detailed(changes: Dictionary) -> Dictionary:
	var result := {"ok": false, "applied": {}, "discarded": {}}
	for id: StringName in changes:
		if get_amount(id) + int(changes[id]) < 0:
			return result
	result["ok"] = true

	var applied: Dictionary = result["applied"]
	var discarded: Dictionary = result["discarded"]
	for id: StringName in changes:
		var n := int(changes[id])
		if n < 0:
			amounts[id] = get_amount(id) + n
			applied[id] = n
	var space := free_space()
	for id: StringName in changes:
		var n := int(changes[id])
		if n <= 0:
			continue
		var kept := n
		if uses_cap(id):
			kept = mini(n, space)
			space -= kept
			if kept < n:
				discarded[id] = n - kept
		if kept > 0:
			amounts[id] = get_amount(id) + kept
			applied[id] = kept

	if not applied.is_empty():
		EventBus.resources_changed.emit(applied)
	return result


func save_data() -> Dictionary:
	return {"amounts": amounts, "cap_bonus": cap_bonus}


func load_data(data: Dictionary) -> void:
	amounts = data.get("amounts", {})
	cap_bonus = int(data.get("cap_bonus", 0))


func _load_defs() -> void:
	defs.clear()
	# list_directory handles exported (remapped) resources too.
	for file in ResourceLoader.list_directory(DEFS_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load(DEFS_DIR.path_join(file)) as ResourceDef
		if def == null or def.id == &"":
			push_error("Economy: %s is not a ResourceDef with an id" % file)
			continue
		if def.id != StringName(file.get_basename()):
			push_warning("Economy: %s has id '%s' (expected the file name)" % [file, def.id])
		defs[def.id] = def
