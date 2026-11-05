class_name SkillTargets
extends RefCounted
## Shape queries shared by class skills (B-13): the player's ClassSkills and CompanionSkill.
## Monsters are found on the monster layer and resolved to their Monster node (weak points and
## child colliders included). Dead monsters are skipped.

const MONSTER_MASK := 1 << (Enums.LAYER_MONSTER - 1)
const WORLD_MASK := 1 << (Enums.LAYER_WORLD - 1)
const MAX_HITS := 32
## Query height above the feet (same as WeaponHolder.MELEE_HEIGHT).
const BODY_HEIGHT := 1.0
## Monster bodies are not points: a body this far outside a path still counts as on it.
const BODY_SLACK := 0.4
## A dash stops this far before a wall.
const WALL_MARGIN := 0.5


## Living monsters whose collider touches a sphere of `radius` around `center` (feet height).
static func monsters_in_radius(from: Node3D, center: Vector3, radius: float) -> Array[Monster]:
	var found: Array[Monster] = []
	if from == null or not from.is_inside_tree() or radius <= 0.0:
		return found
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), center + Vector3.UP * BODY_HEIGHT)
	query.collision_mask = MONSTER_MASK
	query.collide_with_areas = true
	for hit in from.get_world_3d().direct_space_state.intersect_shape(query, MAX_HITS):
		var monster := monster_of(hit["collider"])
		if monster != null and not monster.is_dead() and not monster in found:
			found.append(monster)
	return found


## Living monsters within half_width of the flat segment a -> b, nearest to `a` first.
static func monsters_on_segment(from: Node3D, a: Vector3, b: Vector3, half_width: float) -> Array[Monster]:
	var mid := (a + b) * 0.5
	var reach := a.distance_to(b) * 0.5 + half_width + BODY_SLACK
	var flat_a := Vector3(a.x, 0.0, a.z)
	var flat_b := Vector3(b.x, 0.0, b.z)
	var on_path: Array[Monster] = []
	for monster in monsters_in_radius(from, mid, reach):
		var p := Vector3(monster.global_position.x, 0.0, monster.global_position.z)
		if p.distance_to(Geometry3D.get_closest_point_to_segment(p, flat_a, flat_b)) <= half_width + BODY_SLACK:
			on_path.append(monster)
	on_path.sort_custom(func(m1: Monster, m2: Monster) -> bool:
		return m1.global_position.distance_squared_to(a) < m2.global_position.distance_squared_to(a))
	return on_path


## How far `from` can travel from `origin` along flat `dir` (up to `distance`) before a wall.
static func clear_distance(from: CollisionObject3D, origin: Vector3, dir: Vector3, distance: float) -> float:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	if from == null or not from.is_inside_tree() or flat == Vector3.ZERO:
		return 0.0
	var start := origin + Vector3.UP * BODY_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(start, start + flat * distance, WORLD_MASK, [from.get_rid()])
	var hit := from.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return distance
	return maxf(start.distance_to(hit["position"]) - WALL_MARGIN, 0.0)


## The Monster a collider belongs to (itself, a parent, or a weak point's monster), or null.
static func monster_of(node: Object) -> Monster:
	var n := node as Node
	while n != null and not n is Monster:
		n = n.get_parent()
	return n as Monster
