class_name EffectDef
extends Resource
## One visual effect id (D-18). Owner: Lane D. Data: data/ui/effects/<id>.tres.
## Gameplay calls `Fx.spawn(id, position, params)`; Fx instances `scene`, merges `base_params`
## under the caller's params and plays `sound` (Audio event id, data/ui/audio_events) at the position.
## Many ids share one scene and differ only by base_params (e.g. the four element bursts).

@export var id: StringName
@export var scene: PackedScene
## Defaults the caller can override, e.g. {"element": Enums.Element.GREEN}.
@export var base_params: Dictionary = {}
## Audio event played with the effect (&"" = silent). `sound_crit` replaces it when params.crit.
@export var sound: StringName = &""
@export var sound_crit: StringName = &""
## At most this many of this id alive at once; the oldest is freed first (hit sparks in a big fight).
@export var max_alive := 24
## Optional: params read from a ComboDef's effect_params (combo zones size themselves from A's data).
@export var combo_id: StringName = &""
