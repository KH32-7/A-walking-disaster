class_name RadioVoice
extends Node
## Reads radio_message lines aloud with Godot's built-in TTS (D-16). Owner: Lane D.
## Design 14 "AI 무전병: 음성 켜기", 15 (template radio, no LLM). The subtitle (UI.subtitle) always
## shows the line; this only adds the voice when Settings.radio_voice is on.
## Needs the project setting audio/general/text_to_speech = true (Lane A, project.godot) and an OS
## voice; without either it stays silent. Prefers a Korean voice. Volume = master × voice.

const SETTING := "audio/general/text_to_speech"

## Last line handed to the TTS engine (tests read this even when TTS is unavailable).
var last_spoken := ""
var _voice := ""


func _ready() -> void:
	EventBus.radio_message.connect(_on_radio_message)


func available() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, false)) \
		and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


func wants_voice() -> bool:
	return bool(Settings.get_value(&"radio_voice")) and volume() > 0.0


## 0..100 for DisplayServer.tts_speak.
func volume() -> int:
	return roundi(100.0 * float(Settings.get_value(&"volume_master")) * float(Settings.get_value(&"volume_voice")))


func voice_id() -> String:
	if _voice == "" and available():
		var ko := DisplayServer.tts_get_voices_for_language("ko")
		if not ko.is_empty():
			_voice = ko[0]
		else:
			var all := DisplayServer.tts_get_voices()
			if not all.is_empty():
				_voice = String(all[0].get("id", ""))
	return _voice


func _on_radio_message(_speaker_id: StringName, text: String, priority: int) -> void:
	if not wants_voice():
		return
	last_spoken = text
	if not available():
		return
	var id := voice_id()
	if id == "":
		return
	# A more urgent line cuts the current one off (same rule as the subtitle queue).
	DisplayServer.tts_speak(text, id, volume(), 1.0, 1.0, 0, priority > 0)
