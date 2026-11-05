class_name BlindOverlay
extends ColorRect
## The player's `blind` status on screen (수술등 망령 섬광, docs/design/04-monsters.md "보스"): a white flash,
## then everything but a small circle round the middle goes dark for as long as the status lasts.
## A rare, big moment instead of a status icon. Settings.reduce_flash: no white pop, only the dark.
## UI puts it on its own CanvasLayer (15: above the HUD, below screens); it finds the player's StatusHolder itself.

const STATUS := &"blind"
const FLASH_SEC := 0.25
## Fade out over the last seconds of the status.
const FADE_SEC := 0.4
const DARK := 0.92
const SHADER_CODE := """
shader_type canvas_item;
uniform float dark = 0.0;
uniform float white = 0.0;
uniform float hole = 0.1;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float a = dark * smoothstep(hole, hole + 0.14, length(d));
	COLOR = vec4(mix(vec3(0.0), vec3(1.0, 0.98, 0.9), white), max(a, white));
}
"""

var _holder: StatusHolder
var _white := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER_CODE
	material = ShaderMaterial.new()
	(material as ShaderMaterial).shader = shader
	visible = false


func _process(delta: float) -> void:
	if not is_instance_valid(_holder):
		_bind()
	var left := _holder.time_left(STATUS) if is_instance_valid(_holder) else 0.0
	_white = maxf(_white - delta / FLASH_SEC, 0.0)
	var dark := clampf(left / FADE_SEC, 0.0, 1.0) * DARK
	visible = dark > 0.0 or _white > 0.0
	(material as ShaderMaterial).set_shader_parameter(&"dark", dark)
	(material as ShaderMaterial).set_shader_parameter(&"white", _white)


func darkness() -> float:
	return float((material as ShaderMaterial).get_shader_parameter(&"dark")) if visible else 0.0


func _bind() -> void:
	_holder = null
	var player := get_tree().get_first_node_in_group(Player.GROUP) if is_inside_tree() else null
	if player == null:
		return
	_holder = player.get_node_or_null(NodePath(StatusHolder.NODE_NAME)) as StatusHolder
	if _holder and not _holder.status_applied.is_connected(_on_applied):
		_holder.status_applied.connect(_on_applied)


func _on_applied(id: StringName, _stacks: int, _time_left: float) -> void:
	if id == STATUS and not Fx.reduced_flash():
		_white = 1.0
