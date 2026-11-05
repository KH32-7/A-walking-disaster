extends RefCounted
## B-03: speeds, stamina drain and regen, dodge cost/distance/i-frames, downing.
## Drives Player.step() directly with fake input; no camera, so move axes are world axes.

const DT := 1.0 / 60.0
const EPS := 0.01

var _ok := true


func run() -> bool:
	_ok = true
	_test_speeds()
	_test_stamina()
	_test_dodge()
	_test_damage()
	_test_gun_faces_cursor()
	return _ok


## With a gun the player faces the cursor even while not aiming; with a melee weapon it faces
## the move direction.
func _test_gun_faces_cursor() -> void:
	var previous := Armory.get_equipped(Armory.PLAYER_ID, Enums.EquipSlot.MAIN)
	var gun := Armory.create_item(&"pistol", Enums.Rarity.COMMON)
	Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, gun)
	var p := _spawn()
	p.set_aim_point(p.global_position + Vector3(5.0, 0.0, 0.0))
	_steps(p, 0.2, {"move": Vector2.UP})
	_expect(p.facing().dot(Vector3.RIGHT) > 0.99, "gun: faces the cursor while walking away from it")
	var blade := Armory.create_item(&"dagger", Enums.Rarity.COMMON)
	Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, blade)
	_steps(p, 0.2, {"move": Vector2.UP})
	_expect(p.facing().dot(Vector3.FORWARD) > 0.99, "melee: faces the move direction")
	p.free()
	Armory.unequip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN)
	Armory.remove_item(gun)
	Armory.remove_item(blade)
	if previous != &"":
		Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, previous)


func _test_speeds() -> void:
	var p := _spawn()
	_steps(p, 0.5, {"move": Vector2.UP})
	_expect_near(_flat_speed(p), p.stats.walk_speed, "walk speed")
	_expect(p.move_state == Player.MoveState.WALK, "walk state")
	_steps(p, 0.5, {"move": Vector2.UP, "sprint": true})
	_expect_near(_flat_speed(p), p.stats.sprint_speed, "sprint speed")
	_expect(p.move_state == Player.MoveState.SPRINT, "sprint state")
	_steps(p, 0.5, {"move": Vector2.UP, "aim": true, "sprint": true})
	_expect_near(_flat_speed(p), p.stats.aim_move_speed, "aim move speed (aim beats sprint)")
	_expect(p.move_state == Player.MoveState.AIM_WALK, "aim walk state")
	_steps(p, 0.5, {})
	_expect(p.move_state == Player.MoveState.IDLE, "idle state")
	p.free()


func _test_stamina() -> void:
	var p := _spawn()
	_steps(p, 1.0, {"move": Vector2.UP, "sprint": true})
	_expect_near(p.stamina, p.stats.max_stamina - p.stats.sprint_stamina_per_sec, "sprint drains 10/s", 0.5)
	var after_sprint := p.stamina
	_steps(p, p.stats.stamina_regen_delay_sec - 0.1, {})
	_expect_near(p.stamina, after_sprint, "no regen during delay")
	_steps(p, 0.2, {})
	_expect(p.stamina > after_sprint, "regen starts after delay")
	var regen_start := p.stamina
	_steps(p, 0.2, {})
	_expect_near(p.stamina, regen_start + p.stats.stamina_regen * 0.2, "regen 25/s", 0.05)
	p.free()


func _test_dodge() -> void:
	var p := _spawn()
	var start := p.stamina
	p.step(DT, {"move": Vector2.RIGHT, "dodge": true})
	_expect(p.move_state == Player.MoveState.DODGE, "dodge starts")
	_expect_near(start - p.stamina, p.stats.dodge_stamina, "dodge costs 25")
	_expect_near(_flat_speed(p) * p.stats.dodge_duration_sec, p.stats.dodge_distance, "dodge covers 3.5m")
	p.take_damage(10.0)
	_expect_near(p.health, p.stats.max_health, "i-frames block damage")
	_steps(p, p.stats.dodge_duration_sec + DT, {})
	_expect(p.move_state != Player.MoveState.DODGE, "dodge ends")
	p.stamina = p.stats.dodge_stamina - 1.0
	p.step(DT, {"dodge": true})
	_expect(p.move_state != Player.MoveState.DODGE, "no dodge without stamina")
	p.free()


func _test_damage() -> void:
	var p := _spawn()
	var downed := [false]
	p.downed.connect(func() -> void: downed[0] = true)
	p.take_damage(30.0)
	_expect_near(p.health, p.stats.max_health - 30.0, "damage applies")
	p.take_damage(1000.0)
	_expect(p.is_downed and downed[0], "downed at 0 health")
	p.free()


func _spawn() -> Player:
	var p: Player = (load("res://field/player/player.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	_expect(p.is_in_group(Player.GROUP), "player group")
	return p


func _steps(p: Player, seconds: float, input: Dictionary) -> void:
	for i in roundi(seconds / DT):
		p.step(DT, input)


func _flat_speed(p: Player) -> float:
	return Vector2(p.velocity.x, p.velocity.z).length()


func _expect(cond: bool, what: String) -> void:
	if not cond:
		push_error("test_player: %s" % what)
		_ok = false


func _expect_near(value: float, expected: float, what: String, eps: float = EPS) -> void:
	_expect(absf(value - expected) <= eps, "%s (got %.3f, want %.3f)" % [what, value, expected])
