extends Node
## Vault over low cover: pushing into low cover (B-06 low_cover group) for stats.vault_hold_sec
## climbs over it with a "vault" noise; too tall, too deep, not low cover, no room behind, aiming
## or supporting someone keeps the player in front. Drives Player.step() + move_and_slide() in a
## physics world (player physics off).

const DT := 1.0 / 60.0
const PLAYER_SCENE := preload("res://field/player/player.tscn")
## Player feet at z 0 walking toward -z; the cover's near face sits just past the body.
const FACE_Z := -0.4

var _ok := true


func run() -> bool:
	_ok = true
	await _test_vault_over()
	await _test_blocked(Vector3(2, 1.6, 0.4), true, {}, "too tall")
	await _test_blocked(Vector3(2, 0.8, 2.0), true, {}, "too deep")
	await _test_blocked(Vector3(2, 0.8, 0.4), false, {}, "not low cover")
	await _test_blocked(Vector3(2, 0.8, 0.4), true, {"aim": true}, "aiming")
	await _test_blocked(Vector3(2, 0.8, 0.4), true, {"support": true}, "supporting")
	await _test_no_room()
	return _ok


func _test_vault_over() -> void:
	var w := await _world(Vector3(2, 0.8, 0.4), true)
	var p: Player = w["player"]
	var states: Array = []
	p.move_state_changed.connect(func(s: Player.MoveState) -> void: states.append(s))
	var noises: Array = []
	var listener := func(_pos: Vector3, radius: float, source: Node) -> void:
		if source == p or (source != null and p.is_ancestor_of(source)):
			noises.append(radius)
	EventBus.noise_emitted.connect(listener)
	_drive(p, p.stats.vault_hold_sec * 0.5, {"move": Vector2.UP})
	_expect(not states.has(Player.MoveState.VAULT), "a short push does not vault")
	_drive(p, 0.1, {})
	_drive(p, p.stats.vault_hold_sec + 0.1, {"move": Vector2.UP})
	_expect(p.is_vaulting(), "pushing long enough starts the vault")
	var weapons := p.get_node(^"Weapons") as WeaponHolder
	_expect(not weapons.can_act(), "no weapons mid-vault")
	_expect(noises.any(func(r: float) -> bool: return absf(r - 5.0) < 0.01),
			"vault makes a 5 m noise (got %s)" % [noises])
	_drive(p, p.stats.vault_duration_sec + 0.1, {})
	_expect(not p.is_vaulting(), "vault ends")
	_expect(p.global_position.z < FACE_Z - 0.4 - 0.3, "lands behind the cover (z %.2f)" % p.global_position.z)
	_expect(absf(p.global_position.y) < 0.1, "lands on the floor (y %.2f)" % p.global_position.y)
	EventBus.noise_emitted.disconnect(listener)
	w["root"].free()


func _test_blocked(size: Vector3, low_cover: bool, input: Dictionary, what: String) -> void:
	var w := await _world(size, low_cover)
	var p: Player = w["player"]
	if input.get("support", false):
		p.one_hand_only = true
	var states: Array = []
	p.move_state_changed.connect(func(s: Player.MoveState) -> void: states.append(s))
	_drive(p, 1.0, {"move": Vector2.UP, "aim": input.get("aim", false)})
	_expect(not states.has(Player.MoveState.VAULT), "%s: no vault" % what)
	_expect(p.global_position.z > FACE_Z, "%s: stays in front (z %.2f)" % [what, p.global_position.z])
	w["root"].free()


## A wall right behind the cover: no room to land.
func _test_no_room() -> void:
	var w := await _world(Vector3(2, 0.8, 0.4), true)
	_box(w["root"], Vector3(0, 1.5, FACE_Z - 0.4 - 0.2), Vector3(2, 3, 0.2))
	await _physics()
	var p: Player = w["player"]
	_drive(p, 1.0, {"move": Vector2.UP})
	_expect(not p.is_vaulting() and p.global_position.z > FACE_Z, "no room behind: no vault")
	w["root"].free()


## Floor, the player at the origin and a box of `size` whose near face is at FACE_Z.
func _world(size: Vector3, low_cover: bool) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	_box(root, Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	var cover := _box(root, Vector3(0, size.y * 0.5, FACE_Z - size.z * 0.5), size)
	if low_cover:
		cover.add_to_group(WeaponHolder.LOW_COVER_GROUP)
	var p: Player = PLAYER_SCENE.instantiate()
	root.add_child(p)
	p.set_physics_process(false)
	p.get_node(^"Weapons").set_physics_process(false)
	p.global_position = Vector3(0, 0.02, 0)
	await _physics()
	return {"root": root, "player": p}


func _drive(p: Player, seconds: float, input: Dictionary) -> void:
	for i in roundi(seconds / DT):
		p.step(DT, input)
		if not p.is_vaulting():
			p.move_and_slide()


func _box(parent: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = pos
	return body


func _physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_ok = false
		push_error("test_vault: " + label)
