class_name AudioEventDef
extends Resource
## One sound event (D-11). Owner: Lane D. Data: data/ui/audio_events/<id>.tres.
## Design 16 "데이터 정의": AudioEvent {id, stream, bus, noise_radius, visual_cue_id, priority}.
## `stream` is a real file (assets/audio/...) once licensed audio exists; until then `synth`
## names a placeholder recipe in audio/synth.gd so every event already makes a sound.
## noise_radius is informational only - Lane B decides noise and emits EventBus.noise_emitted.

enum Bus { SFX, VOICE, MUSIC, UI }
## Mixing (16 "믹싱 우선순위"): noise warning > radio > combat > music.
enum Priority { LOW, COMBAT, RADIO, WARNING }

@export var id: StringName
@export_file("*.ogg", "*.wav", "*.mp3") var stream := ""
@export var synth: StringName = &""
@export var bus: Bus = Bus.SFX
@export var priority: Priority = Priority.COMBAT
@export var volume_db := 0.0
@export var pitch_random := 0.06
## Played in 3D at the given position when one is passed (false: always 2D, e.g. UI).
@export var positional := true
@export var max_distance := 40.0
@export var noise_radius := 0.0
## Visual cue for players who cannot hear it (UI shows it next to the subtitle line).
@export var visual_cue_id: StringName = &""
@export var caption := ""
