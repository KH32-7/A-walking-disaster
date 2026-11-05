extends Node3D
## Sandbox: tune the vision light (VisionShade) live. Run alone (F6).
## Sliders start from the shader defaults. "값 복사" puts the current values on the clipboard
## as shader uniform lines to paste into vision_shade.gdshader.

const SandboxCameraInput := preload("res://field/_sandbox/sandbox_camera_input.gd")
## [uniform, label, min, max, step]
const SLIDERS := [
	[&"circle_start", "원 흐려짐 시작", 0.0, 12.0, 0.1],
	[&"circle_end", "원 끝", 0.0, 14.0, 0.1],
	[&"cone_half_deg", "부채꼴 반각", 5.0, 90.0, 1.0],
	[&"cone_feather_deg", "경계 번짐", 0.0, 45.0, 1.0],
	[&"cone_fade_start", "앞쪽 흐려짐 시작", 0.0, 30.0, 0.5],
	[&"cone_range", "앞쪽 끝", 1.0, 35.0, 0.5],
	[&"lit_boost", "안쪽 밝기", 0.8, 1.5, 0.01],
]
const SHADE_CHANNELS := ["바깥 R", "바깥 G", "바깥 B"]

@onready var _camera: FieldCamera = $FieldCamera
@onready var _box: VBoxContainer = $DebugLayer/Panel/Box

var _shade: VisionShade
var _mat: ShaderMaterial
var _defaults := {}
var _sliders := {}  # key -> HSlider (uniform name, "shade_0..2", "turn")
var _shade_color := Color(0.70, 0.70, 0.78)


func _ready() -> void:
	# UI autoload opens the title screen on boot (flow state TITLE). Sandbox only: hide it.
	if UI.is_open(&"title"):
		UI.close(&"title")
	SandboxCameraInput.ensure()
	for c in _camera.get_children():
		if c is VisionShade:
			_shade = c
	_mat = _shade.material_override as ShaderMaterial
	var rid := VisionShade.SHADER.get_rid()
	for s in SLIDERS:
		_defaults[s[0]] = RenderingServer.shader_get_parameter_default(rid, s[0])
		_add_slider(s[0], s[1], s[2], s[3], s[4])
	var shade: Variant = RenderingServer.shader_get_parameter_default(rid, &"out_shade")
	if shade is Color:
		_shade_color = shade
	elif shade is Vector3:
		_shade_color = Color(shade.x, shade.y, shade.z)
	_defaults[&"out_shade"] = _shade_color
	for i in 3:
		_add_slider("shade_%d" % i, SHADE_CHANNELS[i], 0.0, 1.0, 0.01)
	_add_slider(&"turn", "회전 따라오기", 1.0, 40.0, 0.5)
	_add_buttons()
	_reset()


func _add_slider(key: Variant, label: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size.x = 150
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size.x = 200
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 50
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%.2f" % v
		_apply(key, v))
	row.add_child(name_label)
	row.add_child(slider)
	row.add_child(value_label)
	_box.add_child(row)
	_sliders[key] = slider


func _add_buttons() -> void:
	var row := HBoxContainer.new()
	var toggle := Button.new()
	toggle.text = "시야 켜기/끄기"
	toggle.pressed.connect(_toggle)
	var reset := Button.new()
	reset.text = "기본값"
	reset.pressed.connect(_reset)
	var copy := Button.new()
	copy.text = "값 복사"
	copy.pressed.connect(_copy)
	for b: Button in [toggle, reset, copy]:
		b.focus_mode = Control.FOCUS_NONE
		row.add_child(b)
	_box.add_child(row)


func _toggle() -> void:
	var on := not _shade.is_processing()
	_shade.set_process(on)
	_shade.visible = on


func _apply(key: Variant, v: float) -> void:
	if key == &"turn":
		_shade.turn_sharpness = v
	elif str(key).begins_with("shade_"):
		_shade_color[int(str(key).right(1))] = v
		_mat.set_shader_parameter(&"out_shade", _shade_color)
	else:
		_mat.set_shader_parameter(key, v)


func _reset() -> void:
	for s in SLIDERS:
		if _defaults[s[0]] != null:
			_sliders[s[0]].value = float(_defaults[s[0]])
	var shade: Color = _defaults[&"out_shade"]
	for i in 3:
		_sliders["shade_%d" % i].value = shade[i]
	_sliders[&"turn"].value = VisionShade.TURN_SHARPNESS


func _copy() -> void:
	var lines := PackedStringArray()
	for s in SLIDERS:
		lines.append("uniform float %s = %s;" % [s[0], _sliders[s[0]].value])
	lines.append("uniform vec3 out_shade : source_color = vec3(%.2f, %.2f, %.2f);" % [
		_shade_color.r, _shade_color.g, _shade_color.b])
	lines.append("const TURN_SHARPNESS := %s" % _sliders[&"turn"].value)
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	print(text)
