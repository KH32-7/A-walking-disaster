class_name FxDef
extends Resource
## One effect id (D-18). Owner: Lane D. Lives in data/ui/effects/<id>.tres; Fx.spawn(id, ...) builds it.

@export var id: StringName
## Minimum life in seconds. The effect also lives until its last layer is done.
@export var lifetime := 0.5
## When set and present in params, that value (seconds) is the life instead (zones: &"duration").
@export var lifetime_param: StringName = &""
## Radius the layers are authored for; params.radius scales `follow_radius` layers.
@export var base_radius := 1.0
## Oldest copies of this id are removed beyond this many.
@export var max_alive := 16
## Audio event ids (data/ui/audio_events) Fx plays at the spot. Leave empty when gameplay plays it.
@export var sound: StringName = &""
@export var sound_crit: StringName = &""
## When set, Fx first looks for "<id>_<params[variant_param]>" (essence_combo + id swamp -> essence_combo_swamp).
@export var variant_param: StringName = &""
@export var layers: Array[FxLayer] = []
