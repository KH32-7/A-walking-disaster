extends SceneTree
## Loads every project GDScript so parse errors are caught even in scripts no scene uses yet.
## Owner: Lane A (task A-02). Run by tools/headless_check.sh:
##
##   godot --headless --path . --script res://tools/check_scripts.gd
##
## Skips addons/ (third-party) and hidden folders. Exits 1 if any script fails to load.

const SKIP_DIRS := ["res://addons", "res://.godot", "res://assets"]

var _bad: PackedStringArray = []
var _count := 0


func _initialize() -> void:
	await process_frame
	_scan("res://")
	print("Scripts checked: %d, failed: %d" % [_count, _bad.size()])
	for path in _bad:
		print("BROKEN  %s" % path)
	quit(1 if _bad.size() > 0 else 0)


func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		var sub_path := dir_path.path_join(sub)
		if sub.begins_with(".") or sub_path in SKIP_DIRS:
			continue
		_scan(sub_path)
	for file in dir.get_files():
		if file.ends_with(".gd"):
			_check(dir_path.path_join(file))


func _check(path: String) -> void:
	# Reloading the running script with CACHE_MODE_IGNORE would replace it mid-run.
	if path == get_script().resource_path:
		return
	_count += 1
	var script := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if script == null or not script.can_instantiate():
		_bad.append(path)
