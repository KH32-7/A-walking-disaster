extends Node
## D-18: every Fx id loads and spawns, Lane B's ids and params work, effects free themselves,
## combo zones size from ComboDef, hit feedback (damage number, flash, hurt) from B-style signals,
## reduce_flash dims flashes, unknown ids are ignored.

const B_IDS := [&"muzzle_flash", &"bullet_tracer", &"bullet_impact", &"hit_spark", &"perfect_block", &"neon_moth_blast"]
const D18_IDS := [&"element_green", &"element_stone", &"element_water", &"element_light",
	&"combo_thorn_bush", &"combo_swamp", &"combo_photosynthesis", &"combo_mud", &"combo_shard_burst",
	&"combo_shock_puddle", &"release_gun", &"release_blade", &"release_blunt", &"explosion", &"noise_lure",
	&"boss_telegraph", &"damage_number", &"melee_swing"]

class FakeMonster:
	extends MeshInstance3D
	signal damaged(amount: float, info: Dictionary)
	func _init() -> void:
		mesh = BoxMesh.new()
		add_to_group(&"field_monsters")

class FakePlayer:
	extends MeshInstance3D
	signal health_changed(current: float, maximum: float)
	var health := 100.0
	func _init() -> void:
		mesh = BoxMesh.new()
		add_to_group(&"player")


func run() -> bool:
	var ok := true
	Fx.manual_step = true
	Fx.clear()
	for id in B_IDS + D18_IDS:
		ok = _expect(Fx.get_def(id) != null, "effect %s registered" % id) and ok
	# Lane B's calls, params exactly as in field/ (weapon_holder, companion, self_destruct_behavior).
	var at := Vector3(1, 1, 1)
	ok = _expect(Fx.spawn_node(&"muzzle_flash", at, {"direction": Vector3.FORWARD}) != null, "muzzle_flash spawns") and ok
	var tracer := Fx.spawn_node(&"bullet_tracer", at, {"to": at + Vector3(12, 0, 0)})
	ok = _expect(tracer != null and tracer.lifetime < 0.3, "tracer lasts its flight (12 m at 120 m/s) + linger") and ok
	ok = _expect(Fx.spawn_node(&"bullet_impact", at, {"normal": Vector3.UP}) != null, "bullet_impact spawns") and ok
	var spark := Fx.spawn_node(&"hit_spark", at, {"element": Enums.Element.GREEN, "weak_point": true, "crit": true})
	ok = _expect(spark != null and spark.params.get("mode") == &"body", "hit_spark uses body mode from base_params") and ok
	ok = _expect(Fx.spawn_node(&"perfect_block", at, {}) != null, "perfect_block spawns") and ok
	ok = _expect(Fx.spawn_node(&"neon_moth_blast", at, {}) != null, "neon_moth_blast spawns") and ok
	for id in D18_IDS:
		ok = _expect(Fx.spawn_node(id, at, {"amount": 5.0}) != null, "%s spawns" % id) and ok
	# Data-driven sizes: combo zones read ComboDef effect_params, caller wins.
	var swamp := Fx.spawn_node(&"combo_swamp", at)
	ok = _expect(is_equal_approx(float(swamp.params.get("zone_sec", 0.0)), 3.0), "swamp zone_sec from ComboDef") and ok
	ok = _expect(swamp.lifetime > 3.0, "swamp lasts its zone time") and ok
	var thorn := Fx.spawn_node(&"combo_thorn_bush", at, {"zone_sec": 1.0})
	ok = _expect(thorn.lifetime < 2.0, "caller params override ComboDef") and ok
	var lure := Fx.spawn_node(&"noise_lure", at, {"silent": true})
	ok = _expect(is_equal_approx(float(lure.params.get("fuse_sec", 0.0)), 4.0), "lure fuse from data (design 4 s)") and ok
	# Every effect frees itself.
	for i in 400:
		Fx.advance(1.0 / 60.0)
	await get_tree().process_frame
	ok = _expect(Fx.live_effects().is_empty(), "all effects freed after their lifetime (%d left)" % Fx.live_effects().size()) and ok
	# Cap per id.
	for i in 40:
		Fx.spawn(&"hit_spark", at, {"silent": true})
	await get_tree().process_frame
	ok = _expect(Fx.live_effects().size() <= Fx.get_def(&"hit_spark").max_alive, "hit_spark capped at max_alive") and ok
	Fx.clear()
	await get_tree().process_frame
	ok = _expect(Fx.spawn_node(&"no_such_effect", at) == null, "unknown id ignored") and ok
	ok = await _hit_feedback() and ok
	ok = _reduced_flash() and ok
	Fx.clear()
	Fx.manual_step = false
	return ok


func _hit_feedback() -> bool:
	var ok := true
	var m := FakeMonster.new()
	var p := FakePlayer.new()
	add_child(m)
	add_child(p)
	Fx.feedback.scan()
	m.damaged.emit(23.4, {"crit": true, "position": Vector3(0, 1, 0)})
	var nums := _numbers()
	ok = _expect(nums.size() == 1, "monster damaged -> one damage number") and ok
	if nums.size() == 1:
		var label := nums[0].get_child(0) as Label3D
		ok = _expect(label.text == "23!", "crit number text '23!' (got '%s')" % label.text) and ok
		ok = _expect(label.modulate.is_equal_approx(UiTokens.ACCENT), "crit number in ACCENT") and ok
		ok = _expect(is_equal_approx(nums[0].lifetime, 0.7), "number lives 0.7 s (UI_RULES §6)") and ok
	ok = _expect(HitFlash.is_flashing(m), "monster flashes on hit") and ok
	m.damaged.emit(2.0, {"status_tick": true})
	ok = _expect(_numbers().size() == 2, "status tick shows a number too") and ok
	p.health = 88.0
	p.health_changed.emit(88.0, 100.0)
	var last := _numbers().back() as FxEffect
	ok = _expect((last.get_child(0) as Label3D).text == "-12", "player hurt shows -12") and ok
	ok = _expect(HitFlash.is_flashing(p), "player flashes when hurt") and ok
	for i in 30:
		Fx.advance(1.0 / 60.0)
	ok = _expect(not HitFlash.is_flashing(m) and m.material_overlay == null, "flash ends and overlay is removed") and ok
	m.queue_free()
	p.queue_free()
	Fx.clear()
	await get_tree().process_frame
	return ok


func _reduced_flash() -> bool:
	var ok := true
	Fx.reduced_flash_override = 1
	var fx := Fx.spawn_node(&"hit_spark", Vector3.ZERO, {"silent": true})
	ok = _expect(fx.flash_k < 1.0 and fx.reduced_flash, "reduce_flash dims effect flashes") and ok
	Fx.reduced_flash_override = 0
	fx = Fx.spawn_node(&"hit_spark", Vector3.ZERO, {"silent": true})
	ok = _expect(is_equal_approx(fx.flash_k, 1.0), "full flash when off") and ok
	Fx.reduced_flash_override = -1
	return ok


func _numbers() -> Array[FxEffect]:
	var out: Array[FxEffect] = []
	for fx in Fx.live_effects():
		if fx.params.get("effect_id") == &"damage_number":
			out.append(fx)
	return out


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
