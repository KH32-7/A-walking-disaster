extends Node
## Autoload `GameState`. Owner: Lane A.
## Global, lane-independent state only: day, season, phase, flags.
## Domain state lives in the domain autoloads (Economy, Armory, FieldState, Colony).
## Design reference: docs/design/01-flow-time.md

const DAYS_PER_SEASON := 15
const SORTIE_DUSK_SEC := 12.0 * 60.0
const SORTIE_NIGHT_SEC := 15.0 * 60.0

var day: int = 1
var phase: Enums.Phase = Enums.Phase.MORNING
## Story / unlock flags. Keys are StringName, values are bool or int.
var flags: Dictionary = {}


@warning_ignore("integer_division")
func season() -> Enums.Season:
	return (((day - 1) / DAYS_PER_SEASON) % 4) as Enums.Season


func set_phase(next: Enums.Phase) -> void:
	if next == phase:
		return
	phase = next
	EventBus.phase_changed.emit(phase)


func start_next_day() -> void:
	day += 1
	set_phase(Enums.Phase.MORNING)
	EventBus.day_started.emit(day)


func has_flag(flag: StringName) -> bool:
	return bool(flags.get(flag, false))


func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[flag] = value


# --- Save provider (see SaveSystem) ---
func save_data() -> Dictionary:
	return {"day": day, "phase": phase, "flags": flags}


func load_data(data: Dictionary) -> void:
	day = int(data.get("day", 1))
	phase = int(data.get("phase", Enums.Phase.MORNING)) as Enums.Phase
	flags = data.get("flags", {})
