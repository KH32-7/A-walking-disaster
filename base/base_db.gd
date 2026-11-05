class_name BaseDB
## Read-only lookup for Lane C data defs (data/traits, data/jobs, later data/buildings ...).
## Loaded once on first use. Other lanes may call these getters too.

const TRAITS_DIR := "res://data/traits"
const JOBS_DIR := "res://data/jobs"
const BUILDINGS_DIR := "res://data/buildings"
const ZONES_DIR := "res://data/buildings/zones"

static var _traits: Dictionary = {}
static var _jobs: Dictionary = {}
static var _buildings: Dictionary = {}
static var _zones: Dictionary = {}


static func zones() -> Dictionary:
	if _zones.is_empty():
		_zones = _load_dir(ZONES_DIR)
	return _zones


static func get_zone(zone_id: StringName) -> ZoneDef:
	return zones().get(zone_id)


static func traits() -> Dictionary:
	if _traits.is_empty():
		_traits = _load_dir(TRAITS_DIR)
	return _traits


static func jobs() -> Dictionary:
	if _jobs.is_empty():
		_jobs = _load_dir(JOBS_DIR)
	return _jobs


static func buildings() -> Dictionary:
	if _buildings.is_empty():
		_buildings = _load_dir(BUILDINGS_DIR)
	return _buildings


static func get_building(def_id: StringName) -> BuildingDef:
	return buildings().get(def_id)


static func get_trait(trait_id: StringName) -> TraitDef:
	return traits().get(trait_id)


static func get_job(job_id: StringName) -> JobDef:
	return jobs().get(job_id)


## id -> Resource for every .tres in `dir_path`. Handles exported builds (".tres.remap").
static func _load_dir(dir_path: String) -> Dictionary:
	var result := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("BaseDB: missing data folder %s" % dir_path)
		return result
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var res: Resource = load("%s/%s" % [dir_path, name])
		var id: StringName = res.get("id") if res else &""
		if id == &"":
			push_error("BaseDB: %s/%s has no id" % [dir_path, name])
			continue
		if result.has(id):
			push_error("BaseDB: duplicate id %s in %s" % [id, dir_path])
		result[id] = res
	return result
