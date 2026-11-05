class_name ShockField
extends Node3D
## Shock puddle a ShockOrb leaves (B-18). For MonsterRules.SHOCK_FIELD_SEC it zaps the player
## and allies inside SHOCK_FIELD_RADIUS every SHOCK_FIELD_TICK_SEC (damage + shock_sec).
## TODO(B-14): shock status format.

var info: Dictionary = {}
var shooter: Monster

## Below this much time left, no new zap: float drift must not add a 7th zap at the 3 s edge.
const END_EPSILON := 0.0001

var _left := MonsterRules.SHOCK_FIELD_SEC
var _tick := 0.0


func _physics_process(delta: float) -> void:
	advance(delta)


## Runs the timers. Tests call this directly.
func advance(delta: float) -> void:
	if not is_inside_tree() or _left <= 0.0:
		return
	# Zap on the tick boundaries inside the lifetime: t = 0, 0.5, ... 2.5 (6 zaps for 3 s).
	# A boundary passed this step happened at (now + delta + _tick); it counts only if some
	# lifetime was still left at that moment.
	_tick -= delta
	while _tick <= 0.0 and _left - delta - _tick > END_EPSILON:
		_tick += MonsterRules.SHOCK_FIELD_TICK_SEC
		zap()
	_left -= delta
	if _left <= END_EPSILON:
		queue_free()


## Hits everyone inside once. Returns how many were hit.
func zap() -> int:
	var shape := SphereShape3D.new()
	shape.radius = MonsterRules.SHOCK_FIELD_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = ShockOrb.TARGET_LAYERS
	var hit_info := info.duplicate()
	hit_info["source"] = shooter if is_instance_valid(shooter) else null
	hit_info["position"] = global_position
	var count := 0
	var seen: Array[Object] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query):
		var body: Object = hit.collider
		if body in seen or not body.has_method("take_damage"):
			continue
		seen.append(body)
		body.take_damage(MonsterRules.SHOCK_FIELD_TICK_DAMAGE, hit_info)
		count += 1
	return count
