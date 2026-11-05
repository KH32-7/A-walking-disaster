class_name MenuReader
extends Node
## Menu text-to-speech (D-15, design 14 "메뉴 읽어주기"). Owner: Lane D.
## `UI` adds one. While `Settings.tts_menu` is on, it reads the focused control whenever focus
## moves (buttons: their text; anything with `tts_text()`: that), and screens may call
## `MenuReader.say()` when a value changes. Uses Godot's built-in TTS (DisplayServer.tts_speak).
## TTS also needs the project setting `audio/general/text_to_speech` (Lane A, project.godot);
## without it nothing is spoken, but `last_text` still records what would have been read (tests).

const SETTING := "audio/general/text_to_speech"

## What was (or would have been) spoken last. For tests and the preview.
static var last_text := ""
static var _voice := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Speaks `text` now (interrupting the previous line) if menu TTS is on.
static func say(text: String) -> void:
	if text.is_empty() or not bool(Settings.get_value(&"tts_menu")):
		return
	last_text = text
	if not can_speak():
		return
	if _voice.is_empty():
		var voices := DisplayServer.tts_get_voices_for_language("ko")
		if voices.is_empty():
			voices = DisplayServer.tts_get_voices_for_language("en")
		_voice = voices[0] if not voices.is_empty() else ""
	if _voice.is_empty():
		return
	var vol := roundi(100.0 * clampf(float(Settings.get_value(&"volume_voice")) \
		* float(Settings.get_value(&"volume_master")), 0.0, 1.0))
	DisplayServer.tts_speak(text, _voice, vol, 1.0, 1.0, 0, true)


static func can_speak() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, false)) and DisplayServer.get_name() != "headless"


## Text for a control: tts_text() if it has one, else a button's text or a label's text.
static func text_of(c: Control) -> String:
	if c == null:
		return ""
	if c.has_method(&"tts_text"):
		return String(c.call(&"tts_text"))
	if c is Button:
		return (c as Button).text if not (c as Button).text.is_empty() else (c as Button).tooltip_text
	if c is Label:
		return (c as Label).text
	return c.tooltip_text


func _on_focus_changed(c: Control) -> void:
	say(text_of(c))
