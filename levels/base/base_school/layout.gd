extends Node3D
## Base map layout (C-09): collision, navigation, markers. Owner: Lane C.
## The base is a clearing in a park forest (design 09 "기지 지도"): 공터 front_yard (built on from
## day 1), the 방송실 camp main_hall south of it, and three forest zones to clear (서 park_a, 북 park_b,
## 동 연못가 gate_market). ForestEdge walls keep people in, with a gap toward every raid spawn.
## Water bodies (lake, pond) are StaticBody3D with metadata "radii"; their collision is an
## elliptic prism made here, and dressing.tscn (forest, water meshes) reads the same nodes.
## The navigation mesh is baked when the layout enters the tree (greybox changes often, so nothing
## baked is stored in the scene). Listen to `navigation_ready` before asking for paths.
## Ref: docs/design/09-base-building.md "구역과 개간", docs/dev/contracts.md "맵 파일과 마커".

signal navigation_ready

const WATER_SEGMENTS := 24
const WATER_HEIGHT := 2.0

## Frames to wait for the NavigationServer map to pick up the new mesh before giving up.
const MAP_SYNC_MAX_FRAMES := 120
## The mesh is baked from CSG collision shapes, which CSG creates a few frames after entering the
## tree (later when the scene is loaded mid-game by SceneRouter). An empty result is retried.
const BAKE_RETRIES := 10
const BAKE_RETRY_FRAMES := 3

@onready var _navigation: NavigationRegion3D = $Navigation

## True once the mesh is baked AND the navigation map uses it (paths work).
var navigation_baked := false

var _attempts := 0


func _ready() -> void:
	# Every loaded copy of this scene shares the NavigationMesh sub-resource. Bake into our own
	# copy, or a second base instance (re-entering the base, tests) finds it "already baking".
	_navigation.navigation_mesh = _navigation.navigation_mesh.duplicate()
	_navigation.bake_finished.connect(_on_bake_finished)
	_build_water_collision()
	# CSG builds its shapes at the end of the frame; bake after that.
	await get_tree().process_frame
	await get_tree().physics_frame
	_navigation.bake_navigation_mesh(true)


func _on_bake_finished() -> void:
	_attempts += 1
	if _navigation.navigation_mesh.get_polygon_count() == 0 and _attempts < BAKE_RETRIES:
		for i in BAKE_RETRY_FRAMES:
			await get_tree().physics_frame
		_navigation.bake_navigation_mesh(true)
		return
	if _navigation.navigation_mesh.get_polygon_count() == 0:
		push_error("base layout: navigation mesh is still empty after %d bakes" % _attempts)
	# The region's new mesh reaches the map on a later physics step (map iteration changes).
	var map := _navigation.get_navigation_map()
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	for i in MAP_SYNC_MAX_FRAMES:
		if NavigationServer3D.map_get_iteration_id(map) != iteration:
			break
		await get_tree().physics_frame
	navigation_baked = true
	navigation_ready.emit()


## Elliptic prism collision for every Water/<body> (blocks walking and the navmesh).
func _build_water_collision() -> void:
	var water := _navigation.get_node_or_null(^"Water")
	if water == null:
		return
	for body in water.get_children():
		if not (body is StaticBody3D and body.has_meta(&"radii")):
			continue
		var radii: Vector2 = body.get_meta(&"radii")
		var points := PackedVector3Array()
		for k in WATER_SEGMENTS:
			var a := k * TAU / WATER_SEGMENTS
			var p := Vector3(cos(a) * radii.x, 0.0, sin(a) * radii.y)
			points.append(p)
			points.append(p + Vector3.UP * WATER_HEIGHT)
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var col := CollisionShape3D.new()
		col.name = "Shape"
		col.shape = shape
		body.add_child(col)
