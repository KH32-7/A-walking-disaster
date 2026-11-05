extends RefCounted
## Flooded mall boss: 네온 거신 (docs/design/04-monsters.md "보스"). Data from the 04 table, laser (red line,
## shock), shock floor (three circles that stay live), neon moth summon, power cables (cut all three: it shuts
## down, takes more damage, then the cables come back), first kill flag. Ticks are driven by hand.

const DT := 0.1
const BOSS_ID := &"neon_colossus"
const FLAG := &"blueprint_solar"

var _root: Node3D
var _ok := true


class FakeTarget extends Node3D:
	var hits: Array[Dictionary] = []

	func take_damage(amount: float, info: Dictionary) -> void:
		hits.append({"amount": amount, "info": info})


func run() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	_root = Node3D.new()
	_root.name = "TestBossColossus"
	tree.root.add_child(_root)
	var saved_kills := FieldState.boss_kills.duplicate()
	var saved_flags := GameState.flags.duplicate()
	var tests: Array[Callable] = [_test_data, _test_laser, _test_shock_floor, _test_summon, _test_cables,
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
	_check(def != null and def.scene != null, "colossus def and scene load")
	if def == null:
		return
	# 04 "마물 목록": 네온, 보스, 2500 / 30 / 40 / 3.0, 청각 x1.0, 시각 18 m.
	var got := [def.family, def.tier, def.hp, def.defense, def.attack, def.move_speed, def.hearing_mult, def.sight_range]
	_check(got == [Enums.Element.LIGHT, Enums.MonsterTier.BOSS, 2500.0, 30.0, 40.0, 3.0, 1.0, 18.0],
			"colossus matches the 04 table %s" % [got])
	var c := _spawn()
	_check(c.mechanic != null and (c.mechanic.get("cables") as Array).size() == 3, "three power cables")


func _test_laser() -> void:
	var c := _spawn()
	var player := _player(Vector3(0, 0, -10))
	var areas: Array[Dictionary] = []
	c.telegraph_started.connect(func(area: Dictionary) -> void: areas.append(area))
	c.chase(player)
	c.tick(DT)
	_check(c.casting() != null and c.casting().id == &"laser", "10 m away: laser")
	_check(areas.size() == 1 and areas[0]["shape"] == &"line" and is_equal_approx(areas[0]["length"], 18.0),
			"laser marks an 18 m red line")
	_tick(c, 1.3)
	_check(player.hits.size() == 1, "laser lands once")
	if player.hits.size() == 1:
		_check(is_equal_approx(player.hits[0].amount, 52.0), "damage = 40 x 1.3")
		_check((player.hits[0].info["status"] as Array)[0]["id"] == &"shock", "laser shocks")


func _test_shock_floor() -> void:
	var c := _spawn()
	_cooldown(c, &"laser")
	var player := _player(Vector3(0, 0, -6))
	var holder := StatusHolder.attach(player)
	var areas: Array[Dictionary] = []
	c.telegraph_started.connect(func(area: Dictionary) -> void: areas.append(area))
	c.chase(player)
	c.tick(DT)
	_check(c.casting() != null and c.casting().id == &"shock_floor", "laser cooling: shock floor")
	_check(areas.size() == 3 and areas.all(func(a: Dictionary) -> bool: return a["shape"] == &"circle"),
			"three red circles (%d)" % areas.size())
	_check(areas.size() > 0 and areas[0]["position"].distance_to(Vector3(0, 0, -6)) < 0.01, "one on the player")
	_tick(c, 1.1)
	_check(player.hits.size() == 1, "the floor hits once on landing (%d)" % player.hits.size())
	holder.remove(&"shock")
	_tick(c, 0.6)
	_check(holder.has(&"shock"), "standing on the live floor keeps shocking")
	_check((c.mechanic.get("_zones") as Array).size() == 3, "three live circles")
	_tick(c, 4.0)
	_check((c.mechanic.get("_zones") as Array).is_empty(), "the floor goes out after its time")


func _test_summon() -> void:
	var c := _spawn()
	_cooldown(c, &"laser")
	_cooldown(c, &"shock_floor")
	var player := _player(Vector3(0, 0, -8))
	c.chase(player)
	c.tick(DT)
	_check(c.casting() != null and c.casting().id == &"summon_moths", "summons moths when the rest cool down")
	_tick(c, 1.1)
	var moths := 0
	for child in _root.get_children():
		if child is Monster and not child is BossMonster and (child as Monster).def.id == &"neon_moth":
			moths += 1
	_check(moths == 2, "two neon moths (%d)" % moths)


func _test_cables() -> void:
	var c := _spawn()
	var m := c.mechanic
	var cables: Array = m.get("cables")
	var player := _player(Vector3(0, 0, -10))
	c.chase(player)
	c.tick(DT)
	_check(c.casting() != null, "it is mid-pattern")
	for i in cables.size():
		var cable := cables[i] as PowerCable
		cable.take_damage(100.0, {"element": Enums.Element.NONE})
		_check(not cable.cut, "100 is not enough for a cable")
		cable.take_damage(100.0, {"element": Enums.Element.NONE})
		_check(cable.cut, "cable %d cut" % i)
		if i < cables.size() - 1:
			_check(not m.call(&"is_stunned"), "still running with a cable left")
	_check(m.call(&"is_stunned") and c.is_held() and c.casting() == null, "all three cut: shut down mid-pattern")
	var before := c.hp
	c.take_damage(100.0)
	var stunned_hit := before - c.hp
	_tick(c, 6.2)
	_check(not m.call(&"is_stunned") and not c.is_held(), "back up after the stun")
	_check(cables.all(func(x: Variant) -> bool: return not (x as PowerCable).cut), "cables come back")
	before = c.hp
	c.take_damage(100.0)
	_check(stunned_hit > (before - c.hp) * 1.4, "takes more damage while shut down")
	var green := cables[0] as PowerCable
	green.take_damage(110.0, {"element": Enums.Element.GREEN})
	_check(green.cut, "green beats neon on the cables too (110 x 1.5 > 150)")


func _test_first_kill() -> void:
	FieldState.boss_kills = {}
	GameState.flags.erase(FLAG)
	var c := _spawn()
	c.take_damage(10000000.0)
	_check(GameState.has_flag(FLAG), "first kill gives the solar panel blueprint flag")


# --- Helpers --------------------------------------------------------------

func _spawn() -> BossMonster:
	var def := load("res://data/monsters/%s.tres" % BOSS_ID) as MonsterDef
	var c := def.scene.instantiate() as BossMonster
	c.def = def
	c.arena_radius = 20.0
	_root.add_child(c)
	c.set_physics_process(false)
	return c


func _player(pos: Vector3) -> FakeTarget:
	var p := FakeTarget.new()
	p.add_to_group(Monster.PLAYER_GROUP)
	p.position = pos
	_root.add_child(p)
	return p


func _cooldown(c: BossMonster, id: StringName) -> void:
	c._cooldowns[id] = 999.0


func _tick(c: BossMonster, sec: float) -> void:
	for i in roundi(sec / DT):
		c.tick(DT)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("test_boss_colossus: " + what)
