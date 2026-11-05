extends FxEffect
## &"melee_swing": a swept band at waist height that grows from one side of the swing to the other in
## 0.1 s and fades. params: direction (Vector3), arc_deg, range (m), element, combo_step (odd = backhand).
## Lane B does not call it yet (request in vfx/README.md); it replaces the debug view's swing arc.

const HEIGHT := 0.9
const SWEEP := 0.1
const STEPS := 18

var _arc: MeshInstance3D
var _mesh := ImmediateMesh.new()
var _dir := Vector3.FORWARD
var _half := 0.9
var _reach := 1.6
var _flip := false
var _color := Color.WHITE


func _build() -> void:
	lifetime = 0.24
	var d: Vector3 = params.get("direction", Vector3.FORWARD)
	d.y = 0.0
	_dir = d.normalized() if d.length_squared() > 0.0 else Vector3.FORWARD
	_half = deg_to_rad(p_float("arc_deg", 100.0)) * 0.5
	_reach = p_float("range", 1.6)
	_flip = int(params.get("combo_step", 0)) % 2 == 1
	_color = element_color(Color(1, 0.97, 0.9))
	_arc = MeshInstance3D.new()
	_arc.mesh = _mesh
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arc.material_override = FxEffect.material(Blend.ADD, false)
	_arc.position = Vector3.UP * HEIGHT
	add_child(_arc)
	_tick(0.0, 0.0)


func _tick(_k: float, _delta: float) -> void:
	var sweep := clampf(age / SWEEP, 0.0, 1.0)
	var fade := 1.0 - clampf((age - SWEEP) / (lifetime - SWEEP), 0.0, 1.0)
	_mesh.clear_surfaces()
	_arc.visible = sweep > 0.02
	if not _arc.visible:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var from := _half if not _flip else -_half
	var to := lerpf(from, -from, sweep)
	for i in STEPS + 1:
		var t := float(i) / STEPS
		var a := lerpf(from, to, t)
		var v := _dir.rotated(Vector3.UP, a)
		var alpha := t * t * fade * 0.85  # trailing end clear, leading edge bright
		_mesh.surface_set_color(Color(1, 1, 1, alpha * 0.4))
		_mesh.surface_add_vertex(v * _reach * 0.4)
		_mesh.surface_set_color(Color(1, 1, 1, alpha))
		_mesh.surface_add_vertex(v * _reach)
	_mesh.surface_end()
	_arc.set_instance_shader_parameter(&"tint", _color)
	_arc.set_instance_shader_parameter(&"energy", 1.2)
	_arc.set_instance_shader_parameter(&"spin", 0.0)
	_arc.set_instance_shader_parameter(&"squash", Vector2.ONE)
