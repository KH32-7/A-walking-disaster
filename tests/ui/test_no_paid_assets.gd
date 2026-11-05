extends RefCounted
## D-02: the public repo holds no models, textures, audio or Unity packages outside the allowed
## places. Paid/licensed files belong in the private assets/ submodule only (root CLAUDE.md).
## Allowed: assets/ (submodule), addons/ (plugins), art/ (self-made only), ui/theme/fonts/ (OFL),
## icon.svg, and .godot/.

const BLOCKED := ["fbx", "glb", "gltf", "obj", "dae", "blend", "vrm", "png", "jpg", "jpeg", "tga", "psd",
	"exr", "hdr", "webp", "wav", "ogg", "mp3", "flac", "unitypackage", "zip"]
const ALLOWED_PREFIX := ["res://assets/", "res://addons/", "res://art/", "res://ui/theme/fonts/",
	"res://.godot/"]


func run() -> bool:
	var found := PackedStringArray()
	_walk("res://", found)
	for f in found:
		printerr("binary asset outside assets/: %s" % f)
	return found.is_empty()


func _walk(path: String, found: PackedStringArray) -> void:
	for p in ALLOWED_PREFIX:
		if path.begins_with(p):
			return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = false
	for sub in dir.get_directories():
		_walk(path.path_join(sub) + "/", found)
	for f in dir.get_files():
		if f.get_extension().to_lower() in BLOCKED:
			found.append(path.path_join(f))
