extends Node
## Screenshot helper for map dressing (D-10). Loads a map assembly scene, optional overview camera.
##   godot --path . res://art/_preview/map_shot.tscn -- --scene=res://levels/field/flooded_mall/flooded_mall.tscn --overview=60 --shot=user://m.png

var _t := 0.0
var _shot := ""


func _ready() -> void:
	var scene := ""
	var overview := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene = a.trim_prefix("--scene=")
		elif a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		elif a.begins_with("--overview="):
			overview = float(a.trim_prefix("--overview="))
	if scene.is_empty():
		return
	var s := (load(scene) as PackedScene).instantiate()
	add_child(s)
	if overview > 0.0:
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = overview * 2.0
		cam.far = 600.0
		add_child(cam)
		cam.position = Vector3(overview * 1.2, overview * 1.6, overview * 1.2)
		cam.look_at(Vector3.ZERO)
		cam.make_current()


func _process(delta: float) -> void:
	_t += delta
	if _shot != "" and _t > 2.5 and _t - delta <= 2.5:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
