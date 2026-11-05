extends SceneTree
## Test runner. Owner: Lane A (task A-02).
##
##   godot --headless --path . --script res://tests/run_tests.gd [-- --lane=core]
##
## Finds every res://tests/<lane>/test_*.gd (lanes: core, field, base, ui), creates it, and calls
## `run() -> bool`. A test may be `extends RefCounted` or `extends Node`; Node tests are added to
## the tree first (so `_ready` and autoloads work) and freed afterwards. `run()` may use `await`.
## Prints one line per test and exits with code 1 if any test failed or could not load.

const LANES := ["core", "field", "base", "ui"]
const TEST_ROOT := "res://tests"

var _failed := 0
var _passed := 0


func _initialize() -> void:
	# Wait one frame so autoloads are in the tree before any test runs.
	await process_frame
	var lanes := _requested_lanes()
	for lane in lanes:
		for path in _find_tests("%s/%s" % [TEST_ROOT, lane]):
			await _run_one(path)
	print("")
	print("TESTS: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _requested_lanes() -> Array:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lane="):
			var lane := arg.trim_prefix("--lane=")
			if lane in LANES:
				return [lane]
			push_error("Unknown lane '%s'. Use one of %s." % [lane, LANES])
			return []
	return LANES


## `-- --only=build_enter` runs only test files whose name contains that text (quick reruns).
func _wanted(file: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			return arg.trim_prefix("--only=") in file
	return true


func _find_tests(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file in dir.get_files():
		# Exported builds may list remapped files; tests only run from source.
		if file.begins_with("test_") and file.ends_with(".gd") and _wanted(file):
			found.append("%s/%s" % [dir_path, file])
	found.sort()
	return found


func _run_one(path: String) -> void:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		_report(path, false, "could not load (parse error?)")
		return
	var instance: Object = script.new()
	if not instance.has_method("run"):
		_report(path, false, "has no run() -> bool")
		_dispose(instance)
		return
	if instance is Node:
		root.add_child(instance)
	var ok: Variant = await instance.run()
	_report(path, ok == true, "" if ok is bool else "run() did not return bool")
	_dispose(instance)


func _dispose(instance: Object) -> void:
	if instance is Node:
		instance.queue_free()
	elif not (instance is RefCounted):
		instance.free()


func _report(path: String, ok: bool, note: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	var line := "%s  %s" % ["PASS" if ok else "FAIL", path]
	if note != "":
		line += "  (%s)" % note
	print(line)
