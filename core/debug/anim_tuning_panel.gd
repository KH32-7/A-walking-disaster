extends CanvasLayer
## Debug animation speed panel (\ key, or console `anim`). Not F9: the editor's embedded
## game view uses F9 to suspend the game, and test scenes use F1-F12.
## Created by DebugConsole in debug builds only.
## Sliders change the player's animation tuning (data/classes/player_anim_tuning.tres) and a few
## movement numbers (data/classes/player_base.tres) in memory while the game keeps running, so feet
## and ground speed can be matched by eye. "저장" writes both .tres files (works when running from
## the editor); "되돌리기" reloads them from disk.

const TOGGLE_KEY := KEY_BACKSLASH
## resource key -> .tres path
const PATHS := {
	&"anim": "res://data/classes/player_anim_tuning.tres",
	&"stats": "res://data/classes/player_base.tres",
}
## [resource key, property, label, min, max, step]
const FIELDS := [
	[&"anim", &"walk_mult", "걷기 애니 배속", 0.1, 4.0, 0.05],
	[&"anim", &"sprint_mult", "달리기 애니 배속", 0.1, 4.0, 0.05],
	[&"anim", &"aim_walk_mult", "총 걷기 애니 배속", 0.1, 4.0, 0.05],
	[&"anim", &"back_walk_mult", "뒷걸음 애니 배속", 0.1, 4.0, 0.05],
	[&"anim", &"dodge_mult", "구르기 애니 배속", 0.1, 4.0, 0.05],
	[&"anim", &"min_playback", "최소 재생 속도", 0.1, 2.0, 0.05],
	[&"anim", &"max_playback", "최대 재생 속도", 0.5, 6.0, 0.05],
	[&"anim", &"sprint_max_playback", "달리기 최대 재생 속도", 0.5, 8.0, 0.05],
	[&"stats", &"walk_speed", "걷기 이동 m/s", 0.5, 10.0, 0.1],
	[&"stats", &"sprint_speed", "달리기 이동 m/s", 0.5, 14.0, 0.1],
	[&"stats", &"backpedal_speed_mult", "뒷걸음 이동 배수", 0.1, 1.0, 0.05],
]

var _panel: PanelContainer
var _sliders := {}  # property -> HSlider
var _values := {}  # property -> Label
var _readout: Label
var _status: Label
var _res := {}  # resource key -> Resource (the cached instances the game uses)


func _ready() -> void:
	layer = 127
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in PATHS:
		_res[key] = load(PATHS[key])
	_build()
	_panel.visible = false


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == TOGGLE_KEY:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_sync()


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var model := player.get_node_or_null(^"Model") if player != null else null
	if model == null or not model.has_method(&"walk_playback"):
		_readout.text = "플레이어 모델 없음 (필드에서 열기)"
		return
	var v: Vector3 = player.get(&"velocity")
	_readout.text = "이동 %.2f m/s  ·  걷기 재생 x%.2f" % [Vector2(v.x, v.z).length(), model.walk_playback()]


func _sync() -> void:
	for f in FIELDS:
		var slider: HSlider = _sliders[f[1]]
		slider.set_value_no_signal(float(_res[f[0]].get(f[1])))
		_values[f[1]].text = "%.2f" % slider.value


func _on_slider(value: float, key: StringName, property: StringName) -> void:
	_values[property].text = "%.2f" % value
	_res[key].set(property, value)


func _on_save() -> void:
	var failed := []
	for key in PATHS:
		if ResourceSaver.save(_res[key], PATHS[key]) != OK:
			failed.append(PATHS[key])
	_status.text = "저장함" if failed.is_empty() else "저장 실패: %s" % ", ".join(failed)


func _on_revert() -> void:
	for key in PATHS:
		var disk := ResourceLoader.load(PATHS[key], "", ResourceLoader.CACHE_MODE_IGNORE)
		if disk == null:
			continue
		for f in FIELDS:
			if f[0] == key:
				_res[key].set(f[1], disk.get(f[1]))
	_sync()
	_status.text = "파일 값으로 되돌림"


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 16)
	_panel.custom_minimum_size = Vector2(400, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "애니메이션 속도 (\\ 키)"
	box.add_child(title)

	for f in FIELDS:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = f[2]
		name_label.custom_minimum_size = Vector2(150, 0)
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = f[3]
		slider.max_value = f[4]
		slider.step = f[5]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Keyboard focus would let WASD move the slider instead of the player.
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(_on_slider.bind(f[0], f[1]))
		row.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size = Vector2(44, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		box.add_child(row)
		_sliders[f[1]] = slider
		_values[f[1]] = value

	_readout = Label.new()
	box.add_child(_readout)

	var buttons := HBoxContainer.new()
	for spec in [["저장", _on_save], ["되돌리기", _on_revert]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		buttons.add_child(b)
	box.add_child(buttons)

	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_status)
