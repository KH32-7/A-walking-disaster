class_name ShockOrb
extends Node3D
## Signal wraith's ranged electric orb (B-18, shock_orb behavior). Flies straight with a ray
## per step against the world, player and ally layers. Hitting the player or an ally deals
## `damage`; wherever it stops (hit, wall or MonsterRules.ORB_MAX_RANGE) it leaves a ShockField.
## Design: docs/design/04-monsters.md 신호등 망령 "원거리 전기 구체, 맞은 자리에 3초 감전 장판"

const FIELD_SCENE := preload("res://field/monsters/projectiles/shock_field.tscn")
const HIT_MASK := (1 << (Enums.LAYER_WORLD - 1)) | (1 << (Enums.LAYER_PLAYER - 1)) | (1 << (Enums.LAYER_ALLY - 1))
const TARGET_LAYERS := (1 << (Enums.LAYER_PLAYER - 1)) | (1 << (Enums.LAYER_ALLY - 1))
## Landing looks this far down for the floor under the orb.
const FLOOR_PROBE := 3.0

var velocity := Vector3.ZERO
var damage := 0.0
## Hit info from the monster (element, monster_id, shock_sec ...).
var info: Dictionary = {}
var shooter: Monster

var _travelled := 0.0
var _done := false


func _physics_process(delta: float) -> void:
	advance(delta)


## One flight step. Tests call this directly.
func advance(delta: float) -> void:
	if _done or not is_inside_tree():
		return
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	if is_instance_valid(shooter):
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var body := hit.collider as CollisionObject3D
		if body and (body.collision_layer & TARGET_LAYERS) != 0 and body.has_method("take_damage"):
			body.take_damage(damage, _hit_info())
		land(hit.position)
		return
	global_position = to
	_travelled += from.distance_to(to)
	if _travelled >= MonsterRules.ORB_MAX_RANGE:
		land(to)


## Ends the flight and leaves a shock field on the floor under `point`.
func land(point: Vector3) -> void:
	if _done:
		return
	_done = true
	var parent := get_parent()
	if parent:
		var field := FIELD_SCENE.instantiate() as ShockField
		field.info = _hit_info()
		field.shooter = shooter
		field.position = _floor_under(point)
		parent.add_child.call_deferred(field)
	queue_free()


func _hit_info() -> Dictionary:
	var out := info.duplicate()
	out["source"] = shooter if is_instance_valid(shooter) else null
	out["position"] = global_position
	return out


func _floor_under(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.1,
			point + Vector3.DOWN * FLOOR_PROBE, 1 << (Enums.LAYER_WORLD - 1))
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var global_point: Vector3 = hit.position if not hit.is_empty() else point + Vector3.DOWN * MonsterRules.SIGHT_RAY_HEIGHT
	var parent := get_parent() as Node3D
	return parent.to_local(global_point) if parent else global_point
