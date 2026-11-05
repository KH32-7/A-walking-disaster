class_name RaidMarch
extends RefCounted
## Movement helper for raiders (B-23): monsters Lane C spawns into a base defense battle.
## Monster creates one when Monster.raid_goal is set and calls it from _move_to.
##
## - Follows the navigation map of the monster's world (the base layout bakes one). With no map
##   or no path left it walks straight at the point and bumps into whatever is in the way.
## - A raid structure in the way (a world-layer collider whose node or parent is in
##   STRUCTURE_GROUP and has take_damage) is hit every def.attack_interval instead of walked into.
##   Lane C's structure decides what the hit does; info carries the siege numbers from MonsterDef.
## - goal(): raid_goal, or the nearest node in GATE_GROUP for def.charges_gates (debris ram).
## Numbers: MonsterRules RAID_*.

## Lane C: walls, palisades, doors, traps ... anything raiders may break. A destroyed structure
## leaves the group (or the tree).
const STRUCTURE_GROUP := &"raid_structures"
## Lane C: doors and barricades (also in STRUCTURE_GROUP). def.charges_gates raiders go here first.
const GATE_GROUP := &"raid_gates"
const WORLD_MASK := 1 << (Enums.LAYER_WORLD - 1)

var monster: Monster

var _path := PackedVector3Array()
var _index := 0
var _path_goal := Vector3.INF
var _repath_left := 0.0
var _hit_left := MonsterRules.ATTACK_WINDUP_SEC


func _init(owner: Monster) -> void:
	monster = owner


## Where the raider heads when it has nothing to fight.
func goal() -> Vector3:
	if monster.def.charges_gates:
		var gate := nearest_gate()
		if gate != null:
			return gate.global_position
	return monster.raid_goal


## Nearest standing gate, or null.
func nearest_gate() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in monster.get_tree().get_nodes_in_group(GATE_GROUP):
		if not node is Node3D or not node.has_method(&"take_damage"):
			continue
		var d := monster.global_position.distance_squared_to(node.global_position)
		if d < best_dist:
			best = node
			best_dist = d
	return best


## Next point to steer at on the way to `point`: a navigation path corner, or `point` itself.
func next_corner(point: Vector3, delta: float) -> Vector3:
	_repath_left -= delta
	if _repath_left <= 0.0 or _flat(_path_goal - point) > MonsterRules.RAID_REPATH_GOAL_MOVE:
		_repath(point)
	while _index < _path.size() and _flat(_path[_index] - monster.global_position) < MonsterRules.RAID_WAYPOINT_REACHED:
		_index += 1
	return _path[_index] if _index < _path.size() else point


## Raid structure right in front (along `dir`, within attack range), or null.
func blocking_structure(dir: Vector3) -> Node3D:
	var origin := monster.global_position + Vector3.UP * MonsterRules.RAID_BLOCK_RAY_HEIGHT
	var to := origin + dir.normalized() * monster.def.attack_range
	var query := PhysicsRayQueryParameters3D.create(origin, to, WORLD_MASK, [monster.get_rid()])
	var hit := monster.get_world_3d().direct_space_state.intersect_ray(query)
	return structure_of(hit.get("collider")) if not hit.is_empty() else null


## Hits `structure` once the attack timer allows (first hit after the wind-up).
func hit(structure: Node3D, delta: float) -> void:
	_hit_left -= delta
	if _hit_left > 0.0:
		return
	_hit_left = monster.def.attack_interval
	var info := {
		"source": monster, "element": monster.def.family, "monster_id": monster.def.id,
		"structure_damage_mult": monster.def.structure_damage_mult,
		"charges_gates": monster.def.charges_gates,
	}
	structure.call(&"take_damage", monster.attack_damage(), info)
	monster.attack_landed.emit(structure, info)


## Not hitting anything this step: the next hit waits for the wind-up again.
func reset_hit() -> void:
	_hit_left = MonsterRules.ATTACK_WINDUP_SEC


## The collider, or its nearest parent, that is a raid structure. null if neither is.
static func structure_of(collider: Variant) -> Node3D:
	var node := collider as Node
	while node != null:
		if node is Node3D and node.is_in_group(STRUCTURE_GROUP) and node.has_method(&"take_damage"):
			return node
		node = node.get_parent()
	return null


func _repath(point: Vector3) -> void:
	_repath_left = MonsterRules.RAID_REPATH_SEC
	_path_goal = point
	_index = 0
	var map := monster.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		_path = PackedVector3Array()  # no navigation synced (tests, maps without a navmesh)
		return
	_path = NavigationServer3D.map_get_path(map, monster.global_position, point, true)


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
