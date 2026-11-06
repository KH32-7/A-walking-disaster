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
	# The base turns its follow camera off (process disabled) while nobody walks there: this light must
	# still check, or it stays lit at the shader's default spot (사용자 제보 2026-11-06: 기지에 빛).
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	_mat.shader = SHADER
	_mat.render_priority = Material.RENDER_PRIORITY_MAX
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	# Hidden until _process finds a field player. The base map keeps its FieldCamera (with this shade)
	# switched off between direct defences, so _process never ran there and the shade stayed on: a
	# light circle over the base where the hidden player stood (user report 2026-11-06).
	visible = false
	DebugConsole.register(&"vision", _cmd_vision,
		"vision <out|boost|circle|cone|feather|range> <값...> - 시야 라이트 값 바꾸기")


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


## Debug console: tune the light inside a real field, where it is darker than the sandbox.
func _cmd_vision(args: PackedStringArray) -> String:
	const KEYS := {"boost": &"lit_boost", "cone": &"cone_half_deg", "feather": &"cone_feather_deg",
		"range": &"cone_range"}
	if args.size() == 2 and args[0] == "out":
		var v := float(args[1])
		_mat.set_shader_parameter(&"out_shade", Color(v, v, v + 0.08))
	elif args.size() == 3 and args[0] == "circle":
		_mat.set_shader_parameter(&"circle_start", float(args[1]))
		_mat.set_shader_parameter(&"circle_end", float(args[2]))
	elif args.size() == 2 and KEYS.has(args[0]):
		_mat.set_shader_parameter(KEYS[args[0]], float(args[1]))
	else:
		return "사용법: vision out 0.7 / vision boost 1.2 / vision circle 1 2.1 / vision cone 32"
	return "적용함"
