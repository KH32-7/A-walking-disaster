extends Node3D
## Lane B all-in-one test on the real map (dev only). Run alone (F6).
## The flooded mall as a sortie: player, camera, monsters, loot, rescues, extraction, lost gear,
## D's field HUD (UI.show_field_hud) fed by Player.hud_state(), temporary combat visuals.
## Without SceneRouter, so this scene fakes the sortie start (phase, sortie_started, loadout).
##
## Debug keys (raw keycodes, test only):
##   T   take every identified slot of the container you opened (stand-in for D-08)
##   K   kill monsters within KILL_RADIUS
##   F8  teleport to the next rescue target     F9  teleport to the next active extraction point
##   F1..F6 weapons, F7 ammo (WeaponDebug)   Q / E class skills (B-13, game input)
##   F10 sortie clock +3 min (dusk at 12, night at 15 if night is on)
##   F11 fake day raid warning (B-22 emergency return), then Y go back / N stay
##   F12 spawn the next roster monster in front of you, Shift+F12 as an elite
## Console (`): `card <0-2>` answers the nearest rescue target's picture card round.

const REGION_ID := &"flooded_mall"
const LOADOUT := {Enums.EquipSlot.MAIN: &"pistol", Enums.EquipSlot.SUB: &"dagger"}
## B-16: consumables handed out at the start (test only), id -> count.
const TEST_CONSUMABLES := {&"first_aid_kit": 2, &"bandage": 2, &"noise_lure": 3, &"painkiller": 1,
		&"flashbang": 2, &"grenade": 2}
const KILL_RADIUS := 4.0
const KILL_DAMAGE := 9999.0
const TELEPORT_OFFSET := Vector3(0.0, 0.2, 2.0)
const CLOCK_SKIP_SEC := 180.0
const SPAWN_AHEAD := 6.0
const MONSTERS_DIR := "res://data/monsters"
const ROUTE_COLOR := Color(0.3, 0.9, 1.0, 0.9)

@onready var _mall: Node3D = $FloodedMall
@onready var _label: Label = $DebugLayer/InfoLabel

var _player: Player
var _container: LootContainer
var _rescue_index := -1
var _extract_index := -1
var _events: PackedStringArray = []
var _roster: Array[MonsterDef] = []
var _roster_index := -1
var _return_offer := false
var _route_mesh := ImmediateMesh.new()


func _enter_tree() -> void:
	# Before the mall's spawners run: same order SceneRouter.go_to_field uses.
	GameState.set_phase(Enums.Phase.SORTIE)
	EventBus.sortie_started.emit({"region_id": REGION_ID, "seed": randi()})


func _ready() -> void:
	_player = _mall.get(&"player") as Player
	for slot: Enums.EquipSlot in LOADOUT:
		if Armory.get_equipped(Armory.PLAYER_ID, slot) == &"":
			Armory.equip(Armory.PLAYER_ID, slot, Armory.create_item(LOADOUT[slot], Enums.Rarity.COMMON))
	for id: StringName in TEST_CONSUMABLES:
		Bag.try_add(id, TEST_CONSUMABLES[id])
	UI.show_field_hud(true)
	# Deferred: spawners may place their nodes during their own deferred calls.
	_watch_containers.call_deferred()
	EventBus.player_downed.connect(func() -> void: _log("player downed"))
	EventBus.monster_killed.connect(func(id: StringName, _e: Enums.Element, _p: Vector3) -> void:
		_log("killed %s" % id))
	EventBus.rescue_completed.connect(func(r: Dictionary) -> void: _log("rescued %s" % r.get("name", "?")))
	EventBus.extraction_completed.connect(func(id: StringName) -> void: _log("extracted at %s" % id))
	DebugConsole.register(&"card", _cmd_card, "card <0-2> - answer the nearest rescue card round")
	FieldState.dusk_started.connect(func() -> void: _log("dusk"))
	FieldState.night_started.connect(func() -> void: _log("night"))
	_roster = _load_roster()
	_setup_route_line()
	_watch_emergency.call_deferred()


func _exit_tree() -> void:
	UI.show_field_hud(false)


func _process(_delta: float) -> void:
	if _player == null:
		return
	var extraction := _extraction()
	var result := FieldState.last_sortie_result()
	_label.text = "\n".join([
		"[B flooded mall test]  seed %d" % FieldState.sortie_seed,
		"Extract: %s  now %s %.0f%%" % [
			", ".join(PackedStringArray(extraction.active_point_ids())) if extraction else "-",
			extraction.current_point_id() if extraction else "-",
			(extraction.progress() if extraction else 0.0) * 100.0],
		"Rescue: %s" % _rescue_text(),
		"Clock: %s  %s" % [_clock_text(), _night_text()],
		"Player status: %s" % _status_text(_player.status),
		"Class: %s" % _class_text(),
		"Nearest monster: %s" % _nearest_monster_text(),
		"Emergency: %s" % _emergency_text(),
		"Container: %s" % _container_text(),
		"Result: %s" % (_result_text(result) if not result.is_empty() else "-"),
		"Events: %s" % " / ".join(_events),
		"T take all, K kill near, F8 rescue, F9 extract, F1-F7 weapons/ammo, ` card <n>",
		"F10 +3 min, F11 raid warning (Y/N), F12 spawn monster (Shift elite)",
	])
	_draw_route()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _player == null:
		return
	match key.keycode:
		KEY_T:
			if _container:
				for i in _container.get_slots().size():
					_container.take(i)
		KEY_K:
			for node in get_tree().get_nodes_in_group(Monster.GROUP):
				var monster := node as Monster
				if monster.global_position.distance_to(_player.global_position) <= KILL_RADIUS:
					monster.take_damage(KILL_DAMAGE, {"source": _player})
		KEY_F8:
			var targets := _rescue_targets()
			if not targets.is_empty():
				_rescue_index = (_rescue_index + 1) % targets.size()
				_teleport(targets[_rescue_index].global_position)
		KEY_F9:
			var extraction := _extraction()
			var points: Array = extraction.active_points() if extraction else []
			if not points.is_empty():
				_extract_index = (_extract_index + 1) % points.size()
				_teleport(points[_extract_index].global_position)
		KEY_F10:
			FieldState.advance_sortie_time(CLOCK_SKIP_SEC)
		KEY_F11:
			EventBus.raid_warning.emit({"time": Enums.RaidTime.DAY, "source": &"b_flooded_mall_test"})
		KEY_Y, KEY_N:
			var emergency := _emergency()
			if emergency and _return_offer:
				_return_offer = false
				emergency.answer(key.keycode == KEY_Y)
		KEY_F12:
			_spawn_roster_monster(key.shift_pressed)


func _watch_containers() -> void:
	for node in _mall.find_children("*", "StaticBody3D", true, false):
		var container := node as LootContainer
		if container and not container.open_started.is_connected(_on_open_started):
			container.open_started.connect(_on_open_started.bind(container))


func _on_open_started(_duration: float, _forcing: bool, container: LootContainer) -> void:
	_container = container


func _teleport(point: Vector3) -> void:
	_player.global_position = point + TELEPORT_OFFSET
	_player.velocity = Vector3.ZERO


func _cmd_card(args: PackedStringArray) -> String:
	var target := _nearest_rescue()
	if target == null or target.current_card_round().is_empty():
		return "no card round nearby"
	return "correct" if target.answer_card(int(args[0]) if not args.is_empty() else 0) else "wrong"


func _extraction() -> ExtractionManager:
	return get_tree().get_first_node_in_group(ExtractionManager.GROUP) as ExtractionManager


func _rescue_targets() -> Array[RescueTarget]:
	var manager := get_tree().get_first_node_in_group(RescueManager.GROUP) as RescueManager
	var out: Array[RescueTarget] = []
	if manager:
		for t in manager.targets:
			if is_instance_valid(t):
				out.append(t)
	return out


func _nearest_rescue() -> RescueTarget:
	var best: RescueTarget = null
	for t in _rescue_targets():
		if best == null or t.global_position.distance_to(_player.global_position) \
				< best.global_position.distance_to(_player.global_position):
			best = t
	return best


func _rescue_text() -> String:
	var parts: PackedStringArray = []
	for t in _rescue_targets():
		parts.append("%s %s %.0fm" % [t.display_name, RescueTarget.State.keys()[t.state],
			t.global_position.distance_to(_player.global_position)])
	return ", ".join(parts) if not parts.is_empty() else "none"


func _nearest_monster_text() -> String:
	var best: Monster = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(Monster.GROUP):
		var monster := node as Monster
		var dist := monster.global_position.distance_to(_player.global_position)
		if dist < best_dist and not monster.is_dead():
			best = monster
			best_dist = dist
	if best == null:
		return "none"
	return "%s%s %.0fm %s, status %s" % [best.def.id, " ELITE" if best.elite else "", best_dist,
		Enums.AIState.keys()[best.state], _status_text(best.status)]


func _container_text() -> String:
	if _container == null or not is_instance_valid(_container):
		return "none"
	var slots: PackedStringArray = []
	for slot in _container.get_slots():
		if slot.count == 0 and slot.identified:
			continue
		slots.append("%s x%d" % [slot.item_id, slot.count] if slot.identified else "?")
	return "%s [%s]" % [LootContainer.State.keys()[_container.state], ", ".join(slots)]


func _result_text(result: Dictionary) -> String:
	return "extracted %s at %s, kills %d, rescued %s, stranded %s" % [
		result.get("extracted"), result.get("point_id"), result.get("kills", 0),
		result.get("rescued", []), result.get("stranded", [])]


func _log(text: String) -> void:
	_events.append(text)
	if _events.size() > 3:
		_events.remove_at(0)


# --- M2 test helpers -------------------------------------------------------------

func _load_roster() -> Array[MonsterDef]:
	var out: Array[MonsterDef] = []
	for file in DirAccess.get_files_at(MONSTERS_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load("%s/%s" % [MONSTERS_DIR, file]) as MonsterDef
		if def and def.tier == Enums.MonsterTier.NORMAL:
			out.append(def)
	return out


func _spawn_roster_monster(as_elite: bool) -> void:
	if _roster.is_empty():
		return
	_roster_index = (_roster_index + 1) % _roster.size()
	var def := _roster[_roster_index]
	var scene: PackedScene = def.scene if def.scene else load("res://field/monsters/monster_base.tscn")
	var monster := scene.instantiate() as Monster
	monster.def = def
	monster.position = _player.global_position + _player.facing() * SPAWN_AHEAD
	_mall.add_child(monster)
	if as_elite:
		monster.make_elite()
	_log("spawned %s%s" % [def.id, " (elite)" if as_elite else ""])


func _emergency() -> EmergencyReturn:
	return get_tree().get_first_node_in_group(EmergencyReturn.GROUP) as EmergencyReturn


func _watch_emergency() -> void:
	var emergency := _emergency()
	if emergency == null:
		return
	emergency.return_offered.connect(func(_raid: Dictionary) -> void:
		_return_offer = true
		_log("raid warning: Y go back / N stay"))
	emergency.return_started.connect(func(id: StringName) -> void: _log("going back to %s" % id))


func _emergency_text() -> String:
	var emergency := _emergency()
	if emergency == null:
		return "-"
	if _return_offer:
		return "offered (Y / N)"
	var target := emergency.target_point_id()
	return "returning to %s, %d route points" % [target, emergency.route().size()] if target != &"" else "-"


func _setup_route_line() -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = _route_mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = ROUTE_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inst.material_override = mat
	add_child(inst)


## Test-only stand-in for D's route line: the emergency return path on the ground.
func _draw_route() -> void:
	_route_mesh.clear_surfaces()
	var emergency := _emergency()
	var route := emergency.route() if emergency else PackedVector3Array()
	if route.size() < 2:
		return
	_route_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in route:
		_route_mesh.surface_add_vertex(p + Vector3.UP * 0.1)
	_route_mesh.surface_end()


func _clock_text() -> String:
	var t := int(FieldState.sortie_time())
	return "%02d:%02d" % [t / 60, t % 60]


func _night_text() -> String:
	if not FieldState.night_enabled():
		return "(night off)"
	if FieldState.is_night():
		return "NIGHT"
	if FieldState.is_dusk():
		return "DUSK"
	return "dusk in %ds" % int(FieldState.dusk_left_sec())


## B-13: class, mastery, Q / E cooldowns and lasting skill effects.
func _class_text() -> String:
	var skills := _player.skills
	var combat_class := skills.combat_class()
	if combat_class < 0:
		return "no main weapon"
	var parts: PackedStringArray = ["%s M%d (xp %d)" % [Enums.CombatClass.keys()[combat_class],
		Progression.mastery_level(combat_class), Progression.mastery_xp(combat_class)]]
	for entry: Dictionary in skills.hud_skills():
		parts.append("%s %.1fs" % [entry["key"], entry["left"]])
	for effect in skills.active():
		parts.append("%s %.1fs" % [effect["id"], effect["time_left"]])
	return ", ".join(parts)


func _status_text(holder: StatusHolder) -> String:
	if holder == null:
		return "-"
	var parts: PackedStringArray = []
	for e in holder.active():
		parts.append("%s x%d %.1fs" % [e["id"], e["stacks"], e["time_left"]])
	return ", ".join(parts) if not parts.is_empty() else "none"
