extends Node
## Wall see-through for the field camera (user request 2026-11-06). Wall pieces of the pack
## buildings (buildings.tscn) that stand between the camera and the player, or between the camera and
## an interactable near the player (loot boxes ...), fade to semi-transparent and back.
##
## FieldCamera adds this as a child. Walls are found once by their pack piece name (house walls,
## windows, entrances, inner walls and doors, parapets); their world bounds go into a coarse grid so
## each frame only the walls around the player are tested against the sight lines.
## Without the private assets/ pack (CI) there are no such pieces and this does nothing.

## GeometryInstance3D.transparency for a wall in the way (0 opaque .. 1 invisible).
const SEE_THROUGH := 0.6
## How fast walls fade in and out (per second, exponential).
const FADE_SPEED := 10.0
## Sight line end heights: player chest, interactables slightly above their base.
const PLAYER_HEIGHT := 1.0
const TARGET_HEIGHT := 0.5
## Interactables (physics layer LAYER_INTERACTABLE) within this distance of the player get a clear view.
const TARGET_RADIUS := 8.0
const MAX_TARGETS := 8
## Grid cell size (m) and how many cells around the player are tested.
const CELL := 8.0
const CELL_REACH := 2
## After a scene change, scan for walls this many times, RESCAN_SEC apart (a map may add its
## pack buildings a moment after it loads).
const SCANS_PER_SCENE := 3
const RESCAN_SEC := 1.0
## Pack piece names that count as walls.
const WALL_PIECE := "^house_(a|b|c)_(wall|windows|entrance|interior_wall)|^house_interior_door"

var _cells := {}  # Vector2i -> Array[MeshInstance3D]
var _bounds := {}  # MeshInstance3D -> AABB (world)
var _faded := {}  # MeshInstance3D -> current transparency
var _regex := RegEx.create_from_string(WALL_PIECE)
var _rescan_left := 0.0
var _scans_left := 0
var _scene: Node = null


func _process(delta: float) -> void:
	var camera := get_parent() as Camera3D
	if camera == null:
		return
	var scene := get_tree().current_scene
	if scene != _scene:
		_scene = scene
		_scans_left = SCANS_PER_SCENE
		_rescan_left = 0.0
		_cells.clear()
		_bounds.clear()
	_rescan_left -= delta
	if _scans_left > 0 and _rescan_left <= 0.0:
		_rescan_left = RESCAN_SEC
		_scans_left -= 1
		_scan()
	var player := camera.get(&"target") as Node3D
	var hits := {}
	if player != null and player.is_inside_tree() and not _cells.is_empty():
		var eye := camera.global_position
		var targets: Array[Vector3] = [player.global_position + Vector3.UP * PLAYER_HEIGHT]
		targets.append_array(_interactables(player))
		var center := _cell_of(player.global_position)
		for dx in range(-CELL_REACH, CELL_REACH + 1):
			for dz in range(-CELL_REACH, CELL_REACH + 1):
				for mi: MeshInstance3D in _cells.get(center + Vector2i(dx, dz), []):
					if hits.has(mi) or not is_instance_valid(mi):
						continue
					var box: AABB = _bounds[mi]
					for t in targets:
						if box.intersects_segment(eye, t):
							hits[mi] = true
							break
	var k := 1.0 - exp(-FADE_SPEED * delta)
	for mi: MeshInstance3D in hits:
		_faded[mi] = _faded.get(mi, 0.0)
	for mi: MeshInstance3D in _faded.keys():
		if not is_instance_valid(mi):
			_faded.erase(mi)
			continue
		var want := SEE_THROUGH if hits.has(mi) else 0.0
		var now: float = lerpf(_faded[mi], want, k)
		if want == 0.0 and now < 0.01:
			now = 0.0
		mi.transparency = now
		if now == 0.0 and want == 0.0:
			_faded.erase(mi)
		else:
			_faded[mi] = now


## Interactable bodies near the player (loot containers ...), as sight line end points.
func _interactables(player: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var sphere := SphereShape3D.new()
	sphere.radius = TARGET_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), player.global_position)
	query.collision_mask = 1 << (Enums.LAYER_INTERACTABLE - 1)
	for hit in player.get_world_3d().direct_space_state.intersect_shape(query, MAX_TARGETS):
		var body := hit.collider as Node3D
		if body != null:
			out.append(body.global_position + Vector3.UP * TARGET_HEIGHT)
	return out


## Finds wall meshes in the current scene (already known ones are skipped).
func _scan() -> void:
	for mi: MeshInstance3D in _bounds.keys():
		if not is_instance_valid(mi):
			_bounds.erase(mi)
	var root := get_tree().current_scene
	if root == null:
		return
	var found := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if _bounds.has(mi) or mi.mesh == null or not _is_wall(mi):
			continue
		var box := mi.global_transform * mi.get_aabb()
		_bounds[mi] = box
		found = true
		var a := _cell_of(box.position)
		var b := _cell_of(box.end)
		for x in range(a.x, b.x + 1):
			for z in range(a.y, b.y + 1):
				var key := Vector2i(x, z)
				if not _cells.has(key):
					_cells[key] = []
				(_cells[key] as Array).append(mi)
	if found:
		for key: Vector2i in _cells:
			_cells[key] = (_cells[key] as Array).filter(func(m: Variant) -> bool: return is_instance_valid(m))


## True when the mesh belongs to a pack wall piece (nearest ancestor instanced from a scene file).
func _is_wall(mi: MeshInstance3D) -> bool:
	var n: Node = mi
	while n != null:
		if n.scene_file_path != "":
			return _regex.search(n.scene_file_path.get_file()) != null
		n = n.get_parent()
	return false


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))
