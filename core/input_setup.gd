extends Node
## Autoload `InputSetup`. Owner: Lane A.
## Default bindings are defined in code (not in project.godot) so that nobody has to
## edit project.godot to add an action, and so the remap UI (Lane D) can reset to defaults.
## Design reference: docs/design/14-ui-controls-accessibility.md

const DEFAULTS := {
	&"move_up": [{"key": KEY_W}, {"joy_axis": [JOY_AXIS_LEFT_Y, -1.0]}],
	&"move_down": [{"key": KEY_S}, {"joy_axis": [JOY_AXIS_LEFT_Y, 1.0]}],
	&"move_left": [{"key": KEY_A}, {"joy_axis": [JOY_AXIS_LEFT_X, -1.0]}],
	&"move_right": [{"key": KEY_D}, {"joy_axis": [JOY_AXIS_LEFT_X, 1.0]}],
	&"attack": [{"mouse": MOUSE_BUTTON_LEFT}, {"joy_axis": [JOY_AXIS_TRIGGER_RIGHT, 1.0]}],
	&"aim": [{"mouse": MOUSE_BUTTON_RIGHT}, {"joy_axis": [JOY_AXIS_TRIGGER_LEFT, 1.0]}],
	&"dodge": [{"key": KEY_SPACE}, {"joy_button": JOY_BUTTON_A}],
	&"sprint": [{"key": KEY_SHIFT}, {"joy_button": JOY_BUTTON_LEFT_STICK}],
	&"reload": [{"key": KEY_R}, {"joy_button": JOY_BUTTON_X}],
	&"interact": [{"key": KEY_F}, {"joy_button": JOY_BUTTON_B}],
	&"weapon_1": [{"key": KEY_1}],
	&"weapon_2": [{"key": KEY_2}],
	&"weapon_swap": [{"joy_button": JOY_BUTTON_Y}],
	&"item_1": [{"key": KEY_3}, {"joy_button": JOY_BUTTON_DPAD_UP}],
	&"item_2": [{"key": KEY_4}, {"joy_button": JOY_BUTTON_DPAD_RIGHT}],
	&"item_3": [{"key": KEY_5}, {"joy_button": JOY_BUTTON_DPAD_DOWN}],
	&"item_4": [{"key": KEY_6}, {"joy_button": JOY_BUTTON_DPAD_LEFT}],
	&"skill_q": [{"key": KEY_Q}, {"joy_button": JOY_BUTTON_LEFT_SHOULDER}],
	&"skill_e": [{"key": KEY_E}, {"joy_button": JOY_BUTTON_RIGHT_SHOULDER}],
	&"essence_release": [{"key": KEY_X}],
	&"companion_command": [{"key": KEY_V}, {"joy_button": JOY_BUTTON_RIGHT_STICK}],
	&"bag": [{"key": KEY_TAB}, {"joy_button": JOY_BUTTON_BACK}],
	&"map": [{"key": KEY_M}],
	&"pause": [{"key": KEY_ESCAPE}, {"joy_button": JOY_BUTTON_START}],
}


func _ready() -> void:
	apply_defaults(false)


## overwrite = true resets every action to its defaults (used by the remap UI).
func apply_defaults(overwrite: bool) -> void:
	for action: StringName in DEFAULTS:
		if InputMap.has_action(action):
			if not overwrite:
				continue
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.3)
		for spec: Dictionary in DEFAULTS[action]:
			InputMap.action_add_event(action, _make_event(spec))


func _make_event(spec: Dictionary) -> InputEvent:
	if spec.has("key"):
		var key_event := InputEventKey.new()
		key_event.physical_keycode = spec["key"]
		return key_event
	if spec.has("mouse"):
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = spec["mouse"]
		return mouse_event
	if spec.has("joy_button"):
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = spec["joy_button"]
		return button_event
	var axis_event := InputEventJoypadMotion.new()
	axis_event.axis = spec["joy_axis"][0]
	axis_event.axis_value = spec["joy_axis"][1]
	return axis_event
