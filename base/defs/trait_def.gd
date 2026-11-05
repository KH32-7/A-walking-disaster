class_name TraitDef
extends Resource
## One resident trait (docs/design/07-residents.md "특성"). Data lives in data/traits/<id>.tres.
## `effects` are read by the system that owns each rule (work output in C-05, morale in C-06,
## relations in C-14, guard power in C-08, companion noise in B-17 via Colony.get_resident()).

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Effect key -> value. Keys used so far:
##   work_efficiency (+0.1 = +10%), solo_work_efficiency, craft_efficiency, fatigue_gain_mult,
##   food_use (+1 / -1 per day), morale_floor, morale_gain_mult, guard_power,
##   no_flee (1), flee_hp_ratio, evacuate_first (1), raid_warning_hours, companion_noise_m,
##   relation_gain_mult, bonfire_relation_mult, friendship_gain_bonus, romance_exempt (1),
##   prejudice_relation_mult, essence_workshop_efficiency
@export var effects: Dictionary[StringName, float] = {}
## Traits that cannot appear together on one resident (부지런함 ↔ 느긋함 ...).
@export var exclusive_with: Array[StringName] = []
## Rolled for new residents. Story traits (편견, 마물 흔적) come only from profiles/events.
@export var randomizable := true
## Can be removed by an event (편견 해소, docs/design/08-relations-population.md).
@export var removable := false


func effect(key: StringName, default: float = 0.0) -> float:
	return effects.get(key, default)
