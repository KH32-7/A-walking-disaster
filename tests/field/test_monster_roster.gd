extends RefCounted
## B-18: every monster def, elite variant, drops, and the new behaviors
## (statue, mist, neon moth, signal wraith, rally). Ticks are driven by hand.

const DIR := "res://data/monsters/"
const DT := 0.1

var _root: Node3D
var _ok := true


class FakeTarget extends Node3D:
	var hits: Array[Dictionary] = []

	func take_damage(amount: float, info: Dictionary) -> void:
		hits.append({"amount": amount, "info": info})


## Player-layer body so orb rays and shock field queries can hit it.
class FakeBody extends StaticBody3D:
	var hits: Array[Dictionary] = []

	func _init() -> void:
		collision_layer = 1 << (Enums.LAYER_PLAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.5
		shape.shape = sphere
		shape.position.y = 1.0
		add_child(shape)

	func take_damage(amount: float, info: Dictionary) -> void:
		hits.append({"amount": amount, "info": info})


func run() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	_root = Node3D.new()
	_root.name = "TestMonsterRoster"
	tree.root.add_child(_root)
	var tests: Array[Callable] = [
		_test_all_defs,
		_test_design_numbers,
		_test_elite,
		_test_sight_mult,
		_test_drop_rolls,
		_test_kill_drops,
		_test_drop_pile_pickup,
		_test_statue,
		_test_mist,
		_test_neon_moth,
		_test_signal_wraith,
		_test_rally,
	]
	for test in tests:
		await test.call()
		for child in _root.get_children():
			child.free()
	_root.free()
	return _ok


# --- Tests ----------------------------------------------------------------

func _test_all_defs() -> void:
	var shapes := {
		Enums.Element.GREEN: MonsterDef.WeakPointShape.PETAL, Enums.Element.STONE: MonsterDef.WeakPointShape.SQUARE,
		Enums.Element.WATER: MonsterDef.WeakPointShape.DROPLET, Enums.Element.LIGHT: MonsterDef.WeakPointShape.BOLT,
	}
	var count := 0
	for file in ResourceLoader.list_directory(DIR):
		if not file.ends_with(".tres"):
			continue
		count += 1
		var def := load(DIR + file) as MonsterDef
		_check(def != null, "%s is a MonsterDef" % file)
		if def == null:
			continue
		_check(String(def.id) + ".tres" == file, "%s id matches the file name" % file)
		_check(def.weak_point_shape == shapes[def.family], "%s core shape follows its family (16)" % def.id)
		for id in def.behaviors + def.elite_behaviors:
			_check(Monster.BEHAVIORS.has(id), "%s behavior %s exists" % [def.id, id])
		if def.tier == Enums.MonsterTier.NORMAL:
			_check(MonsterDrops.table(def.drop_table_id) != null, "%s has a drop table" % def.id)
			_check(not def.elite_behaviors.is_empty(), "%s has an elite pattern" % def.id)
		_check(def.scene != null, "%s has a scene" % def.id)
		if def.scene == null:
			continue
		var m := _spawn(def, Vector3(count * 4.0, 0, 0))
		_check(m.get_node_or_null("WeakPoint") is MonsterWeakPoint, "%s scene has a weak point" % def.id)
		_check(m._behaviors.size() == def.behaviors.size(), "%s attaches every behavior" % def.id)
	_check(count == 10, "8 field monsters + 2 raid monsters (no bosses yet)")


func _test_design_numbers() -> void:
	# 04 "마물 목록": family, hp, defense, attack, move, hearing, sight.
	var table := {
		&"vine_tendril": [Enums.Element.GREEN, 40.0, 0.0, 8.0, 5.5, 1.2, 8.0],
		&"spore_pod": [Enums.Element.GREEN, 30.0, 0.0, 6.0, 0.0, 1.5, 10.0],
		&"rubble_bug": [Enums.Element.STONE, 25.0, 10.0, 6.0, 6.0, 1.0, 6.0],
		&"statue": [Enums.Element.STONE, 120.0, 40.0, 20.0, 4.0, 1.5, 0.0],
		&"mist": [Enums.Element.WATER, 35.0, 0.0, 10.0, 4.5, 1.0, 6.0],
		&"swamp_blob": [Enums.Element.WATER, 80.0, 5.0, 12.0, 3.0, 0.8, 6.0],
		&"neon_moth": [Enums.Element.LIGHT, 20.0, 0.0, 25.0, 6.5, 1.3, 10.0],
		&"signal_wraith": [Enums.Element.LIGHT, 60.0, 10.0, 15.0, 3.5, 1.0, 14.0],
	}
	for id: StringName in table:
		var def := _load(id)
		var got := [def.family, def.hp, def.defense, def.attack, def.move_speed, def.hearing_mult, def.sight_range]
		_check(got == table[id], "%s matches the 04 table" % id)
		_check(def.tier == Enums.MonsterTier.NORMAL, "%s is a normal monster" % id)
	var bug := _load(&"rubble_bug")
	_check(bug.group_min == 6 and bug.group_max == 10, "rubble bugs come in packs of 6 to 10")
	# 04 "습격 전용 마물".
	var crusher := _load(&"root_crusher")
	_check(crusher.tier == Enums.MonsterTier.SIEGE and crusher.family == Enums.Element.GREEN and crusher.hp == 200.0
			and crusher.structure_damage_mult == 3.0, "root crusher: siege, green, hp 200, walls x3")
	var ram := _load(&"debris_ram")
	_check(ram.tier == Enums.MonsterTier.SIEGE and ram.family == Enums.Element.STONE and ram.hp == 350.0
			and ram.defense == 50.0 and ram.charges_gates, "debris ram: siege, stone, hp 350, defense 50, charges gates")
	_check(crusher.drop_table_id == &"" and ram.drop_table_id == &"", "raid monsters have no field drops")


func _test_elite() -> void:
	var vine := _load(&"vine_tendril")
	# Before entering the tree.
	var before := vine.scene.instantiate() as Monster
	before.def = vine
	before.make_elite()
	_root.add_child(before)
	before.set_physics_process(false)
	_check(before.elite and is_equal_approx(before.max_hp, 120.0) and is_equal_approx(before.hp, 120.0), "elite hp x3 (before tree)")
	_check(is_equal_approx(before.attack_damage(), 12.0), "elite attack x1.5")
	_check(before.scale.is_equal_approx(Vector3.ONE * 1.3), "elite size x1.3")
	_check(before.get_behavior(&"rally") != null and before.get_behavior(&"bind") != null, "elite keeps bind and adds rally")
	# After entering the tree, and calling twice.
	var after := _spawn(vine, Vector3(5, 0, 0))
	after.make_elite()
	after.make_elite()
	_check(is_equal_approx(after.max_hp, 120.0) and after.scale.is_equal_approx(Vector3.ONE * 1.3), "make_elite after ready, once only")
	_check(after._behaviors.size() == 2, "elite behavior added once")
	_check(MonsterDrops.table_for(after).id == MonsterDrops.ELITE_TABLE_ID, "elites use the elite drop table")
	var player := _player(Vector3(5, 0, -1))
	after.chase(player)
	_ticks(after, MonsterRules.ATTACK_WINDUP_SEC + 2 * DT)
	_check(player.hits.size() == 1 and is_equal_approx(player.hits[0].amount, 12.0), "elite hits for attack x1.5")
	# Elite wraith fires a fan.
	var wraith := _spawn(_load(&"signal_wraith"), Vector3(-5, 0, 0))
	wraith.make_elite()
	var orbs: Array[ShockOrb] = wraith.get_behavior(&"shock_orb").make_orbs(Vector3.ZERO, Vector3.FORWARD, {})
	_check(orbs.size() == MonsterRules.ORB_FAN_COUNT and not orbs[0].velocity.is_equal_approx(orbs[2].velocity),
			"elite signal wraith fires 3 orbs in a fan")
	for orb in orbs:
		orb.free()


func _test_sight_mult() -> void:
	var m := _spawn(_load(&"vine_tendril"), Vector3.ZERO)
	var player := _player(Vector3(0, 0, -7))
	_check(m.can_see(player), "sees 7 m away with sight 8")
	m.sight_mult = 0.7
	_check(is_equal_approx(m.sight_range(), 5.6) and not m.can_see(player), "sight_mult 0.7 cuts sight to 5.6 m")


func _test_drop_rolls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	var normal := MonsterDrops.table(&"monster_normal")
	var elite := MonsterDrops.table(&"monster_elite")
	var n := 4000
	var essence := 0
	var material := 0
	var gear := 0
	var counts_ok := true
	for i in n:
		var d := MonsterDrops.roll(normal, Enums.Element.GREEN, 1.0, rng)
		if d.resources.has(&"essence_green_low"):
			essence += 1
			counts_ok = counts_ok and d.resources[&"essence_green_low"] == 1
		if d.resources.has(&"vine_fiber"):
			material += 1
			counts_ok = counts_ok and d.resources[&"vine_fiber"] == 1
		gear += d.gear.size()
		for g: Dictionary in d.gear:
			counts_ok = counts_ok and g.rarity == Enums.Rarity.COMMON and Armory.get_def(g.def_id) != null
	_check(absf(essence / float(n) - 0.3) < 0.03, "normal: low essence 30%% (got %.3f)" % (essence / float(n)))
	_check(absf(material / float(n) - 0.5) < 0.03, "normal: family material 50%% (got %.3f)" % (material / float(n)))
	_check(absf(gear / float(n) - 0.03) < 0.012, "normal: common gear 3%% (got %.3f)" % (gear / float(n)))
	_check(counts_ok, "normal: 1 essence, 1 material, common gear")

	var elite_ok := true
	var elite_gear := 0
	for i in 1000:
		var d := MonsterDrops.roll(elite, Enums.Element.LIGHT, 1.0, rng)
		var e: int = d.resources.get(&"essence_light_mid", 0)
		var mat: int = d.resources.get(&"neon_dust", 0)
		elite_ok = elite_ok and e >= 1 and e <= 2 and mat >= 2 and mat <= 3
		elite_gear += d.gear.size()
		for g: Dictionary in d.gear:
			elite_ok = elite_ok and g.rarity >= Enums.Rarity.UNCOMMON
	_check(elite_ok, "elite: 1-2 mid essence, 2-3 material always, gear uncommon or better")
	_check(absf(elite_gear / 1000.0 - 0.2) < 0.04, "elite: gear 20%% (got %.3f)" % (elite_gear / 1000.0))

	# Night drop x1.3.
	var night := 0
	for i in n:
		if MonsterDrops.roll(normal, Enums.Element.GREEN, 1.3, rng).resources.has(&"essence_green_low"):
			night += 1
	_check(absf(night / float(n) - 0.39) < 0.03, "drop_mult 1.3: essence 39%% (got %.3f)" % (night / float(n)))
	var extra := 0
	for i in 1000:
		var mat: int = MonsterDrops.roll(elite, Enums.Element.GREEN, 1.3, rng).resources.get(&"vine_fiber", 0)
		if mat == 4:
			extra += 1
	_check(extra > 0, "drop_mult above 100% adds a chance of one more")
	_check(MonsterDrops.roll(normal, Enums.Element.GREEN, 0.0, rng).resources.is_empty(), "drop_mult 0 drops nothing")

	for element in [Enums.Element.GREEN, Enums.Element.STONE, Enums.Element.WATER, Enums.Element.LIGHT]:
		_check(Economy.get_def(MonsterDrops.material_id(element)) != null, "family material %s is a Lane A resource" % element)
	_check(MonsterDrops.essence_id(Enums.Element.WATER, Enums.EssenceGrade.HIGH) == &"essence_water_high", "essence id format")


func _test_kill_drops() -> void:
	var tree := _root.get_tree()
	var vine := _load(&"vine_tendril")
	var elite := _spawn(vine, Vector3.ZERO)
	elite.make_elite()
	elite.take_damage(9999.0, {})
	var plain := _spawn(vine, Vector3(6, 0, 0))
	plain.drop_mult = 0.0
	plain.take_damage(9999.0, {})
	await tree.process_frame
	var piles := _piles()
	_check(piles.size() == 1, "elite kill leaves one pile, drop_mult 0 leaves none")
	if piles.size() == 1:
		var pile := piles[0]
		_check(pile.resources.get(&"essence_green_mid", 0) >= 1 and pile.resources.get(&"vine_fiber", 0) >= 2,
				"elite pile has mid essence and family material")
		_check(pile.global_position.distance_to(Vector3.ZERO) < 0.01 and pile.monster_id == &"vine_tendril",
				"pile sits where the monster died")
		_check(pile.collision_layer == 1 << (Enums.LAYER_INTERACTABLE - 1) and pile.interact_label() != "",
				"pile is interactable")


func _test_drop_pile_pickup() -> void:
	var bag_before := Bag.save_data()
	Bag.load_data({})
	var pile := (MonsterDrops.PILE_SCENE.instantiate() as MonsterDropPile)
	pile.resources = {&"essence_green_low": 2, &"vine_fiber": 1}
	pile.gear.assign([{"def_id": &"club", "rarity": Enums.Rarity.UNCOMMON}])
	_root.add_child(pile)
	var got: Array = []
	pile.picked_up.connect(func(res: Dictionary, uids: Array[StringName]) -> void: got.append_array([res, uids]))
	_check(pile.begin_open(null), "picking up a pile")
	_check(Bag.count_of(&"essence_green_low") == 2 and Bag.count_of(&"vine_fiber") == 1, "resources went into the bag")
	var uids: Array[StringName] = []
	if got.size() == 2:
		uids = got[1]
	_check(uids.size() == 1 and Armory.get_item(uids[0]).def_id == &"club"
			and Armory.get_item(uids[0]).rarity == Enums.Rarity.UNCOMMON, "gear created in Armory with its rarity")
	_check(pile.is_empty() and pile.is_queued_for_deletion(), "an emptied pile goes away")
	Bag.load_data(bag_before)
	for uid in uids:
		Armory.remove_item(uid)


func _test_statue() -> void:
	var statue := _spawn(_load(&"statue"), Vector3.ZERO)
	statue.velocity = Vector3.ONE
	_ticks(statue, DT)
	_check(statue.velocity == Vector3.ONE * Vector3(0, 1, 0) and statue.get_behavior(&"noise_only").is_frozen(),
			"statue stands still with no noise")
	statue.hear(Vector3(5, 0, 0), null)
	_ticks(statue, MonsterRules.SUSPICIOUS_SEC + 3 * DT)
	_check(statue.state == Enums.AIState.INVESTIGATE and statue.velocity.x > 0.0, "noise makes it move")
	_ticks(statue, MonsterRules.STATUE_QUIET_SEC)
	_check(statue.velocity.x == 0.0 and statue.get_behavior(&"noise_only").is_frozen(), "quiet again: it freezes")
	# Blind, but it still hits what touches it.
	var player := _player(Vector3(0, 0, -1))
	statue.hear(player.global_position, null)
	statue.chase(player)
	_ticks(statue, MonsterRules.ATTACK_WINDUP_SEC + 2 * DT)
	_check(statue.state == Enums.AIState.ATTACK and player.hits.size() == 1, "blind statue attacks at touch range")


func _test_mist() -> void:
	var mist := _spawn(_load(&"mist"), Vector3.ZERO)
	var body := mist.get_node("Body") as Node3D
	var player := _player(Vector3(0, 0, -10))
	_ticks(mist, DT)
	_check(not body.visible, "mist is hidden from 10 m")
	player.global_position = Vector3(0, 0, -2.5)
	_ticks(mist, DT)
	_check(body.visible, "mist shows within 3 m")
	player.global_position = Vector3(0, 0, -10)
	_ticks(mist, DT)
	_check(not body.visible, "hidden again when the player backs off")
	mist.get_behavior(&"mist").reveal(1.0)
	_check(body.visible, "a flash reveals it")
	_ticks(mist, 1.0 + DT)
	_check(not body.visible, "the flash wears off")
	player.global_position = Vector3(0, 0, -1)
	mist.chase(player)
	_ticks(mist, MonsterRules.ATTACK_WINDUP_SEC + 2 * DT)
	_check(player.hits.size() == 1 and player.hits[0].info.get("slow_sec", 0.0) > 0.0, "mist contact slows")


func _test_neon_moth() -> void:
	var tree := _root.get_tree()
	var moth := _spawn(_load(&"neon_moth"), Vector3.ZERO)
	var player := _player(Vector3(0, 0, -0.8))
	var kills: Array = []
	var on_kill := func(id: StringName, _e: Enums.Element, _p: Vector3) -> void: kills.append(id)
	var blasts: Array = []
	var on_noise := func(_pos: Vector3, radius: float, source: Node) -> void:
		if source == moth:
			blasts.append(radius)
	EventBus.monster_killed.connect(on_kill)
	EventBus.noise_emitted.connect(on_noise)
	moth.chase(player)
	_ticks(moth, MonsterRules.ATTACK_WINDUP_SEC + 2 * DT)
	EventBus.monster_killed.disconnect(on_kill)
	EventBus.noise_emitted.disconnect(on_noise)
	_check(player.hits.size() == 1 and is_equal_approx(player.hits[0].amount, 25.0), "neon moth self-destruct hits for 25")
	_check(blasts == [MonsterRules.SELF_DESTRUCT_NOISE], "self-destruct is a 15 m noise")
	_check(moth.is_dead() and moth.is_queued_for_deletion(), "the moth is gone")
	_check(kills.is_empty(), "self-destruct is not a kill")
	await tree.process_frame
	_check(_piles().is_empty(), "self-destruct drops nothing")


func _test_signal_wraith() -> void:
	var tree := _root.get_tree()
	var wraith := _spawn(_load(&"signal_wraith"), Vector3.ZERO)
	var body := FakeBody.new()
	body.add_to_group(Monster.PLAYER_GROUP)
	body.position = Vector3(0, 0, -8)
	_root.add_child(body)
	await tree.physics_frame
	wraith.chase(body)
	_ticks(wraith, DT)
	_check(wraith.state == Enums.AIState.ATTACK, "signal wraith attacks from 8 m")
	_ticks(wraith, MonsterRules.ATTACK_WINDUP_SEC + DT)
	var orbs: Array[ShockOrb] = []
	for child in _root.get_children():
		if child is ShockOrb:
			orbs.append(child)
	_check(orbs.size() == 1 and body.hits.is_empty(), "it fires one orb instead of a melee hit")
	if orbs.size() != 1:
		return
	var orb := orbs[0]
	for i in 100:
		if orb.is_queued_for_deletion():
			break
		orb.advance(0.05)
	_check(body.hits.size() == 1 and is_equal_approx(body.hits[0].amount, 15.0)
			and body.hits[0].info.get("shock_sec", 0.0) > 0.0, "the orb hits for 15 and shocks")
	await tree.process_frame
	var field: ShockField
	for child in _root.get_children():
		if child is ShockField:
			field = child
	_check(field != null, "the orb leaves a shock field")
	if field == null:
		return
	await tree.physics_frame
	for i in ceili(MonsterRules.SHOCK_FIELD_SEC / DT) + 1:
		field.advance(DT)
	var ticks := ceili(MonsterRules.SHOCK_FIELD_SEC / MonsterRules.SHOCK_FIELD_TICK_SEC)
	_check(body.hits.size() == 1 + ticks, "shock field zaps every 0.5 s for 3 s (%d hits)" % body.hits.size())
	_check(field.is_queued_for_deletion(), "the field is gone after 3 s")


func _test_rally() -> void:
	var vine := _load(&"vine_tendril")
	var caller := _spawn(vine, Vector3.ZERO)
	caller.make_elite()
	var near := _spawn(vine, Vector3(10, 0, 0))
	var pod := _spawn(_load(&"spore_pod"), Vector3(0, 0, 8))
	var far := _spawn(vine, Vector3(MonsterRules.RALLY_RADIUS + 3.0, 0, 0))
	var stone := _spawn(_load(&"rubble_bug"), Vector3(-5, 0, 0))
	var player := _player(Vector3(0, 0, -3))
	caller.chase(player)
	_check(near.state == Enums.AIState.CHASE and near.target == player, "elite rally: nearby vine tendril chases too")
	_check(pod.state == Enums.AIState.CHASE, "rally calls the same family")
	_check(far.state != Enums.AIState.CHASE, "monsters beyond 15 m are not called")
	_check(stone.state != Enums.AIState.CHASE, "other families are not called")


# --- Helpers --------------------------------------------------------------

func _load(id: StringName) -> MonsterDef:
	return load(DIR + String(id) + ".tres") as MonsterDef


func _spawn(def: MonsterDef, pos: Vector3) -> Monster:
	var m := def.scene.instantiate() as Monster
	m.def = def
	m.position = pos
	_root.add_child(m)
	m.set_physics_process(false)  # tests drive tick() by hand
	return m


func _player(pos: Vector3) -> FakeTarget:
	var p := FakeTarget.new()
	p.add_to_group(Monster.PLAYER_GROUP)
	p.position = pos
	_root.add_child(p)
	return p


func _piles() -> Array[MonsterDropPile]:
	var out: Array[MonsterDropPile] = []
	for child in _root.get_children():
		if child is MonsterDropPile:
			out.append(child)
	return out


func _ticks(m: Monster, seconds: float) -> void:
	for i in ceili(seconds / DT):
		m.tick(DT)


func _check(cond: bool, what: String) -> void:
	if not cond:
		push_error("test_monster_roster: " + what)
		_ok = false
