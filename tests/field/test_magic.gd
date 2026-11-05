extends Node
## B-15: magic weapons. Pure rules (mana, essence statuses, stagger stretch, mud, slow override), then
## a real player and real monsters: element factor applied once, water slow + wet, green bind +
## lifesteal, light chain, combo zones (thorn bush, swamp), kill combos (shard burst,
## photosynthesis), mana gains and HUD, release for gun / blunt / blade (noise 15 m, no mana).
## Weapons are engraved with A's debug command `engrave`. Proc rolls are forced through
## MagicWeapon.roll. Player, monster and weapon physics are off; the test drives step().

const DT := 1.0 / 60.0
const EPS := 0.01
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const VINE_DEF := preload("res://data/monsters/vine_tendril.tres")
const TEST_HP := 10000.0
const ALWAYS := 0.0
const NEVER := 0.999

var _ok := true
var _created: Array[StringName] = []
var _previous := {}
var _noises: Array[float] = []


class World:
	var root: Node3D
	var player: Player
	var holder: WeaponHolder
	var magic: MagicWeapon


func run() -> bool:
	_ok = true
	var progression_before := Progression.save_data().duplicate(true)
	Progression.load_data({})
	EventBus.noise_emitted.connect(_on_noise)
	_remember_loadout()

	_test_mana_rule()
	_test_hit_statuses()
	_test_stagger_and_mud()
	_test_slow_override()
	await _test_element_once()
	await _test_water_and_green()
	await _test_light_chain()
	await _test_zones()
	await _test_kill_combos()
	await _test_mana_in_world()
	await _test_release_gun()
	await _test_release_blunt()
	await _test_release_blade()

	_restore_loadout()
	EventBus.noise_emitted.disconnect(_on_noise)
	Progression.load_data(progression_before)
	return _ok


# --- Pure -------------------------------------------------------------------

func _test_mana_rule() -> void:
	_expect_near(MagicRules.add_mana(0.0, true, true, 0), 3.0, "shot hit +3")
	_expect_near(MagicRules.add_mana(0.0, false, true, 0), 5.0, "melee hit +5")
	_expect_near(MagicRules.add_mana(0.0, false, true, 1), 15.0, "kill +10")
	_expect_near(MagicRules.add_mana(95.0, false, true, 2), 100.0, "capped at 100")
	_expect(not MagicRules.is_magic({"element": Enums.Element.NONE}), "no element, not magic")
	_expect(MagicRules.is_magic({"element": Enums.Element.WATER}), "element, magic")


func _test_hit_statuses() -> void:
	var always := func() -> float: return ALWAYS
	var never := func() -> float: return NEVER
	var green := _effects([&"essence_green_low"])
	var bind := MagicRules.hit_statuses(green, always)
	_expect(bind.size() == 1 and bind[0]["id"] == &"bind" and is_equal_approx(bind[0]["duration"], 1.0),
			"green low: bind 1 s")
	_expect(MagicRules.hit_statuses(green, never).is_empty(), "green: no proc, nothing")
	_expect(MagicRules.hit_statuses(green, never, true).size() == 1, "forced (gun release) always procs")
	var stone := MagicRules.hit_statuses(_effects([&"essence_stone_low"]), always)
	_expect(stone.size() == 1 and stone[0]["id"] == &"armor_break", "stone: armor break")
	var water := MagicRules.hit_statuses(_effects([&"essence_water_low"]), always)
	_expect(water.size() == 2 and water[0]["id"] == &"slow" and is_equal_approx(water[0]["move_mult"], 0.7)
			and is_equal_approx(water[0]["duration"], 2.0) and water[1]["id"] == &"wet"
			and is_equal_approx(water[1]["duration"], 2.0), "water: slow -30% 2 s + wet 2 s")
	_expect(MagicRules.hit_statuses(_effects([&"essence_light_low"]), always).is_empty(),
			"light: no status (chain after the hit)")
	# Same essence twice comes merged from A (root 10% x1.5 = 15%): read as is, not x1.5 again.
	var twice := _effects([&"essence_green_low", &"essence_green_low"])
	_expect(MagicRules.hit_statuses(twice, func() -> float: return 0.14).size() == 1, "merged 15% procs at 0.14")
	_expect(MagicRules.hit_statuses(twice, func() -> float: return 0.16).is_empty(), "not 22.5%")


func _test_stagger_and_mud() -> void:
	var src: Array = [{"id": &"stagger", "duration": 1.5}, {"id": &"bleed"}]
	var out := MagicRules.extend_stagger(src, 0.2)
	_expect_near(out[0]["duration"], 1.8, "stone low: stagger +20%")
	_expect_near(src[0]["duration"], 1.5, "the hit's own list is not changed")
	_expect_near(MagicRules.extend_stagger([{"id": &"stagger"}], 0.5)[0]["duration"], 1.5, "default 1 s +50%")
	var mud: Dictionary = EssenceRules.weapon_effects([&"essence_stone_low", &"essence_water_low"])["combo"]
	var entries := MagicRules.combo_statuses(mud)
	_expect(mud["id"] == &"mud" and entries.size() == 2 and entries[0]["id"] == &"armor_break"
			and entries[1]["id"] == &"slow" and is_equal_approx(entries[1]["duration"], 3.0),
			"mud: armor break + slow 3 s")


func _test_slow_override() -> void:
	var body := Node.new()
	add_child(body)
	var status := StatusHolder.attach(body)
	status.apply(&"slow", {"move_mult": 0.7})
	_expect_near(status.move_mult(), 0.7, "slow with move_mult 0.7")
	status.apply(&"slow", {"move_mult": 0.9})
	_expect_near(status.move_mult(), 0.7, "a weaker slow keeps the stronger")
	status.apply(&"slow")
	_expect_near(status.move_mult(), StatusHolder.get_def(&"slow").move_mult, "def slow 0.6 is stronger")
	body.free()


# --- In the world -----------------------------------------------------------

## Monster.take_damage multiplies the element once; MagicWeapon adds nothing to the hit amount.
func _test_element_once() -> void:
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	w.magic.roll = func() -> float: return NEVER
	var vine := await _monster(w, Vector3(0, 0, -3))
	var plain := _shot_damage(w, vine)
	_engrave(&"essence_stone_low")
	_expect(w.holder.current_stats()["element"] == Enums.Element.STONE, "engraved: stone")
	_expect_near(_shot_damage(w, vine) / plain, 1.5, "stone vs green (weak) x1.5 once", 0.001)
	_engrave(&"essence_light_low")
	_expect_near(_shot_damage(w, vine) / plain, 0.75, "light vs green (resist) x0.75 once", 0.001)
	w.root.free()


func _test_water_and_green() -> void:
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	_engrave(&"essence_water_low")
	w.magic.roll = func() -> float: return ALWAYS
	var vine := await _monster(w, Vector3(0, 0, -3))
	_shot_damage(w, vine)
	_expect(vine.status.has(&"slow") and vine.status.has(&"wet"), "water: slow + wet")
	_expect_near(vine.status.move_mult(), 0.7, "essence slow -30%")
	_engrave(&"essence_green_low")
	w.player.health = 50.0
	var dealt := _shot_damage(w, vine)
	_expect(vine.status.has(&"bind"), "green: bind")
	_expect_near(w.player.health, 50.0 + dealt * 0.02, "lifesteal 2% of the damage taken", 0.001)
	w.root.free()


func _test_light_chain() -> void:
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	_engrave(&"essence_light_low")
	w.magic.roll = func() -> float: return ALWAYS
	var target := await _monster(w, Vector3(0, 0, -3))
	var near_a := await _monster(w, Vector3(1.5, 0, -3))
	var near_b := await _monster(w, Vector3(-1.5, 0, -3))
	var third := await _monster(w, Vector3(2.5, 0, -3))
	var far := await _monster(w, Vector3(5, 0, -3))
	_shot_damage(w, target)
	# 30% of the attacker-side hit, then the vine's resist to light (x0.75).
	var want := _base(w) * 0.3 * 0.75
	_expect_near(TEST_HP - near_a.hp, want, "chain to the nearest (30%, light resisted)")
	_expect_near(TEST_HP - near_b.hp, want, "chain to the second nearest")
	_expect(third.hp == TEST_HP, "only 2 chain targets")
	_expect(far.hp == TEST_HP, "out of chain range")
	w.root.free()


func _test_zones() -> void:
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN, Enums.Rarity.EPIC)
	_engrave(&"essence_green_low", 0)
	_engrave(&"essence_stone_low", 1)
	var combo: Variant = w.holder.current_stats()["combo"]
	_expect(combo != null and combo["id"] == &"thorn_bush", "green + stone: thorn bush")
	w.magic.roll = func() -> float: return ALWAYS
	var target := await _monster(w, Vector3(0, 0, -3))
	var inside := await _monster(w, Vector3(1, 0, -3))
	_shot_damage(w, target)
	var zone := _zone(w)
	_expect(zone != null and zone.combo_id == &"thorn_bush", "thorn bush zone at the target")
	if zone != null:
		zone.set_physics_process(false)
		_step_zone(zone, DT)
		_expect_near(inside.status.move_mult(), 0.7, "thorn bush slow -30%")
		_step_zone(zone, 3.0)
		_expect_near(TEST_HP - inside.hp, 15.0, "5 per second for 3 s, flat")
		_expect(zone.is_queued_for_deletion(), "zone gone after 3 s")
	w.root.free()

	w = await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN, Enums.Rarity.EPIC)
	_engrave(&"essence_green_low", 0)
	_engrave(&"essence_water_low", 1)
	w.magic.roll = func() -> float: return ALWAYS
	target = await _monster(w, Vector3(0, 0, -3))
	inside = await _monster(w, Vector3(1.8, 0, -3))
	_shot_damage(w, target)
	zone = _zone(w)
	_expect(zone != null and zone.combo_id == &"swamp", "green + water: swamp")
	if zone != null:
		zone.set_physics_process(false)
		_step_zone(zone, DT)
		_expect_near(inside.status.move_mult(), 0.5, "swamp radius 2 m, slow -50%")
		_expect(inside.hp == TEST_HP, "swamp deals no damage")
	w.root.free()


func _test_kill_combos() -> void:
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN, Enums.Rarity.EPIC)
	_engrave(&"essence_stone_low", 0)
	_engrave(&"essence_light_low", 1)
	w.magic.roll = func() -> float: return ALWAYS
	var target := await _monster(w, Vector3(0, 0, -3))
	var near := await _monster(w, Vector3(1.5, 0, -3))
	var sources: Array = []
	near.damaged.connect(func(_a: float, info: Dictionary) -> void: sources.append(info.get("magic", &"")))
	target.hp = 1.0
	_shot_damage(w, target)
	_expect(target.is_dead(), "killed")
	_expect(&"shard_burst" in sources, "stone + light kill: shard burst hits the neighbour")
	w.root.free()

	w = await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN, Enums.Rarity.EPIC)
	_engrave(&"essence_green_low", 0)
	_engrave(&"essence_light_low", 1)
	w.magic.roll = func() -> float: return ALWAYS
	target = await _monster(w, Vector3(0, 0, -3))
	target.hp = 1.0
	w.player.health = 50.0
	_shot_damage(w, target)
	# +10 photosynthesis, +2% of the 1 hp it took (lifesteal).
	_expect_near(w.player.health, 60.02, "green + light kill: photosynthesis +10", 0.001)
	w.root.free()


func _test_mana_in_world() -> void:
	var w := await _world()
	_equip(&"dagger", Enums.EquipSlot.MAIN)
	_equip(&"pistol", Enums.EquipSlot.SUB)
	w.magic.roll = func() -> float: return NEVER
	var vine := await _monster(w, Vector3(0, 0, -1.2))
	_swing(w)
	_expect_near(w.magic.mana(), 0.0, "normal weapon: no mana")
	_engrave(&"essence_water_low")
	_swing(w)
	_expect_near(w.magic.mana(), 5.0, "melee hit +5")
	_expect_near(MagicWeapon.hud_mana(w.player), 0.05, "HUD mana 0..1")
	vine.hp = 1.0
	_swing(w)
	_expect_near(w.magic.mana(), 20.0, "melee kill +5 +10")
	var dagger := w.holder.current_uid()
	w.holder.switch_to(Enums.EquipSlot.SUB)
	_engrave(&"essence_water_low", 0, "sub")
	var other := await _monster(w, Vector3(0, 0, -3))
	_shot_damage(w, other)
	_magic_step(w, DT)
	_expect_near(w.magic.mana(), 3.0, "shot hit +3, gauge per weapon")
	_expect_near(w.magic.mana(dagger), 20.0, "dagger keeps its own gauge")
	w.magic.reset()
	_expect_near(w.magic.mana(dagger), 0.0, "sortie over: back to 0")
	w.root.free()


func _test_release_gun() -> void:
	var w := await _world()
	_equip(&"pistol", Enums.EquipSlot.MAIN)
	_engrave(&"essence_water_low")
	w.magic.roll = func() -> float: return NEVER
	w.magic.set_mana(99.0)
	_expect(not w.magic.release(), "99 mana: no release")
	w.magic.set_mana(100.0)
	_noises.clear()
	_magic_step(w, DT, true)
	_expect(w.magic.charged_shots() == 5, "gun release: 5 element shots")
	_expect(15.0 in _noises, "release noise 15 m")
	_expect_near(w.magic.mana(), 0.0, "gauge used up")
	var vine := await _monster(w, Vector3(0, 0, -3))
	_shot_damage(w, vine)
	_expect(vine.status.has(&"slow") and vine.status.has(&"wet"), "charged shot: water effect 100%")
	_expect(w.magic.charged_shots() == 4, "one charged shot used")
	for i in 4:
		_shot_damage(w, vine)
	_expect(w.magic.charged_shots() == 0, "5 shots then normal")
	w.root.free()


func _test_release_blunt() -> void:
	var w := await _world()
	_equip(&"hammer", Enums.EquipSlot.MAIN)
	w.magic.set_mana(100.0)
	_expect(not w.magic.release(), "normal weapon: no release")
	_engrave(&"essence_water_low")
	w.magic.roll = func() -> float: return NEVER
	w.magic.set_mana(100.0)
	var a := await _monster(w, Vector3(2, 0, 0))
	var b := await _monster(w, Vector3(0, 0, 4.5))
	var out := await _monster(w, Vector3(6, 0, 0))
	_expect(w.magic.release(), "blunt release")
	_expect(a.hp < TEST_HP and b.hp < TEST_HP, "everything within 5 m hit")
	_expect(a.status.time_left(&"stagger") >= 2.0 - EPS and b.status.has(&"stagger"), "stagger 2 s")
	_expect(out.hp == TEST_HP, "6 m away: not hit")
	_magic_step(w, DT)
	_expect_near(w.magic.mana(), 0.0, "release hits give no mana")
	w.root.free()


func _test_release_blade() -> void:
	var w := await _world()
	_equip(&"dagger", Enums.EquipSlot.MAIN)
	_engrave(&"essence_water_low")
	w.magic.roll = func() -> float: return NEVER
	var vine := await _monster(w, Vector3(2, 0, 0))
	var out := await _monster(w, Vector3(0, 0, 4))
	var hits := [0]
	vine.damaged.connect(func(_a: float, info: Dictionary) -> void:
		if info.get("release", false):
			hits[0] += 1)
	w.magic.set_mana(100.0)
	_expect(w.magic.release(), "blade release")
	_magic_step(w, 1.0)
	_expect(hits[0] == 4, "blade storm: 4 hits within 3 m (got %d)" % hits[0])
	_expect(out.hp == TEST_HP, "4 m away: not hit")
	_magic_step(w, 1.0)
	_expect(hits[0] == 4, "storm over")
	w.root.free()


# --- Helpers ----------------------------------------------------------------

func _effects(ids: Array) -> Array:
	return EssenceRules.weapon_effects(ids)["effects"]


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
	w.player.skills.set_physics_process(false)
	w.magic = w.player.magic
	w.magic.set_physics_process(false)
	w.magic.reset()
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


## Fires once (after the attack interval). Returns the damage `monster` took.
func _shot_damage(w: World, monster: Monster) -> float:
	_advance(w, float(w.holder.current_stats().get("attack_interval", 0.5)) + DT)
	if w.holder.ammo_in_magazine() <= 1:
		w.holder._magazines.clear()
	var before := monster.hp
	w.holder.fire()
	return before - maxf(monster.hp, 0.0)


## Swings once (after the interval), then one magic step so the mana gain lands.
func _swing(w: World) -> void:
	_advance(w, float(w.holder.current_stats().get("attack_interval", 0.5)) + 1.0)
	w.player.stamina = w.player.stats.max_stamina
	_expect(w.holder.swing(), "swing")
	_magic_step(w, DT)


## Steps the weapon holder (game order) for `sec` seconds, no input.
func _advance(w: World, sec: float) -> void:
	var t := 0.0
	while t < sec:
		w.holder.step(DT, {})
		t += DT


func _magic_step(w: World, sec: float, release_first: bool = false) -> void:
	w.magic.step(DT, {"release": release_first})
	var t := DT
	while t < sec - EPS:
		w.magic.step(DT, {})
		t += DT


func _step_zone(zone: MagicZone, sec: float) -> void:
	var t := 0.0
	while t < sec - EPS and not zone.is_queued_for_deletion():
		zone.step(DT)
		t += DT


func _zone(w: World) -> MagicZone:
	for child in w.root.get_children():
		if child is MagicZone:
			return child
	return null


## Attacker-side damage of the active weapon (no crit).
func _base(w: World) -> float:
	var stats := w.holder.current_stats()
	return DamageFormula.attacker_damage(float(stats["damage"]),
			ClassMastery.level(int(stats["combat_class"])), w.holder.tuning.mastery_per_level, 1.0)


func _engrave(essence: StringName, slot: int = 0, equip: String = "main") -> void:
	var out := DebugConsole.execute("engrave %s %d %s" % [essence, slot, equip])
	_expect(out.contains("element"), "engrave %s: %s" % [essence, out])


func _equip(def_id: StringName, slot: Enums.EquipSlot, rarity: Enums.Rarity = Enums.Rarity.COMMON) -> StringName:
	var uid := Armory.create_item(def_id, rarity)
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
		push_error("test_magic: " + label)


func _expect_near(a: float, b: float, label: String, eps: float = EPS) -> void:
	_expect(absf(a - b) <= eps, "%s (got %.3f, want %.3f)" % [label, a, b])
