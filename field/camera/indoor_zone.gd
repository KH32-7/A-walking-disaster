class_name IndoorZone
extends Area3D
## Roof hide hook (B-04). Lane B puts this Area3D (with a CollisionShape3D child covering the
## interior) in a field layout.tscn. While the player is inside, the building's roof is hidden.
## Contract with Lane D (dressing.tscn): put each roof node in group ROOF_GROUP (`field_roof`) and
## give it metadata `building_id` equal to this zone's building_id.
## A roof node may define `set_roof_hidden(hidden: bool)` to fade itself (shader, shadows-only);
## without it the node's `visible` is toggled.

signal player_entered(building_id: StringName)
signal player_exited(building_id: StringName)

const ROOF_GROUP := &"field_roof"
const ROOF_META := &"building_id"

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


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(Player.GROUP):
		set_roofs_hidden(true)
		player_entered.emit(building_id)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group(Player.GROUP):
		set_roofs_hidden(false)
		player_exited.emit(building_id)
