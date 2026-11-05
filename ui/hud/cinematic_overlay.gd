class_name CinematicOverlay
extends Control
## Film look for cutscenes and story talks (사용자 요청 2026-11-06, 인트로 컷신). Owner: Lane D.
## Letterbox bars, a black fade, a vignette, a title card, captions in the lower bar and a talk box
## that types its lines and waits for F / Enter / click. Hold Esc to skip a skippable scene.
## Everything is awaitable:  await UI.cinematic.fade_to(1.0, 0.6)
##                           await UI.cinematic.talk([["한도윤", "문 잘 잠갔지?"], ...])
## Lives on its own layer (25): above the HUD and menus, below the overlay (spotlight, toasts).

signal skip_requested
signal talk_finished

const BAR_RATIO := 0.115  # each bar, of the screen height
const TYPE_CPS := 38.0  # typed characters per second
const SKIP_HOLD_SEC := 1.0
const SPEAKER_COLOR := Color("f6c744")  # UiTokens.ACCENT

const VIGNETTE := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	d.x *= 1.6;
	float v = smoothstep(0.32, 0.95, length(d));
	COLOR = vec4(0.0, 0.0, 0.0, v * strength);
}
"""

var skippable := false
## True for a whole cutscene: the radio / broadcast subtitles stay hidden under it.
var film := false
var _top: ColorRect
var _bottom: ColorRect
var _black: ColorRect
var _vignette: ColorRect
var _title: Label
var _sub: Label
var _caption: Label
var _talk: PanelContainer
var _talk_name: Label
var _talk_text: Label
var _talk_next: Label
var _skip_box: HBoxContainer
var _skip_bar: ProgressBar
var _bars := 0.0
var _skip_t := 0.0
## Esc held in this window (key events, not the OS key state: a press elsewhere must not skip).
var _esc_down := false
var _lines: Array = []
var _line := -1
var _typed := 0.0
var _talking := false
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_vignette = ColorRect.new()
	var sh := Shader.new()
	sh.code = VIGNETTE
	var m := ShaderMaterial.new()
	m.shader = sh
	_vignette.material = m
	_full(_vignette)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.modulate.a = 0.0
	_full(_black)
	_top = ColorRect.new()
	_top.color = Color.BLACK
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	_bottom = ColorRect.new()
	_bottom.color = Color.BLACK
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom)
	_title = _make_label(64, 800, UiTokens.TEXT)
	_title.add_theme_constant_override(&"outline_size", 0)
	_sub = _make_label(22, 500, UiTokens.TEXT_DIM)
	_caption = _make_label(26, 600, UiTokens.TEXT)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_talk()
	_skip_box = HBoxContainer.new()
	_skip_box.add_theme_constant_override(&"separation", 10)
	_skip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_box.add_child(KeyChip.new("Esc", KeyChip.Style.OUTLINE))
	var sl := _make_label(15, 500, UiTokens.TEXT_DIM, false)
	sl.text = "길게 눌러 건너뛰기"
	_skip_box.add_child(sl)
	_skip_bar = ProgressBar.new()
	_skip_bar.custom_minimum_size = Vector2(60, 4)
	_skip_bar.show_percentage = false
	_skip_bar.max_value = 1.0
	_skip_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skip_box.add_child(_skip_bar)
	add_child(_skip_box)
	for l: Label in [_title, _sub, _caption]:
		l.modulate.a = 0.0
	_layout()
	resized.connect(_layout)


func _full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)


func _make_label(fs: int, weight: int, color: Color, add := true) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", UiThemeBuilder.font_kr(weight))
	l.add_theme_font_size_override(&"font_size", fs)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override(&"outline_size", 6)
	if add:
		add_child(l)
	return l


func _build_talk() -> void:
	_talk = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.05, 0.86)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.border_width_top = 1
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 20
	sb.content_margin_bottom = 22
	_talk.add_theme_stylebox_override(&"panel", sb)
	_talk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_talk_name = _make_label(20, 700, SPEAKER_COLOR, false)
	_talk_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(_talk_name)
	_talk_text = _make_label(25, 500, UiTokens.TEXT, false)
	_talk_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_talk_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_talk_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_talk_text.custom_minimum_size = Vector2(0, 76)
	v.add_child(_talk_text)
	_talk_next = _make_label(15, 500, UiTokens.TEXT_DIM, false)
	_talk_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_talk_next.text = "F / 클릭  ▶"
	v.add_child(_talk_next)
	_talk.add_child(v)
	_talk.visible = false
	add_child(_talk)


func _layout() -> void:
	var vp := size
	var bar := vp.y * BAR_RATIO * _bars
	_top.position = Vector2.ZERO
	_top.size = Vector2(vp.x, bar)
	_bottom.position = Vector2(0, vp.y - bar)
	_bottom.size = Vector2(vp.x, bar)
	_title.position = Vector2(0, vp.y * 0.5 - 70)
	_title.size = Vector2(vp.x, 90)
	_sub.position = Vector2(0, vp.y * 0.5 + 24)
	_sub.size = Vector2(vp.x, 40)
	_caption.position = Vector2(vp.x * 0.15, vp.y - vp.y * BAR_RATIO + 8)
	_caption.size = Vector2(vp.x * 0.7, vp.y * BAR_RATIO - 16)
	var tw := minf(1100.0, vp.x - 120.0)
	_talk.size = Vector2(tw, 0)
	_talk.position = Vector2((vp.x - tw) * 0.5, vp.y - vp.y * 0.06 - _talk.get_combined_minimum_size().y)
	var ss := _skip_box.get_combined_minimum_size()
	_skip_box.position = Vector2(vp.x - ss.x - 36, 26)


# ---------------- API ----------------

## Letterbox in (true) or out. Also hides the HUD layer while the bars are in.
func bars(on: bool, sec := 0.8) -> Tween:
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(_set_bars, _bars, 1.0 if on else 0.0, sec)
	var vm := _vignette.material as ShaderMaterial
	tw.parallel().tween_method(func(v: float) -> void: vm.set_shader_parameter(&"strength", v),
		float(vm.get_shader_parameter(&"strength")), 0.75 if on else 0.0, sec)
	if UI.hud != null:
		UI.hud.visible = not on
	if UI.subtitle != null:
		UI.subtitle.visible = not on  # the base's morning broadcast waits for the film to end
	return tw


## Black over everything: 1 = black, 0 = clear.
func fade_to(alpha: float, sec := 0.6) -> Tween:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_black, ^"modulate:a", alpha, sec)
	return tw


## Instant black (a hard cut) or clear.
func cut(black: bool) -> void:
	_black.modulate.a = 1.0 if black else 0.0


## Title card: fades in, holds, fades out. Await it.
func title(text: String, sub := "", hold := 2.2) -> Tween:
	_title.text = text
	_sub.text = sub
	_title.scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(_title, ^"modulate:a", 1.0, 0.9)
	tw.parallel().tween_property(_sub, ^"modulate:a", 1.0, 1.2).set_delay(0.4)
	tw.tween_interval(hold)
	tw.tween_property(_title, ^"modulate:a", 0.0, 0.8)
	tw.parallel().tween_property(_sub, ^"modulate:a", 0.0, 0.8)
	return tw


## One line in the lower bar (radio, thoughts). sec = how long it stays; 0 = until the next.
func caption(text: String, sec := 3.0) -> void:
	_caption.text = text
	var tw := create_tween()
	tw.tween_property(_caption, ^"modulate:a", 1.0, 0.35)
	if sec > 0.0:
		tw.tween_interval(sec)
		tw.tween_property(_caption, ^"modulate:a", 0.0, 0.5)


func clear_caption() -> void:
	create_tween().tween_property(_caption, ^"modulate:a", 0.0, 0.3)


## Talk box: lines = [[speaker, text], ...]. Each line types out; F / Enter / click finishes it,
## then goes on. Emits talk_finished. Await it:  await UI.cinematic.talk(lines)
func talk(lines: Array) -> Signal:
	_lines = lines
	_line = -1
	_talking = true
	_talk.visible = true
	_talk.modulate.a = 0.0
	create_tween().tween_property(_talk, ^"modulate:a", 1.0, 0.25)
	_next_line()
	return talk_finished


func is_talking() -> bool:
	return _talking


## Back to normal: no bars, no black, nothing on screen.
func reset() -> void:
	_esc_down = false
	skippable = false
	film = false
	_set_bars(0.0)
	(_vignette.material as ShaderMaterial).set_shader_parameter(&"strength", 0.0)
	_black.modulate.a = 0.0
	for l: Label in [_title, _sub, _caption]:
		l.modulate.a = 0.0
	_talk.visible = false
	_talking = false
	if UI.hud != null:
		UI.hud.visible = true
	if UI.subtitle != null:
		UI.subtitle.visible = true


# ---------------- internals ----------------

func _set_bars(v: float) -> void:
	_bars = v
	_layout()


func _next_line() -> void:
	_line += 1
	if _line >= _lines.size():
		_talking = false
		var tw := create_tween()
		tw.tween_property(_talk, ^"modulate:a", 0.0, 0.2)
		tw.tween_callback(func() -> void: _talk.visible = false)
		talk_finished.emit()
		return
	_talk_name.text = String(_lines[_line][0])
	_talk_text.text = String(_lines[_line][1])
	_talk_text.visible_characters = 0
	_typed = 0.0
	Audio.play(&"ui_click")
	_layout()


func _process(delta: float) -> void:
	_t += delta
	if UI.subtitle != null and film:
		UI.subtitle.visible = false
	elif UI.subtitle != null and _bars <= 0.0:
		UI.subtitle.visible = true
	if _talking and _line >= 0 and _line < _lines.size():
		var total := _talk_text.get_total_character_count()
		if _talk_text.visible_characters >= 0 and _talk_text.visible_characters < total:
			_typed += delta * TYPE_CPS
			_talk_text.visible_characters = mini(int(_typed), total)
		_talk_next.modulate.a = 0.45 + 0.4 * sin(_t * 4.0) if _talk_text.visible_characters >= total else 0.0
	_skip_box.visible = skippable
	if skippable:
		if _esc_down:
			_skip_t += delta
			if _skip_t >= SKIP_HOLD_SEC:
				_skip_t = 0.0
				skippable = false
				skip_requested.emit()
		else:
			_skip_t = maxf(_skip_t - delta * 2.0, 0.0)
		_skip_bar.value = _skip_t / SKIP_HOLD_SEC


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE and not event.is_echo():
		_esc_down = event.is_pressed() and skippable
	if not _talking:
		return
	var go := false
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		go = k in [KEY_F, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		go = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if not go:
		return
	get_viewport().set_input_as_handled()
	var total := _talk_text.get_total_character_count()
	if _talk_text.visible_characters < total and _talk_text.visible_characters >= 0:
		_talk_text.visible_characters = total  # first press finishes the line
	else:
		_next_line()
