class_name RainFx
extends Node3D
## Rainy days (사용자 요청 2026-11-06: 비 오는 날, 아름답게). Owner: Lane D. Lives under the Fx autoload
## and follows whichever Camera3D is current, so field and base scenes need no changes.
##   - Streaks: thin drops falling a little slanted, drawn along their velocity.
##   - They stop on whatever they hit (roofs, walls, ground: a height field that follows the camera)
##     and leave a splash there: a ring that spreads on the surface plus a few bouncing beads.
##   - Low mist: a few big soft puffs drifting near the ground.
##   - Grade: the picture goes cooler, a little softer and darker, with a gentle vignette; the scene's
##     fog thickens (its own colour is left to the day / night dressing).
## Shown while GameState.is_raining(), in play (not the title) and never in the intro house.
## Fades in and out over FADE_SEC. Sound is Audio's (amb_rain).

const FADE_SEC := 2.5
const AREA := 46.0  # m, square of rain around the point the camera looks at
const DROP_HEIGHT := 11.0  # below the play cameras, so no drop smears across the lens
const DROP_COUNT := 7000
const DROP_SPEED := 26.0
const WIND := Vector3(0.18, 0.0, 0.08)  # slant of the drops (x / z per 1 down)
const SPLASH_COUNT := 2400
const MIST_COUNT := 26
const FOG_MULT := 2.5
const GRADE_LAYER := 5  # under the HUD (10): the UI keeps its colours

const GRADE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
uniform vec3 tint = vec3(0.78, 0.86, 0.96);
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	// a touch of softness: the rain veil
	vec3 soft = textureLod(screen_tex, SCREEN_UV, 1.6).rgb;
	c = mix(c, soft, 0.35 * amount);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 graded = mix(vec3(l), c, 0.8) * tint;
	graded = graded * 0.97 + vec3(0.025, 0.035, 0.05);  // lifted blacks: grey sky light, not darkness
	vec2 d = SCREEN_UV - vec2(0.5);
	float vig = smoothstep(0.9, 0.3, length(d * vec2(1.25, 1.0)));
	graded *= mix(0.86, 1.0, vig);
	COLOR = vec4(mix(c, graded, amount), 1.0);
}
"""

var _drops: GPUParticles3D
var _splash: GPUParticles3D
var _mist: GPUParticles3D
var _field: GPUParticlesCollisionHeightField3D
var _grade_layer: CanvasLayer
var _grade: ColorRect
var _grade_mat: ShaderMaterial
var _amount := 0.0
var _env: Environment
var _env_fog := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	_build_drops()
	_build_mist()
	_field = GPUParticlesCollisionHeightField3D.new()
	_field.name = "Surfaces"
	_field.size = Vector3(AREA + 8.0, DROP_HEIGHT + 30.0, AREA + 8.0)
	_field.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_field.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(_field)
	_grade_layer = CanvasLayer.new()
	_grade_layer.layer = GRADE_LAYER
	add_child(_grade_layer)
	_grade = ColorRect.new()
	_grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = GRADE_SHADER
	_grade_mat = ShaderMaterial.new()
	_grade_mat.shader = sh
	_grade.material = _grade_mat
	_grade_layer.add_child(_grade)
	_set_amount(0.0)


## 0..1 now (tests, the bot).
func amount() -> float:
	return _amount


func wanted() -> bool:
	if not GameState.is_raining() or GameState.flow_state == Enums.FlowState.TITLE:
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var intro := get_tree().get_first_node_in_group(&"intro_cutscene")
	if intro != null and intro.has_method(&"phase") and intro.call(&"phase") == &"house":
		return false  # inside the 낡은 집
	return true


func _process(delta: float) -> void:
	var target := 1.0 if wanted() else 0.0
	if not is_equal_approx(_amount, target):
		_set_amount(move_toward(_amount, target, delta / FADE_SEC))
	if _amount <= 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Centre on where the camera looks (the ground plane under the view), not under the camera.
	var origin := cam.global_position
	var fwd := -cam.global_basis.z
	var centre := origin + fwd * 18.0
	if absf(fwd.y) > 0.05:
		var t := (0.0 - origin.y) / fwd.y
		if t > 0.0 and t < 200.0:
			centre = origin + fwd * t
	centre.y = maxf(centre.y, 0.0)
	# Start well under the camera (the field camera is low): no drop smears across the lens.
	var h := clampf((origin.y - centre.y) * 0.55, 4.0, DROP_HEIGHT)
	_drops.global_position = Vector3(centre.x, centre.y + h, centre.z) - WIND * h
	_mist.global_position = centre + Vector3(0, 0.6, 0)
	_field.global_position = Vector3(centre.x, centre.y + 4.0, centre.z)
	_apply_fog()
	var k := 0.45 if GameState.flow_state == Enums.FlowState.FIELD else 0.8
	_grade_mat.set_shader_parameter(&"amount", _amount * k)


func _set_amount(v: float) -> void:
	_amount = clampf(v, 0.0, 1.0)
	var on := _amount > 0.0
	_drops.emitting = on
	_mist.emitting = on
	_drops.amount_ratio = _amount
	_mist.amount_ratio = _amount
	_grade.visible = on
	# The field already has its own dark vision light: a lighter grade there.
	var k := 0.45 if GameState.flow_state == Enums.FlowState.FIELD else 0.8
	_grade_mat.set_shader_parameter(&"amount", _amount * k)
	_apply_fog()


## The scene's fog, thicker while it rains. The dressing owns the colour; only density is touched,
## and it goes back when the rain stops or the scene changes.
func _apply_fog() -> void:
	var we := get_viewport().find_world_3d()
	var env: Environment = null
	if we != null:
		env = we.environment if we.environment != null else we.fallback_environment
	if env != _env:
		if _env != null and _env_fog >= 0.0 and is_instance_valid(_env):
			_env.fog_density = _env_fog
		_env = env
		_env_fog = env.fog_density if env != null else -1.0
	if _env != null and _env_fog >= 0.0:
		_env.fog_density = _env_fog * lerpf(1.0, FOG_MULT, _amount)


# ---------------- particles ----------------

func _build_drops() -> void:
	_drops = GPUParticles3D.new()
	_drops.name = "Drops"
	_drops.amount = DROP_COUNT
	_drops.lifetime = DROP_HEIGHT / DROP_SPEED * 1.6
	_drops.preprocess = _drops.lifetime
	_drops.fixed_fps = 0
	_drops.local_coords = false
	_drops.visibility_aabb = AABB(Vector3(-AREA, -DROP_HEIGHT - 40.0, -AREA), Vector3(AREA * 2.0, DROP_HEIGHT + 60.0, AREA * 2.0))
	_drops.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA * 0.5, 2.0, AREA * 0.5)
	pm.direction = Vector3(WIND.x, -1.0, WIND.z).normalized()
	pm.spread = 1.5
	pm.initial_velocity_min = DROP_SPEED * 0.9
	pm.initial_velocity_max = DROP_SPEED * 1.1
	pm.gravity = Vector3(0, -6.0, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	pm.sub_emitter_amount_at_collision = 1
	_drops.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.016, 0.55)
	quad.material = _streak_material()
	_drops.draw_pass_1 = quad
	add_child(_drops)
	_splash = _build_splash()
	add_child(_splash)
	_drops.sub_emitter = _drops.get_path_to(_splash)


func _build_splash() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Splashes"
	p.amount = SPLASH_COUNT
	p.lifetime = 0.42
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 100, 400))
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.particle_flag_rotate_y = true
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.15))
	grow.add_point(Vector2(1.0, 1.0), 0.6, 0.0)
	var gc := CurveTexture.new()
	gc.curve = grow
	pm.scale_curve = gc
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.75))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var ring := QuadMesh.new()
	ring.size = Vector2(0.8, 0.8)
	ring.orientation = PlaneMesh.FACE_Y
	ring.center_offset = Vector3(0, 0.03, 0)
	ring.material = _ring_material()
	p.draw_pass_1 = ring
	return p


func _build_mist() -> void:
	_mist = GPUParticles3D.new()
	_mist.name = "Mist"
	_mist.amount = MIST_COUNT
	_mist.lifetime = 9.0
	_mist.preprocess = 9.0
	_mist.local_coords = false
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mist.visibility_aabb = AABB(Vector3(-AREA, -5, -AREA), Vector3(AREA * 2.0, 12, AREA * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA * 0.55, 0.4, AREA * 0.55)
	pm.direction = Vector3(1, 0, 0.3)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3.ZERO
	pm.scale_min = 7.0
	pm.scale_max = 12.0
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	_mist.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = _mist_material()
	_mist.draw_pass_1 = quad
	add_child(_mist)


# ---------------- materials ----------------

func _streak_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.86, 0.93, 1.0, 0.5)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	# soft at both ends, brighter towards the leading tip
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.85, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 1.0)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 4
	gt.height = 64
	m.albedo_texture = gt
	return m


func _ring_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.9, 0.96, 1.0, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.78, 0.9, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	m.albedo_texture = gt
	return m


func _mist_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.78, 0.84, 0.9, 0.09)
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 1.5
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	m.albedo_texture = gt
	return m
