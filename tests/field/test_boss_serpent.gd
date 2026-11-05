extends RefCounted
## Flooded mall boss: 가라앉은 간판뱀 (docs/design/04-monsters.md "보스"). Data from the 04 table, immune
## underwater, tail swing (cone), splash (orange ring: slow + wet, no damage), dive (swim, line, charge),
## surfaced window, first kill drop (legendary blade). Ticks are driven by hand (no physics movement).

const DT := 0.1
const BOSS_ID := &"sunken_sign_serpent"

var _root: Node3D
var _ok := true


class FakeTarget extends Node3D:
	var hits: Array[Dictionary] = []

	func take_damage(amount: float, info: Dictionary) -> void:
		hits.append({"amount": amount, "info": info})


func run() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	_root = Node3D.new()
	_root.name = "TestBossSerpent"
	tree.root.add_child(_root)
	var tests: Array[Callable] = [_test_data, _test_immune_underwater, _test_tail_swing, _test_splash, _test_dive,
		_test_first_kill_drop]
	for test in tests:
		test.call()
		for child in _root.get_children():
			child.free()
	_root.free()
	return _ok


func _test_data() -> void:
	var def := load("res://data/monsters/%s.tres" % BOSS_ID) as MonsterDef
	_check(def != null and def.scene != null, "serpent def and scene load")
	if def == null:
		return
	# 04 "마물 목록": 물, 보스, 1200 / 15 / 35 / 6.0, 청각 x1.2, 시각 12 m.
	var got := [def.family, def.tier, def.hp, def.defense, def.attack, def.move_speed, def.hearing_mult, def.sight_range]
	_check(got == [Enums.Element.WATER, Enums.MonsterTier.BOSS, 1200.0, 15.0, 35.0, 6.0, 1.2, 12.0],
			"serpent matches the 04 table %s" % [got])
	_check(def.regions.has(&"flooded_mall"), "lives in the flooded mall")
	var boss := BossDef.for_monster(BOSS_ID)
	_check(boss != null and boss.mechanic != null and boss.respawn_days == 3, "boss def with its mechanic")
	if boss:
		var ids: Array[StringName] = []
		for p in boss.patterns:
			ids.append(p.id)
		_check(ids == [&"tail_swing", &"splash", &"dive"], "patterns %s" % [ids])
	_check(Enums.element_multiplier(Enums.Element.LIGHT, Enums.Element.WATER) > 1.0, "light beats it (04: 광 속성)")


func _test_immune_underwater() -> void:
	var s := _spawn()
	var m := s.mechanic
	_check(m != null and m.get("submerged") == true, "starts underwater")
	s.take_damage(500.0)
	_check(is_equal_approx(s.hp, s.max_hp), "no damage underwater")


func _test_tail_swing() -> void:
	var s := _spawn()
	var player := _player(Vector3(0, 0, -3))
	s.chase(player)
	s.tick(DT)
	_check(s.casting() != null and s.casting().id == &"tail_swing", "3 m away: tail swing")
	_check(s.mechanic.get("submerged") == false, "comes up to swing")
	s.take_damage(100.0)
	_check(s.hp < s.max_hp, "hittable while up")
	_tick(s, 1.1)
	_check(player.hits.size() == 1, "tail swing lands after the warning")
	if player.hits.size() == 1:
		_check(is_equal_approx(player.hits[0].amount, 42.0), "damage = 35 x 1.2 (%.1f)" % player.hits[0].amount)
	player.position = Vector3(0, 0, -40)  # out of reach: no new pattern keeps it up
	_tick(s, 3.2)
	_check(s.mechanic.get("submerged") == true, "sinks again after its surface time")


func _test_splash() -> void:
	var s := _spawn()
	var player := _player(Vector3(0, 0, -6))
	var holder := StatusHolder.attach(player)  # the player has one (Player.status)
	var areas: Array[Dictionary] = []
	s.telegraph_started.connect(func(area: Dictionary) -> void: areas.append(area))
	s.chase(player)
	s.tick(DT)
	_check(s.casting() != null and s.casting().id == &"splash", "6 m away (past the tail): splash")
	_check(areas.size() == 1 and areas[0]["kind"] == &"warn" and areas[0]["shape"] == &"circle",
			"splash warns with an orange circle")
	_tick(s, 1.1)
	_check(player.hits.is_empty(), "splash deals no damage")
	_check(holder.has(&"slow") and holder.has(&"wet"), "splash slows and wets")


func _test_dive() -> void:
	var s := _spawn()
	var player := _player(Vector3(0, 0, -10))
	var areas: Array[Dictionary] = []
	s.telegraph_started.connect(func(area: Dictionary) -> void: areas.append(area))
	s.chase(player)
	s.tick(DT)
	_check(s.casting() != null and s.casting().id == &"dive", "10 m away: dive")
	_tick(s, 0.7)
	_check(s.is_held() and s.mechanic.call(&"is_diving") and s.mechanic.get("submerged") == true,
			"after the windup it is under and swimming")
	s.take_damage(500.0)
	_check(is_equal_approx(s.hp, s.max_hp), "immune while diving")
	_tick(s, 1.7)  # swim time runs out (no physics here, it stays put)
	_check(areas.size() == 1 and areas[0]["shape"] == &"line" and is_equal_approx(areas[0]["length"], 12.0),
			"marks a 12 m line before the charge")
	_check(player.hits.is_empty(), "nothing lands during the warning")
	_tick(s, 1.5)
	_check(player.hits.size() == 1, "charge hits whoever stayed on the line")
	_check(not s.is_held() and s.mechanic.get("submerged") == false, "up and fighting after the charge")
	s.take_damage(100.0)
	_check(s.hp < s.max_hp, "hittable after the charge")


func _test_first_kill_drop() -> void:
	var boss := BossDef.for_monster(BOSS_ID)
	var table := MonsterDrops.table(boss.first_kill_drop_table_id) if boss else null
	_check(table != null and is_equal_approx(table.gear_chance, 1.0), "first kill always drops gear")
	if table == null:
		return
	_check(table.gear_rarity_weights == [0.0, 0.0, 0.0, 0.0, 1.0], "legendary only")
	var all_blades := not table.gear_pool.is_empty()
	for id in table.gear_pool:
		var item := load("res://data/items/%s.tres" % id)
		all_blades = all_blades and item != null and int(item.get("combat_class")) == Enums.CombatClass.BLADE
	_check(all_blades, "the pool is blades (04: 전설 칼 1종)")


# --- Helpers --------------------------------------------------------------

func _spawn() -> BossMonster:
	var def := load("res://data/monsters/%s.tres" % BOSS_ID) as MonsterDef
	var s := def.scene.instantiate() as BossMonster
	s.def = def
	_root.add_child(s)
	s.set_physics_process(false)  # tests drive tick() by hand
	return s


func _player(pos: Vector3) -> FakeTarget:
	var p := FakeTarget.new()
	p.add_to_group(Monster.PLAYER_GROUP)
	p.position = pos
	_root.add_child(p)
	return p


func _tick(s: BossMonster, sec: float) -> void:
	for i in roundi(sec / DT):
		s.tick(DT)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("test_boss_serpent: " + what)
