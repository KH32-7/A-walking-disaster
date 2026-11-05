extends RefCounted
## D-02: every row in assets/LICENSES.md has the four license checks filled.
## Skipped (passes) when the private submodule is not checked out.

const PATH := "res://assets/LICENSES.md"
const REQUIRED := ["다른 엔진", "상업 이용", "재배포 금지", "AI 제한", "출처 (URL)", "라이선스"]


func run() -> bool:
	if not FileAccess.file_exists(PATH):
		print("  (assets submodule not present, license check skipped)")
		return true
	var lines := FileAccess.get_file_as_string(PATH).split("\n")
	var header: PackedStringArray = []
	var ok := true
	for line in lines:
		var t := line.strip_edges()
		if not t.begins_with("|"):
			continue
		var cells := _cells(t)
		if header.is_empty():
			header = cells
			for col in REQUIRED:
				if not col in header:
					printerr("LICENSES.md header lacks column '%s'" % col)
					ok = false
			continue
		if cells.size() > 0 and cells[0].begins_with("---"):
			continue
		for col in REQUIRED:
			var i := header.find(col)
			if i < 0:
				continue
			if i >= cells.size() or cells[i].is_empty():
				printerr("LICENSES.md row '%s' has an empty '%s'" % [cells[0] if cells.size() > 0 else "?", col])
				ok = false
	return ok


func _cells(row: String) -> PackedStringArray:
	var out := PackedStringArray()
	var parts := row.trim_prefix("|").trim_suffix("|").split("|")
	for p in parts:
		out.append(p.strip_edges())
	return out
