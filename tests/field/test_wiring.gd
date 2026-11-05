extends Node
## M1 wiring: player footsteps reach EventBus as noise, monsters trace that noise back to
## the player, vine binding stops the player, godmode blocks damage, F opens a container.

const DT := 1.0 / 60.0
const PLAYER_SCENE := preload("res://field/player/player.tscn")
const MONSTER_SCENE := preload("res://field/monsters/monster_base.tscn")
const CONTAINER_SCENE := preload("res://field/loot/loot_container.tscn")

var _ok := true
var _noises: Array = []


func run() -> bool:
	_ok = true
	EventBus.noise_emitted.connect(_on_noise)
	_test_footstep_noise()
	_test_monster_traces_player()
	_test_bind_and_godmode()
	await _test_interact_opens_container()
	EventBus.noise_emitted.disconnect(_on_noise)
	return _ok


func _test_footstep_noise() -> void:
	var p := _spawn_player()
	var noise: NoiseEmitter = p.get_node("Noise")
	_noises.clear()
	p.step(DT, {"move": Vector2.UP})
	_expect(_last_noise_radius() == noise.radius_for(&"walk"), "walking emits walk noise")
	_expect(_noises.back()[2] == p, "noise source is the player")
	_noises.clear()
	p.step(DT, {"move": Vector2.UP, "sprint": true})
	_expect(_last_noise_radius() == noise.radius_for(&"sprint"), "sprinting emits sprint noise")
	_noises.clear()
	p.step(DT, {"move": Vector2.UP, "aim": true})
	_expect(_noises.is_empty(), "aim walking is silent")
	p.step(DT, {})
	_noises.clear()
	p.step(DT, {"move": Vector2.RIGHT, "dodge": true})
	_expect(_last_noise_radius() == noise.radius_for(&"roll"), "dodge emits roll noise")
	p.free()


func _test_monster_traces_player() -> void:
	var p := _spawn_player()
	var m := MONSTER_SCENE.instantiate() as Monster
	m.def = load("res://data/monsters/vine_tendril.tres")
	m.position = Vector3(2.0, 0.0, 0.0)
	add_child(m)
	_expect(m.target_from_source(p) == p, "monster traces player noise to the player")
	m.free()
	p.free()


func _test_bind_and_godmode() -> void:
	var p := _spawn_player()
	p.take_damage(1.0, {"bind_sec": 1.0})
	_expect(p.is_bound(), "bind_sec binds the player")
	for i in 10:
		p.step(DT, {"move": Vector2.UP})
	_expect(Vector2(p.velocity.x, p.velocity.z).length() < 0.01, "bound player does not move")
	var health := p.health
	DebugConsole.godmode = true
	p.take_damage(50.0)
	DebugConsole.godmode = false
	_expect(p.health == health, "godmode blocks damage")
	p.free()


func _test_interact_opens_container() -> void:
	var p := _spawn_player()
	var c: LootContainer = CONTAINER_SCENE.instantiate()
	c.def = load("res://data/loot/containers/drawer.tres")
	c.loot_table = load("res://data/loot/tables/flooded_mall_drawer.tres")
	c.position = Vector3(0.0, 0.0, -1.0)
	add_child(c)
	for i in 3:
		await get_tree().physics_frame
	_expect(p.interact(), "interact reaches a container in range")
	_expect(c.state == LootContainer.State.OPENING, "container starts opening")
	c.free()
	p.free()


func _spawn_player() -> Player:
	var p: Player = PLAYER_SCENE.instantiate()
	add_child(p)
	return p


func _on_noise(position: Vector3, radius: float, source: Node) -> void:
	_noises.append([position, radius, source])


func _last_noise_radius() -> float:
	return _noises.back()[1] if not _noises.is_empty() else -1.0


func _expect(cond: bool, what: String) -> void:
	if not cond:
		push_error("test_wiring: %s" % what)
		_ok = false
