extends Node3D
## D-09 preview: every appearance preset side by side (placeholder bodies until VRoid models land).
## Optional: -- --shot=user://chars.png

const CHAR := preload("res://art/characters/character.tscn")


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fc3d8")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c9d6e0")
	env.environment.ambient_light_energy = 0.5
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.2
	add_child(cam)
	cam.position = Vector3(0, 2.0, 6)
	cam.look_at(Vector3(0, 0.8, 0))
	var floor_mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(12, 0.1, 4)
	floor_mi.mesh = bm
	floor_mi.position.y = -0.05
	floor_mi.material_override = load("res://art/materials/toon_concrete.tres")
	add_child(floor_mi)
	var ids := CharacterLook.preset_ids()
	for i in ids.size():
		var c: CharacterLook = CHAR.instantiate()
		var p: AppearancePreset = CharacterLook.presets()[ids[i]]
		c.age_stage = p.age_stage if p.age_stage >= 0 else 3
		c.preset_id = ids[i]
		c.position = Vector3((i - (ids.size() - 1) * 0.5) * 0.95, 0, 0)
		add_child(c)
		var l := Label3D.new()
		l.text = p.display_name
		l.font_size = 26
		l.pixel_size = 0.004
		l.position = c.position + Vector3(0, -0.2, 0.6)
		l.modulate = Color("1f2329")
		l.outline_size = 0
		add_child(l)


var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t > 0.8 and _t - delta <= 0.8:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shot="):
				get_viewport().get_texture().get_image().save_png(a.trim_prefix("--shot="))
				get_tree().quit()
