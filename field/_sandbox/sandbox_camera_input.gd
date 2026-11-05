extends RefCounted
## Sandbox only: registers the FieldCamera actions that core/input_setup.gd does not have yet
## (request to Lane A pending). Adds only missing actions, so real defaults win once they land.
## Gameplay code never touches InputMap.

const ACTIONS := {
	&"camera_rotate_left": [{"key": KEY_Z}],
	&"camera_rotate_right": [{"key": KEY_C}],
	&"camera_zoom_in": [{"mouse": MOUSE_BUTTON_WHEEL_UP}],
	&"camera_zoom_out": [{"mouse": MOUSE_BUTTON_WHEEL_DOWN}],
	&"aim_left": [{"joy_axis": [JOY_AXIS_RIGHT_X, -1.0]}],
	&"aim_right": [{"joy_axis": [JOY_AXIS_RIGHT_X, 1.0]}],
	&"aim_up": [{"joy_axis": [JOY_AXIS_RIGHT_Y, -1.0]}],
	&"aim_down": [{"joy_axis": [JOY_AXIS_RIGHT_Y, 1.0]}],
}


static func ensure() -> void:
	for action: StringName in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for spec: Dictionary in ACTIONS[action]:
			InputMap.action_add_event(action, _make_event(spec))


static func _make_event(spec: Dictionary) -> InputEvent:
	if spec.has("key"):
		var key_event := InputEventKey.new()
		key_event.physical_keycode = spec["key"]
		return key_event
	if spec.has("mouse"):
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = spec["mouse"]
		return mouse_event
	var axis_event := InputEventJoypadMotion.new()
	axis_event.axis = spec["joy_axis"][0]
	axis_event.axis_value = spec["joy_axis"][1]
	return axis_event
