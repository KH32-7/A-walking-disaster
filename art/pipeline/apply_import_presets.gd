@tool
extends EditorScript
## Applies the D-02 import presets to everything under res://assets/. Owner: Lane D.
## Run from the script editor (File > Run) after adding a pack and letting Godot import it once.
## It only rewrites [params] in existing .import files, then reimports the changed files.
## Rules (art/pipeline/README.md):
##   textures      VRAM compressed + mipmaps; *_normal / *_n -> normal map; ui/icons -> lossless, no mipmaps
##   3D scenes     LODs, shadow meshes, tangents; animations only under characters/ and monsters/
##   audio         music/ambience loop, sfx do not

const ROOT := "res://assets"
const TEX := ["png", "jpg", "jpeg", "tga", "webp", "bmp", "exr", "hdr", "tif", "tiff"]
const SCENE := ["fbx", "glb", "gltf", "obj", "dae", "blend"]
const AUDIO := ["wav", "ogg", "mp3"]


func _run() -> void:
	var changed := PackedStringArray()
	_walk(ROOT, changed)
	if changed.is_empty():
		print("import presets: nothing to change")
		return
	EditorInterface.get_resource_filesystem().reimport_files(changed)
	print("import presets: reimported %d files" % changed.size())


static func params_for(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	var base := path.get_file().get_basename().to_lower()
	if ext in TEX:
		if path.begins_with(ROOT + "/ui/"):
			return {"compress/mode": 0, "mipmaps/generate": false}
		var p := {"compress/mode": 2, "mipmaps/generate": true}
		if base.ends_with("_normal") or base.ends_with("_n") or base.ends_with("_nrm"):
			p["compress/normal_map"] = 1
		return p
	if ext in SCENE:
		var animated := path.begins_with(ROOT + "/characters/") or path.begins_with(ROOT + "/monsters/")
		return {"meshes/generate_lods": true, "meshes/create_shadow_meshes": true,
			"meshes/ensure_tangents": true, "animation/import": animated}
	if ext in AUDIO:
		var loop := path.begins_with(ROOT + "/audio/music/") or path.begins_with(ROOT + "/audio/ambience/")
		if ext == "wav":
			return {"edit/loop_mode": 2 if loop else 0}
		return {"loop": loop}
	return {}


func _walk(dir_path: String, changed: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	if FileAccess.file_exists(dir_path + "/.gdignore"):
		return
	for sub in dir.get_directories():
		_walk(dir_path + "/" + sub, changed)
	for f in dir.get_files():
		if f.ends_with(".import"):
			var asset := dir_path + "/" + f.trim_suffix(".import")
			if _apply(asset, dir_path + "/" + f):
				changed.append(asset)


func _apply(asset: String, import_file: String) -> bool:
	var want := params_for(asset)
	if want.is_empty():
		return false
	var cfg := ConfigFile.new()
	if cfg.load(import_file) != OK:
		return false
	var dirty := false
	for k: String in want:
		if cfg.get_value("params", k, null) != want[k]:
			cfg.set_value("params", k, want[k])
			dirty = true
	if dirty:
		cfg.save(import_file)
	return dirty
