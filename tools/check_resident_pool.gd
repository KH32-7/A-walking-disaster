extends SceneTree
## Validates the hand-written survivor pool. Owner: Lane A (task A-16).
##
##   godot --headless --path . --script res://tools/check_resident_pool.gd
##
## For every data/resident_pool/*.tres: is a ResidentTemplate, id == file name, unique id,
## schema fields and ranges (ResidentTemplate.validate), banned words
## (tools/resident_banned_words.txt). Lists entries still waiting for a human review.
## Exits 1 if any entry has an error. tests/core/test_resident_pool.gd runs the same checks in CI.
## What a machine cannot judge (tone, stereotypes, real people, "필요와 기여") is up to the
## reviewer: read docs/design/15-ai-features.md "검수 규칙" before setting reviewed = true.

const POOL_DIR := "res://data/resident_pool"


func _initialize() -> void:
	await process_frame
	var report := check_dir(POOL_DIR, ResidentTemplate.load_banned_words())
	for line in report["lines"]:
		print(line)
	print("Resident pool: %d entries, %d reviewed, %d waiting for review, %d with errors" % [
		report["count"], report["reviewed"], report["count"] - report["reviewed"], report["failed"]])
	quit(1 if report["failed"] > 0 else 0)


## Returns {count, reviewed, failed, lines, errors: {file: PackedStringArray}}.
static func check_dir(dir_path: String, banned: PackedStringArray) -> Dictionary:
	var report := {"count": 0, "reviewed": 0, "failed": 0, "lines": PackedStringArray(), "errors": {}}
	if banned.is_empty():
		report["lines"].append("WARNING  no banned words loaded (%s)" % ResidentTemplate.BANNED_WORDS_PATH)
	var seen := {}
	var files := Array(ResourceLoader.list_directory(dir_path))
	files.sort()
	for file: String in files:
		if not file.ends_with(".tres"):
			continue
		report["count"] += 1
		var errors := PackedStringArray()
		var t := load(dir_path.path_join(file)) as ResidentTemplate
		if t == null:
			errors.append("not a ResidentTemplate")
		else:
			errors = t.validate(banned)
			if String(t.id) != file.get_basename():
				errors.append("id '%s' does not match the file name" % t.id)
			if seen.has(t.id):
				errors.append("duplicate id '%s' (also in %s)" % [t.id, seen[t.id]])
			seen[t.id] = file
			if t.reviewed:
				report["reviewed"] += 1
		if errors.is_empty():
			report["lines"].append("%s  %s" % ["OK      " if t.reviewed else "REVIEW  ", file])
		else:
			report["failed"] += 1
			report["errors"][file] = errors
			report["lines"].append("ERROR   %s" % file)
			for e in errors:
				report["lines"].append("          - %s" % e)
	return report
