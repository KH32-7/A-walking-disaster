extends CanvasLayer
## Debug panel for the look (\ key, or console `look`). Created by DebugConsole in debug builds only.
##
## Top: Look.tuning (data/look/look_tuning.tres): toon shading amount, the screen style (] flips it
## on/off), the player outline. "스타일 저장" writes that .tres; "스타일 되돌리기" reloads it.
## Bottom: the current map's lighting and post-processing. The map's Dressing node
## (art/dressing/region_dressing.gd) builds its WorldEnvironment and sun from exported properties;
## the sliders change those live, "맵에 저장" writes them into the map's dressing.tscn and
## "값 복사" copies them as .tscn lines. Saving to res:// works only when running from the editor.

const TOGGLE_KEY := KEY_BACKSLASH
const FLIP_KEY := KEY_BRACKETRIGHT
const PATH := "res://data/look/look_tuning.tres"
const DRESSING_SCRIPT := "res://art/dressing/region_dressing.gd"
## Look.tuning: [property, label, min, max, step]
const STYLE_FIELDS := [
	[&"toon_amount", "툰 셰이딩 (0 끔)", 0.0, 1.0, 0.05],
	[&"paint_radius", "붓터치 반경 (0 끔)", 0, 6, 1],
	[&"paint_step", "붓터치 간격 px", 1.0, 4.0, 0.25],
	[&"outline_px", "외곽선 두께 px", 0.0, 4.0, 0.25],
	[&"outline_depth", "외곽선 깊이 감도", 0.0, 0.3, 0.01],
	[&"outline_normal", "외곽선 면 꺾임 감도", 0.0, 2.0, 0.05],
	[&"outline_strength", "외곽선 진하기", 0.0, 1.0, 0.05],
	[&"outline_fade_far", "외곽선 최대 거리 m", 5.0, 200.0, 1.0],
	[&"saturation", "채도", 0.0, 2.0, 0.05],
	[&"contrast", "대비", 0.5, 2.0, 0.05],
	[&"brightness", "밝기", 0.5, 2.0, 0.05],
	[&"bands", "명암 단계 (0 끔)", 0, 8, 1],
	[&"band_mix", "명암 단계 섞기", 0.0, 1.0, 0.05],
	[&"hero_outline_px", "주인공 외곽선 px (0 끔)", 0.0, 8.0, 0.25],
]
## Dressing properties: [property, label, min, max, step]. _apply_map() pushes them to the live
## Environment / sun the same way region_dressing.gd builds them.
const MAP_FIELDS := [
	[&"exposure", "노출", 0.2, 3.0, 0.02],
	[&"agx_contrast", "톤맵 대비 (AgX)", 0.5, 3.0, 0.05],
	[&"sun_energy", "해 밝기", 0.0, 4.0, 0.05],
	[&"ambient_energy", "주변광", 0.0, 2.0, 0.02],
	[&"ssao_intensity", "SSAO (구석 그늘)", 0.0, 8.0, 0.1],
	[&"glow_intensity", "글로우", 0.0, 2.0, 0.05],
	[&"glow_bloom", "블룸", 0.0, 0.5, 0.01],
	[&"fog_density", "안개", 0.0, 0.01, 0.0002],
	[&"contrast", "맵 대비", 0.5, 2.0, 0.02],
	[&"saturation", "맵 채도", 0.0, 2.0, 0.02],
]

var _panel: PanelContainer
var _scroll: ScrollContainer
var _enabled: CheckButton
var _style_sliders := {}  # property -> [HSlider, Label, step]
var _map_sliders := {}
var _map_title: Label
var _status: Label
var _dressing: Node  # the current map's Dressing node, null outside a map


func _ready() -> void:
	layer = 127
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	# Typing \ or ] into the console must not flip the look.
	if key == null or not key.pressed or key.echo or DebugConsole.is_open():
		return
	if key.physical_keycode == TOGGLE_KEY:
		toggle()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == FLIP_KEY:
		flip()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	_scroll.custom_minimum_size.y = get_viewport().get_visible_rect().size.y - 56.0
	# The map changes when going base <-> field.
	if _find_dressing() != _dressing:
		_sync()


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_sync()


## Turns the screen style on/off. Returns the new state.
func flip() -> bool:
	Look.tuning.enabled = not Look.tuning.enabled
	_sync()
	return Look.tuning.enabled


func _sync() -> void:
	_enabled.set_pressed_no_signal(Look.tuning.enabled)
	for p: StringName in _style_sliders:
		_show(_style_sliders[p], float(Look.tuning.get(p)))
	_dressing = _find_dressing()
	var has_map := _dressing != null
	_map_title.text = "맵 조명: %s" % _dressing.scene_file_path.get_file() if has_map else "맵 조명: (맵 없음)"
	for p: StringName in _map_sliders:
		var row: Array = _map_sliders[p]
		row[0].editable = has_map
		if has_map:
			_show(row, float(_dressing.get(p)))


func _show(row: Array, value: float) -> void:
	row[0].set_value_no_signal(value)
	row[1].text = _fmt(row[0].value, row[2])


func _fmt(value: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % int(value)
	return "%.4f" % value if step < 0.001 else "%.2f" % value


func _find_dressing() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for n in scene.find_children("*", "Node3D", true, false):
		var script := n.get_script() as Script
		if script != null and script.resource_path == DRESSING_SCRIPT:
			return n
	return null


func _on_style(value: float, property: StringName) -> void:
	var row: Array = _style_sliders[property]
	row[1].text = _fmt(value, row[2])
	if row[2] >= 1.0:
		Look.tuning.set(property, int(value))
	else:
		Look.tuning.set(property, snappedf(value, 0.0001))


func _on_map(value: float, property: StringName) -> void:
	var row: Array = _map_sliders[property]
	row[1].text = _fmt(value, row[2])
	if _dressing == null:
		return
	_dressing.set(property, snappedf(value, 0.0001))
	_apply_map()


## Same mapping as region_dressing.gd _environment().
func _apply_map() -> void:
	var env_node := _dressing.get_node_or_null(^"DressingEnvironment") as WorldEnvironment
	var sun := _dressing.get_node_or_null(^"Sun") as DirectionalLight3D
	if env_node != null and env_node.environment != null:
		var e := env_node.environment
		e.tonemap_exposure = _d(&"exposure")
		e.tonemap_agx_contrast = _d(&"agx_contrast")
		e.ambient_light_energy = _d(&"ambient_energy")
		e.ssao_enabled = _d(&"ssao_intensity") > 0.0
		e.ssao_intensity = _d(&"ssao_intensity")
		e.glow_intensity = _d(&"glow_intensity")
		e.glow_bloom = _d(&"glow_bloom")
		e.fog_density = _d(&"fog_density")
		e.adjustment_enabled = true
		e.adjustment_contrast = _d(&"contrast")
		e.adjustment_saturation = _d(&"saturation")
	if sun != null:
		sun.light_energy = _d(&"sun_energy")


func _d(property: StringName) -> Variant:
	return _dressing.get(property)


func _on_style_save() -> void:
	var err := ResourceSaver.save(Look.tuning, PATH)
	_status.text = "스타일 저장함" if err == OK else "스타일 저장 실패: %s" % PATH


func _on_style_revert() -> void:
	var disk := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as LookTuning
	if disk != null:
		for prop in disk.get_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE and prop.name != "script" and prop.name != "resource_path":
				Look.tuning.set(prop.name, disk.get(prop.name))
	_sync()
	_status.text = "스타일을 파일 값으로 되돌림"


## The map values as .tscn property lines (ssao on/off and adjust follow the sliders).
func _map_lines() -> Dictionary:
	var lines := {}
	for p: StringName in _map_sliders:
		var num := String.num(float(_dressing.get(p)), 4)  # no 0.8200000000000001 in the .tscn
		lines[String(p)] = num if num.contains(".") else num + ".0"
	lines["ssao"] = var_to_str(float(_dressing.get(&"ssao_intensity")) > 0.0)
	lines["adjust"] = "true"
	return lines


func _on_map_copy() -> void:
	if _dressing == null:
		return
	var lines := _map_lines()
	var text := ""
	for k: String in lines:
		text += "%s = %s\n" % [k, lines[k]]
	DisplayServer.clipboard_set(text)
	print("[look] %s\n%s" % [_dressing.scene_file_path, text])
	_status.text = "클립보드에 복사함 (%s)" % _dressing.scene_file_path.get_file()


## Rewrites `key = value` lines of the root node in the map's dressing .tscn in place; missing keys
## go after the node's last property.
func _on_map_save() -> void:
	if _dressing == null or _dressing.scene_file_path.is_empty():
		_status.text = "저장할 맵 파일이 없음"
		return
	var path := _dressing.scene_file_path
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_status.text = "맵 파일을 못 읽음: %s" % path
		return
	var src := f.get_as_text().split("\n")
	f.close()
	var root_at := -1
	for i in src.size():
		if src[i].begins_with("[node ") and not src[i].contains(" parent="):
			root_at = i
			break
	if root_at < 0:
		_status.text = "맵 파일에서 루트 노드를 못 찾음"
		return
	var end := src.size()
	for i in range(root_at + 1, src.size()):
		if src[i].begins_with("["):
			end = i
			break
	var lines := _map_lines()
	var out := PackedStringArray()
	var done := {}
	var last_prop := root_at  # index in `out` of the root block's last property line
	for i in src.size():
		var line := src[i]
		if i > root_at and i < end:
			var key := line.get_slice(" = ", 0)
			if lines.has(key):
				line = "%s = %s" % [key, lines[key]]
				done[key] = true
			if not line.strip_edges().is_empty():
				last_prop = out.size()
		elif i == root_at:
			last_prop = out.size()
		out.append(line)
	var missing := PackedStringArray()
	for k: String in lines:
		if not done.has(k):
			missing.append("%s = %s" % [k, lines[k]])
	for j in missing.size():
		out.insert(last_prop + 1 + j, missing[j])
	f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = "맵 저장 실패 (에디터에서 실행했는지 확인): %s" % path
		return
	f.store_string("\n".join(out))
	f.close()
	_status.text = "맵에 저장함: %s" % path


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(460, 600)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	_scroll.add_child(box)

	var title := Label.new()
	title.text = "화면 스타일 (\\ 키 패널, ] 키 켜기/끄기)"
	box.add_child(title)
	_enabled = CheckButton.new()
	_enabled.text = "화면 스타일 켜기"
	_enabled.focus_mode = Control.FOCUS_NONE
	_enabled.toggled.connect(func(on: bool) -> void: Look.tuning.enabled = on)
	box.add_child(_enabled)
	for f in STYLE_FIELDS:
		_style_sliders[f[0]] = _slider_row(box, f, _on_style)
	_buttons(box, [["스타일 저장", _on_style_save], ["스타일 되돌리기", _on_style_revert]])

	box.add_child(HSeparator.new())
	_map_title = Label.new()
	box.add_child(_map_title)
	for f in MAP_FIELDS:
		_map_sliders[f[0]] = _slider_row(box, f, _on_map)
	_buttons(box, [["맵에 저장", _on_map_save], ["값 복사", _on_map_copy]])

	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.6)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


## Returns [HSlider, value Label, step].
func _slider_row(box: Container, f: Array, on_change: Callable) -> Array:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = f[1]
	name_label.custom_minimum_size = Vector2(180, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = f[2]
	slider.max_value = f[3]
	slider.step = f[4]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Keyboard focus would let WASD move the slider instead of the player.
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(on_change.bind(f[0]))
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size = Vector2(56, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	box.add_child(row)
	return [slider, value, float(f[4])]


func _buttons(box: Container, specs: Array) -> void:
	var row := HBoxContainer.new()
	for spec in specs:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		row.add_child(b)
	box.add_child(row)
