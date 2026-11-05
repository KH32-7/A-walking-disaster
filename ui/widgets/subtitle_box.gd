class_name SubtitleBox
extends VBoxContainer
## Bottom-centre subtitle (UI_RULES §4-§5): max 2 lines, speaker name in ACCENT, shadow only.
## Owner: Lane D (D-01). UI puts one on the overlay layer and feeds it EventBus.radio_message.
## Follows Settings: subtitles, subtitle_size, subtitle_speaker, subtitle_bg_alpha.
## Text longer than MAX_CHARS is cut with "…" so a line never runs past 2 rows at 900px.

const MAX_LINES := 2
const MAX_CHARS := 70
const CHARS_PER_SEC := 14.0
const MIN_SEC := 2.5

## True while a film or a talk owns the screen (CinematicOverlay): nothing shows and the current
## line's time does not run, so the broadcast waits for the scene to end. Set this instead of
## `visible`; the box shows itself only while it has a line.
var held := false:
	set(v):
		if v == held:
			return
		held = v
		_refresh_visible()

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _left := 0.0
var _label: RichTextLabel
var _bg: StyleBoxFlat


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bg = StyleBoxFlat.new()
	_bg.set_corner_radius_all(UiTokens.CARD_RADIUS)
	_bg.content_margin_left = 14
	_bg.content_margin_right = 14
	_bg.content_margin_top = 6
	_bg.content_margin_bottom = 6
	panel.add_theme_stylebox_override(&"panel", _bg)
	add_child(panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(900, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override(&"font_shadow_color", UiTokens.SHADOW)
	_label.add_theme_constant_override(&"shadow_offset_y", 2)
	_label.add_theme_constant_override(&"shadow_outline_size", 3)
	panel.add_child(_label)
	visible = false
	_apply_settings()
	if not EventBus.settings_changed.is_connected(_on_settings_changed):
		EventBus.settings_changed.connect(_on_settings_changed)


## speaker_name may be empty (narration). Lines longer than 2 rows are cut by the label width.
## Line width in px. UI narrows it while a menu is open so it fits right of the key footer.
func set_width(w: float) -> void:
	if _label != null:
		_label.custom_minimum_size.x = w


func show_line(speaker_name: String, text: String, priority: int = 0) -> void:
	var item := {"speaker": speaker_name, "text": text, "priority": priority}
	if not _current.is_empty() and priority > int(_current.get("priority", 0)):
		_queue.push_front(_current)
		_play(item)
		return
	if _current.is_empty():
		_play(item)
	else:
		_queue.append(item)


func clear() -> void:
	_queue.clear()
	_current = {}
	_refresh_visible()


func current_text() -> String:
	return String(_current.get("text", ""))


func _play(item: Dictionary) -> void:
	_current = item
	_left = maxf(MIN_SEC, String(item.text).length() / CHARS_PER_SEC)
	var speaker := String(item.speaker)
	var show_speaker := bool(Settings.get_value(&"subtitle_speaker")) and not speaker.is_empty()
	var raw := String(item.text)
	if raw.length() > MAX_CHARS:
		raw = raw.left(MAX_CHARS - 1) + "..."
	var body := _keep_words(raw).replace("[", "[lb]")
	var head := ("[color=#%s][b]%s[/b][/color]  " % [UiTokens.ACCENT.to_html(false), speaker]) \
		if show_speaker else ""
	_label.text = "[center]" + head + body + "[/center]"
	_label.add_theme_constant_override(&"line_separation", 4)
	_refresh_visible()


func _refresh_visible() -> void:
	visible = not held and not _current.is_empty() and bool(Settings.get_value(&"subtitles"))


## Hangul may break between any two syllables in a RichTextLabel (잡 / 혔습니다). A word joiner
## (U+2060, zero width) between letters keeps each word whole, so lines break only at spaces.
static func _keep_words(s: String) -> String:
	var out := ""
	for i in s.length():
		if i > 0 and s[i] != " " and s[i - 1] != " ":
			out += "⁠"
		out += s[i]
	return out


func _process(delta: float) -> void:
	if _current.is_empty() or held:
		return
	_left -= delta
	if _left <= 0.0:
		_current = {}
		if _queue.is_empty():
			_refresh_visible()
		else:
			_play(_queue.pop_front())


func _apply_settings() -> void:
	var idx := int(Settings.get_value(&"subtitle_size"))
	var size_px := roundi(UiTokens.SIZE_SUBTITLE * UiTokens.SUBTITLE_SCALES[clampi(idx, 0, 2)])
	_label.add_theme_font_size_override(&"normal_font_size", size_px)
	_label.add_theme_font_size_override(&"bold_font_size", size_px)
	_label.add_theme_font_override(&"normal_font", UiThemeBuilder.font_kr(500))
	_label.add_theme_font_override(&"bold_font", UiThemeBuilder.font_kr(700))
	_bg.bg_color = Color(0, 0, 0, float(Settings.get_value(&"subtitle_bg_alpha")) * 0.6)
	_refresh_visible()


func _on_settings_changed(key: StringName) -> void:
	if String(key).begins_with("subtitle"):
		_apply_settings()
