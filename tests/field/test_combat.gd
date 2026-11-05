extends Node
## B-06: damage formula (pure), then the WeaponHolder against a real monster in a physics world:
## 6 demo weapons hit, upgrade not applied twice, weak point, low cover, wall, backstab, combo,
## block / perfect block / guard break, magazine and reload.
## Player and monster physics are off; the test drives WeaponHolder.step() and the attack calls.

const DT := 1.0 / 60.0
const EPS := 0.01
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const VINE_DEF := preload("res://data/monsters/vine_tendril.tres")
const BLOB_DEF := preload("res://data/monsters/swamp_blob.tres")
const BUG_DEF := preload("res://data/monsters/rubble_bug.tres")
const TEST_HP := 10000.0
const SIX_WEAPONS: Array[StringName] = [&"pistol", &"rifle", &"dagger", &"machete", &"club", &"pipe_wrench"]

var _ok := true
var _created: Array[StringName] = []
var _previous := {}


func run() -> bool:
	_ok = true
	_test_formula()
	_test_spread_and_bloom()
	_test_arcs_and_backstab_rule()
	_test_combo_and_block_rules()
	_remember_loadout()
	await _test_six_weapons()
	await _test_upgrade_not_doubled()
	await _test_weak_point()
	await _test_cover_and_wall()
	await _test_short_monsters()
	await _test_shot_radius()
	await _test_melee_combo_and_backstab()
	await _test_block()
	await _test_magazine_and_reload()
	await _test_one_hand_only()
	_restore_loadout()
	return _ok


# --- Pure formula ---------------------------------------------------------

func _test_formula() -> void:
	_expect_near(DamageFormula.mastery_factor(1, 0.03), 1.03, "mastery 1 -> x1.03")
	_expect_near(DamageFormula.mastery_factor(10, 0.03), 1.3, "mastery 10 -> x1.3")
	_expect_near(DamageFormula.full(18.0, 1, 0.03, 1.0, 1.0, 1.0, 0.0), 18.54, "pistol, nothing else")
	# A=35 (stats damage, upgrade inside), M=10, weak point, element weakness, crit, R=100.
	_expect_near(DamageFormula.full(35.0, 10, 0.03, 2.0, 1.5, 1.5, 100.0),
			35.0 * 1.3 * 2.0 * 1.5 * 1.5 * 0.5, "every factor")
	_expect_near(DamageFormula.full(20.0, 1, 0.03, 1.0, 0.75, 1.0, 0.0), 20.0 * 1.03 * 0.75, "resisted")
	_expect_near(DamageFormula.attacker_damage(14.0, 1, 0.03, 1.0, 1.5), 14.0 * 1.03 * 1.5, "extra x1.5")
	_expect_near(DamageFormula.attacker_damage(-5.0, 1, 0.03, 1.0), 0.0, "negative damage clamps")
	_expect_near(DamageFormula.crit_chance(0.05, 3.0), 0.08, "crit affix +3%p")
	_expect_near(DamageFormula.crit_multiplier(0.07, 0.08, 1.5), 1.5, "roll under chance crits")
	_expect_near(DamageFormula.crit_multiplier(0.09, 0.08, 1.5), 1.0, "roll over chance does not")


func _test_spread_and_bloom() -> void:
	_expect_near(DamageFormula.spread_deg(6.0, 0.0, false, false, 1.5, 0.5), 6.0, "pistol 6")
	_expect_near(DamageFormula.spread_deg(6.0, 0.0, true, false, 1.5, 0.5), 9.0, "moving x1.5")
	_expect_near(DamageFormula.spread_deg(6.0, 0.0, false, true, 1.5, 0.5), 3.0, "aiming x0.5")
	_expect_near(DamageFormula.spread_deg(6.0, 2.0, true, true, 1.5, 0.5), 6.0, "bloom, moving, aiming")
	var bloom := 0.0
	for i in 10:
		bloom = DamageFormula.add_bloom(bloom, 1.0, 6.0, 10.0)
	_expect_near(bloom, 4.0, "bloom +1 per shot up to the cap")


func _test_arcs_and_backstab_rule() -> void:
	var fwd := Vector3.FORWARD
	_expect(DamageFormula.in_arc(fwd, Vector3(1, 0, -1), 120.0), "45 deg is inside 120")
	_expect(not DamageFormula.in_arc(fwd, Vector3(1, 0, 0), 120.0), "90 deg is outside 120")
	_expect(DamageFormula.is_backstab(fwd, Vector3.BACK, 90.0, false), "behind, unaware")
	_expect(not DamageFormula.is_backstab(fwd, Vector3.BACK, 90.0, true), "behind but aware")
	_expect(not DamageFormula.is_backstab(fwd, Vector3.RIGHT, 90.0, false), "side is not behind")
	_expect(not DamageFormula.is_backstab(fwd, Vector3.FORWARD, 90.0, false), "front is not behind")


func _test_combo_and_block_rules() -> void:
	_expect(DamageFormula.next_combo(0, 0.0, 0.35, 3) == 1, "first swing is 1")
	_expect(DamageFormula.next_combo(1, 0.1, 0.35, 3) == 2, "inside window -> 2")
	_expect(DamageFormula.next_combo(2, 0.1, 0.35, 3) == 3, "inside window -> 3")
	_expect(DamageFormula.next_combo(3, 0.1, 0.35, 3) == 1, "after 3 starts over")
	_expect(DamageFormula.next_combo(1, 0.5, 0.35, 3) == 1, "window passed -> 1")
	var perfect := DamageFormula.block(20.0, 0.1, 0.2, 0.5, 0.5)
	_expect(perfect["perfect"] and perfect["damage"] == 0.0, "perfect block inside 0.2s")
	var normal := DamageFormula.block(20.0, 0.5, 0.2, 0.5, 0.5)
	_expect(not normal["perfect"], "late block is normal")
	_expect_near(normal["damage"], 10.0, "block -50%")
	_expect_near(normal["stamina_cost"], 10.0, "stamina = incoming x0.5")


# --- In the world ---------------------------------------------------------

## B-10 부축: only light weapons while player.one_hand_only.
func _test_one_hand_only() -> void:
	var w := await _world()
	_equip(&"rifle", Enums.EquipSlot.MAIN)
	_equip(&"pistol", Enums.EquipSlot.SUB)
	w.holder.switch_to(Enums.EquipSlot.MAIN)
	w.player.one_hand_only = true
	w.holder.step(1.0 / 60.0, {})
	_expect(w.holder.active_slot == Enums.EquipSlot.SUB, "supporting falls back to the light pistol")
	_expect(not w.holder.switch_to(Enums.EquipSlot.MAIN), "rifle refused while supporting")
	# Only a two-hand rifle (SUB takes light weapons only, so leave it empty): no attack at all.
	Armory.unequip(Armory.PLAYER_ID, Enums.EquipSlot.SUB)
	w.player.one_hand_only = false
	w.holder.switch_to(Enums.EquipSlot.MAIN)
	w.player.one_hand_only = true
	var ammo := w.holder.ammo_in_magazine()
	w.holder.step(1.0 / 60.0, {"attack": true})
	_expect(w.holder.active_slot == Enums.EquipSlot.MAIN and w.holder.ammo_in_magazine() == ammo,
		"no two-hand attack while supporting")
	w.player.one_hand_only = false
	_expect(w.holder.switch_to(Enums.EquipSlot.MAIN), "rifle usable again")
	w.root.free()


func _test_six_weapons() -> void:
	for def_id in SIX_WEAPONS:
		var w := await _world()
		_equip(def_id, Enums.EquipSlot.MAIN)
		var monster: Monster = await _monster(w, Vector3(0, 0, -1.0), true)
		var stats := w.holder.current_stats()
		var attacked := w.holder.fire() if WeaponHolder.is_gun(stats) else w.holder.swing()
		_expect(attacked, "%s attacks" % def_id)
		_expect(monster.hp < TEST_HP, "%s damages the monster" % def_id)
		w.root.free()


func _test_upgrade_not_doubled() -> void:
	var w := await _world()
	var uid := _equip(&"pistol", Enums.EquipSlot.MAIN)
	Armory.get_item(uid).upgrade_level = 5  # test only: there is no upgrade API in Armory yet
	var stats := Armory.get_item_stats(uid)
	_expect_near(stats["damage"], 18.0 * 1.3, "Armory damage includes +5 upgrade")
	var monster: Monster = await _monster(w, Vector3(0, 0, -5), false)
	w.holder.fire()
	# Monster faces away (no weak point), defense 0, element none: hp loss = A x 1.03 only.
	_expect_near(TEST_HP - monster.hp, 18.0 * 1.3 * 1.03, "upgrade applied once")
	w.root.free()


func _test_weak_point() -> void:
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	var front: Monster = await _monster(w, Vector3(0, 0, -5), true)
	w.holder.fire()
	_expect_near(TEST_HP - front.hp, 18.0 * 1.03 * 2.0, "front shot hits the glowing core x2")
	w.root.free()


func _test_cover_and_wall() -> void:
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	var monster: Monster = await _monster(w, Vector3(0, 0, -5), false)
	var cover := _box(w.root, Vector3(0, 0.6, -4.2), Vector3(2, 1.2, 0.4))
	cover.add_to_group(WeaponHolder.LOW_COVER_GROUP)
	await _physics()
	w.holder.fire()
	_expect_near(TEST_HP - monster.hp, 18.0 * 1.03 * 0.5, "low cover near the target -50%")
	cover.remove_from_group(WeaponHolder.LOW_COVER_GROUP)
	monster.hp = TEST_HP
	w.holder.step(1.0, {})
	w.holder.fire()
	_expect_near(monster.hp, TEST_HP, "a wall (not low cover) blocks the shot")
	w.root.free()

	# Cover right in front of the shooter, far from the target: no penalty.
	w = await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	monster = await _monster(w, Vector3(0, 0, -8), false)
	_box(w.root, Vector3(0, 0.6, -1.0), Vector3(2, 1.2, 0.4)).add_to_group(WeaponHolder.LOW_COVER_GROUP)
	await _physics()
	w.holder.fire()
	_expect_near(TEST_HP - monster.hp, 18.0 * 1.03, "shooter's own cover does not reduce damage")
	w.root.free()


## User feedback 2026-11-06: shots flew over split slimes (0.68 to 0.9 m tall) and rubble bugs
## (0.4 m), all shorter than the 1 m shot height. Checked with aim assist off (a thin line).
func _test_short_monsters() -> void:
	var assist: Variant = Settings.get_value(&"aim_assist")
	Settings.values[&"aim_assist"] = 0
	var smallest := MonsterRules.SIZE_MULT * pow(MonsterRules.SPLIT_SIZE_RATIO, MonsterRules.SPLIT_MAX_GENERATIONS)
	for setup in [[BLOB_DEF, MonsterRules.SPLIT_MAX_GENERATIONS, smallest], [BUG_DEF, 0, 0.0]]:
		var w := await _world()
		_equip(&"pistol", Enums.EquipSlot.MAIN)
		var def: MonsterDef = setup[0]
		var monster: Monster = def.scene.instantiate()
		monster.def = def
		monster.split_generation = setup[1]
		if setup[2] > 0.0:
			monster.scale = Vector3.ONE * setup[2]
			monster.size_applied = true
		w.root.add_child(monster)
		monster.set_physics_process(false)
		monster.global_position = Vector3(0, 0, -5)
		monster.max_hp = TEST_HP
		monster.hp = TEST_HP
		await _physics()
		w.holder.fire()
		_expect(monster.hp < TEST_HP, "the shot hits a short %s (gen %d)" % [def.id, setup[1]])
		w.root.free()
	Settings.values[&"aim_assist"] = assist


## Aim help: the shot is shot_radius_by_assist[level] wide against monsters, a thin line at 0.
func _test_shot_radius() -> void:
	var assist: Variant = Settings.get_value(&"aim_assist")
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	# Body edge (0.4 m x SIZE_MULT) misses the line by about 0.18 m.
	var monster: Monster = await _monster(w, Vector3(0.7, 0, -5), false)
	Settings.values[&"aim_assist"] = 0
	w.holder.fire()
	_expect_near(monster.hp, TEST_HP, "assist off: a near miss stays a miss")
	Settings.values[&"aim_assist"] = 1
	w.holder.step(1.0, {})
	w.holder.fire()
	_expect(monster.hp < TEST_HP, "weak assist: the wider shot hits the near miss")
	Settings.values[&"aim_assist"] = assist
	w.root.free()


func _test_melee_combo_and_backstab() -> void:
	var w := await _world()
	_equip(&"dagger", Enums.EquipSlot.MAIN)
	var back: Monster = await _monster(w, Vector3(0, 0, -1.0), false)
	var stamina := w.player.stamina
	w.holder.swing()
	_expect_near(TEST_HP - back.hp, 14.0 * 1.03 * 2.5, "dagger backstab x2.5 on an unaware monster")
	_expect_near(stamina - w.player.stamina, 8.0, "blade swing costs 8 stamina")
	w.root.free()

	w = await _world()
	_equip(&"machete", Enums.EquipSlot.MAIN)
	var front: Monster = await _monster(w, Vector3(0, 0, -1.0), true)
	var per_hit := 22.0 * 1.03 * 1.2  # machete vs a green-family monster
	var expected := [per_hit, per_hit, per_hit * 1.5]
	for i in 3:
		var before := front.hp
		w.holder.step(0.4, {})  # machete attack_interval, then inside the 0.35s window
		_expect(w.holder.swing(), "combo swing %d" % (i + 1))
		_expect(w.holder.combo_step == i + 1, "combo step %d" % (i + 1))
		_expect_near(before - front.hp, expected[i], "combo hit %d damage" % (i + 1))
	w.holder.step(0.4, {})
	w.holder.swing()
	_expect(w.holder.combo_step == 1, "swing after a finished combo is 1")
	w.holder.step(0.4 + 0.5, {})
	w.holder.swing()
	_expect(w.holder.combo_step == 1, "swing after the window restarts the combo")
	w.player.stamina = 1.0
	w.holder.step(1.0, {})
	_expect(not w.holder.swing(), "no swing without stamina")
	_expect(front.hp > 0.0 and is_instance_valid(front), "monster still alive")
	w.root.free()

	# Blunt costs 15 and a monster out of the arc is not hit.
	w = await _world()
	_equip(&"pipe_wrench", Enums.EquipSlot.MAIN)
	var side: Monster = await _monster(w, Vector3(1.2, 0, 0), true)
	stamina = w.player.stamina
	w.holder.swing()
	_expect_near(stamina - w.player.stamina, 15.0, "blunt swing costs 15 stamina")
	_expect_near(side.hp, TEST_HP, "monster at the side is outside the swing arc")
	w.root.free()


func _test_block() -> void:
	var w := await _world()
	_equip(&"club", Enums.EquipSlot.MAIN)
	var monster: Monster = await _monster(w, Vector3(0, 0, -1.5), true)
	var aim := {"aim": true}
	w.holder.step(DT, aim)
	_expect(w.holder.is_blocking, "aim with a melee weapon blocks")
	w.player.take_damage(20.0, {"source": monster})
	_expect_near(w.player.health, w.player.stats.max_health, "perfect block: no damage")
	_expect(monster.is_stunned(), "perfect block stuns the attacker")
	w.holder.step(0.5, aim)
	var stamina := w.player.stamina
	w.player.take_damage(20.0, {"source": monster})
	_expect_near(w.player.health, w.player.stats.max_health - 10.0, "block -50%")
	_expect_near(stamina - w.player.stamina, 10.0, "block costs incoming x0.5 stamina")
	var behind := Node3D.new()
	w.root.add_child(behind)
	behind.global_position = Vector3(0, 0, 3)
	w.player.take_damage(10.0, {"source": behind})
	_expect_near(w.player.health, w.player.stats.max_health - 20.0, "hit from behind is not blocked")
	w.player.stamina = 4.0
	w.player.take_damage(20.0, {"source": monster})
	_expect(not w.holder.is_blocking and w.holder.is_stunned(), "stamina 0 breaks the guard")
	_expect(w.player.is_bound(), "guard break locks movement")
	w.holder.step(1.1, aim)
	_expect(not w.holder.is_blocking, "aim must be released after a guard break")
	w.holder.step(DT, {})
	w.holder.step(DT, aim)
	_expect(w.holder.is_blocking, "block again after releasing aim")
	w.root.free()


func _test_magazine_and_reload() -> void:
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	_expect(w.holder.ammo_in_magazine() == 12, "pistol starts with a full magazine")
	_expect(w.holder.ammo_reserve() == -1, "starting pistol ammo is infinite")
	for i in 12:
		w.holder.fire()
		w.holder.step(0.4, {})
	_expect(w.holder.ammo_in_magazine() == 0, "12 shots empty the magazine")
	_expect(not w.holder.fire(), "empty magazine does not fire")
	_expect(w.holder.is_reloading, "empty fire starts the reload")
	w.holder.step(w.holder.tuning.weapon_value(&"pistol", 0, "reload_sec", 1.0) + DT, {})
	_expect(not w.holder.is_reloading and w.holder.ammo_in_magazine() == 12, "reload refills")

	var pistol := w.holder.current_uid()
	var rifle := _equip(&"rifle", Enums.EquipSlot.MAIN)
	Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.SUB, pistol)
	_expect(w.holder.current_uid() == rifle, "rifle is active in MAIN")
	w.holder.step(DT, {"weapon_2": true})
	_expect(w.holder.current_uid() == pistol, "weapon_2 picks the SUB pistol")
	w.holder.step(DT, {"weapon_swap": true})
	_expect(w.holder.active_slot == Enums.EquipSlot.MAIN, "weapon_swap goes back to MAIN")
	w.holder.step(1.0, {})
	_expect(w.holder.fire() and w.holder.ammo_in_magazine() == 19, "rifle uses its own magazine")
	if Bag.count(&"ammo_rifle") == 0:
		_expect(not w.holder.start_reload(), "no rifle reload without rifle ammo in the bag")
	w.root.free()


# --- Helpers --------------------------------------------------------------

class World:
	var root: Node3D
	var player: Player
	var holder: WeaponHolder


func _world() -> World:
	var w := World.new()
	w.root = Node3D.new()
	add_child(w.root)
	w.player = PLAYER_SCENE.instantiate()
	w.root.add_child(w.player)
	w.player.set_physics_process(false)
	w.holder = w.player.get_node(^"Weapons")
	w.holder.set_physics_process(false)
	w.holder.tuning = _test_tuning()
	await _physics()
	return w


## Stats as designed, but no crits and no spread so single shots are exact.
func _test_tuning() -> CombatTuning:
	var t: CombatTuning = WeaponHolder.DEFAULT_TUNING.duplicate(true)
	t.crit_rate = 0.0
	for def_id: StringName in t.weapon_types:
		t.weapon_types[def_id]["spread_deg"] = 0.0
	t.class_defaults[Enums.CombatClass.GUN]["spread_deg"] = 0.0
	t.bloom_per_shot_deg = 0.0
	return t


func _monster(w: World, pos: Vector3, facing_player: bool) -> Monster:
	var monster: Monster = VINE_DEF.scene.instantiate()
	monster.def = VINE_DEF
	w.root.add_child(monster)
	monster.set_physics_process(false)
	monster.global_position = pos
	if facing_player:
		var to := -pos
		monster.rotation.y = atan2(-to.x, -to.z)
	monster.max_hp = TEST_HP
	monster.hp = TEST_HP
	await _physics()
	return monster


func _box(parent: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = pos
	return body


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


func _physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_ok = false
		push_error("test_combat: " + label)


func _expect_near(a: float, b: float, label: String, eps: float = EPS) -> void:
	_expect(absf(a - b) <= eps, "%s (got %.3f, want %.3f)" % [label, a, b])
