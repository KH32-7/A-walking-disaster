extends Node
## B-17: companion residents. V tap / hold split, health 80 + 힘 x 5 + 방어구, damage (적성, 능력치),
## spread (감각), Q skill (적성 상, cooldown x1.5), spawning from the loadout, the three modes,
## shooting (no friendly fire), downed / help up 3 s / stranded after 30 s, traits (겁이 많음, 용감함,
## 조용한 발걸음), MOBILITY nav layers, HUD entries.
## Companions are driven with tick(); their own physics process is off.

const DT := 1.0 / 60.0
const EPS := 0.01
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const COMPANION_SCENE := preload("res://field/companion/field_companion.tscn")
const VINE_DEF := preload("res://data/monsters/vine_tendril.tres")
const TUNING := preload("res://data/classes/companion_tuning.tres")
const NOISE_TABLE := preload("res://field/noise/noise_table.tres")
const TEST_HP := 10000.0
const Mode := FieldCompanion.Mode
const State := FieldCompanion.State

var _ok := true
var _root: Node3D
var _player: Player
var _created: Array[StringName] = []
var _noises: Array = []
var _stranded: Array = []


func run() -> bool:
	_ok = true
	var colony_before := Colony.save_data()
	var field_before := FieldState.save_data()
	var router_before := SceneRouter.save_data()
	EventBus.noise_emitted.connect(_on_noise)
	EventBus.companion_stranded.connect(_on_stranded)

	_test_command_press()
	_test_data()
	_root = Node3D.new()
	add_child(_root)
	_player = PLAYER_SCENE.instantiate()
	_player.set_physics_process(false)
	_root.add_child(_player)
	_player.get_node(^"Weapons").set_physics_process(false)
	await _physics()

	_test_health()
	_test_damage_and_spread()
	_test_skill()
	_test_spawn_and_modes()
	await _test_targets()
	await _test_shooting_and_melee()
	_test_downed()
	_test_status()
	_test_stranded_by_signal()
	_test_traits()
	_test_hud()

	_root.free()
	for uid in _created:
		Armory.remove_item(uid)
	EventBus.noise_emitted.disconnect(_on_noise)
	EventBus.companion_stranded.disconnect(_on_stranded)
	Colony.load_data(colony_before)
	FieldState.load_data(field_before)
	SceneRouter.load_data(router_before)
	return _ok


func _test_command_press() -> void:
	var p := CommandPress.new()
	_check(p.update(true, DT) == CommandPress.Result.NONE, "press: nothing yet")
	_check(p.update(false, DT) == CommandPress.Result.TAP, "short press = tap")
	var fired := []
	for i in 40:
		fired.append(p.update(true, DT))
	_check(fired.count(CommandPress.Result.HOLD) == 1 and not fired.has(CommandPress.Result.TAP), "hold fires once")
	_check(p.update(false, DT) == CommandPress.Result.NONE, "release after a hold is not a tap")


func _test_data() -> void:
	_check(TUNING.base_health == 80.0 and TUNING.health_per_str == 5.0, "03: 80 + str x 5")
	_check(TUNING.skill_cooldown_mult == 1.5, "03: skill cooldown x1.5")
	for action: StringName in TUNING.mode_footstep.values():
		_check(NOISE_TABLE.has_action(action) and NOISE_TABLE.is_footstep(action), "footstep action %s" % action)
	_check(NOISE_TABLE.base_radius(&"companion_quiet") < NOISE_TABLE.base_radius(&"escort_walk"), "신중 is quieter")


func _test_health() -> void:
	var t: CompanionTuning = TUNING
	_check(is_equal_approx(FieldCompanion.max_health_for({"stats": {&"str": 6}}, {}, t), 110.0), "80 + 6 x 5")
	_check(is_equal_approx(FieldCompanion.max_health_for({"stats": {&"str": 6}}, {"defense": 22.0, "max_hp": 10}, t), 142.0),
			"armor defense and max_hp affix add")
	var id := _resident({"stats": {"str": 4}})
	_equip(id, &"flak_vest", Enums.EquipSlot.BODY)
	var c := _companion(id, Vector3(2, 0, 0))
	var defense := float(Armory.get_owner_summary(id)["defense"])
	_check(defense > 0.0 and is_equal_approx(c.max_health, 100.0 + defense), "equipped vest counts (%.1f)" % c.max_health)
	_check(c.health == c.max_health, "starts at full health")
	c.free()


func _test_damage_and_spread() -> void:
	var stats := {"damage": 20.0, "combat_class": Enums.CombatClass.BLUNT}
	var high := _companion(_resident({"stats": {"str": 5}, "class_aptitude": {"blunt": Enums.Aptitude.HIGH, "gun": Enums.Aptitude.MID}}), Vector3.ZERO)
	var low := _companion(_resident({"stats": {"str": 5}, "class_aptitude": {"blunt": Enums.Aptitude.LOW}}), Vector3.ZERO)
	_check(absf(high.hit_damage(stats, 1.0) - 20.0 * 1.15 * 1.15) < EPS, "적성 상 x1.15, 힘 5 x1.15")
	_check(absf(low.hit_damage(stats, 1.0) - 20.0 * 0.7 * 1.15) < EPS, "적성 하 x0.7")
	_check(absf(high.hit_damage(stats, 1.5) - 20.0 * 1.15 * 1.15 * 1.5) < EPS, "crit x1.5")
	var gun := {"damage": 20.0, "combat_class": Enums.CombatClass.GUN, "def_id": &"pistol"}
	_check(absf(high.hit_damage(gun, 1.0) - 20.0) < EPS, "gun: no stat bonus, 적성 중 x1.0")
	high.free()
	low.free()
	var sharp := _companion(_resident({"stats": {"sense": 10}}), Vector3.ZERO)
	var dull := _companion(_resident({"stats": {"sense": 1}}), Vector3.ZERO)
	var base: float = sharp.combat.weapon_value(&"pistol", Enums.CombatClass.GUN, "spread_deg", 0.0)
	_check(base > 0.0 and absf(sharp.spread_deg(gun) - base * 0.7) < EPS, "감각 10: spread -30%")
	_check(absf(dull.spread_deg(gun) - base * 0.97) < EPS, "감각 1: spread -3%")
	sharp.free()
	dull.free()


func _test_skill() -> void:
	var gun := {"combat_class": Enums.CombatClass.GUN}
	var high := _companion(_resident({"class_aptitude": {"gun": Enums.Aptitude.HIGH}}), Vector3.ZERO)
	var used := []
	high.skill_used.connect(func(cls: int) -> void: used.append(cls))
	_check(high.try_skill(gun) and used == [Enums.CombatClass.GUN], "적성 상: Q used")
	_check(is_equal_approx(high.skill_time_left(), 15.0), "gun Q 10 s x1.5 = 15 s")
	_check(not high.try_skill(gun), "on cooldown")
	high.free()
	var mid := _companion(_resident({"class_aptitude": {"gun": Enums.Aptitude.MID}}), Vector3.ZERO)
	_check(not mid.try_skill(gun), "적성 중: no skill")
	mid.free()


func _test_spawn_and_modes() -> void:
	var adult := _resident({"name": "한만석"})
	var child := _resident({"name": "아이", "age_stage": Enums.AgeStage.CHILD})
	var wheel := _resident({"name": "휠체어", "access_needs": [Enums.AccessNeed.MOBILITY]})
	var extra := _resident({"name": "셋째"})
	_player.global_position = Vector3(0, 0, 10)
	var m := CompanionManager.new()
	m.spawn_on_ready = false
	_root.add_child(m)
	var placed := m.spawn_ids([child, adult, &"nobody", wheel, extra])
	_check(placed.size() == 2, "child and unknown skipped, cap 2 (%d)" % placed.size())
	var c := placed[0]
	_check(c.party_id == adult and c.display_name == "한만석", "resident id and name")
	_check(c.is_in_group(ExtractionManager.PARTY_GROUP) and c.party_kind == ExtractionManager.KIND_COMPANION,
			"in the extraction party as companion")
	_check(c.get_collision_layer_value(Enums.LAYER_ALLY) and not c.get_collision_layer_value(Enums.LAYER_INTERACTABLE),
			"layer 3 while up")
	_check(absf(c.global_position.distance_to(_player.global_position) - TUNING.spawn_offset) < EPS, "beside the player")
	_check(placed[1].global_position.distance_to(c.global_position) > 1.0, "second one on the other side")
	_check(c.navigation_layers() == FieldCompanion.NAV_ALL and placed[1].navigation_layers() == FieldCompanion.NAV_NO_STAIRS,
			"MOBILITY: no stairs nav layer")
	_check(m.cycle_mode() == Mode.CAUTIOUS and c.mode == Mode.CAUTIOUS and placed[1].mode == Mode.CAUTIOUS,
			"hold V: everyone 신중")
	_check(m.cycle_mode() == Mode.COVER and m.cycle_mode() == Mode.AGGRESSIVE, "엄호, then back to 공격적")
	m.free()


func _test_targets() -> void:
	_player.global_position = Vector3(0, 0, 0)
	var c := _companion(_resident({}), Vector3(1, 0, 0))
	var near: Monster = await _monster(Vector3(1, 0, -5))
	_check(c.pick_target() == near, "공격적: nearest visible monster")
	var wall := _box(Vector3(1, 1, -2.5), Vector3(4, 2, 0.3))
	await _physics()
	_check(c.pick_target() == null, "wall blocks sight")
	wall.free()
	var cover := _box(Vector3(1, 0.6, -2.5), Vector3(4, 1.2, 0.3))
	cover.add_to_group(WeaponHolder.LOW_COVER_GROUP)
	await _physics()
	_check(c.pick_target() == near, "low cover does not block")
	cover.free()
	await _physics()

	c.set_mode(Mode.CAUTIOUS)
	_check(c.pick_target() == null, "신중: ignores monsters the player has not hit")
	var weapons := _player.get_node(^"Weapons") as WeaponHolder
	c.tick(DT)  # binds the player
	weapons.hit_landed.emit(near, 10.0, {})
	_check(c.pick_target() == near, "신중: attacks what the player hit")
	var other: Monster = await _monster(Vector3(-1, 0, -4))
	c._marked.clear()
	c.take_damage(1.0, {"source": other})
	_check(c.pick_target() == other, "신중: fights back against what hits it")

	c.set_mode(Mode.COVER)
	var rescued := _rescued_dummy(Vector3(20, 0, 0))
	await _physics()
	_check(c.anchor() == rescued, "엄호: stays by the rescued person")
	_check(c.pick_target() == null, "엄호: monsters near itself but far from the rescued person are ignored")
	var by_rescued: Monster = await _monster(Vector3(20, 0, -4))
	_check(c.pick_target() == by_rescued, "엄호: monster close to the rescued person")
	rescued.free()
	_check(c.anchor() == _player, "엄호 without rescued people: the player")
	near.free()
	other.free()
	by_rescued.free()
	c.free()


func _test_shooting_and_melee() -> void:
	_player.global_position = Vector3(0, 0, -2.5)
	var id := _resident({"class_aptitude": {"gun": Enums.Aptitude.HIGH}})
	_equip(id, &"pistol", Enums.EquipSlot.MAIN)
	var c := _companion(id, Vector3(0, 0, 0))
	c.combat = _exact_combat()
	var monster: Monster = await _monster(Vector3(0, 0, -5))
	c.target = monster
	var stats := c.weapon_stats()
	var player_hp := _player.health
	_noises.clear()
	_check(c.attack(stats), "shoots")
	var expected := c.hit_damage(stats, 1.0) * Enums.element_multiplier(stats.get("element", Enums.Element.NONE),
			VINE_DEF.family) * MonsterRules.defense_factor(VINE_DEF.defense)
	_check(absf(TEST_HP - monster.hp - expected) < EPS, "pistol damage x 적성 상 (%.2f vs %.2f)" % [TEST_HP - monster.hp, expected])
	_check(_player.health == player_hp, "the player in the line of fire is not hit")
	_check(_noise_from(c) == NOISE_TABLE.base_radius(&"pistol"), "gunshot noise from the companion")
	_check(not c.attack(stats), "waits attack_interval")
	# Magazine empties, then reload.
	for i in int(stats["magazine"]) - 1:
		c._attack_left = 0.0
		c.attack(stats)
	c._attack_left = 0.0
	_check(not c.attack(stats), "empty magazine: reloading")
	monster.hp = TEST_HP
	_check(c.try_skill(stats), "Q in combat with 적성 상")
	c.free()

	var bid := _resident({"stats": {"str": 10}, "class_aptitude": {"blunt": Enums.Aptitude.LOW}})
	_equip(bid, &"club", Enums.EquipSlot.MAIN)
	var b := _companion(bid, Vector3(0, 0, -4))
	b.combat = _exact_combat()
	b.target = monster
	var club := b.weapon_stats()
	_check(b.attack(club), "club swing in reach")
	var swing := b.hit_damage(club, 1.0) * Enums.element_multiplier(club.get("element", Enums.Element.NONE),
			VINE_DEF.family) * MonsterRules.defense_factor(VINE_DEF.defense)
	_check(absf(TEST_HP - monster.hp - swing) < EPS and absf(b.hit_damage(club, 1.0) - float(club["damage"]) * 0.7 * 1.3) < EPS,
			"club x 적성 하 0.7 x 힘 10 1.3")
	b.free()
	monster.free()


func _test_downed() -> void:
	var id := _resident({})
	FieldState.companions.assign([id])
	var c := _companion(id, Vector3(0, 0, 0))
	_player.global_position = Vector3(1, 0, 0)
	c.take_damage(c.max_health, {})
	_check(c.state == State.DOWNED, "health 0: downed")
	_check(not c.get_collision_layer_value(Enums.LAYER_ALLY) and c.get_collision_layer_value(Enums.LAYER_INTERACTABLE),
			"downed: off layer 3, on layer 7")
	_check(c.hud_entry()["command"] == FieldCompanion.DOWNED_LABEL and c.hud_entry()["hp"] == 0.0, "HUD shows it")
	_ticks(c, 10.0)
	_check(c.begin_open(_player), "F: start helping up")
	_check(not c.begin_open(_player), "already being helped")
	_ticks(c, TUNING.revive_sec - 0.2)
	_check(c.state == State.DOWNED and c.hold_state()["progress"] > 0.9, "still downed before 3 s")
	_ticks(c, 0.3)
	_check(c.state == State.ACTIVE and is_equal_approx(c.health, c.max_health * TUNING.revive_health_ratio),
			"helped up after 3 s with half health")

	c.take_damage(c.max_health, {})
	c.begin_open(_player)
	_ticks(c, 1.0)
	_player.global_position = Vector3(5, 0, 0)
	_ticks(c, DT)
	_check(c.hold_state().is_empty(), "walking away cancels the help")
	_check(absf(c.down_time_left() - (TUNING.downed_sec - DT)) < 0.05, "the 30 s wait paused while helped")
	_stranded.clear()
	_ticks(c, TUNING.downed_sec)
	_check(c.state == State.STRANDED and _stranded == [id], "not helped in 30 s: stranded once")
	_check(not FieldState.companions.has(id) and not c.is_in_group(ExtractionManager.PARTY_GROUP),
			"left FieldState.companions and the party")
	_check(not c.get_collision_layer_value(Enums.LAYER_ALLY) and not c.get_collision_layer_value(Enums.LAYER_INTERACTABLE),
			"stranded: no layers")
	c.free()


## B-14 StatusHolder: hits carry effects, bleed ticks, stagger stops actions, downed clears.
func _test_status() -> void:
	var c := _companion(_resident({}), Vector3.ZERO)
	var start := c.health
	c.take_damage(1.0, {"status": [{"id": &"bleed"}, {"id": &"stagger", "duration": 1.0}]})
	_check(c.status.has(&"bleed") and c.status.has(&"stagger"), "hit applies bleed and stagger")
	_check(not c.status.can_act(), "staggered: no actions")
	_ticks(c, 1.05)
	_check(c.health < start - 1.0, "bleed ticks (%.1f -> %.1f)" % [start, c.health])
	_check(c.status.can_act(), "stagger wears off")
	c.take_damage(c.health, {})
	_check(c.state == State.DOWNED and not c.status.has(&"bleed"), "downed clears statuses")
	c.free()


func _test_stranded_by_signal() -> void:
	var id := _resident({})
	var c := _companion(id, Vector3.ZERO)
	var fired := [false]
	c.stranded.connect(func() -> void: fired[0] = true)
	EventBus.companion_stranded.emit(&"someone_else", &"flooded_mall")
	_check(c.state == State.ACTIVE, "another resident's stranding does not matter")
	EventBus.companion_stranded.emit(id, &"flooded_mall")
	_check(c.state == State.STRANDED and fired[0], "player down / left at extraction: stranded")
	c.free()


func _test_traits() -> void:
	var timid := _companion(_resident({"traits": [&"timid"]}), Vector3.ZERO)
	timid.health = timid.max_health * 0.31
	_check(not timid.is_retreating(), "timid above 30%")
	timid.health = timid.max_health * 0.3
	_check(timid.is_retreating() and timid.hud_entry()["command"] == FieldCompanion.RETREAT_LABEL, "timid: 30% retreats")
	timid.free()
	var brave := _companion(_resident({"traits": [&"brave"]}), Vector3.ZERO)
	brave.health = 1.0
	_check(not brave.is_retreating(), "brave never retreats")
	brave.free()

	_player.global_position = Vector3(20, 0, 0)
	var quiet := _companion(_resident({"traits": [&"quiet_step"]}), Vector3.ZERO)
	var loud := _companion(_resident({"traits": [&"brave"]}), Vector3(0, 0, 3))
	for c: FieldCompanion in [quiet, loud]:
		c.velocity = Vector3(3, 0, 0)
	_noises.clear()
	quiet._update_noise()
	loud._update_noise()
	_check(_noise_from(loud) == 4.0 and _noise_from(quiet) == 2.0, "조용한 발걸음: footsteps -2m")
	loud.set_mode(Mode.CAUTIOUS)
	_noises.clear()
	loud._update_noise()
	_check(_noise_from(loud) == NOISE_TABLE.base_radius(&"companion_quiet"), "신중: quiet footsteps")
	quiet.free()
	loud.free()


func _test_hud() -> void:
	var c := _companion(_resident({"name": "한만석"}), Vector3.ZERO)
	c.health = c.max_health * 0.5
	var list: Array = _player.hud_state()["companions"]
	_check(list.size() == 1 and list[0]["name"] == "한만석" and absf(list[0]["hp"] - 0.5) < EPS
			and list[0]["command"] == "공격적", "hud_state companions entry")
	c.free()


# --- Helpers -------------------------------------------------------------------

func _resident(profile: Dictionary) -> StringName:
	return Colony.add_resident(profile)


func _equip(owner: StringName, def_id: StringName, slot: Enums.EquipSlot) -> StringName:
	var uid := Armory.create_item(def_id, Enums.Rarity.COMMON)
	_created.append(uid)
	_check(Armory.equip(owner, slot, uid), "equip %s" % def_id)
	return uid


func _companion(id: StringName, at: Vector3) -> FieldCompanion:
	var c: FieldCompanion = COMPANION_SCENE.instantiate()
	c.setup(id, Colony.get_resident(id))
	_root.add_child(c)
	# After add_child: _ready turns processing back on for scripts with _physics_process.
	c.set_physics_process(false)
	c.global_position = at
	return c


## Crits off and no spread, so single hits are exact.
func _exact_combat() -> CombatTuning:
	var t: CombatTuning = FieldCompanion.DEFAULT_COMBAT.duplicate(true)
	t.crit_rate = 0.0
	for def_id: StringName in t.weapon_types:
		t.weapon_types[def_id]["spread_deg"] = 0.0
	t.class_defaults[Enums.CombatClass.GUN]["spread_deg"] = 0.0
	return t


func _monster(pos: Vector3) -> Monster:
	var monster: Monster = VINE_DEF.scene.instantiate()
	monster.def = VINE_DEF
	_root.add_child(monster)
	monster.set_physics_process(false)
	monster.global_position = pos
	monster.max_hp = TEST_HP
	monster.hp = TEST_HP
	await _physics()
	return monster


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	_root.add_child(body)
	body.global_position = pos
	return body


## A rescued person in the party (only what FieldCompanion reads).
func _rescued_dummy(pos: Vector3) -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar party_kind := &\"rescued\"\n"
	script.reload()
	var node := Node3D.new()
	node.set_script(script)
	node.add_to_group(ExtractionManager.PARTY_GROUP)
	_root.add_child(node)
	node.global_position = pos
	return node


func _ticks(c: FieldCompanion, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		c.tick(minf(DT, left))
		left -= DT


func _physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _on_noise(_position: Vector3, radius: float, source: Node) -> void:
	_noises.append([radius, source])


func _on_stranded(resident_id: StringName, _region_id: StringName) -> void:
	_stranded.append(resident_id)


func _noise_from(n: Node) -> float:
	for e in _noises:
		if e[1] == n:
			return e[0]
	return -1.0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_ok = false
		printerr("  FAIL companion: %s" % msg)
