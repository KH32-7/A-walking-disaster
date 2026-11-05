extends Node
## B-27: hit-stop rules (never a single bullet, kills and crit kills stop longer), shake falloff,
## time scale comes back after a stop, a flinch springs the monster's Body back to rest.


func run() -> bool:
	var ok := true
	ok = _expect(CombatFeel.stop_for(false, false, false, false) == 0.0, "a bullet hit does not stop") and ok
	ok = _expect(CombatFeel.stop_for(false, true, false, false) == 0.0, "a crit bullet that does not kill does not stop") and ok
	ok = _expect(CombatFeel.stop_for(false, false, true, false) == CombatFeel.STOP_MELEE_HIT, "melee hit stops") and ok
	ok = _expect(CombatFeel.stop_for(false, false, true, true) == CombatFeel.STOP_MELEE_FINISHER, "combo finisher stops longer") and ok
	ok = _expect(CombatFeel.stop_for(true, false, false, false) == CombatFeel.STOP_KILL, "kill stops") and ok
	ok = _expect(CombatFeel.stop_for(true, true, false, false) > CombatFeel.STOP_KILL, "crit kill stops longest") and ok
	ok = _expect(is_equal_approx(CombatFeel.falloff(0.0), 1.0), "shake full at the centre") and ok
	ok = _expect(CombatFeel.falloff(CombatFeel.SHAKE_RANGE + 1.0) == 0.0, "no shake out of range") and ok

	CombatFeel.hit_stop(self, 0.05)
	ok = _expect(is_equal_approx(Engine.time_scale, CombatFeel.STOP_TIME_SCALE), "hit-stop slows time") and ok
	await get_tree().create_timer(0.15, true, false, true).timeout
	ok = _expect(is_equal_approx(Engine.time_scale, 1.0), "time scale back to 1 after the stop") and ok

	var monster := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, 0.5, 0)
	monster.add_child(body)
	add_child(monster)
	var source := Node3D.new()
	add_child(source)
	source.global_position = Vector3(-3, 0, 0)
	CombatFeel.flinch(monster, {"source": source, "crit": true})
	ok = _expect(body.position.x > 0.05, "flinch pushes the body away from the attacker") and ok
	await get_tree().create_timer(CombatFeel.FLINCH_SEC + 0.1).timeout
	ok = _expect(body.position.is_equal_approx(Vector3(0, 0.5, 0)) and body.scale.is_equal_approx(Vector3.ONE),
		"body back at rest after the flinch") and ok
	monster.queue_free()
	source.queue_free()
	return ok


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		push_error("test_combat_feel: " + what)
	return cond
