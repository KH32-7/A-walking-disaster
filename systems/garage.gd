extends Node
## Autoload `Garage`. Vehicles the base owns: crafted at the workshop or ridden out of a sortie.
## Design reference: docs/design/02-field.md "탈것" (가안).

const DEFS_DIR := "res://data/vehicles"
const TUNING: VehicleTuning = preload("res://data/vehicles/tuning/vehicle_tuning.tres")

## uid -> {"def_id": StringName, "durability": float, "lost"?: {"region_id", "position": [x, y, z],
## "yaw", "offered"}}. "lost" = left in the field: it waits there for one sortie to that region
## (02 "고립과 유실물" rule), then it is gone.
var owned: Dictionary = {}
## def id -> VehicleDef
var defs: Dictionary = {}
var _next_uid := 1


func _ready() -> void:
	_load_defs()
	SaveSystem.register_provider(&"garage", self)
	EventBus.sortie_started.connect(_on_sortie_started)
	EventBus.sortie_ended.connect(apply_sortie_result)


func get_def(def_id: StringName) -> VehicleDef:
	return defs.get(def_id)


func is_vehicle(def_id: StringName) -> bool:
	return defs.has(def_id)


## Adds one vehicle. durability < 0 = full. Returns its uid.
func add(def_id: StringName, durability: float = -1.0) -> StringName:
	var def := get_def(def_id)
	if def == null:
		push_error("Garage: unknown vehicle '%s'" % def_id)
		return &""
	var uid := StringName("veh_%d" % _next_uid)
	_next_uid += 1
	var full := def.max_durability
	owned[uid] = {"def_id": def_id, "durability": full if durability < 0.0 else clampf(durability, 0.0, full)}
	return uid


func remove(uid: StringName) -> bool:
	return owned.erase(uid)


func list() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(owned.keys())
	out.sort()
	return out


func def_of(uid: StringName) -> VehicleDef:
	return get_def(owned.get(uid, {}).get("def_id", &""))


func durability(uid: StringName) -> float:
	return float(owned.get(uid, {}).get("durability", 0.0))


func set_durability(uid: StringName, value: float) -> void:
	var def := def_of(uid)
	if def != null:
		owned[uid]["durability"] = clampf(value, 0.0, def.max_durability)


func is_broken(uid: StringName) -> bool:
	return owned.has(uid) and durability(uid) <= 0.0


## Left in the field on an earlier sortie (not at the base).
func is_away(uid: StringName) -> bool:
	return owned.has(uid) and owned[uid].has("lost")


## Vehicles that can go out now: at the base and not broken.
func ready_list() -> Array[StringName]:
	var out: Array[StringName] = []
	for uid in list():
		if not is_away(uid) and not is_broken(uid):
			out.append(uid)
	return out


## Vehicles waiting in `region_id` this sortie (VehicleSpawner puts them back where they were left).
func lost_in_region(region_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for uid in list():
		if is_away(uid) and StringName(owned[uid]["lost"].get("region_id", "")) == region_id:
			out.append(uid)
	return out


## Where a lost vehicle was left: Transform3D from the saved position and yaw.
func lost_transform(uid: StringName) -> Transform3D:
	var lost: Dictionary = owned.get(uid, {}).get("lost", {})
	var p: Array = lost.get("position", [0.0, 0.0, 0.0])
	return Transform3D(Basis(Vector3.UP, float(lost.get("yaw", 0.0))), Vector3(p[0], p[1], p[2]))


## EventBus.sortie_ended: the vehicle ridden out comes home (a field-found one is added), the base's
## vehicles still out there become lost. A lost one that already had its sortie and stayed out is gone.
func apply_sortie_result(result: Dictionary) -> void:
	var rode: Dictionary = result.get("vehicle", {})
	if not rode.is_empty():
		var rode_uid := StringName(rode.get("garage_uid", ""))
		if owned.has(rode_uid):
			owned[rode_uid].erase("lost")
			set_durability(rode_uid, float(rode.get("durability", 0.0)))
		else:
			add(StringName(rode.get("def_id", "")), float(rode.get("durability", 0.0)))
	for e: Dictionary in result.get("vehicles_left", []):
		var uid := StringName(e.get("garage_uid", ""))
		if not owned.has(uid):
			continue
		if bool(owned[uid].get("lost", {}).get("offered", false)):
			owned.erase(uid)
			continue
		set_durability(uid, float(e.get("durability", durability(uid))))
		owned[uid]["lost"] = {"region_id": String(result.get("region_id", "")),
			"position": e.get("position", [0.0, 0.0, 0.0]), "yaw": float(e.get("yaw", 0.0)), "offered": false}


## A new sortie: lost vehicles in another region are gone, the ones here get their one chance.
func _on_sortie_started(loadout: Dictionary) -> void:
	var region := StringName(loadout.get("region_id", &""))
	for uid: StringName in owned.keys():
		var lost: Dictionary = owned[uid].get("lost", {})
		if lost.is_empty():
			continue
		if bool(lost.get("offered", false)) or StringName(lost.get("region_id", "")) != region:
			owned.erase(uid)
		else:
			lost["offered"] = true


## Workshop repair cost to full: {&"scrap": n}, empty when not damaged.
func repair_cost(uid: StringName) -> Dictionary:
	var def := def_of(uid)
	if def == null:
		return {}
	var lost := def.max_durability - durability(uid)
	if lost <= 0.0:
		return {}
	return {&"scrap": ceili(lost / TUNING.durability_per_scrap)}


## Pays repair_cost through Economy and restores full durability.
func repair(uid: StringName) -> bool:
	var cost := repair_cost(uid)
	if cost.is_empty() or not Economy.apply({&"scrap": -int(cost[&"scrap"])}):
		return false
	set_durability(uid, def_of(uid).max_durability)
	return true


func save_data() -> Dictionary:
	var out := {}
	for uid: StringName in owned:
		out[String(uid)] = {"def_id": String(owned[uid]["def_id"]), "durability": owned[uid]["durability"]}
		if owned[uid].has("lost"):
			out[String(uid)]["lost"] = owned[uid]["lost"].duplicate(true)
	return {"owned": out, "next_uid": _next_uid}


func load_data(data: Dictionary) -> void:
	owned.clear()
	var saved: Dictionary = data.get("owned", {})
	for key in saved:
		var entry: Dictionary = saved[key]
		owned[StringName(key)] = {
			"def_id": StringName(entry.get("def_id", "")),
			"durability": float(entry.get("durability", 0.0)),
		}
		if entry.has("lost"):
			owned[StringName(key)]["lost"] = (entry["lost"] as Dictionary).duplicate(true)
	_next_uid = int(data.get("next_uid", owned.size() + 1))


func _load_defs() -> void:
	defs.clear()
	for file in ResourceLoader.list_directory(DEFS_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load(DEFS_DIR.path_join(file)) as VehicleDef
		if def == null or def.id == &"":
			push_error("Garage: %s is not a VehicleDef with an id" % file)
			continue
		defs[def.id] = def
