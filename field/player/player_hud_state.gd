class_name PlayerHudState
extends RefCounted
## Builds Player.hud_state() for the field HUD (D-04, issue #28). The HUD only draws what
## this returns; missing keys fall back to HUD defaults. Filled now: hp, stamina, weapons,
## heading and compass (extraction points), hold bar, interact prompt, dusk_left_sec (B-21,
## left out when night is off so the demo has no dusk timer).
## skills (B-13: [{key, left, max}] of enabled class skills), mana (B-15: weapon in hand, 0..1).
## boss (B-19, only while a boss is fighting near the player): {name, hp, hp_max, phase, phase_count}.
## Later: armor (B-06 armor), consumables (B-16),
## companions (B-17), minimap. objectives: Quests.active_field_objectives of this region.

const PROMPT_KEY := "F"
const EXTRACT_HOLD_LABEL := "탈출 대기 중"
const WEAPON_SLOTS := [Enums.EquipSlot.MAIN, Enums.EquipSlot.SUB]


static func build(player: Player) -> Dictionary:
	var state := {
		"hp": player.health,
		"hp_max": player.stats.max_health,
		"stamina": player.stamina / player.stats.max_stamina,
		"level": Progression.level,
		"xp": float(Progression.xp) / maxf(1.0, float(Progression.xp_needed())),
	}
	_add_weapons(player, state)
	state["skills"] = ClassSkills.hud_list(player)
	_add_heading(player, state)
	var extraction := player.get_tree().get_first_node_in_group(ExtractionManager.GROUP) as ExtractionManager
	_add_compass(player, extraction, state)
	state["hold"] = _hold(player, extraction)
	state["prompt"] = _prompt(player, state["hold"])
	# No sortie clock outside the field (B-23 base defense).
	if player.field_rules and FieldState.night_enabled():
		state["dusk_left_sec"] = FieldState.dusk_left_sec()
	state["companions"] = FieldCompanion.hud_list(player.get_tree())
	state["consumables"] = player.consumables.hud_slots()
	state["mana"] = MagicWeapon.hud_mana(player)
	state["objectives"] = _objectives()
	var boss := BossMonster.hud_for(player)
	if not boss.is_empty():
		state["boss"] = boss
	return state


## Field quest goals of this region (A-13 Quests): [{text, progress, main}] for the top-right list.
static func _objectives() -> Array:
	var out: Array = []
	for o: Dictionary in Quests.active_field_objectives(FieldState.region_id):
		var def := Quests.get_def(StringName(o.quest_id))
		var done := int(o["count"]) - int(o["remaining"])
		out.append({"text": String(o["text"]), "progress": "%d/%d" % [done, int(o["count"])],
			"main": def != null and def.type == Enums.QuestType.MAIN})
	return out


static func _add_weapons(player: Player, state: Dictionary) -> void:
	var holder := player.get_node_or_null(^"Weapons") as WeaponHolder
	var weapons: Array = []
	var index := 0
	for slot: Enums.EquipSlot in WEAPON_SLOTS:
		var uid := Armory.get_equipped(Armory.PLAYER_ID, slot)
		if uid == &"":
			continue
		var stats := Armory.get_item_stats(uid)
		var def := Armory.get_def(stats.get("def_id", &""))
		var entry := {
			"name": def.name if def else String(stats.get("def_id", "")),
			"melee": int(stats.get("combat_class", -1)) != Enums.CombatClass.GUN,
			"rarity": int(stats.get("rarity", 0)),
		}
		if holder and holder.active_slot == slot:
			index = weapons.size()
			if not entry["melee"]:
				entry["ammo"] = holder.ammo_in_magazine()
				entry["reserve"] = holder.ammo_reserve()
		weapons.append(entry)
	state["weapons"] = weapons
	state["weapon_index"] = index
	state["reloading"] = holder.is_reloading if holder else false


## Compass heading = where "up" on screen points, as a bearing (0 = world -Z, clockwise).
static func _add_heading(player: Player, state: Dictionary) -> void:
	var camera := player.get_viewport().get_camera_3d()
	if camera:
		state["heading_deg"] = _bearing(-camera.global_basis.z)


static func _add_compass(player: Player, extraction: ExtractionManager, state: Dictionary) -> void:
	if extraction == null:
		return
	var markers: Array = []
	var emergency := player.get_tree().get_first_node_in_group(EmergencyReturn.GROUP) as EmergencyReturn
	var emergency_id := emergency.target_point_id() if emergency else &""
	for point in extraction.active_points():
		var to_point := point.global_position - player.global_position
		var marker := {"bearing": _bearing(to_point), "kind": &"extract",
			"dist": Vector2(to_point.x, to_point.z).length()}
		if point.id == emergency_id:
			marker["emergency"] = true  # B-22: the emergency return target
		markers.append(marker)
	state["compass_markers"] = markers


static func _hold(player: Player, extraction: ExtractionManager) -> Dictionary:
	var item_hold := player.consumables.hold_state()
	if not item_hold.is_empty():
		return item_hold
	var using := player.interacting()
	if using and using.has_method(&"hold_state"):
		var hold: Dictionary = using.hold_state()
		if not hold.is_empty():
			# Shown as a ring around the [F] chip on the thing itself (WorldPrompts), not the head bar.
			hold = hold.duplicate()
			hold["at_target"] = true
			return hold
	if extraction and extraction.current_point_id() != &"":
		return {"label": EXTRACT_HOLD_LABEL, "progress": extraction.progress()}
	return {}


static func _prompt(player: Player, hold: Dictionary) -> Dictionary:
	if not hold.is_empty():
		return {}
	var target := player.interact_target()
	if target == null or not target.has_method(&"interact_label"):
		return {}
	var label: String = target.interact_label()
	return {} if label == "" else {"key": PROMPT_KEY, "label": label}


static func _bearing(direction: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(direction.x, -direction.z)), 360.0)
