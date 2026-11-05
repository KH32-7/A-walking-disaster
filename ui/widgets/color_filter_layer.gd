class_name ColorFilterLayer
extends CanvasLayer
## Full-screen colour-blind filter (D-15). Owner: Lane D. `UI` adds one above every other layer,
## so it covers the 3D world, the HUD, menus and overlays. Hidden when Settings.color_filter is 0.
## Shader: res://art/shaders/color_filter.gdshader.

const LAYER := 120
const SHADER := preload("res://art/shaders/color_filter.gdshader")

var rect: ColorRect


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.name = &"Filter"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	add_child(rect)
	apply()
	EventBus.settings_changed.connect(func(k: StringName) -> void:
		if k == &"color_filter":
			apply())


func apply() -> void:
	var mode := clampi(int(Settings.get_value(&"color_filter")), 0, 3)
	(rect.material as ShaderMaterial).set_shader_parameter(&"mode", mode)
	visible = mode != 0


func mode() -> int:
	return int((rect.material as ShaderMaterial).get_shader_parameter(&"mode"))
