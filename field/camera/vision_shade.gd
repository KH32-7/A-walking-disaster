class_name VisionShade
extends MeshInstance3D
## B: Duckov-style vision light. Lit fan in front of the player, darker behind.
## Shape from docs/design/02-field.md "시야" (6m circle, 90 deg fan, 18m). Hidden when the
## player has field_rules off (base). Numbers live in the shader uniforms' defaults.

const SHADER := preload("res://field/camera/vision_shade.gdshader")
## Light follows the facing a little behind the body so the edge sweeps instead of snapping.
const TURN_SHARPNESS := 9.0

var turn_sharpness := TURN_SHARPNESS
var _mat := ShaderMaterial.new()
var _yaw := 0.0
var _has_yaw := false


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	_mat.shader = SHADER
	_mat.render_priority = Material.RENDER_PRIORITY_MAX
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


func _process(delta: float) -> void:
	var p := get_tree().get_first_node_in_group(Player.GROUP) as Player
	visible = p != null and p.field_rules
	if not visible:
		return
	var f := p.facing()
	var want := atan2(f.x, f.z)
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-turn_sharpness * delta)) if _has_yaw else want
	_has_yaw = true
	_mat.set_shader_parameter(&"player_xz", Vector2(p.global_position.x, p.global_position.z))
	_mat.set_shader_parameter(&"facing_xz", Vector2(sin(_yaw), cos(_yaw)))
