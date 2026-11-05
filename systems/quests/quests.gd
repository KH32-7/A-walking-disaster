extends Node
## Autoload `Quests`. Owner: Lane A (task A-13).
## Quest state (main story, personal requests, radio rumors, community, trade), objective progress
## from EventBus signals, rewards. Story flags themselves live in GameState (has_flag / set_flag).
## Data: data/quests/*.tres (QuestDef). Save provider "quests".
## Design reference: docs/design/13-world-narrative.md "퀘스트 유형", 07-residents.md "신뢰도"
##
## Lane B: Quests.active_field_objectives(region_id) when a region loads -> place the goals
## (keepsake pickups at "marker", rumor rescuees ...). Keepsakes are resources (data/resources/,
## e.g. keepsake_plane): put them in the bag with Bag.try_add(); the quest completes when they come
## home in the sortie loot. Nothing else to call - progress comes from the normal field signals.
## Lane C: a community event can Quests.start(id) / Quests.advance(id, objective_id).
## Lane D: active_quests() for the quest log, quest_started/updated/completed/failed signals.

enum Status { ACTIVE, COMPLETED, FAILED }

const QUESTS_DIR := "res://data/quests"
const BROADCASTER := &"broadcaster"
const RUMOR_RADIO_TRIGGER := &"quest_rumor"

## id -> QuestDef
var defs: Dictionary = {}

## quest id -> {"status": Status, "start_day": int, "end_day": int, "giver_id": StringName,
## "progress": Array[int] (one per objective)}. Quests never started are absent.
var _states: Dictionary = {}
## Current sortie: {"region_id": StringName, "companions": Array}. Empty outside the field.
var _sortie: Dictionary = {}


func _ready() -> void:
	_load_defs()
	SaveSystem.register_provider(&"quests", self)
	EventBus.day_started.connect(_on_day_started)
	EventBus.sortie_started.connect(_on_sortie_started)
	EventBus.sortie_ended.connect(_on_sortie_ended)
	EventBus.rescue_completed.connect(_on_rescue_completed)
	EventBus.building_completed.connect(_on_building_completed)
	EventBus.raid_resolved.connect(_on_raid_resolved)
	EventBus.resident_left.connect(_on_resident_lost)
	EventBus.resident_died.connect(_on_resident_lost)
	_register_debug_commands()


# --- Public API ---

func get_def(quest_id: StringName) -> QuestDef:
	return defs.get(quest_id)


## Status of a quest, or -1 if it never started.
func get_status(quest_id: StringName) -> int:
	return int(_states[quest_id]["status"]) if _states.has(quest_id) else -1


func is_active(quest_id: StringName) -> bool:
	return get_status(quest_id) == Status.ACTIVE


func is_completed(quest_id: StringName) -> bool:
	return get_status(quest_id) == Status.COMPLETED


## Starts a quest that has never started. `giver_id` overrides the def's giver (templated personal
## requests). Returns false for unknown or already started quests.
func start(quest_id: StringName, giver_id: StringName = &"") -> bool:
	var def := get_def(quest_id)
	if def == null:
		push_error("Quests: unknown quest '%s'" % quest_id)
		return false
	if _states.has(quest_id):
		return false
	var progress: Array[int] = []
	progress.resize(def.objectives.size())
	progress.fill(0)
	_states[quest_id] = {
		"status": Status.ACTIVE,
		"start_day": GameState.day,
		"end_day": 0,
		"giver_id": giver_id if giver_id != &"" else def.giver_id,
		"progress": progress,
	}
	EventBus.quest_started.emit(quest_id)
	EventBus.notification_posted.emit("새 의뢰: %s" % def.title, &"info")
	if def.type == Enums.QuestType.RUMOR and def.radio_text != "" and Radio.triggers.has(RUMOR_RADIO_TRIGGER):
		Radio.say(RUMOR_RADIO_TRIGGER, {"text": def.radio_text})
	if def.objectives.is_empty():
		complete(quest_id)
	return true


## Adds progress to one objective of an active quest (Lane C community events, debug).
## Completes the quest when every objective is done. Returns false if nothing changed.
func advance(quest_id: StringName, objective_id: StringName, amount: int = 1) -> bool:
	var def := get_def(quest_id)
	if def == null or not is_active(quest_id):
		return false
	for i in def.objectives.size():
		if def.objectives[i].id == objective_id:
			return _add_progress(quest_id, i, amount)
	return false


## Finishes an active quest now and grants its rewards. Normally called by progress itself.
func complete(quest_id: StringName) -> bool:
	if not is_active(quest_id):
		return false
	var def := get_def(quest_id)
	var state: Dictionary = _states[quest_id]
	state["status"] = Status.COMPLETED
	state["end_day"] = GameState.day
	for i in def.objectives.size():
		state["progress"][i] = def.objectives[i].count
	_consume_recovered(def)
	_grant(def, state["giver_id"])
	EventBus.quest_completed.emit(quest_id)
	EventBus.notification_posted.emit("의뢰 완료: %s" % def.title, &"info")
	_check_triggers()
	return true


## reason: &"deadline", &"giver_lost", &"raid_lost", &"manual" ...
func fail(quest_id: StringName, reason: StringName = &"manual") -> bool:
	if not is_active(quest_id):
		return false
	var state: Dictionary = _states[quest_id]
	state["status"] = Status.FAILED
	state["end_day"] = GameState.day
	EventBus.quest_failed.emit(quest_id, reason)
	EventBus.notification_posted.emit("의뢰 실패: %s" % get_def(quest_id).title, &"warn")
	return true


## For the quest log (Lane D). One Dictionary per active quest, oldest first:
## {"id", "type": Enums.QuestType, "title", "description", "giver_id",
##  "days_left": int (-1 = no deadline),
##  "objectives": [{"id", "kind": StringName, "text", "progress", "count", "done"}]}
func active_quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for quest_id: StringName in _states:
		if not is_active(quest_id):
			continue
		var def := get_def(quest_id)
		if def == null:
			continue
		var state: Dictionary = _states[quest_id]
		var objectives: Array[Dictionary] = []
		for i in def.objectives.size():
			var o: QuestObjective = def.objectives[i]
			var p := int(state["progress"][i])
			objectives.append({"id": o.id, "kind": QuestObjective.KIND_NAMES[o.kind], "text": o.text,
				"progress": p, "count": o.count, "done": p >= o.count})
		out.append({"id": quest_id, "type": def.type, "title": def.title, "description": def.description,
			"giver_id": state["giver_id"], "days_left": days_left(quest_id), "objectives": objectives})
	return out


## Days left before a deadline fails the quest (0 = today is the last day), -1 = no deadline.
func days_left(quest_id: StringName) -> int:
	var def := get_def(quest_id)
	if def == null or not is_active(quest_id) or not def.fail_condition.has("days"):
		return -1
	var last_day := int(_states[quest_id]["start_day"]) + int(def.fail_condition["days"]) - 1
	return maxi(last_day - GameState.day, 0)


## Lane B: unfinished goals of active quests inside `region_id`, for placing pickups / spots.
## [{"quest_id", "objective_id", "kind": &"visit"|&"recover"|&"rescue", "region_id", "marker",
##   "target_id", "count", "remaining", "text"}]
func active_field_objectives(region_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for quest_id: StringName in _states:
		if not is_active(quest_id):
			continue
		var def := get_def(quest_id)
		if def == null:
			continue
		for i in def.objectives.size():
			var o: QuestObjective = def.objectives[i]
			var p := int(_states[quest_id]["progress"][i])
			if not o.is_field() or o.region_id != region_id or p >= o.count:
				continue
			out.append({"quest_id": quest_id, "objective_id": o.id, "kind": QuestObjective.KIND_NAMES[o.kind],
				"region_id": o.region_id, "marker": o.marker, "target_id": o.target_id, "count": o.count,
				"remaining": o.count - p, "text": o.text})
	return out


# --- Signal reactions ---

func _on_day_started(day: int) -> void:
	# Nothing moves on the title screen (tests and menus emit day_started without a running game).
	if GameState.flow_state == Enums.FlowState.TITLE:
		return
	for quest_id: StringName in _states.keys():
		if not is_active(quest_id):
			continue
		var def := get_def(quest_id)
		var start_day := int(_states[quest_id]["start_day"])
		if def.fail_condition.has("days") and day >= start_day + int(def.fail_condition["days"]):
			fail(quest_id, &"deadline")
			continue
		# A defended day that ended without a raid counts as held.
		for i in def.objectives.size():
			var o: QuestObjective = def.objectives[i]
			if o.kind == QuestObjective.Kind.DEFEND and day > start_day + o.day_offset:
				_add_progress(quest_id, i, o.count)
	_check_triggers()


func _on_sortie_started(loadout: Dictionary) -> void:
	_sortie = {"region_id": StringName(loadout.get("region_id", &"")),
		"companions": Array(loadout.get("companions", [])).map(func(c): return StringName(c))}


func _on_sortie_ended(result: Dictionary) -> void:
	var region := StringName(result.get("region_id", _sortie.get("region_id", &"")))
	var extracted := bool(result.get("extracted", false))
	var stranded: Array = Array(result.get("stranded", [])).map(
		func(s): return StringName(s.get("resident_id", &"")) if s is Dictionary else StringName(s))
	var brought := _loot_counts(result.get("loot", {}))
	var companions: Array = _sortie.get("companions", [])
	_sortie = {}
	for entry in _open_objectives():
		var quest_id: StringName = entry[0]
		var i: int = entry[1]
		var o: QuestObjective = entry[2]
		if not _is_open(quest_id, i):
			continue
		if o.kind == QuestObjective.Kind.VISIT:
			if not extracted or o.region_id != region:
				continue
			if o.companion_id != &"":
				var who := _companion_of(quest_id, o)
				if who not in companions or who in stranded:
					continue
			_add_progress(quest_id, i, o.count)
		elif o.kind == QuestObjective.Kind.RECOVER:
			if (o.region_id == &"" or o.region_id == region) and int(brought.get(o.target_id, 0)) > 0:
				_add_progress(quest_id, i, int(brought[o.target_id]))


func _on_rescue_completed(rescued: Dictionary) -> void:
	var region := StringName(_sortie.get("region_id", &""))
	var rescued_id := StringName(rescued.get("id", &""))
	for entry in _open_objectives():
		var o: QuestObjective = entry[2]
		if o.kind != QuestObjective.Kind.RESCUE or not _is_open(entry[0], entry[1]):
			continue
		if o.region_id != &"" and o.region_id != region:
			continue
		if o.target_id != &"" and o.target_id != rescued_id:
			continue
		_add_progress(entry[0], entry[1], 1)


func _on_building_completed(building_uid: StringName) -> void:
	var def_id := StringName(Colony.get_building(building_uid).get("def_id", &""))
	if def_id == &"":
		return
	for entry in _open_objectives():
		var o: QuestObjective = entry[2]
		if o.kind == QuestObjective.Kind.BUILD and o.target_id == def_id and _is_open(entry[0], entry[1]):
			_add_progress(entry[0], entry[1], 1)


## result: Colony.resolve_raid() Dictionary {"outcome": Enums.RaidOutcome, ...}.
func _on_raid_resolved(result: Dictionary) -> void:
	var lost := int(result.get("outcome", Enums.RaidOutcome.WIN)) == Enums.RaidOutcome.LOSS
	for entry in _open_objectives():
		var quest_id: StringName = entry[0]
		var o: QuestObjective = entry[2]
		if o.kind != QuestObjective.Kind.DEFEND or not _is_open(quest_id, entry[1]):
			continue
		if GameState.day != int(_states[quest_id]["start_day"]) + o.day_offset:
			continue
		if lost:
			fail(quest_id, &"raid_lost")
		else:
			_add_progress(quest_id, entry[1], o.count)


func _on_resident_lost(resident_id: StringName, _why: StringName) -> void:
	for quest_id: StringName in _states.keys():
		if not is_active(quest_id) or _states[quest_id]["giver_id"] != resident_id:
			continue
		if bool(get_def(quest_id).fail_condition.get("giver_lost", false)):
			fail(quest_id, &"giver_lost")


# --- Save provider "quests" ---

func save_data() -> Dictionary:
	return {"states": _states.duplicate(true), "sortie": _sortie.duplicate(true)}


func load_data(data: Dictionary) -> void:
	_states = {}
	var states: Dictionary = data.get("states", {})
	for key in states:
		var src: Dictionary = states[key]
		var progress: Array[int] = []
		for p in src.get("progress", []):
			progress.append(int(p))
		var def := get_def(StringName(key))
		if def != null:
			progress.resize(def.objectives.size())  # data may have gained objectives since the save
		_states[StringName(key)] = {
			"status": int(src.get("status", Status.ACTIVE)),
			"start_day": int(src.get("start_day", 1)),
			"end_day": int(src.get("end_day", 0)),
			"giver_id": StringName(src.get("giver_id", &"")),
			"progress": progress,
		}
	_sortie = data.get("sortie", {}).duplicate(true)


# --- Internals ---

func _check_triggers() -> void:
	for quest_id: StringName in defs:
		if not _states.has(quest_id) and _trigger_met(defs[quest_id]):
			start(quest_id)


func _trigger_met(def: QuestDef) -> bool:
	var p := def.trigger_params
	match def.trigger:
		&"day":
			return GameState.day >= int(p.get("day", 1))
		&"quest":
			return is_completed(StringName(p.get("quest", &"")))
		&"flag":
			return GameState.has_flag(StringName(p.get("flag", &"")))
		&"trust":
			var giver := Colony.get_resident(def.giver_id)
			return not giver.is_empty() \
				and int(giver.get("status", Enums.ResidentStatus.ACTIVE)) == Enums.ResidentStatus.ACTIVE \
				and int(giver.get("trust", 0)) >= int(p.get("trust", 40))
	return false


## Snapshot of [quest_id, objective_index, objective] for every unfinished objective of active quests.
## Handlers re-check _is_open() per entry: earlier entries may complete or fail a quest.
func _open_objectives() -> Array:
	var out := []
	for quest_id: StringName in _states:
		var def := get_def(quest_id)
		if def == null:
			continue
		for i in def.objectives.size():
			if _is_open(quest_id, i):
				out.append([quest_id, i, def.objectives[i]])
	return out


func _is_open(quest_id: StringName, index: int) -> bool:
	return is_active(quest_id) and int(_states[quest_id]["progress"][index]) < get_def(quest_id).objectives[index].count


func _add_progress(quest_id: StringName, index: int, amount: int) -> bool:
	var def := get_def(quest_id)
	var progress: Array = _states[quest_id]["progress"]
	var o: QuestObjective = def.objectives[index]
	var next := clampi(int(progress[index]) + amount, 0, o.count)
	if next == int(progress[index]):
		return false
	progress[index] = next
	EventBus.quest_updated.emit(quest_id, o.id, next)
	for i in def.objectives.size():
		if int(progress[i]) < def.objectives[i].count:
			return true
	complete(quest_id)
	return true


func _companion_of(quest_id: StringName, o: QuestObjective) -> StringName:
	return StringName(_states[quest_id]["giver_id"]) if o.companion_id == QuestObjective.GIVER else o.companion_id


## Sortie loot (Bag.unload_to_base result) -> {resource id or item def id: amount that came home}.
func _loot_counts(loot: Dictionary) -> Dictionary:
	var counts := {}
	var resources: Dictionary = loot.get("resources", {})
	for id in resources:
		counts[StringName(id)] = counts.get(StringName(id), 0) + int(resources[id])
	for uid in loot.get("items", []):
		var item := Armory.get_item(StringName(uid))
		if item != null:
			counts[item.def_id] = counts.get(item.def_id, 0) + 1
	return counts


func _consume_recovered(def: QuestDef) -> void:
	for o: QuestObjective in def.objectives:
		if o.kind != QuestObjective.Kind.RECOVER or not o.consume or Economy.get_def(o.target_id) == null:
			continue
		var n := mini(o.count, Economy.get_amount(o.target_id))
		if n > 0:
			Economy.apply({o.target_id: -n})


func _grant(def: QuestDef, giver_id: StringName) -> void:
	var r := def.rewards
	var resources: Dictionary = r.get("resources", {})
	if not resources.is_empty():
		var changes := {}
		for id in resources:
			changes[StringName(id)] = int(resources[id])
		Economy.apply(changes)
	for entry in r.get("items", []):
		Armory.create_item(StringName(entry.get("def_id", &"")), int(entry.get("rarity", -1)))
	for flag in r.get("flags", []):
		GameState.set_flag(StringName(flag), true)
	# Progression (A-11) gives XP for finished personal requests. Looked up by path so this file
	# still loads before that autoload exists.
	var progression := get_node_or_null(^"/root/Progression")
	if def.type == Enums.QuestType.PERSONAL and progression != null and progression.has_method(&"award"):
		progression.call(&"award", &"personal_request")
	var trust := int(r.get("trust", 0))
	if trust != 0 and giver_id != &"" and giver_id != BROADCASTER:
		# TODO(C): Colony.add_trust(resident_id, amount) is requested from Lane C (개인 요청 완료 +20).
		if Colony.has_method(&"add_trust"):
			Colony.call(&"add_trust", giver_id, trust)


func _load_defs() -> void:
	defs.clear()
	for file in ResourceLoader.list_directory(QUESTS_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load(QUESTS_DIR.path_join(file)) as QuestDef
		if def == null or def.id == &"":
			push_error("Quests: %s is not a QuestDef with an id" % file)
			continue
		defs[def.id] = def


# --- Debug console ---

func _register_debug_commands() -> void:
	DebugConsole.register(&"quest", _cmd_quest,
		"quest [list|start <id>|done <id>|fail <id>|step <id> <objective>|field <region>]")


func _cmd_quest(args: PackedStringArray) -> String:
	var verb := args[0] if not args.is_empty() else "list"
	var id := StringName(args[1]) if args.size() > 1 else &""
	match verb:
		"list":
			var lines: Array[String] = []
			for quest_id: StringName in defs:
				var s := get_status(quest_id)
				lines.append("%s  %s" % [quest_id, "-" if s < 0 else Status.keys()[s]])
			return "\n".join(lines)
		"start":
			return "시작" if start(id) else "시작 못 함: %s" % id
		"done":
			return "완료" if complete(id) else "진행 중이 아님: %s" % id
		"fail":
			return "실패 처리" if fail(id) else "진행 중이 아님: %s" % id
		"step":
			return "진행" if args.size() > 2 and advance(id, StringName(args[2])) else "진행 못 함"
		"field":
			return str(active_field_objectives(id))
	return "사용법: quest [list|start <id>|done <id>|fail <id>|step <id> <objective>|field <region>]"
