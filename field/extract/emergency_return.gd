class_name EmergencyReturn
extends Node
## Emergency return (B-22). ExtractionManager adds one as its child, so every region has it.
## A day raid warning during the sortie asks "go back?" (return_offered). Going back picks the
## nearest active extraction point (navmesh path length, straight line without a navmesh),
## keeps a route to it for the world / map line, sets the manager's wait to 0 s and emits
## EventBus.emergency_return_requested. SceneRouter then sends the extraction into the
## day raid defence.
##
## Lane D: find this node with get_tree().get_first_node_in_group(EmergencyReturn.GROUP),
## show the question on return_offered and call answer(). Draw the route from route_changed / route().
## The compass marker of the target point gets "emergency": true in Player.hud_state().
## Design reference: docs/design/10-raids-defense.md "출격 중 습격과 긴급 귀환", 02-field.md "탈출"

## A day raid warning came in. Ask the player; answer with answer(). raid = the raid_warning info.
signal return_offered(raid: Dictionary)
## The player chose to go back. The countdown at every point is now 0 s.
signal return_started(point_id: StringName)
## New route from the player to the target point (world positions, first = near the player).
signal route_changed(points: PackedVector3Array)

const GROUP := &"field_emergency_return"
## Seconds between route updates while returning.
const REPATH_SEC := 0.5
## Navigation layers the player walks on (B-12: 1 = walkers).
const NAV_LAYERS := 1

enum State { IDLE, OFFERED, DECLINED, RETURNING }

var state := State.IDLE

var _target: ExtractPoint
var _route := PackedVector3Array()
var _repath_left := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.raid_warning.connect(_on_raid)
	# A day raid without a guard post comes with no warning (10 "예고"): raid_started asks too.
	EventBus.raid_started.connect(_on_raid)


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Public ---

## Answer to return_offered. true = go back now, false = keep exploring (the raid is auto-resolved).
func answer(go_back: bool) -> void:
	if state != State.OFFERED:
		return
	if not go_back:
		state = State.DECLINED
		return
	var manager := _manager()
	var player := _player()
	if manager == null or manager.state == ExtractionManager.State.DONE or player == null:
		state = State.DECLINED
		return
	state = State.RETURNING
	manager.wait_multiplier = 0.0
	_target = pick_target(player.global_position)
	_update_route(player.global_position)
	return_started.emit(target_point_id())
	EventBus.emergency_return_requested.emit()


## Id of the point we are heading to, &"" when not returning.
func target_point_id() -> StringName:
	return _target.id if _target != null else &""


## Route to the target point, empty when not returning.
func route() -> PackedVector3Array:
	return _route


## Nearest usable active point from `from`. KEY / BATTERY points without the item in the bag
## count only when nothing else is left.
func pick_target(from: Vector3) -> ExtractPoint:
	var manager := _manager()
	if manager == null:
		return null
	var best: ExtractPoint
	var best_cost := INF
	for point in manager.active_points():
		var cost := _path_cost(from, point.global_position)
		if not _usable(point):
			cost += 1.0e6
		if cost < best_cost:
			best_cost = cost
			best = point
	return best


## Route upkeep. _physics_process calls it; tests call it directly.
func tick(delta: float) -> void:
	if state != State.RETURNING or _target == null:
		return
	_repath_left -= delta
	if _repath_left > 0.0:
		return
	var player := _player()
	if player != null:
		_update_route(player.global_position)


# --- Internals ---

func _on_raid(raid: Dictionary) -> void:
	if state != State.IDLE or int(raid.get("time", -1)) != Enums.RaidTime.DAY:
		return
	var manager := _manager()
	if manager == null or manager.state == ExtractionManager.State.DONE:
		return
	state = State.OFFERED
	return_offered.emit(raid.duplicate(true))


func _manager() -> ExtractionManager:
	return get_parent() as ExtractionManager


func _player() -> Node3D:
	return get_tree().get_first_node_in_group(Player.GROUP) as Node3D


func _usable(point: ExtractPoint) -> bool:
	var item: StringName = ExtractionManager.REQUIRED_ITEM.get(point.type, &"")
	return item == &"" or Bag.count_of(item) > 0


func _nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := get_viewport().world_3d.navigation_map
	return NavigationServer3D.map_get_path(map, from, to, true, NAV_LAYERS)


## Walking distance along the navmesh, plus the gap if the path stops short of the point.
## Straight line when there is no navmesh.
func _path_cost(from: Vector3, to: Vector3) -> float:
	var path := _nav_path(from, to)
	if path.is_empty():
		return from.distance_to(to)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length + path[path.size() - 1].distance_to(to)


func _update_route(from: Vector3) -> void:
	_repath_left = REPATH_SEC
	_route = _nav_path(from, _target.global_position)
	if _route.is_empty():
		_route = PackedVector3Array([from, _target.global_position])
	route_changed.emit(_route)
