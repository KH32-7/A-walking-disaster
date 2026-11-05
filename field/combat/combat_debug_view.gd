class_name CombatDebugView
extends Node3D
## TEMPORARY combat visuals until Lane D's real ones (Fx.spawn VFX D-18, aim display).
## Child of the player. Debug builds only: frees itself in release builds.
## Gun: aim point marker + faint aim line, spread fan while aiming, travelling bullet streaks,
## impact crosses, muzzle flash. Melee: swing arc on the ground, brighter for a moment on a swing.
## Everything is drawn with one ImmediateMesh in world space, rebuilt every frame.

const GROUND_Y := 0.05
const ARC_SEGMENTS := 16
const AIM_MARKER_RADIUS := 0.35
## Fallback aim distance before the camera has given an aim point.
const DEFAULT_AIM_DIST := 4.0
const BULLET_SPEED := 120.0
const STREAK_LENGTH := 1.6
const TRACE_LINGER_SEC := 0.06
const IMPACT_SEC := 0.15
const IMPACT_SIZE := 0.2
const MUZZLE_SEC := 0.05
const MUZZLE_SIZE := 0.3
const SWING_FLASH_SEC := 0.12

const AIM_COLOR := Color(1.0, 1.0, 1.0, 0.45)
const AIM_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.18)
const FAN_COLOR := Color(1.0, 1.0, 1.0, 0.10)
const FAN_EDGE_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const MELEE_COLOR := Color(1.0, 1.0, 1.0, 0.08)
const MELEE_FLASH_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const BULLET_COLOR := Color(1.0, 0.85, 0.4, 1.0)
const IMPACT_COLOR := Color(1.0, 0.6, 0.25, 1.0)

var _player: Player
var _holder: WeaponHolder
var _mesh := ImmediateMesh.new()
## [{"from", "to", "age", "hit"}]
var _shots: Array[Dictionary] = []
var _muzzle_left := 0.0
var _muzzle_at := Vector3.ZERO
var _swing_left := 0.0

var _tris := PackedVector3Array()
var _tri_colors := PackedColorArray()
var _lines := PackedVector3Array()
var _line_colors := PackedColorArray()


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_player = get_parent() as Player
	_holder = _player.get_node_or_null(^"Weapons") as WeaponHolder if _player else null
	if _holder == null:
		queue_free()
		return
	top_level = true
	global_transform = Transform3D.IDENTITY
	var inst := MeshInstance3D.new()
	inst.mesh = _mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	inst.material_override = mat
	add_child(inst)
	_holder.shot_traced.connect(_on_shot_traced)
	_holder.attacked.connect(_on_attacked)


func _process(delta: float) -> void:
	_tris.clear()
	_tri_colors.clear()
	_lines.clear()
	_line_colors.clear()
	if not _player.is_downed:
		var stats := _holder.current_stats()
		if WeaponHolder.is_gun(stats):
			_draw_gun(stats)
		elif not stats.is_empty():
			_draw_melee(stats, delta)
	_draw_shots(delta)
	_draw_muzzle(delta)
	_flush()


func _on_shot_traced(from: Vector3, to: Vector3, hit: bool) -> void:
	_shots.append({"from": from, "to": to, "age": 0.0, "hit": hit})


func _on_attacked(kind: StringName, _combo_step: int) -> void:
	if kind == &"shot":
		_muzzle_left = MUZZLE_SEC
		_muzzle_at = _player.global_position + Vector3.UP * _holder.tuning.muzzle_height \
				+ _player.facing() * 0.5
	else:
		_swing_left = SWING_FLASH_SEC


func _draw_gun(stats: Dictionary) -> void:
	var origin := _ground(_player.global_position)
	var aim: Variant = _player.aim_point()
	var target: Vector3 = _ground(aim) if aim != null else origin + _player.facing() * DEFAULT_AIM_DIST
	# The line shows where a shot would really go (facing); the ring shows the cursor.
	# They only line up while aiming (RMB), when the player turns to the cursor.
	var dist := maxf(origin.distance_to(target), DEFAULT_AIM_DIST)
	_line(origin, origin + _player.facing() * dist, AIM_LINE_COLOR)
	_ring(target, AIM_MARKER_RADIUS, AIM_COLOR)
	if _player.is_aiming:
		_fan(origin, _player.facing(), _holder.current_spread_deg(), float(stats.get("range", 10.0)),
				FAN_COLOR, FAN_EDGE_COLOR)


func _draw_melee(stats: Dictionary, delta: float) -> void:
	_swing_left = maxf(_swing_left - delta, 0.0)
	var color := MELEE_FLASH_COLOR if _swing_left > 0.0 else MELEE_COLOR
	_fan(_ground(_player.global_position), _player.facing(), _holder.tuning.melee_arc_deg,
			float(stats.get("range", 1.5)), color, Color(color, color.a * 2.0))


func _draw_shots(delta: float) -> void:
	for i in range(_shots.size() - 1, -1, -1):
		var shot := _shots[i]
		shot["age"] += delta
		var from: Vector3 = shot["from"]
		var to: Vector3 = shot["to"]
		var length := from.distance_to(to)
		var travel_sec := length / BULLET_SPEED
		if shot["age"] > travel_sec + maxf(TRACE_LINGER_SEC, IMPACT_SEC):
			_shots.remove_at(i)
			continue
		var dir := (to - from).normalized() if length > 0.0 else Vector3.FORWARD
		if shot["age"] <= travel_sec:
			var head := minf(shot["age"] * BULLET_SPEED, length)
			_line(from + dir * maxf(head - STREAK_LENGTH, 0.0), from + dir * head, BULLET_COLOR)
		elif shot["age"] <= travel_sec + TRACE_LINGER_SEC:
			_line(from, to, Color(BULLET_COLOR, 0.25))
		if shot["hit"] and shot["age"] > travel_sec and shot["age"] <= travel_sec + IMPACT_SEC:
			_cross(to, IMPACT_SIZE, IMPACT_COLOR)


func _draw_muzzle(delta: float) -> void:
	if _muzzle_left <= 0.0:
		return
	_muzzle_left -= delta
	_cross(_muzzle_at, MUZZLE_SIZE, BULLET_COLOR)


# --- Primitive helpers ---------------------------------------------------------

func _ground(point: Vector3) -> Vector3:
	return Vector3(point.x, _player.global_position.y + GROUND_Y, point.z)


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_lines.append_array([a, b])
	_line_colors.append_array([color, color])


func _ring(center: Vector3, radius: float, color: Color) -> void:
	for i in ARC_SEGMENTS:
		var a0 := TAU * i / ARC_SEGMENTS
		var a1 := TAU * (i + 1) / ARC_SEGMENTS
		_line(center + Vector3(cos(a0), 0.0, sin(a0)) * radius,
				center + Vector3(cos(a1), 0.0, sin(a1)) * radius, color)


func _cross(center: Vector3, size: float, color: Color) -> void:
	var h := size * 0.5
	_line(center - Vector3(h, 0.0, 0.0), center + Vector3(h, 0.0, 0.0), color)
	_line(center - Vector3(0.0, 0.0, h), center + Vector3(0.0, 0.0, h), color)
	_line(center - Vector3(0.0, h, 0.0), center + Vector3(0.0, h, 0.0), color)


## Filled fan on the ground: full angle `angle_deg` around `forward`, out to `radius`.
func _fan(origin: Vector3, forward: Vector3, angle_deg: float, radius: float,
		fill: Color, edge: Color) -> void:
	var half := deg_to_rad(maxf(angle_deg, 0.5)) * 0.5
	var flat := Vector3(forward.x, 0.0, forward.z).normalized()
	var prev := origin + flat.rotated(Vector3.UP, half) * radius
	_line(origin, prev, edge)
	for i in range(1, ARC_SEGMENTS + 1):
		var t := lerpf(half, -half, float(i) / ARC_SEGMENTS)
		var p := origin + flat.rotated(Vector3.UP, t) * radius
		_tris.append_array([origin, prev, p])
		_tri_colors.append_array([fill, fill, fill])
		_line(prev, p, edge)
		prev = p
	_line(origin, prev, edge)


func _flush() -> void:
	_mesh.clear_surfaces()
	if not _tris.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in _tris.size():
			_mesh.surface_set_color(_tri_colors[i])
			_mesh.surface_add_vertex(_tris[i])
		_mesh.surface_end()
	if not _lines.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in _lines.size():
			_mesh.surface_set_color(_line_colors[i])
			_mesh.surface_add_vertex(_lines[i])
		_mesh.surface_end()
