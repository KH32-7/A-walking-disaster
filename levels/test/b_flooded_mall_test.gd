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
##   F1..F6 weapons, F7 ammo (WeaponDebug)
## Console (`): `card <0-2>` answers the nearest rescue target's picture card round.

const REGION_ID := &"flooded_mall"
const LOADOUT := {Enums.EquipSlot.MAIN: &"pistol", Enums.EquipSlot.SUB: &"dagger"}
const KILL_RADIUS := 4.0
const KILL_DAMAGE := 9999.0
const TELEPORT_OFFSET := Vector3(0.0, 0.2, 2.0)

@onready var _mall: Node3D = $FloodedMall
@onready var _label: Label = $DebugLayer/InfoLabel

var _player: Player
var _container: LootContainer
var _rescue_index := -1
var _extract_index := -1
var _events: PackedStringArray = []


func _enter_tree() -> void:
	# Before the mall's spawners run: same order SceneRouter.go_to_field uses.
	GameState.set_phase(Enums.Phase.SORTIE)
	EventBus.sortie_started.emit({"region_id": REGION_ID, "seed": randi()})


func _ready() -> void:
	_player = _mall.get(&"player") as Player
	for slot: Enums.EquipSlot in LOADOUT:
		if Armory.get_equipped(Armory.PLAYER_ID, slot) == &"":
			Armory.equip(Armory.PLAYER_ID, slot, Armory.create_item(LOADOUT[slot], Enums.Rarity.COMMON))
	UI.show_field_hud(true)
	# Deferred: spawners may place their nodes during their own deferred calls.
	_watch_containers.call_deferred()
	EventBus.player_downed.connect(func() -> void: _log("player downed"))
	EventBus.monster_killed.connect(func(id: StringName, _e: Enums.Element, _p: Vector3) -> void:
		_log("killed %s" % id))
	EventBus.rescue_completed.connect(func(r: Dictionary) -> void: _log("rescued %s" % r.get("name", "?")))
	EventBus.extraction_completed.connect(func(id: StringName) -> void: _log("extracted at %s" % id))
	DebugConsole.register(&"card", _cmd_card, "card <0-2> - answer the nearest rescue card round")


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
		"Nearest monster: %s" % _nearest_monster_text(),
		"Container: %s" % _container_text(),
		"Result: %s" % (_result_text(result) if not result.is_empty() else "-"),
		"Events: %s" % " / ".join(_events),
		"T take all, K kill near, F8 rescue, F9 extract, F1-F7 weapons/ammo, ` card <n>",
	])


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
	return "%s %.0fm %s" % [best.def.id, best_dist, Enums.AIState.keys()[best.state]]


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
