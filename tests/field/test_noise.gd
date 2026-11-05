extends RefCounted
## B-05 noise tests. run() -> bool is called by the A-02 runner.
## Completion: aim walk 0m, sprint 8m, pistol 15m exactly (docs/design/02-field.md "소음").

const ARMOR_STUB := preload("res://field/_sandbox/stubs/armory_armor_stub.gd")

var _ok := true


func run() -> bool:
	_ok = true
	var host := Node3D.new()
	host.name = "NoiseHost"
	var emitter := NoiseEmitter.new()
	host.add_child(emitter)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)

	_test_base_radii(emitter)
	_test_emit_signal(emitter, host)
	_test_rain(emitter)
	_test_armor(emitter)

	host.free()
	return _ok


func _test_base_radii(emitter: NoiseEmitter) -> void:
	_expect_eq(emitter.radius_for(&"aim_walk"), 0.0, "aim_walk")
	_expect_eq(emitter.radius_for(&"sprint"), 8.0, "sprint")
	_expect_eq(emitter.radius_for(&"pistol"), 15.0, "pistol")


func _test_emit_signal(emitter: NoiseEmitter, host: Node3D) -> void:
	var heard: Array = []
	var listener := func(pos: Vector3, radius: float, source: Node) -> void:
		heard.append([pos, radius, source])
	EventBus.noise_emitted.connect(listener)
	host.position = Vector3(3.0, 0.0, -2.0)
	emitter.emit(&"pistol")
	emitter.emit(&"aim_walk")  # 0m: must not emit
	EventBus.noise_emitted.disconnect(listener)
	host.position = Vector3.ZERO

	_expect_eq(heard.size(), 1, "emit count (aim_walk 0m stays silent)")
	if heard.size() == 1:
		_expect_eq(heard[0][0], Vector3(3.0, 0.0, -2.0), "emit position")
		_expect_eq(heard[0][1], 15.0, "emit radius")
		_expect_eq(heard[0][2], host, "emit source is the parent actor")


func _test_rain(emitter: NoiseEmitter) -> void:
	emitter.raining = true
	_expect_eq(emitter.radius_for(&"pistol"), 11.25, "pistol in rain")
	_expect_eq(emitter.radius_for(&"aim_walk"), 0.0, "aim_walk in rain")
	emitter.raining = false


func _test_armor(emitter: NoiseEmitter) -> void:
	var original: Script = Armory.get_script()
	Armory.set_script(ARMOR_STUB)
	emitter.armory_owner_id = Armory.PLAYER_ID
	# Stub armor: helmet +1, scrap armor +3 = 4, capped to +3. Footsteps only.
	_expect_eq(emitter.radius_for(&"walk"), 7.0, "walk with heavy armor")
	_expect_eq(emitter.radius_for(&"sprint"), 11.0, "sprint with heavy armor")
	_expect_eq(emitter.radius_for(&"aim_walk"), 0.0, "aim_walk ignores armor")
	_expect_eq(emitter.radius_for(&"pistol"), 15.0, "pistol ignores armor")
	emitter.armory_owner_id = &""
	Armory.set_script(original)


func _expect_eq(got: Variant, want: Variant, label: String) -> void:
	if got != want:
		_ok = false
		push_error("test_noise: %s: got %s, want %s" % [label, got, want])
