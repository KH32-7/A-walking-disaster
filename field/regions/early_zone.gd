class_name EarlyZone
extends RefCounted
## First days of a region (docs/design/02-field.md "맵 구조" 초반 구역, 사용자 요청 2026-11-07):
## before RegionDef.early_open_day only the map south of RegionDef.early_min_z (world z, m) is open.
## apply() runs from the region scene's _ready: the markers have joined their groups by then (their
## own _ready), and the spawners and managers read the groups later (deferred call or first frame).
## Markers north of the line leave their groups, a wall stands on the line, and FieldState.open_min_z
## tells RoamingSpawner where it may put packs. Hidden routes keep their gates; the wall reaches
## below ground so a tunnel under the line is shut too.

const MARKER_GROUPS: Array[StringName] = [MonsterNest.GROUP, LootSpot.GROUP, RescueSpot.GROUP,
	ExtractPoint.GROUP, VehicleSpot.GROUP, BossArena.GROUP, Recording.GROUP, PlayerSpawn.GROUP]
const WALL_GROUP := &"early_zone_wall"
## Half the wall's length along x (m): past the map bounds (227 m square).
const WALL_HALF_LENGTH := 114.0
const WALL_THICK := 1.5
const WALL_TOP := 4.0
const WALL_BOTTOM := -8.0
## Matte dark vine green (greybox until a vine mesh is made).
const WALL_COLOR := Color("3d4a2f")


## The closed line on `day` (world z), or -INF when the whole map is open.
static func closed_line(def: RegionDef, day: int) -> float:
	if def == null or def.early_min_z == -INF or day >= def.early_open_day:
		return -INF
	return def.early_min_z


## Closes the north of `root`'s map for today. Returns the line (-INF = nothing closed).
static func apply(root: Node3D, def: RegionDef) -> float:
	var z := closed_line(def, GameState.day)
	FieldState.open_min_z = z
	if z == -INF:
		return z
	for group in MARKER_GROUPS:
		for node in root.get_tree().get_nodes_in_group(group):
			if node is Node3D and root.is_ancestor_of(node) and (node as Node3D).global_position.z < z:
				node.remove_from_group(group)
	root.add_child(_wall(z))
	return z


static func _wall(z: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "EarlyZoneWall"
	body.collision_mask = 0
	body.add_to_group(WALL_GROUP)
	body.position = Vector3(0.0, 0.0, z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WALL_HALF_LENGTH * 2.0, WALL_TOP - WALL_BOTTOM, WALL_THICK)
	shape.shape = box
	shape.position.y = (WALL_TOP + WALL_BOTTOM) * 0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(WALL_HALF_LENGTH * 2.0, WALL_TOP, WALL_THICK)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WALL_COLOR
	mat.roughness = 1.0
	bm.material = mat
	mesh.mesh = bm
	mesh.position.y = WALL_TOP * 0.5
	body.add_child(mesh)
	return body
