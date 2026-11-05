extends Node
## B-16: consumable data (6 kinds), sticky quick slots, use time (move limits, cancel rules),
## heal / bandage / painkiller on the player, throwing (target clamp, arc), lure noise after its
## delay, flash blind + LIGHT heal + mist reveal, blast damage and noise, HUD keys.
## Bodies are driven with step()/tick()/advance(); their physics is off.

const DT := 1.0 / 60.0
const EPS := 0.01
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const MONSTER_SCENE := preload("res://field/monsters/monster_base.tscn")
const VINE_DEF := preload("res://data/monsters/vine_tendril.tres")
const MIST_DEF := preload("res://data/monsters/mist.tres")
const IDS: Array[StringName] = [&"first_aid_kit", &"bandage", &"painkiller", &"noise_lure",
		&"flashbang", &"grenade"]

var _ok := true
var _saved_bag: Dictionary
var _noises: Array = []


func run() -> bool:
	_ok = true
	_saved_bag = Bag.save_data().duplicate(true)
	EventBus.noise_emitted.connect(_on_noise)
	_test_defs()
	_test_slots()
	_test_medkit()
	_test_cancel_rules()
	_test_bandage_and_painkiller()
	_test_throw()
	_test_lure()
	_test_flash()
	_test_blast()
	EventBus.noise_emitted.disconnect(_on_noise)
	Bag.load_data(_saved_bag)
	return _ok


func _test_defs() -> void:
	for id in IDS:
		var def := ConsumableUser.get_def(id)
		_expect(def != null and def.id == id, "%s.tres loads with its id" % id)
	_expect(ConsumableUser.all_defs().size() == IDS.size(), "6 consumable kinds")
	_expect(ConsumableUser.all_defs()[0].id == &"first_aid_kit", "medkit has the first slot priority")
	var kit := ConsumableUser.get_def(&"first_aid_kit")
	_expect_near(kit.heal, 50.0, "medkit +50")
	_expect_near(kit.use_sec, 3.0, "medkit 3 s")
	_expect(kit.can_move and kit.heal_perk_stat == &"medkit_pct", "medkit: slow walk, medic perk")
	var bandage := ConsumableUser.get_def(&"bandage")
	_expect(is_equal_approx(bandage.heal, 15.0) and is_equal_approx(bandage.use_sec, 1.5) \
			and bandage.remove_status == &"bleed", "bandage: bleed off, +15, 1.5 s")
	var pill := StatusHolder.get_def(&"painkiller")
	_expect(pill != null and is_equal_approx(pill.duration_sec, 10.0) and is_equal_approx(pill.damage_mult, 0.8),
			"painkiller status: 10 s, damage x0.8")
	var blind := StatusHolder.get_def(&"blind")
	_expect(blind != null and is_equal_approx(blind.duration_sec, 3.0) and blind.sight_mult == 0.0,
			"blind status: 3 s, no sight")
	var lure := ConsumableUser.get_def(&"noise_lure")
	var table: NoiseTable = NoiseEmitter.DEFAULT_TABLE
	_expect(is_equal_approx(lure.delay_sec, 4.0) and is_equal_approx(table.base_radius(lure.noise), 15.0),
			"lure: 15 m after 4 s")
	var bomb := ConsumableUser.get_def(&"grenade")
	_expect(is_equal_approx(bomb.radius, 3.0) and is_equal_approx(bomb.damage, 60.0) \
			and is_equal_approx(table.base_radius(bomb.noise), 25.0), "grenade: 3 m, 60, noise 25 m")


func _test_slots() -> void:
	_reset_bag()
	var p := _player()
	var user := p.consumables
	Bag.try_add(&"noise_lure", 1)
	Bag.try_add(&"first_aid_kit", 2)
	_expect(user.slots == ([&"noise_lure", &"first_aid_kit", &"", &""] as Array[StringName]),
			"kinds take the lowest free slot in the order they show up")
	Bag.try_add(&"bandage", 1)
	_expect(user.slots[2] == &"bandage", "a new kind goes to the next free slot")
	Bag.remove_item(&"noise_lure", 1)
	_expect(user.slots[0] == &"" and user.slots[1] == &"first_aid_kit", "a used-up kind frees its slot, others stay")
	Bag.load_data({})
	Bag.resize(Vector2i(4, 5))
	for id in IDS:
		Bag.try_add(id, 1)
	user.slots.assign([&"", &"", &"", &""])
	user.refresh_slots()
	_expect(user.slots == ([&"first_aid_kit", &"bandage", &"noise_lure", &"painkiller"] as Array[StringName]),
			"several at once: slot priority, the 5th kind waits")
	Bag.remove_item(&"bandage", 1)
	_expect(user.slots[1] == &"flashbang", "a waiting kind fills a freed slot")
	var hud := user.hud_slots()
	_expect(hud.size() == 4 and hud[0]["count"] == 1 and hud[0]["name"] == "구급상자" and hud[0]["rarity"] == 0,
			"HUD slot: name, count, rarity")
	var state := p.hud_state()
	_expect(state.has("consumables") and (state["consumables"] as Array).size() == 4, "hud_state has consumables")
	p.free()


func _test_medkit() -> void:
	_reset_bag()
	var p := _player()
	var user := p.consumables
	Bag.try_add(&"first_aid_kit", 2)
	p.health = 20.0
	var finished: Array = []
	user.use_finished.connect(func(id: StringName) -> void: finished.append(id))
	_expect(user.use_slot(0) and user.is_using(), "key 3 starts the medkit")
	_expect(not user.use(&"first_aid_kit"), "one use at a time")
	var hold: Dictionary = p.hud_state()["hold"]
	_expect(hold.get("label") == "구급상자 사용 중" and is_equal_approx(hold.get("progress", -1.0), 0.0), "hold bar shows it")
	var input := user.filter_input({"move": Vector2(1, 0), "sprint": true})
	_expect(is_equal_approx((input["move"] as Vector2).x, ConsumableUser.USE_MOVE_MULT) and not input["sprint"],
			"medkit: slow walk, no sprint")
	_steps(user, 2.9)
	_expect(user.is_using() and Bag.count_of(&"first_aid_kit") == 2 and is_equal_approx(p.health, 20.0),
			"nothing happens before 3 s")
	_steps(user, 0.2)
	_expect(not user.is_using() and finished == [&"first_aid_kit"], "medkit finishes at 3 s")
	_expect(Bag.count_of(&"first_aid_kit") == 1 and is_equal_approx(p.health, 70.0), "medkit: one used, +50")
	p.health = p.stats.max_health - 10.0
	user.use(&"first_aid_kit")
	_steps(user, 3.1)
	_expect(is_equal_approx(p.health, p.stats.max_health), "healing stops at max hp")
	_expect(user.slots[0] == &"" and not user.use_slot(0), "empty slot does nothing")
	p.free()


func _test_cancel_rules() -> void:
	_reset_bag()
	var p := _player()
	var user := p.consumables
	Bag.try_add(&"bandage", 3)
	var cancelled: Array = []
	user.use_cancelled.connect(func(id: StringName) -> void: cancelled.append(id))
	user.use(&"bandage")
	var input := user.filter_input({"move": Vector2(1, 0)})
	_expect(input["move"] == Vector2.ZERO, "bandage: stand still")
	user.filter_input({"move": Vector2.ZERO, "dodge": true})
	_expect(not user.is_using() and cancelled == [&"bandage"] and Bag.count_of(&"bandage") == 3,
			"dodge cancels and keeps the item")
	user.use(&"bandage")
	p.take_damage(5.0, {})
	_steps(user, 0.1)
	_expect(user.is_using(), "a plain hit does not cancel")
	p.stun(0.5)
	_steps(user, DT)
	_expect(not user.is_using() and Bag.count_of(&"bandage") == 3, "stagger cancels")
	_expect(not user.use(&"bandage"), "cannot start while staggered")
	p.status.clear()
	var weapons := p.get_node_or_null(^"Weapons") as WeaponHolder
	if weapons:
		user.use(&"bandage")
		weapons.attacked.emit(&"swing", 0)
		_expect(not user.is_using(), "attacking cancels")
	p.free()


func _test_bandage_and_painkiller() -> void:
	_reset_bag()
	var p := _player()
	var user := p.consumables
	Bag.try_add(&"bandage", 1)
	Bag.try_add(&"painkiller", 1)
	p.health = 50.0
	p.status.apply(&"bleed")
	user.use(&"bandage")
	_steps(user, 1.6)
	_expect(not p.status.has(&"bleed") and is_equal_approx(p.health, 65.0), "bandage: bleed off, +15")
	user.use(&"painkiller")
	_steps(user, 1.1)
	_expect(p.status.has(&"painkiller") and Bag.count_of(&"painkiller") == 0, "painkiller on after 1 s")
	var hp := p.health
	p.take_damage(10.0, {})
	_expect_near(hp - p.health, 8.0, "painkiller: hits -20%")
	p.free()


func _test_throw() -> void:
	_reset_bag()
	var p := _player()
	var user := p.consumables
	p.set_aim_point(Vector3(3, 0, 4))
	_expect(user.throw_target().distance_to(Vector3(3, 0, 4)) < EPS, "throw lands on the aim point")
	p.set_aim_point(Vector3(30, 0, 0))
	_expect(user.throw_target().distance_to(Vector3(ConsumableUser.THROW_MAX_RANGE, 0, 0)) < EPS,
			"too far: pulled in to the max range")
	p.set_aim_point(Vector3(6, 0, 0))
	Bag.try_add(&"noise_lure", 2)
	var thrown: Array = []
	user.thrown.connect(func(id: StringName, _t: Vector3) -> void: thrown.append(id))
	_expect(user.use(&"noise_lure") and thrown == [&"noise_lure"], "lure thrown at once")
	_expect(Bag.count_of(&"noise_lure") == 1 and not user.is_using(), "one lure out of the bag, no use time")
	var item: ThrownConsumable = null
	for child in get_children():
		if child is ThrownConsumable:
			item = child
	_expect(item != null and item.is_flying() and item.global_position.y > 1.0, "lure flies from the hand")
	var peak := 0.0
	for i in 120:
		if item == null or not item.is_flying():
			break
		item.advance(DT)
		peak = maxf(peak, item.global_position.y)
	_expect(item != null and not item.is_flying() and item.global_position.distance_to(Vector3(6, 0, 0)) < EPS,
			"lands on the target")
	_expect(peak > ConsumableUser.THROW_HEIGHT, "it flies an arc")
	if item:
		item.free()
	p.free()


func _test_lure() -> void:
	var m := _monster(VINE_DEF, Vector3(3, 0, 0), Enums.AIState.WANDER)
	var item := _thrown(&"noise_lure", Vector3.ZERO)
	_noises.clear()
	_steps_item(item, 3.9)
	_expect(_noises.is_empty(), "no noise before 4 s")
	_steps_item(item, 0.2)
	_expect(_noises.size() == 1 and absf(_noises[0][1] - 15.0 * _rain()) < EPS, "one 15 m noise at 4 s")
	_expect(_noises.size() == 1 and not (_noises[0][2] is Player), "the noise is not the player's")
	_expect(m.state == Enums.AIState.SUSPICIOUS or m.state == Enums.AIState.INVESTIGATE,
			"a monster in range turns to the lure")
	_expect(not is_instance_valid(item) or item.is_queued_for_deletion(), "the lure is used up")
	m.free()


func _test_flash() -> void:
	var near := _monster(VINE_DEF, Vector3(3, 0, 0), Enums.AIState.WANDER)
	var far := _monster(VINE_DEF, Vector3(20, 0, 0), Enums.AIState.WANDER)
	var light_def: MonsterDef = VINE_DEF.duplicate()
	light_def.family = Enums.Element.LIGHT
	var light := _monster(light_def, Vector3(-3, 0, 0), Enums.AIState.WANDER)
	light.hp = light.max_hp * 0.5
	var mist := _monster(MIST_DEF, Vector3(0, 0, 3), Enums.AIState.WANDER)
	var mist_behavior := mist.get_behavior(&"mist")
	_expect(mist_behavior != null and not mist_behavior.get(&"revealed"), "mist starts hidden")
	_thrown(&"flashbang", Vector3.ZERO)
	_expect(near.status.has(&"blind") and near.sight_range() == 0.0, "flash blinds a monster in range")
	_expect(not far.status.has(&"blind"), "out of range: not blinded")
	_expect(not light.status.has(&"blind") and is_equal_approx(light.hp, light.max_hp * 0.7),
			"LIGHT family heals 20% instead")
	_expect(mist_behavior.get(&"revealed"), "flash shows the mist")
	for i in roundi(3.1 / DT):
		near.tick(DT)
	_expect(not near.status.has(&"blind") and near.sight_range() > 0.0, "blind wears off after 3 s")
	for m in [near, far, light, mist]:
		m.free()


func _test_blast() -> void:
	var near := _monster(VINE_DEF, Vector3(2, 0, 0), Enums.AIState.SLEEP)
	var far := _monster(VINE_DEF, Vector3(5, 0, 0), Enums.AIState.SLEEP)
	near.hp = 500.0
	var near_hp := near.hp
	var far_hp := far.hp
	_noises.clear()
	_thrown(&"grenade", Vector3.ZERO)
	_expect_near(near_hp - near.hp, 60.0, "blast: 60 to a monster in 3 m")
	_expect(is_equal_approx(far.hp, far_hp), "blast: nothing at 5 m")
	_expect(_noises.size() == 1 and absf(_noises[0][1] - 25.0 * _rain()) < EPS, "blast: 25 m noise")
	near.free()
	far.free()


# --- Helpers ----------------------------------------------------------------

func _player() -> Player:
	var p: Player = PLAYER_SCENE.instantiate()
	p.set_physics_process(false)
	add_child(p)
	p.consumables.set_physics_process(false)
	return p


func _monster(def: MonsterDef, at: Vector3, state: Enums.AIState) -> Monster:
	var m: Monster = MONSTER_SCENE.instantiate()
	m.def = def
	m.start_state = state
	m.position = at
	add_child(m)
	m.set_physics_process(false)
	return m


## A thrown item landing at `at` (no flight): a lure starts its fuse, the rest go off now.
func _thrown(id: StringName, at: Vector3) -> ThrownConsumable:
	var item := ThrownConsumable.new()
	item.def = ConsumableUser.get_def(id)
	add_child(item)
	item.set_physics_process(false)
	item.global_position = at
	item.launch(at)
	item.land(at)
	return item


func _reset_bag() -> void:
	Bag.load_data({})
	Bag.resize(Vector2i(4, 5))


func _rain() -> float:
	return GameState.RAIN_NOISE_MULT if GameState.is_raining() else 1.0


func _steps(user: ConsumableUser, sec: float) -> void:
	for i in roundi(sec / DT):
		user.step(DT)


func _steps_item(item: ThrownConsumable, sec: float) -> void:
	for i in roundi(sec / DT):
		if is_instance_valid(item):
			item.advance(DT)


func _on_noise(point: Vector3, radius: float, source: Node) -> void:
	_noises.append([point, radius, source])


func _expect(cond: bool, message: String) -> void:
	if not cond:
		_ok = false
		printerr("FAIL test_consumables: " + message)


func _expect_near(a: float, b: float, message: String) -> void:
	_expect(absf(a - b) < EPS, "%s (got %.3f, want %.3f)" % [message, a, b])
