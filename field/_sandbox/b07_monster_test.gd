extends Node3D
## B-07 monster test scene. Run alone (F6). Debug Label3D above each monster
## shows its AI state and hp (sandbox only; the real "?" / "!" is Lane D's D-05).
## Run with `-- --b07-demo` for a scripted check that prints PASS / FAIL and quits.

const DEMO_ARG := "--b07-demo"

@onready var _player: CharacterBody3D = $FakePlayer
@onready var _spawner: MonsterSpawner = $MonsterSpawner
@onready var _pod: Monster = $SporePod
@onready var _blob: Monster = $SwampBlob

var _kills: Dictionary = {}  # monster_id -> count
var _screams := 0
var _demo := false
var _demo_time := 0.0
var _demo_step := 0
var _demo_ok := true


func _ready() -> void:
	EventBus.monster_killed.connect(_on_monster_killed)
	EventBus.noise_emitted.connect(_on_noise)
	_demo = OS.get_cmdline_user_args().has(DEMO_ARG)


func _process(delta: float) -> void:
	for node in get_tree().get_nodes_in_group(Monster.GROUP):
		_update_label(node as Monster)
	if _demo:
		_demo_time += delta
		_run_demo()


func _update_label(m: Monster) -> void:
	var label := m.get_node_or_null("DebugState") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "DebugState"
		label.position.y = 2.4
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 48
		label.pixel_size = 0.01
		m.add_child(label)
		m.state_changed.connect(func(old: Enums.AIState, new: Enums.AIState) -> void:
			print("[b07] %s %s -> %s" % [m.name, Enums.AIState.keys()[old], Enums.AIState.keys()[new]]))
	var mark := ""
	if m.state == Enums.AIState.SUSPICIOUS:
		mark = " ?"
	elif m.state == Enums.AIState.CHASE or m.state == Enums.AIState.ATTACK:
		mark = " !"
	label.text = "%s%s\n%d / %d" % [Enums.AIState.keys()[m.state], mark, ceili(m.hp), ceili(m.max_hp)]


func _on_monster_killed(monster_id: StringName, _element: Enums.Element, _position: Vector3) -> void:
	_kills[monster_id] = _kills.get(monster_id, 0) + 1


func _on_noise(_position: Vector3, radius: float, source: Node) -> void:
	if source is Monster and is_equal_approx(radius, MonsterRules.ALARM_SCREAM_RADIUS):
		_screams += 1
		print("[b07] %s screamed" % source.name)


## Scripted check for headless runs. Steps fire once each, in order.
func _run_demo() -> void:
	match _demo_step:
		0:
			if _demo_time > 0.5:
				_expect(_spawner.region_alive_count() >= 5, "nest spawned its first pack")
				# Stand in front of the pod (it faces -Z) so it spots the player.
				_player.global_position = _pod.global_position + Vector3(0, 0, -4)
				_demo_step += 1
		1:
			if _demo_time > 2.0:
				_expect(_pod.state == Enums.AIState.CHASE or _pod.state == Enums.AIState.ATTACK, "pod spotted the player")
				_expect(_screams >= 1, "pod screamed (20 m noise)")
				_player.global_position = Vector3(25, 0, 25)
				_blob.take_damage(10000.0, {})
				_demo_step += 1
		2, 3:
			if _demo_time > 2.5 + (_demo_step - 1) * 0.5:
				for blob in _blobs():
					blob.take_damage(10000.0, {})
				_demo_step += 1
		4:
			if _demo_time > 4.5:
				_expect(_kills.get(&"swamp_blob", 0) == 7, "swamp blob split 1 -> 2 -> 4 (7 kills)")
				_expect(_blobs().is_empty(), "no blob left after the 2nd split")
				var vine := _first_vine()
				_expect(vine != null, "a vine tendril is alive")
				if vine:
					# Open floor, away from walls, so the result does not depend on where it wandered.
					vine.global_position = Vector3(0, 0, 14)
					_player.global_position = Vector3(0, 0, 12.8)
					vine.chase(_player)
				_demo_step += 1
		5:
			if _demo_time > 7.0:
				var bound: bool = _player.hits.any(func(h: Dictionary) -> bool:
					return h.info.get("monster_id") == &"vine_tendril" and h.info.get("bind_sec", 0.0) > 0.0)
				_expect(bound, "vine tendril hit carries bind_sec")
				print("[b07] demo ", "PASS" if _demo_ok else "FAIL")
				get_tree().quit(0 if _demo_ok else 1)
				_demo_step += 1


func _blobs() -> Array[Monster]:
	var result: Array[Monster] = []
	for node in get_tree().get_nodes_in_group(Monster.GROUP):
		var m := node as Monster
		if m.def.id == &"swamp_blob" and not m.is_dead():
			result.append(m)
	return result


func _first_vine() -> Monster:
	for node in get_tree().get_nodes_in_group(Monster.GROUP):
		var m := node as Monster
		if m.def.id == &"vine_tendril" and not m.is_dead():
			return m
	return null


func _expect(cond: bool, what: String) -> void:
	print("[b07] %s: %s" % ["ok" if cond else "FAILED", what])
	_demo_ok = _demo_ok and cond
