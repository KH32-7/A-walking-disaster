extends Node
## Autoload `EventBus`. Owner: Lane A.
## The ONLY way lanes talk to each other at runtime besides the public getters
## listed in docs/dev/contracts.md. Emit from the owning lane, listen from anywhere.
## Rule: adding a signal is fine (PR to Lane A); changing or removing one needs
## every listener updated in the same PR.

# --- Day flow (emitted by Lane A: GameState / SceneRouter) ---
signal day_started(day: int)
signal phase_changed(phase: Enums.Phase)
## loadout: {"region_id": StringName, "companions": Array[StringName], "gear": Dictionary}
signal sortie_started(loadout: Dictionary)
## result: {"extracted": bool, "loot": Array, "rescued": Array, "stranded": Array, "xp": int}
signal sortie_ended(result: Dictionary)
## report: {"produced": Dictionary, "consumed": Dictionary, "morale": Dictionary, "events": Array}
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
## info: {"time": Enums.Phase, "direction": StringName, "scale": int, "eta_sec": float}
signal raid_warning(info: Dictionary)
signal raid_started(info: Dictionary)
signal raid_resolved(result: Dictionary)

# --- Items / economy (emitted by Lane A: Economy / Armory) ---
signal resources_changed(changes: Dictionary)
signal item_added(item_uid: StringName)
signal item_removed(item_uid: StringName)
signal equipment_changed(owner_id: StringName, slot: Enums.EquipSlot)

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
