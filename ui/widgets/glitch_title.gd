class_name GlitchTitle
extends Control
## Title text that comes in like a broken broadcast: torn slices and a teal / yellow split, then
## settles. A short burst again every few seconds. Settings.reduce_flash: plain fade in, no bursts.
## The text is drawn once into a SubViewport so the shader can move whole slices of it.

const SHADER := preload("res://ui/widgets/glitch_title.gdshader")
const PAD := 48  # room for torn slices to move without being cut off
const INTRO_DELAY := 0.15
const INTRO_TIME := 0.7
const FADE_TIME := 0.4  # reduce_flash fade in
const IDLE_GAP := Vector2(5.0, 9.0)
const IDLE_TIME := 0.22
const IDLE_POWER := 0.45
const STEP := 0.05  # tear pattern jumps in steps (looks digital, not wobbly)

var _mat := ShaderMaterial.new()
var _label := Label.new()
var _view := SubViewport.new()
var _box := SubViewportContainer.new()
var _t := -INTRO_DELAY
var _next_burst := 0.0
var _burst_end := 0.0
var _step_t := 0.0


func _init(text: String, font: Font, px: int) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	_label.text = text
	_label.add_theme_font_override(&"font", font)
	_label.add_theme_font_size_override(&"font_size", px)
	_label.position = Vector2(PAD, PAD)
	_view.transparent_bg = true
	_view.add_child(_label)
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"text_color", UiTokens.TEXT)
	_mat.set_shader_parameter(&"ghost_a", UiTokens.INFO)
	_mat.set_shader_parameter(&"ghost_b", UiTokens.ACCENT)
	_box.stretch = true
	_box.position = Vector2(-PAD, -PAD)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.material = _mat
	_box.add_child(_view)
	add_child(_box)


func _ready() -> void:
	var s := _label.get_combined_minimum_size()
	custom_minimum_size = s
	_box.size = s + Vector2(PAD, PAD) * 2.0
	_next_burst = INTRO_TIME + randf_range(IDLE_GAP.x, IDLE_GAP.y)


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.0:
		return
	var calm := bool(Settings.get_value(&"reduce_flash"))
	var power := 0.0
	if calm:
		modulate.a = clampf(_t / FADE_TIME, 0.0, 1.0)
	else:
		modulate.a = 1.0
		if _t < INTRO_TIME:
			power = pow(1.0 - _t / INTRO_TIME, 1.5)
		elif _t >= _next_burst:
			_burst_end = _t + IDLE_TIME
			_next_burst = _t + randf_range(IDLE_GAP.x, IDLE_GAP.y)
		if _t < _burst_end:
			power = IDLE_POWER
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = STEP
		_mat.set_shader_parameter(&"seed", randf() * 100.0)
	_mat.set_shader_parameter(&"intensity", power)
