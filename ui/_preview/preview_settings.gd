extends Node3D
## D-15 preview: settings tabs, key capture / confirm, the title's quick accessibility screen and
## the colour-blind filters, over a small colourful scene so the filter and blur show.
## Settings go to a throwaway file (user://preview_settings.cfg), never the real one.
## Optional: -- --view=access|graphics|audio|controls|difficulty|capture|confirm|quick|large|
##   protan|deutan|tritan --shot=user://x.png

const VIEWS := {
	"access": {"tab": &"access"},
	"graphics": {"tab": &"graphics"},
	"audio": {"tab": &"audio"},
	"controls": {"tab": &"controls", "focus": &"reload"},
	"difficulty": {"tab": &"difficulty", "focus": &"permadeath"},
	"capture": {"tab": &"controls", "focus": &"reload"},
	"confirm": {"tab": &"controls", "focus": &"reload"},
	"quick": {"quick": true},
	"large": {"quick": true, "set": {&"text_size": 2, &"high_contrast": true}},
	"protan": {"tab": &"access", "focus": &"color_filter", "set": {&"color_filter": 1}},
	"deutan": {"tab": &"access", "focus": &"color_filter", "set": {&"color_filter": 2}},
	"tritan": {"tab": &"access", "focus": &"color_filter", "set": {&"color_filter": 3}},
}

var _shot := ""
var _view := "access"
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # screens pause the tree
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
	Settings.path = "user://preview_settings.cfg"
	Settings.values = Settings.DEFAULTS.duplicate()
	var v: Dictionary = VIEWS.get(_view, VIEWS["access"])
	var sets: Dictionary = v.get("set", {})
	for k: StringName in sets:
		Settings.set_value(k, sets[k])
	_scene()
	if v.get("quick", false):
		UI.open(&"accessibility_quick")
	else:
		UI.open(&"settings", {"tab": v.get("tab", &"access"), "focus": v.get("focus", &"")})
	if _view == "capture" or _view == "confirm":
		await get_tree().process_frame
		var s: SettingsScreen = UI.get_screen(&"settings")
		if _view == "capture":
			s.start_capture(&"reload")
		else:
			var k := InputEventKey.new()
			k.physical_keycode = KEY_F  # already "interact": shows the swap line
			s.confirm_binding(&"reload", k)


func _scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("5a7a6a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d0d8c8")
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16
	add_child(cam)
	cam.position = Vector3(10, 12, 14)
	cam.look_at(Vector3(0, 0, 0))
	_box(Vector3(0, -0.1, 0), Vector3(30, 0.2, 30), Color("6d6a62"))
	# red / green / blue / yellow props so the colour filters have something to change
	var cols := [Color("d9453b"), Color("5fc46b"), Color("3fb0e6"), Color("f6c744"), Color("b072e8"), Color("f29a3a")]
	for i in cols.size():
		_box(Vector3(-6 + i * 2.4, 0.8, -2 + (i % 2) * 2.0), Vector3(1.6, 1.6, 1.6), cols[i])


func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	if _shot != "" and _t > 1.0 and _t - delta <= 1.0:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
