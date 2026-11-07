class_name FieldVehicle
extends CharacterBody3D
## A vehicle in the field (02 "탈것"). VehicleSpawner or the sortie loadout makes one with setup().
## - Layer 1 (world: blocks walking and shots like cover) + layer 7 (interactable: F to ride or repair).
## - The driver is the Player (Player.riding). Passengers are party members (companions, following
##   rescuees) parked on seats: hidden and off every physics layer. Hits on any rider go to the vehicle.
## - Broken (durability 0): needs a mechanic companion (former_job) nearby while the player holds F.
## Design reference: docs/design/02-field.md "탈것" (가안).

signal mounted()
signal dismounted()
signal wrecked()
signal repaired()

const GROUP := &"field_vehicles"
const TUNING: VehicleTuning = preload("res://data/vehicles/tuning/vehicle_tuning.tres")
const RIDE_LABEL := "타기"
const DISMOUNT_LABEL := "내리기"
const REPAIR_LABEL := "고치기 (꾹 누르기)"
const NEED_MECHANIC_LABEL := "정비공 필요"
const REPAIR_HOLD_LABEL := "고치는 중"
## Engine noise only above this speed (m/s).
const MOVING_SPEED := 0.5
## Damage look (no gauge, 02 "탈것"): grey smoke below TUNING.smoke_ratio, flames below
## TUNING.fire_ratio, dark smoke once broken.
const SMOKE_COLOR := Color(0.38, 0.38, 0.38, 0.6)
const FIRE_COLOR := Color(1.0, 0.45, 0.1, 0.85)
const WRECK_COLOR := Color(0.12, 0.12, 0.12, 0.7)

var def: VehicleDef
var durability := 0.0
## Garage uid when it came from the base, &"" when found in the field.
var garage_uid: StringName = &""
var driver: Player
## Seats after the driver, in boarding order.
var passengers: Array[Node3D] = []

var _input := Vector3.ZERO
var _speed := 0.0
var _repairer: Node3D
var _repair_left := 0.0
var _repair_from := Vector3.ZERO
## Monster instance id -> seconds until it can be rammed again.
var _ram_cooldown := {}
var _noise: NoiseEmitter
var _smoke: CPUParticles3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(p_def: VehicleDef, p_durability: float, p_garage_uid: StringName = &"") -> void:
	def = p_def
	durability = clampf(p_durability, 0.0, def.max_durability)
	garage_uid = p_garage_uid


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = (1 << (Enums.LAYER_WORLD - 1)) | (1 << (Enums.LAYER_INTERACTABLE - 1))
	# Boats only bump into the land around the water (layer 9); land vehicles into the world.
	var bounds := Enums.LAYER_BOAT_BOUNDS if def.surface == VehicleDef.Surface.WATER else Enums.LAYER_WORLD
	collision_mask = (1 << (bounds - 1)) | (1 << (Enums.LAYER_MONSTER - 1))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = def.body_size
	shape.shape = box
	shape.position.y = def.body_size.y * 0.5
	add_child(shape)
	add_child(_make_look())
	_noise = NoiseEmitter.new()
	add_child(_noise)
	_smoke = _make_smoke()
	add_child(_smoke)
	_update_damage_look()


func _physics_process(delta: float) -> void:
	_tick_repair(delta)
	for id in _ram_cooldown.keys():
		_ram_cooldown[id] -= delta
		if _ram_cooldown[id] <= 0.0:
			_ram_cooldown.erase(id)
	_drive(delta)
	if driver != null:
		driver.global_position = seat_position(0)
	_update_noise()


# --- Public API ----------------------------------------------------------------

func is_broken() -> bool:
	return durability <= 0.0


func forward() -> Vector3:
	return -global_basis.z


## World position of seat i (0 = driver). Passengers are hidden, so they all sit at the middle.
func seat_position(i: int) -> Vector3:
	return global_position + Vector3.UP * def.body_size.y * (0.3 if i == 0 else 0.5)


## Player.interact() entry: ride a working vehicle, or start the repair hold on a broken one.
func begin_open(interactor: Node3D) -> bool:
	var player := interactor as Player
	if player == null or driver != null:
		return false
	if not is_broken():
		return mount(player)
	if _repairer != null or mechanic_near() == null:
		return false
	_repairer = player
	_repair_from = player.global_position
	_repair_left = TUNING.repair_sec
	_noise.start_continuous(TUNING.repair_noise_action)
	return true


## [F] prompt words.
func interact_label() -> String:
	if driver != null or _repairer != null:
		return ""
	if not is_broken():
		return RIDE_LABEL
	return REPAIR_LABEL if mechanic_near() != null else NEED_MECHANIC_LABEL


## HUD hold ring while repairing, {} otherwise.
func hold_state() -> Dictionary:
	if _repairer == null:
		return {}
	return {"label": REPAIR_HOLD_LABEL, "progress": clampf(1.0 - _repair_left / TUNING.repair_sec, 0.0, 1.0)}


func mechanic_near() -> FieldCompanion:
	return mechanic_near_point(get_tree(), global_position)


## A standing mechanic companion within TUNING.mechanic_range_m of `point`, or null.
static func mechanic_near_point(tree: SceneTree, point: Vector3) -> FieldCompanion:
	for node in tree.get_nodes_in_group(FieldCompanion.GROUP):
		var c := node as FieldCompanion
		if c != null and c.state == FieldCompanion.State.ACTIVE and c.riding == null \
				and StringName(c.resident.get("former_job", &"")) == TUNING.mechanic_job \
				and c.global_position.distance_to(point) <= TUNING.mechanic_range_m:
			return c
	return null


## The player drives; nearby party members take the free seats (closest first).
func mount(player: Player) -> bool:
	if driver != null or is_broken() or player.is_riding():
		return false
	driver = player
	player.start_riding(self)
	for node in _boarders(player):
		_seat(node)
	mounted.emit()
	return true


## Everyone gets off beside it. False when there is no ground in reach (a boat away from the bank).
func can_dismount() -> bool:
	return driver != null and not _exit_spots(false).is_empty()


func dismount(force := false) -> bool:
	if driver == null:
		return false
	var spots := _exit_spots(force)
	if spots.is_empty():
		return false
	var player := driver
	driver = null
	_input = Vector3.ZERO
	player.stop_riding(spots[0])
	for i in passengers.size():
		_unseat(passengers[i], spots[(i + 1) % spots.size()])
	passengers.clear()
	dismounted.emit()
	return true


## Driver steering for this frame: world direction on the ground, length <= 1.
func set_input(dir: Vector3) -> void:
	_input = Vector3(dir.x, 0.0, dir.z).limit_length(1.0)


## Hits on the vehicle or on anyone riding it. At 0 everyone is thrown out and it is broken.
func take_damage(amount: float, _info: Dictionary = {}) -> void:
	if amount <= 0.0 or is_broken():
		return
	durability = maxf(durability - amount, 0.0)
	_update_damage_look()
	if is_broken():
		_speed = 0.0
		dismount(true)
		wrecked.emit()


# --- Driving -------------------------------------------------------------------

func _drive(delta: float) -> void:
	var wanted := 0.0
	if driver != null and _input.length_squared() > 0.0001:
		var dir := _input.normalized()
		var turn := deg_to_rad(def.turn_speed_deg) * delta
		rotate_y(clampf(forward().signed_angle_to(dir, Vector3.UP), -turn, turn))
		# Full speed only once it points where the stick points.
		wanted = def.speed * _input.length() * maxf(forward().dot(dir), 0.0)
	_speed = move_toward(_speed, wanted, def.acceleration * delta)
	var flat := forward() * _speed
	velocity.x = flat.x
	velocity.z = flat.z
	if def.surface == VehicleDef.Surface.WATER:
		velocity.y = 0.0
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	var speed_before := _speed
	move_and_slide()
	_ram(speed_before)
	# Hitting a wall or a monster eats the speed.
	_speed = minf(_speed, Vector2(velocity.x, velocity.z).length())


func _ram(speed: float) -> void:
	if not def.ram or speed < TUNING.ram_min_speed:
		return
	for i in get_slide_collision_count():
		var monster := get_slide_collision(i).get_collider() as Monster
		if monster == null or _ram_cooldown.has(monster.get_instance_id()):
			continue
		_ram_cooldown[monster.get_instance_id()] = TUNING.ram_cooldown_sec
		monster.take_damage(speed * TUNING.ram_damage_per_speed,
				{"source": driver, "status": [{"id": &"knockback", "dir": forward()}]})
		take_damage(TUNING.ram_self_damage)


func _update_noise() -> void:
	if _repairer != null or def.noise_action == &"":
		return
	var moving := absf(_speed) > MOVING_SPEED
	if moving and not _noise.is_continuous():
		_noise.start_continuous(def.noise_action)
	elif not moving and _noise.is_continuous():
		_noise.stop_continuous()


# --- Repair ---------------------------------------------------------------------

## Hold F with the mechanic nearby; letting go, walking off or the mechanic leaving cancels.
func _tick_repair(delta: float) -> void:
	if _repairer == null:
		return
	if _repairer.get(&"interact_held") == false or mechanic_near() == null \
			or _repairer.global_position.distance_to(_repair_from) > TUNING.repair_leave_m:
		_stop_repair()
		return
	_repair_left -= delta
	if _repair_left <= 0.0:
		_stop_repair()
		durability = maxf(durability, def.max_durability * TUNING.repaired_ratio)
		_update_damage_look()
		repaired.emit()


func _stop_repair() -> void:
	_repairer = null
	_noise.stop_continuous()


# --- Seats ----------------------------------------------------------------------

func _boarders(player: Player) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(ExtractionManager.PARTY_GROUP):
		var n := node as Node3D
		if n != null and _can_board(n) \
				and n.global_position.distance_to(player.global_position) <= TUNING.board_range_m:
			found.append(n)
	var from := player.global_position
	found.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
	return found.slice(0, def.seats - 1)


## Standing companions and following rescuees. Wheelchair users only where def.wheelchair_ok.
func _can_board(n: Node3D) -> bool:
	if n is FieldCompanion:
		var c := n as FieldCompanion
		return c.state == FieldCompanion.State.ACTIVE and c.riding == null \
				and (def.wheelchair_ok or c.navigation_layers() != FieldCompanion.NAV_NO_STAIRS)
	if n is RescueTarget:
		var t := n as RescueTarget
		return t.state == RescueTarget.State.FOLLOW and t.riding == null \
				and (def.wheelchair_ok or t.spawn.move_type != RescueSpawn.Move.WHEELCHAIR)
	return false


func _seat(n: Node3D) -> void:
	passengers.append(n)
	n.set(&"riding", self)
	n.set_meta(&"layer_before_ride", (n as CollisionObject3D).collision_layer)
	(n as CollisionObject3D).collision_layer = 0
	n.visible = false


func _unseat(n: Node3D, at: Vector3) -> void:
	n.set(&"riding", null)
	(n as CollisionObject3D).collision_layer = n.get_meta(&"layer_before_ride")
	n.remove_meta(&"layer_before_ride")
	n.visible = true
	n.global_position = at


## Ground points beside it: right, left, behind. Land vehicles always have them. Boats need walkable
## ground (nav map) within TUNING.exit_snap_m; force takes the nearest ground anywhere (wrecked boat).
func _exit_spots(force: bool) -> Array[Vector3]:
	var right := Vector3(global_basis.x.x, 0.0, global_basis.x.z).normalized()
	var side := def.body_size.x * 0.5 + TUNING.exit_gap_m
	var back := def.body_size.z * 0.5 + TUNING.exit_gap_m
	var out: Array[Vector3] = []
	for offset: Vector3 in [right * side, -right * side, -forward() * back]:
		var p: Vector3 = global_position + offset
		if def.surface == VehicleDef.Surface.LAND:
			out.append(p)
			continue
		var ground := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)
		if force or ground.distance_to(p) <= TUNING.exit_snap_m:
			out.append(ground)
	return out


# --- Look -----------------------------------------------------------------------

## Model fitted to body_size length and turned by model_yaw_deg; a grey box without a model.
func _make_look() -> Node3D:
	if def.model == null:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = def.body_size
		mesh.mesh = box
		mesh.position.y = def.body_size.y * 0.5
		return mesh
	return fit_model(def.model.instantiate() as Node3D, def.body_size.z, def.model_yaw_deg)


func _update_damage_look() -> void:
	if _smoke == null:
		return
	var ratio := durability / maxf(def.max_durability, 1.0)
	_smoke.emitting = ratio < TUNING.smoke_ratio
	_smoke.color = WRECK_COLOR if is_broken() else (FIRE_COLOR if ratio < TUNING.fire_ratio else SMOKE_COLOR)


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "DamageSmoke"
	p.emitting = false
	p.amount = 14
	p.lifetime = 1.6
	p.position.y = def.body_size.y
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0.0, 0.4, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	return p


## Turns `model` by yaw_deg, scales it so its front-to-back length (along Z after the turn) is
## `length`, and lifts it so its lowest point sits on the origin. Returns the model.
static func fit_model(model: Node3D, length: float, yaw_deg: float) -> Node3D:
	var turn := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)))
	var box := turn * _mesh_bounds(model)
	var s := length / box.size.z if box.size.z > 0.0 else 1.0
	model.rotation.y = deg_to_rad(yaw_deg)
	model.scale = Vector3.ONE * s
	model.position.y = -box.position.y * s
	return model


## Bounds of every mesh under `root`, in root space.
static func _mesh_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var m := node as MeshInstance3D
		var local := m.transform
		var parent := m.get_parent()
		while parent != root and parent is Node3D:
			local = (parent as Node3D).transform * local
			parent = parent.get_parent()
		var part := local * m.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box
