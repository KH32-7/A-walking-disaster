class_name LootData
extends RefCounted
## Read-only lookup over data/loot/ (B-08). Loads every .tres once, then answers by id or type.

const TABLE_DIR := "res://data/loot/tables/"
const CONTAINER_DIR := "res://data/loot/containers/"

static var _tables: Dictionary = {}  # id -> LootTable
static var _containers: Dictionary = {}  # LootSpot.ContainerType -> LootContainerDef
static var _loaded := false


static func table(table_id: StringName) -> LootTable:
	_load()
	return _tables.get(table_id)


## The table made for this region and container kind, or null.
static func find_table(region_id: StringName, type: LootSpot.ContainerType) -> LootTable:
	_load()
	for t: LootTable in _tables.values():
		if t.region_id == region_id and t.container_type == type:
			return t
	return null


static func container_def(type: LootSpot.ContainerType) -> LootContainerDef:
	_load()
	return _containers.get(type)


## Table for a spot: the spot's own id first, then the region's table, then the container default.
static func resolve_table(spot_table_id: StringName, region_id: StringName,
		type: LootSpot.ContainerType) -> LootTable:
	if spot_table_id != &"":
		return table(spot_table_id)
	var found := find_table(region_id, type)
	if found:
		return found
	var def := container_def(type)
	return table(def.loot_table_id) if def and def.loot_table_id != &"" else null


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for res in _load_dir(TABLE_DIR):
		if res is LootTable:
			_tables[res.id] = res
	for res in _load_dir(CONTAINER_DIR):
		if res is LootContainerDef:
			_containers[res.type] = res


static func _load_dir(dir: String) -> Array[Resource]:
	var out: Array[Resource] = []
	for file in ResourceLoader.list_directory(dir):
		if file.ends_with(".tres"):
			out.append(load(dir + file))
	return out
