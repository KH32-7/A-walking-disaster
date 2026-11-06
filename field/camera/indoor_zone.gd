class_name IndoorZone
extends Area3D
## Roof hide hook (B-04). Lane B puts this Area3D (with a CollisionShape3D child covering the
## interior) in a field layout.tscn. While the player is inside, the building's roof is hidden.
## Contract with Lane D (dressing.tscn): put each roof node in group ROOF_GROUP (`field_roof`) and
## give it metadata `building_id` equal to this zone's building_id.
## A roof node may define `set_roof_hidden(hidden: bool)` to fade itself (shader, shadows-only);
## without it the node's `visible` is toggled.
## Things on an upper floor that are not under a roof node (loot containers, spawned at runtime) join
## group ABOVE_GROUP: they hide with the roofs when they stand over this zone, above its ceiling
## (user report 2026-11-06: the mall's 2F cabinets floated over the 1F).

signal player_entered(building_id: StringName)
signal player_exited(building_id: StringName)

const ROOF_GROUP := &"field_roof"
const ROOF_META := &"building_id"
const ABOVE_GROUP := &"field_hide_above_roof"
## A node counts as above the ceiling from this far below the zone's top (m).
const ABOVE_MARGIN := 0.5

@export var building_id: StringName


func _ready() -> void:
	collision_layer = 1 << (Enums.LAYER_TRIGGER - 1)
	collision_mask = 1 << (Enums.LAYER_PLAYER - 1)
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Hides (true) or shows (false) every roof node tagged with this zone's building_id.
func set_roofs_hidden(hidden: bool) -> void:
	for node in get_tree().get_nodes_in_group(ROOF_GROUP):
		if node.get_meta(ROOF_META, &"") != building_id:
			continue
		if node.has_method(&"set_roof_hidden"):
			node.set_roof_hidden(hidden)
		elif node is Node3D:
			node.visible = not hidden
	for node in get_tree().get_nodes_in_group(ABOVE_GROUP):
		if node is Node3D and _is_above(node.global_position):
			node.visible = not hidden


## p stands over this zone's floor plan, at or above its ceiling.
func _is_above(p: Vector3) -> bool:
	for cs in find_children("*", "CollisionShape3D", true, false):
		var shape := (cs as CollisionShape3D).shape as ConvexPolygonShape3D
		if shape == null:
			continue
		var xform := (cs as Node3D).global_transform
		var flat := PackedVector2Array()
		var top := -INF
		for v in shape.points:
			var g := xform * v
			flat.append(Vector2(g.x, g.z))
			top = maxf(top, g.y)
		if p.y >= top - ABOVE_MARGIN and Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), Geometry2D.convex_hull(flat)):
			return true
	return false


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(Player.GROUP):
		set_roofs_hidden(true)
		player_entered.emit(building_id)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group(Player.GROUP):
		set_roofs_hidden(false)
		player_exited.emit(building_id)
