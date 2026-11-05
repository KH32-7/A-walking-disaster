class_name MusicLayerDef
extends Resource
## One music stem (D-20). Owner: Lane D. Data: data/ui/music_layers/<id>.tres.
## Design 16 "데이터 정의": MusicLayer {id, state(BASE, FIELD, CHASE, NIGHT, RAID, FESTIVAL), unlock_population}.
## Every stem has the same tempo and length (MusicSynth.BPM / LOOP_SEC), so Audio starts all stems of one
## timeline together and only fades their volume: layers come and go without breaking the beat.
## `stream` is a real file (assets/audio/...) once licensed music exists; until then `synth` names a
## placeholder recipe in audio/synth_music.gd. A real file must keep the same tempo and length.

## base / festival (overlay on base) / field / chase (overlay on field) / night / raid
@export var state: StringName = &"base"
@export var id: StringName
## Heard only when Colony.population() >= this (base instruments join as the colony grows).
@export var unlock_population := 0
@export_file("*.ogg", "*.wav", "*.mp3") var stream := ""
@export var synth: StringName = &""
@export var volume_db := -6.0
## Text for players who cannot hear the music (Audio.music_layers_changed listeners show it).
@export var caption := ""
@export var visual_cue_id: StringName = &""
