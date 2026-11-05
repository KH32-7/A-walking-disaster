extends RefCounted
## Flooded mall boss: 방파제 골렘 (docs/design/04-monsters.md "보스"). Data from the 04 table, wave slam (red
## line, knockback + wet), rock throw (red circle on you, stagger), guard stance (defense x2, no attacks), a
## blunt hit breaks it (stagger), first kill reward (generator cores x2 + radio tower blueprint flag).

const DT := 0.1
const BOSS_ID := &"breakwater_golem"
const FLAG := &"blueprint_radio_tower"

var _root: Node3D
var _ok := true


class FakeTarget extends Node3D:
	var hits: Array[Dictionary] = []

	func take_damage(amount: float, info: Dictionary) -> void:
		hits.append({"amount": amount, "info": info})


func run() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	_root = Node3D.new()
	_root.name = "TestBossGolem"
	tree.root.add_child(_root)
	var saved_kills := FieldState.boss_kills.duplicate()
	var saved_flags := GameState.flags.duplicate()
	var tests: Array[Callable] = [_test_data, _test_wave_slam, _test_rock_throw, _test_guard, _test_guard_break,
		_test_first_kill]
	for test in tests:
		test.call()
		for child in _root.get_children():
			child.free()
	_root.free()
	FieldState.boss_kills = saved_kills
	GameState.flags = saved_flags
	return _ok


func _test_data() -> void:
	var def := load("res://data/monsters/%s.tres" % BOSS_ID) as MonsterDef
	_check(def != null and def.scene != null, "golem def and scene load")
	if def == null:
		return
	# 04 "마물 목록": 잔해, 보스, 3000 / 60 / 45 / 2.0, 청각 x1.0, 시각 14 m.
	var got := [def.family, def.tier, def.hp, def.defense, def.attack, def.move_speed, def.hearing_mult, def.sight_range]
	_check(got == [Enums.Element.STONE, Enums.MonsterTier.BOSS, 3000.0, 60.0, 45.0, 2.0, 1.0, 14.0],
			"golem matches the 04 table %s" % [got])
	_check(Enums.element_multiplier(Enums.Element.WATER, Enums.Element.STONE) > 1.0, "water beats it (04: 수 속성)")


func _test_wave_slam() -> void:
	var g := _spawn()
	var player := _player(Vector3(0, 0, -5))
	var areas: Array[Dictionary] = []
	g.telegraph_started.connect(func(area: Dictionary) -> void: areas.append(area))
	g.chase(player)
	g.tick(DT)
	_check(g.casting() != null and g.casting().id == &"wave_slam", "5 m away: wave slam")
	_check(areas.size() == 1 and areas[0]["shape"] == &"line" and is_equal_approx(areas[0]["width"], 4.0),
			"wave slam marks a wide red line")
	_tick(g, 1.3)
	_check(player.hits.size() == 1, "wave slam lands")
	if player.hits.size() == 1:
		var ids: Array = (player.hits[0].info["status"] as Array).map(func(e: Dictionary) -> StringName: return e["id"])
		_check(is_equal_approx(player.hits[0].amount, 58.5) and ids == [&"knockback", &"wet"],
				"45 x 1.3, knockback and wet %s" % [ids])


func _test_rock_throw() -> void:
	var g := _spawn()
	var player := _player(Vector3(0, 0, -12))
	var areas: Array[Dictionary] = []
	g.telegraph_started.connect(func(area: Dictionary) -> void: areas.append(area))
	g.chase(player)
	g.tick(DT)
	_check(g.casting() != null and g.casting().id == &"rock_throw", "12 m away: rock throw")
	_check(areas.size() == 1 and areas[0]["position"].distance_to(Vector3(0, 0, -12)) < 0.01,
			"the red circle is on the player")
	_tick(g, 1.5)
	_check(player.hits.size() == 1 and (player.hits[0].info["status"] as Array)[0]["id"] == &"stagger",
			"the rock lands and staggers")


func _test_guard() -> void:
	var g := _spawn()
	_cooldown(g, &"wave_slam")
	_cooldown(g, &"rock_throw")
	var player := _player(Vector3(0, 0, -5))
	g.chase(player)
	g.tick(DT)
	_check(g.casting() != null and g.casting().id == &"guard", "guard when the attacks cool down")
	var before := g.hp
	g.take_damage(200.0)
	var open_hit := before - g.hp
	_tick(g, 0.7)
	_check(g.mechanic.get("guarding") == true and g.is_held(), "in its guard stance")
	before = g.hp
	g.take_damage(200.0, {"weapon": &"longsword"})
	var guarded_hit := before - g.hp
	# defense 60 -> 120: factor 100/160 -> 100/220.
	_check(is_equal_approx(guarded_hit / open_hit, 160.0 / 220.0), "guard doubles its defense (%.3f)" % (guarded_hit / open_hit))
	_check(g.mechanic.get("guarding") == true, "a blade does not break the guard")
	_tick(g, 8.3)
	_check(g.mechanic.get("guarding") == false and not g.is_held(), "the guard ends after its time")


func _test_guard_break() -> void:
	var g := _spawn()
	_cooldown(g, &"wave_slam")
	_cooldown(g, &"rock_throw")
	var player := _player(Vector3(0, 0, -5))
	g.chase(player)
	_tick(g, 0.8)
	_check(g.mechanic.get("guarding") == true, "guarding")
	_check(Armory.get_def(&"club") != null and Armory.get_def(&"club").combat_class == Enums.CombatClass.BLUNT,
			"the club is a blunt weapon")
	g.take_damage(50.0, {"weapon": &"club"})
	_check(g.mechanic.get("guarding") == false and not g.is_held(), "a blunt hit breaks the guard")
	_check(g.status.has(&"stagger"), "it staggers when the guard breaks")


func _test_first_kill() -> void:
	FieldState.boss_kills = {}
	GameState.flags.erase(FLAG)
	var boss := BossDef.for_monster(BOSS_ID)
	var table := MonsterDrops.table(boss.first_kill_drop_table_id) if boss else null
	_check(table != null and table.bonus_resources.get(&"generator_core") == 2, "first kill drops 2 generator cores")
	var g := _spawn()
	g.take_damage(100000000.0)
	_check(GameState.has_flag(FLAG), "first kill gives the radio tower blueprint flag")


# --- Helpers --------------------------------------------------------------

func _spawn() -> BossMonster:
	var def := load("res://data/monsters/%s.tres" % BOSS_ID) as MonsterDef
	var g := def.scene.instantiate() as BossMonster
	g.def = def
	g.arena_radius = 20.0
	_root.add_child(g)
	g.set_physics_process(false)
	return g


func _player(pos: Vector3) -> FakeTarget:
	var p := FakeTarget.new()
	p.add_to_group(Monster.PLAYER_GROUP)
	p.position = pos
	_root.add_child(p)
	return p


func _cooldown(g: BossMonster, id: StringName) -> void:
	g._cooldowns[id] = 999.0


func _tick(g: BossMonster, sec: float) -> void:
	for i in roundi(sec / DT):
		g.tick(DT)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("test_boss_golem: " + what)
