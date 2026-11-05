class_name FieldCamera
extends Camera3D
## Quarter-view field camera (B-04). Follows the player, starts on a fixed 45 deg diagonal,
## turns in 90 deg steps with a short tween, and has 3 zoom distances.
## Aiming: mouse cursor -> ground raycast, gamepad -> right stick direction (screen relative,
## with aim assist from Settings `aim_assist`). The point goes to Player.set_aim_point().
## Input uses only action names. Rotation, zoom and aim-stick actions are requested from Lane A
## (core/input_setup.gd); a missing action is ignored. Sandboxes register them temporarily.
## Design reference: docs/design/16-art-sound.md "아트 방향", 14-ui-controls-accessibility.md

signal rotated(yaw_index: int)
signal zoom_changed(level: int)

## Camera numbers, all placeholders, all here.
const PITCH_DEG := 55.0 ## look-down angle (design 16)
const START_YAW_DEG := 45.0 ## diagonal quarter view
const YAW_STEP_DEG := 90.0
const ROTATE_SEC := 0.25 ## instant when Settings `reduce_shake` is on
## near, middle, far (design 16: 3 steps). User feedback 2026-11-06 (B-26): start closer, 14/18/24 -> 10/13.5/18.
const ZOOM_DISTANCES := [10.0, 13.5, 18.0]
const START_ZOOM := 1
const FOV_DEG := 60.0
const FOCUS_HEIGHT := 1.0 ## look at the player's chest, not the feet
const FOLLOW_SHARPNESS := 10.0 ## exponential follow, higher is tighter
const ZOOM_SHARPNESS := 8.0
## Aiming (right click) pulls the camera in a little for focus: distance x this while aiming.
const AIM_ZOOM_MULT := 0.82
const AIM_ZOOM_SHARPNESS := 6.0
## Tilt-shift depth of field, as ratios of the current zoom distance.
const DOF_FAR_START := 1.2 ## far blur starts at distance x 1.2
const DOF_FAR_TRANSITION := 0.5 ## full far blur at distance x 1.7 (top screen edge)
const DOF_NEAR_END := 0.8 ## near blur ends at distance x 0.8
const DOF_NEAR_TRANSITION := 0.25
const DOF_AMOUNT := 0.08 ## Godot default 0.1, keep it soft
## Aiming numbers.
const STICK_DEADZONE := 0.25
const STICK_AIM_DISTANCE := 8.0 ## stick aim point this far in front of the player
const AIM_RAY_LENGTH := 200.0
const ASSIST_RANGE := 16.0
const ASSIST_CONE_DEG := [0.0, 6.0, 12.0, 20.0] ## index = Settings `aim_assist` (0 off, 1..3)

const ACTION_ROTATE_LEFT := &"camera_rotate_left"
const ACTION_ROTATE_RIGHT := &"camera_rotate_right"
const ACTION_ZOOM_IN := &"camera_zoom_in"
const ACTION_ZOOM_OUT := &"camera_zoom_out"
const ACTION_AIM_LEFT := &"aim_left"
const ACTION_AIM_RIGHT := &"aim_right"
const ACTION_AIM_UP := &"aim_up"
const ACTION_AIM_DOWN := &"aim_down"

## Followed node. Empty means the first node in group `player`.
@export var target: Node3D

var _yaw_deg := START_YAW_DEG
var _yaw_target_deg := START_YAW_DEG
var _zoom := START_ZOOM
var _distance: float = ZOOM_DISTANCES[START_ZOOM]
## 0 = not aiming, 1 = fully aim-zoomed (eased).
var _aim_zoom := 0.0
var _focus := Vector3.ZERO
var _use_stick := false
var _tween: Tween
## B-27: shot kick (decays to zero) and shake trauma (CombatFeel).
var _kick := Vector3.ZERO
var _trauma := 0.0
var _shake_time := 0.0


func _ready() -> void:
	fov = FOV_DEG
	var dof := CameraAttributesPractical.new()
	dof.dof_blur_far_enabled = true
	dof.dof_blur_near_enabled = true
	dof.dof_blur_amount = DOF_AMOUNT
	attributes = dof
	make_current()
	if target != null:
		snap()


func _physics_process(delta: float) -> void:
	if target == null:
		target = get_tree().get_first_node_in_group(Player.GROUP) as Node3D
		if target == null:
			return
		snap()
	_focus = _focus.lerp(_target_focus(), 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	_aim_zoom = lerpf(_aim_zoom, 1.0 if _gun_aiming() else 0.0, 1.0 - exp(-AIM_ZOOM_SHARPNESS * delta))
	var want: float = ZOOM_DISTANCES[_zoom] * lerpf(1.0, AIM_ZOOM_MULT, _aim_zoom)
	_distance = lerpf(_distance, want, 1.0 - exp(-ZOOM_SHARPNESS * delta))
	_kick = _kick.lerp(Vector3.ZERO, 1.0 - exp(-CombatFeel.KICK_RETURN_SHARPNESS * delta))
	_trauma = maxf(_trauma - CombatFeel.SHAKE_DECAY * delta, 0.0)
	_shake_time += delta
	_place()
	_update_aim()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_use_stick = false


func _unhandled_input(event: InputEvent) -> void:
	if _pressed(event, ACTION_ROTATE_LEFT):
		rotate_step(-1)
	elif _pressed(event, ACTION_ROTATE_RIGHT):
		rotate_step(1)
	elif _pressed(event, ACTION_ZOOM_IN):
		zoom_step(-1)
	elif _pressed(event, ACTION_ZOOM_OUT):
		zoom_step(1)


## Turns the view by 90 deg per step. Negative = camera orbits left.
func rotate_step(steps: int) -> void:
	_yaw_target_deg += steps * YAW_STEP_DEG
	if _tween != null:
		_tween.kill()
	if Settings.get_value(&"reduce_shake"):
		_yaw_deg = _yaw_target_deg
	else:
		_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_property(self, "_yaw_deg", _yaw_target_deg, ROTATE_SEC)
	rotated.emit(yaw_index())


## Negative = closer. Clamped to the 3 distances.
func zoom_step(steps: int) -> void:
	var level := clampi(_zoom + steps, 0, ZOOM_DISTANCES.size() - 1)
	if level == _zoom:
		return
	_zoom = level
	zoom_changed.emit(_zoom)


## 0..3, which of the 4 diagonal views the camera is turning to (0 = start view).
func yaw_index() -> int:
	return posmod(roundi((_yaw_target_deg - START_YAW_DEG) / YAW_STEP_DEG), 4)


func zoom_level() -> int:
	return _zoom


## Jumps to the target view now (no follow lag, no zoom ease, no rotation tween).
func snap() -> void:
	if _tween != null:
		_tween.kill()
	_yaw_deg = _yaw_target_deg
	_distance = ZOOM_DISTANCES[_zoom]
	_focus = _target_focus()
	_place()


## Screen-relative 2D input (stick, WASD) to a flat world direction. Same rule as Player._to_world.
func screen_to_ground(input: Vector2) -> Vector3:
	var right := global_basis.x
	var forward := -global_basis.z
	right.y = 0.0
	forward.y = 0.0
	return (right.normalized() * input.x + forward.normalized() * -input.y).normalized()


## World point under a screen position: first world-layer hit, else the plane at the target's feet.
## Returns null when the ray misses both (pointing at the sky).
func aim_point_from_screen(screen_pos: Vector2) -> Variant:
	var origin := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + dir * AIM_RAY_LENGTH, 1 << (Enums.LAYER_WORLD - 1))
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position
	var ground_y := target.global_position.y if target != null else 0.0
	return Plane(Vector3.UP, ground_y).intersects_ray(origin, dir)


## Stick aim point. Inside the deadzone the player keeps facing where it faces now.
func aim_point_from_stick(stick: Vector2, origin: Vector3, facing: Vector3) -> Vector3:
	var dir := facing
	if stick.length() > STICK_DEADZONE:
		dir = assist_direction(origin, screen_to_ground(stick), _assist_targets(),
			Settings.get_value(&"aim_assist"))
	return origin + dir * STICK_AIM_DISTANCE


## Aim assist: bends a flat aim direction to the closest-angle target inside the level's cone.
static func assist_direction(origin: Vector3, dir: Vector3, targets: Array[Vector3], level: int) -> Vector3:
	var best := dir
	var best_angle := deg_to_rad(ASSIST_CONE_DEG[clampi(level, 0, ASSIST_CONE_DEG.size() - 1)])
	for pos in targets:
		var to := pos - origin
		to.y = 0.0
		if to.length_squared() < 0.0001 or to.length() > ASSIST_RANGE:
			continue
		var angle := dir.angle_to(to)
		if angle <= best_angle:
			best_angle = angle
			best = to.normalized()
	return best


## Right click with a gun (aim). With a melee weapon right click is block: no aim zoom.
func _gun_aiming() -> bool:
	var player := target as Player
	if player == null or not player.is_aiming:
		return false
	var weapons := player.get_node_or_null(^"Weapons") as WeaponHolder
	return weapons != null and WeaponHolder.is_gun(weapons.current_stats())


func _target_focus() -> Vector3:
	return target.global_position + Vector3.UP * FOCUS_HEIGHT


func _place() -> void:
	if not is_inside_tree():
		return
	var pitch := deg_to_rad(PITCH_DEG)
	var yaw := deg_to_rad(_yaw_deg)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * _distance
	# Kick and shake move eye and focus together, so the view slides instead of swinging.
	var jolt := _kick
	var shake := _trauma * _trauma
	if shake > 0.0:
		var t := _shake_time * CombatFeel.SHAKE_FREQ
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		jolt += right * sin(t * 1.0 + 0.3) * CombatFeel.SHAKE_MAX_OFFSET * shake
		jolt += Vector3.UP * sin(t * 1.37 + 1.7) * CombatFeel.SHAKE_MAX_OFFSET * shake
	look_at_from_position(_focus + offset + jolt, _focus + jolt, Vector3.UP)
	if shake > 0.0:
		rotate_object_local(Vector3.FORWARD,
				deg_to_rad(CombatFeel.SHAKE_MAX_ROLL_DEG) * shake * sin(_shake_time * CombatFeel.SHAKE_FREQ * 0.83))
	var dof := attributes as CameraAttributesPractical
	if dof != null:
		dof.dof_blur_far_distance = _distance * DOF_FAR_START
		dof.dof_blur_far_transition = _distance * DOF_FAR_TRANSITION
		dof.dof_blur_near_distance = _distance * DOF_NEAR_END
		dof.dof_blur_near_transition = _distance * DOF_NEAR_TRANSITION


## B-27: pushes the view by `v` (m); it springs back on its own.
func add_kick(v: Vector3) -> void:
	_kick += v


## B-27: adds shake trauma (0..1 total).
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _update_aim() -> void:
	var player := target as Player
	if player == null:
		return
	var stick := _read_stick()
	if stick.length() > STICK_DEADZONE:
		_use_stick = true
	var point: Variant
	if _use_stick:
		point = aim_point_from_stick(stick, player.global_position, player.facing())
	else:
		point = aim_point_from_screen(get_viewport().get_mouse_position())
	if point != null:
		player.set_aim_point(point)


func _read_stick() -> Vector2:
	for action in [ACTION_AIM_LEFT, ACTION_AIM_RIGHT, ACTION_AIM_UP, ACTION_AIM_DOWN]:
		if not InputMap.has_action(action):
			return Vector2.ZERO
	return Input.get_vector(ACTION_AIM_LEFT, ACTION_AIM_RIGHT, ACTION_AIM_UP, ACTION_AIM_DOWN)


func _assist_targets() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group(Monster.GROUP):
		var monster := node as Monster
		if monster != null and not monster.is_dead():
			found.append(monster.global_position)
	return found


func _pressed(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)
