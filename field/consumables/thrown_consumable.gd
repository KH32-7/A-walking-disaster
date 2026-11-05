class_name ThrownConsumable
extends Node3D
## A thrown consumable in flight and on the ground (B-16): noise lure, flashbang, grenade.
## Flies a ballistic arc from the hand to the target with one world ray per step, like ShockOrb.
## It is not a physics body, so it has no collision layer. Hitting a wall drops it to the floor there.
## Where it lands (numbers in data/classes/consumables/):
##   LURE   after def.delay_sec, one def.noise there. Monsters that hear it investigate the spot.
##   FLASH  monsters in def.radius with a clear line get def.target_status (blind), LIGHT family
##          heal def.light_heal_ratio of max hp instead, mist monsters show (mist reveal()).
##   BLAST  def.damage to monsters in def.radius with a clear line, plus def.noise.
## Lane D: Fx.spawn(&"consumable_<id>", point, {"radius"}) and Audio.play(&"consumable_<id>", point).
## Design reference: docs/design/03-combat-classes.md "소모품", 04-monsters.md 물안개

signal landed(point: Vector3)
signal triggered(point: Vector3)

const WORLD_MASK := 1 << (Enums.LAYER_WORLD - 1)
## Flight time per meter thrown, with a floor (s). Sets how high the arc goes.
const FLIGHT_SEC_PER_M := 0.1
const FLIGHT_MIN_SEC := 0.25
## Effect line rays start this high above the landing point and the monster (m).
const RAY_HEIGHT := 0.5
## Looks this far down for the floor after hitting a wall (m).
const FLOOR_PROBE := 3.0

var def: ConsumableDef
## Who threw it: blast damage source (monsters that get hit chase them).
var thrower: Node3D
var velocity := Vector3.ZERO

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _flying := false
var _target := Vector3.ZERO
var _arrive_left := 0.0
var _fuse := -1.0
var _noise: NoiseEmitter


func _ready() -> void:
	_noise = NoiseEmitter.new()
	_noise.name = &"Noise"
	add_child(_noise)


func _physics_process(delta: float) -> void:
	advance(delta)


## Starts the arc from the current position so it lands on `target`.
func launch(target: Vector3) -> void:
	var to := target - global_position
	var sec := maxf(Vector2(to.x, to.z).length() * FLIGHT_SEC_PER_M, FLIGHT_MIN_SEC)
	velocity = to / sec + Vector3.UP * 0.5 * _gravity * sec
	_target = target
	_arrive_left = sec
	_flying = true


func is_flying() -> bool:
	return _flying


## One flight or fuse step. Tests call this directly.
func advance(delta: float) -> void:
	if not is_inside_tree():
		return
	if _flying:
		_fly(delta)
	elif _fuse >= 0.0:
		_fuse -= delta
		if _fuse <= 0.0:
			_fuse = -1.0
			trigger()


## Ends the flight at `point`: a lure starts its fuse, the rest go off at once.
func land(point: Vector3) -> void:
	if not _flying:
		return
	_flying = false
	velocity = Vector3.ZERO
	global_position = point
	landed.emit(point)
	if def.effect == ConsumableDef.Effect.LURE and def.delay_sec > 0.0:
		_fuse = def.delay_sec
	else:
		trigger()


## The effect, its noise, Fx and sound, then the item is gone.
func trigger() -> void:
	var point := global_position
	match def.effect:
		ConsumableDef.Effect.FLASH:
			_flash(point)
		ConsumableDef.Effect.BLAST:
			_blast(point)
	if def.noise != &"":
		_noise.emit(def.noise)
	Fx.spawn(StringName("consumable_%s" % def.id), point, {"radius": def.radius})
	Audio.play(StringName("consumable_%s" % def.id), point)
	triggered.emit(point)
	queue_free()


## Living monsters within def.radius of `point` with no wall in between.
func monsters_in_reach(point: Vector3) -> Array[Monster]:
	var out: Array[Monster] = []
	for node in get_tree().get_nodes_in_group(Monster.GROUP):
		var monster := node as Monster
		if monster == null or monster.is_dead() or not monster.is_inside_tree():
			continue
		if monster.global_position.distance_to(point) <= def.radius and _clear_line(point, monster):
			out.append(monster)
	return out


func _fly(delta: float) -> void:
	var step := minf(delta, _arrive_left)
	var from := global_position
	var to := from + velocity * step + Vector3.DOWN * 0.5 * _gravity * step * step
	velocity.y -= _gravity * step
	_arrive_left -= step
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK))
	if not hit.is_empty():
		land(_floor_under(hit.position + hit.normal * 0.05))
	elif _arrive_left <= 0.0:
		land(_target)
	else:
		global_position = to


func _flash(point: Vector3) -> void:
	for monster in monsters_in_reach(point):
		if monster.def.family == Enums.Element.LIGHT:
			monster.hp = minf(monster.max_hp, monster.hp + monster.max_hp * def.light_heal_ratio)
		elif def.target_status != &"":
			monster.status.apply(def.target_status)
		var mist := monster.get_behavior(&"mist")
		if mist != null and mist.has_method(&"reveal"):
			mist.call(&"reveal")


func _blast(point: Vector3) -> void:
	var info := {"source": thrower if is_instance_valid(thrower) else null, "position": point,
			"element": Enums.Element.NONE}
	for monster in monsters_in_reach(point):
		monster.take_damage(def.damage, info)


func _clear_line(point: Vector3, monster: Monster) -> bool:
	var up := Vector3.UP * RAY_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(point + up, monster.global_position + up, WORLD_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _floor_under(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point, point + Vector3.DOWN * FLOOR_PROBE, WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else point
