extends Node3D
## D-03 preview: toon bands, rim, outline, water, element glow cores, roof fade. Run this scene (F6).
## Quarter-view camera at ~55° like the field. A/D or arrows move the "player" capsule under the roof.
## Optional:  godot --path . res://art/_preview/shader_preview.tscn -- --shot=user://shader.png

const M := "res://art/materials/"

var _player: MeshInstance3D
var _fader: RoofFader
var _frames := 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("8fc3d8")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b9cbd6")
	e.ambient_light_energy = 0.45
	e.glow_enabled = true
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16
	add_child(cam)
	cam.position = Vector3(14, 18, 14)
	cam.look_at(Vector3(2, 0, 1))

	_box(Vector3(0, -0.25, -3), Vector3(24, 0.5, 18), "toon_concrete")
	_box(Vector3(0, -0.45, 9), Vector3(24, 0.4, 6), "toon_water")
	_box(Vector3(-4, 1, -3), Vector3(2, 2, 2), "toon_wood")
	_sphere(Vector3(-1, 1, -3), 1.0, "toon_default")
	_sphere(Vector3(2, 1.2, -4), 1.2, "toon_foliage")
	var i := 0
	for el in ["green", "stone", "water", "light"]:
		_box(Vector3(-4.5 + i * 3.0, 0.4, 3.0), Vector3(1.2, 0.8, 1.2), "toon_wood")
		var core := _sphere(Vector3(-4.5 + i * 3.0, 1.4, 3.0), 0.45, "glow_" + el)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		i += 1
	# small interior: walls + roof with roof_fade
	var roof_mat := load(M + "roof_fade_concrete.tres") as ShaderMaterial
	_box(Vector3(5, 1.5, 0), Vector3(0.3, 3, 5), "", roof_mat)
	_box(Vector3(7.5, 1.5, -2.5), Vector3(5, 3, 0.3), "", roof_mat)
	_box(Vector3(7.5, 3.1, 0), Vector3(5.4, 0.3, 5.4), "", roof_mat)
	_player = _capsule(Vector3(7, 0.9, 0))
	_fader = RoofFader.new()
	_fader.target = _player
	_fader.materials = [roof_mat]
	add_child(_fader)


func _process(delta: float) -> void:
	var dir := Input.get_axis(&"ui_left", &"ui_right")
	_player.position.x = clampf(_player.position.x + dir * delta * 4.0, 0.0, 9.0)
	_frames += 1
	if _frames == 20:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shot="):
				get_viewport().get_texture().get_image().save_png(a.trim_prefix("--shot="))
				get_tree().quit()


func _box(pos: Vector3, size: Vector3, mat_name: String, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat if mat != null else load(M + mat_name + ".tres")
	mi.position = pos
	add_child(mi)
	return mi


func _sphere(pos: Vector3, r: float, mat_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = load(M + mat_name + ".tres")
	mi.position = pos
	add_child(mi)
	return mi


func _capsule(pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = CapsuleMesh.new()
	var m := (load(M + "toon_default.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter(&"albedo", Color("e9e3d5"))
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi
