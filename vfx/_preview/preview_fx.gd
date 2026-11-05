extends Node3D
## D-18 preview: every Fx id on a grid, replayed every REPLAY_SEC. Owner: Lane D.
## Keys: 1~5 element (없음, 풀, 돌, 물, 번개), C crit, F reduce flash, R replay now.
## WASD / arrows move the camera, mouse wheel zooms. Needs the assets submodule to show anything.

const REPLAY_SEC := 2.5
const SPACING := 8.0
const COLUMNS := 6

var _element := Enums.Element.NONE
var _crit := false
var _t := 0.0
var _camera: Camera3D
var _rig: Node3D
var _help: Label
var _spots: Array[Dictionary] = []  # {id, pos, params}


func _ready() -> void:
	_build_world()
	var ids: Array[StringName] = [&"hit_spark", &"muzzle_flash", &"bullet_tracer", &"bullet_impact",
		&"consumable_grenade", &"neon_moth_blast", &"consumable_flashbang", &"consumable_noise_lure",
		&"essence_release", &"essence_chain", &"perfect_block", &"damage_number",
		&"essence_combo:thorn_bush", &"essence_combo:swamp", &"essence_combo:mud",
		&"essence_combo:photosynthesis", &"essence_combo:shard_burst", &"essence_combo:shock_puddle",
		&"slam", &"dash_slash", &"brace", &"precision_shot", &"suppressive_fire", &"shadow_step",
		&"boss_telegraph:circle", &"boss_telegraph:ring", &"boss_telegraph:cone", &"boss_telegraph:line",
		&"monster_claw", &"monster_bite", &"monster_slam", &"monster_splash", &"monster_scream", &"monster_cast",
		&"monster_death", &"boss_slam", &"boss_root_burst", &"boss_summon_pods",
		&"boss_dive", &"boss_splash", &"boss_tail_swing", &"boss_scalpels", &"boss_flash", &"boss_clones",
		&"boss_decoy_pop", &"boss_laser", &"boss_shock_floor", &"boss_cable_cut", &"boss_overload", &"boss_summon_moths",
		&"boss_wave_slam", &"boss_rock_throw", &"boss_guard", &"boss_guard_break"]
	for i in ids.size():
		var pos := Vector3((i % COLUMNS) * SPACING, 0.0, (i / COLUMNS) * SPACING)
		_spots.append({"id": ids[i], "pos": pos})
		var label := Label3D.new()
		label.text = String(ids[i]).replace(":", " ")
		label.font_size = 40
		label.pixel_size = 0.01
		label.rotation_degrees.x = -90.0
		label.modulate = UiTokens.TEXT_DIM
		add_child(label)
		label.position = pos + Vector3(0.0, 0.02, 2.6)
	_rig.position = Vector3((COLUMNS - 1) * SPACING * 0.5, 0.0, (ids.size() / COLUMNS - 1) * SPACING * 0.5)
	_replay()


func _process(delta: float) -> void:
	_t += delta
	if _t >= REPLAY_SEC:
		_replay()
	var move := Vector3(Input.get_axis(&"ui_left", &"ui_right"), 0.0, Input.get_axis(&"ui_up", &"ui_down"))
	if Input.is_physical_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): move.x += 1.0
	if Input.is_physical_key_pressed(KEY_W): move.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S): move.z += 1.0
	_rig.position += move.limit_length(1.0) * delta * 20.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.position.z = maxf(_camera.position.z * 0.9, 4.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.position.z = minf(_camera.position.z * 1.1, 80.0)
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	if key >= KEY_1 and key <= KEY_5:
		_element = key - KEY_1 as Enums.Element
	elif key == KEY_C:
		_crit = not _crit
	elif key == KEY_F:
		Fx.reduced_flash_override = 0 if Fx.reduced_flash() else 1
	elif key != KEY_R:
		return
	_replay()


func _replay() -> void:
	_t = 0.0
	Fx.clear()
	_update_help()
	for spot in _spots:
		var parts := String(spot["id"]).split(":")
		var id := StringName(parts[0])
		var pos: Vector3 = spot["pos"]
		# Essence and monster effects always carry an element in play; show green when none is picked.
		var needs_element := id == &"essence_release" or String(id).begins_with("monster_") or String(id).begins_with("boss_")
		var element := _element if _element != Enums.Element.NONE or not needs_element else Enums.Element.GREEN
		var p := {"element": element, "crit": _crit, "weak_point": _crit, "direction": Vector3.RIGHT,
			"radius": 3.0, "combat_class": Enums.CombatClass.BLADE}
		match id:
			&"bullet_tracer", &"essence_chain":
				pos += Vector3(-3.0, 1.0, 0.0)
				p["to"] = pos + Vector3(6.0, 0.0, 0.0)
			&"muzzle_flash", &"hit_spark", &"perfect_block":
				pos += Vector3.UP
			&"bullet_impact":
				pos += Vector3.UP
				p["normal"] = Vector3(0.0, 0.5, 1.0).normalized()
			&"neon_moth_blast":
				p.erase("radius")
			&"consumable_flashbang":
				p["radius"] = 8.0
			&"brace":
				p["radius"] = 6.0
			&"essence_combo":
				p["id"] = StringName(parts[1])
				p["radius"] = 2.0
				p["duration"] = REPLAY_SEC - 0.2
			&"boss_telegraph":
				p = {"shape": StringName(parts[1]), "radius": 3.0, "inner": 1.5, "angle_deg": 70.0,
					"length": 6.0, "width": 2.0, "direction": Vector3.BACK, "duration": REPLAY_SEC - 0.4,
					"kind": &"warn" if _crit else &"danger"}
				if parts[1] == "line":
					pos += Vector3(0.0, 0.0, -3.0)
			&"monster_claw", &"monster_bite", &"monster_slam", &"monster_splash", &"monster_scream", &"monster_cast", &"monster_death", &"boss_summon_pods":
				p.erase("radius")  # D-17: authored at their default size
			&"boss_splash":
				p["radius"] = 7.0
			&"boss_flash":
				p["radius"] = 9.0
			&"boss_shock_floor":
				p["radius"] = 2.5
				p["duration"] = REPLAY_SEC - 0.4
			&"boss_rock_throw":
				p["radius"] = 3.0
			&"boss_guard":
				p["duration"] = REPLAY_SEC - 0.4
			&"boss_laser", &"boss_wave_slam":
				pos += Vector3(-3.5, 0.0, 0.0)
				p["to"] = pos + Vector3(7.0, 0.0, 0.0)
			&"boss_scalpels":
				pos += Vector3(-3.5, 1.6, 0.0)
				p["to"] = pos + Vector3(7.0, 0.0, 0.0)
			&"boss_root_burst", &"boss_dive":
				pos += Vector3(-3.5, 0.0, 0.0)
				p["to"] = pos + Vector3(7.0, 0.0, 0.0)
			&"damage_number":
				Fx.feedback.show_number(pos + Vector3.UP * 1.6, "128!" if _crit else "37",
					UiTokens.ACCENT if _crit else UiTokens.TEXT, 1.5 if _crit else 1.0)
				continue
		Fx.spawn(id, pos, p)


func _update_help() -> void:
	_help.text = "속성 %s (1~5) / 치명타 %s (C) / 번쩍임 줄이기 %s (F) / R 다시 / WASD 이동, 휠 확대" % [
		UiTokens.ELEMENT_NAMES[_element], "켬" if _crit else "끔", "켬" if Fx.reduced_flash() else "끔"]


func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.09, 0.1, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.52, 0.56)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.light_energy = 0.8
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.29, 0.3)
	floor_mesh.material_override = mat
	add_child(floor_mesh)
	_rig = Node3D.new()
	_rig.rotation_degrees = Vector3(-50.0, 45.0, 0.0)  # game camera: 45 deg top-down
	add_child(_rig)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 0.0, 30.0)
	_camera.fov = 40.0
	_rig.add_child(_camera)
	_camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	_help = Label.new()
	_help.position = Vector2(16, 12)
	_help.add_theme_font_size_override(&"font_size", UiTokens.SIZE_BODY)
	layer.add_child(_help)
