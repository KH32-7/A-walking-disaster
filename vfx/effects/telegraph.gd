extends FxEffect
## &"boss_telegraph" (design 04: area attacks are marked on the ground 1 s before, shape + colour).
## The shape IS the warning: circle / cone / line / ring, outlined light with a dark rim, hatched inside,
## and a solid front sweeping from the origin to the edge — when it reaches the edge the attack lands.
## A "!" triangle sits at the origin. At the end a brief pop (a single dim blink with reduce_flash).
## params: shape (&"circle" | &"cone" | &"line" | &"ring"), radius, inner (ring), angle_deg (cone),
##   length / width (line), direction (Vector3, cone and line), duration (base_params 1.0 s),
##   kind (&"danger" red, &"warn" orange for non-damage areas like slows).

const SHADER := preload("res://vfx/shaders/telegraph.gdshader")
const SHAPES := {&"circle": 0, &"cone": 1, &"line": 2, &"ring": 3}
const END_SEC := 0.25

var _mat: ShaderMaterial
var _plane: MeshInstance3D
var _icon: Part
var _icon_mark: Label3D
var _dur := 1.0


func _build() -> void:
	_dur = p_float("duration", 1.0)
	lifetime = _dur + END_SEC
	var shape: int = SHAPES.get(StringName(params.get("shape", &"circle")), 0)
	var radius := p_float("radius", 3.0)
	var length := p_float("length", 8.0)
	var width := p_float("width", 1.6)
	var dir: Vector3 = params.get("direction", Vector3.FORWARD)
	dir.y = 0.0
	if dir.length_squared() > 0.0:
		basis = Basis.looking_at(-dir.normalized(), Vector3.UP)  # local +Z = attack direction
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.render_priority = -1
	_mat.set_shader_parameter(&"shape", shape)
	_mat.set_shader_parameter(&"radius", radius)
	_mat.set_shader_parameter(&"inner", p_float("inner", radius * 0.5))
	_mat.set_shader_parameter(&"half_angle", deg_to_rad(p_float("angle_deg", 70.0)) * 0.5)
	_mat.set_shader_parameter(&"line_length", length)
	_mat.set_shader_parameter(&"line_width", width)
	var kind: StringName = params.get("kind", &"danger")
	_mat.set_shader_parameter(&"color", UiTokens.WARN if kind == &"warn" else UiTokens.DANGER)
	var plane := PlaneMesh.new()
	var ext := (maxf(length, width) if shape == 2 else radius) + 0.3
	plane.size = Vector2(ext * 2.0, ext * 2.0)
	_plane = MeshInstance3D.new()
	_plane.mesh = plane
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plane.material_override = _mat
	_plane.position = Vector3.UP * 0.04
	add_child(_plane)
	var icon_at := Vector3.UP * 0.5 + (Vector3(0, 0, 0.8) if shape == 2 else Vector3.ZERO)
	if shape == 3:
		icon_at = Vector3(0, 0.5, (radius + p_float("inner", radius * 0.5)) * 0.5)
	_icon = sprite(UiTokens.Shape.TRIANGLE, UiTokens.WARN if kind == &"warn" else UiTokens.DANGER, 0.32, Blend.MIX, true, true)
	_icon.auto = false
	_icon.node.position = icon_at
	_icon_mark = Label3D.new()
	_icon_mark.text = "!"
	_icon_mark.font = UiThemeBuilder.font_num()
	_icon_mark.font_size = 34
	_icon_mark.outline_size = 0
	_icon_mark.modulate = UiTokens.TEXT
	_icon_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon_mark.fixed_size = false
	_icon_mark.pixel_size = 0.01
	_icon_mark.no_depth_test = true
	_icon_mark.render_priority = 3
	_icon_mark.position = icon_at + Vector3.DOWN * 0.04
	add_child(_icon_mark)
	_tick(0.0, 0.0)


func _tick(_k: float, _delta: float) -> void:
	var progress := clampf(age / _dur, 0.0, 1.0)
	_mat.set_shader_parameter(&"progress", progress)
	var end := clampf((age - _dur) / END_SEC, 0.0, 1.0)
	var pop := (1.0 - end) * (0.5 * flash_k) if age >= _dur else 0.0
	_mat.set_shader_parameter(&"flash", pop)
	_mat.set_shader_parameter(&"opacity", 1.0 - ease(end, 2.0))
	var pulse := 1.0 + 0.12 * sin(age * 18.0) * (1.0 - progress * 0.5)
	_icon.node.visible = age < _dur
	_icon_mark.visible = _icon.node.visible
	_icon.node.scale = Vector3.ONE * 0.32 * _icon.scale_k * pulse
	_icon.set_look(_icon.color, 0.0)
