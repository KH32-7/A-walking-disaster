extends Node
## Autoload `Radio`. Owner: Lane A (task A-14).
## Decides WHEN the broadcaster speaks (rule-based triggers) and WHAT is said
## (offline template lines from data/radio/), then emits EventBus.radio_message.
## No LLM: the team dropped generative AI features.
## Other lanes never emit radio_message for the broadcaster themselves - they call `say()`
## or emit their normal gameplay signals and let the trigger table react.
## Design reference: docs/design/15-ai-features.md "AI 무전병", 13-world-narrative.md "아침 방송"
##
## Field situations only Lane B can see call say() directly:
##   Radio.say(&"low_ammo")                          # ammo < 20 %
##   Radio.say(&"low_health")                        # hp < 30 %
##   Radio.say(&"noise_high")                        # noise stayed loud
##   Radio.say(&"rescuee_low_health")                # companion hp low
##   Radio.say(&"no_progress", {"direction": "북쪽"}) # 3 minutes without progress
##   Radio.say(&"dusk", {"minutes": 3})              # SORTIE_DUSK_SEC reached
## and Radio.set_combat(true/false) around fights (one line per fight).
## Radio reacts by itself to: day_started (morning broadcast with weather), raid_warning
## (morning sign / 60 s warning / day-raid prediction while in the field), player_downed +
## sortie_started (repeated downs in one region, once before the next sortie there).

const BROADCASTER := &"broadcaster"
const TRIGGERS_DIR := "res://data/radio"
## Settings "ai_radio_frequency": 0 off (story lines only), 1 when needed, 2 often.
const FREQ_OFF := 0
const FREQ_OFTEN := 2
## Same region downs before the broadcaster suggests another approach.
const REPEATED_DOWNS := 3
## Korean names for raid directions in lines (Colony uses &"north" ...).
const DIRECTION_NAMES := {&"north": "북쪽", &"south": "남쪽", &"east": "동쪽", &"west": "서쪽"}
const OUTCOME_NAMES := ["완승", "승리", "아슬아슬한 승리", "패배"]

## id -> RadioTrigger
var triggers: Dictionary = {}
## Recorded wording of the line being emitted right now ("" = speak it as shown). RadioVoice reads it.
var voice_text := ""

## Seconds of unpaused game time; cooldowns use this so pausing does not burn them.
var _clock := 0.0
## trigger id -> _clock when it last spoke
var _last_spoke: Dictionary = {}
## trigger ids already used in this sortie / day
var _used_sortie: Dictionary = {}
var _used_day: Dictionary = {}
## trigger id -> index list still to play (shuffle bag, so lines rotate without repeats)
var _bags: Dictionary = {}
var _in_combat := false
var _spoke_this_combat := false
var _current_region: StringName
## region id -> downs (saved), region id -> true once advised
var _downs: Dictionary = {}
var _advised: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_load_triggers()
	SaveSystem.register_provider(&"radio", self)
	EventBus.day_started.connect(_on_day_started)
	EventBus.sortie_started.connect(_on_sortie_started)
	EventBus.player_downed.connect(_on_player_downed)
	EventBus.raid_warning.connect(_on_raid_warning)


func _process(delta: float) -> void:
	_clock += delta


## Queue a line. `template_id` is a data/radio trigger id; `context` fills its {placeholders}.
## priority < 0 uses the trigger's own priority. Returns true if a line was emitted.
func say(template_id: StringName, context: Dictionary = {}, priority: int = -1) -> bool:
	var trigger: RadioTrigger = triggers.get(template_id)
	if trigger == null:
		push_error("Radio: unknown trigger '%s'" % template_id)
		return false
	if not _allowed(trigger):
		return false
	var line := _next_line(trigger).format(context)
	var index: int = _bags[String(trigger.id) + ":last"]
	voice_text = trigger.voice_lines[index] if index < trigger.voice_lines.size() else ""
	_last_spoke[trigger.id] = _clock
	if trigger.once_per == &"sortie":
		_used_sortie[trigger.id] = true
	elif trigger.once_per == &"day":
		_used_day[trigger.id] = true
	if _in_combat:
		_spoke_this_combat = true
	EventBus.radio_message.emit(BROADCASTER, line, trigger.priority if priority < 0 else priority)
	voice_text = ""
	return true


## Lane B: true while the player is fighting. Only one guidance line per fight.
func set_combat(active: bool) -> void:
	if active and not _in_combat:
		_spoke_this_combat = false
	_in_combat = active


## The full morning broadcast. Called on day_started; also usable from the debug console.
func morning_broadcast() -> void:
	say(&"morning_greeting", {"day": GameState.day})
	say(&"morning_weather_rain" if GameState.is_raining() else &"morning_weather_clear")
	say(&"morning_quip")


# --- Signal reactions ---

func _on_day_started(_day: int) -> void:
	_used_day.clear()
	if not in_tutorial():
		morning_broadcast()


## True while the new-game tutorial runs (intro house → park doctor). No morning broadcast then
## (사용자 요청 2026-11-06): the 방송실 지기 is talking to the hero in person.
static func in_tutorial() -> bool:
	return GameState.has_flag(IntroCutscene.FLAG_PENDING) and not GameState.has_flag(IntroTutorial.FLAG_DONE)


func _on_sortie_started(loadout: Dictionary) -> void:
	_used_sortie.clear()
	_current_region = StringName(loadout.get("region_id", &""))
	if _downs.get(_current_region, 0) >= REPEATED_DOWNS and not _advised.has(_current_region):
		_advised[_current_region] = true
		say(&"repeated_downs", {"region": _region_name(_current_region)})


func _on_player_downed() -> void:
	if _current_region != &"":
		_downs[_current_region] = _downs.get(_current_region, 0) + 1


## raid_warning info is the Colony.roll_raid() Dictionary (contracts.md).
func _on_raid_warning(info: Dictionary) -> void:
	var directions: Array = info.get("directions", [])
	var direction := _direction_name(directions[0] if not directions.is_empty() else &"")
	var is_day := int(info.get("time", Enums.RaidTime.NIGHT)) == Enums.RaidTime.DAY
	if is_day and FieldState.in_sortie():
		_day_raid_advice(info)
	elif GameState.phase == Enums.Phase.MORNING:
		say(&"raid_sign", {"direction": direction})
	else:
		say(&"raid_warning", {"direction": direction})


func _day_raid_advice(info: Dictionary) -> void:
	var prediction: Dictionary = {}
	if Colony.has_method(&"predict_raid"):
		prediction = Colony.call(&"predict_raid", info)
	var likely := int(prediction.get("likely", Enums.RaidOutcome.WIN))
	var range_text := _outcome_range(prediction)
	if likely >= Enums.RaidOutcome.NARROW:
		say(&"day_raid_return", {"range": range_text})
	else:
		say(&"day_raid_hold", {"range": range_text})


# --- Save provider "radio" ---

func save_data() -> Dictionary:
	return {"downs": _downs, "advised": _advised}


func load_data(data: Dictionary) -> void:
	_downs = data.get("downs", {})
	_advised = data.get("advised", {})


# --- Internals ---

func _allowed(trigger: RadioTrigger) -> bool:
	var frequency := int(Settings.get_value(&"ai_radio_frequency"))
	if trigger.guidance and frequency == FREQ_OFF:
		return false
	if trigger.once_per == &"sortie" and _used_sortie.has(trigger.id):
		return false
	if trigger.once_per == &"day" and _used_day.has(trigger.id):
		return false
	if trigger.guidance and _in_combat and _spoke_this_combat:
		return false
	var cooldown := trigger.cooldown_sec * (0.5 if frequency == FREQ_OFTEN else 1.0)
	if cooldown > 0.0 and _last_spoke.has(trigger.id) and _clock - _last_spoke[trigger.id] < cooldown:
		return false
	return not trigger.lines.is_empty()


func _next_line(trigger: RadioTrigger) -> String:
	var bag: Array = _bags.get(trigger.id, [])
	if bag.is_empty():
		for i in trigger.lines.size():
			bag.append(i)
		# Shuffle, but never start a new round with the line that ended the previous one.
		var last: int = _bags.get(String(trigger.id) + ":last", -1)
		for i in range(bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp: int = bag[i]
			bag[i] = bag[j]
			bag[j] = tmp
		if bag.size() > 1 and bag.back() == last:
			bag.push_front(bag.pop_back())
	var index: int = bag.pop_back()
	_bags[trigger.id] = bag
	_bags[String(trigger.id) + ":last"] = index
	return trigger.lines[index]


func _outcome_range(prediction: Dictionary) -> String:
	if not prediction.has("ratio_min"):
		return "예상하기 어렵습니다"
	var likely := clampi(int(prediction.get("likely", Enums.RaidOutcome.WIN)), 0, OUTCOME_NAMES.size() - 1)
	return "%s 쪽 (전력비 %.1f~%.1f)" % [OUTCOME_NAMES[likely], prediction["ratio_min"], prediction["ratio_max"]]


func _direction_name(direction: StringName) -> String:
	return DIRECTION_NAMES.get(direction, String(direction) if direction != &"" else "어느 쪽")


func _region_name(region_id: StringName) -> String:
	# TODO(B): use the region's display name once data/regions has one.
	return String(region_id)


func _load_triggers() -> void:
	triggers.clear()
	for file in ResourceLoader.list_directory(TRIGGERS_DIR):
		if file.ends_with(".tres"):
			var trigger := load(TRIGGERS_DIR.path_join(file)) as RadioTrigger
			if trigger == null or trigger.id == &"":
				push_error("Radio: %s is not a RadioTrigger with an id" % file)
				continue
			triggers[trigger.id] = trigger
