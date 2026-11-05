extends RefCounted
## Flooded mall boss: 수술등 망령 (docs/design/04-monsters.md "보스"). Data from the 04 table, flash (orange
## ring, blind 2 s), scalpels (three red lines, one hit each, bleed), clones (two shadowless clones that pop
## on a hit and count as no kill), the blind screen, first kill flag. Ticks are driven by hand.

const DT := 0.1
const BOSS_ID := &"surgical_lamp_wraith"
const FLAG := &"blueprint_infirmary_lv3"

var _root: Node3D
var _ok := true


class FakeTarget extends Node3D:
	var hits: Array[Dictionary] = []

	func take_damage(amount: float, info: Dictionary) -> void:
		hits.append({"amount": amount, "info": info})


func run() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	_root = Node3D.new()
	_root.name = "TestBossWraith"
	tree.root.add_child(_root)
	var saved_kills := FieldState.boss_kills.duplicate()
	var saved_flags := GameState.flags.duplicate()
	var tests: Array[Callable] = [_test_data, _test_flash, _test_scalpels, _test_clones, _test_blind_screen,
		_test_first_kill]
	for test in tests:
		await test.call()
		for child in _root.get_children():
			child.free()
	_root.free()
	FieldState.boss_kills = saved_kills
	GameState.flags = saved_flags
	return _ok


func _test_data() -> void:
	var def := load("res://data/monsters/%s.tres" % BOSS_ID) as MonsterDef
	_check(def != null and def.scene != null, "wraith def and scene load")
	if def == null:
		return
	# 04 "마물 목록": 네온, 보스, 1400 / 20 / 35 / 4.0, 청각 x1.0, 시각 16 m.
	var got := [def.family, def.tier, def.hp, def.defense, def.attack, def.move_speed, def.hearing_mult, def.sight_range]
	_check(got == [Enums.Element.LIGHT, Enums.MonsterTier.BOSS, 1400.0, 20.0, 35.0, 4.0, 1.0, 16.0],
			"wraith matches the 04 table %s" % [got])
	_check(Enums.element_multiplier(Enums.Element.GREEN, Enums.Element.LIGHT) > 1.0, "green beats it (04: 풀 속성)")
	var boss := BossDef.for_monster(BOSS_ID)
	_check(boss != null and boss.mechanic != null and boss.first_kill_flags.has(FLAG), "boss def, mechanic, Lv3 flag")


func _test_flash() -> void:
	var w := _spawn()
	var player := _player(Vector3(0, 0, -5))
	var holder := StatusHolder.attach(player)
	var areas: Array[Dictionary] = []
	w.telegraph_started.connect(func(area: Dictionary) -> void: areas.append(area))
	w.chase(player)
	w.tick(DT)
	_check(w.casting() != null and w.casting().id == &"flash", "5 m away: flash first")
	_check(areas.size() == 1 and areas[0]["kind"] == &"warn", "flash warns with an orange ring")
	_tick(w, 1.3)
	_check(player.hits.is_empty(), "flash deals no damage")
	_check(holder.has(&"blind") and is_equal_approx(holder.time_left(&"blind"), 2.0), "blind for 2 s (04)")
	var safe := _player(Vector3(0, 0, -30))
	var safe_holder := StatusHolder.attach(safe)
	_check(not safe_holder.has(&"blind"), "out of the ring: not blinded")


func _test_scalpels() -> void:
	var w := _spawn()
	_cooldown(w, &"flash")
	var player := _player(Vector3(0, 0, -10))
	var areas: Array[Dictionary] = []
	w.telegraph_started.connect(func(area: Dictionary) -> void: areas.append(area))
	w.chase(player)
	w.tick(DT)
	_check(w.casting() != null and w.casting().id == &"scalpels", "10 m away: scalpels")
	_check(areas.size() == 3 and areas.all(func(a: Dictionary) -> bool: return a["shape"] == &"line"),
			"three red lines %s" % [areas.size()])
	_tick(w, 0.9)
	_check(player.hits.size() == 1, "one hit even where lines meet (%d)" % player.hits.size())
	if player.hits.size() == 1:
		_check(is_equal_approx(player.hits[0].amount, 28.0), "damage = 35 x 0.8")
		_check((player.hits[0].info["status"] as Array)[0]["id"] == &"bleed", "scalpels bleed")


func _test_clones() -> void:
	var w := _spawn()
	_cooldown(w, &"flash")
	_cooldown(w, &"scalpels")
	var player := _player(Vector3(0, 0, -6))
	var kills: Array = []
	var on_kill := func(id: StringName, _f, _p) -> void: kills.append(id)
	EventBus.monster_killed.connect(on_kill)
	w.chase(player)
	w.tick(DT)
	_check(w.casting() != null and w.casting().id == &"clones", "clones when the rest cool down")
	_tick(w, 1.1)
	var decoys: Array = w.mechanic.get("decoys")
	_check(decoys.size() == 2, "two clones (%d)" % decoys.size())
	_check(w.global_position.distance_to(player.global_position) > 4.0, "the real one stands round you too")
	for d in decoys:
		var shadows := true
		for g in (d as Node).find_children("*", "GeometryInstance3D", true, false):
			shadows = shadows and (g as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_check(not shadows, "a clone casts no shadow")
	_check(not w.mechanic.can_use(BossDef.for_monster(BOSS_ID).patterns[2]), "no new clones while two stand")
	(decoys[0] as Monster).take_damage(10.0)
	_check((decoys[0] as Monster).is_dead(), "a clone pops on the first hit")
	EventBus.monster_killed.disconnect(on_kill)
	_check(kills.is_empty(), "a popped clone is no kill")
	_tick(w, 12.1)
	_check(w.mechanic.get("decoys").is_empty(), "clones go after their time")


func _test_blind_screen() -> void:
	var overlay: BlindOverlay = UI.blind_overlay
	_check(overlay != null, "UI has the blind overlay")
	if overlay == null:
		return
	var player := _player(Vector3.ZERO)
	var holder := StatusHolder.attach(player)
	holder.name = StatusHolder.NODE_NAME
	overlay.call(&"_bind")
	holder.apply(&"blind", {"duration": 2.0})
	overlay._process(0.016)
	_check(overlay.darkness() > 0.5, "blind darkens the screen")
	holder.remove(&"blind")
	overlay._process(1.0)
	_check(overlay.darkness() == 0.0, "clears when it wears off")


func _test_first_kill() -> void:
	FieldState.boss_kills = {}
	GameState.flags.erase(FLAG)
	var w := _spawn()
	w.take_damage(1000000.0)
	_check(GameState.has_flag(FLAG), "first kill gives the infirmary Lv3 blueprint flag")


# --- Helpers --------------------------------------------------------------

func _spawn() -> BossMonster:
	var def := load("res://data/monsters/%s.tres" % BOSS_ID) as MonsterDef
	var w := def.scene.instantiate() as BossMonster
	w.def = def
	w.arena_radius = 20.0
	_root.add_child(w)
	w.set_physics_process(false)
	return w


func _player(pos: Vector3) -> FakeTarget:
	var p := FakeTarget.new()
	p.add_to_group(Monster.PLAYER_GROUP)
	p.position = pos
	_root.add_child(p)
	return p


func _cooldown(w: BossMonster, id: StringName) -> void:
	w._cooldowns[id] = 999.0


func _tick(w: BossMonster, sec: float) -> void:
	for i in roundi(sec / DT):
		w.tick(DT)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("test_boss_wraith: " + what)
