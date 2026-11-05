class_name MusicLayerDef
extends Resource
## One music stem (D-20). Owner: Lane D. Data: data/ui/music_layers/<id>.tres.
## Design 16 "데이터 정의": MusicLayer {id, state(BASE, FIELD, CHASE, NIGHT, RAID, FESTIVAL), unlock_population}.
## Every stem has the same tempo and length (MusicSynth.BPM / LOOP_SEC), so Audio starts all stems of one
## timeline together and only fades their volume: layers come and go without breaking the beat.
## `stream` is a real file (assets/audio/...) once licensed music exists; until then `synth` names a
## placeholder recipe in audio/synth_music.gd. A real stem file must keep the same tempo and length.
## A `full_track` is a finished song instead (any length, Audio loops it).

## title / base / festival (overlay on base) / field / chase (overlay on field) / night / raid
@export var state: StringName = &"base"
@export var id: StringName
## Heard only when Colony.population() >= this (base instruments join as the colony grows).
@export var unlock_population := 0
## Field region (levels/field/<region_id>/) this layer belongs to. Empty = any region. A region that has its
## own layers for a state hears only those; the empty-region layers are the fallback for the other regions.
@export var region: StringName = &""
## A complete song, not a stem. An overlay (chase, festival) that is a full track replaces the layers under
## it (crossfade) instead of mixing over them.
@export var full_track := false
@export_file("*.ogg", "*.wav", "*.mp3") var stream := ""
@export var synth: StringName = &""
@export var volume_db := -6.0
## Text for players who cannot hear the music (Audio.music_layers_changed listeners show it).
@export var caption := ""
@export var visual_cue_id: StringName = &""
