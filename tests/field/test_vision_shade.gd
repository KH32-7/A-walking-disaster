extends Node
## B: vision light on the FieldCamera. Shown in the field, hidden when the player has
## field_rules off (base), follows the player's position and facing.

const CAMERA_SCENE := preload("res://field/camera/field_camera.tscn")
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const DT := 1.0 / 60.0
const EPS := 0.02

var _ok := true


func run() -> bool:
	_ok = true
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.set_physics_process(false)
	var camera: FieldCamera = CAMERA_SCENE.instantiate()
	camera.target = player
	add_child(camera)
	var shade := _shade(camera)
	_expect(shade != null, "camera has a VisionShade")
	if shade != null:
		_test_follow(shade, player)
		_test_turn_is_smooth(shade, player)
		_test_hidden_in_base(shade, player)
	camera.free()
	player.free()
	return _ok


func _test_follow(shade: VisionShade, player: Player) -> void:
	player.global_position = Vector3(3.0, 0.0, -2.0)
	player._facing = Vector3.RIGHT
	shade._process(DT)
	_expect(shade.visible, "visible in the field")
	var pos: Vector2 = _param(shade, &"player_xz")
	_expect_near(pos.distance_to(Vector2(3.0, -2.0)), 0.0, "player position reaches the shader")
	var f: Vector2 = _param(shade, &"facing_xz")
	_expect_near(f.distance_to(Vector2(1.0, 0.0)), 0.0, "first frame snaps to the facing")


func _test_turn_is_smooth(shade: VisionShade, player: Player) -> void:
	player._facing = Vector3.BACK
	shade._process(DT)
	var f: Vector2 = _param(shade, &"facing_xz")
	_expect(f.distance_to(Vector2(0.0, 1.0)) > 0.1, "one frame later the light is still turning")
	for i in 120:
		shade._process(DT)
	f = _param(shade, &"facing_xz")
	_expect_near(f.distance_to(Vector2(0.0, 1.0)), 0.0, "light catches up with the facing")


func _test_hidden_in_base(shade: VisionShade, player: Player) -> void:
	player.field_rules = false
	shade._process(DT)
	_expect(not shade.visible, "hidden when field_rules is off")
	player.field_rules = true


func _shade(camera: FieldCamera) -> VisionShade:
	for c in camera.get_children():
		if c is VisionShade:
			return c
	return null


func _param(shade: VisionShade, key: StringName) -> Variant:
	return (shade.material_override as ShaderMaterial).get_shader_parameter(key)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_ok = false
		push_error("test_vision_shade: %s" % label)


func _expect_near(actual: float, expected: float, label: String, eps := EPS) -> void:
	if absf(actual - expected) > eps:
		_ok = false
		push_error("test_vision_shade: %s (got %.3f, want %.3f)" % [label, actual, expected])
