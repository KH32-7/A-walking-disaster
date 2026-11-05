class_name RadioVoice
extends Node
## Reads radio_message lines aloud (D-16). Owner: Lane D.
## Design 14 "AI 무전병: 음성 켜기", 15 (template radio, no LLM). The subtitle (UI.subtitle) always
## shows the line; this only adds the voice when Settings.radio_voice is on.
## A recorded clip for the exact line (clip_path, private assets/) plays first. Without one it
## falls back to Godot's built-in TTS, which needs the project setting
## audio/general/text_to_speech = true (Lane A, project.godot) and an OS voice; without either it
## stays silent. Prefers a Korean voice. Volume = master × voice.

const SETTING := "audio/general/text_to_speech"
const CLIP_DIR := "res://assets/audio/voice"

## Last line handed to the voice (tests read this even when TTS is unavailable).
var last_spoken := ""
var _voice := ""
var _player: AudioStreamPlayer
var _queue: Array[AudioStream] = []


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = &"Voice"  # Audio already scales this bus by master x voice volume
	_player.finished.connect(_play_next)
	add_child(_player)
	EventBus.radio_message.connect(_on_radio_message)


## Recorded clip for this exact line. Name = first 12 hex chars of the line's MD5, so a clip
## always matches its subtitle. Editing a line's text drops its clip until it is re-recorded.
static func clip_path(speaker_id: StringName, text: String) -> String:
	return "%s/%s/%s.mp3" % [CLIP_DIR, speaker_id, text.md5_text().left(12)]


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


func _on_radio_message(speaker_id: StringName, text: String, priority: int) -> void:
	say(speaker_id, text, priority > 0)


## Voice only, no subtitle. Cutscenes that draw their own captions call this.
func say(speaker_id: StringName, text: String, interrupt := false) -> void:
	if not wants_voice():
		return
	last_spoken = text
	var path := clip_path(speaker_id, text)
	if ResourceLoader.exists(path):
		_play_clip(load(path), interrupt)
		return
	if not available():
		return
	var id := voice_id()
	if id == "":
		return
	# A more urgent line cuts the current one off (same rule as the subtitle queue).
	DisplayServer.tts_speak(text, id, volume(), 1.0, 1.0, 0, interrupt)


## A more urgent line cuts the current one off; others wait their turn.
func _play_clip(stream: AudioStream, interrupt: bool) -> void:
	if interrupt:
		_queue.clear()
		_player.stop()
	if _player.playing:
		_queue.append(stream)
		return
	_player.stream = stream
	_player.play()


func _play_next() -> void:
	if not _queue.is_empty():
		_player.stream = _queue.pop_front()
		_player.play()
