extends RefCounted
## Quests (A-13): data loads and is consistent, every objective kind moves forward, rewards,
## fail conditions, triggers, field objectives for Lane B, save round trip.
## Handlers are called directly (not via EventBus.emit) so SceneRouter, Colony and Radio do not react;
## only building_completed goes through the real signal (Colony emits it). Autosave is off, no files.

const R1 := &"test_region"
const R2 := &"other_region"

var _saved := {}
var _saved_defs: Dictionary
var _saved_autosave: bool
var _completed: Array = []
var _failed: Array = []
var _radio: Array = []


func run() -> bool:
	_saved_autosave = SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	for key in [&"game", &"economy", &"armory", &"colony", &"quests"]:
		_saved[key] = SaveSystem._providers[key].save_data().duplicate(true)
	_saved_defs = Quests.defs
	var on_done := func(id): _completed.append(id)
	var on_fail := func(id, reason): _failed.append([id, reason])
	var on_radio := func(_speaker, text, _priority): _radio.append(text)
	EventBus.quest_completed.connect(on_done)
	EventBus.quest_failed.connect(on_fail)
	EventBus.radio_message.connect(on_radio)

	var ok := _check_data()
	for check in [_check_wiring, _check_visit, _check_recover, _check_rescue, _check_build, _check_defend,
			_check_fail_conditions, _check_triggers, _check_field_objectives, _check_rumor_radio, _check_save]:
		_reset()
		ok = check.call() and ok

	EventBus.quest_completed.disconnect(on_done)
	EventBus.quest_failed.disconnect(on_fail)
	EventBus.radio_message.disconnect(on_radio)
	Quests.defs = _saved_defs
	for key: StringName in _saved:
		SaveSystem._providers[key].load_data(_saved[key])
	SaveSystem.autosave_enabled = _saved_autosave
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


## Fresh game state, only the given test defs loaded, in a running game (not the title screen).
func _reset(test_defs: Array = []) -> void:
	for key: StringName in _saved:
		SaveSystem._providers[key].load_data({})
	GameState.day = 5
	GameState.flow_state = Enums.FlowState.BASE_MORNING
	Quests.defs = {}
	for def: QuestDef in test_defs:
		Quests.defs[def.id] = def
	_completed.clear()
	_failed.clear()
	_radio.clear()


func _objective(kind: QuestObjective.Kind, props: Dictionary = {}) -> QuestObjective:
	var o := QuestObjective.new()
	o.id = StringName(props.get("id", QuestObjective.KIND_NAMES[kind]))
	o.kind = kind
	o.text = "test"
	for key in props:
		o.set(key, props[key])
	return o


func _quest(id: StringName, objectives: Array, props: Dictionary = {}) -> QuestDef:
	var def := QuestDef.new()
	def.id = id
	def.title = String(id)
	for o: QuestObjective in objectives:
		def.objectives.append(o)
	for key in props:
		def.set(key, props[key])
	return def


func _with(defs: Array) -> void:
	_reset(defs)


# --- Checks ---

func _check_data() -> bool:
	var defs := _saved_defs
	var ok := _expect(defs.size() >= 5, "only %d quests in data/quests" % defs.size())
	var types := {}
	for id: StringName in defs:
		var def: QuestDef = defs[id]
		types[def.type] = true
		ok = _expect(not def.objectives.is_empty(), "%s has no objectives" % id) and ok
		ok = _expect(def.title != "" and def.description != "", "%s has no title/description" % id) and ok
		ok = _expect(def.trigger in [&"manual", &"day", &"quest", &"flag", &"trust"], "%s trigger %s" % [id, def.trigger]) and ok
		if def.trigger == &"quest":
			ok = _expect(defs.has(StringName(def.trigger_params.get("quest", &""))), "%s waits for a missing quest" % id) and ok
		if def.type == Enums.QuestType.RUMOR:
			ok = _expect(def.radio_text != "", "rumor %s has no radio_text" % id) and ok
		var seen := {}
		for o: QuestObjective in def.objectives:
			ok = _expect(o.id != &"" and not seen.has(o.id), "%s objective id '%s'" % [id, o.id]) and ok
			seen[o.id] = true
			ok = _expect(o.count >= 1 and o.text != "", "%s/%s count or text" % [id, o.id]) and ok
			match o.kind:
				QuestObjective.Kind.VISIT:
					ok = _expect(o.region_id != &"", "%s/%s visit without region" % [id, o.id]) and ok
				QuestObjective.Kind.RECOVER:
					ok = _expect(Economy.get_def(o.target_id) != null or Armory.get_def(o.target_id) != null,
						"%s/%s recovers unknown '%s'" % [id, o.id, o.target_id]) and ok
				QuestObjective.Kind.BUILD:
					ok = _expect(BaseDB.get_building(o.target_id) != null, "%s/%s builds unknown '%s'" % [id, o.id, o.target_id]) and ok
		for res in def.rewards.get("resources", {}):
			ok = _expect(Economy.get_def(StringName(res)) != null, "%s rewards unknown resource %s" % [id, res]) and ok
	for t in [Enums.QuestType.MAIN, Enums.QuestType.PERSONAL, Enums.QuestType.RUMOR]:
		ok = _expect(types.has(t), "no quest of type %s" % Enums.QuestType.keys()[t]) and ok
	ok = _expect(Radio.triggers.has(Quests.RUMOR_RADIO_TRIGGER), "radio trigger quest_rumor missing") and ok
	# The demo personal request shows its keepsake to Lane B.
	_reset(defs.values())
	Quests.start(&"personal_carpenter_plane")
	var field := Quests.active_field_objectives(&"flooded_mall")
	ok = _expect(field.any(func(f): return f["target_id"] == &"keepsake_plane" and f["marker"] == &"hardware_store"),
		"keepsake not in field objectives: %s" % [field]) and ok
	return ok


func _check_wiring() -> bool:
	var ok := true
	for pair in [[EventBus.day_started, Quests._on_day_started], [EventBus.sortie_started, Quests._on_sortie_started],
			[EventBus.sortie_ended, Quests._on_sortie_ended], [EventBus.rescue_completed, Quests._on_rescue_completed],
			[EventBus.building_completed, Quests._on_building_completed], [EventBus.raid_resolved, Quests._on_raid_resolved],
			[EventBus.resident_left, Quests._on_resident_lost], [EventBus.resident_died, Quests._on_resident_lost]]:
		var sig: Signal = pair[0]
		ok = _expect(sig.is_connected(pair[1]), "Quests not connected to %s" % sig.get_name()) and ok
	return _expect(SaveSystem._providers.get(&"quests") == Quests, "save provider 'quests' missing") and ok


func _sortie(region: StringName, companions: Array, extracted: bool, loot := {}, stranded := []) -> void:
	Quests._on_sortie_started({"region_id": region, "companions": companions, "gear": {}})
	Quests._on_sortie_ended({"extracted": extracted, "region_id": region, "loot": loot, "rescued": [],
		"stranded": stranded, "xp": 0})


func _check_visit() -> bool:
	_with([_quest(&"t_visit", [_objective(QuestObjective.Kind.VISIT, {"region_id": R1})]),
		_quest(&"t_escort", [_objective(QuestObjective.Kind.VISIT, {"region_id": R1, "companion_id": QuestObjective.GIVER})],
			{"type": Enums.QuestType.PERSONAL, "request_type": Enums.RequestType.ESCORT, "giver_id": &"res_a"})])
	Quests.start(&"t_visit")
	Quests.start(&"t_escort")
	_sortie(R2, [], true)
	var ok := _expect(Quests.is_active(&"t_visit"), "other region counted as visit")
	_sortie(R1, [], false)
	ok = _expect(Quests.is_active(&"t_visit"), "visit counted without extracting") and ok
	_sortie(R1, [], true)
	ok = _expect(Quests.is_completed(&"t_visit"), "visit not completed") and ok
	ok = _expect(Quests.is_active(&"t_escort"), "escort done without the giver") and ok
	_sortie(R1, [&"res_a"], true, {}, [{"resident_id": &"res_a", "region_id": R1}])
	ok = _expect(Quests.is_active(&"t_escort"), "escort done with the giver stranded") and ok
	_sortie(R1, [&"res_b", &"res_a"], true)
	return _expect(Quests.is_completed(&"t_escort"), "escort not completed") and ok


func _check_recover() -> bool:
	var keepsake := _objective(QuestObjective.Kind.RECOVER, {"region_id": R1, "target_id": &"keepsake_plane", "consume": true})
	_with([_quest(&"t_keepsake", [keepsake], {"giver_id": &"res_a",
			"rewards": {"resources": {&"wood": 3}, "flags": [&"t_flag"], "items": [{"def_id": &"hammer", "rarity": 1}]}}),
		_quest(&"t_pistol", [_objective(QuestObjective.Kind.RECOVER, {"target_id": &"pistol"})])])
	Quests.start(&"t_keepsake")
	Quests.start(&"t_pistol")
	var added: Array = []
	var on_item := func(uid): added.append(uid)
	EventBus.item_added.connect(on_item)
	var wood := Economy.get_amount(&"wood")

	# Bag.unload_to_base already put the loot in storage before sortie_ended.
	Economy.apply({&"keepsake_plane": 1})
	_sortie(R2, [], true, {"resources": {&"keepsake_plane": 1}, "items": []})
	var ok := _expect(Quests.is_active(&"t_keepsake"), "keepsake from the wrong region counted")
	_sortie(R1, [], false, {"resources": {&"keepsake_plane": 1}, "items": []})  # safe pocket after going down
	ok = _expect(Quests.is_completed(&"t_keepsake"), "keepsake not recovered") and ok
	ok = _expect(Economy.get_amount(&"keepsake_plane") == 0, "keepsake not handed over (consume)") and ok
	ok = _expect(Economy.get_amount(&"wood") == wood + 3, "resource reward") and ok
	ok = _expect(GameState.has_flag(&"t_flag"), "flag reward") and ok
	ok = _expect(added.size() == 1 and Armory.get_item(added[0]).def_id == &"hammer" \
		and Armory.get_item(added[0]).rarity == 1, "item reward %s" % [added]) and ok

	var gun := Armory.create_item(&"pistol")
	_sortie(R2, [], true, {"resources": {}, "items": [gun]})
	ok = _expect(Quests.is_completed(&"t_pistol"), "item def recovery") and ok
	EventBus.item_added.disconnect(on_item)
	return ok


func _check_rescue() -> bool:
	_with([_quest(&"t_rescue", [_objective(QuestObjective.Kind.RESCUE, {"region_id": R1, "count": 2})]),
		_quest(&"t_named", [_objective(QuestObjective.Kind.RESCUE, {"target_id": &"pool_lin"})])])
	Quests.start(&"t_rescue")
	Quests.start(&"t_named")
	Quests._on_sortie_started({"region_id": R2, "companions": []})
	Quests._on_rescue_completed({"id": &"someone"})
	var ok := _expect(Quests.active_quests()[0]["objectives"][0]["progress"] == 0, "rescue in another region counted")
	Quests._on_sortie_started({"region_id": R1, "companions": []})
	Quests._on_rescue_completed({"id": &"someone"})
	ok = _expect(Quests.is_active(&"t_rescue") and Quests.is_active(&"t_named"), "named rescue matched a stranger") and ok
	Quests._on_rescue_completed({"id": &"pool_lin"})
	return _expect(Quests.is_completed(&"t_rescue") and Quests.is_completed(&"t_named"), "rescues not completed") and ok


func _check_build() -> bool:
	_with([_quest(&"t_build", [_objective(QuestObjective.Kind.BUILD, {"target_id": &"bed"})])])
	Quests.start(&"t_build")
	var other := Colony.place_building(&"bonfire", Vector2i.ZERO, 0, &"", false)
	Colony.complete_building(other)
	var ok := _expect(Quests.is_active(&"t_build"), "another building counted")
	var uid := Colony.place_building(&"bed", Vector2i(2, 0), 0, &"", false)
	ok = _expect(uid != &"", "could not place a bed") and ok
	Colony.complete_building(uid)  # real building_completed signal
	return _expect(Quests.is_completed(&"t_build"), "bed not counted") and ok


func _check_defend() -> bool:
	var defend := func(id): return _quest(id, [_objective(QuestObjective.Kind.DEFEND, {"day_offset": 1})])
	# Lost raid on the defended day fails the quest; a raid on another day does nothing.
	_with([defend.call(&"t_lose")])
	Quests.start(&"t_lose")  # day 5, defend day 6
	Quests._on_raid_resolved({"outcome": Enums.RaidOutcome.LOSS})
	var ok := _expect(Quests.is_active(&"t_lose"), "raid on the wrong day counted")
	GameState.day = 6
	Quests._on_day_started(6)
	ok = _expect(Quests.is_active(&"t_lose"), "defend day completed before it ended") and ok
	Quests._on_raid_resolved({"outcome": Enums.RaidOutcome.LOSS})
	ok = _expect(_failed.has([&"t_lose", &"raid_lost"]), "lost raid did not fail: %s" % [_failed]) and ok
	# Any other outcome holds the day.
	_with([defend.call(&"t_win")])
	Quests.start(&"t_win")
	GameState.day = 6
	Quests._on_raid_resolved({"outcome": Enums.RaidOutcome.NARROW})
	ok = _expect(Quests.is_completed(&"t_win"), "won raid did not complete") and ok
	# No raid at all: held once the next morning comes.
	_with([defend.call(&"t_quiet")])
	Quests.start(&"t_quiet")
	GameState.day = 6
	Quests._on_day_started(6)
	ok = _expect(Quests.is_active(&"t_quiet"), "quiet day held too early") and ok
	GameState.day = 7
	Quests._on_day_started(7)
	return _expect(Quests.is_completed(&"t_quiet"), "day without a raid not held") and ok


func _check_fail_conditions() -> bool:
	_with([_quest(&"t_deadline", [_objective(QuestObjective.Kind.VISIT, {"region_id": R1})], {"fail_condition": {"days": 2}}),
		_quest(&"t_giver", [_objective(QuestObjective.Kind.VISIT, {"region_id": R1})],
			{"giver_id": &"res_a", "fail_condition": {"giver_lost": true}}),
		_quest(&"t_keep", [_objective(QuestObjective.Kind.VISIT, {"region_id": R1})], {"giver_id": &"res_a"})])
	for id in [&"t_deadline", &"t_giver", &"t_keep"]:
		Quests.start(id)
	var ok := _expect(Quests.days_left(&"t_deadline") == 1 and Quests.days_left(&"t_keep") == -1, "days_left")
	GameState.day = 6
	Quests._on_day_started(6)
	ok = _expect(Quests.is_active(&"t_deadline") and Quests.days_left(&"t_deadline") == 0, "deadline failed a day early") and ok
	GameState.day = 7
	Quests._on_day_started(7)
	ok = _expect(_failed.has([&"t_deadline", &"deadline"]), "deadline did not fail") and ok
	Quests._on_resident_lost(&"res_b", &"left")
	ok = _expect(Quests.is_active(&"t_giver"), "another resident leaving failed it") and ok
	Quests._on_resident_lost(&"res_a", &"died")
	ok = _expect(_failed.has([&"t_giver", &"giver_lost"]), "giver lost did not fail") and ok
	ok = _expect(Quests.is_active(&"t_keep"), "quest without giver_lost failed") and ok
	ok = _expect(not Quests.fail(&"t_giver") and not Quests.complete(&"t_giver") and not Quests.start(&"t_giver"),
		"finished quest changed again") and ok
	return ok


func _check_triggers() -> bool:
	_with([_quest(&"t_day", [_objective(QuestObjective.Kind.BUILD, {"target_id": &"bed"})], {"trigger": &"day", "trigger_params": {"day": 6}}),
		_quest(&"t_first", [], {"trigger": &"manual"}),
		_quest(&"t_chain", [_objective(QuestObjective.Kind.BUILD, {"target_id": &"bed"})], {"trigger": &"quest", "trigger_params": {"quest": &"t_first"}}),
		_quest(&"t_flagged", [_objective(QuestObjective.Kind.BUILD, {"target_id": &"bed"})], {"trigger": &"flag", "trigger_params": {"flag": &"t_open"}}),
		_quest(&"t_trust", [_objective(QuestObjective.Kind.BUILD, {"target_id": &"bed"})],
			{"type": Enums.QuestType.PERSONAL, "trigger": &"trust", "trigger_params": {"trust": 40}})])
	var low := Colony.add_resident({"name": "시험", "trust": 10})
	(Quests.defs[&"t_trust"] as QuestDef).giver_id = low

	GameState.flow_state = Enums.FlowState.TITLE
	GameState.day = 6
	Quests._on_day_started(6)
	var ok := _expect(Quests.get_status(&"t_day") == -1, "quest started on the title screen")
	GameState.flow_state = Enums.FlowState.BASE_MORNING
	Quests._on_day_started(6)
	ok = _expect(Quests.is_active(&"t_day"), "day trigger") and ok
	ok = _expect(Quests.get_status(&"t_first") == -1 and Quests.get_status(&"t_trust") == -1, "manual/trust started early") and ok
	ok = _expect(Quests.start(&"t_first") and Quests.is_completed(&"t_first"), "quest without objectives completes on start") and ok
	ok = _expect(Quests.is_active(&"t_chain"), "quest trigger did not chain") and ok
	GameState.set_flag(&"t_open")
	Quests._on_day_started(6)
	ok = _expect(Quests.is_active(&"t_flagged"), "flag trigger") and ok
	ok = _expect(Quests.get_status(&"t_trust") == -1, "trust 10 started a trust-40 request") and ok
	var trusted := Colony.add_resident({"name": "시험2", "trust": 45})
	(Quests.defs[&"t_trust"] as QuestDef).giver_id = trusted
	Quests._on_day_started(6)
	ok = _expect(Quests.is_active(&"t_trust") and Quests.active_quests().any(
		func(q): return q["id"] == &"t_trust" and q["giver_id"] == trusted), "trust trigger") and ok
	return ok


func _check_field_objectives() -> bool:
	_with([_quest(&"t_field", [
			_objective(QuestObjective.Kind.VISIT, {"id": &"go", "region_id": R1}),
			_objective(QuestObjective.Kind.RECOVER, {"id": &"photo", "region_id": R1, "target_id": &"keepsake_plane", "marker": &"desk"}),
			_objective(QuestObjective.Kind.RECOVER, {"id": &"wood", "target_id": &"wood", "count": 5}),
			_objective(QuestObjective.Kind.BUILD, {"id": &"bed", "target_id": &"bed"})]),
		_quest(&"t_waiting", [_objective(QuestObjective.Kind.VISIT, {"region_id": R1})])])
	Quests.start(&"t_field")
	var field := Quests.active_field_objectives(R1)
	var ids := field.map(func(f): return f["objective_id"])
	var ok := _expect(ids == [&"go", &"photo"], "field objectives %s" % [ids])
	var photo: Dictionary = field[1] if field.size() > 1 else {}
	ok = _expect(photo.get("kind") == &"recover" and photo.get("marker") == &"desk" and photo.get("remaining") == 1 \
		and photo.get("quest_id") == &"t_field", "field objective fields %s" % [photo]) and ok
	ok = _expect(Quests.active_field_objectives(R2).is_empty(), "objectives leaked into another region") and ok
	ok = _expect(Quests.advance(&"t_field", &"photo"), "advance()") and ok
	ids = Quests.active_field_objectives(R1).map(func(f): return f["objective_id"])
	ok = _expect(ids == [&"go"], "done objective still listed: %s" % [ids]) and ok
	var entries := Quests.active_quests()
	return _expect(entries.size() == 1 and entries[0]["objectives"].size() == 4 and entries[0]["objectives"][1]["done"], "active_quests %s" % [entries]) and ok


func _check_rumor_radio() -> bool:
	_with([_quest(&"t_rumor", [_objective(QuestObjective.Kind.RESCUE, {"region_id": R1})],
		{"type": Enums.QuestType.RUMOR, "radio_text": "시험 소문입니다.", "trigger": &"day", "trigger_params": {"day": 1}})])
	Quests._on_day_started(5)
	return _expect(Quests.is_active(&"t_rumor"), "rumor did not start in the morning") \
		and _expect(_radio.any(func(t): return t.contains("시험 소문입니다.")), "rumor not broadcast: %s" % [_radio])


func _check_save() -> bool:
	_with([_quest(&"t_a", [_objective(QuestObjective.Kind.RESCUE, {"region_id": R1, "count": 3})], {"giver_id": &"res_a"}),
		_quest(&"t_b", [_objective(QuestObjective.Kind.VISIT, {"region_id": R1})]),
		_quest(&"t_c", [_objective(QuestObjective.Kind.VISIT, {"region_id": R1})])])
	Quests.start(&"t_a")
	Quests.start(&"t_b")
	Quests.start(&"t_c")
	Quests.advance(&"t_a", &"rescue")
	Quests.complete(&"t_b")
	Quests.fail(&"t_c")
	Quests._on_sortie_started({"region_id": R1, "companions": [&"res_a"]})
	# Same path as SaveSystem: Godot-typed JSON text and back.
	var text := JSON.stringify(JSON.from_native(Quests.save_data()))
	var restored: Dictionary = JSON.to_native(JSON.parse_string(text))
	Quests.load_data({})
	var ok := _expect(Quests.get_status(&"t_a") == -1 and Quests.active_quests().is_empty(), "load_data({}) did not reset")
	Quests.load_data(restored)
	ok = _expect(Quests.is_active(&"t_a") and Quests.is_completed(&"t_b") and Quests.get_status(&"t_c") == Quests.Status.FAILED,
		"statuses after load") and ok
	var entries := Quests.active_quests()
	ok = _expect(entries.size() == 1 and entries[0]["objectives"][0]["progress"] == 1 and entries[0]["giver_id"] == &"res_a",
		"progress after load %s" % [entries]) and ok
	# The sortie in progress survives a suspend save: a rescue still counts for its region.
	Quests._on_rescue_completed({"id": &"x"})
	return _expect(Quests.active_quests()[0]["objectives"][0]["progress"] == 2, "sortie region lost on load") and ok
