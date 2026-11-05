class_name NoiseTable
extends Resource
## Noise radius table and modifiers (B-05). Values live in field/noise/noise_table.tres.
## Design reference: docs/design/02-field.md "소음", 05-gear.md "방어구 기본형",
## 07-residents.md "조용한 발걸음". All numbers are 가안.

## Base radius in meters per action id (lowercase snake_case StringName).
@export var radii: Dictionary[StringName, float] = {}
## Actions that count as footsteps: armor bonus and "조용한 발걸음" apply only to these.
@export var footstep_actions: Array[StringName] = []
## Upper limit of the summed armor noise bonus on footsteps (m).
@export var armor_bonus_cap := 3.0
## Footstep bonus of the "조용한 발걸음" trait (m). Not wired yet: the player has no traits.
@export var quiet_step_bonus := -2.0
## Multiplier applied to every radius on a rainy day.
@export var rain_multiplier := 0.75
## Seconds between repeats while a continuous noise (generator) runs.
@export var continuous_interval_sec := 1.0


func has_action(action: StringName) -> bool:
	return radii.has(action)


func base_radius(action: StringName) -> float:
	return radii.get(action, 0.0)


func is_footstep(action: StringName) -> bool:
	return footstep_actions.has(action)
