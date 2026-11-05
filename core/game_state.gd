extends Node
## Autoload `GameState`. Owner: Lane A.
## Global, lane-independent state only: day, season, phase, flags.
## Domain state lives in the domain autoloads (Economy, Armory, FieldState, Colony).
## Design reference: docs/design/01-flow-time.md

const DAYS_PER_SEASON := 15
const SORTIE_DUSK_SEC := 12.0 * 60.0
const SORTIE_NIGHT_SEC := 15.0 * 60.0

## Coarse day phase for each fine-grained flow state. TITLE is absent: it keeps the current phase.
const PHASE_OF_FLOW := {
	Enums.FlowState.BASE_MORNING: Enums.Phase.MORNING,
	Enums.FlowState.SORTIE_PREP: Enums.Phase.MORNING,
	Enums.FlowState.FIELD: Enums.Phase.SORTIE,
	Enums.FlowState.RESULT: Enums.Phase.SORTIE,
	Enums.FlowState.BASE_STAY: Enums.Phase.STAY,
	Enums.FlowState.BASE_DAY_RAID: Enums.Phase.STAY,
	Enums.FlowState.EVENING: Enums.Phase.EVENING,
	Enums.FlowState.NIGHT: Enums.Phase.NIGHT,
	Enums.FlowState.NIGHT_RAID: Enums.Phase.NIGHT,
	Enums.FlowState.NIGHT_EVENT: Enums.Phase.NIGHT,
}

var day: int = 1
var phase: Enums.Phase = Enums.Phase.MORNING
var flow_state: Enums.FlowState = Enums.FlowState.TITLE
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


## Called by SceneRouter only. Emits flow_state_changed, then phase_changed if the phase moved.
func set_flow_state(next: Enums.FlowState) -> void:
	if next == flow_state:
		return
	flow_state = next
	EventBus.flow_state_changed.emit(flow_state)
	if PHASE_OF_FLOW.has(next):
		set_phase(PHASE_OF_FLOW[next])


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
