extends Node
## B-13: class data, passive gates and mastery XP (pure), then every skill on a real player and
## real monsters: precision shot (x2.5 + pierce), suppressive fire (auto fire, slow, 25 m noise),
## dash slash, shadow step (unseen, silent steps, first attack x3), slam, brace, passives,
## mastery M in the damage formula, mastery XP (sub weapon 50%), HUD skills, companion Q.
## Player, monster and companion physics are off; the test drives WeaponHolder / ClassSkills.step().

const DT := 1.0 / 60.0
const EPS := 0.01
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const COMPANION_SCENE := preload("res://field/companion/field_companion.tscn")
const VINE_DEF := preload("res://data/monsters/vine_tendril.tres")
const TEST_HP := 10000.0

var _ok := true
var _created: Array[StringName] = []
var _previous := {}
var _noises: Array[float] = []


class World:
	var root: Node3D
	var player: Player
	var holder: WeaponHolder
	var skills: ClassSkills


func run() -> bool:
	_ok = true
	var progression_before := Progression.save_data().duplicate(true)
	var colony_before := Colony.save_data()
	var phase_before := GameState.phase
	EventBus.noise_emitted.connect(_on_noise)
	_remember_loadout()

	_test_data()
	_test_passive_gates()
	_test_mastery_xp_rule()
	await _test_mastery_in_damage()
	await _test_precision_shot()
	await _test_suppressive_fire()
	await _test_dash_slash()
	await _test_shadow_step()
	await _test_slam()
	await _test_brace()
	await _test_passives()
	await _test_mastery_from_hits()
	await _test_hud_and_disabled_e()
	await _test_companion_q()

	_restore_loadout()
	EventBus.noise_emitted.disconnect(_on_noise)
	GameState.set_phase(phase_before)
	Colony.load_data(colony_before)
	Progression.load_data(progression_before)
	return _ok


# --- Pure -------------------------------------------------------------------

func _test_data() -> void:
	var want := {
		Enums.CombatClass.GUN: [&"precision_shot", 10.0, &"suppressive_fire", 15.0],
		Enums.CombatClass.BLADE: [&"dash_slash", 8.0, &"shadow_step", 20.0],
		Enums.CombatClass.BLUNT: [&"slam", 10.0, &"brace", 18.0],
	}
	for c: int in want:
		var def := ClassDef.for_class(c)
		_expect(def != null and def.id == c, "class %d loads" % c)
		if def == null:
			continue
		_expect(def.skill_q.id == want[c][0] and is_equal_approx(def.skill_q.cooldown_sec, want[c][1]), "Q of %d" % c)
		_expect(def.skill_e.id == want[c][2] and is_equal_approx(def.skill_e.cooldown_sec, want[c][3]), "E of %d" % c)
		_expect(not def.weapon_types.is_empty() and def.passive_5 != &"" and def.passive_10 != &"", "passives of %d" % c)
		for def_id in def.weapon_types:
			var item := Armory.get_def(def_id)
			_expect(item != null and item.combat_class == c, "%s is family %d" % [def_id, c])
	_expect(ClassDef.for_class(-1) == null, "no main weapon, no class")
	var gun := ClassDef.for_class(Enums.CombatClass.GUN)
	_expect_near(gun.skill_q.cooldown_for({"aim_cooldown_mult": 0.5}), 5.0, "sniper rifle precision cooldown -50%")
	_expect_near(gun.skill_q.cooldown_for({}), 10.0, "other guns 10 s")


func _test_passive_gates() -> void:
	var gun := ClassDef.for_class(Enums.CombatClass.GUN)
	_expect_near(gun.passive_value(&"reload_fast", 4), 0.0, "reload passive locked at 4")
	_expect_near(gun.passive_value(&"reload_fast", 5), 0.25, "reload -25% at 5")
	_expect_near(gun.passive_value(&"weak_point_bonus", 9), 0.0, "weak point locked at 9")
	_expect_near(gun.passive_value(&"weak_point_bonus", 10), 0.3, "weak point +30% at 10")
	_expect_near(gun.passive_value(&"backstab_bonus", 10), 0.0, "other class's passive is 0")


func _test_mastery_xp_rule() -> void:
	_expect_near(ClassMastery.xp_for(20.0, false, false), 2.0, "20 damage = 2 xp")
	_expect_near(ClassMastery.xp_for(20.0, true, false), 7.0, "kill +5")
	_expect_near(ClassMastery.xp_for(20.0, true, true), 3.5, "sub weapon 50%")
	Progression.load_data({})
	var m := ClassMastery.new()
	m.gain(Enums.CombatClass.BLADE, 5.0, false, false)  # 0.5 xp: kept
	_expect(Progression.mastery_xp(Enums.CombatClass.BLADE) == 0, "fraction kept back")
	m.gain(Enums.CombatClass.BLADE, 5.0, false, false)  # 1.0 total
	_expect(Progression.mastery_xp(Enums.CombatClass.BLADE) == 1, "whole point sent to Progression")
	var need := Progression.mastery_xp_to_next(1)
	_expect(m.gain(Enums.CombatClass.BLADE, float(need) * 10.0, false, false) == 2, "level 2 reached")
	_expect(Progression.mastery_level(Enums.CombatClass.GUN) == 1, "classes stay separate")


# --- In the world -----------------------------------------------------------

func _test_mastery_in_damage() -> void:
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	var monster := await _monster(w, Vector3(0, 0, -3))
	_set_mastery({"GUN": 1})
	var low := _shot_damage(w, monster)
	# 9, not 10: the shot hits the vine's front core and gun mastery 10 adds weak point +30%.
	_set_mastery({"GUN": 9})
	var high := _shot_damage(w, monster)
	_expect_near(high / low, 1.27 / 1.03, "mastery 9 vs 1 = (1 + 0.27) / (1 + 0.03)", 0.001)
	_set_mastery({"GUN": 10})
	_expect_near(_shot_damage(w, monster) / low, 1.3 * 1.3 / 1.03, "mastery 10 + weak point passive", 0.001)
	w.root.free()


func _test_precision_shot() -> void:
	_set_mastery({})
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	var front := await _monster(w, Vector3(0, 0, -3))
	var back := await _monster(w, Vector3(0, 0, -6))
	var normal := _shot_damage(w, front)
	_expect(back.hp == TEST_HP, "a normal shot stops at the first monster")
	_expect(w.skills.use(&"q"), "precision shot used")
	_expect(not w.skills.use(&"q"), "cooling down")
	_advance(w, 1.0)
	_expect_near(_shot_damage(w, front), normal, "still focusing: normal shot")
	_advance(w, 1.1)
	_expect(w.holder.shot_pierces, "armed after 2 s")
	var before_back := back.hp
	_expect_near(_shot_damage(w, front), normal * 2.5, "armed shot x2.5")
	_expect_near(before_back - back.hp, normal * 2.5, "and it pierces to the second monster")
	_expect(not w.holder.shot_pierces, "one shot only")
	_expect_near(_shot_damage(w, front), normal, "next shot is normal again")
	w.root.free()


func _test_suppressive_fire() -> void:
	_set_mastery({})
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	var monster := await _monster(w, Vector3(0, 0, -4))
	_noises.clear()
	var rounds := w.holder.ammo_in_magazine()
	_expect(w.skills.use(&"e"), "suppressive fire used")
	_advance(w, 1.0)
	_expect(w.holder.ammo_in_magazine() < rounds - 1, "fires on its own")
	_expect(monster.status.has(&"slow"), "hit monster slowed")
	_expect_near(monster.status.move_mult(), 0.6, "move -40%")
	_expect(_noises.has(25.0), "25 m noise")
	_advance(w, 2.5)
	var left := w.holder.ammo_in_magazine()
	_advance(w, 1.0)
	_expect(w.holder.ammo_in_magazine() == left, "stops after 3 s")
	w.root.free()


func _test_dash_slash() -> void:
	_set_mastery({})
	var w := await _world()
	_equip(&"dagger", Enums.EquipSlot.MAIN)
	var near := await _monster(w, Vector3(0, 0, -2))
	var far := await _monster(w, Vector3(0, 0, -9))
	var expected := _expected_damage(near, _base(w) * 1.5)
	_noises.clear()
	_expect(w.skills.use(&"q"), "dash slash used")
	_expect_near(TEST_HP - near.hp, expected, "monster on the path x1.5")
	_expect(near.status.has(&"bleed"), "blade hit bleeds")
	_expect(far.hp == TEST_HP, "beyond 5 m untouched")
	_expect(_noises.has(3.0), "blade attack noise")
	_advance(w, ClassSkills.DASH_SEC + DT)
	_expect_near(w.player.global_position.z, -5.0, "dashed 5 m forward", 0.05)
	# A wall 2 m ahead stops the dash before it.
	w.player.global_position = Vector3.ZERO
	_box(w.root, Vector3(0, 1, -2.5), Vector3(4, 2, 0.2))
	await _physics()
	w.skills._cooldown.clear()
	_expect(w.skills.use(&"q"), "dash again")
	_advance(w, ClassSkills.DASH_SEC + DT)
	_expect(w.player.global_position.z > -2.4, "stops before the wall (z %.2f)" % w.player.global_position.z)
	w.root.free()


func _test_shadow_step() -> void:
	_set_mastery({})
	var w := await _world()
	_equip(&"dagger", Enums.EquipSlot.MAIN)
	var monster := await _monster(w, Vector3(0, 0, -1))
	var noise := w.player.get_node(^"Noise") as NoiseEmitter
	var walk := noise.radius_for(&"walk")
	_expect(monster.can_see(w.player), "seen before")
	_expect(w.skills.use(&"e"), "shadow step used")
	_expect(w.skills.is_hidden() and not monster.can_see(w.player), "hidden: monster cannot see")
	_expect(noise.radius_for(&"walk") == 0.0 and noise.radius_for(&"sprint") == 0.0, "no footstep noise")
	var expected := _expected_damage(monster, _base(w) * 3.0)
	_expect(w.holder.swing(), "swing")
	_expect_near(TEST_HP - monster.hp, expected, "first attack x3")
	_expect(not w.skills.is_hidden() and monster.can_see(w.player), "attacking ends the stealth")
	_expect_near(noise.radius_for(&"walk"), walk, "footsteps back")
	# Unused, it runs out after 4 s.
	w.skills._cooldown.clear()
	w.skills.use(&"e")
	_advance(w, 4.1)
	_expect(not w.skills.is_hidden(), "ends after 4 s")
	w.root.free()


func _test_slam() -> void:
	_set_mastery({})
	var w := await _world()
	_equip(&"club", Enums.EquipSlot.MAIN)
	var a := await _monster(w, Vector3(0, 0, -2))
	var b := await _monster(w, Vector3(2.5, 0, 0))
	var far := await _monster(w, Vector3(0, 0, 6))
	var expected := _expected_damage(a, _base(w) * 1.8)
	_expect(w.skills.use(&"q"), "slam used")
	_expect_near(TEST_HP - a.hp, expected, "x1.8 in front")
	_expect_near(TEST_HP - b.hp, expected, "x1.8 to the side (radius, no arc)")
	_expect(far.hp == TEST_HP, "6 m away untouched")
	_expect_near(a.status.time_left(&"stagger"), 1.5, "stagger 1.5 s")
	w.root.free()


func _test_brace() -> void:
	_set_mastery({})
	var w := await _world()
	_equip(&"club", Enums.EquipSlot.MAIN)
	var near := await _monster(w, Vector3(0, 0, 5))
	var far := await _monster(w, Vector3(0, 0, 12))
	_expect(w.skills.use(&"e"), "brace used")
	_expect(near.state == Enums.AIState.CHASE and near.target == w.player, "taunts within 6 m")
	_expect(far.state != Enums.AIState.CHASE, "not beyond 6 m")
	var hp := w.player.health
	w.player.take_damage(10.0, {"source": near, "status": [{"id": &"knockback"}, {"id": &"slow"}]})
	_expect_near(hp - w.player.health, 4.0, "damage -60%")
	_expect(not w.player.status.has(&"knockback"), "no knockback")
	_expect(w.player.status.has(&"slow"), "other statuses still land")
	_advance(w, 3.1)
	hp = w.player.health
	w.player.take_damage(10.0, {"source": near})
	_expect_near(hp - w.player.health, 10.0, "full damage after 3 s")
	w.root.free()


func _test_passives() -> void:
	var w := await _world()
	var monster := await _monster(w, Vector3(0, 0, -3))
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	_set_mastery({"GUN": 4})
	w.skills.step(DT, {})
	_expect_near(w.holder.reload_mult, 1.0, "gun 4: normal reload")
	_set_mastery({"GUN": 5})
	w.skills.step(DT, {})
	_expect_near(w.holder.reload_mult, 0.75, "gun 5: reload -25%")
	var weak := MonsterWeakPoint.new()
	monster.add_child(weak)
	_expect_near(w.skills.filter_hit(weak, 10.0, {}), 10.0, "gun 5: weak point normal")
	_set_mastery({"GUN": 10})
	_expect_near(w.skills.filter_hit(weak, 10.0, {}), 13.0, "gun 10: weak point +30%")

	_equip(&"dagger", Enums.EquipSlot.MAIN)
	_set_mastery({"BLADE": 5})
	_expect_near(w.skills.filter_hit(monster, 10.0, {"backstab": true}), 15.0, "blade 5: backstab +50%")
	_expect_near(w.skills.filter_hit(monster, 10.0, {}), 10.0, "blade 5: front hit normal")
	var info := {}
	w.skills.filter_hit(monster, 10.0, info)
	_expect(_status(info, &"bleed").get("stacks_max", 1) == 1, "blade 5: bleed 1 stack")
	_set_mastery({"BLADE": 10})
	info = {}
	w.skills.filter_hit(monster, 10.0, info)
	_expect(_status(info, &"bleed").get("stacks_max", 1) == 2, "blade 10: bleed 2 stacks")

	_equip(&"club", Enums.EquipSlot.MAIN)
	_set_mastery({"BLUNT": 4})
	info = {"combo_step": 2}
	w.skills.filter_hit(monster, 10.0, info)
	_expect(not info.has("status"), "blunt 2nd hit: nothing")
	info = {"combo_step": 3}
	w.skills.filter_hit(monster, 10.0, info)
	_expect(not _status(info, &"armor_break").is_empty(), "blunt finisher: armor break")
	_expect(not _status(info, &"stagger").has("duration"), "blunt 4: stagger default")
	_set_mastery({"BLUNT": 5})
	info = {"combo_step": 3}
	w.skills.filter_hit(monster, 10.0, info)
	_expect_near(float(_status(info, &"stagger").get("duration", 0.0)), 1.3, "blunt 5: stagger +30%")
	_equip(&"hammer", Enums.EquipSlot.MAIN)
	info = {"combo_step": 2}
	w.skills.filter_hit(monster, 10.0, info)
	_expect(not _status(info, &"armor_break").is_empty(), "hammer breaks armor on hit 2")
	_equip(&"club", Enums.EquipSlot.MAIN)
	monster.status.apply(&"armor_break")
	_expect_near(w.skills.filter_hit(monster, 10.0, {}), 10.0, "blunt 5: no ally bonus")
	_set_mastery({"BLUNT": 10})
	_expect_near(w.skills.filter_hit(monster, 10.0, {}), 11.5, "blunt 10: armor broken +15%")
	_expect_near(ClassSkills.party_damage_mult(monster, get_tree()), 1.15, "companions get it too")
	w.root.free()


func _test_mastery_from_hits() -> void:
	_set_mastery({})
	var w := await _world()
	_equip(&"rifle", Enums.EquipSlot.MAIN)
	_equip(&"pistol", Enums.EquipSlot.SUB)
	var monster := await _monster(w, Vector3(0, 0, -3))
	GameState.set_phase(Enums.Phase.MORNING)
	_shot_damage(w, monster)
	_expect(Progression.mastery_xp(Enums.CombatClass.GUN) == 0, "no mastery outside a sortie")
	GameState.set_phase(Enums.Phase.SORTIE)
	var main_hits := 0.0
	for i in 10:
		main_hits += _shot_damage(w, monster)
	var main_xp := Progression.mastery_xp(Enums.CombatClass.GUN)
	_expect(main_xp > 0, "main weapon hits give mastery (%d)" % main_xp)
	w.skills.mastery = ClassMastery.new()
	_set_mastery({})
	w.holder.switch_to(Enums.EquipSlot.SUB)
	var sub_hits := 0.0
	while sub_hits < main_hits:
		sub_hits += _shot_damage(w, monster)
	var sub_xp := Progression.mastery_xp(Enums.CombatClass.GUN)
	_expect(absf(sub_xp - main_xp * 0.5) <= 2.0, "sub weapon about 50%% (%d vs %d)" % [sub_xp, main_xp])
	# A kill adds XP_PER_KILL.
	_set_mastery({})
	w.skills.mastery = ClassMastery.new()
	w.holder.switch_to(Enums.EquipSlot.MAIN)
	_advance(w, 0.5)  # the pistol's attack interval still holds the shared cooldown
	monster.hp = 1.0
	_shot_damage(w, monster)
	_expect(Progression.mastery_xp(Enums.CombatClass.GUN) >= int(ClassMastery.XP_PER_KILL), "kill xp")
	GameState.set_phase(Enums.Phase.MORNING)
	await get_tree().process_frame  # the drop pile is added deferred; free it with the root
	w.root.free()


func _test_hud_and_disabled_e() -> void:
	var w := await _world()
	_equip(&"dagger", Enums.EquipSlot.MAIN)
	var list := ClassSkills.hud_list(w.player)
	_expect(list.size() == 2 and list[0]["key"] == "Q" and list[1]["key"] == "E", "HUD Q and E")
	_expect(is_equal_approx(list[0]["left"], 0.0) and is_equal_approx(list[0]["max"], 8.0), "Q ready, max 8")
	w.skills.use(&"q")
	list = w.player.hud_state()["skills"]
	_expect(is_equal_approx(list[0]["left"], 8.0), "Q cooling down in hud_state()")
	var e := ClassDef.for_class(Enums.CombatClass.BLADE).skill_e
	e.enabled = false
	list = ClassSkills.hud_list(w.player)
	_expect(list.size() == 1 and list[0]["key"] == "Q", "E off in data: HUD Q only")
	_expect(not w.skills.use(&"e"), "E off: key does nothing")
	e.enabled = true
	Armory.unequip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN)
	_expect(ClassSkills.hud_list(w.player).is_empty(), "no main weapon: no skills")
	w.root.free()


func _test_companion_q() -> void:
	var probe: FieldCompanion = COMPANION_SCENE.instantiate()
	_expect_near(probe.skill_cooldown(Enums.CombatClass.BLADE), 12.0, "companion dash 8 s x1.5")
	_expect_near(probe.skill_cooldown(Enums.CombatClass.GUN, {"aim_cooldown_mult": 0.5}), 7.5, "sniper companion 5 s x1.5")
	probe.free()
	var w := await _world()
	var id := Colony.add_resident({"name": "test", "class_aptitude": {"blunt": Enums.Aptitude.HIGH}})
	var uid := Armory.create_item(&"club", Enums.Rarity.COMMON)
	_created.append(uid)
	Armory.equip(id, Enums.EquipSlot.MAIN, uid)
	var c: FieldCompanion = COMPANION_SCENE.instantiate()
	c.setup(id, Colony.get_resident(id))
	w.root.add_child(c)
	c.set_physics_process(false)
	c.global_position = Vector3(10, 0, 0)
	var a := await _monster(w, Vector3(11.5, 0, 0))
	var far := await _monster(w, Vector3(16, 0, 0))
	c.target = a
	var stats := c.weapon_stats()
	var expected := _expected_damage(a, c.hit_damage(stats, 1.0) * 1.8)
	_expect(c.try_skill(stats), "companion slam")
	_expect_near(TEST_HP - a.hp, expected, "companion slam x1.8")
	_expect(a.status.has(&"stagger") and far.hp == TEST_HP, "stagger, radius 3 m")
	_expect_near(c.skill_time_left(), 15.0, "companion slam 10 s x1.5")
	Armory.unequip(id, Enums.EquipSlot.MAIN)
	w.root.free()


# --- Helpers ----------------------------------------------------------------

func _world() -> World:
	var w := World.new()
	w.root = Node3D.new()
	add_child(w.root)
	w.player = PLAYER_SCENE.instantiate()
	w.root.add_child(w.player)
	w.player.set_physics_process(false)
	w.holder = w.player.get_node(^"Weapons")
	w.holder.set_physics_process(false)
	w.holder.tuning = _exact_tuning()
	w.skills = w.player.skills
	w.skills.set_physics_process(false)
	await _physics()
	return w


## Crits off and no spread, so single hits are exact.
func _exact_tuning() -> CombatTuning:
	var t: CombatTuning = WeaponHolder.DEFAULT_TUNING.duplicate(true)
	t.crit_rate = 0.0
	for def_id: StringName in t.weapon_types:
		t.weapon_types[def_id]["spread_deg"] = 0.0
	t.class_defaults[Enums.CombatClass.GUN]["spread_deg"] = 0.0
	t.bloom_per_shot_deg = 0.0
	return t


func _monster(w: World, pos: Vector3) -> Monster:
	var monster: Monster = VINE_DEF.scene.instantiate()
	monster.def = VINE_DEF
	w.root.add_child(monster)
	monster.set_physics_process(false)
	monster.global_position = pos
	var to := -pos
	monster.rotation.y = atan2(-to.x, -to.z)  # facing the origin
	monster.max_hp = TEST_HP
	monster.hp = TEST_HP
	await _physics()
	return monster


func _box(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = pos


## Fires once at once (waits out the attack interval first). Returns the damage `monster` took.
func _shot_damage(w: World, monster: Monster) -> float:
	_advance(w, float(w.holder.current_stats().get("attack_interval", 0.5)) + DT)
	if w.holder.ammo_in_magazine() <= 1:
		w.holder._magazines.clear()
	var before := monster.hp
	w.holder.fire()
	return before - monster.hp


## Steps the weapon holder and the class runtime (game order) for `sec` seconds, no input.
func _advance(w: World, sec: float) -> void:
	var t := 0.0
	while t < sec:
		w.holder.step(DT, {})
		w.skills.step(DT, {})
		t += DT


## Attacker-side damage of the active weapon (no crit), then the monster's own factors.
func _base(w: World) -> float:
	var stats := w.holder.current_stats()
	return DamageFormula.attacker_damage(float(stats["damage"]),
			ClassMastery.level(int(stats["combat_class"])), w.holder.tuning.mastery_per_level, 1.0)


func _expected_damage(monster: Monster, amount: float) -> float:
	return amount * MonsterRules.defense_factor(VINE_DEF.defense * monster.status.defense_mult())


func _status(info: Dictionary, id: StringName) -> Dictionary:
	for entry: Dictionary in info.get("status", []):
		if entry.get("id", &"") == id:
			return entry
	return {}


func _set_mastery(levels: Dictionary) -> void:
	var data := {}
	for key: String in levels:
		data[key] = {"level": levels[key], "xp": 0}
	Progression.load_data({"mastery": data})


func _equip(def_id: StringName, slot: Enums.EquipSlot) -> StringName:
	var uid := Armory.create_item(def_id, Enums.Rarity.COMMON)
	_created.append(uid)
	Armory.equip(Armory.PLAYER_ID, slot, uid)
	return uid


func _remember_loadout() -> void:
	_previous = {}
	for slot in [Enums.EquipSlot.MAIN, Enums.EquipSlot.SUB]:
		_previous[slot] = Armory.get_equipped(Armory.PLAYER_ID, slot)


func _restore_loadout() -> void:
	for uid in _created:
		Armory.remove_item(uid)
	_created.clear()
	for slot: Enums.EquipSlot in _previous:
		if _previous[slot] != &"":
			Armory.equip(Armory.PLAYER_ID, slot, _previous[slot])


func _on_noise(_point: Vector3, radius: float, _source: Node) -> void:
	_noises.append(radius)


func _physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_ok = false
		push_error("test_classes: " + label)


func _expect_near(a: float, b: float, label: String, eps: float = EPS) -> void:
	_expect(absf(a - b) <= eps, "%s (got %.3f, want %.3f)" % [label, a, b])
