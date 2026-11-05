extends Node
## B-14: status effect data (8 kinds), StatusHolder rules (ticks, stacks, refresh, movement,
## actions, armor break, wet + shock, knockback, legacy bind_sec) and the hooks on the player,
## monsters and rescued people. Bodies are driven with step()/tick(); their physics is off.

const DT := 1.0 / 60.0
const EPS := 0.01
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const MONSTER_SCENE := preload("res://field/monsters/monster_base.tscn")
const TARGET_SCENE := preload("res://field/rescue/rescue_target.tscn")
const VINE_DEF := preload("res://data/monsters/vine_tendril.tres")
const IDS: Array[StringName] = [&"bleed", &"stagger", &"knockback", &"armor_break",
		&"slow", &"bind", &"shock", &"wet"]


class Dummy extends Node3D:
	var hits: Array = []

	func take_damage(amount: float, info: Dictionary = {}) -> void:
		hits.append([amount, info])


var _ok := true


func run() -> bool:
	_ok = true
	_test_defs()
	_test_bleed_ticks()
	_test_stacks_and_refresh()
	_test_wet_and_shock()
	_test_move_and_action_queries()
	_test_knockback()
	_test_legacy_bind()
	_test_player()
	_test_monster()
	_test_rescue_target()
	return _ok


func _test_defs() -> void:
	for id in IDS:
		var def := StatusHolder.get_def(id)
		_expect(def != null and def.id == id, "%s.tres loads with its id" % id)
	var bleed := StatusHolder.get_def(&"bleed")
	_expect_near(bleed.tick_damage, 3.0, "bleed 3 per second")
	_expect_near(bleed.duration_sec, 5.0, "bleed 5 s")
	_expect(StatusHolder.get_def(&"stagger").stops_actions, "stagger stops actions")
	_expect_near(StatusHolder.get_def(&"knockback").knockback_m, 1.5, "knockback 1.5 m")
	var armor := StatusHolder.get_def(&"armor_break")
	_expect_near(armor.defense_mult, 0.5, "armor break R x0.5")
	_expect_near(armor.duration_sec, 5.0, "armor break 5 s")
	_expect(StatusHolder.get_def(&"shock").element == Enums.Element.LIGHT, "shock ticks are LIGHT")
	_expect(StatusHolder.get_def(&"nope") == null, "unknown id has no def")


func _test_bleed_ticks() -> void:
	var d := _dummy()
	var removed: Array[StringName] = []
	d.get_node("Status").status_removed.connect(func(id: StringName) -> void: removed.append(id))
	var s: StatusHolder = d.get_node("Status")
	_expect(s.apply(&"bleed"), "apply bleed")
	_steps(s, 0.5)
	_expect(d.hits.is_empty(), "no tick before 1 s")
	_steps(s, 5.0)
	var total := 0.0
	for h: Array in d.hits:
		total += h[0]
	_expect(d.hits.size() == 5, "5 ticks in 5 s (got %d)" % d.hits.size())
	_expect_near(total, 15.0, "bleed deals 3 x 5")
	_expect(StatusHolder.is_tick(d.hits[0][1]) and d.hits[0][1]["status_tick"] == &"bleed", "tick info")
	_expect(not s.has(&"bleed") and removed == [&"bleed"], "bleed ends and says so")
	d.free()


func _test_stacks_and_refresh() -> void:
	var d := _dummy()
	var s: StatusHolder = d.get_node("Status")
	s.apply(&"bleed")
	_steps(s, 3.0)
	s.apply(&"bleed")
	_expect(s.stacks(&"bleed") == 1, "bleed caps at 1 stack")
	_expect_near(s.time_left(&"bleed"), 5.0, "re-applying refreshes the time")
	s.apply(&"bleed", {"duration": 1.0})
	_expect_near(s.time_left(&"bleed"), 5.0, "a shorter one keeps the longer time")
	s.clear()
	d.hits.clear()
	s.apply(&"bleed", {"stacks_max": 2})
	s.apply(&"bleed", {"stacks_max": 2})
	_expect(s.stacks(&"bleed") == 2, "blade mastery 10: 2 stacks")
	_steps(s, 1.0)
	_expect(d.hits.size() == 1 and absf(d.hits[0][0] - 6.0) < EPS, "2 stacks tick 6")
	var list := s.active()
	_expect(list.size() == 1 and list[0]["id"] == &"bleed" and list[0]["stacks"] == 2, "active() for Lane D")
	d.free()


func _test_wet_and_shock() -> void:
	var d := _dummy()
	var s: StatusHolder = d.get_node("Status")
	_expect_near(s.scale_damage(10.0, {"element": Enums.Element.LIGHT}), 10.0, "dry: light x1")
	s.apply(&"wet")
	_expect_near(s.scale_damage(10.0, {"element": Enums.Element.LIGHT}), 12.5, "wet: light x1.25")
	_expect_near(s.scale_damage(10.0, {"element": Enums.Element.GREEN}), 10.0, "wet: other elements x1")
	_expect_near(s.scale_damage(10.0, {"element": Enums.Element.LIGHT, "status_tick": &"shock"}), 10.0,
			"ticks are not scaled twice")
	s.apply(&"shock")
	_expect_near(s.move_mult(), 0.8, "shock slows a little")
	_steps(s, 1.0)
	_expect(d.hits.size() == 1, "shock ticks once in 1 s")
	if d.hits.size() == 1:
		_expect_near(d.hits[0][0], 5.0 * 1.25, "wet shock tick x1.25")
		_expect(d.hits[0][1]["element"] == Enums.Element.LIGHT, "shock tick is LIGHT")
	d.free()


func _test_move_and_action_queries() -> void:
	var d := _dummy()
	var s: StatusHolder = d.get_node("Status")
	_expect(s.can_move() and s.can_act() and s.move_mult() == 1.0, "nothing active")
	s.apply(&"slow")
	_expect_near(s.move_mult(), 0.6, "slow x0.6")
	_expect(s.can_act(), "slowed can act")
	s.apply(&"bind")
	_expect(not s.can_move() and s.can_act(), "bound: no moving, can still attack")
	s.clear()
	s.apply(&"stagger")
	_expect(not s.can_move() and not s.can_act(), "staggered: nothing")
	s.apply(&"armor_break")
	_expect_near(s.defense_mult(), 0.5, "armor break halves R")
	_steps(s, 1.1)
	_expect(s.can_act() and s.has(&"armor_break"), "stagger 1 s ends, armor break stays")
	_steps(s, 4.0)
	_expect_near(s.defense_mult(), 1.0, "armor break ends after 5 s")
	_expect(s.steer(Vector3(2, -1, 2)) == Vector3(2, -1, 2), "steer passes velocity through")
	s.apply(&"bind")
	_expect(s.steer(Vector3(2, -1, 2)) == Vector3(0, -1, 0), "steer stops a bound body, keeps y")
	d.free()


func _test_knockback() -> void:
	var d := _dummy()
	var s: StatusHolder = d.get_node("Status")
	var source := Node3D.new()
	add_child(source)
	source.global_position = Vector3(-1, 0, 0)
	s.apply_hit({"source": source, "status": [{"id": &"knockback"}]})
	_expect(not s.can_act(), "knocked back: no actions")
	var push := s.knockback_velocity()
	_expect(push.x > 0.0 and absf(push.z) < EPS, "pushed away from the source")
	var steered := s.steer(Vector3(0, -2, 3))
	_expect(absf(steered.x - push.x) < EPS and steered.y == -2.0 and absf(steered.z) < EPS, "steer = push")
	var dist := 0.0
	for i in 120:
		if not s.has(&"knockback"):
			break
		dist += s.knockback_velocity().length() * DT
		s.step(DT)
	_expect_near(dist, 1.5, "pushed 1.5 m")
	s.apply(&"knockback", {"dir": Vector3(0, 0, -2)})
	_expect(s.knockback_velocity().z < 0.0, "explicit dir")
	source.free()
	d.free()


func _test_legacy_bind() -> void:
	var d := _dummy()
	var s: StatusHolder = d.get_node("Status")
	s.apply_hit({"bind_sec": 1.0})
	_expect(s.has(&"bind") and is_equal_approx(s.time_left(&"bind"), 1.0), "bind_sec = 1 s bind")
	s.apply_hit({"status_tick": &"bleed", "status": [{"id": &"slow"}]})
	_expect(not s.has(&"slow"), "tick hits carry no statuses")
	d.free()


func _test_player() -> void:
	var p: Player = PLAYER_SCENE.instantiate()
	p.set_physics_process(false)
	add_child(p)
	_expect(p.get_node("Status") == p.status, "player has a Status child")
	p.take_damage(5.0, {"status": [{"id": &"bleed"}]})
	_expect_near(p.health, 95.0, "hit damage")
	_player_steps(p, 1.0, {})
	_expect_near(p.health, 92.0, "bleed tick on the player")
	p.status.clear()
	p.take_damage(1.0, {"status": [{"id": &"slow"}]})
	_player_steps(p, 1.0, {"move": Vector2.UP})
	var flat := Vector2(p.velocity.x, p.velocity.z).length()
	_expect_near(flat, p.stats.walk_speed * 0.6, "slowed walk")
	p.status.clear()
	p.stun(1.0)
	_expect(p.is_bound() and not p.status.can_act(), "stun = stagger")
	_player_steps(p, 1.1, {})
	_expect(not p.is_bound(), "stagger wears off")
	var source := Node3D.new()
	add_child(source)
	source.global_position = p.global_position + Vector3(-1, 0, 0)
	p.take_damage(1.0, {"source": source, "status": [{"id": &"knockback"}]})
	p.step(DT, {"move": Vector2.LEFT})
	_expect(p.velocity.x > 1.0, "knockback pushes the player away")
	source.free()
	p.status.apply(&"bleed")
	p.take_damage(1000.0)
	_expect(p.is_downed and p.status.active().is_empty(), "downed clears statuses")
	p.free()


func _test_monster() -> void:
	var def: MonsterDef = VINE_DEF.duplicate()
	def.defense = 100.0
	var m: Monster = MONSTER_SCENE.instantiate()
	m.def = def
	m.hp_scale = 100.0
	m.start_state = Enums.AIState.SLEEP
	add_child(m)
	m.set_physics_process(false)
	var hp := m.hp
	m.take_damage(10.0, {"status": [{"id": &"armor_break"}]})
	_expect_near(hp - m.hp, 5.0, "R 100 halves the hit; armor break starts after it")
	hp = m.hp
	m.take_damage(10.0, {})
	_expect_near(hp - m.hp, 10.0 * 100.0 / 150.0, "armor break: R 50")
	m.status.clear()
	m.stun(1.0)
	_expect(m.is_stunned(), "monster stun = stagger")
	for i in 30:
		m.tick(DT)
	_expect(Vector2(m.velocity.x, m.velocity.z).length() < EPS, "staggered monster stands still")
	for i in 40:
		m.tick(DT)
	_expect(not m.is_stunned(), "monster stagger wears off")
	var sleeper: Monster = MONSTER_SCENE.instantiate()
	sleeper.def = VINE_DEF
	sleeper.start_state = Enums.AIState.SLEEP
	add_child(sleeper)
	sleeper.set_physics_process(false)
	hp = sleeper.hp
	sleeper.status.apply(&"bleed")
	for i in 61:
		sleeper.tick(DT)
	_expect_near(hp - sleeper.hp, 3.0, "bleed tick on a monster is flat")
	_expect(sleeper.state == Enums.AIState.SLEEP, "bleed ticks do not wake it")
	sleeper.free()
	m.free()


func _test_rescue_target() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.set_physics_process(false)
	add_child(player)
	var spawn := RescueSpawn.new()
	spawn.template_id = &"test_person"
	spawn.rescue_type = RescueSpawn.Type.INJURED
	spawn.move_type = RescueSpawn.Move.WALK
	var t: RescueTarget = TARGET_SCENE.instantiate()
	t.setup(spawn, {"name": "테스트"})
	t.set_physics_process(false)
	add_child(t)
	t.global_position = Vector3(1, 0, 1)
	_expect(t.begin_open(player) and t.state == RescueTarget.State.FOLLOW, "rescued and following")
	var health := t.health
	t.take_damage(2.0, {"status": [{"id": &"bleed"}, {"id": &"bind"}]})
	_expect(t.status.has(&"bleed") and t.status.has(&"bind"), "rescuee gets statuses")
	_expect(t.status.steer(Vector3(1, 0, 0)) == Vector3.ZERO, "bound rescuee does not walk")
	for i in 61:
		t.tick(DT)
	_expect_near(health - t.health, 5.0, "hit 2 + bleed tick 3")
	t.take_damage(t.health + 1.0, {})
	_expect(t.state == RescueTarget.State.DOWNED and t.status.active().is_empty(), "downed clears statuses")
	t.free()
	player.free()


# --- Helpers ----------------------------------------------------------------

func _dummy() -> Dummy:
	var d := Dummy.new()
	add_child(d)
	StatusHolder.attach(d)
	return d


func _steps(s: StatusHolder, sec: float) -> void:
	for i in roundi(sec / DT):
		s.step(DT)


func _player_steps(p: Player, sec: float, input: Dictionary) -> void:
	for i in roundi(sec / DT):
		p.step(DT, input)


func _expect_near(a: float, b: float, what: String) -> void:
	_expect(absf(a - b) < EPS, "%s (got %.3f, want %.3f)" % [what, a, b])


func _expect(cond: bool, what: String) -> void:
	if not cond:
		push_error("test_status: %s" % what)
		_ok = false
