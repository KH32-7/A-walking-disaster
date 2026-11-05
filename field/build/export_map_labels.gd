extends SceneTree
## Writes RegionDef.map_labels (place names for the field map and minimap) from each region's map
## file levels/field/<id>/build/<id>_map.json, scaled like the layout (LayoutBuilder MAP_SCALE).
##   godot --headless --path . --script res://field/build/export_map_labels.gd
## Run it again after a map file changes. Only regions that have both a map file and a RegionDef.
##
## What becomes a label (floor 0 only, named zones):
##   landmark  landmarks[]                       water  zones kind "flooded"
##   area      zones kind "vegetation"           road   zones kind "road"
##   spot      zones kind "indoor" that no landmark already names or covers

const LAYOUT := preload("res://field/build/layout_builder.gd")
const MAP_FMT := "res://levels/field/%s/build/%s_map.json"
const ZONE_KINDS := {"flooded": &"water", "vegetation": &"area", "road": &"road", "indoor": &"spot"}


## RegionDef is only loaded at run time: it uses autoloads, which a --script main cannot name.
const REGIONS_DIR := "res://data/regions/"


func _initialize() -> void:
	var failed := false
	for file in ResourceLoader.list_directory(REGIONS_DIR):
		if not file.ends_with(".tres"):
			continue
		var def: Resource = load(REGIONS_DIR + file)
		if def == null or not &"map_labels" in def:
			continue
		var path := MAP_FMT % [def.id, def.id]
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			push_error("export_map_labels: cannot read %s" % path)
			failed = true
			continue
		def.set(&"map_labels", labels_from_map(data))
		var err := ResourceSaver.save(def, def.resource_path)
		if err != OK:
			push_error("export_map_labels: cannot save %s (%d)" % [def.resource_path, err])
			failed = true
			continue
		print("%s: %d labels" % [def.id, def.map_labels.size()])
	quit(1 if failed else 0)


static func labels_from_map(data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var landmark_rects: Array[Rect2] = []
	var names := {}
	for l: Dictionary in data.get("landmarks", []):
		if int(l.get("floor", 0)) != 0 or String(l.get("name", "")).is_empty():
			continue
		var c := _xz(l["center"])
		var sz := Vector2(l.get("size", [0, 0])[0], l.get("size", [0, 0])[1])
		landmark_rects.append(Rect2(c - sz * 0.5, sz))
		names[l["name"]] = true
		out.append({"text": String(l["name"]), "pos": c * LAYOUT.MAP_SCALE, "kind": &"landmark"})
	for z: Dictionary in data.get("zones", []):
		var kind: StringName = ZONE_KINDS.get(z.get("kind", ""), &"")
		var text := String(z.get("name", ""))
		if kind == &"" or text.is_empty() or int(z.get("floor", 0)) != 0 or names.has(text):
			continue
		var c := _xz(z["center"])
		if kind == &"spot" and landmark_rects.any(func(r: Rect2) -> bool: return r.has_point(c)):
			continue
		names[text] = true
		out.append({"text": text, "pos": c * LAYOUT.MAP_SCALE, "kind": kind})
	return out


static func _xz(v: Array) -> Vector2:
	return Vector2(float(v[0]), float(v[2]))
