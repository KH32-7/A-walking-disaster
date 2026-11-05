extends RefCounted
## B-19: boss common rules and the ancient tree giant. Ticks are driven by hand.
## Data (04 table), telegraph shapes, patterns (slam, root burst, spore pod summon), phases,
## arena leash, out-of-combat recovery, first kill reward, drops, 3-day respawn, spawner, HUD key.
## Respawn days are kept per boss (old per-region saves are moved over). BossMechanic hooks and hold().

const DT := 0.1
const BOSS_ID := &"ancient_tree_giant"
const FLAG := &"blueprint_essence_workshop"
const PARK := "res://levels/field/city_park/city_park.tscn"

var _root: Node3D
var _ok := true
var _saved_kills: Dictionary
var _saved_respawn: Dictionary
var _saved_flags: Dictionary


## Records the BossMechanic hooks; runs `action` patterns itself and ignores hits while `immune`.
class FakeMechanic extends BossMechanic:
	var calls: Array[StringName] = []
	var immune := false
	var landed: Array[StringName] = []

	func on_added() -> void:
		calls.append(&"added")

	func can_use(pattern: BossPattern) -> bool:
		return pattern.id != &"root_burst"

	func on_pattern_started(pattern: BossPattern, _area: Dictionary) -> void:
		calls.append(StringName("start_%s" % pattern.id))

	func land_pattern(pattern: BossPattern, _area: Dictionary) -> bool:
		if pattern.action == &"":
			return false
		landed.append(pattern.action)
		boss.hold(2.0)
		return true

	func filter_damage(amount: float, _info: Dictionary) -> float:
		return 0.0 if immune else amount

	func on_phase_changed(phase: int) -> void:
		calls.append(StringName("phase_%d" % phase))

	func on_died() -> void:
		calls.append(&"died")


class FakeTarget extends Node3D:
	var hits: Array[Dictionary] = []

	func take_damage(amount: float, info: Dictionary) -> void:
		hits.append({"amount": amount, "info": info})


func run() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	_root = Node3D.new()
	_root.name = "TestBoss"
	tree.root.add_child(_root)
	_saved_kills = FieldState.boss_kills.duplicate()
	_saved_respawn = FieldState.boss_respawn_day.duplicate()
	_saved_flags = GameState.flags.duplicate()
	var saved_day := GameState.day
	var tests: Array[Callable] = [
		_test_data,
		_test_area_shapes,
		_test_slam,
		_test_slam_dodged,
		_test_root_burst,
		_test_summon,
		_test_phase,
		_test_leash,
		_test_recovery,
		_test_first_kill,
		_test_second_kill_table,
		_test_spawner_respawn,
		_test_first_day,
		_test_bosses_per_day,
		_test_intro,
		_test_park_wiring,
		_test_hud,
		_test_save,
		_test_mechanic,
	]
	for test in tests:
		FieldState.boss_kills = {}
		FieldState.boss_respawn_day = {}
		GameState.day = saved_day
		await test.call()
		for child in _root.get_children():
			child.free()
	_root.free()
	GameState.day = saved_day
	FieldState.boss_kills = _saved_kills
	FieldState.boss_respawn_day = _saved_respawn
	GameState.flags = _saved_flags
	return _ok


# --- Tests ----------------------------------------------------------------

func _test_data() -> void:
	var def := load("res://data/monsters/ancient_tree_giant.tres") as MonsterDef
	_check(def != null, "ancient tree giant def loads")
	if def == null:
		return
	# 04 "마물 목록": 수풀, 보스, 600 / 20 / 30 / 2.5, 청각 x1.0, 시각 12 m.
	var got := [def.family, def.tier, def.hp, def.defense, def.attack, def.move_speed, def.hearing_mult, def.sight_range]
	_check(got == [Enums.Element.GREEN, Enums.MonsterTier.BOSS, 600.0, 20.0, 30.0, 2.5, 1.0, 12.0],
			"giant matches the 04 table %s" % [got])
	_check(def.weak_point_shape == MonsterDef.WeakPointShape.PETAL, "green core is a petal")
	var boss := BossDef.for_monster(BOSS_ID)
	_check(boss != null and boss.monster_id == BOSS_ID, "boss def loads")
	if boss == null:
		return
	_check(boss.phases == [0.5] and boss.respawn_days == 3, "phase 2 at 50%, respawn after 3 days")
	_check(boss.first_kill_flags.has(FLAG), "first kill gives the essence workshop blueprint flag")
	var essence_workshop := load("res://data/buildings/essence_workshop.tres")
	_check(essence_workshop != null and (essence_workshop.get(&"requires_flags") as Array).has(FLAG),
			"the essence workshop building needs that flag (Lane C data)")
	var ids: Array[StringName] = []
	for p in boss.patterns:
		ids.append(p.id)
		_check(is_equal_approx(p.windup_sec, 1.0), "%s warns 1 s before (04)" % p.id)
		if not p.is_summon():
			_check(p.shape in [&"circle", &"cone", &"line", &"ring"], "%s shape is a Fx boss_telegraph shape" % p.id)
	_check(ids == [&"slam", &"root_burst", &"summon_pods"], "patterns: slam, root burst, spore pod summon (04)")
	var giant := _spawn()
	_check(giant is BossMonster and giant.boss == boss, "scene root is a BossMonster with its BossDef")
	var core := giant.get_node_or_null(^"WeakPoint") as Node3D
	_check(core is MonsterWeakPoint and core.position.z > 0.5, "the flower core is on the back (+Z)")


func _test_area_shapes() -> void:
	var circle := {"shape": &"circle", "position": Vector3(1, 0, 1), "radius": 2.0}
	_check(BossMonster.area_contains(circle, Vector3(2, 5, 2)), "circle: inside (height ignored)")
	_check(not BossMonster.area_contains(circle, Vector3(4, 0, 1)), "circle: outside")
	var ring := {"shape": &"ring", "position": Vector3.ZERO, "radius": 4.0, "inner": 2.0}
	_check(BossMonster.area_contains(ring, Vector3(3, 0, 0)) and not BossMonster.area_contains(ring, Vector3(1, 0, 0)),
			"ring: hits between inner and radius only")
	var cone := {"shape": &"cone", "position": Vector3.ZERO, "radius": 5.0, "angle_deg": 60.0, "direction": Vector3.FORWARD}
	_check(BossMonster.area_contains(cone, Vector3(1, 0, -3)), "cone: inside the angle")
	_check(not BossMonster.area_contains(cone, Vector3(3, 0, -1)), "cone: outside the angle")
	var line := {"shape": &"line", "position": Vector3.ZERO, "length": 10.0, "width": 2.0, "direction": Vector3.RIGHT}
	_check(BossMonster.area_contains(line, Vector3(9, 0, 0.9)), "line: inside")
	_check(not BossMonster.area_contains(line, Vector3(-1, 0, 0)), "line: behind the origin")
	_check(not BossMonster.area_contains(line, Vector3(5, 0, 1.5)), "line: beside it")


func _test_slam() -> void:
	var giant := _spawn()
	var player := _player(Vector3(0, 0, -2))
	var areas: Array[Dictionary] = []
	giant.telegraph_started.connect(func(area: Dictionary) -> void: areas.append(area))
	giant.chase(player)
	giant.tick(DT)
	_check(giant.casting() != null and giant.casting().id == &"slam", "target 2 m away: slam")
	_check(areas.size() == 1 and areas[0]["shape"] == &"circle" and areas[0]["kind"] == &"danger",
			"slam marks a red circle on the ground")
	if areas.size() == 1:
		_check(areas[0]["position"].distance_to(Vector3(0, 0, -2.5)) < 0.01, "slam circle is in front of the boss")
	_tick(giant, 0.9)
	_check(player.hits.is_empty(), "nothing lands before the 1 s warning ends")
	_tick(giant, 0.3)
	_check(player.hits.size() == 1, "slam lands once after 1 s")
	if player.hits.size() == 1:
		var hit: Dictionary = player.hits[0]
		_check(is_equal_approx(hit.amount, 45.0), "slam damage = attack 30 x 1.5 (%.1f)" % hit.amount)
		_check((hit.info["status"] as Array)[0]["id"] == &"knockback", "slam knocks back")
		_check(hit.info["element"] == Enums.Element.GREEN, "green element")
	_check(giant.casting() == null, "windup over")


func _test_slam_dodged() -> void:
	var giant := _spawn()
	var player := _player(Vector3(0, 0, -2))
	giant.chase(player)
	giant.tick(DT)
	player.position = Vector3(8, 0, 0)  # walked out during the warning
	_tick(giant, 1.2)
	_check(player.hits.is_empty(), "leaving the marked area dodges the slam")


func _test_root_burst() -> void:
	var giant := _spawn()
	var player := _player(Vector3(0, 0, -8))
	var areas: Array[Dictionary] = []
	giant.telegraph_started.connect(func(area: Dictionary) -> void: areas.append(area))
	giant.chase(player)
	giant.tick(DT)
	_check(giant.casting() != null and giant.casting().id == &"root_burst", "target 8 m away: root burst")
	_check(areas.size() == 1 and areas[0]["shape"] == &"line", "root burst marks a line toward the target")
	_tick(giant, 1.2)
	_check(player.hits.size() == 1, "root burst hits along the line")
	if player.hits.size() == 1:
		_check(is_equal_approx(player.hits[0].amount, 30.0), "root burst damage = attack 30")
		_check((player.hits[0].info["status"] as Array)[0]["id"] == &"bind", "root burst binds (green)")


func _test_summon() -> void:
	var giant := _spawn()
	giant.arena_radius = 18.0
	var player := _player(Vector3(0, 0, -3))
	var started: Array[StringName] = []
	giant.pattern_started.connect(func(id: StringName) -> void: started.append(id))
	giant.chase(player)
	giant._cooldowns[&"slam"] = 99.0
	giant.tick(DT)
	_check(started == [&"summon_pods"] and giant.casting().shape == &"", "summon has no ground area")
	_tick(giant, 1.2)
	var pods := _pods()
	_check(pods.size() == 2, "2 spore pods summoned (%d)" % pods.size())
	for pod in pods:
		_check(pod.drop_mult == 0.0, "summons drop nothing")
		_check(pod.target == player, "summons start on the boss's target")
		var flat := Vector2(pod.global_position.x, pod.global_position.z)
		_check(flat.length() <= 17.0 + 0.01, "summon stays inside the arena")
	for i in 2:
		giant._cooldowns[&"summon_pods"] = 0.0
		giant._gap = 0.0
		giant.tick(DT)
		_tick(giant, 1.2)
	_check(_pods().size() == 4, "at most 4 summons alive (%d)" % _pods().size())


func _test_phase() -> void:
	var giant := _spawn()
	var phases: Array[int] = []
	giant.phase_changed.connect(func(p: int) -> void: phases.append(p))
	giant.hp = giant.max_hp * 0.55
	giant.take_damage(0.1)
	_check(phases.is_empty() and giant.phase == 1, "still phase 1 above 50%")
	giant.hp = giant.max_hp * 0.5 + 0.05
	giant.take_damage(1.0)
	_check(phases == [2] and giant.phase == 2, "phase 2 at 50%")
	giant.hp = giant.max_hp * 0.8
	giant.take_damage(0.1)
	_check(giant.phase == 2, "healing mid-fight does not undo phase 2")
	var player := _player(Vector3(0, 0, -2))
	giant.chase(player)
	giant.tick(DT)
	_check(is_equal_approx(giant._cooldowns[&"slam"], 4.0 / 1.5), "phase 2 patterns come 1.5x faster")


func _test_leash() -> void:
	var giant := _spawn()
	giant.arena_radius = 18.0
	var player := _player(Vector3(0, 0, -30))
	giant.chase(player)
	giant.position = Vector3(0, 0, -18.5)
	giant._cooldowns[&"root_burst"] = 99.0
	giant._cooldowns[&"summon_pods"] = 99.0
	giant.tick(DT)
	_check(giant.state == Enums.AIState.RETURN, "past the arena edge the boss goes home")
	giant.take_damage(1.0, {"source": player})
	_check(giant.state == Enums.AIState.RETURN, "hits do not pull it back out while returning")


func _test_recovery() -> void:
	var giant := _spawn()
	var player := _player(Vector3(0, 0, -3))
	giant.chase(player)
	giant._cooldowns[&"slam"] = 99.0
	giant.tick(DT)
	_tick(giant, 1.2)
	_check(_pods().size() == 2, "summons out before the reset")
	giant.hp = giant.max_hp * 0.4
	giant.take_damage(1.0)
	_check(giant.phase == 2, "phase 2 before the reset")
	player.free()
	giant._set_state(Enums.AIState.WANDER)
	_tick(giant, 5.0)
	_check(giant.hp < giant.max_hp and giant.phase == 2, "recovering out of combat, 5% per second")
	_tick(giant, 10.0)
	_check(is_equal_approx(giant.hp, giant.max_hp), "back to full hp")
	_check(giant.phase == 1 and giant._cooldowns.is_empty(), "full hp resets the fight to phase 1")
	_check(_pods().is_empty(), "its summons vanish on the reset")


func _test_first_kill() -> void:
	GameState.flags.erase(FLAG)
	var notes: Array[String] = []
	var on_note := func(text: String, _severity: StringName) -> void: notes.append(text)
	EventBus.notification_posted.connect(on_note)
	var giant := _spawn()
	giant.region_id = &"city_park"
	var defeated: Array[bool] = []
	giant.defeated.connect(func(first: bool) -> void: defeated.append(first))
	giant.take_damage(100000.0)
	EventBus.notification_posted.disconnect(on_note)
	_check(defeated == [true], "defeated as a first kill")
	_check(GameState.has_flag(FLAG), "first kill sets blueprint_essence_workshop")
	_check(FieldState.boss_kill_count(BOSS_ID) == 1, "kill counted")
	_check(FieldState.boss_respawn_day.get(BOSS_ID) == GameState.day + 3, "park boss back in 3 days")
	_check(notes.size() == 1 and notes[0].contains("정수 공방 설계도"), "first kill notice %s" % [notes])
	await (Engine.get_main_loop() as SceneTree).process_frame
	var pile := _pile()
	_check(pile != null, "boss leaves a drop pile")
	if pile:
		var res := pile.resources
		_check(res.get(&"essence_green_high") == 3, "3 high green essences (04 드롭) %s" % [res])
		_check(res.get(&"vine_fiber") == 5 and res.get(&"rare_parts") == 1, "5 vine fiber + 1 rare part")
		_check(pile.gear.is_empty(), "first kill: no gear roll, the blueprint is the reward")


func _test_second_kill_table() -> void:
	FieldState.boss_kills = {BOSS_ID: 1}
	GameState.flags.erase(FLAG)
	var giant := _spawn()
	var defeated: Array[bool] = []
	giant.defeated.connect(func(first: bool) -> void: defeated.append(first))
	_check(MonsterDrops.table_for(giant).id == &"monster_boss", "later kills use the boss table")
	var table := MonsterDrops.table(&"monster_boss")
	_check(is_equal_approx(table.gear_chance, 0.3) and table.gear_rarity_weights.slice(0, 3) == [0.0, 0.0, 0.0],
			"later kills: 30% gear, epic or better (04 드롭)")
	giant.take_damage(100000.0)
	_check(defeated == [false] and not GameState.has_flag(FLAG), "no first-kill reward the second time")
	_check(FieldState.boss_kill_count(BOSS_ID) == 2, "second kill counted")


func _test_spawner_respawn() -> void:
	var arena := _arena(BOSS_ID, Vector3(40, 0, 0))
	var spawner := _spawner(&"test_region")
	GameState.day = BossDef.for_monster(BOSS_ID).first_day
	spawner.spawn_all()
	var giant := spawner.boss_at(arena)
	_check(giant != null, "spawner puts the boss at the arena")
	if giant == null:
		return
	_check(giant.global_position.distance_to(arena.global_position) < 0.01, "at the arena center")
	_check(giant.state == Enums.AIState.SLEEP, "asleep until woken")
	_check(is_equal_approx(giant.arena_radius, 12.0) and giant.home == arena.global_position, "arena is its leash")
	giant.free()
	FieldState.record_boss_kill(&"test_region", BOSS_ID, GameState.day + 3)
	spawner.spawn_all()
	_check(spawner.boss_at(arena) == null, "no boss before the respawn day")
	_check(FieldState.boss_ready(&"sunken_sign_serpent"), "the day is kept per boss: another boss of the region is up")
	FieldState.boss_respawn_day[BOSS_ID] = GameState.day
	spawner.spawn_all()
	_check(spawner.boss_at(arena) != null, "boss is back on the respawn day")


func _test_first_day() -> void:
	var first := BossDef.for_monster(BOSS_ID).first_day
	_check(first > 1, "the park boss does not show up on day 1 (first_day %d)" % first)
	var arena := _arena(BOSS_ID, Vector3(40, 0, 0))
	var spawner := _spawner(&"test_region")
	GameState.day = first - 1
	spawner.spawn_all()
	_check(spawner.boss_at(arena) == null, "no boss before its first day")
	GameState.day = first
	spawner.spawn_all()
	_check(spawner.boss_at(arena) != null, "the boss is out from its first day")


func _test_bosses_per_day() -> void:
	var mall := _spawner(&"flooded_mall")
	var arenas: Array[BossArena] = []
	for id: StringName in [&"sunken_sign_serpent", &"surgical_lamp_wraith", &"neon_colossus", &"breakwater_golem"]:
		arenas.append(_arena(id, Vector3(40, 0, 0)))
	var picked := mall.todays(arenas, 20)
	_check(picked.size() == RegionDef.load_def(&"flooded_mall").bosses_per_day, "the mall puts bosses_per_day out")
	_check(mall.todays(arenas, 20) == picked, "same day, same boss")
	var reversed := arenas.duplicate()
	reversed.reverse()
	_check(mall.todays(reversed, 20) == picked, "the pick does not depend on the arena order")
	var seen := {}
	for day in range(12, 40):
		for arena in mall.todays(arenas, day):
			seen[arena.boss_id] = true
	_check(seen.size() >= 3, "other days bring out other bosses (%d seen)" % seen.size())
	_check(_spawner(&"city_park").todays(arenas, 20).size() == arenas.size(), "bosses_per_day 0 = every arena")
	# Today's boss killed: its arena stays empty and no other boss takes its place.
	GameState.day = 20
	for arena in picked:
		FieldState.boss_respawn_day[arena.boss_id] = 23
	mall.spawn_all()
	_check(arenas.all(func(a: BossArena) -> bool: return mall.boss_at(a) == null),
			"killing today's boss does not bring out another one the same day")


func _test_intro() -> void:
	GameState.day = BossDef.for_monster(BOSS_ID).first_day
	var arena := _arena(BOSS_ID, Vector3.ZERO)
	var spawner := _spawner(&"test_region")
	spawner.spawn_all()
	var giant := spawner.boss_at(arena)
	_check(giant != null, "intro: spawner puts the giant out")
	if giant == null:
		return
	giant.set_physics_process(false)
	_check(giant.is_buried() and giant.state == Enums.AIState.SLEEP, "spawned asleep: buried")
	var visual := giant.get_node_or_null(^"Visual") as MonsterVisual
	var model := giant.get_node_or_null(^"Visual/Model") as Node3D
	if model:
		_check(model.position.y < visual.model_offset.y - 0.5, "only its top shows (model at %.2f)" % model.position.y)
	var woke := [false]
	giant.woke.connect(func() -> void: woke[0] = true)
	var player := _player(Vector3(0, 0, -3))
	giant.take_damage(10.0, {"source": player})
	_check(not giant.is_buried() and giant.is_in_intro() and giant.is_held(), "the first hit wakes it into the intro")
	var hp := giant.hp
	giant.take_damage(100.0, {"source": player})
	_check(is_equal_approx(giant.hp, hp), "hits are ignored while it climbs out")
	_tick(giant, 0.5)
	_check(giant.casting() == null, "no pattern during the intro")
	_check(not woke[0], "still climbing out")
	_tick(giant, MonsterRules.BOSS_RISE_SEC - 0.5 + DT)
	_check(woke[0], "woke fires once it has climbed out")
	if model:
		_check(absf(model.position.y - visual.model_offset.y) < 0.01, "model back on the ground (%.2f)" % model.position.y)
	_tick(giant, MonsterRules.BOSS_INTRO_SEC - MonsterRules.BOSS_RISE_SEC)
	_check(not giant.is_in_intro() and not giant.is_held(), "the intro ends")
	giant.take_damage(10.0, {"source": player})
	_check(giant.hp < hp, "hits land after the intro")
	var awake := _spawn()
	_check(not awake.is_buried(), "a boss not spawned asleep is not buried")


func _test_park_wiring() -> void:
	var state := (load(PARK) as PackedScene).get_state()
	var found := false
	for i in state.get_node_count():
		if state.get_node_name(i) != &"BossSpawner":
			continue
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == &"region_id":
				found = state.get_node_property_value(i, p) == &"city_park"
	_check(found, "city_park.tscn has a BossSpawner for city_park")


func _test_hud() -> void:
	var giant := _spawn()
	giant.arena_radius = 18.0
	giant.start_state = Enums.AIState.SLEEP
	giant._set_state(Enums.AIState.SLEEP)
	var player := _player(Vector3(0, 0, -5))
	_check(BossMonster.hud_for(player).is_empty(), "no boss bar while it sleeps")
	giant.chase(player)
	var hud := BossMonster.hud_for(player)
	_check(hud.get("name") == "고목 거인" and hud.get("hp_max") == 600.0 and hud.get("phase") == 1
			and hud.get("phase_count") == 2, "boss bar data while fighting %s" % [hud])
	player.position = Vector3(0, 0, -40)
	_check(BossMonster.hud_for(player).is_empty(), "no boss bar far from its arena")


func _test_save() -> void:
	FieldState.record_boss_kill(&"city_park", BOSS_ID, 9)
	var data := FieldState.save_data()
	FieldState.load_data({})
	_check(FieldState.boss_kill_count(BOSS_ID) == 0 and FieldState.boss_ready(BOSS_ID), "new game: no kills")
	FieldState.load_data(data)
	_check(FieldState.boss_kill_count(BOSS_ID) == 1 and FieldState.boss_respawn_day.get(BOSS_ID) == 9,
			"kills and respawn day survive a save")
	FieldState.load_data({"boss_respawn_day": {&"city_park": 11}})
	_check(FieldState.boss_respawn_day == {BOSS_ID: 11}, "an old per-region day moves to the region's boss %s"
			% [FieldState.boss_respawn_day])


func _test_mechanic() -> void:
	var def := load("res://data/monsters/ancient_tree_giant.tres") as MonsterDef
	var data := BossDef.for_monster(BOSS_ID).duplicate() as BossDef
	data.mechanic = FakeMechanic
	var special := BossPattern.new()
	special.id = &"special"
	special.action = &"dive"
	special.range_max = 20.0
	special.shape = &""
	var patterns: Array[BossPattern] = [special]
	patterns.append_array(data.patterns)
	data.patterns = patterns
	var giant := def.scene.instantiate() as BossMonster
	giant.def = def
	giant.boss = data
	_root.add_child(giant)
	giant.set_physics_process(false)
	var m := giant.mechanic as FakeMechanic
	_check(m != null and m.calls == [&"added"], "BossDef.mechanic is made and told it was added")
	if m == null:
		return
	var player := _player(Vector3(0, 0, -8))
	giant.chase(player)
	giant.tick(DT)
	_check(giant.casting() != null and giant.casting().id == &"special", "action pattern starts like any other")
	_check(m.calls.has(&"start_special"), "mechanic hears the windup")
	_tick(giant, 1.1)
	_check(m.landed == [&"dive"] and player.hits.is_empty(), "mechanic lands the action, no common hit")
	_check(giant.is_held(), "hold() hands the body to the mechanic")
	_tick(giant, 1.0)
	_check(giant.is_held() and giant.casting() == null, "no pattern while held")
	_tick(giant, 1.2)
	_check(not giant.is_held(), "the hold ends")
	_tick(giant, 0.2)
	_check(giant.casting() == null or giant.casting().id != &"root_burst", "can_use() false skips root burst")
	m.immune = true
	giant.take_damage(1000.0)
	_check(is_equal_approx(giant.hp, giant.max_hp), "filter_damage 0 ignores the hit")
	m.immune = false
	giant.take_damage(400.0)
	_check(m.calls.has(&"phase_2"), "mechanic hears the phase change")
	giant.take_damage(100000.0)
	_check(m.calls.back() == &"died", "mechanic hears the death")


# --- Helpers --------------------------------------------------------------

func _spawn() -> BossMonster:
	var def := load("res://data/monsters/ancient_tree_giant.tres") as MonsterDef
	var giant := def.scene.instantiate() as BossMonster
	giant.def = def
	_root.add_child(giant)
	giant.set_physics_process(false)  # tests drive tick() by hand
	return giant


func _arena(boss_id: StringName, pos: Vector3) -> BossArena:
	var arena := (load("res://field/markers/boss_arena.tscn") as PackedScene).instantiate() as BossArena
	arena.boss_id = boss_id
	arena.radius = 12.0
	arena.position = pos
	_root.add_child(arena)
	return arena


func _spawner(region: StringName) -> BossSpawner:
	var spawner := BossSpawner.new()
	spawner.region_id = region
	_root.add_child(spawner)
	spawner.set_process(false)
	return spawner


func _player(pos: Vector3) -> FakeTarget:
	var p := FakeTarget.new()
	p.add_to_group(Monster.PLAYER_GROUP)
	p.position = pos
	_root.add_child(p)
	return p


func _tick(giant: BossMonster, sec: float) -> void:
	for i in roundi(sec / DT):
		giant.tick(DT)


func _pods() -> Array[Monster]:
	var out: Array[Monster] = []
	for child in _root.get_children():
		if child is Monster and not child is BossMonster and not (child as Monster).is_dead() \
				and (child as Monster).def.id == &"spore_pod":
			out.append(child)
	return out


func _pile() -> MonsterDropPile:
	for child in _root.get_children():
		if child is MonsterDropPile:
			return child
	return null


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("test_boss: " + what)
