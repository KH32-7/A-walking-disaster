extends Node3D
## B-08 sandbox check. Runs a scripted looting demo on the five container kinds with a
## fake interactor (no player until B-03), logs every signal on screen and in stdout,
## then prints PASS or FAIL. Quits by itself when run headless.

const BAG_STUB := preload("res://field/_sandbox/stubs/bag_stub.gd")
const SEED := 2026
## Give up on one step after this many seconds.
const STEP_TIMEOUT := 12.0
const Type := LootSpot.ContainerType

@onready var _spawner: LootSpawner = $LootSpawner
@onready var _looter: Node3D = $FakeLooter
@onready var _label: Label = $LogLayer/LogLabel

var _bag: Node
var _lines: PackedStringArray = []
var _failures := 0
var _noise_count := 0


func _ready() -> void:
	_bag = _ensure_bag()
	EventBus.noise_emitted.connect(_on_noise)
	_run_demo.call_deferred()


func _run_demo() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var by_type := {}
	for c in _spawner.spawn(rng):
		by_type[c.def.type] = c
		_watch(c)
	_expect(by_type.size() == Type.size(), "one container per kind spawned")
	var instant_before: Variant = Settings.get_value(&"instant_loot")
	Settings.set_value(&"instant_loot", false)

	_log("1. Drawer: open, identify, take all")
	var drawer: LootContainer = by_type[Type.DRAWER]
	_go_to(drawer)
	drawer.begin_open(_looter)
	_expect(await _wait(func() -> bool: return _all_identified(drawer)), "drawer identified every slot")
	_take_all(drawer)

	_log("2. Toolbox: move during opening")
	var toolbox: LootContainer = by_type[Type.TOOLBOX]
	_go_to(toolbox)
	toolbox.begin_open(_looter)
	await get_tree().create_timer(1.0).timeout
	_looter.global_position += Vector3(1.0, 0.0, 0.0)
	_expect(await _wait(func() -> bool: return not toolbox.is_in_session()), "moving canceled the toolbox")
	_expect(toolbox.state == LootContainer.State.CLOSED, "toolbox closed again")

	_log("3. Supply crate: locked, no key, forced")
	var crate: LootContainer = by_type[Type.SUPPLY_CRATE]
	var noise_before := _noise_count
	_go_to(crate)
	crate.begin_open(_looter)
	_expect(_noise_count == noise_before + 1, "forcing the crate made one noise")
	_expect(await _wait(func() -> bool: return _all_identified(crate)), "crate opened and identified")
	_take_all(crate)

	_log("4. Medicine cabinet: instant_loot on")
	Settings.set_value(&"instant_loot", true)
	var medicine: LootContainer = by_type[Type.MEDICINE]
	_go_to(medicine)
	medicine.begin_open(_looter)
	_expect(await _wait(func() -> bool: return medicine.state == LootContainer.State.OPEN), "medicine opened")
	_expect(_all_identified(medicine), "instant_loot identified every slot at once")
	Settings.set_value(&"instant_loot", false)

	_log("5. Monster nest: open, identify")
	var nest: LootContainer = by_type[Type.MONSTER_NEST]
	_go_to(nest)
	nest.begin_open(_looter)
	_expect(await _wait(func() -> bool: return _all_identified(nest)), "nest identified every slot")

	Settings.set_value(&"instant_loot", instant_before)
	_log("Bag: %s" % [_bag.stacks])
	_log("B08 DEMO %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)


func _ensure_bag() -> Node:
	var existing := get_node_or_null(LootContainer.BAG_PATH)
	if existing:
		return existing
	var stub: Node = BAG_STUB.new()
	stub.name = "Bag"
	get_tree().root.add_child.call_deferred(stub)
	return stub


func _watch(c: LootContainer) -> void:
	var kind: String = Type.keys()[c.def.type]
	c.open_started.connect(func(d: float, forcing: bool) -> void:
		_log("  %s open_started %.1fs%s" % [kind, d, " (forcing)" if forcing else ""]))
	c.opened.connect(func(n: int) -> void: _log("  %s opened, %d unidentified slots" % [kind, n]))
	c.slot_revealed.connect(func(i: int, id: StringName, n: int) -> void:
		_log("  %s slot %d: %s x%d" % [kind, i, id, n]))
	c.reveal_finished.connect(func() -> void: _log("  %s reveal_finished" % kind))
	c.session_ended.connect(func() -> void: _log("  %s session_ended" % kind))
	c.slot_taken.connect(func(i: int, id: StringName, n: int) -> void:
		_log("  %s took slot %d: %s x%d" % [kind, i, id, n]))


func _go_to(c: LootContainer) -> void:
	_looter.global_position = c.global_position + Vector3(0.0, 0.0, 1.0)


func _take_all(c: LootContainer) -> void:
	for i in c.get_slots().size():
		c.take(i)


func _all_identified(c: LootContainer) -> bool:
	if c.state != LootContainer.State.OPEN:
		return false
	for slot in c.get_slots():
		if not slot.identified:
			return false
	return true


func _wait(cond: Callable) -> bool:
	var t := 0.0
	while not cond.call():
		if t > STEP_TIMEOUT:
			return false
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return true


func _expect(cond: bool, what: String) -> void:
	_log("  %s: %s" % ["ok" if cond else "FAILED", what])
	if not cond:
		_failures += 1


func _on_noise(pos: Vector3, radius: float, source: Node) -> void:
	_noise_count += 1
	_log("  noise %.1fm at (%.1f, %.1f) from %s" % [radius, pos.x, pos.z, source.name if source else "none"])


func _log(text: String) -> void:
	print(text)
	_lines.append(text)
	if _lines.size() > 30:
		_lines.remove_at(0)
	_label.text = "\n".join(_lines)
