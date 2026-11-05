class_name NoiseEmitter
extends Node3D
## Noise component (B-05). Add as a child of the actor (player, door, generator ...).
## Looks up the action's radius in the NoiseTable, applies modifiers and emits
## EventBus.noise_emitted(position, radius, source). That signal is the ONLY way noise
## reaches monsters: B-07 compares distance <= radius * its own hearing multiplier.
## This component never looks monsters up itself.
## Design reference: docs/design/02-field.md "소음".

const DEFAULT_TABLE := preload("res://field/noise/noise_table.tres")

@export var table: NoiseTable = DEFAULT_TABLE
## Armory owner whose armor adds footstep noise (Armory.PLAYER_ID for the player).
## Empty = no armor bonus (doors, generators, monsters).
@export var armory_owner_id: StringName = &""
## Rainy day: every radius x table.rain_multiplier.
## TODO(A request): read the day's weather from GameState once A adds it; this export stands in.
@export var raining := false

var _continuous_action: StringName = &""
var _continuous_timer: Timer


## Final radius for `action` with every modifier applied. 0 for unknown actions.
func radius_for(action: StringName) -> float:
	if not table.has_action(action):
		push_error("NoiseEmitter: unknown noise action '%s'" % action)
		return 0.0
	var radius := table.base_radius(action)
	if table.is_footstep(action):
		radius += _armor_bonus()
		# TODO(B-13 or later): add table.quiet_step_bonus when the actor has the "조용한 발걸음" trait.
	if raining:
		radius *= table.rain_multiplier
	return maxf(radius, 0.0)


## Emits one noise for `action` at this node's position. Returns the radius (0 = nothing emitted).
func emit(action: StringName) -> float:
	var radius := radius_for(action)
	if radius > 0.0:
		EventBus.noise_emitted.emit(global_position, radius, get_parent())
	return radius


## Repeats `action` every table.continuous_interval_sec until stop_continuous() (e.g. generator).
func start_continuous(action: StringName) -> void:
	_continuous_action = action
	if _continuous_timer == null:
		_continuous_timer = Timer.new()
		_continuous_timer.timeout.connect(_on_continuous_timeout)
		add_child(_continuous_timer)
	_continuous_timer.start(table.continuous_interval_sec)
	emit(action)


func stop_continuous() -> void:
	_continuous_action = &""
	if _continuous_timer != null:
		_continuous_timer.stop()


func is_continuous() -> bool:
	return _continuous_action != &""


func _on_continuous_timeout() -> void:
	emit(_continuous_action)


## Sum of worn armor noise_mod. Armory applies the +3m cap (05-gear.md "방어구 기본형").
func _armor_bonus() -> float:
	if armory_owner_id == &"":
		return 0.0
	return float(Armory.get_owner_summary(armory_owner_id).get("armor_noise", 0.0))
