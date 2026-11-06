extends Node3D
## D-05 preview: quarter-view field with fake monsters, noise (edge arrows only, no rings), plus the HUD.
## Keys: 1 walk noise (4 m), 2 sprint (8 m), 3 gunshot (22 m), 4 noise behind the camera, S/A/W monster states.
## Optional: -- --shot=user://markers.png

class FakeMonster:
	extends MeshInstance3D
	signal state_changed(old_state: int, new_state: int)
	var state: int = Enums.AIState.WANDER

	func _init(pos: Vector3, s: int) -> void:
		position = pos
		state = s
		var cm := CapsuleMesh.new()
		cm.radius = 0.5
		cm.height = 1.6
		mesh = cm
		material_override = load("res://art/materials/toon_foliage.tres")
		add_to_group(&"field_monsters")

	func set_state(s: int) -> void:
		var old := state
		state = s
		state_changed.emit(old, s)

const Fake := preload("res://ui/_preview/fake_field_state.gd")

var _mons: Array[FakeMonster] = []
var _t := 0.0


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("2f6f74")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b9cbd6")
	env.environment.ambient_light_energy = 0.5
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 30
	add_child(cam)
	cam.position = Vector3(18, 22, 18)
	cam.look_at(Vector3.ZERO)
	var floor_mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 0.2, 40)
	floor_mi.mesh = bm
	floor_mi.position.y = -0.1
	floor_mi.material_override = load("res://art/materials/toon_concrete.tres")
	add_child(floor_mi)
	var player := MeshInstance3D.new()
	player.mesh = CapsuleMesh.new()
	player.material_override = load("res://art/materials/toon_default.tres")
	player.position = Vector3(0, 1, 0)
	add_child(player)
	for spec in [[Vector3(-6, 0.8, -3), Enums.AIState.SUSPICIOUS], [Vector3(5, 0.8, -6), Enums.AIState.CHASE],
			[Vector3(3, 0.8, 5), Enums.AIState.WANDER], [Vector3(-30, 0.8, 20), Enums.AIState.CHASE]]:
		var m := FakeMonster.new(spec[0], spec[1])
		add_child(m)
		_mons.append(m)
	UI.show_field_hud(true)
	UI.field_hud.auto_bind = false


func _process(delta: float) -> void:
	_t += delta
	UI.field_hud.set_state(Fake.make(2.0))
	if fmod(_t, 0.5) < delta:
		UI.world_markers.add_noise(Vector3(0, 0, 0), 4.0)
	if fmod(_t + 0.2, 0.9) < delta:
		UI.world_markers.add_noise(Vector3(5, 0, -6), 8.0)
	if _t > 0.55 and _t - delta <= 0.55:
		UI.world_markers.add_noise(Vector3(1, 0, 1), 22.0)
		UI.world_markers.add_noise(Vector3(-25, 0, -30), 14.0)
	if _t > 0.95 and _t - delta <= 0.95:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shot="):
				get_viewport().get_texture().get_image().save_png(a.trim_prefix("--shot="))
				get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match (event as InputEventKey).keycode:
		KEY_1: UI.world_markers.add_noise(Vector3.ZERO, 4.0)
		KEY_2: UI.world_markers.add_noise(Vector3.ZERO, 8.0)
		KEY_3: UI.world_markers.add_noise(Vector3.ZERO, 22.0)
		KEY_4: UI.world_markers.add_noise(Vector3(-25, 0, -30), 14.0)
		KEY_S: _mons[2].set_state(Enums.AIState.SUSPICIOUS)
		KEY_A: _mons[2].set_state(Enums.AIState.CHASE)
		KEY_W: _mons[2].set_state(Enums.AIState.WANDER)
