extends RefCounted
## B-07: monster AI states, hearing, sight, pack alert, damage, death signal,
## leash and nest spawning. Ticks are driven by hand with a fixed delta.

const BASE_SCENE := preload("res://field/monsters/monster_base.tscn")
const VINE := preload("res://data/monsters/vine_tendril.tres")
const POD := preload("res://data/monsters/spore_pod.tres")
const BLOB := preload("res://data/monsters/swamp_blob.tres")
const DT := 0.1

var _root: Node3D
var _ok := true


class FakeTarget extends Node3D:
	var hits: Array[Dictionary] = []

	func take_damage(amount: float, info: Dictionary) -> void:
		hits.append({"amount": amount, "info": info})


func run() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	_root = Node3D.new()
	_root.name = "TestMonsters"
	tree.root.add_child(_root)
	var tests: Array[Callable] = [
		_test_hearing_range,
		_test_state_signal_and_investigate,
		_test_sleep,
		_test_repeated_noise_chases,
		_test_sight,
		_test_pack_alert,
		_test_attack,
		_test_damage_and_death,
		_test_leash,
		_test_spawner,
		_test_demo_data,
		_test_bind,
		_test_alarm,
		_test_split,
		_test_visual,
	]
	for test in tests:
		test.call()
		for child in _root.get_children():
			child.free()
	_root.free()
	return _ok


# --- Tests ----------------------------------------------------------------

func _test_hearing_range() -> void:
	var m := _spawn(_def(), Vector3.ZERO)
	# hearing_mult 1.2, radius 10 -> heard up to 12 m.
	EventBus.noise_emitted.emit(Vector3(12.5, 0, 0), 10.0, null)
	_check(m.state == Enums.AIState.WANDER, "noise beyond radius x hearing is ignored")
	EventBus.noise_emitted.emit(Vector3(11.5, 0, 0), 10.0, null)
	_check(m.state == Enums.AIState.SUSPICIOUS, "noise inside radius x hearing makes it suspicious")
	EventBus.noise_emitted.emit(m.global_position, 10.0, m)
	_check(m._heard_times.size() == 1, "a monster ignores its own noise")


func _test_state_signal_and_investigate() -> void:
	var m := _spawn(_def(), Vector3.ZERO)
	var changes: Array = []
	m.state_changed.connect(func(old: Enums.AIState, new: Enums.AIState) -> void: changes.append([old, new]))
	m.hear(Vector3(5, 0, 0), null)
	_check(changes == [[Enums.AIState.WANDER, Enums.AIState.SUSPICIOUS]], "state_changed(WANDER, SUSPICIOUS)")
	_ticks(m, MonsterRules.SUSPICIOUS_SEC + DT)
	_check(m.state == Enums.AIState.INVESTIGATE, "suspicious turns into investigate after 1 s")
	_check(changes.back() == [Enums.AIState.SUSPICIOUS, Enums.AIState.INVESTIGATE], "state_changed(SUSPICIOUS, INVESTIGATE)")
	# Not moving in tests (no physics step), so it gives up travel and looks around.
	_ticks(m, MonsterRules.INVESTIGATE_TRAVEL_MAX_SEC + MonsterRules.INVESTIGATE_LOOK_SEC + 5 * DT)
	_check(m.state == Enums.AIState.WANDER, "investigate with nothing found goes back to wander")


func _test_sleep() -> void:
	var m := _spawn(_def(), Vector3.ZERO, Enums.AIState.SLEEP)
	# Sleeping: hearing x0.5 -> 6 m for radius 10.
	EventBus.noise_emitted.emit(Vector3(8, 0, 0), 10.0, null)
	EventBus.noise_emitted.emit(Vector3(8, 0, 0), 10.0, null)
	_check(m.state == Enums.AIState.SLEEP, "sleeping monster hears at half range")
	EventBus.noise_emitted.emit(Vector3(5, 0, 0), 10.0, null)
	_check(m.state == Enums.AIState.SLEEP, "one noise does not wake it")
	EventBus.noise_emitted.emit(Vector3(5, 0, 0), 10.0, null)
	_check(m.state == Enums.AIState.SUSPICIOUS, "two noises wake it suspicious")
	var hit := _spawn(_def(), Vector3(20, 0, 0), Enums.AIState.SLEEP)
	hit.take_damage(1.0, {})
	_check(hit.state == Enums.AIState.SUSPICIOUS, "a hit wakes it suspicious")


func _test_repeated_noise_chases() -> void:
	var player := _player(Vector3(0, 0, 10))  # out of sight range
	var m := _spawn(_def(), Vector3.ZERO)
	m.hear(player.global_position, player)
	_ticks(m, 0.5)
	m.hear(player.global_position, player)
	_check(m.state == Enums.AIState.SUSPICIOUS, "two noises are not enough to chase")
	_ticks(m, 0.5)
	m.hear(player.global_position, player)
	_check(m.state == Enums.AIState.CHASE and m.target == player, "3 noises in 3 s from the player start a chase")

	var lure := _spawn(_def(), Vector3(30, 0, 0))
	for i in 3:
		lure.hear(Vector3(30, 0, 5), null)
	_check(lure.state == Enums.AIState.SUSPICIOUS, "sourceless noise (thrown lure) never starts a chase")

	var slow := _spawn(_def(), Vector3(-30, 0, 0))
	slow.hear(player.global_position, player)
	_ticks(slow, MonsterRules.HEARING_WINDOW_SEC * 0.6)
	slow.hear(player.global_position, player)
	_ticks(slow, MonsterRules.HEARING_WINDOW_SEC * 0.6)
	slow.hear(player.global_position, player)
	_check(slow.state != Enums.AIState.CHASE, "noises spread over more than 3 s do not chase")


func _test_sight() -> void:
	var m := _spawn(_def(), Vector3.ZERO)
	var player := _player(Vector3(0, 0, -5))
	_check(m.find_visible_target() == player, "player in front inside range is seen")
	player.global_position = Vector3(0, 0, 5)
	_check(m.find_visible_target() == null, "player behind is not seen")
	player.global_position = Vector3(0, 0, -9)
	_check(m.find_visible_target() == null, "player beyond sight range is not seen")
	player.global_position = Vector3(0, 0, -5)
	_wall(Vector3(0, 1, -2.5))
	_check(m.find_visible_target() == null, "a world wall blocks sight")

	var m2 := _spawn(_def(), Vector3(30, 0, 0))
	var ally := _ally(Vector3(30, 0, -4))
	_check(m2.find_visible_target() == ally, "allies on layer 3 are seen")
	var player2 := _player(Vector3(30, 0, -6))
	_check(m2.find_visible_target() == player2, "player has priority over allies")

	m2.hear(Vector3(30, 0, -1), null)
	_ticks(m2, DT)
	_check(m2.state == Enums.AIState.CHASE and m2.target == player2, "suspicious monster that sees the player chases")


func _test_pack_alert() -> void:
	var pack := MonsterPack.new()
	var a := _spawn(_def(), Vector3.ZERO, Enums.AIState.WANDER, pack)
	var b := _spawn(_def(), Vector3(2, 0, 0), Enums.AIState.SLEEP, pack)
	var c := _spawn(_def(), Vector3(-2, 0, 0), Enums.AIState.WANDER, pack)
	var player := _player(Vector3(0, 0, -5))
	a.chase(player)
	_check(b.state == Enums.AIState.SUSPICIOUS and c.state == Enums.AIState.SUSPICIOUS,
			"one pack member chasing makes the rest suspicious")
	_check(pack.leader() == a, "first alive member leads the pack")


func _test_attack() -> void:
	var m := _spawn(_def(), Vector3.ZERO)
	var player := _player(Vector3(0, 0, -1))
	var landed: Array = []
	var started: Array = []
	m.attack_landed.connect(func(t: Node3D, info: Dictionary) -> void: landed.append(info))
	m.attack_started.connect(func(info: Dictionary) -> void: started.append(landed.size()))
	m.chase(player)
	_ticks(m, DT)
	_check(m.state == Enums.AIState.ATTACK, "target in attack range starts the attack")
	_ticks(m, MonsterRules.ATTACK_WINDUP_SEC + DT)
	_check(started == [0], "attack_started fires once, before the attack lands")
	_check(player.hits.size() == 1 and is_equal_approx(player.hits[0].amount, m.def.attack),
			"attack calls take_damage(attack, info) on the target")
	_check(landed.size() == 1 and landed[0].source == m and landed[0].element == m.def.family,
			"attack_landed carries source and element")
	player.global_position = Vector3(0, 0, -5)
	_ticks(m, DT)
	_check(m.state == Enums.AIState.CHASE, "target moving away goes back to chase")
	player.global_position = Vector3(0, 0, 5)
	m.rotation.y = 0.0
	_wall(Vector3(0, 1, 2.5))
	_ticks(m, MonsterRules.LOSE_TARGET_SEC + DT)
	_check(m.state == Enums.AIState.INVESTIGATE, "target unseen for 8 s turns into investigate")


func _test_damage_and_death() -> void:
	var def := _def()
	def.defense = 25.0  # factor 100 / 125 = 0.8
	def.hp = 100.0
	var m := _spawn(def, Vector3(3, 0, 4))
	var dealt: Array[float] = []
	m.damaged.connect(func(amount: float, _info: Dictionary) -> void: dealt.append(amount))
	m.take_damage(10.0, {"element": Enums.Element.NONE})
	_check(is_equal_approx(dealt[0], 8.0), "defense factor 100 / (100 + R)")
	(m.get_node("WeakPoint") as MonsterWeakPoint).take_damage(10.0, {"element": Enums.Element.NONE})
	_check(is_equal_approx(dealt[1], 16.0), "weak point doubles damage")
	m.take_damage(10.0, {"element": Enums.Element.STONE})  # stone beats green: x1.5
	_check(is_equal_approx(dealt[2], 12.0), "element weakness x1.5")
	m.take_damage(10.0, {"element": Enums.Element.LIGHT})  # green resists light: x0.75
	_check(is_equal_approx(dealt[3], 6.0), "element resistance x0.75")

	var killed: Array = []
	var on_killed := func(id: StringName, element: Enums.Element, pos: Vector3) -> void:
		killed.append([id, element, pos])
	EventBus.monster_killed.connect(on_killed)
	m.take_damage(1000.0, {})
	EventBus.monster_killed.disconnect(on_killed)
	_check(killed.size() == 1, "death emits monster_killed once")
	_check(killed.size() == 1 and killed[0] == [def.id, def.family, Vector3(3, 0, 4)],
			"monster_killed(id, element, position)")
	_check(m.is_dead() and m.is_queued_for_deletion(), "dead monster is freed")


func _test_leash() -> void:
	var m := _spawn(_def(), Vector3(MonsterRules.RETURN_DISTANCE + 5.0, 0, 0))
	m.home = Vector3.ZERO
	m.hp = 10.0
	m.hear(Vector3(MonsterRules.RETURN_DISTANCE + 6.0, 0, 0), null)
	_ticks(m, DT)
	_check(m.state == Enums.AIState.RETURN, "more than 40 m from home returns")
	_ticks(m, 1.0)
	_check(m.hp > 10.0, "hp regenerates while returning")
	m.hear(m.global_position, null)
	_check(m.state == Enums.AIState.RETURN, "returning monsters ignore noise")
	m.global_position = Vector3(0.2, 0, 0)
	_ticks(m, DT)
	_check(m.state == Enums.AIState.WANDER, "reaching home goes back to wander")


func _test_spawner() -> void:
	var def := _def()
	def.group_min = 3
	def.group_max = 3
	var other := _def()
	other.family = Enums.Element.WATER
	var nest := MonsterNest.new()
	nest.family = Enums.Element.GREEN
	nest.spawn_interval_sec = 180.0
	nest.max_alive = 6
	nest.position = Vector3(10, 0, 10)
	_root.add_child(nest)
	var spawner := MonsterSpawner.new()
	spawner.monster_defs = [other, def]
	_root.add_child(spawner)

	spawner.tick(0.0)
	_check(spawner.alive_count(nest) == 3, "nest spawns one pack (group_min..group_max) at start")
	var all_green := true
	var same_pack := true
	var first: Monster = spawner.get_child(0)
	for child in spawner.get_children():
		var mon := child as Monster
		all_green = all_green and mon.def == def
		same_pack = same_pack and mon.pack == first.pack
		_check(mon.global_position.distance_to(nest.global_position) <= MonsterRules.SPAWN_SCATTER_RADIUS + 0.01,
				"spawned near the nest")
		_check(mon.home == nest.global_position, "home is the nest")
	_check(all_green, "nest only spawns its own family")
	_check(same_pack, "a nest's monsters share one pack")
	spawner.tick(179.0)
	_check(spawner.alive_count(nest) == 3, "nothing before the interval")
	spawner.tick(1.0)
	var after := spawner.alive_count(nest)
	_check(after >= 4 and after <= 5, "1 to 2 more after spawn_interval_sec")
	spawner.tick(180.0 * 5)
	_check(spawner.alive_count(nest) == 6, "nest stops at max_alive")

	nest.max_alive = 100
	spawner.tick(180.0 * 40)
	_check(spawner.region_alive_count() == MonsterRules.REGION_MAX_ALIVE, "region cap 40")


func _test_demo_data() -> void:
	# 04 "마물 목록": hp, defense, attack, move, hearing, sight.
	var table := {
		VINE: [&"vine_tendril", Enums.Element.GREEN, 40.0, 0.0, 8.0, 5.5, 1.2, 8.0],
		POD: [&"spore_pod", Enums.Element.GREEN, 30.0, 0.0, 6.0, 0.0, 1.5, 10.0],
		BLOB: [&"swamp_blob", Enums.Element.WATER, 80.0, 5.0, 12.0, 3.0, 0.8, 6.0],
	}
	for def: MonsterDef in table:
		var row: Array = table[def]
		var got := [def.id, def.family, def.hp, def.defense, def.attack, def.move_speed, def.hearing_mult, def.sight_range]
		_check(got == row, "%s matches the 04 table" % row[0])
		var m := def.scene.instantiate() as Monster
		_check(m != null and m.get_node_or_null("WeakPoint") is MonsterWeakPoint, "%s scene is a Monster with a weak point" % row[0])
		if m:
			m.free()
	_check(VINE.group_min == 3 and VINE.group_max == 5, "vine tendrils come in packs of 3 to 5")


func _test_bind() -> void:
	var m := _spawn(VINE, Vector3.ZERO)
	var player := _player(Vector3(0, 0, -1))
	m.chase(player)
	_ticks(m, MonsterRules.ATTACK_WINDUP_SEC + 2 * DT)
	_check(player.hits.size() == 1 and is_equal_approx(player.hits[0].info.get("bind_sec", 0.0), MonsterRules.BIND_SEC),
			"vine tendril hit binds for 1 s")


func _test_alarm() -> void:
	var pod := _spawn(POD, Vector3.ZERO)
	# Scream 20 m x vine hearing 1.2 = 24 m.
	var near := _spawn(VINE, Vector3(22, 0, 0))
	var far := _spawn(VINE, Vector3(-25, 0, 0))
	var screams: Array = []
	var on_noise := func(pos: Vector3, radius: float, source: Node) -> void:
		if source == pod:
			screams.append(radius)
	EventBus.noise_emitted.connect(on_noise)
	var player := _player(Vector3(0, 0, -3))
	pod.chase(player)
	_check(screams == [MonsterRules.ALARM_SCREAM_RADIUS], "spore pod screams once on spotting (20 m)")
	_check(near.state == Enums.AIState.SUSPICIOUS, "monsters inside scream range turn suspicious")
	_check(far.state == Enums.AIState.WANDER, "monsters outside scream range do not hear it")
	_ticks(pod, DT)
	_check(pod.state == Enums.AIState.ATTACK, "spore pod attacks from range without moving")
	player.global_position = Vector3(0, 0, -9)
	_ticks(pod, DT)
	_check(pod.state == Enums.AIState.CHASE and screams.size() == 1, "ATTACK -> CHASE does not scream again")
	EventBus.noise_emitted.disconnect(on_noise)
	_check(pod.global_position == Vector3.ZERO and not pod.can_move(), "spore pod never moves")


func _test_split() -> void:
	var blob := _spawn(BLOB, Vector3(5, 0, 5))
	var split: MonsterBehavior = blob._behaviors[0]
	var children: Array[Monster] = split.make_children()
	_check(children.size() == MonsterRules.SPLIT_COUNT, "swamp blob splits into 2")
	for child in children:
		_root.add_child(child)
		child.set_physics_process(false)
	var c: Monster = children[0]
	_check(c.split_generation == 1 and is_equal_approx(c.max_hp, BLOB.hp * MonsterRules.SPLIT_HP_RATIO),
			"split child is generation 1 with half hp")
	var grandchildren: Array[Monster] = (c._behaviors[0] as MonsterBehavior).make_children()
	_check(grandchildren.size() == 2 and grandchildren[0].split_generation == 2, "generation 1 splits again")
	var last: Monster = grandchildren[0]
	_root.add_child(last)
	_check((last._behaviors[0] as MonsterBehavior).make_children().is_empty(), "no third split")
	for g in grandchildren:
		if not g.is_inside_tree():
			g.free()


## B-28: Lane D's model (art/monsters/<id>.tscn) replaces the grey box; no model -> grey box stays.
func _test_visual() -> void:
	var m := _spawn(VINE, Vector3.ZERO)
	var body := m.get_node(^"Body") as Node3D
	var core := m.get_node(^"WeakPoint/Core") as Node3D
	if m.has_node(^"Visual"):
		_check(not body.visible, "the model hides the grey-box body")
		_check(core.visible, "the weak point core stays visible")
	else:
		_check(body.visible, "without assets the grey box stays")
	var plain := _spawn(_def(), Vector3(5, 0, 0))
	_check(not plain.has_node(^"Visual") and (plain.get_node(^"Body") as Node3D).visible,
			"a monster id with no art keeps its grey box")


# --- Helpers --------------------------------------------------------------

func _def() -> MonsterDef:
	var def := MonsterDef.new()
	def.id = &"test_monster"
	def.family = Enums.Element.GREEN
	def.hp = 40.0
	def.attack = 8.0
	def.move_speed = 5.5
	def.hearing_mult = 1.2
	def.sight_range = 8.0
	def.sight_angle = 110.0
	def.attack_range = 1.5
	def.attack_interval = 1.0
	def.scene = BASE_SCENE
	return def


func _spawn(def: MonsterDef, pos: Vector3, start := Enums.AIState.WANDER, pack: MonsterPack = null) -> Monster:
	var m := BASE_SCENE.instantiate() as Monster
	m.def = def
	m.start_state = start
	m.position = pos
	if pack:
		pack.add(m)
	_root.add_child(m)
	m.set_physics_process(false)  # tests drive tick() by hand
	return m


func _player(pos: Vector3) -> FakeTarget:
	var p := FakeTarget.new()
	p.add_to_group(Monster.PLAYER_GROUP)
	p.position = pos
	_root.add_child(p)
	return p


func _ally(pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (Enums.LAYER_ALLY - 1)
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	body.add_child(shape)
	body.position = pos
	_root.add_child(body)
	return body


func _wall(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (Enums.LAYER_WORLD - 1)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 0.4)
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	_root.add_child(body)


func _ticks(m: Monster, seconds: float) -> void:
	for i in ceili(seconds / DT):
		m.tick(DT)


func _check(cond: bool, what: String) -> void:
	if not cond:
		push_error("test_monsters: " + what)
		_ok = false
