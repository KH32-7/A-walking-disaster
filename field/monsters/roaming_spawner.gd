class_name RoamingSpawner
extends Node3D
## Monsters that do not belong to a nest (user request 2026-11-05: some just roam the map).
## When the region loads it scatters ROAM_START_GROUPS small packs over outdoor navmesh away from
## the player, then adds one pack every ROAM_INTERVAL_SEC where the player cannot see it
## (off camera and farther than ROAM_MIN_PLAYER_DIST). A pack wanders around its own spawn point.
## Same rules as MonsterSpawner: the region cap (MonsterRules.REGION_MAX_ALIVE) counts nest and
## roaming monsters together, and at night the timer runs FieldState.night.spawn_mult faster and
## MonsterSpawner.apply_night() is applied. Numbers: MonsterRules ROAM_*. Not in 04 design yet.

signal monster_spawned(monster: Monster)

## Spawn pool. NORMAL tier defs that can move (spore pods stay put, so they never roam).
@export var monster_defs: Array[MonsterDef] = []
## Limits the pool to defs listing this region. Empty = no region filter.
@export var region_id: StringName = &""
@export var spawn_start_groups := true
## Spawn points must be on these navigation layers (1 = on foot).
@export_flags_3d_navigation var navigation_layers: int = 1
## IndoorZones under this node are not spawn ground. Empty = this node's parent.
@export var zones_root: NodePath

var _alive: Array[Monster] = []
var _timer := MonsterRules.ROAM_INTERVAL_SEC
var _started := false
## xz outlines of IndoorZone shapes, collected on the first tick.
var _indoor: Array[PackedVector2Array] = []


func _ready() -> void:
	FieldState.night_started.connect(_on_night_started)


func _process(delta: float) -> void:
	tick(delta)


## Advances the spawn timer. Tests call this with large deltas.
func tick(delta: float) -> void:
	if not _started:
		# The navigation map syncs a few frames after the region loads; wait for it.
		if not _nav_ready():
			return
		_started = true
		_collect_indoor()
		if spawn_start_groups:
			for i in MonsterRules.ROAM_START_GROUPS:
				# Leave room under ROAM_MAX_ALIVE for the packs still to come (1 monster each).
				var packs_left := MonsterRules.ROAM_START_GROUPS - i - 1
				_spawn_pack(MonsterRules.ROAM_START_MIN_PLAYER_DIST, false,
						packs_left * MonsterRules.ROAM_GROUP_MIN)
	_timer -= delta * (FieldState.night.spawn_mult if FieldState.is_night() else 1.0)
	while _timer <= 0.0:
		_timer += MonsterRules.ROAM_INTERVAL_SEC
		_spawn_pack(MonsterRules.ROAM_MIN_PLAYER_DIST, true)


func alive_count() -> int:
	_prune()
	return _alive.size()


func alive() -> Array[Monster]:
	_prune()
	return _alive.duplicate()


## Spawns up to `count` monsters of one def at `at` as one pack. def = null picks one.
func spawn_group(at: Vector3, count: int, def: MonsterDef = null) -> Array[Monster]:
	var out: Array[Monster] = []
	var pick := def if def else _pick_def()
	if pick == null or pick.scene == null:
		push_warning("RoamingSpawner: no def that can roam")
		return out
	var pack := MonsterPack.new()
	for i in count:
		if alive_count() >= MonsterRules.ROAM_MAX_ALIVE \
				or get_tree().get_nodes_in_group(Monster.GROUP).size() >= MonsterRules.REGION_MAX_ALIVE:
			break
		var monster := pick.scene.instantiate() as Monster
		monster.def = pick
		monster.home = at
		monster.wander_radius = MonsterRules.ROAM_WANDER_RADIUS
		var angle := randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * randf() * MonsterRules.SPAWN_SCATTER_RADIUS
		monster.position = to_local(at + offset)
		pack.add(monster)
		monster.name = String(pick.id)
		add_child(monster, true)
		_alive.append(monster)
		out.append(monster)
		if FieldState.is_night():
			MonsterSpawner.apply_night(monster, true)
		monster_spawned.emit(monster)
	return out


## reserve = roaming slots to keep free for packs that still have to spawn (start packs).
func _spawn_pack(min_player_dist: float, hide_from_camera: bool, reserve: int = 0) -> void:
	var room := MonsterRules.ROAM_MAX_ALIVE - alive_count() - reserve
	if room <= 0:
		return
	var at := _pick_point(min_player_dist, hide_from_camera)
	if at != Vector3.INF:
		var size := randi_range(MonsterRules.ROAM_GROUP_MIN, MonsterRules.ROAM_GROUP_MAX)
		spawn_group(at, mini(size, room))


## Random outdoor navmesh point that keeps the ROAM_* distances, or Vector3.INF.
## If no point keeps ROAM_SPREAD from the other packs, tries once more without that one rule.
func _pick_point(min_player_dist: float, hide_from_camera: bool) -> Vector3:
	var p := _try_points(min_player_dist, hide_from_camera, true)
	return p if p != Vector3.INF else _try_points(min_player_dist, hide_from_camera, false)


func _try_points(min_player_dist: float, hide_from_camera: bool, keep_spread: bool) -> Vector3:
	var map := get_world_3d().navigation_map
	var players := get_tree().get_nodes_in_group(Player.GROUP)
	var nests := get_tree().get_nodes_in_group(MonsterNest.GROUP)
	var camera := get_viewport().get_camera_3d() if hide_from_camera else null
	for i in MonsterRules.ROAM_POINT_TRIES:
		var p := NavigationServer3D.map_get_random_point(map, navigation_layers, true)
		if p == Vector3.ZERO or p.y > MonsterRules.ROAM_MAX_Y or _is_indoor(p):
			continue
		if _near_any(p, players, min_player_dist) or _near_any(p, nests, MonsterRules.ROAM_CLEAR_NEST):
			continue
		if keep_spread and _near_home(p, MonsterRules.ROAM_SPREAD):
			continue
		if camera and camera.is_position_in_frustum(p + Vector3.UP):
			continue
		return p
	return Vector3.INF


func _pick_def() -> MonsterDef:
	var pool: Array[MonsterDef] = []
	for def in monster_defs:
		if def == null or def.tier != Enums.MonsterTier.NORMAL or def.move_speed <= 0.0:
			continue
		if region_id != &"" and not def.regions.is_empty() and not def.regions.has(region_id):
			continue
		pool.append(def)
	return pool.pick_random() if not pool.is_empty() else null


## Before the region's polygons reach the map, random points come back as Vector3.ZERO.
func _nav_ready() -> bool:
	var map := get_world_3d().navigation_map
	return NavigationServer3D.map_get_iteration_id(map) > 0 \
			and NavigationServer3D.map_get_random_point(map, navigation_layers, false) != Vector3.ZERO


func _collect_indoor() -> void:
	var root := get_node_or_null(zones_root) if not zones_root.is_empty() else get_parent()
	if root == null:
		return
	for node in root.find_children("*", "Area3D", true, false):
		if not node is IndoorZone:
			continue
		for shape_node in node.find_children("*", "CollisionShape3D", true, false):
			var shape := (shape_node as CollisionShape3D).shape as ConvexPolygonShape3D
			if shape == null:
				continue
			var xform := (shape_node as Node3D).global_transform
			var flat := PackedVector2Array()
			for v in shape.points:
				var g := xform * v
				flat.append(Vector2(g.x, g.z))
			_indoor.append(Geometry2D.convex_hull(flat))


func _is_indoor(p: Vector3) -> bool:
	for outline in _indoor:
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), outline):
			return true
	return false


func _near_any(p: Vector3, nodes: Array, dist: float) -> bool:
	for node in nodes:
		if node is Node3D and _flat_dist(p, (node as Node3D).global_position) < dist:
			return true
	return false


func _near_home(p: Vector3, dist: float) -> bool:
	_prune()
	for m in _alive:
		if _flat_dist(p, m.home) < dist:
			return true
	return false


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Monsters already out when night falls see less and drop more, but do not turn elite.
func _on_night_started() -> void:
	for monster in alive():
		MonsterSpawner.apply_night(monster, false)


func _prune() -> void:
	_alive.assign(_alive.filter(func(m: Variant) -> bool: return is_instance_valid(m) and not m.is_dead()))
