extends RefCounted
## B-08: loot tables roll inside their ranges, containers open on time, identify one
## slot per 0.5 s, cancel on movement, make noise when forced, honor instant_loot,
## and the spawner places containers on a random share of the LootSpots.

const BAG_STUB := preload("res://field/_sandbox/stubs/bag_stub.gd")
const CONTAINER_SCENE := preload("res://field/loot/loot_container.tscn")
const LOOT_SPOT_SCENE := preload("res://field/markers/loot_spot.tscn")
const STEP := 0.01

var _root: Node
var _ok := true


func run() -> bool:
	_root = (Engine.get_main_loop() as SceneTree).root
	var instant_before: Variant = Settings.get_value(&"instant_loot")
	Settings.set_value(&"instant_loot", false)
	_test_table_roll()
	_test_data_files()
	_test_open_and_reveal()
	_test_move_cancels()
	_test_forced_lock_noise()
	_test_key_opens_quietly()
	_test_instant_loot()
	_test_take()
	_test_spawner()
	Settings.set_value(&"instant_loot", instant_before)
	return _ok


func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("test_loot: " + msg)
		_ok = false


func _test_table_roll() -> void:
	var table := LootTable.new()
	table.roll_min = 2
	table.roll_max = 4
	table.entries = [_entry(&"scrap", 1.0, 1, 3), _entry(&"cloth", 1.0, 2, 2), _entry(&"never", 0.0, 1, 1)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var seen := {}
	for i in 500:
		var drops := table.roll(rng)
		_check(drops.size() >= 2 and drops.size() <= 4, "roll count %d outside 2..4" % drops.size())
		for d in drops:
			seen[d.item_id] = true
			if d.item_id == &"scrap":
				_check(d.count >= 1 and d.count <= 3, "scrap count %d outside 1..3" % d.count)
			elif d.item_id == &"cloth":
				_check(d.count == 2, "cloth count %d is not 2" % d.count)
	_check(seen.has(&"scrap") and seen.has(&"cloth"), "weighted entries never rolled")
	_check(not seen.has(&"never"), "zero-weight entry rolled")
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 7
	b.seed = 7
	_check(table.roll(a) == table.roll(b), "same seed gave different rolls")


func _test_data_files() -> void:
	for type in LootSpot.ContainerType.values():
		var def := LootData.container_def(type)
		_check(def != null, "no container def for type %d" % type)
		var table := LootData.find_table(&"flooded_mall", type)
		_check(table != null, "no flooded_mall table for type %d" % type)
		if table == null:
			continue
		_check(table.roll_min <= table.roll_max, "%s roll_min > roll_max" % table.id)
		for e in table.entries:
			_check(e.item_id != &"" and e.weight > 0.0 and e.min_count <= e.max_count,
				"%s has a bad entry %s" % [table.id, e.item_id])
	var crate := LootData.container_def(LootSpot.ContainerType.SUPPLY_CRATE)
	if crate:
		_check(crate.locked and is_equal_approx(crate.noise_on_force, 6.0), "supply crate is not locked with 6 m noise")
		_check(is_equal_approx(crate.open_sec, 5.0), "supply crate open time is not 5 s")


func _test_open_and_reveal() -> void:
	var s := _setup(_def(1.5), 3)
	var c: LootContainer = s.container
	var events: Array = s.events
	_check(c.begin_open(s.looter), "begin_open refused")
	_step(c, 1.4)
	_check(c.state == LootContainer.State.OPENING and not events.has("opened"), "opened before 1.5 s")
	_step(c, 0.15)
	_check(c.state == LootContainer.State.OPEN and events.has("opened"), "not open after 1.5 s")
	for slot in c.get_slots():
		_check(not slot.identified and slot.item_id == &"", "slot visible before identifying")
	_step(c, 0.4)
	_check(_count(events, "revealed") == 0, "slot identified before 0.5 s")
	_step(c, 0.15)
	_check(_count(events, "revealed") == 1, "first slot not identified at 0.5 s")
	_step(c, 0.5)
	_check(_count(events, "revealed") == 2, "second slot not identified at 1.0 s")
	_step(c, 0.5)
	_check(_count(events, "revealed") == 3 and events.has("finished"), "reveal did not finish at 1.5 s")
	_teardown(s)


func _test_move_cancels() -> void:
	var s := _setup(_def(1.5), 3)
	var c: LootContainer = s.container
	var looter: Node3D = s.looter
	c.begin_open(looter)
	_step(c, 1.0)
	looter.position.x += 1.0
	_step(c, STEP)
	_check(c.state == LootContainer.State.CLOSED and s.events.has("ended"), "moving did not cancel opening")
	# Reopening starts over.
	c.begin_open(looter)
	_step(c, 1.0)
	_check(c.state == LootContainer.State.OPENING, "reopen kept old progress")
	_step(c, 0.6)
	_check(c.state == LootContainer.State.OPEN, "reopen did not finish")
	# Moving during identification stops it; identified slots stay.
	_step(c, 0.55)
	looter.position.x += 1.0
	_step(c, 2.0)
	_check(_count(s.events, "revealed") == 1, "identification kept going after moving")
	c.begin_open(looter)
	_step(c, 1.1)
	_check(_count(s.events, "revealed") == 3, "identification did not resume")
	_teardown(s)


func _test_forced_lock_noise() -> void:
	var noises: Array = []
	var listener := func(pos: Vector3, radius: float, source: Node) -> void:
		noises.append([pos, radius, source])
	EventBus.noise_emitted.connect(listener)
	var s := _setup(_def(5.0, true, 6.0), 2)
	var c: LootContainer = s.container
	c.begin_open(s.looter)
	_check(noises.size() == 1, "forcing a lock emitted %d noises" % noises.size())
	if noises.size() == 1:
		_check(is_equal_approx(noises[0][1], 6.0), "lock noise radius is not 6 m")
		_check(noises[0][0].is_equal_approx(c.global_position), "lock noise not at the container")
		_check(noises[0][2] == s.looter, "lock noise source is not the interactor")
	_step(c, 5.05)
	_check(c.state == LootContainer.State.OPEN and not c.is_locked(), "forced crate did not open")
	EventBus.noise_emitted.disconnect(listener)
	_teardown(s)


func _test_key_opens_quietly() -> void:
	var noises: Array = []
	var listener := func(_p: Vector3, _r: float, _s: Node) -> void:
		noises.append(true)
	EventBus.noise_emitted.connect(listener)
	var s := _setup(_def(5.0, true, 6.0), 2)
	var c: LootContainer = s.container
	s.bag.try_add(&"key", 1)
	c.begin_open(s.looter)
	_check(noises.is_empty(), "key open made noise")
	_step(c, 1.0)
	s.looter.position.x += 1.0
	_step(c, STEP)
	_check(s.bag.count_of(&"key") == 1, "canceled open used up the key")
	s.looter.position.x -= 1.0
	c.begin_open(s.looter)
	_step(c, 5.05)
	_check(c.state == LootContainer.State.OPEN and s.bag.count_of(&"key") == 0, "key not used on open")
	EventBus.noise_emitted.disconnect(listener)
	_teardown(s)


func _test_instant_loot() -> void:
	Settings.set_value(&"instant_loot", true)
	var s := _setup(_def(1.5), 3)
	var c: LootContainer = s.container
	c.begin_open(s.looter)
	_step(c, 1.55)
	_check(_count(s.events, "revealed") == 3 and s.events.has("finished"), "instant_loot did not identify at once")
	Settings.set_value(&"instant_loot", false)
	_teardown(s)


func _test_take() -> void:
	var s := _setup(_def(0.5), 2)
	var c: LootContainer = s.container
	c.begin_open(s.looter)
	_step(c, 0.55)
	_check(c.take(0) == 0, "took an unidentified slot")
	_step(c, 1.0)
	var slot: Dictionary = c.get_slots()[0]
	_check(c.take(0) == slot.count and s.bag.count_of(slot.item_id) == slot.count, "take did not fill the bag")
	_check(c.take(0) == 0, "took the same slot twice")
	_teardown(s)


func _test_spawner() -> void:
	var holder := Node3D.new()
	_root.add_child(holder)
	for i in 10:
		var spot: LootSpot = LOOT_SPOT_SCENE.instantiate()
		spot.container_type = LootSpot.ContainerType.values()[i % LootSpot.ContainerType.size()]
		spot.position = Vector3(i * 2.0, 0.0, 0.0)
		holder.add_child(spot)
	var spawner := LootSpawner.new()
	spawner.spawn_on_ready = false
	spawner.spawn_ratio = 0.5
	holder.add_child(spawner)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var first := spawner.spawn(rng).map(func(c: LootContainer) -> Vector3: return c.global_position)
	_check(first.size() == 5, "spawned %d of 10 spots at ratio 0.5" % first.size())
	for c in spawner.spawned:
		_check(c.collision_layer == 1 << (Enums.LAYER_INTERACTABLE - 1), "container not on interactable layer only")
		_check(c.loot_table != null and c.def != null, "container missing def or table")
		_check(not c.get_slots().is_empty() or c.loot_table.roll_min == 0, "container rolled no slots")
		_check(c.global_position.z == 0.0 and fmod(c.global_position.x, 2.0) == 0.0, "container not on a spot")
	rng.seed = 42
	var again := spawner.spawn(rng).map(func(c: LootContainer) -> Vector3: return c.global_position)
	_check(first == again, "same seed placed containers differently")
	holder.free()


# --- helpers ---

func _def(open_sec: float, locked := false, noise := 0.0) -> LootContainerDef:
	var d := LootContainerDef.new()
	d.open_sec = open_sec
	d.locked = locked
	d.noise_on_force = noise
	d.key_item_id = &"key" if locked else &""
	return d


func _entry(item: StringName, weight: float, lo: int, hi: int) -> LootEntry:
	var e := LootEntry.new()
	e.item_id = item
	e.weight = weight
	e.min_count = lo
	e.max_count = hi
	return e


## Container with exactly `slots` slots, a looter next to it and a fresh bag stub.
func _setup(def: LootContainerDef, slots: int) -> Dictionary:
	var table := LootTable.new()
	table.roll_min = slots
	table.roll_max = slots
	table.entries = [_entry(&"scrap", 1.0, 1, 3)]
	var c: LootContainer = CONTAINER_SCENE.instantiate()
	c.def = def
	c.loot_table = table
	var bag: Node = BAG_STUB.new()
	c.bag = bag
	var looter := Node3D.new()
	looter.position = Vector3(1.0, 0.0, 0.0)
	_root.add_child(c)
	_root.add_child(looter)
	_root.add_child(bag)
	c.set_physics_process(false)  # the test drives advance() itself
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	c.roll_contents(rng)
	var events: Array = []
	c.opened.connect(func(_n: int) -> void: events.append("opened"))
	c.slot_revealed.connect(func(_i: int, _id: StringName, _n: int) -> void: events.append("revealed"))
	c.reveal_finished.connect(func() -> void: events.append("finished"))
	c.session_ended.connect(func() -> void: events.append("ended"))
	return {"container": c, "looter": looter, "bag": bag, "events": events}


func _teardown(s: Dictionary) -> void:
	for key in ["container", "looter", "bag"]:
		s[key].free()


## Advances in small steps like physics frames would.
func _step(c: LootContainer, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		c.advance(STEP)
		t += STEP


func _count(events: Array, what: String) -> int:
	return events.count(what)
