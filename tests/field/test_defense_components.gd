extends Node
## B-23: field combat parts on a base defense map. With the base switches set (Player.field_rules,
## FieldCompanion.field_rules, Monster.raid_goal) nothing field-only happens: going down keeps the
## bag and gear, sends no EventBus.player_downed, strands nobody and leaves FieldState as it was.
## Raiders do not leash, march to the goal, hit raid structures in the way (gates first for the
## debris ram), go for base residents (layer 3) and leave a downed player alone.

const PLAYER_SCENE := preload("res://field/player/player.tscn")
const COMPANION_SCENE := preload("res://field/companion/field_companion.tscn")
const BASE_SCENE := preload("res://field/monsters/monster_base.tscn")
const CRUSHER := preload("res://data/monsters/root_crusher.tres")
const RAM := preload("res://data/monsters/debris_ram.tres")
const BLOB := preload("res://data/monsters/swamp_blob.tres")
const TUNING := preload("res://data/classes/companion_tuning.tres")
const DT := 0.1
const GUARD_ID := &"b23_test_guard"

var _ok := true
var _root: Node3D
var _downed_signals := 0
var _stranded: Array = []


## Raid structure stand-in (Lane C's wall / door): world layer, take_damage, records hits.
class FakeStructure extends StaticBody3D:
	var hits: Array[Dictionary] = []

	func take_damage(amount: float, info: Dictionary) -> void:
		hits.append({"amount": amount, "info": info})


## Base resident stand-in: layer 3 (ally) body with take_damage.
class FakeResident extends StaticBody3D:
	var hits: Array[Dictionary] = []

	func take_damage(amount: float, info: Dictionary) -> void:
		hits.append({"amount": amount, "info": info})


## Something in the player group that is down.
class FakePlayer extends Node3D:
	var is_downed := true


func run() -> bool:
	_ok = true
	var field_before := FieldState.save_data()
	var field_state := _field_snapshot()
	var bag_before := Bag.save_data()
	var autosave_before := SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	EventBus.player_downed.connect(_on_player_downed)
	EventBus.companion_stranded.connect(_on_stranded)
	_root = Node3D.new()
	_root.name = "TestDefense"
	add_child(_root)

	await _test_player_down_keeps_everything()
	await _test_hud_has_no_sortie_clock()
	_test_guard_is_never_stranded()
	_test_raider_does_not_leash()
	_test_raider_hits_structure()
	_test_ram_goes_for_gates()
	_test_targets_residents_not_downed_player()
	_test_split_children_keep_raiding()

	_check(_field_snapshot() == field_state, "FieldState is unchanged after the defense tests")
	_check(_stranded.is_empty(), "no companion_stranded during the defense tests")
	_root.free()
	EventBus.player_downed.disconnect(_on_player_downed)
	EventBus.companion_stranded.disconnect(_on_stranded)
	Bag.load_data(bag_before)
	FieldState.load_data(field_before)
	SaveSystem.autosave_enabled = autosave_before
	return _ok


func _test_player_down_keeps_everything() -> void:
	Bag.add_resource(&"wood", 3)
	var wood := Bag.count(&"wood")
	var equipped := Armory.list_equipped(Armory.PLAYER_ID)
	var field := _field_snapshot()
	var down_result := FieldState.down_result()
	var p := _player()
	p.field_rules = false
	var local := [0]
	p.downed.connect(func() -> void: local[0] += 1)
	_downed_signals = 0
	p.take_damage(p.stats.max_health * 10.0)
	await get_tree().process_frame
	_check(p.is_downed, "base player goes down")
	_check(local[0] == 1, "Player.downed fires once for Lane C")
	_check(_downed_signals == 0, "no EventBus.player_downed on the base map")
	_check(Bag.count(&"wood") == wood, "bag kept")
	_check(Armory.list_equipped(Armory.PLAYER_ID) == equipped, "equipped gear kept, nothing lost")
	_check(_field_snapshot() == field, "lost gear, downs, companions unchanged")
	_check(FieldState.down_result() == down_result, "no down result")
	p.free()


func _test_hud_has_no_sortie_clock() -> void:
	var night_before := FieldState.night
	var night: NightTuning = night_before.duplicate()
	night.enabled = true
	FieldState.night = night
	var p := _player()
	await get_tree().process_frame
	_check(p.hud_state().has("dusk_left_sec"), "field player HUD has the dusk timer")
	p.field_rules = false
	_check(not p.hud_state().has("dusk_left_sec"), "base player HUD has no dusk timer")
	FieldState.night = night_before
	p.free()


func _test_guard_is_never_stranded() -> void:
	var post := Marker3D.new()
	_root.add_child(post)
	post.global_position = Vector3(5.0, 0.0, 0.0)
	var c: FieldCompanion = COMPANION_SCENE.instantiate()
	c.setup(GUARD_ID, {"name": "경비"})
	c.field_rules = false
	c.guard_post = post
	_root.add_child(c)
	c.set_physics_process(false)
	_check(c.anchor() == post, "guard keeps to its post")
	var companions := FieldState.companions.duplicate()
	c.take_damage(c.max_health * 10.0)
	_check(c.state == FieldCompanion.State.DOWNED, "guard goes down")
	c.tick(TUNING.downed_sec + 5.0)
	c.tick(TUNING.downed_sec + 5.0)
	_check(c.state == FieldCompanion.State.DOWNED, "downed guard is not stranded when the wait runs out")
	_check(_stranded.is_empty() and FieldState.companions == companions, "no companion_stranded")
	c.free()
	post.free()


func _test_raider_does_not_leash() -> void:
	var m := _raider(CRUSHER, Vector3(50.0, 0.0, 0.0), Vector3(50.0, 0.0, -20.0))
	m.home = Vector3.ZERO
	m.tick(DT)
	_check(m.is_raider(), "raid_goal makes a raider")
	_check(m.state == Enums.AIState.WANDER, "raider far from home does not return")
	_check(m.velocity.z < -0.1 and absf(m.velocity.x) < 0.01, "raider marches to the goal")
	m.free()
	var far := MonsterRules.CHASE_RETURN_DISTANCE + 10.0
	var field := _spawn(CRUSHER, Vector3(far, 0.0, 0.0))
	field.home = Vector3.ZERO
	field.chase(_fake_player(Vector3(far, 0.0, -3.0), false))
	field.tick(DT)
	_check(field.state == Enums.AIState.RETURN, "field monster still leashes home")
	_clear()


func _test_raider_hits_structure() -> void:
	var wall := _structure(Vector3(0.0, 1.5, -1.2), false)
	var m := _raider(CRUSHER, Vector3.ZERO, Vector3(0.0, 0.0, -20.0))
	for i in 20:
		m.tick(DT)
	_check(not wall.hits.is_empty(), "raider hits the structure in its way")
	_check(m.velocity.length() < 0.01, "raider stops at the structure")
	if not wall.hits.is_empty():
		var hit: Dictionary = wall.hits[0]
		_check(is_equal_approx(hit["amount"], CRUSHER.attack), "hit uses the monster attack")
		_check(is_equal_approx(hit["info"]["structure_damage_mult"], 3.0)
				and hit["info"]["monster_id"] == &"root_crusher" and hit["info"]["source"] == m,
				"hit info carries the siege numbers for Lane C")
		# 2 s: wind-up 0.4 s, then every attack_interval (1.5 s) -> 1 or 2 hits.
		_check(wall.hits.size() <= 2, "hits follow attack_interval")
	wall.remove_from_group(RaidMarch.STRUCTURE_GROUP)
	var hits := wall.hits.size()
	m.tick(DT)
	_check(wall.hits.size() == hits, "a structure out of the group is not hit")
	_clear()


func _test_ram_goes_for_gates() -> void:
	var gate := _structure(Vector3(12.0, 1.5, 0.0), true)
	var m := _raider(RAM, Vector3.ZERO, Vector3(0.0, 0.0, -30.0))
	m.tick(DT)
	_check(m.velocity.x > 0.1, "debris ram heads for the gate before the goal")
	gate.remove_from_group(RaidMarch.GATE_GROUP)
	m.tick(DT)
	_check(m.velocity.z < -0.1, "with no gate left it marches to the goal")
	var crusher := _raider(CRUSHER, Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -30.0))
	gate.add_to_group(RaidMarch.GATE_GROUP)
	crusher.tick(DT)
	_check(crusher.velocity.z < -0.1, "other raiders ignore gates")
	_clear()


func _test_targets_residents_not_downed_player() -> void:
	var m := _raider(CRUSHER, Vector3.ZERO, Vector3(0.0, 0.0, -30.0))
	var down := _fake_player(Vector3(0.0, 0.0, -3.0), true)
	_check(m.find_visible_target() == null, "a downed player is not a target")
	var resident := FakeResident.new()
	resident.collision_layer = 1 << (Enums.LAYER_ALLY - 1)
	resident.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	resident.add_child(shape)
	resident.position = Vector3(0.0, 0.0, -1.0)
	_root.add_child(resident)
	_check(m.find_visible_target() == resident, "a base resident on layer 3 is a target")
	for i in 20:
		m.tick(DT)
	_check(not resident.hits.is_empty(), "raider attacks the resident")
	down.is_downed = false
	_check(m.find_visible_target() == down, "the player is first once up")
	down.is_downed = true
	m.chase(down)
	m.tick(DT)
	_check(m.target != down, "raider lets go of a player who went down")
	_clear()


func _test_split_children_keep_raiding() -> void:
	var goal := Vector3(3.0, 0.0, -9.0)
	var m := _raider(BLOB, Vector3.ZERO, goal)
	var split := m.get_behavior(&"split")
	_check(split != null, "swamp blob splits")
	if split != null:
		var children: Array[Monster] = split.call(&"make_children")
		_check(not children.is_empty() and children.all(func(c: Monster) -> bool: return c.raid_goal == goal),
				"split children keep the raid goal")
		for c in children:
			c.free()
	_clear()


# --- Helpers ----------------------------------------------------------------

## FieldState.save_data() without sortie_time: a clock another test left running keeps ticking
## during awaits. Whether the clock runs (clock_running) is still compared.
func _field_snapshot() -> Dictionary:
	var data := FieldState.save_data()
	data.erase("sortie_time")
	return data


func _player() -> Player:
	var p: Player = PLAYER_SCENE.instantiate()
	_root.add_child(p)
	p.set_physics_process(false)
	p.get_node(^"Weapons").set_physics_process(false)
	return p


func _spawn(def: MonsterDef, pos: Vector3) -> Monster:
	var m := BASE_SCENE.instantiate() as Monster
	m.def = def
	m.position = pos
	_root.add_child(m)
	m.set_physics_process(false)
	return m


func _raider(def: MonsterDef, pos: Vector3, goal: Vector3) -> Monster:
	var m := BASE_SCENE.instantiate() as Monster
	m.def = def
	m.position = pos
	m.raid_goal = goal
	_root.add_child(m)
	m.set_physics_process(false)
	return m


func _structure(pos: Vector3, gate: bool) -> FakeStructure:
	var body := FakeStructure.new()
	body.collision_layer = 1 << (Enums.LAYER_WORLD - 1)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 3.0, 0.4) if gate else Vector3(4.0, 3.0, 0.4)
	shape.shape = box
	body.add_child(shape)
	body.add_to_group(RaidMarch.STRUCTURE_GROUP)
	if gate:
		body.add_to_group(RaidMarch.GATE_GROUP)
	# Position before entering the tree: a body moved after add_child reaches ray queries only
	# on the next physics step.
	body.position = pos
	_root.add_child(body)
	return body


func _fake_player(pos: Vector3, downed: bool) -> FakePlayer:
	var p := FakePlayer.new()
	p.is_downed = downed
	p.add_to_group(Monster.PLAYER_GROUP)
	_root.add_child(p)
	p.global_position = pos
	return p


func _clear() -> void:
	for child in _root.get_children():
		child.free()


func _on_player_downed() -> void:
	_downed_signals += 1


func _on_stranded(resident_id: StringName, region_id: StringName) -> void:
	_stranded.append([resident_id, region_id])


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("test_defense_components: " + what)
