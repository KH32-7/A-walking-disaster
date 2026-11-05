extends Node3D
## Lane B wiring check (M1): the real player with noise, monsters and loot in one sandbox.
## Run alone (F6). Walk near monsters to be heard, sprint to be heard farther, F to open a
## container. Sandbox-only debug keys (raw keycodes, not project actions):
##   T: take every identified slot of the container you opened (stand-in for the D-08 screen)
##   K: kill monsters within KILL_RADIUS (stand-in until B-06 weapons)
## Camera (B-04): Z/C rotate, wheel zoom, hold right click to aim at the cursor. Walk into the
## DemoHouse corner (northwest) to see its roof hide.

const KILL_RADIUS := 4.0
const KILL_DAMAGE := 9999.0
const SandboxCameraInput := preload("res://field/_sandbox/sandbox_camera_input.gd")

@onready var _player: Player = $Player
@onready var _camera: FieldCamera = $FieldCamera
@onready var _label: Label = $DebugLayer/InfoLabel

var _container: LootContainer
var _last_noise := "-"
var _last_event := "-"


func _ready() -> void:
	SandboxCameraInput.ensure()
	EventBus.noise_emitted.connect(_on_noise)
	EventBus.player_downed.connect(func() -> void: _last_event = "player downed")
	EventBus.monster_killed.connect(func(id: StringName, _e: Enums.Element, _p: Vector3) -> void:
		_last_event = "killed %s" % id)
	for child in $LootSpawner.get_children():
		if child is LootContainer:
			child.open_started.connect(func(_d: float, _f: bool) -> void: _container = child)


func _process(_delta: float) -> void:
	_label.text = "\n".join([
		"Move: %s  Bound: %s  Godmode: %s" % [
			Player.MoveState.keys()[_player.move_state], _player.is_bound(), DebugConsole.godmode],
		"Health: %.0f  Stamina: %.0f" % [_player.health, _player.stamina],
		"Last noise: %s" % _last_noise,
		"Nearest monster: %s" % _nearest_monster_text(),
		"Container: %s" % _container_text(),
		"Bag: %s" % _bag_text(),
		"Event: %s" % _last_event,
		"Camera: view %d  zoom %d  Aiming: %s" % [_camera.yaw_index(), _camera.zoom_level(), _player.is_aiming],
		"F open, T take all, K kill near, Z/C rotate, wheel zoom, ` console",
	])


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
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


func _on_noise(_position: Vector3, radius: float, source: Node) -> void:
	_last_noise = "%.1fm from %s" % [radius, source.name if source else "?"]


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
	return "%s %.1fm %s" % [best.def.id, best_dist, Enums.AIState.keys()[best.state]]


func _container_text() -> String:
	if _container == null:
		return "none"
	var slots: PackedStringArray = []
	for slot in _container.get_slots():
		if slot.count == 0 and slot.identified:
			continue
		slots.append("%s x%d" % [slot.item_id, slot.count] if slot.identified else "?")
	return "%s [%s]" % [LootContainer.State.keys()[_container.state], ", ".join(slots)]


func _bag_text() -> String:
	var parts: PackedStringArray = []
	for entry in Bag.entries():
		parts.append("%s x%d" % [entry.ref, entry.amount])
	return ", ".join(parts) if not parts.is_empty() else "empty"
