extends Node
## Autoload `SaveSystem`. Owner: Lane A (task A-04).
## Each lane registers ONE provider for its own state instead of the save system
## reaching into other lanes:
##     SaveSystem.register_provider(&"colony", Colony)
## A provider is any object with `save_data() -> Dictionary` and `load_data(Dictionary)`.
## Values must be plain data (no Objects, no Resources - store ids). Vector3, StringName, int vs
## float etc. survive the round trip: files use Godot's typed JSON (JSON.from_native).
##
## Files: <save_dir>/slot_<n>.json for slots 0..SLOT_COUNT-1, plus one "suspend" file written when
## the player quits mid-sortie. Loading the suspend file deletes it, so a death cannot be undone
## by reloading. Design reference: docs/design/01-flow-time.md "저장".

## Bump when the file layout or a provider's data changes incompatibly. Older files are refused.
const SAVE_VERSION := 1
const SLOT_COUNT := 3
## Slot number reported in game_saved / game_loaded for the suspend file.
const SUSPEND_SLOT := -1

## Tests point this somewhere else so they never touch real saves.
var save_dir := "user://saves"
## The slot autosaves go to. Set by save_slot / load_slot (new game: set it before the first save).
var current_slot := 0
## Autosave at morning start, right before a sortie and right after extraction.
var autosave_enabled := true

var _providers: Dictionary = {}


func _ready() -> void:
	register_provider(&"game", GameState)
	EventBus.day_started.connect(func(_day: int): autosave())
	EventBus.sortie_started.connect(func(_loadout: Dictionary): autosave())
	EventBus.extraction_completed.connect(func(_point_id: StringName): autosave())


func register_provider(key: StringName, provider: Object) -> void:
	assert(provider.has_method("save_data") and provider.has_method("load_data"),
		"Save provider %s must implement save_data() and load_data()" % key)
	_providers[key] = provider


# --- Slots ---

func save_slot(slot: int) -> bool:
	if not _valid_slot(slot):
		push_error("SaveSystem: no slot %d" % slot)
		return false
	if not _write(_slot_path(slot), _snapshot()):
		return false
	current_slot = slot
	EventBus.game_saved.emit(slot)
	return true


## Returns false and changes nothing if the file is missing, unreadable or from another version.
func load_slot(slot: int) -> bool:
	if not _valid_slot(slot):
		push_error("SaveSystem: no slot %d" % slot)
		return false
	var data := _read(_slot_path(slot))
	if data.is_empty():
		return false
	_apply(data)
	current_slot = slot
	EventBus.game_loaded.emit(slot)
	return true


func has_slot(slot: int) -> bool:
	return _valid_slot(slot) and FileAccess.file_exists(_slot_path(slot))


## Hardcore death and the "delete save" menu.
func delete_slot(slot: int) -> void:
	if has_slot(slot):
		DirAccess.remove_absolute(_slot_path(slot))


## Header for the load screen (Lane D):
## {"exists": bool, "compatible": bool, "day": int, "season": Enums.Season, "saved_at": int (unix)}
func slot_info(slot: int) -> Dictionary:
	var info := {"exists": has_slot(slot), "compatible": false, "day": 0, "season": 0, "saved_at": 0}
	if not info["exists"]:
		return info
	var data := _read(_slot_path(slot), true)
	if data.is_empty():
		return info
	info["compatible"] = int(data.get("version", -1)) == SAVE_VERSION
	info["day"] = int(data.get("day", 0))
	info["season"] = int(data.get("season", 0))
	info["saved_at"] = int(data.get("saved_at", 0))
	return info


func autosave() -> bool:
	if not autosave_enabled:
		return false
	return save_slot(current_slot)


# --- Suspend save (quitting mid-sortie) ---

func save_suspend() -> bool:
	var data := _snapshot()
	data["slot"] = current_slot
	if not _write(_suspend_path(), data):
		return false
	EventBus.game_saved.emit(SUSPEND_SLOT)
	return true


func has_suspend() -> bool:
	return FileAccess.file_exists(_suspend_path())


## Loads the suspend file and deletes it, even when it turns out to be unusable.
func load_suspend() -> bool:
	if not has_suspend():
		return false
	var data := _read(_suspend_path())
	DirAccess.remove_absolute(_suspend_path())
	if data.is_empty():
		return false
	_apply(data)
	current_slot = int(data.get("slot", current_slot))
	EventBus.game_loaded.emit(SUSPEND_SLOT)
	return true


# --- Internals ---

func _snapshot() -> Dictionary:
	var providers := {}
	for key: StringName in _providers:
		providers[String(key)] = _providers[key].save_data()
	return {
		"version": SAVE_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"day": GameState.day,
		"season": GameState.season(),
		"providers": providers,
	}


func _apply(data: Dictionary) -> void:
	var providers: Dictionary = data.get("providers", {})
	for key: StringName in _providers:
		# A provider missing from the file gets an empty dict so it resets to its defaults
		# instead of keeping state from the previous game.
		_providers[key].load_data(providers.get(String(key), {}))


func _write(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var text := JSON.stringify(JSON.from_native(data), "\t")
	# Write next to the target first so a crash mid-write never leaves a half file in the slot.
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(text)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("SaveSystem: cannot move %s into place (%s)" % [tmp, error_string(err)])
		return false
	return true


## Returns {} for a missing, corrupt or wrong-version file. `any_version` skips the version check
## (slot_info shows incompatible files as such instead of hiding them).
func _read(path: String, any_version := false) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("SaveSystem: %s is not valid JSON (line %d: %s)"
			% [path, json.get_error_line(), json.get_error_message()])
		return {}
	var data: Variant = JSON.to_native(json.data)
	if not (data is Dictionary) or not data.has("version"):
		push_warning("SaveSystem: %s is not a save file" % path)
		return {}
	if not any_version and int(data["version"]) != SAVE_VERSION:
		push_warning("SaveSystem: %s has version %s, expected %d - refused"
			% [path, data["version"], SAVE_VERSION])
		return {}
	return data


func _valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < SLOT_COUNT


func _slot_path(slot: int) -> String:
	return save_dir.path_join("slot_%d.json" % slot)


func _suspend_path() -> String:
	return save_dir.path_join("suspend.json")
