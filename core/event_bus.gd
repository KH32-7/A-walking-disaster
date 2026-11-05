extends Node
## Autoload `EventBus`. Owner: Lane A.
## The ONLY way lanes talk to each other at runtime besides the public getters
## listed in docs/dev/contracts.md. Emit from the owning lane, listen from anywhere.
## Rule: adding a signal is fine (PR to Lane A); changing or removing one needs
## every listener updated in the same PR.

# --- Day flow (emitted by Lane A: GameState / SceneRouter) ---
signal day_started(day: int)
signal phase_changed(phase: Enums.Phase)
## Fine-grained flow (title, sortie prep, result, day raid, night raid/event ...).
## Lane D opens screens from this. Emitted once per change by GameState.set_flow_state().
signal flow_state_changed(state: Enums.FlowState)
## Today's weather, rolled at the start of each day (GameState.set_weather).
signal weather_changed(weather: Enums.Weather)
## loadout: {"region_id": StringName, "companions": Array[StringName], "gear": Dictionary}
signal sortie_started(loadout: Dictionary)
## result: see docs/dev/contracts.md "출격 결과" (extracted, downed, region_id, point_id, loot, kills,
## kills_by_monster, rescued, rescued_profiles, companions, stranded, duration_sec, down, xp).
signal sortie_ended(result: Dictionary)
## report: Colony.settle_day() result {"changes", "produced", "consumed", "morale", "events"} plus
## "discarded": {res_id: int} (storage-cap overflow, added by SceneRouter after Economy.apply_detailed).
signal evening_settled(report: Dictionary)

# --- Field (emitted by Lane B) ---
signal noise_emitted(position: Vector3, radius: float, source: Node)
signal monster_killed(monster_id: StringName, element: Enums.Element, position: Vector3)
signal player_downed()
## rescued: resident data dictionary created from a rescue template (Lane C turns it into a Resident).
signal rescue_completed(rescued: Dictionary)
signal companion_stranded(resident_id: StringName, region_id: StringName)
signal extraction_completed(point_id: StringName)
signal emergency_return_requested()

# --- Base (emitted by Lane C) ---
signal resident_joined(resident_id: StringName)
signal resident_left(resident_id: StringName, reason: StringName)
signal resident_died(resident_id: StringName, cause: StringName)
signal building_completed(building_uid: StringName)
signal building_damaged(building_uid: StringName)
signal relationship_changed(a: StringName, b: StringName, stage: StringName)
signal night_event_started(event_id: StringName, participants: Array)
## info: the Colony.roll_raid() Dictionary {"raid_id", "time": Enums.RaidTime, "type", "directions",
## "strength", "target", "warning_sec", ...}.
signal raid_warning(info: Dictionary)
signal raid_started(info: Dictionary)
signal raid_resolved(result: Dictionary)

# --- Items / economy (emitted by Lane A: Economy / Armory) ---
signal resources_changed(changes: Dictionary)
signal item_added(item_uid: StringName)
signal item_removed(item_uid: StringName)
signal equipment_changed(owner_id: StringName, slot: Enums.EquipSlot)
## Field bag contents or size changed (Lane A's Bag). Lane D redraws the grid.
signal bag_changed()

# --- Messages (anyone emits, Lane D shows) ---
## severity: &"info", &"warn", &"danger"
signal notification_posted(text: String, severity: StringName)
## Emitted by Lane A's Radio. Lane D renders subtitles + TTS.
signal radio_message(speaker_id: StringName, text: String, priority: int)
signal journal_entry_added(day: int, text: String)

# --- System ---
signal settings_changed(key: StringName)
signal game_saved(slot: int)
signal game_loaded(slot: int)

# --- Progression (emitted by Lane A: Progression) ---
## Player XP gained. reason: the XP action (&"kill_normal", &"rescue", &"extract", &"debug" ...).
signal xp_gained(amount: int, reason: StringName)
## Player reached `level`. Emitted once per level, so a big gain may emit several times.
signal level_up(level: int)
signal perk_chosen(perk_id: StringName)
signal mastery_level_up(combat_class: Enums.CombatClass, level: int)

# --- Quests (emitted by Lane A: Quests) ---
## A quest became active (Quests.get_def(quest_id) has title, type, giver).
signal quest_started(quest_id: StringName)
## One objective moved forward. progress counts up to that objective's count.
signal quest_updated(quest_id: StringName, objective_id: StringName, progress: int)
## Rewards were already granted when this fires.
signal quest_completed(quest_id: StringName)
## reason: &"deadline", &"giver_lost", &"raid_lost", &"manual"
signal quest_failed(quest_id: StringName, reason: StringName)
