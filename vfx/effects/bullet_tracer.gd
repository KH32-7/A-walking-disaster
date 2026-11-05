extends FxEffect
## &"bullet_tracer": a bright streak flying from the muzzle to `to` (speed from base_params, 120 m/s
## like the old debug view), then a faint line that lingers briefly. params: to (Vector3), speed.

const STREAK_COLOR := Color(1.0, 0.88, 0.5)
const LINE_COLOR := Color(1.0, 0.9, 0.6, 0.3)
const STREAK_LEN := 1.4
const LINGER := 0.07

var _streak: Part
var _line: Part
var _to := Vector3.ZERO
var _travel := 0.0


func _build() -> void:
	_to = to_local(params.get("to", global_position + Vector3.FORWARD))
	var speed := p_float("speed", 120.0)
	_travel = _to.length() / maxf(speed, 1.0)
	lifetime = _travel + LINGER
	_line = ribbon(PackedVector3Array([Vector3.ZERO, _to]), 0.04, LINE_COLOR)
	_line.auto = false
	_line.node.visible = false
	_streak = ribbon(PackedVector3Array([Vector3.ZERO, Vector3.FORWARD * 0.001]), 0.09, STREAK_COLOR)
	_streak.auto = false
	_streak.energy = 1.2
	_tick(0.0, 0.0)


func _tick(_k: float, _delta: float) -> void:
	var length := _to.length()
	var dir := _to / length if length > 0.0 else Vector3.FORWARD
	if age <= _travel and length > 0.0:
		var head := minf(age / maxf(_travel, 0.0001), 1.0) * length
		head = maxf(head, minf(STREAK_LEN * 0.5, length))
		var tail := maxf(head - STREAK_LEN, 0.0)
		_streak.node.visible = true
		# The streak is a unit ribbon along the shot, moved and stretched (camera-facing width kept).
		_streak.node.mesh = ribbon_mesh(PackedVector3Array([dir * tail, dir * head]), 0.09)
		_streak.set_look(STREAK_COLOR, 0.0)
	else:
		_streak.node.visible = false
		_line.node.visible = true
		var a := clampf(1.0 - (age - _travel) / LINGER, 0.0, 1.0)
		_line.set_look(Color(LINE_COLOR, LINE_COLOR.a * a), 0.0)
